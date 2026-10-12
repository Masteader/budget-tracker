import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/providers/installment_provider.dart';

void main() {
  group('InstallmentProvider Unit Tests', () {
    test('Initializes with empty plans and uninitialized state', () {
      final provider = InstallmentProvider();
      expect(provider.plans, isEmpty);
      expect(provider.isInitialized, isFalse);
      expect(provider.isLoading, isFalse);
      expect(provider.householdId, isNull);
    });

    test('setPlansForTesting updates plans and notifies listeners', () {
      final provider = InstallmentProvider();
      bool notified = false;
      provider.addListener(() => notified = true);

      final plan = InstallmentPlan(
        id: 'plan_test_1',
        householdId: 'hh_test',
        merchant: 'Tamara Store',
        provider: 'Tamara',
        totalAmount: 1200.0,
        installmentCount: 4,
        monthlyAmount: 300.0,
        paidInstallments: 1,
        dayOfMonth: 27,
        startDate: '2026-10-01',
        status: 'ACTIVE',
      );

      provider.setPlansForTesting([plan], householdId: 'hh_test');
      expect(notified, isTrue);
      expect(provider.plans.length, 1);
      expect(provider.plans.first.merchant, 'Tamara Store');
      expect(provider.householdId, 'hh_test');
      expect(provider.isInitialized, isTrue);
    });
  });
}
