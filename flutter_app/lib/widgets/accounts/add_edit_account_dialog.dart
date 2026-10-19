import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';

/// Dialog to create or edit an account.
class AddEditAccountDialog extends StatefulWidget {
  final String householdId;
  final Account? existingAccount;
  final VoidCallback? onSuccess;

  const AddEditAccountDialog({
    super.key,
    required this.householdId,
    this.existingAccount,
    this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    Account? existingAccount,
    VoidCallback? onSuccess,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AddEditAccountDialog(
        householdId: householdId,
        existingAccount: existingAccount,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<AddEditAccountDialog> createState() => _AddEditAccountDialogState();
}

class _AddEditAccountDialogState extends State<AddEditAccountDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  AccountType _type = AccountType.bank;
  String _currency = 'SAR';
  bool _isSharedPool = false;
  bool _isSubmitting = false;

  final List<String> _supportedCurrencies = ['SAR', 'USD', 'USDT', 'EUR', 'AED'];

  @override
  void initState() {
    super.initState();
    final acc = widget.existingAccount;
    _nameCtrl = TextEditingController(text: acc?.name ?? '');
    _balanceCtrl = TextEditingController(text: acc != null ? acc.balance.toStringAsFixed(2) : '0.00');
    if (acc != null) {
      _type = acc.accountType;
      _currency = acc.currency;
      _isSharedPool = acc.isSharedPool;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingAccount != null;

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppSnackBar.showError(context, context.tr('enter_account_name'));
      return;
    }

    final balance = parseMoneyInput(_balanceCtrl.text) ?? 0.0;
    setState(() => _isSubmitting = true);

    try {
      if (_isEditing) {
        final updated = widget.existingAccount!.copyWith(
          name: name,
          accountType: _type,
          currency: _currency,
          balance: balance,
          isSharedPool: _isSharedPool,
        );
        await AccountService.instance.updateAccount(updated);
        if (balance != widget.existingAccount!.balance) {
          await AccountService.instance.updateBalance(widget.existingAccount!.id, balance);
        }
      } else {
        await AccountService.instance.createAccount(
          householdId: widget.householdId,
          name: name,
          accountType: _type,
          currency: _currency,
          initialBalance: balance,
          isSharedPool: _isSharedPool,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess?.call();
        AppSnackBar.showSuccess(
          context,
          _isEditing ? context.trArgs('aea_updated_msg', {'name': name}) : context.trArgs('aea_created_msg', {'name': name}),
          title: _isEditing ? context.tr('aea_updated_title') : context.tr('aea_created_title'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackBar.showError(context, context.trArgs('aea_save_failed', {'error': e}));
      }
    }
  }

  Future<void> _archive() async {
    if (!_isEditing) return;
    setState(() => _isSubmitting = true);
    try {
      await AccountService.instance.archiveAccount(widget.existingAccount!.id);
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess?.call();
        AppSnackBar.showSuccess(context, context.tr('aea_archived'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackBar.showError(context, context.trArgs('aea_archive_failed', {'error': e}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        _isEditing ? context.tr('edit_account') : context.tr('new_account'),
        style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Account Name
            TextField(
              controller: _nameCtrl,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('account_name'),
                hintText: context.tr('account_name_hint'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Account Type
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('account_type'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: AccountType.values.map((t) {
                return DropdownMenuItem<AccountType>(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.defaultIcon, size: 18, color: context.electricTeal),
                      const SizedBox(width: 8),
                      Text(context.tr(t.translationKey)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _type = val;
                    if (val == AccountType.sharedPool) _isSharedPool = true;
                  });
                }
              },
            ),
            const SizedBox(height: 12),

            // Currency & Balance
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _supportedCurrencies.contains(_currency) ? _currency : _supportedCurrencies.first,
                    dropdownColor: context.cardBg,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.tr('currency'),
                      labelStyle: TextStyle(color: context.textSecondary),
                      filled: true,
                      fillColor: context.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _supportedCurrencies.map((c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _currency = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: _isEditing ? context.tr('current_balance') : context.tr('initial_balance'),
                      labelStyle: TextStyle(color: context.textSecondary),
                      filled: true,
                      fillColor: context.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Shared Pool Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('shared_household_pool'), style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(context.tr('shared_pool_desc'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
              value: _isSharedPool,
              activeThumbColor: context.electricTeal,
              onChanged: (v) => setState(() => _isSharedPool = v),
            ),

            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _isSubmitting ? null : _archive,
                icon: const Icon(Icons.archive_outlined, size: 16, color: Colors.redAccent),
                label: Text(context.tr('archive_account'), style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.electricTeal,
            foregroundColor: context.scaffoldBg,
          ),
          child: _isSubmitting
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.scaffoldBg))
              : Text(_isEditing ? context.tr('save_changes') : context.tr('create_account'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
