import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/installment_plan.dart';

void main() {
  group('InstallmentPlan Model Tests', () {
    test('Parses from API JSON and computes remaining terms correctly', () {
      final json = {
        'id': 'plan_extra_123',
        'household_id': 'hh_1',
        'merchant': 'United Electronics Co. eXtra',
        'provider': 'Tamara',
        'total_amount': 7408.0,
        'installment_count': 4,
        'monthly_amount': 1852.0,
        'paid_installments': 1,
        'day_of_month': 27,
        'start_date': '2026-10-01',
        'status': 'ACTIVE',
        'category_code': 'OPEX-SHOPPING',
        'original_transaction_id': 'tx_extra_1',
      };

      final plan = InstallmentPlan.fromJson(json);

      expect(plan.id, 'plan_extra_123');
      expect(plan.merchant, 'United Electronics Co. eXtra');
      expect(plan.provider, 'Tamara');
      expect(plan.totalAmount, 7408.0);
      expect(plan.installmentCount, 4);
      expect(plan.monthlyAmount, 1852.0);
      expect(plan.paidInstallments, 1);
      expect(plan.remainingInstallments, 3);
      expect(plan.remainingAmount, 5556.0);
      expect(plan.progressPercentage, 0.25);
      expect(plan.status, 'ACTIVE');
      expect(plan.isCompleted, isFalse);
    });

    test('Serializes to JSON correctly', () {
      final plan = InstallmentPlan(
        id: 'plan_1',
        householdId: 'hh_1',
        merchant: 'eXtra',
        provider: 'Tamara',
        totalAmount: 7408.0,
        installmentCount: 4,
        monthlyAmount: 1852.0,
        paidInstallments: 4,
        dayOfMonth: 27,
        startDate: '2026-10-01',
        status: 'COMPLETED',
      );

      expect(plan.isCompleted, isTrue);
      expect(plan.remainingAmount, 0.0);
      expect(plan.progressPercentage, 1.0);

      final json = plan.toJson();
      expect(json['status'], 'COMPLETED');
      expect(json['total_amount'], 7408.0);
    });
  });
}
