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
  });

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
    };
  }
}
