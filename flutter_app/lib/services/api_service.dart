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

  static const String appAuthToken = 'bt_sec_99a81f3d4c72e01b88e2';

  Map<String, String> _buildHeaders({String? signature}) {
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'X-App-Token': appAuthToken,
      if (signature != null) 'X-Signature': signature,
    };
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
            headers: _buildHeaders(signature: signature),
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
            headers: _buildHeaders(signature: signature),
            body: payload,
          )
          .timeout(const Duration(seconds: 20));

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
      final baseData = <String, dynamic>{
        'household_id': householdId,
        'amount': totalAmount,
        'currency': 'SAR',
        'merchant': merchant,
        'category_code': categoryCode,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'raw_sms': auditText,
      };

      try {
        // Try modern schema with items, spent_by, source
        await supabase.from('transactions').insert({
          ...baseData,
          'source': 'chat',
          'items': items,
          'spent_by': spentBy,
        });
      } catch (colErr) {
        // If items or spent_by columns don't exist yet in Supabase schema cache
        try {
          await supabase.from('transactions').insert({
            ...baseData,
            'source': 'chat',
          });
        } catch (_) {
          // Fallback to strict base table columns
          await supabase.from('transactions').insert(baseData);
        }
      }

      return {
        'status': 'success',
        'merchant': merchant,
        'amount': totalAmount,
        'category_code': categoryCode,
        'spent_by': spentBy,
        'items': items,
        'is_reallocated': false,
        'message': 'Recorded SAR ${totalAmount.toStringAsFixed(2)} at $merchant.',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Cloud sync failed: $e'};
    }
  }

  // ── POST /agent/scan-receipt ──────────────────────────────────────────────

  Future<Map<String, dynamic>> scanReceipt({
    List<String>? imagesBase64,
    String? imageBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
  }) async {
    final list = imagesBase64 ?? (imageBase64 != null ? [imageBase64] : <String>[]);
    final payload = jsonEncode({
      'images_base64': list,
      if (list.isNotEmpty) 'image_base64': list.first,
      if (qrCodeRaw != null && qrCodeRaw.trim().isNotEmpty) 'qr_code_raw': qrCodeRaw.trim(),
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
            headers: _buildHeaders(signature: signature),
            body: payload,
          )
          .timeout(const Duration(seconds: 45));

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        return {
          'status': 'error',
          'message': decoded['detail']?.toString() ?? decoded['message']?.toString() ?? 'Server error (${response.statusCode})',
        };
      }
      return decoded;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── GET /budgets/salary-cycle-forecast ──────────────────────────────────

  Future<Map<String, dynamic>> getSalaryCycleForecast(String householdId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/budgets/salary-cycle-forecast?household_id=$householdId'),
            headers: _buildHeaders(),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── POST /budgets/simulate-affordability ─────────────────────────────────

  Future<Map<String, dynamic>> simulateAffordability({
    required String householdId,
    required double targetAmount,
    String itemName = 'Item',
    String? categoryCode,
  }) async {
    final payload = jsonEncode({
      'household_id': householdId,
      'target_amount': targetAmount,
      'item_name': itemName,
      if (categoryCode != null) 'category_code': categoryCode,
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/budgets/simulate-affordability'),
            headers: _buildHeaders(),
            body: payload,
          )
          .timeout(const Duration(seconds: 8));

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── GET /households/{household_id}/settlement ───────────────────────────

  Future<Map<String, dynamic>> getPartnerSettlement(String householdId, {double splitRatio = 0.50}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/households/$householdId/settlement?split_ratio=$splitRatio'),
            headers: _buildHeaders(),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── GET /analytics/price-history ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getGroceryPriceHistory(String householdId, {String? itemFilter}) async {
    try {
      final uri = Uri.parse('$_baseUrl/analytics/price-history')
          .replace(queryParameters: {
        'household_id': householdId,
        if (itemFilter != null && itemFilter.isNotEmpty) 'item_filter': itemFilter,
      });

      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ── GET /budgets/cycles ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSalaryCycles(String householdId) async {
    try {
      final uri = Uri.parse('$_baseUrl/budgets/cycles?household_id=$householdId');
      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── GET /budgets/breakdown ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getBudgetBreakdown(
    String householdId, {
    String? cycleKey,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/budgets/breakdown').replace(queryParameters: {
        'household_id': householdId,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      });
      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── POST /budgets/categories ──────────────────────────────────────────────

  Future<Map<String, dynamic>> addBudgetCategory({
    required String householdId,
    required String code,
    required String category,
    required double allocatedAmount,
    bool isFlexible = true,
    List<String> keywords = const [],
  }) async {
    final payload = jsonEncode({
      'household_id': householdId,
      'code': code,
      'category': category,
      'allocated_amount': allocatedAmount,
      'is_flexible': isFlexible,
      'keywords': keywords,
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/budgets/categories'),
            headers: _buildHeaders(),
            body: payload,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── DELETE /budgets/categories/{code} ─────────────────────────────────────

  Future<Map<String, dynamic>> archiveBudgetCategory(
    String householdId,
    String categoryCode,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/budgets/categories/$categoryCode?household_id=$householdId');
      final response = await http
          .delete(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── POST /budgets/sub-allocations ─────────────────────────────────────────

  Future<Map<String, dynamic>> saveSubAllocations({
    required String householdId,
    required String categoryCode,
    required Map<String, double> subAllocations,
    String? cycleKey,
  }) async {
    final payload = jsonEncode({
      'household_id': householdId,
      'category_code': categoryCode,
      'sub_allocations': subAllocations,
      if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/budgets/sub-allocations'),
            headers: _buildHeaders(),
            body: payload,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}: ${response.body}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ── POST /budgets/sub-categories ──────────────────────────────────────────

  Future<Map<String, dynamic>> addSubCategory({
    required String householdId,
    required String parentCode,
    required String nameEn,
    required double allocatedAmount,
    String? subCode,
    String? cycleKey,
  }) async {
    final payload = jsonEncode({
      'household_id': householdId,
      'parent_code': parentCode,
      'name_en': nameEn,
      'allocated_amount': allocatedAmount,
      if (subCode != null && subCode.isNotEmpty) 'sub_code': subCode,
      if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/budgets/sub-categories'),
            headers: _buildHeaders(),
            body: payload,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}: ${response.body}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}



