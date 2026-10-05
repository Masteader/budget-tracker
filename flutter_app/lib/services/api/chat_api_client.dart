import 'base_api_client.dart';

class ChatApiClient {
  final BaseApiClient baseClient;

  ChatApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
    String? merchant,
    String? spentBy,
  }) async {
    final payload = <String, dynamic>{
      'message': message,
      'household_id': householdId,
      'allow_duplicate': allowDuplicate,
      'preview_only': previewOnly,
      if (userId != null) 'user_id': userId,
      if (enrichTxId != null) 'enrich_tx_id': enrichTxId,
      if (merchant != null && merchant.trim().isNotEmpty) 'merchant': merchant.trim(),
      if (spentBy != null && spentBy.trim().isNotEmpty) 'spent_by': spentBy.trim(),
    };

    final res = await baseClient.post('/agent/chat-transaction', payload, shouldSign: true);
    if (res['status'] == 'error' && (res['message'] as String? ?? '').contains('Failed to connect')) {
      return fallbackDirectCloudChat(message, householdId);
    }
    return res;
  }

  Future<Map<String, dynamic>> simulatePurchase({
    required String message,
    required String householdId,
    double? customAmount,
    String? customCategory,
  }) async {
    return baseClient.post(
      '/agent/simulate-purchase',
      {
        'message': message,
        'household_id': householdId,
        if (customAmount != null) 'amount': customAmount,
        if (customCategory != null) 'category_code': customCategory,
      },
      shouldSign: true,
    );
  }

  Map<String, dynamic> fallbackDirectCloudChat(String message, String householdId) {
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
      items.add({'name': '$merchant Order', 'quantity': 1.0, 'price': totalAmount});
    }

    // Category mapping
    String category = 'OPEX-MISC';
    if (lower.contains('coffee') || lower.contains('cafe') || lower.contains('dunkin') || lower.contains('starbucks') || lower.contains('food') || lower.contains('restaurant') || lower.contains('albaik') || lower.contains('burger')) {
      category = 'OPEX-FOOD';
    } else if (lower.contains('grocer') || lower.contains('supermarket') || lower.contains('tamimi') || lower.contains('panda') || lower.contains('danube') || lower.contains('carrefour') || lower.contains('milk') || lower.contains('bread')) {
      category = 'OPEX-GROCERY';
    } else if (lower.contains('pharmacy') || lower.contains('medicine') || lower.contains('nahdi') || lower.contains('dawaa')) {
      category = 'OPEX-HEALTH';
    } else if (lower.contains('fuel') || lower.contains('gas') || lower.contains('petrol') || lower.contains('uber') || lower.contains('careem') || lower.contains('taxi')) {
      category = 'OPEX-TRANSPORT';
    } else if (lower.contains('clean') || lower.contains('maid') || lower.contains('electricity') || lower.contains('water') || lower.contains('rent')) {
      category = 'OPEX-HOUSEHOLD';
    }

    return {
      'status': 'preview',
      'merchant': merchant,
      'amount': totalAmount,
      'category_code': category,
      'spent_by': spentBy,
      'items': items,
      'message': 'Parsed offline: SAR $totalAmount at $merchant ($category).',
    };
  }
}
