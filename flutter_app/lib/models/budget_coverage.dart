import '../services/salary_cycle_service.dart';
import 'models.dart';
import 'nafaqah.dart' show kWifePersonal;

/// Which categories have an active budget in which salary cycle.
///
/// An expense in a category the household keeps inactive, or has not
/// budgeted this cycle, is still filed under that category: it counts in the
/// totals and reports but in no budget (owner decision 2026-11-05, migration
/// 20261105001000). The app marks such an expense "Unbudgeted" and offers to
/// give the category a budget.
///
/// Which rows are marked follows [TransactionProvider.unbudgetedCycleSpend]
/// (the dashboard hero), [TransactionProvider.totalCycleSpend] and the server's
/// reports: a row without a cycle key is in the cycle of its date, and a row
/// without a category is in no category budget. So the hero's unbudgeted
/// spending is exactly the sum of the open cycle's marked rows.
///
/// A past cycle in which the household had no active budget at all is not
/// marked: it had not started budgeting, and marking every expense of it would
/// say nothing. The open cycle is always marked, as the hero counts it.
class BudgetCoverage {
  const BudgetCoverage._(this._keys, this._cycles, {this.loaded = true});

  /// Not loaded yet (or the load failed): nothing is marked.
  static const BudgetCoverage unknown = BudgetCoverage._(<String>{}, <String>{}, loaded: false);

  final Set<String> _keys;

  /// Cycles with at least one active budget.
  final Set<String> _cycles;

  /// Whether the budget rows were read; until then [isUnbudgeted] is false.
  final bool loaded;

  /// From `budgets` rows (`category_code`, `cycle_key`, `month`, `is_active`).
  /// A NULL `is_active` is active, as [Budget.fromMap] reads it; a legacy row
  /// without a cycle key belongs to the cycle of its month.
  factory BudgetCoverage.fromRows(Iterable<Map<String, dynamic>> rows) {
    final keys = <String>{};
    final cycles = <String>{};
    for (final r in rows) {
      if (r['is_active'] == false) continue;
      final code = r['category_code'] as String?;
      if (code == null || code.isEmpty) continue;
      var cycle = r['cycle_key'] as String?;
      if (cycle == null || cycle.isEmpty) {
        final month = r['month'] as String? ?? '';
        cycle = month.length >= 7 ? month.substring(0, 7) : null;
      }
      if (cycle == null) continue;
      keys.add(_key(code, cycle));
      cycles.add(cycle);
    }
    return BudgetCoverage._(keys, cycles);
  }

  static String _key(String code, String cycle) => '$code|$cycle';

  bool covers(String categoryCode, String cycleKey) => _keys.contains(_key(categoryCode, cycleKey));

  /// Spending that category budgets count: not a settlement between members
  /// and not the wife's personal purchase (her allowance only). The same
  /// exclusions as the budget triggers, [TransactionProvider], the account
  /// service and the cycle report.
  static bool countsInBudgets(Transaction t) => !t.isSettlement && t.nafaqahClass != kWifePersonal;

  /// The cycle [t] counts in: its cycle key, or for a row without one yet
  /// (offline draft) the cycle of its date, as [TransactionProvider] reads it.
  static String effectiveCycleKey(Transaction t, {int? paydayDay}) {
    final key = t.cycleKey;
    if (key != null && key.isNotEmpty) return key;
    return SalaryCycleService.cycleKeyForInstant(t.timestamp, paydayDay: paydayDay);
  }

  /// Whether [t] is in the open salary cycle ([currentCycleKey], by default the
  /// device's current one).
  static bool isCurrentCycle(Transaction t, {int? paydayDay, String? currentCycleKey}) =>
      effectiveCycleKey(t, paydayDay: paydayDay) ==
      (currentCycleKey ?? SalaryCycleService.currentCycle(paydayDay: paydayDay).key);

  /// An expense budgets would count, with no active budget of its category for
  /// its cycle; see the class comment for rows without a category or cycle key,
  /// and for past cycles.
  bool isUnbudgeted(Transaction t, {int? paydayDay, String? currentCycleKey}) {
    if (!loaded || !countsInBudgets(t)) return false;
    final cycle = effectiveCycleKey(t, paydayDay: paydayDay);
    final current = currentCycleKey ?? SalaryCycleService.currentCycle(paydayDay: paydayDay).key;
    if (cycle != current && !_cycles.contains(cycle)) return false;
    final code = t.categoryCode;
    if (code == null || code.isEmpty) return true;
    return !covers(code, cycle);
  }
}
