import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../models/salary_cycle_info.dart';

class BudgetHeroCard extends StatelessWidget {
  final List<Budget> budgets;
  final SalaryCycleInfo? cycle;

  const BudgetHeroCard({
    super.key,
    required this.budgets,
    this.cycle,
  });

  @override
  Widget build(BuildContext context) {
    final totalAllocated = budgets.fold(0.0, (s, b) => s + b.allocatedAmount);
    final totalSpent = budgets.fold(0.0, (s, b) => s + b.spentAmount);

    final now = DateTime.now();
    DateTime fallbackCycleStart;
    if (now.day >= 27) {
      fallbackCycleStart = DateTime(now.year, now.month, 27);
    } else {
      fallbackCycleStart = DateTime(now.year, now.month - 1, 27);
    }
    final fallbackDaysElapsed = now.difference(fallbackCycleStart).inDays + 1;

    final daysTotal = cycle?.daysTotal ?? 30;
    final daysElapsed = (cycle?.daysElapsed ?? fallbackDaysElapsed).clamp(1, daysTotal);

    // Separate fixed lump-sum monthly commitments (rent, utilities) from variable daily expenses
    const fixedCodes = {'HOUSING-RENT', 'HOUSING', 'OPEX-UTILITIES', 'UTILITIES-BILLS'};
    double fixedSpent = 0.0;
    double variableSpent = 0.0;
    for (final b in budgets) {
      if (fixedCodes.contains(b.categoryCode)) {
        fixedSpent += b.spentAmount;
      } else {
        variableSpent += b.spentAmount;
      }
    }

    // Daily burn is computed from variable living expenses so rent doesn't distort projections
    final dailyBurn = daysElapsed > 0 ? variableSpent / daysElapsed : 0.0;
    final projectedSpend = fixedSpent + (dailyBurn * daysTotal);
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C896), Color(0xFF00A3FF)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Budget', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            'SAR ${fmt.format(totalAllocated)}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: 'Spent', value: 'SAR ${fmt.format(totalSpent)}'),
              _StatItem(
                label: 'Remaining',
                value: 'SAR ${fmt.format(totalAllocated - totalSpent)}',
              ),
              _StatItem(label: 'Burn/Day', value: 'SAR ${fmt.format(dailyBurn)}'),
            ],
          ),
          const SizedBox(height: 12),
          if (projectedSpend > totalAllocated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Projected: SAR ${fmt.format(projectedSpend)} (over budget!)',
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
