/// API service: signs and POSTs payloads to FastAPI endpoints (SMS, Chat, Receipt Scan).
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../supabase_config.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String get _baseUrl {
    if (fastapiWebhookUrl.endsWith('/webhook/sms')) {
      return fastapiWebhookUrl.substring(0, fastapiWebhookUrl.length - '/webhook/sms'.length);
    }
    return fastapiWebhookUrl;
  }

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
            Uri.parse(fastapiWebhookUrl),
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

  // ── POST /agent/chat-transaction ──────────────────────────────────────────

  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
  }) async {
    final payload = jsonEncode({
      'message': message,
      'household_id': householdId,
      if (userId != null) 'user_id': userId,
      'allow_duplicate': allowDuplicate,
      if (enrichTxId != null) 'enrich_tx_id': enrichTxId,
    });

    final signature = _sign(payload);

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/agent/chat-transaction'),
            headers: {
              'Content-Type': 'application/json',
              'X-Signature': signature,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 30));

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── POST /agent/scan-receipt ──────────────────────────────────────────────

  Future<Map<String, dynamic>> scanReceipt({
    required String imageBase64,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
  }) async {
    final payload = jsonEncode({
      'image_base64': imageBase64,
      'household_id': householdId,
      if (userId != null) 'user_id': userId,
      'allow_duplicate': allowDuplicate,
      if (enrichTxId != null) 'enrich_tx_id': enrichTxId,
    });

    final signature = _sign(payload);

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/agent/scan-receipt'),
            headers: {
              'Content-Type': 'application/json',
              'X-Signature': signature,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 45));

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
