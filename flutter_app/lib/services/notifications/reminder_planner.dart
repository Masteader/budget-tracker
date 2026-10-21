/// Which local reminders to schedule, computed on the device from data the
/// app already has (R11): the household payday, the recurring bills and the
/// installment plans. Pure: the clock, data and texts are passed in.
///
/// Every reminder fires at 09:00 Asia/Riyadh (UTC+3, no DST) on its day.
/// Reminders are rebuilt whenever the inputs change, so only the next
/// [horizonDays] are scheduled, at most [maxReminders] (iOS keeps 64).
library;

import '../../l10n/app_localizations.dart';
import '../../models/installment_plan.dart';
import '../../models/recurring_bill.dart';
import '../salary_cycle_service.dart';

enum ReminderType { payday, cycleEnd, bill, installment }

class PlannedReminder {
  final int id;
  final ReminderType type;
  final DateTime fireAtUtc;
  final String title;
  final String body;

  const PlannedReminder({
    required this.id,
    required this.type,
    required this.fireAtUtc,
    required this.title,
    required this.body,
  });

  @override
  String toString() => 'PlannedReminder($id, ${type.name}, ${fireAtUtc.toIso8601String()}, $title)';
}

class ReminderPlanner {
  const ReminderPlanner();

  static const int fireHourRiyadh = 9;
  static const int horizonDays = 62;
  static const int maxReminders = 48;

  /// Bill occurrences scheduled per bill (this month's and the next one).
  static const int occurrencesPerBill = 2;

  /// The UTC instant of 09:00 in Riyadh on calendar [date].
  static DateTime fireAt(DateTime date) => DateTime.utc(date.year, date.month, date.day, fireHourRiyadh)
      .subtract(SalaryCycleService.riyadhOffset);

  List<PlannedReminder> plan({
    required DateTime now,
    required int paydayDay,
    required List<RecurringBillItem> bills,
    required List<InstallmentPlan> plans,
    required Set<ReminderType> enabled,
    required AppLocalizations l,
  }) {
    final today = SalaryCycleService.riyadhToday(now: now);
    final last = today.add(const Duration(days: horizonDays));
    final nowUtc = now.toUtc();
    bool inWindow(DateTime date) => !date.isAfter(last) && fireAt(date).isAfter(nowUtc);

    final drafts = <({ReminderType type, DateTime date, String title, String body})>[];
    void add(ReminderType type, DateTime date, String title, String body) {
      if (enabled.contains(type) && inWindow(date)) drafts.add((type: type, date: date, title: title, body: body));
    }

    // Payday and the nudge three days before it, for the current and the next
    // cycles inside the window.
    final current = SalaryCycleService.cycleForInstant(now, paydayDay: paydayDay);
    var cycle = current;
    for (var i = 0; i < 4; i++) {
      final payday = cycle.start;
      add(ReminderType.payday, payday, l.get('notif_payday_title'), l.get('notif_payday_body'));
      final next = cycle.end.add(const Duration(days: 1));
      add(
        ReminderType.cycleEnd,
        next.subtract(const Duration(days: 3)),
        l.get('notif_cycle_end_title'),
        l.format('notif_cycle_end_body', {'date': l.date(cycle.end, 'd MMM')}),
      );
      cycle = SalaryCycleService.cycleForDate(next.year, next.month, next.day, paydayDay: paydayDay);
    }

    // Recurring bills on their expected day of the month. A bill already
    // paid in the current cycle is reminded at its next occurrence only.
    for (final bill in bills) {
      if (bill.cadence != 'monthly') continue;
      var found = 0;
      for (var offset = 0; offset < 4 && found < occurrencesPerBill; offset++) {
        final date = _monthDay(today.year, today.month + offset, bill.expectedDayOfMonth);
        if (date.isBefore(today)) continue;
        if (bill.isPaid && current.containsDate(date)) continue;
        if (!inWindow(date)) continue;
        found++;
        add(
          ReminderType.bill,
          date,
          l.format('notif_bill_title', {'merchant': l.merchant(bill.merchant)}),
          l.format('notif_bill_body', {'amount': l.sar(bill.averageAmount)}),
        );
      }
    }

    // Installments: next_due_at and the plan's frequency, or day_of_month.
    for (final p in plans) {
      for (final date in p.dueDates(today: today, max: 4)) {
        add(
          ReminderType.installment,
          date,
          l.format('notif_installment_title', {'provider': p.provider == 'Bank' ? l.get('bnpl_provider_bank_other') : p.provider}),
          l.format('notif_installment_body', {'amount': l.sar(p.installmentAmount), 'merchant': l.merchant(p.merchant)}),
        );
      }
    }

    drafts.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.type.index.compareTo(b.type.index);
    });
    final counters = <ReminderType, int>{};
    return [
      for (final d in drafts.take(maxReminders))
        PlannedReminder(
          id: (d.type.index + 1) * 1000 + (counters[d.type] = (counters[d.type] ?? 0) + 1),
          type: d.type,
          fireAtUtc: fireAt(d.date),
          title: d.title,
          body: d.body,
        ),
    ];
  }

  static DateTime _monthDay(int year, int month, int day) {
    final y = year + (month - 1) ~/ 12;
    final m = (month - 1) % 12 + 1;
    final lastDay = DateTime.utc(y, m + 1, 0).day;
    final d = day.clamp(1, 31);
    return DateTime.utc(y, m, d < lastDay ? d : lastDay);
  }
}
