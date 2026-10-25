import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/velvet_burgundy_theme.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category_catalog.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';
import '../sub_budget_breakdown_sheet.dart';

/// Interactive 3D budget card per category displaying spent vs allocated,
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
    if (budget.isOverspent || budget.usageRatio >= 1.0) return VelvetBurgundyColors.coralDanger;
    if (budget.usageRatio >= 0.8) return VelvetBurgundyColors.amberCaution;
    return VelvetBurgundyColors.emeraldSafe;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final hasRollover = budget.previousCycleDelta != 0.0;
    final subCategories = kSubCategoriesByParent[budget.categoryCode] ?? const <String>[];
    final visual = CategoryCatalog.visual(budget.categoryCode);

    final statusText = '${(budget.usageRatio * 100).toStringAsFixed(0)}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ThreeDSurfaceCard(
        borderRadius: 22,
        padding: const EdgeInsets.all(14),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 3D Category Icon Puck
                ThreeDIconPuck(
                  size: 40,
                  isSquircle: true,
                  icon: visual.icon,
                  iconSize: 20,
                  iconColor: visual.color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              context.trCat(budget.categoryCode),
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: context.textPrimary,
                              ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 3D Status Pill (e.g. 60% آمن or 112% تجاوز)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: budget.isOverspent
                                  ? (isDark
                                      ? const Color(0xFF3B0C18)
                                      : VelvetBurgundyColors.coralDangerBgLight)
                                  : (isDark
                                      ? const Color(0xFF063326)
                                      : VelvetBurgundyColors.emeraldSafeBgLight),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: budget.isOverspent
                                    ? VelvetBurgundyColors.coralDanger.withValues(alpha: 0.5)
                                    : VelvetBurgundyColors.emeraldSafe.withValues(alpha: 0.5),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              statusText,
                              style: GoogleFonts.outfit(
                                color: budget.isOverspent
                                    ? (isDark ? const Color(0xFFFF8FA2) : VelvetBurgundyColors.coralDangerTextLight)
                                    : (isDark ? const Color(0xFF6EE7B7) : VelvetBurgundyColors.emeraldSafeTextLight),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${context.sar(budget.spentAmount)} / ${context.sar(budget.allocatedAmount)}',
                            style: GoogleFonts.outfit(
                              color: context.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (hasRollover)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: budget.previousCycleDelta > 0
                                    ? VelvetBurgundyColors.emeraldSafe.withValues(alpha: 0.15)
                                    : VelvetBurgundyColors.coralDanger.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                budget.previousCycleDelta > 0
                                    ? '+${context.sar(budget.previousCycleDelta)}'
                                    : '-${context.sar(budget.previousCycleDelta.abs())}',
                                style: TextStyle(
                                  color: budget.previousCycleDelta > 0
                                      ? VelvetBurgundyColors.emeraldSafe
                                      : VelvetBurgundyColors.coralDanger,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 3D Recessed Progress Groove
            Container(
              height: 7,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14050B) : const Color(0xFFF0E6E9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? const Color(0x33FFD2E1) : const Color(0xFFE8DEE1),
                  width: 0.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: budget.usagePercent.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: budget.isOverspent
                            ? [
                                const Color(0xFFF59E0B),
                                VelvetBurgundyColors.coralDanger,
                                const Color(0xFF991B1B),
                              ]
                            : [
                                VelvetBurgundyColors.roseGold,
                                VelvetBurgundyColors.accentRose,
                                VelvetBurgundyColors.primaryLight,
                              ],
                      ),
                    ),
                  ),
                ),
              ),
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
                      style: TextStyle(color: context.dangerColor, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],

            if (subCategories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF14060C) : const Color(0xFFFAF5F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0x26FFD2E1) : VelvetBurgundyColors.roseBorderLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_tree_outlined, size: 13, color: _barColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.tr('itemized_sub_budgets'),
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          context.tr('breakdown'),
                          style: TextStyle(color: context.textSecondary, fontSize: 9.5),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 13, color: context.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: subCategories.map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF260D17) : Colors.white,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isDark ? const Color(0x33FFD2E1) : VelvetBurgundyColors.roseBorderLight,
                          ),
                        ),
                        child: Text(
                          context.trSub(s, nameEn: s),
                          style: TextStyle(color: context.textSecondary, fontSize: 9.5),
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
    );
  }
}
