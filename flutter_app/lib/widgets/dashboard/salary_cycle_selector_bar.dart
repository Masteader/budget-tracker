import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/velvet_burgundy_theme.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';

/// 3D Ceramic selector bar for switching between salary cycles (payday 27th - 26th).
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
    final isDark = context.isDark;
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: ThreeDSurfaceCard(
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // Previous Chevron (3D Puck Button)
            ThreeDIconPuck(
              size: 32,
              isWhiteSurface: true,
              icon: Icons.chevron_left_rounded,
              iconSize: 20,
              iconColor: hasPrevious
                  ? (isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight)
                  : context.textSecondary.withValues(alpha: 0.3),
              onTap: hasPrevious ? onPrevious : null,
            ),
            const SizedBox(width: 8),

            // Middle Cycle Range & Status
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('📅 ', style: TextStyle(fontSize: 13)),
                      Flexible(
                        child: Text(
                          titleText,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF063326)
                                : VelvetBurgundyColors.emeraldSafeBgLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: VelvetBurgundyColors.emeraldSafe.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            context.tr('active_badge'),
                            style: GoogleFonts.outfit(
                              color: isDark
                                  ? const Color(0xFF6EE7B7)
                                  : VelvetBurgundyColors.emeraldSafeTextLight,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subText,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Next Chevron (3D Puck Button)
            ThreeDIconPuck(
              size: 32,
              isWhiteSurface: true,
              icon: Icons.chevron_right_rounded,
              iconSize: 20,
              iconColor: hasNext
                  ? (isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight)
                  : context.textSecondary.withValues(alpha: 0.3),
              onTap: hasNext ? onNext : null,
            ),
          ],
        ),
      ),
    );
  }
}
