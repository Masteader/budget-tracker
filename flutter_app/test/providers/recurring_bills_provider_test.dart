import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';

void main() {
  group('RecurringBillsProvider Unit Tests', () {
    test('initial state has no summary and is not loading', () {
      final provider = RecurringBillsProvider();
      expect(provider.summary, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.householdId, isNull);
    });

    test('manual updateSummary notifies listeners and updates getters', () {
      final provider = RecurringBillsProvider();
      var notified = false;
      provider.addListener(() => notified = true);

      const dummyItem = RecurringBillItem(
        merchant: 'Housing Rent',
        normalizedMerchant: 'Housing Rent',
        categoryCode: 'OPEX-UTILITIES',
        averageAmount: 3000.0,
        expectedDayOfMonth: 1,
        status: 'UPCOMING',
        cadence: 'monthly',
        subCode: 'housing_rent',
        isBudgeted: true,
      );

      const dummySummary = RecurringBillsSummary(
        cycleKey: '2026-10',
        cycleLabel: 'Cycle Oct 2026',
        totalRecurringMonthly: 3000.0,
        paidThisCycle: 0.0,
        reservedAmount: 3000.0,
        bills: [dummyItem],
      );

      provider.setSummaryForTesting(dummySummary, householdId: 'hh-123');
      expect(notified, isTrue);
      expect(provider.summary, isNotNull);
      expect(provider.summary!.reservedAmount, equals(3000.0));
      expect(provider.summary!.bills.length, equals(1));
      expect(provider.householdId, equals('hh-123'));
    });
  });
}
