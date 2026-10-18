import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

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

  double get _base => double.tryParse(_baseAmountCtrl.text) ?? 0.0;
  double get _overtime => double.tryParse(_overtimeCtrl.text) ?? 0.0;
  double get _bonus => double.tryParse(_bonusCtrl.text) ?? 0.0;
  double get _deductions => double.tryParse(_deductionsCtrl.text) ?? 0.0;
  double get _netTotal => (_base + _overtime + _bonus - _deductions).clamp(0.0, double.infinity);

  String get _currentCycleKey {
    final now = _receivedAt;
    if (now.day >= 27) {
      final next = DateTime(now.year, now.month + 1, 1);
      return DateFormat('yyyy-MM').format(next);
    }
    return DateFormat('yyyy-MM').format(now);
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
                    color: const Color(0xFF00C896).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.savings_rounded, color: Color(0xFF00C896), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record Income',
                        style: GoogleFonts.outfit(
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Cycle $_currentCycleKey',
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Source Type Selector
            Text('Income Source', style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: IncomeSourceType.values.map((src) {
                final isSelected = _selectedSource == src;
                return ChoiceChip(
                  label: Text(src.labelEn),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00C896),
                  backgroundColor: context.inputBg,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : context.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedSource = src;
                        if (_titleCtrl.text.isEmpty || _titleCtrl.text == 'Monthly Salary' || _titleCtrl.text == 'Income') {
                          _titleCtrl.text = src.labelEn;
                        }
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Destination Account
            Text('Destination Account', style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_isLoadingAccounts)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_accounts.isEmpty)
              Text('No accounts found. Please create an account first.', style: TextStyle(color: Colors.orange.shade300, fontSize: 13))
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
                        Icon(acc.accountType.defaultIcon, size: 18, color: const Color(0xFF00C896)),
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
                labelText: 'Title / Description',
                labelStyle: TextStyle(color: context.textSecondary),
                hintText: 'e.g. October Salary, Q3 Bonus',
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
                labelText: 'Base Amount',
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
                        labelText: 'Overtime (+)',
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
                        labelText: 'Bonus (+)',
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
                  labelText: 'Deductions / GOSI (-)',
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
                color: const Color(0xFF00C896).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Net Deposit to Account:', style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    'SAR ${fmt.format(_netTotal)}',
                    style: const TextStyle(color: Color(0xFF00C896), fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Submit Button
            ElevatedButton(
              onPressed: _isSaving ? null : _saveIncome,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Deposit Income', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}
