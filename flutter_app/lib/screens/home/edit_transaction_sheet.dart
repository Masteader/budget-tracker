import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main.dart';
import '../../models/models.dart';

class EditTransactionSheet extends StatefulWidget {
  final Transaction transaction;

  const EditTransactionSheet({
    super.key,
    required this.transaction,
  });

  static Future<void> show(BuildContext context, Transaction transaction) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditTransactionSheet(transaction: transaction),
    );
  }

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late TextEditingController _merchantCtrl;
  late TextEditingController _amountCtrl;
  late String _selectedCategory;
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

    try {
      await supabase.from('transactions').update({
        'merchant': _merchantCtrl.text.trim(),
        'amount': amount,
        'category_code': _selectedCategory,
        'items': _items,
      }).eq('id', widget.transaction.id);

      if (mounted) {
        Navigator.pop(context);
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
      if (mounted) {
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: SingleChildScrollView(
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
    );
  }
}
