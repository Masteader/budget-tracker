import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card for resolving potential duplicate transactions detected by the AI.
class DuplicateResolutionCard extends StatelessWidget {
  final Map<String, dynamic> candidateData;
  final ValueChanged<String> onEnrich;
  final ValueChanged<String> onLogAsNew;
  final VoidCallback? onDiscard;

  const DuplicateResolutionCard({
    super.key,
    required this.candidateData,
    required this.onEnrich,
    required this.onLogAsNew,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final candidateId = candidateData['candidate_transaction_id'] as String?;
    final parsed = candidateData['parsed_data'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'Duplicate Prevention Check',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.orange, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: const Text('Enrich Existing SMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    if (candidateId != null) {
                      onEnrich(candidateId);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8B949E)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Log as New', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    final originalMsg = parsed != null
                        ? "${parsed['merchant']} ${parsed['amount']} SAR"
                        : "Expense";
                    onLogAsNew(originalMsg);
                  },
                ),
              ),
            ],
          ),
          if (onDiscard != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF85149),
                  side: BorderSide(color: const Color(0xFFF85149).withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Discard', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: onDiscard,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
