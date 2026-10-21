import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_dues.dart';
import '../../models/models.dart';
import '../../models/payday_outlook.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';

/// The dashboard's one "until payday" hero (UX-07): how much is left until
/// payday, one daily figure, one verdict and, in family mode, what is owed to
/// the wife. All figures come from [PaydayOutlook]; no other card on the
/// dashboard computes a pace or a verdict.
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
    final okColor = isDark ? AppThemes.mintNeon : const Color(0xFF047857);
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
    final barColor = share > 0.9
        ? const Color(0xFFFF5252)
        : (share > 0.75 ? const Color(0xFFFFA657) : (isDark ? AppThemes.electricTeal : AppThemes.success));

    final currencyUnit = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        context.tr('sar'),
        style: GoogleFonts.outfit(
          color: isDark ? AppThemes.electricTeal : const Color(0xFF00A887),
          fontSize: 18,
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
        accentColor: isDark ? AppThemes.iceCyan : const Color(0xFF0284C7),
      ),
      _StatCapsule(
        label: context.tr('spent'),
        value: context.sar(outlook.totalSpent, decimals: 0),
        icon: Icons.payments_outlined,
        accentColor: isDark ? AppThemes.electricTeal : const Color(0xFF059669),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppThemes.deepGlacial : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? AppThemes.iceCyan.withValues(alpha: 0.28)
              : AppThemes.electricTeal.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppThemes.electricTeal.withValues(alpha: isDark ? 0.08 : 0.12),
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
              ? const [Color(0xFF0D2542), AppThemes.brandDarkBg]
              : const [Colors.white, Color(0xFFF0FDF9)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── What this is + days to payday ─────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F2642) : const Color(0xFFE6FAF6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? AppThemes.iceCyan.withValues(alpha: 0.2)
                        : AppThemes.electricTeal.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  context.trPlural('days_to_payday_badge', daysUntilPayday),
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white70 : const Color(0xFF065F54),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ─── The one big number ────────────────────────────────────
          // Scales down instead of overflowing on narrow screens or with
          // large text. Arabic/Urdu put the unit after the number.
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
                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (context.isRtl) currencyUnit,
              ],
            ),
          ),
          Text(baseLine, style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                backgroundColor: isDark ? const Color(0xFF0F2642) : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                // Not clamped: 131% reads 131% (UX-08).
                context.trArgs('percent_spent', {'percent': (share * 100).round()}),
                style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
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
                  style: GoogleFonts.outfit(color: verdictColor, fontSize: 12.5, fontWeight: FontWeight.w700),
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

class _DueRow extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  const _DueRow({required this.text, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppThemes.champagneGold.withValues(alpha: context.isDark ? 0.12 : 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('hero_due_line'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppThemes.champagneGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // The value is never cut off (UX-14): it scales down if it must.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
