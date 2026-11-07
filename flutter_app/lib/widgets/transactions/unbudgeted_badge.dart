import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show supabase;
import '../../models/budget_coverage.dart';
import '../../providers/budget_provider.dart';
import '../../theme/app_themes.dart';
import '../sub_budget_allocation_dialog.dart';

/// Reads which categories have an active budget in which cycle.
typedef BudgetCoverageLoader = Future<BudgetCoverage> Function(String householdId);

/// Gives [categoryCode] a budget; true when one was saved.
typedef CategoryBudgetActivator = Future<bool> Function(
  BuildContext context,
  String householdId,
  String categoryCode,
);

/// The household's budget rows (members read their household's budgets).
Future<BudgetCoverage> loadBudgetCoverage(String householdId) async {
  final rows = await supabase
      .from('budgets')
      .select('category_code, cycle_key, month, is_active')
      .eq('household_id', householdId);
  return BudgetCoverage.fromRows((rows as List).map((r) => Map<String, dynamic>.from(r as Map)));
}

/// The existing budget dialog for [categoryCode] in the open cycle. Saving it
/// gives the category a budget and makes it active; what the cycle already
/// spent in it counts in that budget at once (migration 20261105001000).
///
/// The open cycle is the server's: the current cycle [BudgetProvider] loaded,
/// or none, so the server resolves the household's payday cycle. The phone's
/// cached payday can be stale (first launch, a failed fetch, a payday changed
/// on another device) and would save into the wrong cycle.
Future<bool> activateAndBudgetCategory(BuildContext context, String householdId, String categoryCode) async {
  final saved = await SubBudgetAllocationDialog.show(
    context,
    householdId: householdId,
    categoryCode: categoryCode,
    categoryName: context.trCat(categoryCode),
    cycleKey: _serverOpenCycleKey(context),
  );
  return saved == true;
}

/// The current cycle the server listed for the household, if loaded.
String? _serverOpenCycleKey(BuildContext context) {
  final BudgetProvider provider;
  try {
    provider = Provider.of<BudgetProvider>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
  for (final cycle in provider.cycles) {
    if (cycle.isCurrent && cycle.cycleKey.isNotEmpty) return cycle.cycleKey;
  }
  return null;
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
