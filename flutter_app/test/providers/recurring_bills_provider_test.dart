import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/models/transaction_attribution.dart';
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

  // FABLE2-APP-06: a paid bill was inserted without source or attribution.
  test('a bill payment row is a manual entry paid by the recorder for the household', () {
    const bill = RecurringBillItem(
      merchant: 'SEC Electricity',
      normalizedMerchant: 'SEC',
      categoryCode: 'OPEX-UTILITIES',
      averageAmount: 420.0,
      expectedDayOfMonth: 5,
      status: 'UPCOMING',
      subCode: 'electricity',
    );
    final row = RecurringBillsProvider.buildBillPaymentRow(
      householdId: 'hh-1',
      userId: 'u-1',
      bill: bill,
      occurredAt: DateTime.utc(2026, 10, 21, 9),
    );
    expect(row['source'], 'manual');
    expect(row['user_id'], 'u-1');
    expect(row['spent_by'], 'me');
    expect(row['beneficiary_type'], 'household');
    expect(row['beneficiary_id'], 'household');
    expect(row['category_code'], 'OPEX-UTILITIES');
    expect(row['raw_sms'], 'Manual: SEC Electricity | PaidBy: me | Beneficiary: household | SpentBy: me');
    expect(storedPayerRef(row), 'me');
    expect(row.containsKey('paid_by'), isFalse);
  });
}
