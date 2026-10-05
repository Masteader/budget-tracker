/// Models for recurring household bills, subscriptions, and cycle reserve predictions.
class RecurringBillItem {
  final String merchant;
  final String normalizedMerchant;
  final String categoryCode;
  final double averageAmount;
  final int expectedDayOfMonth;
  final String status; // 'PAID_THIS_CYCLE', 'UPCOMING', 'OVERDUE'
  final String? lastPaidDate;
  final double? paidAmount;
  final String cadence;

  const RecurringBillItem({
    required this.merchant,
    required this.normalizedMerchant,
    required this.categoryCode,
    required this.averageAmount,
    required this.expectedDayOfMonth,
    required this.status,
    this.lastPaidDate,
    this.paidAmount,
    this.cadence = 'monthly',
  });

  bool get isPaid => status == 'PAID_THIS_CYCLE';
  bool get isUpcoming => status == 'UPCOMING';
  bool get isOverdue => status == 'OVERDUE';

  factory RecurringBillItem.fromMap(Map<String, dynamic> map) {
    return RecurringBillItem(
      merchant: map['merchant'] as String? ?? 'Unknown',
      normalizedMerchant: map['normalized_merchant'] as String? ?? 'Unknown',
      categoryCode: map['category_code'] as String? ?? 'OPEX-MISC',
      averageAmount: (map['average_amount'] as num?)?.toDouble() ?? 0.0,
      expectedDayOfMonth: (map['expected_day_of_month'] as num?)?.toInt() ?? 1,
      status: map['status'] as String? ?? 'UPCOMING',
      lastPaidDate: map['last_paid_date'] as String?,
      paidAmount: (map['paid_amount'] as num?)?.toDouble(),
      cadence: map['cadence'] as String? ?? 'monthly',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'merchant': merchant,
      'normalized_merchant': normalizedMerchant,
      'category_code': categoryCode,
      'average_amount': averageAmount,
      'expected_day_of_month': expectedDayOfMonth,
      'status': status,
      'last_paid_date': lastPaidDate,
      'paid_amount': paidAmount,
      'cadence': cadence,
    };
  }
}

class RecurringBillsSummary {
  final String cycleKey;
  final String cycleLabel;
  final double totalRecurringMonthly;
  final double paidThisCycle;
  final double reservedAmount;
  final List<RecurringBillItem> bills;

  const RecurringBillsSummary({
    required this.cycleKey,
    required this.cycleLabel,
    required this.totalRecurringMonthly,
    required this.paidThisCycle,
    required this.reservedAmount,
    required this.bills,
  });

  factory RecurringBillsSummary.fromMap(Map<String, dynamic> map) {
    final list = map['bills'] as List? ?? [];
    return RecurringBillsSummary(
      cycleKey: map['cycle_key'] as String? ?? '',
      cycleLabel: map['cycle_label'] as String? ?? '',
      totalRecurringMonthly: (map['total_recurring_monthly'] as num?)?.toDouble() ?? 0.0,
      paidThisCycle: (map['paid_this_cycle'] as num?)?.toDouble() ?? 0.0,
      reservedAmount: (map['reserved_amount'] as num?)?.toDouble() ?? 0.0,
      bills: list.map((b) => RecurringBillItem.fromMap(Map<String, dynamic>.from(b as Map))).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cycle_key': cycleKey,
      'cycle_label': cycleLabel,
      'total_recurring_monthly': totalRecurringMonthly,
      'paid_this_cycle': paidThisCycle,
      'reserved_amount': reservedAmount,
      'bills': bills.map((b) => b.toMap()).toList(),
    };
  }
}
