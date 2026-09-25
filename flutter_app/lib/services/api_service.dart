/// API service: signs and POSTs payloads to FastAPI endpoints (SMS, Chat, Receipt Scan).
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
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
          .timeout(const Duration(seconds: 4));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] == 'error' && data['message'] != null && (data['message'] as String).contains('Failed to connect')) {
        return await _fallbackDirectCloudChat(message, householdId);
      }
      return data;
    } on Exception catch (_) {
      // Local backend server unreachable (e.g. laptop is turned OFF or phone is on cellular data away from home)
      return await _fallbackDirectCloudChat(message, householdId);
    }
  }

  Future<Map<String, dynamic>> _fallbackDirectCloudChat(String message, String householdId) async {
    final lower = message.toLowerCase();

    // Attribution
    String spentBy = 'me';
    if (lower.contains('partner') || lower.contains('wife') || lower.contains('husband')) {
      spentBy = 'partner';
    } else if (lower.contains('cleaning') || lower.contains('grocer') || lower.contains('supermarket') || lower.contains('utilities') || lower.contains('both') || lower.contains('we ')) {
      spentBy = 'both';
    }

    // Merchant
    String merchant = 'Unknown Merchant';
    final known = [
      'Dunkin', 'Starbucks', 'Albaik', "McDonald's", 'Danube', 'Tamimi', 'Panda', 'Carrefour',
      'Nahdi', 'Al Dawaa', 'Jarir', 'Extra', 'Noon', 'Amazon', 'Aramco', 'Sahel', 'Uber', 'Careem', 'House Cleaning'
    ];
    for (final k in known) {
      if (lower.contains(k.toLowerCase())) {
        merchant = k;
        break;
      }
    }
    if (merchant == 'Unknown Merchant') {
      final mMatch = RegExp(r"(?:merchant|at|from)\s+([A-Za-z0-9'&]+)", caseSensitive: false).firstMatch(message);
      if (mMatch != null) {
        merchant = mMatch.group(1)!;
      } else {
        final words = message.split(' ');
        if (words.isNotEmpty) merchant = words.first;
      }
    }

    // Total Amount
    double totalAmount = 0.0;
    final totMatch = RegExp(r'(?:spent|total|for)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:sar|riyal|rs)?\s*(?:total)?', caseSensitive: false).firstMatch(message);
    if (totMatch != null) {
      totalAmount = double.tryParse(totMatch.group(1)!) ?? 0.0;
    }

    // Line items
    final items = <Map<String, dynamic>>[];
    final itemRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:sar)?\s+([a-zA-Z\s]+?)(?:and|,|$)', caseSensitive: false);
    for (final m in itemRegex.allMatches(message)) {
      final val = double.tryParse(m.group(1)!) ?? 0.0;
      final name = m.group(2)!.trim();
      if (name.toLowerCase() == merchant.toLowerCase() || name.toLowerCase().contains('total') || name.toLowerCase().contains('spent')) {
        continue;
      }
      if (val > 0 && name.length > 1) {
        items.add({'name': name, 'quantity': 1.0, 'price': val});
      }
    }

    if (items.isNotEmpty) {
      final sum = items.fold<double>(0.0, (acc, it) => acc + ((it['price'] as num?)?.toDouble() ?? 0.0));
      if (totalAmount == 0.0 || totalAmount < sum) {
        totalAmount = sum;
      }
    } else if (totalAmount > 0) {
      items.add({'name': merchant, 'quantity': 1.0, 'price': totalAmount});
    }

    // Category
    String categoryCode = 'OPEX-MISC';
    if (lower.contains('dunkin') || lower.contains('coffee') || lower.contains('cafe') || lower.contains('dining') || lower.contains('latte') || lower.contains('albaik')) {
      categoryCode = 'OPEX-DINING';
    } else if (lower.contains('danube') || lower.contains('tamimi') || lower.contains('panda') || lower.contains('grocer') || lower.contains('supermarket')) {
      categoryCode = 'OPEX-GROCERY';
    } else if (lower.contains('fuel') || lower.contains('gas') || lower.contains('uber') || lower.contains('careem')) {
      categoryCode = 'OPEX-FUEL';
    } else if (lower.contains('bill') || lower.contains('stc') || lower.contains('electric') || lower.contains('utilities')) {
      categoryCode = 'OPEX-UTILITIES';
    } else if (lower.contains('jarir') || lower.contains('amazon') || lower.contains('extra') || lower.contains('shopping')) {
      categoryCode = 'OPEX-SHOPPING';
    } else if (lower.contains('nahdi') || lower.contains('pharmacy') || lower.contains('medicine')) {
      categoryCode = 'OPEX-HEALTH';
    }

    final itemsSummary = items.map((it) => '${(it['quantity'] as num).toDouble()}x ${it['name']} (${it['price']} SAR)').join(', ');
    final auditText = itemsSummary.isNotEmpty ? 'Chat: $message | SpentBy: $spentBy | Items: [$itemsSummary]' : 'Chat: $message | SpentBy: $spentBy';

    try {
      final insertData = <String, dynamic>{
        'household_id': householdId,
        'amount': totalAmount,
        'currency': 'SAR',
        'merchant': merchant,
        'category_code': categoryCode,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'raw_sms': auditText,
        'source': 'chat',
        'items': items,
      };

      try {
        await supabase.from('transactions').insert({
          ...insertData,
          'spent_by': spentBy,
        });
      } catch (_) {
        await supabase.from('transactions').insert(insertData);
      }

      return {
        'status': 'success',
        'merchant': merchant,
        'amount': totalAmount,
        'category_code': categoryCode,
        'spent_by': spentBy,
        'items': items,
        'is_reallocated': false,
        'message': 'Recorded SAR ${totalAmount.toStringAsFixed(2)} at $merchant (Direct Cloud Sync).',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Cloud sync failed: $e'};
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
