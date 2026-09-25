/// Data models for the Budget Tracker app.
library;

// ── Transaction ──────────────────────────────────────────────────────────────

class Transaction {
  final String id;
  final String householdId;
  final double amount;
  final String currency;
  final String? merchant;
  final String? categoryCode;
  final DateTime timestamp;
  final bool isReallocated;
  final String? reallocatedFromBudgetId;
  final DateTime createdAt;
  final String source;
  final String spentBy; // 'me' | 'partner' | 'both'
  final List<Map<String, dynamic>> items;
  final String? receiptUrl;
  final String? dedupFingerprint;
  final String? rawSms;

  const Transaction({
    required this.id,
    required this.householdId,
    required this.amount,
    required this.currency,
    this.merchant,
    this.categoryCode,
    required this.timestamp,
    required this.isReallocated,
    this.reallocatedFromBudgetId,
    required this.createdAt,
    this.source = 'sms',
    this.spentBy = 'both',
    this.items = const [],
    this.receiptUrl,
    this.dedupFingerprint,
    this.rawSms,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> parsedItems = [];
    if (map['items'] != null && map['items'] is List) {
      parsedItems = (map['items'] as List)
          .map((item) => item is Map<String, dynamic>
              ? item
              : Map<String, dynamic>.from(item as Map))
          .toList();
    }

    final raw = map['raw_sms'] as String? ?? '';

    // Fallback: parse itemized breakdown from audit raw_sms if items column is empty
    if (parsedItems.isEmpty && raw.contains('Items: [')) {
      final start = raw.lastIndexOf('Items: [');
      final end = raw.indexOf(']', start);
      if (start != -1 && end != -1) {
        final content = raw.substring(start + 8, end);
        final itemRegex = RegExp(
          r'(\d+(?:\.\d+)?)\s*x\s+([^()]+?)\s*\((?:SAR\s*)?([0-9.]+)(?:\s*SAR)?\)',
          caseSensitive: false,
        );
        for (final match in itemRegex.allMatches(content)) {
          final qty = double.tryParse(match.group(1) ?? '1') ?? 1.0;
          final name = match.group(2)?.trim() ?? 'Item';
          final price = double.tryParse(match.group(3) ?? '0') ?? 0.0;
          parsedItems.add({
            'name': name,
            'quantity': qty,
            'price': price,
          });
        }
      }
    }

    // Determine channel source
    String detectedSource = map['source'] as String? ?? 'sms';
    if (detectedSource == 'sms') {
      if (raw.startsWith('Chat:')) {
        detectedSource = 'chat';
      } else if (raw.startsWith('Receipt Scan:')) {
        detectedSource = 'receipt_scan';
      }
    }

    // Determine who spent this ('me' | 'partner' | 'both')
    String detectedSpentBy = map['spent_by'] as String? ?? '';
    if (detectedSpentBy.isEmpty) {
      final spentByRegex = RegExp(r'SpentBy:\s*(me|partner|both)', caseSensitive: false);
      final match = spentByRegex.firstMatch(raw);
      if (match != null) {
        detectedSpentBy = match.group(1)!.toLowerCase();
      } else {
        final cat = map['category_code'] as String? ?? '';
        if (cat.contains('GROCERY') || cat.contains('UTILITIES') || raw.toLowerCase().contains('both') || raw.toLowerCase().contains('cleaning')) {
          detectedSpentBy = 'both';
        } else {
          detectedSpentBy = 'me';
        }
      }
    }

    return Transaction(
      id: map['id'] as String,
      householdId: map['household_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'SAR',
      merchant: map['merchant'] as String?,
      categoryCode: map['category_code'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isReallocated: map['is_reallocated'] as bool? ?? false,
      reallocatedFromBudgetId: map['reallocated_from_budget_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      source: detectedSource,
      spentBy: detectedSpentBy,
      items: parsedItems,
      receiptUrl: map['receipt_url'] as String?,
      dedupFingerprint: map['dedup_fingerprint'] as String?,
      rawSms: raw,
    );
  }
}

// ── Budget ───────────────────────────────────────────────────────────────────

class Budget {
  final String id;
  final String householdId;
  final String month;
  final String categoryCode;
  final double allocatedAmount;
  final double spentAmount;
  final double remainingAmount;

  const Budget({
    required this.id,
    required this.householdId,
    required this.month,
    required this.categoryCode,
    required this.allocatedAmount,
    required this.spentAmount,
    required this.remainingAmount,
  });

  factory Budget.fromMap(Map<String, dynamic> map) => Budget(
        id: map['id'] as String,
        householdId: map['household_id'] as String,
        month: map['month'] as String,
        categoryCode: map['category_code'] as String,
        allocatedAmount: (map['allocated_amount'] as num).toDouble(),
        spentAmount: (map['spent_amount'] as num).toDouble(),
        remainingAmount: (map['remaining_amount'] as num).toDouble(),
      );

  double get usagePercent =>
      allocatedAmount > 0 ? (spentAmount / allocatedAmount).clamp(0.0, 1.0) : 0.0;
}

// ── Household ────────────────────────────────────────────────────────────────

class Household {
  final String id;
  final String name;
  final String inviteCode;
  final DateTime createdAt;

  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdAt,
  });

  factory Household.fromMap(Map<String, dynamic> map) => Household(
        id: map['id'] as String,
        name: map['name'] as String,
        inviteCode: map['invite_code'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

// ── AppUser ──────────────────────────────────────────────────────────────────

class AppUser {
  final String id;
  final String? householdId;
  final String displayName;
  final String role;

  const AppUser({
    required this.id,
    this.householdId,
    required this.displayName,
    required this.role,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        householdId: map['household_id'] as String?,
        displayName: map['display_name'] as String,
        role: map['role'] as String? ?? 'member',
      );

  bool get isAdmin => role == 'admin';
}
