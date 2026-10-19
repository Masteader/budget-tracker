import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Assistant sheet to distribute newly received salary from bank into
/// e-wallets, cash, or savings accounts in one seamless workflow.
class SalaryDistributionAssistantSheet extends StatefulWidget {
  final String householdId;
  final Account sourceAccount;
  final double netSalaryAmount;
  final VoidCallback? onComplete;

  const SalaryDistributionAssistantSheet({
    super.key,
    required this.householdId,
    required this.sourceAccount,
    required this.netSalaryAmount,
    this.onComplete,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    required Account sourceAccount,
    required double netSalaryAmount,
    VoidCallback? onComplete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SalaryDistributionAssistantSheet(
        householdId: householdId,
        sourceAccount: sourceAccount,
        netSalaryAmount: netSalaryAmount,
        onComplete: onComplete,
      ),
    );
  }

  @override
  State<SalaryDistributionAssistantSheet> createState() =>
      _SalaryDistributionAssistantSheetState();
}

class _SalaryDistributionAssistantSheetState
    extends State<SalaryDistributionAssistantSheet> {
  final _fmt = NumberFormat('#,##0.00', 'en_US');
  List<Account> _targetAccounts = [];
  bool _isLoading = true;
  bool _isExecuting = false;

  // Map of accountId -> TextEditingController
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final all = await AccountService.instance.getAccounts(widget.householdId);
      if (mounted) {
        setState(() {
          // Exclude source account
          _targetAccounts =
              all.where((a) => a.id != widget.sourceAccount.id && !a.isArchived).toList();
          for (final a in _targetAccounts) {
            _controllers[a.id] = TextEditingController(text: '');
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalAllocated {
    double sum = 0.0;
    for (final c in _controllers.values) {
      final v = double.tryParse(c.text.trim()) ?? 0.0;
      sum += v;
    }
    return sum;
  }

  double get _remainingInBank => widget.netSalaryAmount - _totalAllocated;

  Future<void> _executeDistribution() async {
    final targets = <String, double>{};
    for (final entry in _controllers.entries) {
      final val = double.tryParse(entry.value.text.trim()) ?? 0.0;
      if (val > 0) {
        targets[entry.key] = val;
      }
    }

    if (targets.isEmpty) {
      Navigator.pop(context);
      return;
    }

    if (_remainingInBank < -0.01) {
      AppSnackBar.showError(
        context,
        context.trArgs('sda_over_msg', {'amount': context.sar(-_remainingInBank)}),
          title: context.tr('overallocated'),
      );
      return;
    }

    setState(() => _isExecuting = true);

    try {
      int successCount = 0;
      for (final entry in targets.entries) {
        final targetAcc = _targetAccounts.firstWhere((a) => a.id == entry.key);
        await AccountService.instance.transferFunds(
          householdId: widget.householdId,
          fromAccountId: widget.sourceAccount.id,
          toAccountId: entry.key,
          amount: entry.value,
          fee: 0.0,
          notes: 'Payday auto-distribution to ${targetAcc.name}',
        );
        successCount++;
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onComplete?.call();
        AppSnackBar.showSuccess(
          context,
          context.trArgs('sda_done_msg', {'count': successCount}),
          title: context.tr('sda_done_title'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExecuting = false);
        AppSnackBar.showError(
          context,
          context.trArgs('sda_failed_msg', {'error': e}),
          title: context.tr('sda_failed_title'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final totalAllocated = _totalAllocated;
    final remaining = _remainingInBank;
    final isOverallocated = remaining < -0.01;

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
        maxHeight: MediaQuery.of(context).size.height * 0.88,
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

          // Title & Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.electricTeal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alt_route_rounded,
                  color: context.electricTeal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('distribute_salary'),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      context.tr('distribute_salary_desc'),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('close'),
                icon: Icon(Icons.close, color: context.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Allocation Tracker
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF09223D), const Color(0xFF0A1828)]
                    : [const Color(0xFFE6FAF5), const Color(0xFFF0FDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isOverallocated
                    ? Colors.redAccent.withValues(alpha: 0.5)
                    : context.electricTeal.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${context.tr('from_source_account')}: ${widget.sourceAccount.name}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.sar(widget.netSalaryAmount),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 36,
                  width: 1,
                  color: context.borderColor,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      context.tr('remaining_in_bank'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isOverallocated ? Colors.redAccent : context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.sar(remaining),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isOverallocated
                            ? Colors.redAccent
                            : context.electricTeal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Accounts List
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: context.electricTeal),
              ),
            )
          else if (_targetAccounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.tr('no_secondary_accounts'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _targetAccounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final acc = _targetAccounts[i];
                  final ctrl = _controllers[acc.id]!;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          acc.accountType.defaultIcon,
                          size: 22,
                          color: context.electricTeal,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                acc.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                '${context.tr(acc.accountType.translationKey)} • ${context.tr('current_balance')}: ${context.sar(acc.balance)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.end,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: context.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                color: context.textSecondary.withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                              prefixText: '${context.tr('sar')} ',
                              prefixStyle: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              fillColor: context.scaffoldBg,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: context.borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: context.electricTeal, width: 1.5),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isExecuting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: context.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    context.tr('keep_all_in_bank'),
                    style: TextStyle(
                      color: context.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_isExecuting || isOverallocated || totalAllocated <= 0)
                      ? null
                      : _executeDistribution,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.electricTeal,
                    foregroundColor: context.scaffoldBg,
                    disabledBackgroundColor: context.chipBg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isExecuting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.scaffoldBg,
                          ),
                        )
                      : Text(
                          '${context.tr('execute_distribution')} (${_fmt.format(totalAllocated)})',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
