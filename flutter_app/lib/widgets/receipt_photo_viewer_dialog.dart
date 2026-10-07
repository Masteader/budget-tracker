import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ReceiptPhotoViewerDialog extends StatelessWidget {
  final String receiptUrl;
  final String merchant;
  final double? amount;

  const ReceiptPhotoViewerDialog({
    super.key,
    required this.receiptUrl,
    required this.merchant,
    this.amount,
  });

  static Future<void> show(
    BuildContext context, {
    required String receiptUrl,
    required String merchant,
    double? amount,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) => ReceiptPhotoViewerDialog(
        receiptUrl: receiptUrl,
        merchant: merchant,
        amount: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          // Header Bar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (amount != null)
                      Text(
                        'SAR ${amount!.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF00C896),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Interactive Zoomable Image
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF161B22),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      receiptUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF00C896)),
                        );
                      },
                      errorBuilder: (ctx, _, __) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.broken_image_outlined, size: 48, color: Color(0xFF8B949E)),
                            const SizedBox(height: 8),
                            Text(
                              'Unable to load receipt image',
                              style: GoogleFonts.outfit(color: const Color(0xFF8B949E)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
