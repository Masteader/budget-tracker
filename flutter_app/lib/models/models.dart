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
  final String? cycleKey;
  final double previousCycleDelta;
  final bool isActive;
  final Map<String, double> subAllocations;

  const Budget({
    required this.id,
    required this.householdId,
    required this.month,
    required this.categoryCode,
    required this.allocatedAmount,
    required this.spentAmount,
    required this.remainingAmount,
    this.cycleKey,
    this.previousCycleDelta = 0.0,
    this.isActive = true,
    this.subAllocations = const {},
  });

  factory Budget.fromMap(Map<String, dynamic> map) => Budget(
        id: map['id'] as String,
        householdId: map['household_id'] as String,
        month: map['month'] as String,
        categoryCode: map['category_code'] as String,
        allocatedAmount: (map['allocated_amount'] as num).toDouble(),
        spentAmount: (map['spent_amount'] as num).toDouble(),
        remainingAmount: (map['remaining_amount'] as num).toDouble(),
        cycleKey: map['cycle_key'] as String?,
        previousCycleDelta: (map['previous_cycle_delta'] as num?)?.toDouble() ?? 0.0,
        isActive: map['is_active'] as bool? ?? true,
        subAllocations: (map['sub_allocations'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toDouble()),
            ) ??
            const {},
      );

  double get usagePercent =>
      allocatedAmount > 0 ? (spentAmount / allocatedAmount).clamp(0.0, 1.0) : 0.0;
}

// ── Salary Cycle & Sub-Budgets ───────────────────────────────────────────────

class SalaryCycleInfo {
  final String cycleKey;
  final String cycleStart;
  final String cycleEnd;
  final String label;
  final String monthName;
  final bool isCurrent;

  const SalaryCycleInfo({
    required this.cycleKey,
    required this.cycleStart,
    required this.cycleEnd,
    required this.label,
    required this.monthName,
    this.isCurrent = false,
  });

  factory SalaryCycleInfo.fromMap(Map<String, dynamic> map) => SalaryCycleInfo(
        cycleKey: map['cycle_key'] as String? ?? '',
        cycleStart: map['cycle_start'] as String? ?? '',
        cycleEnd: map['cycle_end'] as String? ?? '',
        label: map['label'] as String? ?? '',
        monthName: map['month_name'] as String? ?? '',
        isCurrent: map['is_current'] as bool? ?? false,
      );

  int get daysTotal {
    try {
      final start = DateTime.parse(cycleStart);
      final end = DateTime.parse(cycleEnd);
      return end.difference(start).inDays + 1;
    } catch (_) {
      return 30;
    }
  }

  int get daysElapsed {
    try {
      final start = DateTime.parse(cycleStart);
      final now = DateTime.now();
      final diff = now.difference(start).inDays + 1;
      return diff.clamp(1, daysTotal);
    } catch (_) {
      return 1;
    }
  }
}

class SubCategoryBreakdownItem {
  final String? subCode;
  final String name;
  final double allocatedAmount;
  final double spentAmount;
  final int transactionCount;

  const SubCategoryBreakdownItem({
    this.subCode,
    required this.name,
    this.allocatedAmount = 0.0,
    required this.spentAmount,
    required this.transactionCount,
  });

  factory SubCategoryBreakdownItem.fromMap(Map<String, dynamic> map) =>
      SubCategoryBreakdownItem(
        subCode: map['sub_code'] as String?,
        name: map['name'] as String? ?? '',
        allocatedAmount: (map['allocated_amount'] as num?)?.toDouble() ?? 0.0,
        spentAmount: (map['spent_amount'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (map['transaction_count'] as num?)?.toInt() ?? 0,
      );

  double get usagePercent =>
      allocatedAmount > 0 ? (spentAmount / allocatedAmount).clamp(0.0, 1.0) : 0.0;
}


class CategoryBreakdownItem {
  final String categoryCode;
  final String categoryName;
  final double allocatedAmount;
  final double spentAmount;
  final double remainingAmount;
  final double previousCycleDelta;
  final List<SubCategoryBreakdownItem> subCategories;

  const CategoryBreakdownItem({
    required this.categoryCode,
    required this.categoryName,
    required this.allocatedAmount,
    required this.spentAmount,
    required this.remainingAmount,
    this.previousCycleDelta = 0.0,
    this.subCategories = const [],
  });

  factory CategoryBreakdownItem.fromMap(Map<String, dynamic> map) {
    List<SubCategoryBreakdownItem> subs = [];
    if (map['sub_categories'] != null && map['sub_categories'] is List) {
      subs = (map['sub_categories'] as List)
          .map((item) => SubCategoryBreakdownItem.fromMap(
              Map<String, dynamic>.from(item as Map)))
          .toList();
    }

    return CategoryBreakdownItem(
      categoryCode: map['category_code'] as String? ?? '',
      categoryName: map['category_name'] as String? ?? '',
      allocatedAmount: (map['allocated_amount'] as num?)?.toDouble() ?? 0.0,
      spentAmount: (map['spent_amount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (map['remaining_amount'] as num?)?.toDouble() ?? 0.0,
      previousCycleDelta:
          (map['previous_cycle_delta'] as num?)?.toDouble() ?? 0.0,
      subCategories: subs,
    );
  }

  double get usagePercent =>
      allocatedAmount > 0 ? (spentAmount / allocatedAmount).clamp(0.0, 1.0) : 0.0;
}

const Map<String, List<String>> kSubCategoriesByParent = {
  'OPEX-GROCERY': [
    'Meat & Poultry',
    'Fresh Produce & Fruits',
    'Dairy & Eggs',
    'Snacks, Chips & Sweets',
    'Beverages & Water',
    'Pantry & Staples',
    'Cleaning Supplies',
  ],
  'OPEX-UTILITIES': [
    'Housing Rent',
    'Electricity (SEC)',
    'Home Fiber Internet',
    'Mobile SIMs & Data',
    'Water & Municipal Bills',
  ],
  'OPEX-DINING': [
    'Restaurants & Meals',
    'Coffee & Bakeries',
    'Delivery Apps',
  ],
  'OPEX-FUEL': [
    'Gasoline & Fuel',
    'Car Maintenance & Oil',
    'Ride Hailing (Uber/Bolt)',
  ],
  'OPEX-HEALTH': [
    'Prescriptions & Medicines',
    'Clinics & Dental',
  ],
  'OPEX-SHOPPING': [
    'Clothing & Fashion',
    'Electronics & Gadgets',
    'Home Goods & Furniture',
  ],
  'OPEX-ENTERTAINMENT': [
    'Cinema & Outings',
    'Gaming & Subscriptions',
    'Events & Activities',
  ],
  'CAPEX-EDUCATION': [
    'Tuition Fees',
    'Books & Courses',
    'School Supplies',
  ],
  'OPEX-GOV': [
    'Iqama & Visas',
    'Vehicle Registration',
    'Government Fees',
  ],
  'OPEX-MISC': [
    'Personal Care',
    'Gifts & Donations',
    'General Miscellaneous',
  ],
};


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
