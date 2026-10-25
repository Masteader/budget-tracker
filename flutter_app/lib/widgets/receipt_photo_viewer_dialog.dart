import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/receipt_storage_service.dart';
import '../theme/app_themes.dart';
import '../l10n/app_localizations.dart';

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
                        context.sar(amount!),
                        style: GoogleFonts.outfit(
                          // Header sits on the dark modal barrier in both themes.
                          color: const Color(0xFFF0A3BC),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('close'),
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
                color: context.cardBg,
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: FutureBuilder<String?>(
                      future: ReceiptStorageService().getSignedReceiptUrl(receiptUrl),
                      builder: (ctx, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: Color(0xFFF0A3BC)),
                          );
                        }
                        final resolvedUrl = snapshot.data;
                        if (resolvedUrl == null ||
                            (!resolvedUrl.startsWith('http://') && !resolvedUrl.startsWith('https://'))) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined, size: 48, color: context.textSecondary),
                                const SizedBox(height: 8),
                                Text(
                                  context.tr('rpv_load_failed'),
                                  style: GoogleFonts.outfit(color: context.textSecondary),
                                ),
                              ],
                            ),
                          );
                        }
                        return Image.network(
                          resolvedUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(color: Color(0xFFF0A3BC)),
                            );
                          },
                          errorBuilder: (ctx, _, __) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined, size: 48, color: context.textSecondary),
                                const SizedBox(height: 8),
                                Text(
                                  context.tr('rpv_load_failed'),
                                  style: GoogleFonts.outfit(color: context.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
