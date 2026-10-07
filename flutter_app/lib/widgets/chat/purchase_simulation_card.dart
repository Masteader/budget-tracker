import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final item = simulationData['merchant'] as String? ?? 'Item';
    final daysToPayday = simulationData['days_to_payday'] as int? ?? 0;
    final dailyCurrent = (simulationData['current_daily_allowance'] as num?)?.toDouble() ?? 0.0;
    final dailyPost = (simulationData['post_purchase_daily_allowance'] as num?)?.toDouble() ?? 0.0;

    Color badgeColor = const Color(0xFF00C896);
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String verdictLabel = "Comfortably Affordable";

    if (verdict == 'caution') {
      badgeColor = Colors.orange;
      badgeIcon = Icons.warning_amber_rounded;
      verdictLabel = "Caution (Reallocation Needed)";
    } else if (verdict == 'unaffordable' || verdict == 'not_recommended') {
      badgeColor = Colors.redAccent;
      badgeIcon = Icons.cancel_outlined;
      verdictLabel = "Unaffordable / Exceeds Budget";
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
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
                  'Purchase Simulator',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
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
            '$item • SAR ${targetAmt.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Days to Payday: $daysToPayday days away',
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Daily Allowance Now',
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SAR ${dailyCurrent.toStringAsFixed(1)}/d',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF8B949E), size: 14),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'After Purchase',
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SAR ${dailyPost.toStringAsFixed(1)}/d',
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
