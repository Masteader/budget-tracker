import 'models.dart';
import 'nafaqah.dart' show kWifePersonal;

/// Which categories have an active budget in which salary cycle.
///
/// An expense in a category the household keeps inactive, or has not
/// budgeted this cycle, is still filed under that category: it counts in the
/// totals and reports but in no budget (owner decision 2026-11-05, migration
/// 20261105001000). The app marks such an expense "Unbudgeted" and offers to
/// give the category a budget.
class BudgetCoverage {
  const BudgetCoverage._(this._keys, {this.loaded = true});

  /// Not loaded yet (or the load failed): nothing is marked.
  static const BudgetCoverage unknown = BudgetCoverage._(<String>{}, loaded: false);

  final Set<String> _keys;

  /// Whether the budget rows were read; until then [isUnbudgeted] is false.
  final bool loaded;

  /// From `budgets` rows (`category_code`, `cycle_key`, `month`, `is_active`).
  /// A NULL `is_active` is active, as [Budget.fromMap] reads it; a legacy row
  /// without a cycle key belongs to the cycle of its month.
  factory BudgetCoverage.fromRows(Iterable<Map<String, dynamic>> rows) {
    final keys = <String>{};
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
    }
    return BudgetCoverage._(keys);
  }

  static String _key(String code, String cycle) => '$code|$cycle';

  bool covers(String categoryCode, String cycleKey) => _keys.contains(_key(categoryCode, cycleKey));

  /// Spending that category budgets count: not a settlement between members
  /// and not the wife's personal purchase (her allowance only). The same
  /// exclusions as the budget triggers, [TransactionProvider], the account
  /// service and the cycle report.
  static bool countsInBudgets(Transaction t) => !t.isSettlement && t.nafaqahClass != kWifePersonal;

  /// An expense budgets would count, with no active budget of its category
  /// for its cycle. A row without a cycle key yet (offline draft) is not marked.
  bool isUnbudgeted(Transaction t) {
    if (!loaded || !countsInBudgets(t)) return false;
    final code = t.categoryCode;
    final cycle = t.cycleKey;
    if (code == null || code.isEmpty || cycle == null || cycle.isEmpty) return false;
    return !covers(code, cycle);
  }
}
