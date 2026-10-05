import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card displayed when an invoice matches a recent SMS transaction amount.
class DuplicateCandidateCard extends StatelessWidget {
  final String message;
  final int itemCount;
  final VoidCallback onEnrich;
  final VoidCallback onLogSeparate;
  final VoidCallback? onDiscard;

  const DuplicateCandidateCard({
    super.key,
    required this.message,
    required this.itemCount,
    required this.onEnrich,
    required this.onLogSeparate,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Matching Transaction Found',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: onEnrich,
                  child: Text(
                    'Attach $itemCount Items to SMS',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: onLogSeparate,
                  child: const Text('Log as Separate', style: TextStyle(fontSize: 11)),
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
                label: const Text('Discard Duplicate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: onDiscard,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
