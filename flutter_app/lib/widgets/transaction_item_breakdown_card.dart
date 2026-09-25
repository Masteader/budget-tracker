import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TransactionItemBreakdownCard extends StatelessWidget {
  final String merchant;
  final double amount;
  final String currency;
  final String? categoryCode;
  final String source;
  final List<Map<String, dynamic>> items;
  final bool isReallocated;

  const TransactionItemBreakdownCard({
    super.key,
    required this.merchant,
    required this.amount,
    this.currency = 'SAR',
    this.categoryCode,
    this.source = 'chat',
    this.items = const [],
    this.isReallocated = false,
  });

  IconData get _sourceIcon {
    switch (source) {
      case 'chat':
        return Icons.chat_bubble_outline;
      case 'receipt_scan':
        return Icons.document_scanner_outlined;
      case 'manual':
        return Icons.edit_note;
      case 'sms':
      default:
        return Icons.sms_outlined;
    }
  }

  String get _sourceLabel {
    switch (source) {
      case 'chat':
        return 'AI Chat Entry';
      case 'receipt_scan':
        return 'Invoice Scan';
      case 'manual':
        return 'Manual Log';
      case 'sms':
      default:
        return 'Bank SMS';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReallocated ? Colors.orange.withOpacity(0.5) : const Color(0xFF30363D),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: items.isNotEmpty,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_sourceIcon, color: const Color(0xFF00C896), size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  merchant,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                '$currency ${amount.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: const Color(0xFFFF5252),
                ),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _sourceLabel,
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                ),
              ),
              if (categoryCode != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    categoryCode!.replaceFirst(RegExp(r'^[A-Z]+-'), ''),
                    style: const TextStyle(
                      color: Color(0xFF00C896),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (isReallocated) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Reallocated',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          children: [
            if (items.isNotEmpty) ...[
              const Divider(color: Color(0xFF21262D), height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ITEMIZED BREAKDOWN',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...items.map((it) {
                      final name = it['name'] ?? 'Item';
                      final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(
                              '${qty > 1 ? '${qty.toStringAsFixed(0)}x ' : ''}$name',
                              style: const TextStyle(
                                color: Color(0xFFC9D1D9),
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$currency ${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF8B949E),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
