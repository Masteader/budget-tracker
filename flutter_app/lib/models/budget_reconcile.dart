import '../providers/transaction_provider.dart';
import 'models.dart';

/// Reconciles raw category budgets with actual transaction spending for the cycle.
/// Single source of truth for both Dashboard and Budget Management screens (Rule 02 §3).
/// Uses [TransactionProvider.cycleSpendForCategory] directly (never max with stale spent_amount)
/// and strictly excludes wife_personal expenses and debt settlements.
List<Budget> reconcileCycleBudgets(
  List<Budget> raw,
  TransactionProvider tx,
  String cycleKey,
  int paydayDay,
) {
  if (tx.isLoading || tx.transactions.isEmpty) return raw;
  return raw.map((b) {
    final realSpent = tx.cycleSpendForCategory(
      b.categoryCode,
      cycleKey,
      paydayDay: paydayDay,
    );
    return b.copyWith(
      spentAmount: realSpent,
      remainingAmount: b.allocatedAmount - realSpent,
    );
  }).toList();
}
