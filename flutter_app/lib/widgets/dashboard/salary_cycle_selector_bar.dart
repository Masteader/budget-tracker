import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';

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
    final titleText = currentCycle?.monthName ?? DateFormat('MMMM yyyy').format(DateTime.now());
    final subText = currentCycle != null
        ? '${currentCycle!.cycleStart.substring(5)} - ${currentCycle!.cycleEnd.substring(5)}'
        : 'Payday 27th Cycle (27th - 26th)';
    final isCurrent = currentCycle?.isCurrent ?? true;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 24),
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
                        color: Colors.white,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C896).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF00C896).withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Color(0xFF00C896),
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
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 24),
            onPressed: hasNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}
