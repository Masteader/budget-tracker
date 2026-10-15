import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Modal bottom sheet for logging a manual expense quickly.
class ManualExpenseSheet extends StatefulWidget {
  final String? householdId;
  final String? initialMerchant;
  final double? initialAmount;
  final String? initialCategory;

  const ManualExpenseSheet({
    super.key,
    this.householdId,
    this.initialMerchant,
    this.initialAmount,
    this.initialCategory,
  });

  static Future<void> show(
    BuildContext context, {
    String? householdId,
    String? initialMerchant,
    double? initialAmount,
    String? initialCategory,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ManualExpenseSheet(
          householdId: householdId,
          initialMerchant: initialMerchant,
          initialAmount: initialAmount,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  @override
  State<ManualExpenseSheet> createState() => _ManualExpenseSheetState();
}

class _ManualExpenseSheetState extends State<ManualExpenseSheet> {
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  late String _selectedCategory;
  String _selectedSpentBy = 'me';
  bool _isSaving = false;

  static const List<Map<String, String>> _categories = [
    {'code': 'OPEX-GROCERY', 'emoji': '🛒 '},
    {'code': 'OPEX-DINING', 'emoji': '☕ '},
    {'code': 'OPEX-SHOPPING', 'emoji': '🛍️ '},
    {'code': 'OPEX-UTILITIES', 'emoji': '⚡ '},
    {'code': 'OPEX-FUEL', 'emoji': '⛽ '},
    {'code': 'OPEX-ENTERTAINMENT', 'emoji': '🎮 '},
    {'code': 'OPEX-HEALTH', 'emoji': '💊 '},
    {'code': 'CAPEX-EDUCATION', 'emoji': '🎓 '},
    {'code': 'OPEX-GOV', 'emoji': '🏛️ '},
    {'code': 'OPEX-MISC', 'emoji': '📦 '},
  ];

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.initialMerchant ?? '');
    _amountCtrl = TextEditingController(
      text: widget.initialAmount != null && widget.initialAmount! > 0
          ? widget.initialAmount!.toStringAsFixed(2)
          : '',
    );
    _selectedCategory = widget.initialCategory ?? 'OPEX-GROCERY';
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveExpense() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    final merchant = _merchantCtrl.text.trim();

    if (amount <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid amount.');
      return;
    }
    if (merchant.isEmpty) {
      AppSnackBar.showError(context, 'Please enter a merchant or item name.');
      return;
    }

    setState(() => _isSaving = true);
    final hid = widget.householdId ?? '';

    try {
      // 1. Direct Supabase insert
      await supabase.from('transactions').insert({
        'household_id': hid,
        'amount': amount,
        'currency': 'SAR',
        'merchant': merchant,
        'category_code': _selectedCategory,
        'spent_by': _selectedSpentBy,
        'source': 'manual',
        'timestamp': DateTime.now().toIso8601String(),
        'items': [
          {'name': merchant, 'price': amount, 'quantity': 1}
        ],
      });

      if (mounted) {
        context.read<TransactionProvider>().fetchTransactions();
        context.read<BudgetProvider>().refresh();
        Navigator.pop(context);
        AppSnackBar.showSuccess(
          context,
          'Recorded SAR ${amount.toStringAsFixed(2)} at $merchant',
          title: 'Expense Logged',
        );
      }
    } catch (e) {
      // 2. Offline fallback queue
      try {
        await OfflineSyncService.instance.enqueue(
          endpoint: 'chat',
          payload: {
            'message': '$merchant SAR ${amount.toStringAsFixed(2)} in $_selectedCategory',
            'user_id': supabase.auth.currentUser?.id,
          },
          householdId: hid,
        );

        if (mounted) {
          context.read<TransactionProvider>().fetchTransactions();
          context.read<BudgetProvider>().refresh();
          Navigator.pop(context);
          AppSnackBar.showSuccess(
            context,
            'Saved offline: SAR ${amount.toStringAsFixed(2)} at $merchant. Will sync automatically.',
            title: 'Queued Offline',
            icon: Icons.cloud_off_rounded,
          );
        }
      } catch (err) {
        if (mounted) {
          setState(() => _isSaving = false);
          AppSnackBar.showError(context, 'Failed to save expense: $err');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: context.borderColor),
          left: BorderSide(color: context.borderColor),
          right: BorderSide(color: context.borderColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA657).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFFA657), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('manual_log'),
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Merchant
              TextField(
                controller: _merchantCtrl,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: context.tr('merchant_name'),
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: Icon(Icons.storefront_outlined, color: context.textSecondary, size: 20),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Amount
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                decoration: InputDecoration(
                  labelText: context.tr('amount_sar'),
                  prefixText: 'SAR ',
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: const Icon(Icons.attach_money_rounded, color: Color(0xFF00C896), size: 20),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Category
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                dropdownColor: context.cardBg,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: context.tr('category'),
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: Icon(Icons.category_outlined, color: context.textSecondary, size: 20),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _categories.map((c) {
                  final code = c['code']!;
                  final emoji = c['emoji']!;
                  return DropdownMenuItem(
                    value: code,
                    child: Text('$emoji${context.trCat(code)}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 16),

              // Paid By Segmented Options
              Text(
                'Paid by:',
                style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildSegment('me', 'Me', Icons.person_rounded),
                  const SizedBox(width: 8),
                  _buildSegment('partner', 'Partner', Icons.people_alt_rounded),
                  const SizedBox(width: 8),
                  _buildSegment('both', 'Split (Both)', Icons.handshake_rounded),
                ],
              ),
              const SizedBox(height: 20),

              // Save Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSaving ? null : _saveExpense,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('record_expense'),
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(String key, String label, IconData icon) {
    final isSelected = _selectedSpentBy == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSpentBy = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00C896).withValues(alpha: 0.18) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF00C896) : context.borderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFF00C896) : context.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00C896) : context.textSecondary,
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
