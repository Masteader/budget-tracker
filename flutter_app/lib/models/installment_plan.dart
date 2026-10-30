/// Represents a Buy Now Pay Later (BNPL) or credit card installment commitment (e.g. Tamara, Tabby).
class InstallmentPlan {
  final String id;
  final String householdId;
  final String merchant;
  final String provider; // 'Tamara', 'Tabby', 'Bank', 'Other'
  final double totalAmount;
  final int installmentCount;
  final double monthlyAmount;
  final int paidInstallments;
  final int dayOfMonth;
  final String startDate;
  final String status; // 'ACTIVE', 'COMPLETED'
  final String? categoryCode;
  final String? originalTransactionId;
  final String? notes;

  /// 'monthly' or 'biweekly' (Tabby / Tamara "pay in 4"). [monthlyAmount] is
  /// the amount of one installment for either frequency.
  final String frequency;

  /// Next unpaid installment's date from the API (ACTIVE plans only).
  final DateTime? nextDueAt;

  InstallmentPlan({
    required this.id,
    required this.householdId,
    required this.merchant,
    this.provider = 'Tamara',
    required this.totalAmount,
    this.installmentCount = 4,
    required this.monthlyAmount,
    this.paidInstallments = 1,
    this.dayOfMonth = 27,
    required this.startDate,
    this.status = 'ACTIVE',
    this.categoryCode,
    this.originalTransactionId,
    this.notes,
    this.frequency = 'monthly',
    this.nextDueAt,
  });

  bool get isBiweekly => frequency == 'biweekly';

  /// Amount of one installment (the API's `monthly_amount`).
  double get installmentAmount => monthlyAmount;

  /// Dates of the remaining installments, first one first (it may be in the
  /// past when overdue), at most [max]. Uses `next_due_at` when the API sent
  /// it; otherwise a biweekly plan counts 14 days per paid installment from
  /// the start date and a monthly plan uses `day_of_month` from [today].
  /// [today] is a calendar date (UTC midnight).
  List<DateTime> dueDates({required DateTime today, int max = 6}) {
    final remaining = remainingInstallments;
    if (isCompleted || remaining <= 0) return const [];
    final day0 = DateTime.utc(today.year, today.month, today.day);
    DateTime first;
    int anchorDay;
    if (nextDueAt != null) {
      first = nextDueAt!;
      anchorDay = first.day;
    } else if (isBiweekly) {
      final start = DateTime.tryParse(startDate);
      if (start == null) return const [];
      first = DateTime.utc(start.year, start.month, start.day).add(Duration(days: 14 * paidInstallments));
      anchorDay = first.day;
    } else {
      anchorDay = dayOfMonth.clamp(1, 31);
      first = _monthDay(day0.year, day0.month, anchorDay);
      if (first.isBefore(day0)) first = _monthDay(day0.year, day0.month + 1, anchorDay);
    }
    final out = <DateTime>[];
    for (var i = 0; i < remaining && out.length < max; i++) {
      out.add(isBiweekly
          ? first.add(Duration(days: 14 * i))
          : _monthDay(first.year, first.month + i, anchorDay));
    }
    return out;
  }

  /// The next installment's date (see [dueDates]), or null when none is due.
  DateTime? nextDueDate({required DateTime today}) {
    final dates = dueDates(today: today, max: 1);
    return dates.isEmpty ? null : dates.first;
  }

  static DateTime _monthDay(int year, int month, int day) {
    final y = year + (month - 1) ~/ 12;
    final m = (month - 1) % 12 + 1;
    final last = DateTime.utc(y, m + 1, 0).day;
    return DateTime.utc(y, m, day < last ? day : last);
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final d = DateTime.tryParse(raw);
    return d == null ? null : DateTime.utc(d.year, d.month, d.day);
  }

  bool get isCompleted => status.toUpperCase() == 'COMPLETED' || paidInstallments >= installmentCount;

  int get remainingInstallments => (installmentCount - paidInstallments).clamp(0, installmentCount);

  double get remainingAmount => (totalAmount - (monthlyAmount * paidInstallments)).clamp(0.0, totalAmount);

  double get progressPercentage {
    if (installmentCount <= 0) return 1.0;
    return (paidInstallments / installmentCount).clamp(0.0, 1.0);
  }

  factory InstallmentPlan.fromJson(Map<String, dynamic> json) {
    final total = (json['total_amount'] as num?)?.toDouble() ?? 0.0;
    final count = (json['installment_count'] as num?)?.toInt() ?? 4;
    final monthly = (json['monthly_amount'] as num?)?.toDouble() ??
        (count > 0 ? (total / count) : total);

    return InstallmentPlan(
      id: json['id'] as String? ?? '',
      householdId: json['household_id'] as String? ?? '',
      merchant: json['merchant'] as String? ?? 'Merchant',
      provider: json['provider'] as String? ?? 'Tamara',
      totalAmount: total,
      installmentCount: count,
      monthlyAmount: monthly,
      paidInstallments: (json['paid_installments'] as num?)?.toInt() ?? 1,
      dayOfMonth: (json['day_of_month'] as num?)?.toInt() ?? 27,
      startDate: json['start_date'] as String? ?? DateTime.now().toIso8601String().split('T').first,
      status: json['status'] as String? ?? 'ACTIVE',
      categoryCode: json['category_code'] as String?,
      originalTransactionId: json['original_transaction_id'] as String?,
      notes: json['notes'] as String?,
      frequency: json['frequency'] == 'biweekly' ? 'biweekly' : 'monthly',
      nextDueAt: _parseDate(json['next_due_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'merchant': merchant,
      'provider': provider,
      'total_amount': totalAmount,
      'installment_count': installmentCount,
      'monthly_amount': monthlyAmount,
      'paid_installments': paidInstallments,
      'day_of_month': dayOfMonth,
      'start_date': startDate,
      'status': status,
      'category_code': categoryCode,
      'original_transaction_id': originalTransactionId,
      'notes': notes,
      'frequency': frequency,
      'next_due_at': nextDueAt?.toIso8601String().substring(0, 10),
    };
  }

  InstallmentPlan copyWith({
    String? id,
    String? householdId,
    String? merchant,
    String? provider,
    double? totalAmount,
    int? installmentCount,
    double? monthlyAmount,
    int? paidInstallments,
    int? dayOfMonth,
    String? startDate,
    String? status,
    String? categoryCode,
    String? originalTransactionId,
    String? notes,
    String? frequency,
    DateTime? nextDueAt,
  }) {
    return InstallmentPlan(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      merchant: merchant ?? this.merchant,
      provider: provider ?? this.provider,
      totalAmount: totalAmount ?? this.totalAmount,
      installmentCount: installmentCount ?? this.installmentCount,
      monthlyAmount: monthlyAmount ?? this.monthlyAmount,
      paidInstallments: paidInstallments ?? this.paidInstallments,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      startDate: startDate ?? this.startDate,
      status: status ?? this.status,
      categoryCode: categoryCode ?? this.categoryCode,
      originalTransactionId: originalTransactionId ?? this.originalTransactionId,
      notes: notes ?? this.notes,
      frequency: frequency ?? this.frequency,
      nextDueAt: nextDueAt ?? this.nextDueAt,
    );
  }
}
