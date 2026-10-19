import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_config.dart';

typedef AuthTokenProvider = String? Function();
typedef SessionRefresher = Future<String?> Function();

/// Shared HTTP client for the FastAPI backend.
///
/// Authentication is the caller's own Supabase JWT (`Authorization: Bearer`).
/// No static shared secret is sent: a token compiled into the APK can be
/// extracted by anyone and would let them bypass the backend firewall.
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
  String? _overriddenAccessToken;

  BaseApiClient({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
    SessionRefresher? sessionRefresher,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider,
        _sessionRefresher = sessionRefresher;

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
    if (webhookSecret.isEmpty) {
      return '';
    }
    final key = utf8.encode(webhookSecret);
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

  Future<Map<String, dynamic>> _send(
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

    try {
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
    final signature = (shouldSign && webhookSecret.isNotEmpty) ? sign(payload) : null;
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
    final signature = (shouldSign && webhookSecret.isNotEmpty) ? sign(encoded) : null;
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
