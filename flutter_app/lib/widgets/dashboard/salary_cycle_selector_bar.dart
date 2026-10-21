import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../../services/salary_cycle_service.dart';

/// Reusable selector bar for switching between salary cycles (payday 27th - 26th).
class SalaryCycleSelectorBar extends StatelessWidget {
  final SalaryCycleInfo? currentCycle;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool hasPrevious;
  final bool hasNext;

  const SalaryCycleSelectorBar({
    super.key,
    this.currentCycle,
    this.onPrevious,
    this.onNext,
    this.hasPrevious = false,
    this.hasNext = false,
  });

  @override
  Widget build(BuildContext context) {
    // A cycle is named by its dates ("27 Oct – 26 Nov"), never by a month:
    // with a late payday the cycle mostly lies in the previous month.
    final fallbackCycle = SalaryCycleService.currentCycle();
    final fallbackTitle = context.cycleLabel(fallbackCycle.key);
    final titleText = currentCycle != null
        ? context.cycleRangeIso(
            currentCycle!.cycleStart,
            currentCycle!.cycleEnd,
            fallback: context.cycleLabel(currentCycle!.cycleKey, fallback: currentCycle!.monthName),
          )
        : fallbackTitle;
    final isCurrent = currentCycle?.isCurrent ?? true;
    final subText = isCurrent ? context.tr('active_salary_cycle') : context.tr('salary_cycle');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('a11y_previous'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.chevron_left_rounded, color: hasPrevious ? context.textPrimary : context.textSecondary.withValues(alpha: 0.3), size: 24),
            onPressed: hasPrevious ? onPrevious : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      titleText,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppThemes.success.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppThemes.success.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          context.tr('active_badge'),
                          style: TextStyle(
                            color: context.successText,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subText,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('a11y_next'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.chevron_right_rounded, color: hasNext ? context.textPrimary : context.textSecondary.withValues(alpha: 0.3), size: 24),
            onPressed: hasNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}
