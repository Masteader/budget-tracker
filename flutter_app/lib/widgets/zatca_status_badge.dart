import 'package:flutter/material.dart';
import '../theme/app_themes.dart';
import '../l10n/app_localizations.dart';

/// Displays a verified green status banner for Saudi ZATCA e-invoices with seller, total, and 15% VAT.
class ZatcaStatusBadge extends StatelessWidget {
  final String seller;
  final double total;
  final double vat;
  final String? customSubtitle;
  final VoidCallback? onDismiss;

  const ZatcaStatusBadge({
    super.key,
    required this.seller,
    required this.total,
    required this.vat,
    this.customSubtitle,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemes.electricTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppThemes.electricTeal.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppThemes.electricTeal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.trArgs('zsb_verified', {'seller': seller}),
                  style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  customSubtitle ??
                      context.trArgs('zsb_total_vat', {'total': context.sar(total), 'vat': context.sar(vat)}),
                  style: TextStyle(color: context.accentText, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: context.tr('close'),
              icon: Icon(Icons.close, size: 18, color: context.textSecondary),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
