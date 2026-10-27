import 'package:flutter/foundation.dart';
import '../main.dart';
import 'api_service.dart';
import 'salary_cycle_service.dart';

/// Autonomously inspects and repairs any corrupted budget allocation cycles.
/// Handles cases where a prior cycle's rows (e.g. month: 2026-10-01) had their
/// cycle_key hijacked or carried over stale non-zero spent_amounts into a fresh cycle.
class BudgetRepairService {
  BudgetRepairService._();
  static final BudgetRepairService instance = BudgetRepairService._();

  bool _isRepairing = false;

  Future<void> repairHouseholdBudgets(String householdId) async {
    if (_isRepairing || householdId.isEmpty) return;
    _isRepairing = true;
    try {
      final rows = await supabase
          .from('budgets')
          .select()
          .eq('household_id', householdId);

      if (rows.isEmpty) return;

      final curCycle = SalaryCycleService.currentCycle();
      final curCycleKey = curCycle.key;
      final curMonthStr = '$curCycleKey-01';

      // 1. Check for rows where cycle_key is curCycleKey but month belongs to a prior cycle
      // e.g., month == '2026-10-01' but cycle_key was rewritten to '2026-11'
      for (final r in (rows as List)) {
        final month = r['month'] as String? ?? '';
        final cycleKey = r['cycle_key'] as String? ?? '';
        final id = r['id'] as String;
        final catCode = r['category_code'] as String;

        if (cycleKey == curCycleKey && month.isNotEmpty && month != curMonthStr) {
          final priorCycleKey = month.length >= 7 ? month.substring(0, 7) : '2026-10';
          final hasPriorRow = rows.any((other) =>
              other['id'] != id &&
              other['category_code'] == catCode &&
              other['cycle_key'] == priorCycleKey);

          if (!hasPriorRow) {
            // Restore this row to its original prior cycle so past transactions are preserved
            await supabase.from('budgets').update({
              'cycle_key': priorCycleKey,
            }).eq('id', id);

            // Clone active allocations into the current cycle with 0.0 spent
            await supabase.from('budgets').insert({
              'household_id': householdId,
              'category_code': catCode,
              'allocated_amount': r['allocated_amount'],
              'spent_amount': 0.0,
              'remaining_amount': r['allocated_amount'],
              'month': curMonthStr,
              'cycle_key': curCycleKey,
              'account_id': r['account_id'],
              'sub_allocations': r['sub_allocations'] ?? {},
              'is_active': r['is_active'] ?? true,
            });
          } else {
            // If the prior row already exists, just update this row's month and spent_amount
            await supabase.from('budgets').update({
              'month': curMonthStr,
              'spent_amount': 0.0,
            }).eq('id', id);
          }
        }
      }

      // 2. Request backend recalculation to ensure triggers and database rows match transactions
      try {
        await ApiService.instance.recalculateBudgets(householdId, cycleKey: curCycleKey);
      } catch (_) {}
    } catch (e) {
      debugPrint('[BudgetRepairService] Repair error (non-fatal): $e');
    } finally {
      _isRepairing = false;
    }
  }
}
