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

    group('BNPL schedule (frequency + next_due_at)', () {
      InstallmentPlan plan({
        String frequency = 'monthly',
        String? nextDueAt,
        int paid = 1,
        int count = 4,
        int day = 27,
        String start = '2026-10-01',
        String status = 'ACTIVE',
      }) =>
          InstallmentPlan.fromJson({
            'id': 'p',
            'household_id': 'h',
            'merchant': 'Jarir',
            'provider': 'Tabby',
            'total_amount': 400,
            'installment_count': count,
            'monthly_amount': 100,
            'paid_installments': paid,
            'day_of_month': day,
            'start_date': start,
            'status': status,
            'frequency': frequency,
            'next_due_at': nextDueAt,
          });
      final today = DateTime.utc(2026, 10, 21);
      String iso(DateTime d) => d.toIso8601String().substring(0, 10);

      test('parses frequency and next_due_at; absent means monthly and null', () {
        final p = plan(frequency: 'biweekly', nextDueAt: '2026-10-29');
        expect(p.frequency, 'biweekly');
        expect(p.isBiweekly, isTrue);
        expect(p.nextDueAt, DateTime.utc(2026, 10, 29));
        final legacy = InstallmentPlan.fromJson({'id': 'x', 'total_amount': 10, 'start_date': '2026-10-01'});
        expect(legacy.frequency, 'monthly');
        expect(legacy.nextDueAt, isNull);
        expect(plan(frequency: 'weird').frequency, 'monthly');
        expect(p.toJson()['frequency'], 'biweekly');
        expect(p.toJson()['next_due_at'], '2026-10-29');
      });

      test('biweekly from next_due_at: every 14 days, only the remaining installments', () {
        final dates = plan(frequency: 'biweekly', nextDueAt: '2026-10-29', paid: 1).dueDates(today: today);
        expect(dates.map(iso), ['2026-10-29', '2026-11-12', '2026-11-26']);
      });

      test('monthly from next_due_at keeps the day, clamped to short months', () {
        final dates = plan(nextDueAt: '2027-01-31', paid: 1).dueDates(today: today);
        expect(dates.map(iso), ['2027-01-31', '2027-02-28', '2027-03-31']);
      });

      test('without next_due_at: monthly falls back to day_of_month from today', () {
        expect(plan(day: 27, paid: 2).dueDates(today: today).map(iso), ['2026-10-27', '2026-11-27']);
        expect(plan(day: 5, paid: 3).dueDates(today: today).map(iso), ['2026-11-05']);
        expect(plan(day: 21, paid: 3).dueDates(today: today).map(iso), ['2026-10-21']);
      });

      test('without next_due_at: biweekly counts from the start date', () {
        // Paid at purchase (1 of 4) on 1 Oct: next is 15 Oct (past), then 29 Oct, 12 Nov.
        final dates = plan(frequency: 'biweekly', paid: 1, start: '2026-10-01').dueDates(today: today);
        expect(dates.map(iso), ['2026-10-15', '2026-10-29', '2026-11-12']);
        expect(iso(plan(frequency: 'biweekly', paid: 1, start: '2026-10-01').nextDueDate(today: today)!), '2026-10-15');
      });

      test('completed plans have nothing due', () {
        expect(plan(paid: 4).dueDates(today: today), isEmpty);
        expect(plan(status: 'COMPLETED', paid: 2).nextDueDate(today: today), isNull);
      });
    });
  });
}
