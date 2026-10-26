import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';

import '../../core/widgets/three_d_surface_card.dart';

/// Card showing real-time affordability analysis before purchasing an item.
class PurchaseSimulationCard extends StatelessWidget {
  final Map<String, dynamic> simulationData;

  const PurchaseSimulationCard({
    super.key,
    required this.simulationData,
  });

  @override
  Widget build(BuildContext context) {
    final verdict = simulationData['verdict'] as String? ?? 'comfortable';
    final targetAmt = (simulationData['amount'] as num?)?.toDouble() ?? 0.0;
    final item = simulationData['merchant'] as String? ?? context.tr('sim_item');
    final daysToPayday = simulationData['days_to_payday'] as int? ?? 0;
    final dailyCurrent = (simulationData['current_daily_allowance'] as num?)?.toDouble() ?? 0.0;
    final dailyPost = (simulationData['post_purchase_daily_allowance'] as num?)?.toDouble() ?? 0.0;

    Color badgeColor = AppThemes.success;
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String verdictLabel = context.tr('comfortably_affordable');

    if (verdict == 'caution') {
      badgeColor = context.warnText;
      badgeIcon = Icons.warning_amber_rounded;
      verdictLabel = context.tr('caution_reallocation');
    } else if (verdict == 'unaffordable' || verdict == 'not_recommended') {
      badgeColor = context.dangerColor;
      badgeIcon = Icons.cancel_outlined;
      verdictLabel = context.tr('unaffordable_exceeds');
    }

    return ThreeDSurfaceCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('wt2_tag2'),
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  verdictLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$item • ${context.sar(targetAmt)}',
            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            context.trArgs('psim_days_to_payday', {'days': daysToPayday}),
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.subtleCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.tr('psim_daily_now'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.trArgs('per_day_suffix', {'amount': context.sar(dailyCurrent, decimals: 1)}),
                        style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: context.textSecondary, size: 16),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.tr('after_purchase'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.trArgs('per_day_suffix', {'amount': context.sar(dailyPost, decimals: 1)}),
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
