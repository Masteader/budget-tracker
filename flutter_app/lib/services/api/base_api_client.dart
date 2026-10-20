import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_config.dart';

typedef AuthTokenProvider = String? Function();
typedef SessionRefresher = Future<String?> Function();

/// Shared HTTP client for the FastAPI backend.
///
/// Authentication is the caller's own Supabase JWT (`Authorization: Bearer`).
/// No static app token is sent: a token compiled into the APK can be
/// extracted by anyone and would let them bypass the backend firewall.
/// POST bodies (and PUTs with `shouldSign`) carry an `X-Signature` HMAC only
/// when a WEBHOOK_SECRET was supplied at build time; it is optional defense in
/// depth, never the credential.
///
/// Every request:
/// * refreshes the Supabase session first when the access token has expired
///   (the app may have been offline/backgrounded for longer than the 1 h JWT
///   lifetime), and
/// * on an auth rejection (401, or the firewall's 403 for an unverifiable
///   bearer token) refreshes once and replays the identical request.
///
/// Error responses are always normalised to a map containing
/// `status: 'error'`, `status_code` and a human readable `message`.
class BaseApiClient {
  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;
  final SessionRefresher? _sessionRefresher;
  final String _signingSecret;
  String? _overriddenAccessToken;

  /// [signingSecret] defaults to the optional `--dart-define=WEBHOOK_SECRET`;
  /// an empty secret means requests are not signed.
  BaseApiClient({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
    SessionRefresher? sessionRefresher,
    String? signingSecret,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider,
        _sessionRefresher = sessionRefresher,
        _signingSecret = signingSecret ?? webhookSecret;

  String? get _currentAccessToken {
    if (_overriddenAccessToken != null) {
      return _overriddenAccessToken;
    }
    if (_authTokenProvider != null) {
      return _authTokenProvider();
    }
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Returns true when the live Supabase session's access token is expired.
  bool get _liveSessionExpired {
    if (_authTokenProvider != null || _sessionRefresher != null) return false;
    try {
      return Supabase.instance.client.auth.currentSession?.isExpired ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _refreshAccessToken() async {
    if (_sessionRefresher != null) {
      final newToken = await _sessionRefresher();
      if (newToken != null && newToken.isNotEmpty) {
        _overriddenAccessToken = newToken;
      }
      return newToken;
    }
    try {
      final res = await Supabase.instance.client.auth.refreshSession();
      return res.session?.accessToken;
    } catch (_) {
      return null;
    }
  }

  String get baseUrl {
    if (fastapiBaseUrl.isNotEmpty) {
      return fastapiBaseUrl;
    }
    return fastapiWebhookUrl;
  }

  Map<String, String> buildHeaders({String? signature, Map<String, String>? extraHeaders}) {
    final token = _currentAccessToken;
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (signature != null) 'X-Signature': signature,
      ...?extraHeaders,
    };
  }

  String sign(String body) {
    if (_signingSecret.isEmpty) {
      return '';
    }
    final key = utf8.encode(_signingSecret);
    final bytes = utf8.encode(body);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return 'sha256=${digest.toString()}';
  }

  Uri _resolve(String path, [Map<String, dynamic>? queryParams]) {
    var uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())));
    }
    return uri;
  }

  static bool _isAuthRejection(http.Response response) {
    if (response.statusCode == 401) return true;
    // The FastAPI firewall answers 403 (not 401) when the bearer token cannot
    // be verified, e.g. because it expired while the device was offline.
    return response.statusCode == 403 && response.body.contains('Untrusted endpoint access');
  }

  /// Sends one request with the caller's JWT: refreshes the session first when
  /// it has expired, and once more (replaying the request) on an auth rejection.
  Future<http.Response> _sendAuthenticated(
    String method,
    Uri uri, {
    String? body,
    String? signature,
    Map<String, String>? extraHeaders,
    required Duration timeout,
  }) async {
    Future<http.Response> attempt() {
      final request = http.Request(method, uri)
        ..headers.addAll(buildHeaders(signature: signature, extraHeaders: extraHeaders));
      if (body != null) request.body = body;
      return _client.send(request).then(http.Response.fromStream).timeout(timeout);
    }

    if (_liveSessionExpired) {
      await _refreshAccessToken();
    }

    var response = await attempt();

    if (_isAuthRejection(response)) {
      final refreshedToken = await _refreshAccessToken();
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        response = await attempt();
      }
    }
    return response;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    String? body,
    String? signature,
    Map<String, String>? extraHeaders,
    required Duration timeout,
  }) async {
    try {
      final response = await _sendAuthenticated(
        method,
        uri,
        body: body,
        signature: signature,
        extraHeaders: extraHeaders,
        timeout: timeout,
      );

      if (response.statusCode >= 400) {
        return _errorResponse(response);
      }
      if (response.body.trim().isEmpty) {
        return {'status': 'success'};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'status': 'success', 'data': decoded};
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Downloads a binary resource (e.g. the statement PDF) with the same JWT
  /// authentication, refresh and replay as the JSON calls. A bare URL opened
  /// in a browser carries no `Authorization` header and is rejected by the
  /// backend firewall (MOB-26).
  ///
  /// Throws [ApiDownloadException] on an HTTP error, a network failure or a
  /// timeout; an error body is never returned as if it were the file.
  Future<ApiBinaryResponse> getBinary(
    String path, {
    Map<String, dynamic>? queryParams,
    String? accept,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final http.Response response;
    try {
      response = await _sendAuthenticated(
        'GET',
        _resolve(path, queryParams),
        extraHeaders: accept != null ? {'Accept': accept} : null,
        timeout: timeout,
      );
    } on Exception catch (e) {
      throw ApiDownloadException(e.toString());
    }
    if (response.statusCode >= 400) {
      final error = _errorResponse(response);
      throw ApiDownloadException(error['message'] as String, statusCode: response.statusCode);
    }
    return ApiBinaryResponse(
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'],
      contentDisposition: response.headers['content-disposition'],
    );
  }

  static Map<String, dynamic> _errorResponse(http.Response response) {
    final code = response.statusCode;
    Map<String, dynamic> decoded = const {};
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {}

    final detail = decoded['message'] ?? decoded['detail'];
    final String message;
    if (detail is String && detail.isNotEmpty) {
      message = detail;
    } else if (code == 502) {
      message = 'AI backend is waking up (cold start) or temporarily unavailable. Please retry in 15 seconds.';
    } else {
      message = 'Server response error ($code)';
    }
    return {
      ...decoded,
      'status': 'error',
      'status_code': code,
      'message': message,
    };
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool shouldSign = true,
    Duration timeout = const Duration(seconds: 20),
    Map<String, String>? extraHeaders,
  }) {
    final payload = jsonEncode(body);
    final signature = (shouldSign && _signingSecret.isNotEmpty) ? sign(payload) : null;
    return _send(
      'POST',
      _resolve(path),
      body: payload,
      signature: signature,
      extraHeaders: extraHeaders,
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _send('GET', _resolve(path, queryParams), timeout: timeout);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool shouldSign = false,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final encoded = jsonEncode(body ?? {});
    final signature = (shouldSign && _signingSecret.isNotEmpty) ? sign(encoded) : null;
    return _send('PUT', _resolve(path), body: encoded, signature: signature, timeout: timeout);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _send('PATCH', _resolve(path), body: jsonEncode(body ?? {}), timeout: timeout);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParams,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _send('DELETE', _resolve(path, queryParams), timeout: timeout);
  }
}

/// A successful binary download.
class ApiBinaryResponse {
  const ApiBinaryResponse({required this.bytes, this.contentType, this.contentDisposition});

  final Uint8List bytes;
  final String? contentType;
  final String? contentDisposition;

  /// File name from `Content-Disposition: attachment; filename="..."`, if any.
  String? get fileName {
    final header = contentDisposition;
    if (header == null) return null;
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(header);
    return match?.group(1)?.trim();
  }
}

/// A failed binary download. [statusCode] is null for network errors.
class ApiDownloadException implements Exception {
  const ApiDownloadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null ? message : '$message ($statusCode)';
}
