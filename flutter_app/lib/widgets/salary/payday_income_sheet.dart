import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import 'salary_distribution_assistant_sheet.dart';

/// Modal bottom sheet prompted on or around Payday (e.g. 27th) to log itemized salary
/// (Base + Overtime + Bonus + Side - Deductions) into a designated bank account,
/// followed by an optional 1-tap distribution assistant.
class PaydayIncomeSheet extends StatefulWidget {
  final String householdId;
  final VoidCallback? onCompleted;

  const PaydayIncomeSheet({
    super.key,
    required this.householdId,
    this.onCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    VoidCallback? onCompleted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaydayIncomeSheet(
        householdId: householdId,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<PaydayIncomeSheet> createState() => _PaydayIncomeSheetState();
}

class _PaydayIncomeSheetState extends State<PaydayIncomeSheet> {
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  final _baseController = TextEditingController();
  final _overtimeController = TextEditingController();
  final _bonusController = TextEditingController();
  final _sideGigController = TextEditingController();
  final _deductionsController = TextEditingController();

  List<Account> _accounts = [];
  String? _selectedAccountId;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadAccountsAndDefaults();
  }

  @override
  void dispose() {
    _baseController.dispose();
    _overtimeController.dispose();
    _bonusController.dispose();
    _sideGigController.dispose();
    _deductionsController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountsAndDefaults() async {
    try {
      final list = await AccountService.instance.getAccounts(widget.householdId);
      if (mounted) {
        setState(() {
          _accounts = list.where((a) => !a.isArchived).toList();
          // Pick the first bank account by default, or the first account
          final bank = _accounts.where((a) => a.accountType == AccountType.bank).firstOrNull;
          _selectedAccountId = bank?.id ?? _accounts.firstOrNull?.id;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _base => double.tryParse(_baseController.text.trim()) ?? 0.0;
  double get _overtime => double.tryParse(_overtimeController.text.trim()) ?? 0.0;
  double get _bonus => double.tryParse(_bonusController.text.trim()) ?? 0.0;
  double get _sideGig => double.tryParse(_sideGigController.text.trim()) ?? 0.0;
  double get _deductions => double.tryParse(_deductionsController.text.trim()) ?? 0.0;

  double get _grossPay => _base + _overtime + _bonus + _sideGig;
  double get _netTakeHome => _grossPay - _deductions;

  Future<void> _confirmDeposit() async {
    final net = _netTakeHome;
    if (net <= 0) {
      AppSnackBar.showError(
        context,
        'Please enter a valid salary breakdown with positive take-home pay.',
        title: 'Invalid Salary',
      );
      return;
    }

    if (_selectedAccountId == null) {
      AppSnackBar.showError(
        context,
        'Please select a destination account for the deposit.',
        title: 'Account Required',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final destAccount = _accounts.firstWhere((a) => a.id == _selectedAccountId);
      final notes = 'Base: SAR ${_fmt.format(_base)}'
          '${_overtime > 0 ? " | OT: SAR ${_fmt.format(_overtime)}" : ""}'
          '${_bonus > 0 ? " | Bonus: SAR ${_fmt.format(_bonus)}" : ""}'
          '${_sideGig > 0 ? " | Side: SAR ${_fmt.format(_sideGig)}" : ""}'
          '${_deductions > 0 ? " | Ded: -SAR ${_fmt.format(_deductions)}" : ""}';

      final now = DateTime.now();
      final cycleKey = DateFormat('yyyy-MM').format(
        now.day >= 27 ? DateTime(now.year, now.month + 1, 1) : now,
      );

      await AccountService.instance.logIncome(
        householdId: widget.householdId,
        accountId: _selectedAccountId!,
        cycleKey: cycleKey,
        sourceType: IncomeSourceType.salary,
        title: 'Monthly Salary',
        baseAmount: _base + _sideGig,
        overtime: _overtime,
        bonus: _bonus,
        deductions: _deductions,
        notes: notes,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCompleted?.call();

        AppSnackBar.showSuccess(
          context,
          'Deposited SAR ${_fmt.format(net)} to ${destAccount.name}!',
          title: 'Salary Deposited',
        );

        // Prompt salary distribution assistant
        SalaryDistributionAssistantSheet.show(
          context,
          householdId: widget.householdId,
          sourceAccount: destAccount,
          netSalaryAmount: net,
          onComplete: widget.onCompleted,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackBar.showError(
          context,
          'Failed to record salary deposit: $e',
          title: 'Error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final net = _netTakeHome;

    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
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

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5BF), Color(0xFF4DE6F7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  color: Color(0xFF051424),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payday Check-in',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Break down your income & net take-home',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: context.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Net Take-Home Hero Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF06223B), const Color(0xFF041727)]
                    : [const Color(0xFFE6FAF5), const Color(0xFFDCF7F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF00E5BF).withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NET TAKE-HOME PAY',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: const Color(0xFF00E5BF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SAR ${_fmt.format(net > 0 ? net : 0.0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: net >= 0 ? context.textPrimary : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5BF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Color(0xFF00E5BF), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Ready',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF00E5BF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Form Fields (Scrollable)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Base Salary
                  _buildInputField(
                    label: 'Base Salary',
                    hint: 'e.g. 10000',
                    controller: _baseController,
                    prefixIcon: Icons.account_balance_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Overtime & Bonus in a row
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(
                          label: 'Overtime',
                          hint: '0.00',
                          controller: _overtimeController,
                          prefixIcon: Icons.timer_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInputField(
                          label: 'Bonus',
                          hint: '0.00',
                          controller: _bonusController,
                          prefixIcon: Icons.card_giftcard_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Side Gigs & Deductions in a row
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(
                          label: 'Side Gigs',
                          hint: '0.00',
                          controller: _sideGigController,
                          prefixIcon: Icons.work_outline_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInputField(
                          label: 'Deductions (GOSI/Tax)',
                          hint: '0.00',
                          controller: _deductionsController,
                          prefixIcon: Icons.remove_circle_outline,
                          isDeduction: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Destination Account Selector
                  Text(
                    'Deposit Destination Account',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_isLoading)
                    const Center(child: CircularProgressIndicator(color: Color(0xFF00E5BF)))
                  else if (_accounts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Text(
                        'No accounts found. Please add an account first.',
                        style: TextStyle(color: context.textSecondary, fontSize: 13),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _accounts.map((acc) {
                        final isSel = acc.id == _selectedAccountId;
                        return ChoiceChip(
                          avatar: Icon(
                            acc.accountType.defaultIcon,
                            size: 14,
                            color: isSel ? const Color(0xFF051424) : const Color(0xFF00E5BF),
                          ),
                          label: Text(acc.name),
                          selected: isSel,
                          selectedColor: const Color(0xFF00E5BF),
                          labelStyle: TextStyle(
                            color: isSel ? const Color(0xFF051424) : context.textPrimary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            fontSize: 12,
                          ),
                          backgroundColor: context.cardBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSel ? const Color(0xFF00E5BF) : context.borderColor,
                            ),
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _selectedAccountId = acc.id);
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Confirm Button
          ElevatedButton(
            onPressed: (_isSubmitting || net <= 0) ? null : _confirmDeposit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5BF),
              foregroundColor: const Color(0xFF051424),
              disabledBackgroundColor: context.chipBg,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF051424),
                    ),
                  )
                : Text(
                    'Confirm & Deposit (${_fmt.format(net > 0 ? net : 0)})',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData prefixIcon,
    bool isDeduction = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDeduction ? Colors.redAccent : context.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: context.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: context.textSecondary.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            prefixIcon: Icon(
              prefixIcon,
              size: 18,
              color: isDeduction ? Colors.redAccent : const Color(0xFF00E5BF),
            ),
            prefixText: 'SAR ',
            prefixStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDeduction ? Colors.redAccent : context.textSecondary,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            fillColor: context.cardBg,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDeduction ? Colors.redAccent : const Color(0xFF00E5BF),
                width: 1.5,
              ),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
