import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../../services/salary_cycle_service.dart';
import '../../models/money.dart';

/// Modal bottom sheet to record received income (Salary, Overtime, Bonus, Side Gig, Roommate Share).
class RecordIncomeSheet extends StatefulWidget {
  final String householdId;
  final String? initialAccountId;

  const RecordIncomeSheet({
    super.key,
    required this.householdId,
    this.initialAccountId,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    String? initialAccountId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: RecordIncomeSheet(
          householdId: householdId,
          initialAccountId: initialAccountId,
        ),
      ),
    );
  }

  @override
  State<RecordIncomeSheet> createState() => _RecordIncomeSheetState();
}

class _RecordIncomeSheetState extends State<RecordIncomeSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _baseAmountCtrl;
  late final TextEditingController _overtimeCtrl;
  late final TextEditingController _bonusCtrl;
  late final TextEditingController _deductionsCtrl;
  late final TextEditingController _notesCtrl;

  IncomeSourceType _selectedSource = IncomeSourceType.salary;
  String? _selectedAccountId;
  List<Account> _accounts = [];
  bool _isLoadingAccounts = true;
  bool _isSaving = false;
  final DateTime _receivedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: 'Monthly Salary');
    _baseAmountCtrl = TextEditingController();
    _overtimeCtrl = TextEditingController();
    _bonusCtrl = TextEditingController();
    _deductionsCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _selectedAccountId = widget.initialAccountId;
    _loadAccounts();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _baseAmountCtrl.dispose();
    _overtimeCtrl.dispose();
    _bonusCtrl.dispose();
    _deductionsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final list = await AccountService.instance.getAccounts(widget.householdId);
      if (mounted) {
        setState(() {
          _accounts = list;
          _isLoadingAccounts = false;
          if (_selectedAccountId == null && list.isNotEmpty) {
            _selectedAccountId = list.first.id;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAccounts = false);
    }
  }

  double get _base => parseMoneyInput(_baseAmountCtrl.text) ?? 0.0;
  double get _overtime => parseMoneyInput(_overtimeCtrl.text) ?? 0.0;
  double get _bonus => parseMoneyInput(_bonusCtrl.text) ?? 0.0;
  double get _deductions => parseMoneyInput(_deductionsCtrl.text) ?? 0.0;
  double get _netTotal => (_base + _overtime + _bonus - _deductions).clamp(0.0, double.infinity);

  String get _currentCycleKey {
    return SalaryCycleService.cycleKeyForInstant(_receivedAt);
  }

  Future<void> _saveIncome() async {
    final targetAccountId = _selectedAccountId;
    if (targetAccountId == null || targetAccountId.isEmpty) {
      AppSnackBar.showError(context, 'Please select a destination account.');
      return;
    }

    if (_base <= 0.0 && _netTotal <= 0.0) {
      AppSnackBar.showError(context, 'Please enter a valid amount.');
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      await AccountService.instance.logIncome(
        householdId: widget.householdId,
        accountId: targetAccountId,
        cycleKey: _currentCycleKey,
        sourceType: _selectedSource,
        title: _titleCtrl.text.trim().isEmpty ? _selectedSource.labelEn : _titleCtrl.text.trim(),
        baseAmount: _base,
        overtime: _overtime,
        bonus: _bonus,
        deductions: _deductions,
        receivedAt: _receivedAt,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.showSuccess(
          context,
          'Deposited SAR ${NumberFormat('#,##0.00').format(_netTotal)} into ${_accounts.firstWhere((a) => a.id == targetAccountId).name}!',
          title: 'Income Recorded',
          icon: Icons.savings_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(context, 'Failed to record income: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final fmt = NumberFormat('#,##0.00');

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: context.borderColor, width: 1.2)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.electricTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.savings_rounded, color: context.electricTeal, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('record_income'),
                        style: GoogleFonts.outfit(
                           color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${context.tr('cycle')} $_currentCycleKey',
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Source Type Selector
            Text(context.tr('income_source'), style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: IncomeSourceType.values.map((src) {
                final isSelected = _selectedSource == src;
                return ChoiceChip(
                  label: Text(context.tr(src.translationKey)),
                  selected: isSelected,
                  selectedColor: context.electricTeal,
                  backgroundColor: context.inputBg,
                  labelStyle: TextStyle(
                    color: isSelected ? context.scaffoldBg : context.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedSource = src;
                        if (_titleCtrl.text.isEmpty || _titleCtrl.text == 'Monthly Salary' || _titleCtrl.text == 'Income') {
                          _titleCtrl.text = context.tr(src.translationKey);
                        }
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Destination Account
            Text(context.tr('destination_account'), style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_isLoadingAccounts)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_accounts.isEmpty)
              Text(context.tr('no_accounts_configured'), style: TextStyle(color: Colors.orange.shade300, fontSize: 13))
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                dropdownColor: context.cardBg,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                ),
                items: _accounts.map((acc) {
                  return DropdownMenuItem<String>(
                    value: acc.id,
                    child: Row(
                      children: [
                        Icon(acc.accountType.defaultIcon, size: 18, color: context.electricTeal),
                        const SizedBox(width: 8),
                        Text('${acc.name} (${acc.currency} ${fmt.format(acc.balance)})', style: TextStyle(color: context.textPrimary)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedAccountId = val),
              ),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _titleCtrl,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('income_title'),
                labelStyle: TextStyle(color: context.textSecondary),
                hintText: context.tr('income_title_hint'),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
              ),
            ),
            const SizedBox(height: 12),

            // Base Amount
            TextField(
              controller: _baseAmountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                labelText: context.tr('base_amount'),
                prefixText: 'SAR ',
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Optional items (Overtime, Bonus, Deductions)
            if (_selectedSource == IncomeSourceType.salary) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _overtimeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '${context.tr('overtime')} (+)',
                        prefixText: 'SAR ',
                        labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                        filled: true,
                        fillColor: context.inputBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _bonusCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '${context.tr('bonus')} (+)',
                        prefixText: 'SAR ',
                        labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                        filled: true,
                        fillColor: context.inputBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deductionsCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                decoration: InputDecoration(
                  labelText: '${context.tr('deductions_gosi')} (-)',
                  prefixText: 'SAR ',
                  labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
            ],

            // Net Deposit Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.electricTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.electricTeal.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.tr('net_deposit_summary'), style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    'SAR ${fmt.format(_netTotal)}',
                    style: TextStyle(color: context.electricTeal, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Submit Button
            ElevatedButton(
              onPressed: _isSaving ? null : _saveIncome,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.electricTeal,
                foregroundColor: context.scaffoldBg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.scaffoldBg))
                  : Text(context.tr('deposit_income'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}
