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
  });

  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction(
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
      );
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
