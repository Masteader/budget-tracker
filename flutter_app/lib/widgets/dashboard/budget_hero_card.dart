import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/three_d_surface_card.dart';
import '../../l10n/app_localizations.dart';
import '../../models/household_dues.dart';
import '../../models/models.dart';
import '../../models/payday_outlook.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';

/// The dashboard's 3D "until payday" hero card (UX-07):
/// Refactored to match Stitch Screen 1 (3D ceramic squircle card,
/// layered burgundy/rose-gold circular gauge dial, and status badges).
class BudgetHeroCard extends StatelessWidget {
  final List<Budget> budgets;
  final SalaryCycleInfo? cycle;

  /// The household's monthly income; null or 0 falls back to the budgets.
  final double? monthlyIncome;

  /// What is owed between household members, from the viewer's side (the
  /// wife's dues in family mode, the viewer's roommate balances).
  final List<DueLine> dueLines;

  /// Opens the ledger behind [dueLines].
  final VoidCallback? onDueTap;

  /// Clock for tests; defaults to now.
  final DateTime? now;

  /// Above this text scale the stat tiles stack instead of truncating (UX-14).
  static const double stackTilesAboveTextScale = 1.3;

  const BudgetHeroCard({
    super.key,
    required this.budgets,
    this.cycle,
    this.monthlyIncome,
    this.dueLines = const [],
    this.onDueTap,
    this.now,
  });

  /// The cycle the hero describes, as calendar dates (Riyadh).
  (DateTime, DateTime) _cycleDates() {
    final c = cycle;
    if (c != null) {
      final start = DateTime.tryParse(c.cycleStart);
      final end = DateTime.tryParse(c.cycleEnd);
      if (start != null && end != null) {
        return (DateTime.utc(start.year, start.month, start.day), DateTime.utc(end.year, end.month, end.day));
      }
    }
    final current = SalaryCycleService.currentCycle(now: now);
    return (current.start, current.end);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final today = SalaryCycleService.riyadhToday(now: now);
    final (start, end) = _cycleDates();
    final outlook = PaydayOutlook.compute(
      budgets: budgets,
      monthlyIncome: monthlyIncome,
      today: today,
      cycleStart: start,
      cycleEnd: end,
    );

    // The payday badge is about the running cycle: 0 on payday itself.
    final running = SalaryCycleService.currentCycle(now: now);
    final daysUntilPayday = today == running.start ? 0 : running.end.difference(today).inDays + 1;

    final fmt = NumberFormat('#,##0.00', 'en_US');
    final title = outlook.isClosed
        ? context.tr('hero_left_cycle_closed')
        : context.tr(outlook.incomeBased ? 'hero_left_until_payday' : 'hero_left_in_budgets');
    final baseLine = context.trArgs(
      outlook.incomeBased ? 'hero_base_income' : 'hero_base_budget',
      {'amount': context.sar(outlook.base, decimals: 0)},
    );

    final cautionColor = isDark ? const Color(0xFFFFA657) : const Color(0xFFB45309);
    final okColor = isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight;
    final Color verdictColor;
    final IconData verdictIcon;
    final String verdictText;
    switch (outlook.verdict) {
      case PaydayVerdict.overspent:
        verdictColor = context.dangerColor;
        verdictIcon = Icons.warning_amber_rounded;
        verdictText = context.trArgs('hero_verdict_over', {'amount': context.sar(-outlook.left)});
      case PaydayVerdict.runsOut:
        verdictColor = cautionColor;
        verdictIcon = Icons.trending_up_rounded;
        verdictText = context.trArgs('hero_verdict_run_out', {'date': context.fmtDate(outlook.runOutDate!, 'd MMM')});
      case PaydayVerdict.onTrack:
        verdictColor = okColor;
        verdictIcon = Icons.check_circle_outline_rounded;
        verdictText = context.tr('hero_verdict_on_track');
    }

    final share = outlook.spentShare;
    final currencyUnit = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        context.tr('sar'),
        style: GoogleFonts.outfit(
          color: isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.accentRose,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final stackTiles = MediaQuery.textScalerOf(context).scale(10) / 10 > stackTilesAboveTextScale;
    final tiles = [
      _StatCapsule(
        label: context.tr('allocated'),
        value: context.sar(outlook.totalAllocated, decimals: 0),
        icon: Icons.account_balance_wallet_outlined,
        accentColor: isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight,
      ),
      _StatCapsule(
        label: context.tr('spent'),
        value: context.sar(outlook.totalSpent, decimals: 0),
        icon: Icons.payments_outlined,
        accentColor: isDark ? const Color(0xFFF472B6) : VelvetBurgundyColors.accentRose,
      ),
    ];

    final Widget titleText = Text(
      title,
      style: GoogleFonts.outfit(
        color: isDark ? Colors.white70 : const Color(0xFF64748B),
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
    );

    final Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF381423)
            : VelvetBurgundyColors.rosePillLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? VelvetBurgundyColors.roseBorderDark
              : VelvetBurgundyColors.roseBorderLight,
        ),
      ),
      child: Text(
        context.trPlural('days_to_payday_badge', daysUntilPayday),
        style: GoogleFonts.outfit(
          color: isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
      ),
    );

    return ThreeDSurfaceCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header: Info + Dial Gauge (or stacked under large text) ─
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Main content (Title, big amount, status badge)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stackTiles) ...[
                      titleText,
                      const SizedBox(height: 4),
                      badge,
                    ] else
                      Row(
                        children: [
                          Expanded(child: titleText),
                          const SizedBox(width: 6),
                          badge,
                        ],
                      ),
                    const SizedBox(height: 6),

                    // Big Number
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
                            fmt.format(outlook.left),
                            style: GoogleFonts.outfit(
                              color: outlook.verdict == PaydayVerdict.overspent
                                  ? context.dangerColor
                                  : (isDark ? Colors.white : VelvetBurgundyColors.primaryLight),
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (context.isRtl) currencyUnit,
                        ],
                      ),
                    ),
                    Text(baseLine, style: TextStyle(color: context.textSecondary, fontSize: 11)),
                  ],
                ),
              ),

              // 3D Circular Ring Gauge Dial (Stitch Screen 1)
              const SizedBox(width: 14),
              _DialGauge3D(
                spentShare: share,
                daysRemaining: daysUntilPayday,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ─── 3D Recessed Progress Groove ───────────────────────────
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
                widthFactor: share.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: share > 0.9
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
          const SizedBox(height: 10),

          // ─── One daily figure, one verdict ─────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: outlook.isClosed || outlook.verdict == PaydayVerdict.overspent
                    ? const SizedBox.shrink()
                    : Text(
                        context.trArgs('hero_daily_safe', {'amount': context.sar(outlook.safeDaily, decimals: 0)}),
                        key: const Key('hero_daily_figure'),
                        style: GoogleFonts.outfit(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                context.trArgs('percent_spent', {'percent': (share * 100).round()}),
                style: GoogleFonts.outfit(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            key: const Key('hero_verdict'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(verdictIcon, size: 16, color: verdictColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  verdictText,
                  style: GoogleFonts.outfit(
                    color: verdictColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                ),
              ),
            ],
          ),

          // ─── Family / household dues ───────────────────────────────
          for (final due in dueLines) ...[
            const SizedBox(height: 10),
            _DueRow(
              text: _dueText(context, due),
              icon: due.kind == DueKind.owedToWife || due.kind == DueKind.owedToMe
                  ? Icons.family_restroom_rounded
                  : Icons.group_outlined,
              onTap: onDueTap,
            ),
          ],
          const SizedBox(height: 14),

          if (stackTiles)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [tiles[0], const SizedBox(height: 8), tiles[1]],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 8),
                Expanded(child: tiles[1]),
              ],
            ),
        ],
      ),
    );
  }

  String _dueText(BuildContext context, DueLine due) {
    final amount = context.sar(due.amount);
    switch (due.kind) {
      case DueKind.owedToWife:
        return context.trArgs('hero_due_owed_to_wife', {
          'name': due.name ?? context.tr('hero_wife_fallback'),
          'amount': amount,
        });
      case DueKind.owedToMe:
        return context.trArgs('hero_due_owed_to_you', {'amount': amount});
      case DueKind.iOwe:
        return context.trArgs('hero_due_you_owe', {'name': due.name ?? '', 'amount': amount});
      case DueKind.owedByRoommate:
        return context.trArgs('hero_due_owes_you', {'name': due.name ?? '', 'amount': amount});
    }
  }
}

/// 3D Ceramic Circular Ring Gauge Dial (from Stitch Screen 1).
class _DialGauge3D extends StatelessWidget {
  final double spentShare;
  final int daysRemaining;
  final bool isDark;

  const _DialGauge3D({
    required this.spentShare,
    required this.daysRemaining,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (spentShare * 100).clamp(0, 999).round();

    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E101D), Color(0xFF19060E)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF7F9), Color(0xFFF2DCE2)],
              ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF4A0E1E))
                .withValues(alpha: isDark ? 0.4 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? VelvetBurgundyColors.roseBorderDark
              : VelvetBurgundyColors.roseBorderLight,
          width: 1.2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Circular Progress Track
          SizedBox(
            width: 68,
            height: 68,
            child: CircularProgressIndicator(
              value: spentShare.clamp(0.0, 1.0),
              strokeWidth: 6,
              backgroundColor: isDark ? const Color(0xFF14050B) : const Color(0xFFF5EEF0),
              valueColor: AlwaysStoppedAnimation(
                isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight,
              ),
            ),
          ),
          // Inner percentage & days pill
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : VelvetBurgundyColors.primaryLight,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF5E1327) : VelvetBurgundyColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$daysRemaining d',
                  style: GoogleFonts.outfit(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  const _DueRow({required this.text, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Material(
      color: isDark
          ? const Color(0xFF2E1520)
          : const Color(0xFFFFF7F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark
              ? VelvetBurgundyColors.roseBorderDark
              : VelvetBurgundyColors.roseBorderLight,
        ),
      ),
      child: InkWell(
        key: const Key('hero_due_line'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.accentRose,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                ),
              ),
              if (onTap != null)
                Icon(
                  context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: context.textSecondary,
                ),
            ],
          ),
        ),
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
        color: isDark ? const Color(0xFF19060E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? VelvetBurgundyColors.roseBorderDark
              : VelvetBurgundyColors.roseBorderLight,
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF4A0E1E).withValues(alpha: 0.04),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
