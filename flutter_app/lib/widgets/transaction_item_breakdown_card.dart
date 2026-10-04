import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TransactionItemBreakdownCard extends StatelessWidget {
  final String merchant;
  final double amount;
  final String currency;
  final String? categoryCode;
  final String source;
  final String spentBy;
  final List<Map<String, dynamic>> items;
  final bool isReallocated;
  final bool initiallyExpanded;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const TransactionItemBreakdownCard({
    super.key,
    required this.merchant,
    required this.amount,
    this.currency = 'SAR',
    this.categoryCode,
    this.source = 'chat',
    this.spentBy = 'both',
    this.items = const [],
    this.isReallocated = false,
    this.initiallyExpanded = false,
    this.onEdit,
    this.onDelete,
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

  Widget _buildSpentByBadge(String who, {bool detailed = false}) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (who.toLowerCase()) {
      case 'partner':
        bg = const Color(0xFFA371F7).withValues(alpha: 0.16);
        fg = const Color(0xFFBC8CFF);
        icon = Icons.favorite_outline;
        label = detailed ? 'Paid by Partner' : 'Partner';
        break;
      case 'me':
        bg = const Color(0xFF1F6FEB).withValues(alpha: 0.16);
        fg = const Color(0xFF58A6FF);
        icon = Icons.person_outline;
        label = detailed ? 'Paid by Me (Personal)' : 'Me';
        break;
      case 'both':
      default:
        bg = const Color(0xFF00C896).withValues(alpha: 0.16);
        fg = const Color(0xFF00C896);
        icon = Icons.people_alt_outlined;
        label = detailed ? 'Household (Both)' : 'Both';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: detailed ? 10 : 6, vertical: detailed ? 4 : 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: detailed ? 14 : 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: fg,
              fontSize: detailed ? 12 : 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReallocated ? Colors.orange.withValues(alpha: 0.5) : const Color(0xFF30363D),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            iconColor: const Color(0xFF00C896),
            collapsedIconColor: const Color(0xFF8B949E),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withValues(alpha: 0.12),
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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _sourceLabel,
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                  ),
                ),
                _buildSpentByBadge(spentBy),
                if (categoryCode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withValues(alpha: 0.1),
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
                if (isReallocated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
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
            ),
          ),
          children: [
            const Divider(color: Color(0xFF21262D), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Attribution banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF30363D), width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Attributed To:',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF8B949E),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        _buildSpentByBadge(spentBy, detailed: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Itemized items section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'EXACT LINE ITEMS',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF8B949E),
                        ),
                      ),
                      Text(
                        items.isNotEmpty
                            ? '${items.length} ${items.length == 1 ? "item" : "items"}'
                            : 'Single expense',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: const Color(0xFF8B949E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (items.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF21262D)),
                      ),
                      child: Column(
                        children: [
                          ...items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final it = entry.value;
                            final name = it['name'] ?? 'Item';
                            final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                            final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                            return Padding(
                              padding: EdgeInsets.only(
                                top: idx > 0 ? 6 : 0,
                                bottom: idx < items.length - 1 ? 6 : 0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00C896),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${qty > 1 ? '${qty.toStringAsFixed(0)}x ' : ''}$name',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFF0F6FC),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$currency ${price.toStringAsFixed(2)}',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: Color(0xFF21262D), height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Breakdown',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF8B949E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '$currency ${amount.toStringAsFixed(2)}',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF00C896),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF21262D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_outlined, size: 18, color: Color(0xFF8B949E)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '1x $merchant ($currency ${amount.toStringAsFixed(2)})\nNo line items attached. Tap Edit to add items.',
                              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onEdit != null || onDelete != null) ...[
              const Divider(color: Color(0xFF21262D), height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF8B949E)),
                        label: const Text('Edit', style: TextStyle(color: Color(0xFFC9D1D9), fontSize: 12)),
                        onPressed: onEdit,
                      ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        onPressed: onDelete,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }
}
