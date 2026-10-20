/// Data models for the Budget Tracker app.
library;

import '../services/salary_cycle_service.dart';

export 'household_membership.dart';

// ── Transaction ──────────────────────────────────────────────────────────────

class Transaction {
  final String id;
  final String householdId;
  final double amount;
  final String currency;
  final String? merchant;
  final String? categoryCode;
  final String? subCategory;
  final DateTime timestamp;
  final bool isReallocated;
  final String? reallocatedFromBudgetId;
  final DateTime createdAt;
  final String source;
  final String spentBy; // legacy 'me' | 'partner' | 'both'
  final String paidBy; // 'me' | 'partner'
  final String beneficiary; // 'me' | 'partner' | 'both' | child name
  final List<Map<String, dynamic>> items;
  final String? accountId;
  final String? receiptUrl;
  final String? dedupFingerprint;
  final String? qrCodeRaw;
  final String? rawSms;

  /// Ingestion channels a transaction can come from (zero-SMS policy: no SMS channel).
  static const Set<String> sources = {'chat', 'receipt_scan', 'manual'};

  const Transaction({
    required this.id,
    required this.householdId,
    required this.amount,
    required this.currency,
    this.merchant,
    this.categoryCode,
    this.subCategory,
    required this.timestamp,
    required this.isReallocated,
    this.reallocatedFromBudgetId,
    required this.createdAt,
    this.source = 'manual',
    this.spentBy = 'both',
    this.paidBy = 'me',
    this.beneficiary = 'both',
    this.items = const [],
    this.accountId,
    this.receiptUrl,
    this.dedupFingerprint,
    this.qrCodeRaw,
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

    // Determine channel source. Only chat, receipt_scan and manual exist (the app
    // never reads SMS); any other stored label is shown as a manual entry.
    String detectedSource = map['source'] as String? ?? 'manual';
    if (!Transaction.sources.contains(detectedSource)) {
      detectedSource = 'manual';
    }
    if (detectedSource == 'manual') {
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

    // Determine 2D attribution: paid_by and beneficiary
    String detectedPaidBy = map['paid_by'] as String? ?? '';
    String detectedBeneficiary = map['beneficiary'] as String? ?? '';

    if (detectedPaidBy.isEmpty) {
      final paidByRegex = RegExp(r'PaidBy:\s*(me|partner)', caseSensitive: false);
      final match = paidByRegex.firstMatch(raw);
      if (match != null) {
        detectedPaidBy = match.group(1)!.toLowerCase();
      } else if (detectedSpentBy == 'partner') {
        detectedPaidBy = 'partner';
      } else {
        detectedPaidBy = 'me';
      }
    }

    if (detectedBeneficiary.isEmpty) {
      final benRegex = RegExp(r'Beneficiary:\s*(me|partner|both)', caseSensitive: false);
      final match = benRegex.firstMatch(raw);
      if (match != null) {
        detectedBeneficiary = match.group(1)!.toLowerCase();
      } else if (detectedSpentBy == 'partner') {
        detectedBeneficiary = 'partner';
      } else if (detectedSpentBy == 'both') {
        detectedBeneficiary = 'both';
      } else {
        detectedBeneficiary = 'me';
      }
    }

    return Transaction(
      id: map['id'] as String,
      householdId: map['household_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'SAR',
      merchant: map['merchant'] as String?,
      categoryCode: map['category_code'] as String?,
      subCategory: map['sub_category'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isReallocated: map['is_reallocated'] as bool? ?? false,
      reallocatedFromBudgetId: map['reallocated_from_budget_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      source: detectedSource,
      spentBy: detectedSpentBy,
      paidBy: detectedPaidBy,
      beneficiary: detectedBeneficiary,
      items: parsedItems,
      accountId: map['account_id'] as String?,
      receiptUrl: map['receipt_url'] as String?,
      dedupFingerprint: map['dedup_fingerprint'] as String?,
      qrCodeRaw: map['qr_code_raw'] as String? ??
          (raw.contains('ZATCA QR: ') ? raw.substring(raw.indexOf('ZATCA QR: ') + 10).trim() : null),
      rawSms: raw,
    );
  }

  bool get isInstallment {
    final raw = rawSms ?? '';
    final m = (merchant ?? '').toLowerCase();
    return raw.contains('Financed via') ||
        raw.toLowerCase().contains('tamara') ||
        raw.toLowerCase().contains('tabby') ||
        m.contains('tamara') ||
        m.contains('tabby');
  }

  String? get installmentBadgeText {
    final raw = rawSms ?? '';
    final regex = RegExp(r'Financed via\s+([^:]+):\s*Installment\s*(\d+)\s*of\s*(\d+)', caseSensitive: false);
    final match = regex.firstMatch(raw);
    if (match != null) {
      final p = match.group(1)?.trim() ?? 'BNPL';
      final cur = match.group(2) ?? '1';
      final tot = match.group(3) ?? '4';
      return '$p ($cur/$tot)';
    }
    if (raw.toLowerCase().contains('tamara') || (merchant ?? '').toLowerCase().contains('tamara')) {
      return 'Tamara (1/4)';
    }
    if (raw.toLowerCase().contains('tabby') || (merchant ?? '').toLowerCase().contains('tabby')) {
      return 'Tabby (1/4)';
    }
    return null;
  }

  String get installmentProvider {
    final raw = (rawSms ?? '').toLowerCase();
    final m = (merchant ?? '').toLowerCase();
    if (raw.contains('tabby') || m.contains('tabby')) return 'Tabby';
    return 'Tamara';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'amount': amount,
      'currency': currency,
      'merchant': merchant,
      'category_code': categoryCode,
      'sub_category': subCategory,
      'timestamp': timestamp.toIso8601String(),
      'is_reallocated': isReallocated,
      'reallocated_from_budget_id': reallocatedFromBudgetId,
      'created_at': createdAt.toIso8601String(),
      'source': source,
      'spent_by': spentBy,
      'paid_by': paidBy,
      'beneficiary': beneficiary,
      'items': items,
      'account_id': accountId,
      'receipt_url': receiptUrl,
      'dedup_fingerprint': dedupFingerprint,
      'qr_code_raw': qrCodeRaw,
      'raw_sms': rawSms,
    };
  }

  Transaction copyWith({
    String? id,
    String? householdId,
    double? amount,
    String? currency,
    String? merchant,
    String? categoryCode,
    String? subCategory,
    DateTime? timestamp,
    bool? isReallocated,
    String? reallocatedFromBudgetId,
    DateTime? createdAt,
    String? source,
    String? spentBy,
    String? paidBy,
    String? beneficiary,
    List<Map<String, dynamic>>? items,
    String? accountId,
    String? receiptUrl,
    String? dedupFingerprint,
    String? qrCodeRaw,
    String? rawSms,
  }) {
    return Transaction(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      merchant: merchant ?? this.merchant,
      categoryCode: categoryCode ?? this.categoryCode,
      subCategory: subCategory ?? this.subCategory,
      timestamp: timestamp ?? this.timestamp,
      isReallocated: isReallocated ?? this.isReallocated,
      reallocatedFromBudgetId: reallocatedFromBudgetId ?? this.reallocatedFromBudgetId,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      spentBy: spentBy ?? this.spentBy,
      paidBy: paidBy ?? this.paidBy,
      beneficiary: beneficiary ?? this.beneficiary,
      items: items ?? this.items,
      accountId: accountId ?? this.accountId,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      dedupFingerprint: dedupFingerprint ?? this.dedupFingerprint,
      qrCodeRaw: qrCodeRaw ?? this.qrCodeRaw,
      rawSms: rawSms ?? this.rawSms,
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
  final String? accountId;

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
    this.accountId,
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
        accountId: map['account_id'] as String?,
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

  /// Calendar-date arithmetic in UTC so a device DST change (23 h / 25 h day)
  /// cannot shift the count; "today" is the Asia/Riyadh date.
  static DateTime _asDate(String iso) {
    final d = DateTime.parse(iso);
    return DateTime.utc(d.year, d.month, d.day);
  }

  int get daysTotal {
    try {
      return _asDate(cycleEnd).difference(_asDate(cycleStart)).inDays + 1;
    } catch (_) {
      return 30;
    }
  }

  int get daysElapsed {
    try {
      final diff = SalaryCycleService.riyadhToday().difference(_asDate(cycleStart)).inDays + 1;
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

// ── CategoryItem ─────────────────────────────────────────────────────────────

class CategoryItem {
  final String code;
  final String name;
  final bool isSystem;
  final bool isActive;
  final String? householdId;
  final List<String> keywords;

  const CategoryItem({
    required this.code,
    required this.name,
    this.isSystem = false,
    this.isActive = true,
    this.householdId,
    this.keywords = const [],
  });

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    return CategoryItem(
      code: json['code'] as String? ?? '',
      name: json['category'] as String? ?? json['name'] as String? ?? '',
      isSystem: json['is_system'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      householdId: json['household_id'] as String?,
      keywords: (json['keywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'category': name,
        'is_system': isSystem,
        'is_active': isActive,
        if (householdId != null) 'household_id': householdId,
        'keywords': keywords,
      };
}

// ── Household Dependent (Children & Dependents) ──────────────────────────────

class HouseholdDependent {
  final String id;
  final String householdId;
  final String name;
  final String avatarIcon;
  final String relationship;
  final double monthlyAllowance;
  final String? linkedUserId;
  final DateTime? createdAt;

  const HouseholdDependent({
    required this.id,
    required this.householdId,
    required this.name,
    this.avatarIcon = 'child',
    this.relationship = 'child',
    this.monthlyAllowance = 0.0,
    this.linkedUserId,
    this.createdAt,
  });

  bool get isClaimed => linkedUserId != null && linkedUserId!.isNotEmpty;
  bool get isSpouse => relationship.toLowerCase() == 'spouse' || relationship.toLowerCase() == 'wife';
  bool get isPeer => relationship.toLowerCase() == 'peer' || relationship.toLowerCase() == 'roommate';
  bool get isChild => !isSpouse && !isPeer;

  factory HouseholdDependent.fromMap(Map<String, dynamic> map) {
    return HouseholdDependent(
      id: map['id'] as String? ?? '',
      householdId: map['household_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      avatarIcon: map['avatar_icon'] as String? ?? 'child',
      relationship: map['relationship'] as String? ?? 'child',
      monthlyAllowance: (map['monthly_allowance'] as num?)?.toDouble() ?? 0.0,
      linkedUserId: map['linked_user_id'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'name': name,
      'avatar_icon': avatarIcon,
      'relationship': relationship,
      'monthly_allowance': monthlyAllowance,
      if (linkedUserId != null) 'linked_user_id': linkedUserId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}

// ── Household Role Invite ───────────────────────────────────────────────────

class HouseholdInvite {
  final String id;
  final String householdId;
  final String inviteCode;
  final String role; // 'spouse' | 'peer' | 'family_member' | 'dependent'
  final String? targetMemberId;
  final String? targetMemberName;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final bool isValid;

  const HouseholdInvite({
    this.id = '',
    required this.householdId,
    required this.inviteCode,
    this.role = 'peer',
    this.targetMemberId,
    this.targetMemberName,
    this.expiresAt,
    this.createdAt,
    this.isValid = true,
  });

  bool get isSpouse => role.toLowerCase() == 'spouse' || role.toLowerCase() == 'wife';
  bool get isPeer => role.toLowerCase() == 'peer' || role.toLowerCase() == 'roommate';
  bool get isFamilyMember => role.toLowerCase() == 'family_member' || role.toLowerCase() == 'dependent';

  factory HouseholdInvite.fromMap(Map<String, dynamic> map) {
    return HouseholdInvite(
      id: map['id'] as String? ?? '',
      householdId: map['household_id'] as String? ?? '',
      inviteCode: map['invite_code'] as String? ?? '',
      role: map['role'] as String? ?? 'peer',
      targetMemberId: map['target_member_id'] as String?,
      targetMemberName: map['target_member_name'] as String?,
      expiresAt: map['expires_at'] != null ? DateTime.tryParse(map['expires_at'].toString()) : null,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      isValid: map['is_valid'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'household_id': householdId,
      'invite_code': inviteCode,
      'role': role,
      if (targetMemberId != null) 'target_member_id': targetMemberId,
      if (targetMemberName != null) 'target_member_name': targetMemberName,
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'is_valid': isValid,
    };
  }
}

// ── Reimbursement Record Request ─────────────────────────────────────────────

class ReimbursementRecordRequest {
  final String householdId;
  final String payerId;
  final String recipientId;
  final double amount;
  final String paymentMethod;
  final String? notes;

  const ReimbursementRecordRequest({
    required this.householdId,
    required this.payerId,
    required this.recipientId,
    required this.amount,
    this.paymentMethod = 'stc_pay',
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'household_id': householdId,
      'payer_id': payerId,
      'recipient_id': recipientId,
      'amount': amount,
      'payment_method': paymentMethod,
      if (notes != null) 'notes': notes,
    };
  }
}

// ── Multi-Party Pairwise & Simplified Debt Models ────────────────────────────

class PairwiseDebt {
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final double amount;

  const PairwiseDebt({
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.toName,
    required this.amount,
  });

  factory PairwiseDebt.fromMap(Map<String, dynamic> map) {
    return PairwiseDebt(
      fromId: map['from_id'] as String? ?? '',
      toId: map['to_id'] as String? ?? '',
      fromName: map['from_name'] as String? ?? map['from_id'] as String? ?? 'Member',
      toName: map['to_name'] as String? ?? map['to_id'] as String? ?? 'Member',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'from_id': fromId,
      'to_id': toId,
      'from_name': fromName,
      'to_name': toName,
      'amount': amount,
    };
  }
}

class SimplifiedDebt {
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final double amount;

  const SimplifiedDebt({
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.toName,
    required this.amount,
  });

  factory SimplifiedDebt.fromMap(Map<String, dynamic> map) {
    return SimplifiedDebt(
      fromId: map['from_id'] as String? ?? '',
      toId: map['to_id'] as String? ?? '',
      fromName: map['from_name'] as String? ?? map['from_id'] as String? ?? 'Member',
      toName: map['to_name'] as String? ?? map['to_id'] as String? ?? 'Member',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'from_id': fromId,
      'to_id': toId,
      'from_name': fromName,
      'to_name': toName,
      'amount': amount,
    };
  }
}

class FamilyNafaqahSummary {
  final double wifeReimbursementOwed;
  final double spentOnWife;
  final double spentOnChildren;
  final double familyGeneralTotal;

  const FamilyNafaqahSummary({
    this.wifeReimbursementOwed = 0.0,
    this.spentOnWife = 0.0,
    this.spentOnChildren = 0.0,
    this.familyGeneralTotal = 0.0,
  });

  factory FamilyNafaqahSummary.fromMap(Map<String, dynamic> map) {
    return FamilyNafaqahSummary(
      wifeReimbursementOwed: (map['wife_reimbursement_owed'] as num?)?.toDouble() ?? 0.0,
      spentOnWife: (map['spent_on_wife'] as num?)?.toDouble() ?? 0.0,
      spentOnChildren: (map['spent_on_children'] as num?)?.toDouble() ?? 0.0,
      familyGeneralTotal: (map['family_general_total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'wife_reimbursement_owed': wifeReimbursementOwed,
      'spent_on_wife': spentOnWife,
      'spent_on_children': spentOnChildren,
      'family_general_total': familyGeneralTotal,
    };
  }
}

class SettlementV2Summary {
  final String mode; // 'family_nafaqah' | 'multi_roommate' | 'standard'
  final FamilyNafaqahSummary? familySummary;
  final List<PairwiseDebt> pairwiseDebts;
  final List<SimplifiedDebt> simplifiedDebts;
  final Map<String, double> roommateBalances;

  const SettlementV2Summary({
    this.mode = 'standard',
    this.familySummary,
    this.pairwiseDebts = const [],
    this.simplifiedDebts = const [],
    this.roommateBalances = const {},
  });

  bool get isFamilyMode => mode == 'family_nafaqah';
  bool get isRoommateMode => mode == 'multi_roommate';

  factory SettlementV2Summary.fromMap(Map<String, dynamic> map) {
    FamilyNafaqahSummary? fam;
    if (map['family_summary'] != null && map['family_summary'] is Map) {
      fam = FamilyNafaqahSummary.fromMap(Map<String, dynamic>.from(map['family_summary'] as Map));
    }

    List<PairwiseDebt> pairs = [];
    if (map['pairwise_debts'] != null && map['pairwise_debts'] is List) {
      pairs = (map['pairwise_debts'] as List)
          .map((e) => PairwiseDebt.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    List<SimplifiedDebt> simplified = [];
    if (map['simplified_debts'] != null && map['simplified_debts'] is List) {
      simplified = (map['simplified_debts'] as List)
          .map((e) => SimplifiedDebt.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    Map<String, double> balances = {};
    if (map['roommate_balances'] != null && map['roommate_balances'] is Map) {
      (map['roommate_balances'] as Map).forEach((k, v) {
        balances[k.toString()] = (v as num).toDouble();
      });
    }

    return SettlementV2Summary(
      mode: map['mode'] as String? ?? 'standard',
      familySummary: fam,
      pairwiseDebts: pairs,
      simplifiedDebts: simplified,
      roommateBalances: balances,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mode': mode,
      if (familySummary != null) 'family_summary': familySummary!.toMap(),
      'pairwise_debts': pairwiseDebts.map((e) => e.toMap()).toList(),
      'simplified_debts': simplifiedDebts.map((e) => e.toMap()).toList(),
      'roommate_balances': roommateBalances,
    };
  }
}



