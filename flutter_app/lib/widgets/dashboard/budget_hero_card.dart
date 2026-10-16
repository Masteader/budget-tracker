import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';

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
    final remaining = (totalAllocated - totalSpent);

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
    final daysRemaining = (daysTotal - daysElapsed).clamp(0, daysTotal);

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
    final dailyAllowance = daysRemaining > 0 ? (remaining > 0 ? remaining / daysRemaining : 0.0) : 0.0;
    final isBurnCaution = dailyBurn > dailyAllowance && dailyAllowance > 0;
    final spentRatio = totalAllocated > 0 ? (totalSpent / totalAllocated).clamp(0.0, 1.0) : 0.0;

    final fmt = NumberFormat('#,##0.00', 'en_US');
    final compactFmt = NumberFormat('#,##0', 'en_US');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF071C33),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF4DE6F7).withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5BF).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D2542),
            Color(0xFF051424),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header: Sovereign HUD Tag + Cycle Status ───────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5BF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5BF).withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SOVEREIGN HUD',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF4DE6F7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2642),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF4DE6F7).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '$daysRemaining DAYS TO PAYDAY',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ─── Big Remaining Amount ──────────────────────────────────
          Text(
            'CYCLE REMAINING BUDGET',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'SAR ',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF00E5BF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                fmt.format(remaining),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ─── Burn Rate & Progress Gauge ────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: spentRatio,
                backgroundColor: const Color(0xFF0F2642),
                valueColor: AlwaysStoppedAnimation<Color>(
                  spentRatio > 0.9
                      ? const Color(0xFFFF5252)
                      : (spentRatio > 0.75
                          ? const Color(0xFFFFA657)
                          : const Color(0xFF00E5BF)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Pace indicator line
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isBurnCaution ? Icons.trending_up_rounded : Icons.check_circle_outline_rounded,
                    size: 14,
                    color: isBurnCaution ? const Color(0xFFFFA657) : const Color(0xFF73FBC4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isBurnCaution
                        ? 'Burn SAR ${compactFmt.format(dailyBurn)}/d (Pacing High)'
                        : 'Burn SAR ${compactFmt.format(dailyBurn)}/d (On Track)',
                    style: GoogleFonts.outfit(
                      color: isBurnCaution ? const Color(0xFFFFA657) : const Color(0xFF73FBC4),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${(spentRatio * 100).toInt()}% Spent',
                style: GoogleFonts.outfit(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ─── Frosted Metric Capsules ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCapsule(
                  label: 'Allocated',
                  value: 'SAR ${compactFmt.format(totalAllocated)}',
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: const Color(0xFF4DE6F7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCapsule(
                  label: 'Spent',
                  value: 'SAR ${compactFmt.format(totalSpent)}',
                  icon: Icons.payments_outlined,
                  accentColor: const Color(0xFF00E5BF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCapsule(
                  label: 'Allowance',
                  value: 'SAR ${compactFmt.format(dailyAllowance)}/d',
                  icon: Icons.speed_rounded,
                  accentColor: const Color(0xFFD4AF37),
                ),
              ),
            ],
          ),

          // ─── Projected Overbudget Alert (if any) ───────────────────
          if (projectedSpend > totalAllocated) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFA657), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Projected: SAR ${fmt.format(projectedSpend)} (Over budget)',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFFFFA657),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCapsule extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  const _StatCapsule({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accentColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white60,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

