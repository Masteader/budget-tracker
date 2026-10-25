import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';

/// The overspent categories right under the hero (UX-08): the three furthest
/// over budget with the amount over, and "Show all" to the category list.
/// Renders nothing while every category is within budget.
class OverBudgetAlerts extends StatelessWidget {
  final List<Budget> budgets;
  final VoidCallback onShowAll;

  /// How many categories to list.
  final int limit;

  const OverBudgetAlerts({super.key, required this.budgets, required this.onShowAll, this.limit = 3});

  @override
  Widget build(BuildContext context) {
    final over = Budget.sortByRisk(budgets.where((b) => b.isOverspent));
    if (over.isEmpty) return const SizedBox.shrink();
    final danger = context.dangerColor;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 6),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: context.isDarkMode ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.trArgs('over_budget_count', {'count': over.length}),
                  style: GoogleFonts.outfit(color: danger, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: onShowAll,
                style: TextButton.styleFrom(
                  foregroundColor: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF7A152E),
                ),
                child: Text(context.tr('show_all')),
              ),
            ],
          ),
          for (final b in over.take(limit))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 24, bottom: 6, end: 8),
              child: Text(
                context.trArgs('over_budget_row', {
                  'category': context.trCat(b.categoryCode),
                  'amount': context.sar(b.overspentAmount),
                }),
                key: const Key('over_budget_row'),
                style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
