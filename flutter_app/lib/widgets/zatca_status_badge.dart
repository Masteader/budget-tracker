import 'package:flutter/material.dart';

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
        color: const Color(0xFF00C896).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: Color(0xFF00C896), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ZATCA Verified: $seller',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  customSubtitle ??
                      'Total: SAR ${total.toStringAsFixed(2)}  •  VAT: SAR ${vat.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF00C896), fontSize: 11),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF8B949E)),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
