import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';

/// Dialog to reconcile app account balance against actual bank/wallet balance.
class ReconcileBalanceDialog extends StatefulWidget {
  final Account account;
  final VoidCallback? onReconcileSuccess;

  const ReconcileBalanceDialog({
    super.key,
    required this.account,
    this.onReconcileSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required Account account,
    VoidCallback? onReconcileSuccess,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ReconcileBalanceDialog(
        account: account,
        onReconcileSuccess: onReconcileSuccess,
      ),
    );
  }

  @override
  State<ReconcileBalanceDialog> createState() => _ReconcileBalanceDialogState();
}

class _ReconcileBalanceDialogState extends State<ReconcileBalanceDialog> {
  late final TextEditingController _actualBalanceCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _actualBalanceCtrl = TextEditingController(text: widget.account.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _actualBalanceCtrl.dispose();
    super.dispose();
  }

  double get _actualBalance => parseMoneyInput(_actualBalanceCtrl.text) ?? widget.account.balance;
  double get _variance => _actualBalance - widget.account.balance;

  Future<void> _submitReconciliation() async {
    setState(() => _isSaving = true);
    try {
      await AccountService.instance.updateBalance(widget.account.id, _actualBalance);
      if (mounted) {
        Navigator.pop(context);
        widget.onReconcileSuccess?.call();
        AppSnackBar.showSuccess(
          context,
          '${widget.account.name} balance updated to ${widget.account.currency} ${NumberFormat('#,##0.00').format(_actualBalance)}',
          title: context.tr('balance_reconciled'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(context, 'Failed to reconcile balance: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    return AlertDialog(
      backgroundColor: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.electricTeal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune_rounded, color: context.electricTeal, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('reconcile_balance'),
              style: GoogleFonts.outfit(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('reconcile_dialog_desc'),
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Current App Balance
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.inputBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.tr('app_balance'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                  Text(
                    '${widget.account.currency} ${fmt.format(widget.account.balance)}',
                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Actual Bank Balance Input
            TextField(
              controller: _actualBalanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                labelText: context.tr('actual_balance'),
                prefixText: '${widget.account.currency} ',
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Variance Indicator
            if (_variance.abs() > 0.001)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _variance > 0
                      ? context.electricTeal.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _variance > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 16,
                      color: _variance > 0 ? context.electricTeal : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${context.tr('adjustment')}: ${_variance > 0 ? '+' : ''}${fmt.format(_variance)} ${widget.account.currency}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _variance > 0 ? context.electricTeal : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submitReconciliation,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.electricTeal,
            foregroundColor: context.scaffoldBg,
          ),
          child: _isSaving
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.scaffoldBg))
              : Text(context.tr('update_balance'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
