import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/receipt_storage_service.dart';

class EditTransactionSheet extends StatefulWidget {
  final Transaction transaction;

  const EditTransactionSheet({
    super.key,
    required this.transaction,
  });

  static Future<String?> show(BuildContext context, Transaction transaction) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: EditTransactionSheet(transaction: transaction),
      ),
    );
  }

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late TextEditingController _merchantCtrl;
  late TextEditingController _amountCtrl;
  late String _selectedCategory;
  late String _selectedSpentBy;
  late List<Map<String, dynamic>> _items;
  bool _isSaving = false;

  final List<Map<String, String>> _categories = const [
    {'code': 'OPEX-GROCERY', 'name': 'Groceries & Supermarkets'},
    {'code': 'OPEX-DINING', 'name': 'Dining & Cafes'},
    {'code': 'OPEX-FUEL', 'name': 'Fuel & Transport'},
    {'code': 'OPEX-UTILITIES', 'name': 'Utilities & Bills'},
    {'code': 'OPEX-SHOPPING', 'name': 'Shopping & Retail'},
    {'code': 'OPEX-ENTERTAINMENT', 'name': 'Entertainment'},
    {'code': 'OPEX-HEALTH', 'name': 'Health & Pharmacy'},
    {'code': 'OPEX-MISC', 'name': 'Miscellaneous'},
  ];

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.transaction.merchant ?? '');
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toStringAsFixed(2));
    _selectedCategory = widget.transaction.categoryCode ?? 'OPEX-MISC';
    _selectedSpentBy = widget.transaction.spentBy.isNotEmpty ? widget.transaction.spentBy : 'both';
    _items = widget.transaction.items
        .map((it) => Map<String, dynamic>.from(it))
        .toList();
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add({'name': 'New Item', 'quantity': 1.0, 'price': 0.0});
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _saveChanges() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final basePayload = <String, dynamic>{
      'merchant': _merchantCtrl.text.trim(),
      'amount': amount,
      'category_code': _selectedCategory,
      'items': _items,
    };

    try {
      try {
        await supabase.from('transactions').update({
          ...basePayload,
          'spent_by': _selectedSpentBy,
        }).eq('id', widget.transaction.id);
      } catch (_) {
        // Fallback: update raw_sms with SpentBy tag
        final raw = widget.transaction.rawSms ?? '';
        final cleanRaw = raw.replaceAll(RegExp(r'\|\s*SpentBy:\s*(me|partner|both)', caseSensitive: false), '').trim();
        final newRaw = '$cleanRaw | SpentBy: $_selectedSpentBy';
        await supabase.from('transactions').update({
          ...basePayload,
          'raw_sms': newRaw,
        }).eq('id', widget.transaction.id);
      }

      if (mounted) {
        Navigator.pop(context, 'updated');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction updated successfully.'),
            backgroundColor: Color(0xFF00C896),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete Transaction', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete this SAR ${widget.transaction.amount.toStringAsFixed(2)} transaction at ${widget.transaction.merchant ?? "Unknown"}?\nThis will adjust your budget spent amount automatically.',
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    try {
      await supabase.from('transactions').delete().eq('id', widget.transaction.id);
      if (widget.transaction.receiptUrl != null && widget.transaction.receiptUrl!.trim().isNotEmpty) {
        ReceiptStorageService().deleteReceiptByUrl(widget.transaction.receiptUrl!);
      }
      if (mounted) {
        Navigator.pop(context, 'deleted');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction removed and budget restored.'),
            backgroundColor: Color(0xFF00C896),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildSpentByOption(String key, String title, IconData icon, Color activeColor) {
    final isSelected = _selectedSpentBy.toLowerCase() == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSpentBy = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFF30363D),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? activeColor : const Color(0xFF8B949E)),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF8B949E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderRadio(String provider, Color color, String currentSelected, ValueChanged<String> onSelected) {
    final isSelected = currentSelected == provider;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(provider),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFF0D1117),
            border: Border.all(color: isSelected ? color : const Color(0xFF30363D)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            provider,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? color : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _convertToInstallmentPlan() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount first.')),
      );
      return;
    }

    String selectedProvider = 'Tamara';
    int selectedCount = 4;
    bool isProcessing = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            final monthly = amount / selectedCount;
            final remainingBalance = amount - monthly;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF30363D),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Convert to BNPL Installment Plan',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Amortize this purchase across monthly installments to prevent budget blowouts.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
                  ),
                  const SizedBox(height: 16),

                  // Provider Selector
                  Text('PROVIDER', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF8B949E), letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildProviderRadio('Tamara', const Color(0xFFFF6B6B), selectedProvider, (p) {
                        setModalState(() => selectedProvider = p);
                      }),
                      const SizedBox(width: 8),
                      _buildProviderRadio('Tabby', const Color(0xFF00E676), selectedProvider, (p) {
                        setModalState(() => selectedProvider = p);
                      }),
                      const SizedBox(width: 8),
                      _buildProviderRadio('Bank / Other', const Color(0xFF58A6FF), selectedProvider, (p) {
                        setModalState(() => selectedProvider = p);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Duration selector
                  Text('INSTALLMENT DURATION', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF8B949E), letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [3, 4, 6].map((count) {
                      final isSelected = selectedCount == count;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () => setModalState(() => selectedCount = count),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF00C896).withValues(alpha: 0.2) : const Color(0xFF0D1117),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$count Months',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF00C896) : Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Plan Summary Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('First Month (This Cycle):', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                            Text('SAR ${monthly.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF00C896), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Deferred to Next Cycles (${selectedCount - 1} mo):', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                            Text('SAR ${remainingBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                        const Divider(color: Color(0xFF21262D), height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Immediate Budget Headroom:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                            Text('+SAR ${remainingBalance.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF00C896), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isProcessing ? null : () async {
                      setModalState(() => isProcessing = true);
                      try {
                        await ApiService.instance.createInstallmentPlan({
                          'household_id': widget.transaction.householdId,
                          'merchant': _merchantCtrl.text.trim(),
                          'provider': selectedProvider,
                          'total_amount': amount,
                          'installment_count': selectedCount,
                          'paid_installments': 1,
                          'category_code': _selectedCategory,
                          'original_transaction_id': widget.transaction.id,
                          'adjust_original_transaction': true,
                          'notes': 'Converted from transaction via mobile app',
                        });
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (mounted) {
                          Navigator.pop(context, 'updated');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Successfully converted to $selectedProvider $selectedCount-month plan!'),
                              backgroundColor: const Color(0xFF00C896),
                            ),
                          );
                        }
                      } catch (e) {
                        setModalState(() => isProcessing = false);
                        if (sheetCtx.mounted) {
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                    child: isProcessing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Confirm Installment Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF30363D),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit Transaction',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: 'Delete transaction',
                  onPressed: _deleteTransaction,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Merchant
            TextField(
              controller: _merchantCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Merchant Name',
                labelStyle: const TextStyle(color: Color(0xFF8B949E)),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Amount
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Amount (SAR)',
                prefixText: 'SAR ',
                labelStyle: const TextStyle(color: Color(0xFF8B949E)),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // BNPL / Installment Action Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_score_rounded, color: Color(0xFFFF6B6B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BNPL Installment Plan',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'Split into 3 or 4 monthly payments (Tamara / Tabby)',
                          style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _convertToInstallmentPlan,
                    child: const Text('Convert', style: TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Category Dropdown
            DropdownButtonFormField<String>(
              initialValue: _categories.any((c) => c['code'] == _selectedCategory) ? _selectedCategory : 'OPEX-MISC',
              dropdownColor: const Color(0xFF161B22),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Category',
                labelStyle: const TextStyle(color: Color(0xFF8B949E)),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _categories.map((c) {
                return DropdownMenuItem(
                  value: c['code'],
                  child: Text(c['name']!),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            const SizedBox(height: 16),

            // Who spent this attribution selector
            Text(
              'WHO SPENT THIS?',
              style: GoogleFonts.outfit(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8B949E),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildSpentByOption('me', 'Me', Icons.person_outline, const Color(0xFF58A6FF)),
                const SizedBox(width: 8),
                _buildSpentByOption('partner', 'Partner', Icons.favorite_outline, const Color(0xFFBC8CFF)),
                const SizedBox(width: 8),
                _buildSpentByOption('both', 'Both (Shared)', Icons.people_alt_outlined, const Color(0xFF00C896)),
              ],
            ),
            const SizedBox(height: 20),

            // Line items header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LINE ITEMS',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8B949E),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16, color: Color(0xFF00C896)),
                  label: const Text('Add Item', style: TextStyle(color: Color(0xFF00C896), fontSize: 12)),
                  onPressed: _addItem,
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No itemized breakdown attached.',
                  style: GoogleFonts.outfit(color: const Color(0xFF8B949E), fontSize: 12),
                ),
              ),

            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final it = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: it['name'] ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Item name',
                          hintStyle: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) => it['name'] = val,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: ((it['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Color(0xFF00C896), fontSize: 13, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          prefixText: 'SAR ',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) {
                          it['price'] = double.tryParse(val) ?? 0.0;
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF8B949E)),
                      onPressed: () => _removeItem(idx),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
}
