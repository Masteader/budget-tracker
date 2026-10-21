import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';
import '../sub_budget_breakdown_sheet.dart';
import '../../models/category_catalog.dart';

/// Interactive budget card per category displaying spent vs allocated,
/// usage progress bar with alert coloring, rollover badge, and sub-category chips.
class CategoryBudgetCard extends StatelessWidget {
  final Budget budget;
  final String householdId;
  final String? cycleKey;

  const CategoryBudgetCard({
    super.key,
    required this.budget,
    required this.householdId,
    this.cycleKey,
  });

  Color get _barColor {
    if (budget.isOverspent || budget.usageRatio >= 1.0) return Colors.redAccent;
    if (budget.usageRatio >= 0.8) return Colors.orange;
    return AppThemes.success;
  }

  @override
  Widget build(BuildContext context) {
    final hasRollover = budget.previousCycleDelta != 0.0;
    final subCategories = kSubCategoriesByParent[budget.categoryCode] ?? const <String>[];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          SubBudgetBreakdownSheet.show(
            context,
            householdId: householdId,
            categoryCode: budget.categoryCode,
            cycleKey: cycleKey,
            allocatedAmount: budget.allocatedAmount,
            spentAmount: budget.spentAmount,
            previousCycleDelta: budget.previousCycleDelta,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          CategoryCatalog.visual(budget.categoryCode).icon,
                          size: 18,
                          color: CategoryCatalog.visual(budget.categoryCode).color,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            context.trCat(budget.categoryCode),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasRollover) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: budget.previousCycleDelta > 0
                                  ? AppThemes.success.withValues(alpha: 0.15)
                                  : Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              budget.previousCycleDelta > 0
                                  ? '+${context.sar(budget.previousCycleDelta)}'
                                  : '-${context.sar(budget.previousCycleDelta.abs())}',
                              style: TextStyle(
                                color: budget.previousCycleDelta > 0
                                    ? AppThemes.success
                                    : Colors.redAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // Not clamped: 131% reads 131% (UX-08); only the bar is.
                        '${(budget.usageRatio * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: _barColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 16, color: context.textSecondary),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: budget.usagePercent,
                  backgroundColor: context.chipBg,
                  valueColor: AlwaysStoppedAnimation(_barColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.trArgs('amount_spent_suffix', {'amount': context.sar(budget.spentAmount)}),
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  Text(
                    context.trArgs('of_amount', {'amount': context.sar(budget.allocatedAmount)}),
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              if (budget.isOverspent) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: context.dangerColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        context.trArgs('over_by_amount', {'amount': context.sar(budget.overspentAmount)}),
                        style: TextStyle(color: context.dangerColor, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
              if (subCategories.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.scaffoldBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_tree_outlined, size: 13, color: AppThemes.success),
                          const SizedBox(width: 6),
                          Text(
                            context.tr('itemized_sub_budgets'),
                            style: TextStyle(
                              color: context.successText,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            context.tr('breakdown'),
                            style: TextStyle(color: context.textSecondary, fontSize: 10),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 14, color: context.textSecondary),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: subCategories.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.chipBg,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            context.trSub(s, nameEn: s),
                            style: TextStyle(color: context.textSecondary, fontSize: 10),
                          ),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
