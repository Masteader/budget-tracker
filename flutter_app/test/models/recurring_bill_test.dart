import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/recurring_bill.dart';

void main() {
  group('RecurringBill Model Tests', () {
    test('Parses RecurringBillsSummary and nested bills from API JSON', () {
      final json = {
        'cycle_key': '2026-10',
        'cycle_label': 'October 2026 Budget',
        'total_recurring_monthly': 850.0,
        'paid_this_cycle': 400.0,
        'reserved_amount': 450.0,
        'bills': [
          {
            'merchant': 'STC Postpaid',
            'normalized_merchant': 'STC',
            'category_code': 'OPEX-UTILITIES',
            'average_amount': 400.0,
            'expected_day_of_month': 28,
            'status': 'PAID_THIS_CYCLE',
            'last_paid_date': '2026-09-28',
            'paid_amount': 400.0,
            'cadence': 'monthly',
          },
          {
            'merchant': 'Saudi Electricity',
            'normalized_merchant': 'Saudi Electricity',
            'category_code': 'OPEX-UTILITIES',
            'average_amount': 450.0,
            'expected_day_of_month': 10,
            'status': 'UPCOMING',
            'last_paid_date': '2026-09-10',
            'cadence': 'monthly',
          },
        ],
      };

      final summary = RecurringBillsSummary.fromMap(json);

      expect(summary.cycleKey, equals('2026-10'));
      expect(summary.totalRecurringMonthly, equals(850.0));
      expect(summary.paidThisCycle, equals(400.0));
      expect(summary.reservedAmount, equals(450.0));
      expect(summary.bills.length, equals(2));

      final stc = summary.bills[0];
      expect(stc.normalizedMerchant, equals('STC'));
      expect(stc.isPaid, isTrue);
      expect(stc.isUpcoming, isFalse);

      final sec = summary.bills[1];
      expect(sec.normalizedMerchant, equals('Saudi Electricity'));
      expect(sec.isPaid, isFalse);
      expect(sec.isUpcoming, isTrue);
    });
  });
}
