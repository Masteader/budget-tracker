import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/budget_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/app_snackbar.dart';

class EditTransactionSheet extends StatefulWidget {
  final Transaction transaction;
  final List<String> householdDependents;

  const EditTransactionSheet({
    super.key,
    required this.transaction,
    this.householdDependents = const [],
  });

  static Future<String?> show(
    BuildContext context,
    Transaction transaction, {
    List<String> householdDependents = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: EditTransactionSheet(
          transaction: transaction,
          householdDependents: householdDependents,
        ),
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
  late String? _selectedSubCategory;
  late String _selectedPaidBy;
  late String _selectedBeneficiary;
  late List<Map<String, dynamic>> _items;
  List<Map<String, dynamic>> _subCategories = [];
  List<String> _dependents = [];
  bool _isSaving = false;

  final List<Map<String, String>> _categories = const [
    {'code': 'OPEX-GROCERY', 'name': 'Groceries & Supermarkets'},
    {'code': 'OPEX-DINING', 'name': 'Dining & Cafes'},
    {'code': 'OPEX-SHOPPING', 'name': 'Shopping & Retail'},
    {'code': 'OPEX-UTILITIES', 'name': 'Utilities & Bills'},
    {'code': 'OPEX-FUEL', 'name': 'Fuel & Transport'},
    {'code': 'OPEX-ENTERTAINMENT', 'name': 'Entertainment'},
    {'code': 'OPEX-HEALTH', 'name': 'Health & Pharmacy'},
    {'code': 'CAPEX-EDUCATION', 'name': 'Education'},
    {'code': 'OPEX-GOV', 'name': 'Government & Fees'},
    {'code': 'OPEX-MISC', 'name': 'Miscellaneous'},
  ];

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.transaction.merchant ?? '');
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toStringAsFixed(2));
    var initialCat = widget.transaction.categoryCode ?? 'OPEX-MISC';
    if (initialCat == 'OPEX-GROCERIES') initialCat = 'OPEX-GROCERY';
    if (initialCat == 'OPEX-TRANSPORT') initialCat = 'OPEX-FUEL';
    if (initialCat == 'OPEX-EDUCATION') initialCat = 'CAPEX-EDUCATION';
    if (initialCat == 'OPEX-HOUSING') initialCat = 'OPEX-UTILITIES';
    _selectedCategory = initialCat;
    _selectedSubCategory = widget.transaction.subCategory;
    _selectedPaidBy = widget.transaction.paidBy.isNotEmpty ? widget.transaction.paidBy : 'me';
    _selectedBeneficiary = widget.transaction.beneficiary.isNotEmpty ? widget.transaction.beneficiary : 'both';
    if (widget.transaction.paidBy.isEmpty && widget.transaction.spentBy.isNotEmpty) {
      if (widget.transaction.spentBy == 'partner') {
        _selectedPaidBy = 'partner';
        _selectedBeneficiary = 'partner';
      } else if (widget.transaction.spentBy == 'both') {
        _selectedPaidBy = 'me';
        _selectedBeneficiary = 'both';
      } else {
        _selectedPaidBy = 'me';
        _selectedBeneficiary = 'me';
      }
    }
    _items = widget.transaction.items
        .map((it) => Map<String, dynamic>.from(it))
        .toList();
    _dependents = List<String>.from(widget.householdDependents);
    _loadSubCategories(_selectedCategory);
    if (_dependents.isEmpty && widget.transaction.householdId.isNotEmpty) {
      _loadDependents();
    }
  }

  Future<void> _loadSubCategories(String catCode) async {
    try {
      final subs = await ApiService.instance.getSubCategories(catCode);
      if (mounted) {
        setState(() {
          _subCategories = subs;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDependents() async {
    try {
      final deps = await ApiService.instance.getDependents(widget.transaction.householdId);
      if (mounted) {
        setState(() {
          _dependents = deps.map((d) => d.name).toList();
        });
      }
    } catch (_) {}
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
      AppSnackBar.showError(context, 'Please enter a valid amount greater than zero.', title: 'Invalid Amount');
      return;
    }

    setState(() => _isSaving = true);

    String derivedSpentBy = 'both';
    if (_selectedBeneficiary == 'both') {
      derivedSpentBy = 'both';
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'partner') {
      derivedSpentBy = 'partner';
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'me') {
      derivedSpentBy = 'me';
    } else {
      derivedSpentBy = _selectedBeneficiary;
    }

    final basePayload = <String, dynamic>{
      'merchant': _merchantCtrl.text.trim(),
      'amount': amount,
      'category_code': _selectedCategory,
      'sub_category': _selectedSubCategory,
      'items': _items,
    };

    try {
      try {
        await supabase.from('transactions').update({
          ...basePayload,
          'paid_by': _selectedPaidBy,
          'beneficiary': _selectedBeneficiary,
          'spent_by': derivedSpentBy,
        }).eq('id', widget.transaction.id);
      } catch (_) {
        // Fallback: update raw_sms with PaidBy and Beneficiary tags
        final raw = widget.transaction.rawSms ?? '';
        final cleanRaw = raw
            .replaceAll(RegExp(r'\|\s*SpentBy:\s*(me|partner|both)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\|\s*PaidBy:\s*(me|partner)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\|\s*Beneficiary:\s*([^\s\|]+)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\|\s*SubCategory:\s*([^\s\|]+)', caseSensitive: false), '')
            .trim();
        final newRaw = '$cleanRaw | PaidBy: $_selectedPaidBy | Beneficiary: $_selectedBeneficiary | SubCategory: ${_selectedSubCategory ?? ""} | SpentBy: $derivedSpentBy';
        await supabase.from('transactions').update({
          ...basePayload,
          'raw_sms': newRaw,
          'spent_by': derivedSpentBy,
        }).eq('id', widget.transaction.id);
      }

      if (mounted) {
        Navigator.pop(context, 'updated');
        AppSnackBar.showSuccess(
          context,
          'Transaction updated and budget recomputed.',
          title: 'Changes Saved',
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        AppSnackBar.showError(context, 'Failed to update transaction: $e', title: 'Update Error');
      }
    }
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: const Text('Delete Transaction', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete this SAR ${widget.transaction.amount.toStringAsFixed(2)} transaction at ${widget.transaction.merchant ?? "Unknown"}?\nThis will adjust your budget spent amount automatically.',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
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
      if (widget.transaction.receiptUrl != null && widget.transaction.receiptUrl!.trim().isNotEmpty) {
        ReceiptStorageService().deleteReceiptByUrl(widget.transaction.receiptUrl!);
      }
      await supabase.from('transactions').delete().eq('id', widget.transaction.id);
      if (mounted) {
        Navigator.pop(context, 'deleted');
        AppSnackBar.showDelete(
          context,
          'SAR ${widget.transaction.amount.toStringAsFixed(2)} at ${widget.transaction.merchant ?? "merchant"} removed.',
          title: 'Transaction Deleted',
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        AppSnackBar.showError(context, 'Failed to delete transaction: $e', title: 'Delete Error');
      }
    }
  }

  Widget _buildSegmentOption({
    required bool isSelected,
    required String title,
    required IconData icon,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : context.borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? activeColor : context.textSecondary),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? (context.isDark ? Colors.white : const Color(0xFF0F172A)) : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettlementPreviewBanner(double amount) {
    String text;
    IconData icon;
    Color color;

    if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'both') {
      final half = amount * 0.5;
      text = 'Shared 50/50: Partner will owe you SAR ${half.toStringAsFixed(2)}';
      icon = Icons.handshake_outlined;
      color = const Color(0xFF00C896);
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'partner') {
      text = 'Paid for Partner: Partner will owe you full SAR ${amount.toStringAsFixed(2)}';
      icon = Icons.volunteer_activism_outlined;
      color = const Color(0xFFBC8CFF);
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'both') {
      final half = amount * 0.5;
      text = 'Shared 50/50: You will owe partner SAR ${half.toStringAsFixed(2)}';
      icon = Icons.handshake_outlined;
      color = const Color(0xFFFF9E79);
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'me') {
      text = 'Partner paid for you: You will owe partner full SAR ${amount.toStringAsFixed(2)}';
      icon = Icons.card_giftcard_rounded;
      color = const Color(0xFFFF6B6B);
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'me') {
      text = 'Personal purchase: No shared debt or settlement impact';
      icon = Icons.person_outline;
      color = const Color(0xFF58A6FF);
    } else {
      text = "Partner's personal purchase: No shared debt or settlement impact";
      icon = Icons.favorite_outline;
      color = const Color(0xFFBC8CFF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
            color: isSelected ? color.withValues(alpha: 0.15) : context.subtleCardBg,
            border: Border.all(color: isSelected ? color : context.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            provider,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? color : context.textPrimary,
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
      AppSnackBar.showError(context, 'Please enter a valid amount first.', title: 'Amount Required');
      return;
    }

    String selectedProvider = 'Tamara';
    int selectedCount = 4;
    bool isProcessing = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
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
                        color: context.borderColor,
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
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Amortize this purchase across monthly installments to prevent budget blowouts.',
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  // Provider Selector
                  Text('PROVIDER', style: GoogleFonts.outfit(fontSize: 11, color: context.textSecondary, letterSpacing: 1)),
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
                  Text('INSTALLMENT DURATION', style: GoogleFonts.outfit(fontSize: 11, color: context.textSecondary, letterSpacing: 1)),
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
                                color: isSelected ? const Color(0xFF00C896).withValues(alpha: 0.2) : context.subtleCardBg,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF00C896) : context.borderColor,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$count Months',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF00C896) : context.textPrimary,
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
                      color: context.subtleCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('First Month (This Cycle):', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                            Text('SAR ${monthly.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF00C896), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Deferred to Next Cycles (${selectedCount - 1} mo):', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                            Text('SAR ${remainingBalance.toStringAsFixed(2)}', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                          ],
                        ),
                        Divider(color: context.borderColor, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Immediate Budget Headroom:', style: TextStyle(color: context.textSecondary, fontSize: 12)),
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
                        final noteSuffix = ' [Financed via $selectedProvider: Installment 1 of $selectedCount. Full price: SAR ${amount.toStringAsFixed(2)}]';
                        final updatedNotes = '${widget.transaction.rawSms ?? ''}$noteSuffix';

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

                        try {
                          await supabase.from('transactions').update({
                            'amount': monthly,
                            'raw_sms': updatedNotes,
                          }).eq('id', widget.transaction.id);
                        } catch (_) {}

                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (mounted) {
                          try {
                            context.read<InstallmentProvider>().fetchPlans(silent: true);
                            context.read<TransactionProvider>().fetchTransactions();
                            context.read<BudgetProvider>().refresh();
                            context.read<RecurringBillsProvider>().fetchBills(silent: true);
                          } catch (_) {}
                          Navigator.pop(context, 'updated');
                          AppSnackBar.showSuccess(
                            context,
                            'Converted to $selectedProvider $selectedCount-month installment plan!',
                            title: 'Plan Active',
                          );
                        }
                      } catch (e) {
                        setModalState(() => isProcessing = false);
                        if (sheetCtx.mounted) {
                          AppSnackBar.showError(sheetCtx, 'Failed to convert plan: $e', title: 'Conversion Failed');
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

  Future<void> _quickAddChild() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.child_care_rounded, color: Color(0xFF00C896)),
            const SizedBox(width: 8),
            Text(
              'Add Child / Dependent',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary),
            ),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: context.textPrimary),
          decoration: InputDecoration(
            labelText: "Child's Name",
            labelStyle: TextStyle(color: context.textSecondary),
            hintText: 'e.g. Sarah, Omar',
            hintStyle: const TextStyle(color: Color(0xFF484F58)),
            filled: true,
            fillColor: context.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C896), foregroundColor: Colors.black),
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isNotEmpty) Navigator.pop(dCtx, n);
            },
            child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        await ApiService.instance.createDependent(
          widget.transaction.householdId,
          name,
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          if (!_dependents.contains(name)) {
            _dependents.add(name);
          }
          _selectedBeneficiary = name;
        });
      }
    }
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
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('edit_transaction'),
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: context.textPrimary),
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
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('merchant_name'),
                labelStyle: TextStyle(color: context.textSecondary),
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
              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: context.tr('amount_sar'),
                prefixText: 'SAR ',
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // BNPL / Installment Action Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
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
                          context.tr('installment_plans_title'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          context.tr('bnpl_empty_desc'),
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _convertToInstallmentPlan,
                    child: Text(context.tr('convert'), style: const TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Category Dropdown
            DropdownButtonFormField<String>(
              initialValue: _categories.any((c) => c['code'] == _selectedCategory) ? _selectedCategory : 'OPEX-MISC',
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('category'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _categories.map((c) {
                return DropdownMenuItem(
                  value: c['code'],
                  child: Text(context.trCat(c['code']!)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedCategory = val;
                    _selectedSubCategory = null;
                  });
                  _loadSubCategories(val);
                }
              },
            ),
            const SizedBox(height: 12),

            // Sub-Category Dropdown
            DropdownButtonFormField<String?>(
              initialValue: _subCategories.any((s) => s['sub_code'] == _selectedSubCategory)
                  ? _selectedSubCategory
                  : null,
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('sub_category'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(context.tr('select_sub_category'), style: TextStyle(color: context.textSecondary)),
                ),
                ..._subCategories.map((s) {
                  final code = s['sub_code'] as String? ?? '';
                  final nameEn = s['name_en'] as String? ?? code;
                  final nameAr = s['name_ar'] as String? ?? '';
                  return DropdownMenuItem<String?>(
                    value: code,
                    child: Text(context.trSub(code, nameAr: nameAr, nameEn: nameEn)),
                  );
                }),
              ],
              onChanged: (val) {
                setState(() => _selectedSubCategory = val);
              },
            ),
            const SizedBox(height: 16),

            // ── WHO PAID? ────────────────────────────────────────────────
            Text(
              context.tr('who_paid'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildSegmentOption(
                  isSelected: _selectedPaidBy == 'me',
                  title: context.tr('i_paid'),
                  icon: Icons.credit_card_rounded,
                  activeColor: const Color(0xFF58A6FF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedPaidBy = 'me');
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedPaidBy == 'partner',
                  title: context.tr('partner_paid'),
                  icon: Icons.favorite_outline,
                  activeColor: const Color(0xFFBC8CFF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedPaidBy = 'partner');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── FOR WHOM? ────────────────────────────────────────────────
            Text(
              context.tr('for_whom_title'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'me',
                  title: context.tr('me_solo'),
                  icon: Icons.person_outline,
                  activeColor: const Color(0xFF58A6FF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedBeneficiary = 'me');
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'partner',
                  title: context.tr('partner'),
                  icon: Icons.favorite_outline,
                  activeColor: const Color(0xFFBC8CFF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedBeneficiary = 'partner');
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'both',
                  title: context.tr('both_shared'),
                  icon: Icons.people_alt_outlined,
                  activeColor: const Color(0xFF00C896),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedBeneficiary = 'both');
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('paid_for_whom_title'),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: context.textSecondary,
                  ),
                ),
                InkWell(
                  onTap: _quickAddChild,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.add_rounded, size: 14, color: Color(0xFF00C896)),
                        const SizedBox(width: 2),
                        Text(
                          context.tr('add_child'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF00C896),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_dependents.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: context.subtleCardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: context.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('no_children_hint'),
                        style: GoogleFonts.outfit(fontSize: 11, color: context.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dependents.map((depName) {
                  final isSelected = _selectedBeneficiary.toLowerCase() == depName.toLowerCase();
                  return ChoiceChip(
                    label: Text(depName),
                    avatar: const Icon(Icons.child_care_rounded, size: 14, color: Color(0xFF58A6FF)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF58A6FF).withValues(alpha: 0.2),
                    backgroundColor: context.chipBg,
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF58A6FF) : context.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF58A6FF) : context.borderColor,
                    ),
                    onSelected: (selected) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedBeneficiary = selected ? depName : 'both';
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),

            // Live Settlement Preview
            _buildSettlementPreviewBanner(double.tryParse(_amountCtrl.text) ?? 0.0),
            const SizedBox(height: 20),

            // Line items header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('exact_line_items'),
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16, color: Color(0xFF00C896)),
                  label: Text(context.tr('add_item'), style: const TextStyle(color: Color(0xFF00C896), fontSize: 12)),
                  onPressed: _addItem,
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.tr('no_itemized_breakdown'),
                  style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12),
                ),
              ),

            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final it = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.subtleCardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: it['name'] ?? '',
                        style: TextStyle(color: context.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: context.tr('item_name'),
                          hintStyle: TextStyle(color: context.textSecondary, fontSize: 12),
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
                      icon: Icon(Icons.close, size: 18, color: context.textSecondary),
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
                  : Text(context.tr('save_changes'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
}
