/// "Left until payday": the dashboard's one figure, one daily amount and one
/// verdict (UX-07). Every number in the hero comes from here; nothing else on
/// the dashboard computes a second pace or verdict.
library;

import 'models.dart';

/// The single verdict of the hero.
enum PaydayVerdict {
  /// The money lasts until payday at the current pace.
  onTrack,

  /// At the current pace the money runs out before payday ([PaydayOutlook.runOutDate]).
  runsOut,

  /// More was spent than the income (or the budgets, without an income).
  overspent,
}

/// Fixed lump-sum categories (rent, utilities): they do not set the daily
/// pace, and what is still to pay of them is not available for daily spending.
const Set<String> kFixedCostCategoryCodes = {
  'HOUSING-RENT',
  'HOUSING',
  'OPEX-HOUSING',
  'OPEX-UTILITIES',
  'UTILITIES-BILLS',
};

class PaydayOutlook {
  /// The base is the household's monthly income (else the cycle's budgets).
  final bool incomeBased;

  /// Income for the cycle, or the total budgeted without an income.
  final double base;
  final double totalAllocated;
  final double totalSpent;

  /// [base] − [totalSpent]; negative when overspent.
  final double left;

  /// Days from today to the last day of the cycle, both included; 0 once the
  /// cycle is over.
  final int daysLeft;

  /// What can be spent per day until payday: what is left, minus what is still
  /// to pay of fixed costs, over [daysLeft]. 0 when nothing is left.
  final double safeDaily;

  final PaydayVerdict verdict;

  /// When the money runs out at the current pace ([PaydayVerdict.runsOut]).
  final DateTime? runOutDate;

  const PaydayOutlook({
    required this.incomeBased,
    required this.base,
    required this.totalAllocated,
    required this.totalSpent,
    required this.left,
    required this.daysLeft,
    required this.safeDaily,
    required this.verdict,
    this.runOutDate,
  });

  /// The selected cycle is over (a past cycle).
  bool get isClosed => daysLeft == 0;

  /// Spent ÷ base, not clamped (1.31 = 131%).
  double get spentShare => base > 0 ? totalSpent / base : (totalSpent > 0 ? 1.0 : 0.0);

  /// [today], [cycleStart] and [cycleEnd] are calendar dates (Riyadh). An
  /// [operatingCash] or [monthlyIncome] of null or 0 falls back to the budgets as the base.
  factory PaydayOutlook.compute({
    required List<Budget> budgets,
    double? monthlyIncome,
    double? operatingCash,
    required DateTime today,
    required DateTime cycleStart,
    required DateTime cycleEnd,
  }) {
    DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final t = day(today);
    final start = day(cycleStart);
    final end = day(cycleEnd);

    final totalAllocated = budgets.fold(0.0, (s, b) => s + b.allocatedAmount);
    final totalSpent = budgets.fold(0.0, (s, b) => s + b.spentAmount);
    final hasOperatingCash = (operatingCash ?? 0) > 0;
    final hasIncome = (monthlyIncome ?? 0) > 0;
    final incomeBased = hasIncome || hasOperatingCash;

    // Total cycle income / funding capacity:
    // If monthlyIncome is known (> 0), base is monthlyIncome.
    // Otherwise, if operating accounts exist, base reflects initial cycle capacity (operating cash + spent).
    // Otherwise, falls back to totalAllocated budgets.
    final base = hasIncome
        ? monthlyIncome!
        : (hasOperatingCash ? (operatingCash! + totalSpent) : totalAllocated);

    // Left represents what is actually available right now until payday:
    // If live bank accounts exist, the balance in the bank IS what is left (it already reflects all spent transactions).
    // Otherwise, left is base - totalSpent.
    final left = hasOperatingCash ? operatingCash! : (base - totalSpent);

    double variableSpent = 0;
    double fixedStillDue = 0;
    for (final b in budgets) {
      if (kFixedCostCategoryCodes.contains(b.categoryCode)) {
        final due = b.allocatedAmount - b.spentAmount;
        if (due > 0) fixedStillDue += due;
      } else {
        variableSpent += b.spentAmount;
      }
    }

    final cycleDays = end.difference(start).inDays + 1;
    final daysLeft = t.isAfter(end) ? 0 : (end.difference(t).inDays + 1).clamp(0, cycleDays);
    final daysElapsed = (t.difference(start).inDays + 1).clamp(1, cycleDays);

    final available = left - fixedStillDue;
    final safeDaily = daysLeft > 0 && available > 0 ? available / daysLeft : 0.0;

    // Halala precision: spending exactly the base is not "over".
    if (left <= -0.005) {
      return PaydayOutlook(
        incomeBased: incomeBased,
        base: base,
        totalAllocated: totalAllocated,
        totalSpent: totalSpent,
        left: left,
        daysLeft: daysLeft,
        safeDaily: 0,
        verdict: PaydayVerdict.overspent,
      );
    }

    DateTime? runOut;
    final pace = variableSpent / daysElapsed;
    if (daysLeft > 0 && pace > 0) {
      final daysOfMoney = (left / pace).floor();
      if (daysOfMoney < daysLeft) runOut = t.add(Duration(days: daysOfMoney));
    }
    return PaydayOutlook(
      incomeBased: incomeBased,
      base: base,
      totalAllocated: totalAllocated,
      totalSpent: totalSpent,
      left: left,
      daysLeft: daysLeft,
      safeDaily: safeDaily,
      verdict: runOut != null ? PaydayVerdict.runsOut : PaydayVerdict.onTrack,
      runOutDate: runOut,
    );
  }
}
