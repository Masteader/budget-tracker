import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';
import '../../supabase_config.dart';

class BaseApiClient {
  static const String appAuthToken = 'bt_sec_99a81f3d4c72e01b88e2';

  String get baseUrl {
    if (fastapiBaseUrl.isNotEmpty) {
      return fastapiBaseUrl;
    }
    if (fastapiWebhookUrl.endsWith('/webhook/sms')) {
      return fastapiWebhookUrl.substring(0, fastapiWebhookUrl.length - '/webhook/sms'.length);
    }
    return fastapiWebhookUrl;
  }

  Map<String, String> buildHeaders({String? signature}) {
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'X-App-Token': appAuthToken,
      if (signature != null) 'X-Signature': signature,
    };
  }

  String sign(String body) {
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
    final signature = shouldSign ? sign(payload) : null;
    final url = path.startsWith('http') ? Uri.parse(path) : Uri.parse('$baseUrl$path');

    try {
      final response = await http
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
      final response = await http.get(uri, headers: buildHeaders()).timeout(timeout);
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
    final signature = shouldSign ? sign(encoded) : null;
    try {
      final response = await http
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
}


