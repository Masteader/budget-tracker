import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';

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

    Color badgeColor = const Color(0xFF00C896);
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String verdictLabel = context.tr('comfortably_affordable');

    if (verdict == 'caution') {
      badgeColor = Colors.orange;
      badgeIcon = Icons.warning_amber_rounded;
      verdictLabel = context.tr('caution_reallocation');
    } else if (verdict == 'unaffordable' || verdict == 'not_recommended') {
      badgeColor = Colors.redAccent;
      badgeIcon = Icons.cancel_outlined;
      verdictLabel = context.tr('unaffordable_exceeds');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(badgeIcon, color: badgeColor, size: 16),
              const SizedBox(width: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
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
          const SizedBox(height: 10),
          Text(
            '$item • ${context.sar(targetAmt)}',
            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            context.trArgs('psim_days_to_payday', {'days': daysToPayday}),
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.subtleCardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.tr('psim_daily_now'),
                        style: TextStyle(color: context.textSecondary, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.trArgs('per_day_suffix', {'amount': context.sar(dailyCurrent, decimals: 1)}),
                        style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, color: context.textSecondary, size: 14),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.tr('after_purchase'),
                        style: TextStyle(color: context.textSecondary, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.trArgs('per_day_suffix', {'amount': context.sar(dailyPost, decimals: 1)}),
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
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
