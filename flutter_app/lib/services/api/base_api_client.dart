import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_config.dart';

typedef AuthTokenProvider = String? Function();

class BaseApiClient {
  static const String appAuthToken = String.fromEnvironment('APP_AUTH_TOKEN');
  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;

  BaseApiClient({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider;

  String? get _currentAccessToken {
    if (_authTokenProvider != null) {
      return _authTokenProvider();
    }
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
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

  Map<String, String> buildHeaders({String? signature}) {
    final token = _currentAccessToken;
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (appAuthToken.isNotEmpty) 'X-App-Token': appAuthToken,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (signature != null) 'X-Signature': signature,
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

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool shouldSign = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final payload = jsonEncode(body);
    final signature = (shouldSign && webhookSecret.isNotEmpty) ? sign(payload) : null;
    final url = path.startsWith('http') ? Uri.parse(path) : Uri.parse('$baseUrl$path');

    try {
      final response = await _client
          .post(url, headers: buildHeaders(signature: signature), body: payload)
          .timeout(timeout);
      if (response.statusCode >= 400) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
        return {
          'status': 'error',
          'status_code': response.statusCode,
          'message': response.statusCode == 502
              ? 'AI backend is waking up (cold start) or temporarily unavailable. Please retry in 15 seconds.'
              : 'Server response error (${response.statusCode})',
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())));
    }

    try {
      final response = await _client.get(uri, headers: buildHeaders()).timeout(timeout);
      if (response.statusCode >= 400) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
        return {
          'status': 'error',
          'status_code': response.statusCode,
          'message': response.statusCode == 502
              ? 'AI backend is waking up (cold start) or temporarily unavailable. Please retry in 15 seconds.'
              : 'Server response error (${response.statusCode})',
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool shouldSign = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final encoded = jsonEncode(body ?? {});
    final signature = (shouldSign && webhookSecret.isNotEmpty) ? sign(encoded) : null;
    try {
      final response = await _client
          .put(
            Uri.parse(path.startsWith('http') ? path : '$baseUrl$path'),
            headers: buildHeaders(signature: signature),
            body: encoded,
          )
          .timeout(timeout);
      if (response.statusCode >= 400) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
        return {
          'status': 'error',
          'status_code': response.statusCode,
          'message': 'Server response error (${response.statusCode})',
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParams,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())));
    }

    try {
      final response = await _client.delete(uri, headers: buildHeaders()).timeout(timeout);
      if (response.statusCode >= 400) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
        return {
          'status': 'error',
          'status_code': response.statusCode,
          'message': 'Server response error (${response.statusCode})',
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
