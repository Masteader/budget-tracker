import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../store_attribution_card.dart';

/// Interactive confirmation card embedded within chat bubbles that asks user
/// to verify store name and attribution ('me', 'partner', 'both') before saving.
class PendingExpenseConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> pendingData;
  final void Function(String confirmedMerchant, String confirmedSpentBy) onConfirm;
  final VoidCallback onCancel;

  const PendingExpenseConfirmationCard({
    super.key,
    required this.pendingData,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<PendingExpenseConfirmationCard> createState() => _PendingExpenseConfirmationCardState();
}

class _PendingExpenseConfirmationCardState extends State<PendingExpenseConfirmationCard> {
  late final TextEditingController _merchantController;
  late String _selectedSpentBy;

  @override
  void initState() {
    super.initState();
    final defaultMerchant = widget.pendingData['merchant'] as String? ?? 'Store Name';
    _merchantController = TextEditingController(text: defaultMerchant);
    _selectedSpentBy = (widget.pendingData['spent_by'] as String? ?? 'both').toLowerCase();
    if (!['me', 'partner', 'both'].contains(_selectedSpentBy)) {
      _selectedSpentBy = 'both';
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.pendingData['amount'] as num?)?.toDouble() ?? 0.0;
    final rawItems = widget.pendingData['items'] as List?;
    final items = rawItems != null
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF00C896), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Confirm Expense Details',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SAR ${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Items Preview (if any)
          if (items.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF21262D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} item(s) found:',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...items.map((it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${it['quantity']}x ${it['name']}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            Text(
                              'SAR ${(it['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                              style: const TextStyle(color: Color(0xFF00C896), fontSize: 11),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],

          // Store & Attribution details
          StoreAttributionCard(
            merchantController: _merchantController,
            selectedSpentBy: _selectedSpentBy,
            compact: true,
            title: 'Store & Spent By Attribution',
            onSpentByChanged: (newSpentBy) {
              setState(() => _selectedSpentBy = newSpentBy);
            },
          ),
          const SizedBox(height: 8),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Confirm & Add Expense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    final store = _merchantController.text.trim();
                    widget.onConfirm(store.isNotEmpty ? store : 'Store Name', _selectedSpentBy);
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8B949E),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
