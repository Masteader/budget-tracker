import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/services/notifications/reminder_planner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringBillItem _bill(String merchant, int day, {String status = 'UPCOMING', String cadence = 'monthly'}) =>
    RecurringBillItem(
      merchant: merchant,
      normalizedMerchant: merchant,
      categoryCode: 'OPEX-UTILITIES',
      averageAmount: 230,
      expectedDayOfMonth: day,
      status: status,
      cadence: cadence,
    );

InstallmentPlan _plan({String frequency = 'monthly', String? nextDueAt, int paid = 1, int day = 27}) =>
    InstallmentPlan.fromJson({
      'id': 'p1',
      'household_id': 'h',
      'merchant': 'Jarir',
      'provider': 'Tabby',
      'total_amount': 400,
      'installment_count': 4,
      'monthly_amount': 100,
      'paid_installments': paid,
      'day_of_month': day,
      'start_date': '2026-10-01',
      'status': 'ACTIVE',
      'frequency': frequency,
      'next_due_at': nextDueAt,
    });

String _riyadh(DateTime utc) {
  final r = utc.add(const Duration(hours: 3));
  return '${r.year}-${r.month.toString().padLeft(2, '0')}-${r.day.toString().padLeft(2, '0')} ${r.hour}:${r.minute.toString().padLeft(2, '0')}';
}

void main() {
  final en = AppLocalizations(const Locale('en'));
  // 21 Oct 2026, 10:00 in Riyadh (07:00 UTC).
  final now = DateTime.utc(2026, 10, 21, 7);

  List<PlannedReminder> plan({
    DateTime? at,
    int payday = 27,
    List<RecurringBillItem> bills = const [],
    List<InstallmentPlan> plans = const [],
    Set<ReminderType> enabled = const {...ReminderType.values},
    AppLocalizations? l,
  }) =>
      const ReminderPlanner().plan(
        now: at ?? now,
        paydayDay: payday,
        bills: bills,
        plans: plans,
        enabled: enabled,
        l: l ?? en,
      );

  group('payday check-in', () {
    test('fires at 09:00 Riyadh on each upcoming household payday', () {
      final r = plan(enabled: {ReminderType.payday});
      expect(r.map((e) => _riyadh(e.fireAtUtc)).take(2), ['2026-10-27 9:00', '2026-11-27 9:00']);
      expect(r.first.title, "It's payday");
      expect(r.every((e) => e.type == ReminderType.payday), isTrue);
    });

    test('uses the household payday, clamped to short months, never a hard-coded 27th', () {
      final r = plan(enabled: {ReminderType.payday}, payday: 30, at: DateTime.utc(2027, 1, 31, 7));
      expect(r.map((e) => _riyadh(e.fireAtUtc)).take(2), ['2027-02-28 9:00', '2027-03-30 9:00']);
    });

    test('on payday before 09:00 today is included; after 09:00 it is not', () {
      final early = plan(enabled: {ReminderType.payday}, at: DateTime.utc(2026, 10, 27, 4)); // 07:00 Riyadh
      expect(_riyadh(early.first.fireAtUtc), '2026-10-27 9:00');
      final late = plan(enabled: {ReminderType.payday}, at: DateTime.utc(2026, 10, 27, 8)); // 11:00 Riyadh
      expect(_riyadh(late.first.fireAtUtc), '2026-11-27 9:00');
    });
  });

  test('"cycle ends in 3 days" fires three days before each payday', () {
    final r = plan(enabled: {ReminderType.cycleEnd});
    expect(r.map((e) => _riyadh(e.fireAtUtc)).take(2), ['2026-10-24 9:00', '2026-11-24 9:00']);
    expect(r.first.title, '3 days until payday');
    expect(r.first.body, contains('26 Oct'));
  });

  group('recurring bills', () {
    test('each bill on its expected day, this month and next', () {
      final r = plan(enabled: {ReminderType.bill}, bills: [_bill('STC', 25), _bill('SEC', 5)]);
      expect(r.map((e) => '${_riyadh(e.fireAtUtc)} ${e.title}'), [
        '2026-10-25 9:00 stc Telecom is due today',
        '2026-11-05 9:00 SEC is due today',
        '2026-11-25 9:00 stc Telecom is due today',
        '2026-12-05 9:00 SEC is due today',
      ]);
      expect(r.first.body, contains('SAR 230.00'));
    });

    test('a bill already paid this cycle is reminded next time only', () {
      final r = plan(enabled: {ReminderType.bill}, bills: [_bill('STC', 25, status: 'PAID_THIS_CYCLE')]);
      expect(_riyadh(r.first.fireAtUtc), '2026-11-25 9:00');
    });

    test('day 31 is clamped to the end of short months', () {
      final r = plan(enabled: {ReminderType.bill}, bills: [_bill('Rent', 31)], at: DateTime.utc(2026, 11, 2, 7));
      expect(r.map((e) => _riyadh(e.fireAtUtc)), ['2026-11-30 9:00', '2026-12-31 9:00']);
    });
  });

  group('installments', () {
    test('bi-weekly from next_due_at', () {
      final r = plan(enabled: {ReminderType.installment}, plans: [_plan(frequency: 'biweekly', nextDueAt: '2026-10-29')]);
      expect(r.map((e) => _riyadh(e.fireAtUtc)), ['2026-10-29 9:00', '2026-11-12 9:00', '2026-11-26 9:00']);
      expect(r.first.title, 'Tabby installment due today');
      expect(r.first.body, contains('SAR 100.00'));
      expect(r.first.body, contains('Jarir'));
    });

    test('falls back to day_of_month monthly when next_due_at is absent', () {
      final r = plan(enabled: {ReminderType.installment}, plans: [_plan(day: 27, paid: 2)]);
      expect(r.map((e) => _riyadh(e.fireAtUtc)), ['2026-10-27 9:00', '2026-11-27 9:00']);
    });

    test('a completed plan is not reminded', () {
      expect(plan(enabled: {ReminderType.installment}, plans: [_plan(paid: 4)]), isEmpty);
    });
  });

  test('disabled types are skipped, ids are unique and the list is time-ordered', () {
    final all = plan(bills: [_bill('STC', 25)], plans: [_plan(frequency: 'biweekly', nextDueAt: '2026-10-29')]);
    expect(all.map((e) => e.type).toSet(), {...ReminderType.values});
    expect(all.map((e) => e.id).toSet().length, all.length);
    for (var i = 1; i < all.length; i++) {
      expect(all[i].fireAtUtc.isBefore(all[i - 1].fireAtUtc), isFalse);
    }
    expect(all.every((e) => e.fireAtUtc.isAfter(now)), isTrue);
    expect(all.every((e) => e.fireAtUtc.isBefore(now.add(const Duration(days: ReminderPlanner.horizonDays + 1)))), isTrue);
    expect(plan(enabled: const {}, bills: [_bill('STC', 25)]), isEmpty);
    expect(all.length, lessThanOrEqualTo(ReminderPlanner.maxReminders));
  });

  test('texts come from AppLocalizations (Arabic and Urdu)', () {
    for (final lang in ['ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));
      final r = plan(l: l, bills: [_bill('STC', 25)], plans: [_plan(nextDueAt: '2026-10-29')]);
      for (final e in r) {
        expect(RegExp('[؀-ۿ]').hasMatch(e.title), isTrue, reason: '$lang ${e.type}');
        expect(e.title.contains('{'), isFalse);
        expect(e.body.contains('{'), isFalse);
      }
    }
  });
}
