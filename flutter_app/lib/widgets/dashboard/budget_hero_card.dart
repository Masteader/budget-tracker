import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

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
    final isDark = context.isDark;
    final totalAllocated = budgets.fold(0.0, (s, b) => s + b.allocatedAmount);
    final totalSpent = budgets.fold(0.0, (s, b) => s + b.spentAmount);
    final remaining = (totalAllocated - totalSpent);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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

    // Compute dynamic days until payday accurately
    int paydayDay = 27;
    if (cycle != null && cycle!.cycleStart.isNotEmpty) {
      try {
        paydayDay = DateTime.parse(cycle!.cycleStart).day;
      } catch (_) {}
    }
    DateTime nextPayday = DateTime(today.year, today.month, paydayDay);
    int daysUntilPayday;
    if (today.isAtSameMomentAs(nextPayday)) {
      daysUntilPayday = 0;
    } else {
      if (today.isAfter(nextPayday)) {
        nextPayday = DateTime(today.year, today.month + 1, paydayDay);
      }
      daysUntilPayday = nextPayday.difference(today).inDays;
    }

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
    final currencyUnit = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        context.tr('sar'),
        style: GoogleFonts.outfit(
          color: isDark ? const Color(0xFF00E5BF) : const Color(0xFF00A887),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071C33) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? const Color(0xFF4DE6F7).withValues(alpha: 0.28)
              : const Color(0xFF00E5BF).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5BF).withValues(alpha: isDark ? 0.08 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF0D2542),
                  Color(0xFF051424),
                ]
              : const [
                  Colors.white,
                  Color(0xFFF0FDF9),
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
                    context.tr('hero_tag'),
                    style: GoogleFonts.outfit(
                      color: isDark ? const Color(0xFF4DE6F7) : const Color(0xFF008F7A),
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
                  color: isDark ? const Color(0xFF0F2642) : const Color(0xFFE6FAF6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF4DE6F7).withValues(alpha: 0.2)
                        : const Color(0xFF00E5BF).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  context.trArgs('days_to_payday_badge', {'days': daysUntilPayday}),
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white70 : const Color(0xFF065F54),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ─── Big Remaining Amount ──────────────────────────────────
          Text(
            context.tr('cycle_remaining_budget'),
            style: GoogleFonts.outfit(
              color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          // The amount scales down instead of overflowing on narrow screens
          // or with large accessibility text. Arabic/Urdu place the unit after
          // the number ("1,250.00 ر.س"), English before it ("SAR 1,250.00").
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (!context.isRtl) currencyUnit,
                Text(
                  fmt.format(remaining),
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (context.isRtl) currencyUnit,
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ─── Burn Rate & Progress Gauge ────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: spentRatio,
                backgroundColor: isDark ? const Color(0xFF0F2642) : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  spentRatio > 0.9
                      ? const Color(0xFFFF5252)
                      : (spentRatio > 0.75
                          ? const Color(0xFFFFA657)
                          : (isDark ? const Color(0xFF00E5BF) : const Color(0xFF00C896))),
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
                    color: isBurnCaution
                        ? (isDark ? const Color(0xFFFFA657) : const Color(0xFFD97706))
                        : (isDark ? const Color(0xFF73FBC4) : const Color(0xFF059669)),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isBurnCaution
                        ? context.trArgs('burn_pacing_high', {'amount': context.sar(dailyBurn, decimals: 0)})
                        : context.trArgs('burn_on_track', {'amount': context.sar(dailyBurn, decimals: 0)}),
                    style: GoogleFonts.outfit(
                      color: isBurnCaution
                          ? (isDark ? const Color(0xFFFFA657) : const Color(0xFFD97706))
                          : (isDark ? const Color(0xFF73FBC4) : const Color(0xFF059669)),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                context.trArgs('percent_spent', {'percent': (spentRatio * 100).toInt()}),
                style: GoogleFonts.outfit(
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
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
                  label: context.tr('allocated'),
                  value: context.sar(totalAllocated, decimals: 0),
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: isDark ? const Color(0xFF4DE6F7) : const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCapsule(
                  label: context.tr('spent'),
                  value: context.sar(totalSpent, decimals: 0),
                  icon: Icons.payments_outlined,
                  accentColor: isDark ? const Color(0xFF00E5BF) : const Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCapsule(
                  label: context.tr('allowance'),
                  value: context.trArgs('per_day_suffix', {'amount': context.sar(dailyAllowance, decimals: 0)}),
                  icon: Icons.speed_rounded,
                  accentColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFFB45309),
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
                color: isDark
                    ? const Color(0xFFFF5252).withValues(alpha: 0.14)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFFFF5252).withValues(alpha: 0.35)
                      : const Color(0xFFFCA5A5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: isDark ? const Color(0xFFFFA657) : const Color(0xFFDC2626),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.trArgs('projected_over_budget', {'amount': context.sar(projectedSpend)}),
                      style: GoogleFonts.outfit(
                        color: isDark ? const Color(0xFFFFA657) : const Color(0xFFDC2626),
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
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1E34) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.22 : 0.35),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
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
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
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
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

