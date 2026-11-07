import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show supabase;
import '../../models/budget_coverage.dart';
import '../../theme/app_themes.dart';
import '../sub_budget_allocation_dialog.dart';

/// Reads which categories have an active budget in which cycle.
typedef BudgetCoverageLoader = Future<BudgetCoverage> Function(String householdId);

/// Gives [categoryCode] a budget in [cycleKey] (the expense's own cycle, or
/// null for the household's open cycle); true when one was saved.
typedef CategoryBudgetActivator = Future<bool> Function(
  BuildContext context,
  String householdId,
  String categoryCode,
  String? cycleKey,
);

/// The household's budget rows (members read their household's budgets).
Future<BudgetCoverage> loadBudgetCoverage(String householdId) async {
  final rows = await supabase
      .from('budgets')
      .select('category_code, cycle_key, month, is_active')
      .eq('household_id', householdId);
  return BudgetCoverage.fromRows((rows as List).map((r) => Map<String, dynamic>.from(r as Map)));
}

/// The existing budget dialog for [categoryCode] in the expense's cycle.
/// Saving it gives the category a budget and makes it active; what the cycle
/// already spent in it counts in that budget at once (migration 20261105001000).
///
/// [cycleKey] is the expense's own `cycle_key`, which the server set and the
/// caller checked is the open cycle. Without one, none is sent and the server
/// resolves the household's payday cycle. The phone's cached cycles are not
/// used: they can be stale after payday and would save into a closed cycle.
Future<bool> activateAndBudgetCategory(
  BuildContext context,
  String householdId,
  String categoryCode,
  String? cycleKey,
) async {
  final saved = await SubBudgetAllocationDialog.show(
    context,
    householdId: householdId,
    categoryCode: categoryCode,
    categoryName: context.trCat(categoryCode),
    cycleKey: cycleKey != null && cycleKey.isNotEmpty ? cycleKey : null,
  );
  return saved == true;
}

/// "Unbudgeted": an expense in a category with no active budget this cycle.
/// It counts in the totals, in no budget.
class UnbudgetedBadge extends StatelessWidget {
  const UnbudgetedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.warnText;
    return Container(
      key: const ValueKey('feed_badge_unbudgeted'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.money_off_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              context.tr('unbudgeted_badge'),
              style: GoogleFonts.outfit(color: color, fontSize: 12, fontWeight: FontWeight.w600)
                  .copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
            ),
          ),
        ],
      ),
    );
  }
}

/// The edit sheet's explanation. For an expense of the open cycle: the action
/// for an admin ([onActivate]) or, for a member, who can give the category a
/// budget. For an older expense ([pastCycleLabel], its own cycle): a plain note
/// with no action, because budgeting now cannot reach that cycle.
class UnbudgetedNotice extends StatelessWidget {
  final VoidCallback? onActivate;

  /// The expense's own cycle, when it is not the open one.
  final String? pastCycleLabel;

  const UnbudgetedNotice({super.key, this.onActivate, this.pastCycleLabel});

  @override
  Widget build(BuildContext context) {
    final color = context.warnText;
    final past = pastCycleLabel;
    if (past != null) {
      return Container(
        key: const Key('edit_unbudgeted_notice'),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const UnbudgetedBadge(),
            const SizedBox(height: 6),
            Text(
              context.trArgs('unbudgeted_notice_past', {'cycle': past}),
              style: TextStyle(color: context.textPrimary, fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const Key('edit_unbudgeted_notice'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UnbudgetedBadge(),
          const SizedBox(height: 6),
          Text(
            context.tr('unbudgeted_notice'),
            style: TextStyle(color: context.textPrimary, fontSize: 12.5),
          ),
          if (onActivate != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('edit_unbudgeted_activate'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: context.accentText),
                onPressed: onActivate,
                icon: const Icon(Icons.add_chart_rounded, size: 18),
                label: Text(context.tr('unbudgeted_activate')),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                context.tr('unbudgeted_admin_only'),
                style: TextStyle(color: context.textSecondary, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }
}
