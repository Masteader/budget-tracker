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
  bool _isSaving = false;

  // Role-Aware Attribution & Living Model State
  bool _isRoommateMode = false;
  String _familyPayer = 'me'; // 'me' (Husband/Provider), 'wife_reimbursable', 'wife_personal'
  String? _selectedRoommateId;
  String _roommateSplit = 'all'; // 'all' (equal split) | 'personal'
  List<Map<String, dynamic>> _householdMembers = [];

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
    _loadHouseholdMembers();
  }

  Future<void> _loadHouseholdMembers() async {
    final hid = widget.householdId;
    if (hid == null || hid.isEmpty) return;
    try {
      final res = await supabase
          .from('users')
          .select('id, display_name, role, financial_role')
          .eq('household_id', hid);
      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res);
        final hasPeers = list.any((m) => (m['financial_role'] as String?)?.toLowerCase() == 'peer');
        final hasSpouse = list.any((m) => (m['financial_role'] as String?)?.toLowerCase() == 'spouse');
        setState(() {
          _householdMembers = list;
          _isRoommateMode = hasPeers && !hasSpouse;
          if (_isRoommateMode && list.isNotEmpty) {
            final uid = supabase.auth.currentUser?.id;
            final myMember = list.firstWhere(
              (m) => m['id'] == uid,
              orElse: () => list.first,
            );
            _selectedRoommateId = myMember['id'] as String?;
          }
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

    // Determine role-aware attribution fields
    final String paidBy;
    final String benType;
    final String benId;
    final String spentBy;

    if (_isRoommateMode) {
      paidBy = _selectedRoommateId ?? supabase.auth.currentUser?.id ?? 'me';
      benType = _roommateSplit == 'all' ? 'all_peers' : 'individual';
      benId = _roommateSplit == 'all' ? 'all_peers' : (_selectedRoommateId ?? 'me');
      spentBy = _roommateSplit == 'all' ? 'both' : 'me';
    } else {
      if (_familyPayer == 'wife_reimbursable') {
        paidBy = 'wife';
        benType = 'household';
        benId = 'household';
        spentBy = 'partner';
      } else if (_familyPayer == 'wife_personal') {
        paidBy = 'wife';
        benType = 'individual';
        benId = 'wife';
        spentBy = 'partner';
      } else {
        paidBy = 'me';
        benType = 'household';
        benId = 'household';
        spentBy = 'me';
      }
    }

    try {
      // 1. Direct Supabase insert
      await supabase.from('transactions').insert({
        'household_id': hid,
        'amount': amount,
        'currency': 'SAR',
        'merchant': merchant,
        'category_code': _selectedCategory,
        'spent_by': spentBy,
        'paid_by': paidBy,
        'beneficiary_type': benType,
        'beneficiary_id': benId,
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
            'paid_by': paidBy,
            'beneficiary_type': benType,
            'beneficiary_id': benId,
            'spent_by': spentBy,
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

              // Paid By & Responsibility Attribution
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('paid_by_label'),
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: context.subtleCardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildModeTogglePill(
                          label: context.tr('household_model_family'),
                          icon: Icons.family_restroom_rounded,
                          isSelected: !_isRoommateMode,
                          onTap: () => setState(() => _isRoommateMode = false),
                        ),
                        _buildModeTogglePill(
                          label: context.tr('household_model_roommates'),
                          icon: Icons.groups_rounded,
                          isSelected: _isRoommateMode,
                          onTap: () => setState(() => _isRoommateMode = true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (!_isRoommateMode) ...[
                // Family Islamic Nafaqah options
                Row(
                  children: [
                    _buildSegmentOption(
                      isSelected: _familyPayer == 'me',
                      label: context.tr('payer_nafaqah_me'),
                      icon: Icons.shield_outlined,
                      activeColor: const Color(0xFF00C896),
                      onTap: () => setState(() => _familyPayer = 'me'),
                    ),
                    const SizedBox(width: 8),
                    _buildSegmentOption(
                      isSelected: _familyPayer == 'wife_reimbursable',
                      label: context.tr('payer_nafaqah_wife_reimbursable'),
                      icon: Icons.currency_exchange_rounded,
                      activeColor: const Color(0xFFFFA657),
                      onTap: () => setState(() => _familyPayer = 'wife_reimbursable'),
                    ),
                    const SizedBox(width: 8),
                    _buildSegmentOption(
                      isSelected: _familyPayer == 'wife_personal',
                      label: context.tr('payer_nafaqah_wife_personal'),
                      icon: Icons.shopping_bag_outlined,
                      activeColor: const Color(0xFF4DE6F7),
                      onTap: () => setState(() => _familyPayer = 'wife_personal'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_familyPayer == 'wife_reimbursable'
                            ? const Color(0xFFFFA657)
                            : _familyPayer == 'wife_personal'
                                ? const Color(0xFF4DE6F7)
                                : const Color(0xFF00C896))
                        .withValues(alpha: context.isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_familyPayer == 'wife_reimbursable'
                              ? const Color(0xFFFFA657)
                              : _familyPayer == 'wife_personal'
                                  ? const Color(0xFF4DE6F7)
                                  : const Color(0xFF00C896))
                          .withValues(alpha: context.isDark ? 0.35 : 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _familyPayer == 'wife_reimbursable'
                            ? Icons.info_outline_rounded
                            : _familyPayer == 'wife_personal'
                                ? Icons.person_outline_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 15,
                        color: _familyPayer == 'wife_reimbursable'
                            ? const Color(0xFFFFA657)
                            : _familyPayer == 'wife_personal'
                                ? const Color(0xFF4DE6F7)
                                : const Color(0xFF00C896),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _familyPayer == 'wife_reimbursable'
                              ? context.tr('nafaqah_wife_reimbursable_hint')
                              : _familyPayer == 'wife_personal'
                                  ? context.tr('nafaqah_wife_personal_hint')
                                  : context.tr('nafaqah_me_hint'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Multi-Roommate Living Mode
                if (_householdMembers.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Payer:',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _householdMembers.map((m) {
                        final mid = m['id'] as String? ?? '';
                        final name = (m['display_name'] as String?)?.isNotEmpty == true
                            ? m['display_name'] as String
                            : 'Roommate';
                        final isSelected = _selectedRoommateId == mid;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(name),
                            selected: isSelected,
                            onSelected: (sel) {
                              if (sel) setState(() => _selectedRoommateId = mid);
                            },
                            selectedColor: const Color(0xFF00C896).withValues(alpha: 0.2),
                            backgroundColor: context.subtleCardBg,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? (context.isDark ? const Color(0xFF00E5BF) : const Color(0xFF00A87A))
                                  : context.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF00C896) : context.borderColor,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    _buildSegmentOption(
                      isSelected: _roommateSplit == 'all',
                      label: context.tr('roommate_split_all'),
                      icon: Icons.groups_rounded,
                      activeColor: const Color(0xFF00C896),
                      onTap: () => setState(() => _roommateSplit = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _buildSegmentOption(
                      isSelected: _roommateSplit == 'personal',
                      label: context.tr('roommate_split_personal'),
                      icon: Icons.lock_outline_rounded,
                      activeColor: const Color(0xFF4DE6F7),
                      onTap: () => setState(() => _roommateSplit = 'personal'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_roommateSplit == 'all'
                            ? const Color(0xFF00C896)
                            : const Color(0xFF4DE6F7))
                        .withValues(alpha: context.isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_roommateSplit == 'all'
                              ? const Color(0xFF00C896)
                              : const Color(0xFF4DE6F7))
                          .withValues(alpha: context.isDark ? 0.35 : 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _roommateSplit == 'all' ? Icons.pie_chart_outline_rounded : Icons.lock_outline_rounded,
                        size: 15,
                        color: _roommateSplit == 'all' ? const Color(0xFF00C896) : const Color(0xFF4DE6F7),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _roommateSplit == 'all'
                              ? context.tr('roommate_split_all_hint')
                              : context.tr('roommate_split_personal_hint'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildModeTogglePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (context.isDark ? const Color(0xFF00C896) : const Color(0xFF00A87A))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.black : context.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : context.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentOption({
    required bool isSelected,
    required String label,
    required IconData icon,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: context.isDark ? 0.18 : 0.12) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : context.borderColor,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? activeColor : context.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? activeColor : context.textSecondary,
                  fontSize: 11,
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
