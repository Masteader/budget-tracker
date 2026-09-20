/// API service: signs and POSTs SMS payloads to the FastAPI webhook.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../supabase_config.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // ── HMAC-SHA256 signature ────────────────────────────────────────────────

  String _sign(String body) {
    final key = utf8.encode(webhookSecret);
    final bytes = utf8.encode(body);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return 'sha256=${digest.toString()}';
  }

  // ── POST /webhook/sms ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> postSms({
    required String rawSms,
    required String sender,
    required String receivedAt,
    required String householdId,
    String? deviceId,
  }) async {
    final payload = jsonEncode({
      'raw_sms': rawSms,
      'sender': sender,
      'received_at': receivedAt,
      'household_id': householdId,
      if (deviceId != null) 'device_id': deviceId,
    });

    final signature = _sign(payload);

    try {
      final response = await http
          .post(
            Uri.parse('$fastapiWebhookUrl'),
            headers: {
              'Content-Type': 'application/json',
              'X-Signature': signature,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 15));

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
