import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../sub_budget_breakdown_sheet.dart';

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
    if (budget.usagePercent >= 1.0) return Colors.redAccent;
    if (budget.usagePercent >= 0.8) return Colors.orange;
    return const Color(0xFF00C896);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
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
            previousCycleDelta: budget.previousCycleDelta,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
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
                        Flexible(
                          child: Text(
                            budget.categoryCode.replaceFirst(RegExp(r'^[A-Z]+-'), ''),
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
                                  ? const Color(0xFF00C896).withValues(alpha: 0.15)
                                  : Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              budget.previousCycleDelta > 0
                                  ? '+SAR ${fmt.format(budget.previousCycleDelta)}'
                                  : '-SAR ${fmt.format(budget.previousCycleDelta.abs())}',
                              style: TextStyle(
                                color: budget.previousCycleDelta > 0
                                    ? const Color(0xFF00C896)
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
                        '${(budget.usagePercent * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: _barColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8B949E)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: budget.usagePercent,
                  backgroundColor: const Color(0xFF30363D),
                  valueColor: AlwaysStoppedAnimation(_barColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SAR ${fmt.format(budget.spentAmount)} spent',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                  Text(
                    'of SAR ${fmt.format(budget.allocatedAmount)}',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                ],
              ),
              if (subCategories.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF21262D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_tree_outlined, size: 13, color: Color(0xFF00C896)),
                          SizedBox(width: 6),
                          Text(
                            'Sub-Categories',
                            style: TextStyle(
                              color: Color(0xFF00C896),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'Breakdown',
                            style: TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 14, color: Color(0xFF8B949E)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: subCategories.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
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
