import 'package:flutter/material.dart';

/// Supported types of accounts.
enum AccountType {
  bank,
  eWallet,
  crypto,
  cash,
  sharedPool,
}

extension AccountTypeExtension on AccountType {
  String get value {
    switch (this) {
      case AccountType.bank:
        return 'bank';
      case AccountType.eWallet:
        return 'e_wallet';
      case AccountType.crypto:
        return 'crypto';
      case AccountType.cash:
        return 'cash';
      case AccountType.sharedPool:
        return 'shared_pool';
    }
  }

  static AccountType fromString(String? val) {
    switch (val) {
      case 'bank':
        return AccountType.bank;
      case 'e_wallet':
      case 'ewallet':
        return AccountType.eWallet;
      case 'crypto':
        return AccountType.crypto;
      case 'cash':
        return AccountType.cash;
      case 'shared_pool':
      case 'pool':
        return AccountType.sharedPool;
      default:
        return AccountType.bank;
    }
  }

  String get labelEn {
    switch (this) {
      case AccountType.bank:
        return 'Bank Account';
      case AccountType.eWallet:
        return 'E-Wallet';
      case AccountType.crypto:
        return 'Crypto Exchange';
      case AccountType.cash:
        return 'Cash Wallet';
      case AccountType.sharedPool:
        return 'Shared Household Pool';
    }
  }

  IconData get defaultIcon {
    switch (this) {
      case AccountType.bank:
        return Icons.account_balance_rounded;
      case AccountType.eWallet:
        return Icons.phone_android_rounded;
      case AccountType.crypto:
        return Icons.currency_bitcoin_rounded;
      case AccountType.cash:
        return Icons.payments_rounded;
      case AccountType.sharedPool:
        return Icons.group_rounded;
    }
  }
}

/// The three capacity states an account can have against its mapped budgets.
enum AccountCapacityStatus {
  zeroBased, // Margin == 0 (100% Allocated)
  surplus,   // Margin > 0 (Surplus Buffer)
  deficit,   // Margin < 0 (Over-Committed)
}

/// Represents a bank account, e-wallet, crypto exchange, cash, or shared pool.
class Account {
  final String id;
  final String householdId;
  final String ownerUserId;
  final String name;
  final AccountType accountType;
  final String currency;
  final double balance;
  final bool isSharedPool;
  final String colorHex;
  final String iconName;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Account({
    required this.id,
    required this.householdId,
    required this.ownerUserId,
    required this.name,
    required this.accountType,
    this.currency = 'SAR',
    this.balance = 0.0,
    this.isSharedPool = false,
    this.colorHex = '#00E5BF',
    this.iconName = 'account_balance_rounded',
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Calculates capacity margin against committed budgets.
  /// Margin = balance - committedBudgets.
  double calculateMargin(double committedBudgets) {
    return balance - committedBudgets;
  }

  /// Determines the capacity status.
  AccountCapacityStatus getStatus(double committedBudgets) {
    final margin = calculateMargin(committedBudgets);
    if (margin.abs() < 0.001) {
      return AccountCapacityStatus.zeroBased;
    } else if (margin > 0) {
      return AccountCapacityStatus.surplus;
    } else {
      return AccountCapacityStatus.deficit;
    }
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id']?.toString() ?? '',
      householdId: map['household_id']?.toString() ?? '',
      ownerUserId: map['owner_user_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      accountType: AccountTypeExtension.fromString(map['account_type']?.toString()),
      currency: map['currency']?.toString() ?? 'SAR',
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      isSharedPool: map['is_shared_pool'] == true,
      colorHex: map['color_hex']?.toString() ?? '#00E5BF',
      iconName: map['icon_name']?.toString() ?? 'account_balance_rounded',
      isArchived: map['is_archived'] == true,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'owner_user_id': ownerUserId,
      'name': name,
      'account_type': accountType.value,
      'currency': currency,
      'balance': balance,
      'is_shared_pool': isSharedPool,
      'color_hex': colorHex,
      'icon_name': iconName,
      'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  Account copyWith({
    String? name,
    AccountType? accountType,
    String? currency,
    double? balance,
    bool? isSharedPool,
    String? colorHex,
    String? iconName,
    bool? isArchived,
  }) {
    return Account(
      id: id,
      householdId: householdId,
      ownerUserId: ownerUserId,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      currency: currency ?? this.currency,
      balance: balance ?? this.balance,
      isSharedPool: isSharedPool ?? this.isSharedPool,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Inter-account fund transfers with optional fees.
class AccountTransfer {
  final String id;
  final String householdId;
  final String userId;
  final String fromAccountId;
  final String toAccountId;
  final double amount;
  final double fee;
  final DateTime timestamp;
  final String? notes;
  final DateTime? createdAt;

  const AccountTransfer({
    required this.id,
    required this.householdId,
    required this.userId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    this.fee = 0.0,
    required this.timestamp,
    this.notes,
    this.createdAt,
  });

  double get totalDeduction => amount + fee;

  factory AccountTransfer.fromMap(Map<String, dynamic> map) {
    return AccountTransfer(
      id: map['id']?.toString() ?? '',
      householdId: map['household_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      fromAccountId: map['from_account_id']?.toString() ?? '',
      toAccountId: map['to_account_id']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      fee: (map['fee'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'amount': amount,
      'fee': fee,
      'timestamp': timestamp.toIso8601String(),
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}

/// Source types for incoming money.
enum IncomeSourceType {
  salary,
  overtime,
  bonus,
  sideGig,
  roommateShare,
  other,
}

extension IncomeSourceTypeExtension on IncomeSourceType {
  String get value {
    switch (this) {
      case IncomeSourceType.salary:
        return 'salary';
      case IncomeSourceType.overtime:
        return 'overtime';
      case IncomeSourceType.bonus:
        return 'bonus';
      case IncomeSourceType.sideGig:
        return 'side_gig';
      case IncomeSourceType.roommateShare:
        return 'roommate_share';
      case IncomeSourceType.other:
        return 'other';
    }
  }

  static IncomeSourceType fromString(String? val) {
    switch (val) {
      case 'salary':
        return IncomeSourceType.salary;
      case 'overtime':
        return IncomeSourceType.overtime;
      case 'bonus':
        return IncomeSourceType.bonus;
      case 'side_gig':
        return IncomeSourceType.sideGig;
      case 'roommate_share':
        return IncomeSourceType.roommateShare;
      default:
        return IncomeSourceType.other;
    }
  }

  String get labelEn {
    switch (this) {
      case IncomeSourceType.salary:
        return 'Monthly Salary';
      case IncomeSourceType.overtime:
        return 'Overtime';
      case IncomeSourceType.bonus:
        return 'Bonus / Commission';
      case IncomeSourceType.sideGig:
        return 'Side Gig / Freelance';
      case IncomeSourceType.roommateShare:
        return 'Roommate Share';
      case IncomeSourceType.other:
        return 'Other Income';
    }
  }
}

/// Multi-source itemized income record.
class IncomeRecord {
  final String id;
  final String householdId;
  final String userId;
  final String accountId;
  final String cycleKey;
  final IncomeSourceType sourceType;
  final String title;
  final double baseAmount;
  final double overtime;
  final double bonus;
  final double deductions;
  final DateTime receivedAt;
  final String? notes;
  final DateTime? createdAt;

  const IncomeRecord({
    required this.id,
    required this.householdId,
    required this.userId,
    required this.accountId,
    required this.cycleKey,
    required this.sourceType,
    required this.title,
    this.baseAmount = 0.0,
    this.overtime = 0.0,
    this.bonus = 0.0,
    this.deductions = 0.0,
    required this.receivedAt,
    this.notes,
    this.createdAt,
  });

  /// Net amount deposited = base + overtime + bonus - deductions.
  double get netAmount => baseAmount + overtime + bonus - deductions;

  factory IncomeRecord.fromMap(Map<String, dynamic> map) {
    final net = (map['net_amount'] as num?)?.toDouble();
    final base = (map['base_amount'] as num?)?.toDouble() ?? 0.0;
    final ot = (map['overtime'] as num?)?.toDouble() ?? 0.0;
    final b = (map['bonus'] as num?)?.toDouble() ?? 0.0;
    final d = (map['deductions'] as num?)?.toDouble() ?? 0.0;

    return IncomeRecord(
      id: map['id']?.toString() ?? '',
      householdId: map['household_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      accountId: map['account_id']?.toString() ?? '',
      cycleKey: map['cycle_key']?.toString() ?? '',
      sourceType: IncomeSourceTypeExtension.fromString(map['source_type']?.toString()),
      title: map['title']?.toString() ?? 'Income',
      baseAmount: (base == 0.0 && net != null && net > 0) ? net : base,
      overtime: ot,
      bonus: b,
      deductions: d,
      receivedAt: DateTime.tryParse(map['received_at']?.toString() ?? '') ?? DateTime.now(),
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'account_id': accountId,
      'cycle_key': cycleKey,
      'source_type': sourceType.value,
      'title': title,
      'base_amount': baseAmount,
      'overtime': overtime,
      'bonus': bonus,
      'deductions': deductions,
      'net_amount': netAmount,
      'received_at': receivedAt.toIso8601String(),
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}
