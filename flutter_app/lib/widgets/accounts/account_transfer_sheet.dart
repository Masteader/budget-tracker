import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../providers/household_role_provider.dart';
import '../../services/account_service.dart';
import '../../services/household_permissions.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';

typedef AccountsLoader = Future<List<Account>> Function(String householdId);

/// Modal bottom sheet for executing an inter-account fund transfer.
///
/// Money leaves a shared pool only by a household admin (DB-16): for members,
/// shared pools are offered as destinations but never as the source.
class AccountTransferSheet extends StatefulWidget {
  final String householdId;
  final String? prefilledFromAccountId;
  final String? prefilledToAccountId;
  final double? prefilledAmount;
  final VoidCallback? onTransferSuccess;

  /// Role overrides; by default read from [HouseholdRoleProvider].
  final bool? isAdmin;
  final String? currentUserId;
  final AccountsLoader? loadAccounts;

  const AccountTransferSheet({
    super.key,
    required this.householdId,
    this.prefilledFromAccountId,
    this.prefilledToAccountId,
    this.prefilledAmount,
    this.onTransferSuccess,
    this.isAdmin,
    this.currentUserId,
    this.loadAccounts,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    String? prefilledFromAccountId,
    String? prefilledToAccountId,
    double? prefilledAmount,
    VoidCallback? onTransferSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: AccountTransferSheet(
          householdId: householdId,
          prefilledFromAccountId: prefilledFromAccountId,
          prefilledToAccountId: prefilledToAccountId,
          prefilledAmount: prefilledAmount,
          onTransferSuccess: onTransferSuccess,
        ),
      ),
    );
  }

  @override
  State<AccountTransferSheet> createState() => _AccountTransferSheetState();
}

class _AccountTransferSheetState extends State<AccountTransferSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _notesCtrl;

  String? _fromAccountId;
  String? _toAccountId;
  List<Account> _accounts = [];
  List<Account> _sourceAccounts = [];
  bool _sharedPoolsHidden = false;
  bool _isLoadingAccounts = true;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.prefilledAmount != null && widget.prefilledAmount! > 0
          ? widget.prefilledAmount!.toStringAsFixed(2)
          : '',
    );
    _feeCtrl = TextEditingController(text: '0.00');
    _notesCtrl = TextEditingController();
    _fromAccountId = widget.prefilledFromAccountId;
    _toAccountId = widget.prefilledToAccountId;
    _loadAccounts();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  HouseholdRoleProvider? _roles() {
    try {
      return context.read<HouseholdRoleProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _loadAccounts() async {
    final roles = _roles();
    try {
      if (widget.isAdmin == null && roles != null && !roles.isLoaded && roles.householdId != null) {
        await roles.refresh();
      }
      final loader = widget.loadAccounts ?? AccountService.instance.getAccounts;
      final list = await loader(widget.householdId);
      final isAdmin = widget.isAdmin ?? roles?.isAdmin ?? false;
      final currentUserId = widget.currentUserId ?? roles?.currentUserId;
      final sources = HouseholdPermissions.withdrawableAccounts(list, currentUserId: currentUserId, isAdmin: isAdmin);
      if (mounted) {
        setState(() {
          _accounts = list;
          _sourceAccounts = sources;
          _sharedPoolsHidden = !isAdmin && list.any(HouseholdPermissions.isSharedPool);
          _isLoadingAccounts = false;

          if (_fromAccountId != null && !sources.any((a) => a.id == _fromAccountId)) {
            _fromAccountId = null;
          }
          // If no initial selection, choose the first allowed source and another destination
          if (_fromAccountId == null && sources.isNotEmpty) {
            _fromAccountId = sources.first.id;
          }
          if (_toAccountId == null) {
            final others = list.where((a) => a.id != _fromAccountId);
            if (others.isNotEmpty) _toAccountId = others.first.id;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAccounts = false);
    }
  }

  double get _amount => parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0;
  /// The optional fee: empty is 0; a negative or unreadable fee is null
  /// (FABLE2-APP-07: a negative fee used to credit the source account).
  double? get _parsedFee =>
      _feeCtrl.text.trim().isEmpty ? 0.0 : parseMoneyInput(_feeCtrl.text, allowNegative: false);
  double get _fee => _parsedFee ?? 0.0;
  double get _totalDeduction => _amount + _fee;

  Account? get _fromAccount =>
      _accounts.where((a) => a.id == _fromAccountId).firstOrNull;
  Account? get _toAccount =>
      _accounts.where((a) => a.id == _toAccountId).firstOrNull;

  Future<void> _executeTransfer() async {
    if (_fromAccountId == null || _toAccountId == null) {
      AppSnackBar.showError(context, context.tr('ats_select_both'));
      return;
    }

    if (_fromAccountId == _toAccountId) {
      AppSnackBar.showError(context, context.tr('ats_same_account'));
      return;
    }

    if (_amount <= 0.0) {
      AppSnackBar.showError(context, context.tr('ats_invalid_amount'));
      return;
    }

    if (_parsedFee == null) {
      AppSnackBar.showError(context, context.tr('ats_invalid_fee'));
      return;
    }

    final from = _fromAccount;
    if (from != null && from.balance < _totalDeduction) {
      AppSnackBar.showError(
        context,
        context.trArgs('ats_insufficient', {'account': from.name, 'amount': from.currency == 'SAR' ? context.sar(from.balance) : '${from.currency} ${from.balance.toStringAsFixed(2)}'}),
      );
      return;
    }

    setState(() => _isTransferring = true);
    HapticFeedback.mediumImpact();

    try {
      await AccountService.instance.transferFunds(
        householdId: widget.householdId,
        fromAccountId: _fromAccountId!,
        toAccountId: _toAccountId!,
        amount: _amount,
        fee: _fee,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onTransferSuccess?.call();
        AppSnackBar.showSuccess(
          context,
          context.trArgs('ats_done_msg', {'amount': context.sar(_amount), 'from': from?.name, 'to': _toAccount?.name}),
          title: context.tr('ats_done_title'),
          icon: Icons.swap_horiz_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTransferring = false);
        AppSnackBar.showError(
          context,
          HouseholdPermissions.isPermissionDenied(e)
              ? context.tr('perm_pool_admin_only')
              : context.trArgs('ats_failed', {'error': e}),
        );
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
                  child: Icon(Icons.swap_horiz_rounded, color: context.electricTeal, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('transfer_funds'),
                    style: GoogleFonts.outfit(
                      color: context.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isLoadingAccounts)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_accounts.length < 2 || _sourceAccounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Text(
                  context.tr('need_two_accounts_transfer'),
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                ),
              )
            else ...[
              // Source Account (From)
              Text(context.tr('from_source_account'), style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _fromAccountId,
                dropdownColor: context.cardBg,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                ),
                items: _sourceAccounts.map((acc) {
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
                onChanged: (val) => setState(() => _fromAccountId = val),
              ),
              if (_sharedPoolsHidden) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 13, color: context.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr('perm_pool_hidden_hint'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Swap icon indicator
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.inputBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Icon(Icons.arrow_downward_rounded, size: 16, color: context.electricTeal),
                ),
              ),
              const SizedBox(height: 12),

              // Destination Account (To)
              Text(context.tr('to_destination_account'), style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _toAccountId,
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
                onChanged: (val) => setState(() => _toAccountId = val),
              ),
              const SizedBox(height: 16),

              // Transfer Amount
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                decoration: InputDecoration(
                  labelText: context.tr('transfer_amount'),
                  prefixText: '${context.tr('sar')} ',
                  labelStyle: TextStyle(color: context.textSecondary),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Fee & Notes
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: context.tr('transfer_fee'),
                        prefixText: '${context.tr('sar')} ',
                        labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                        filled: true,
                        fillColor: context.inputBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _notesCtrl,
                style: TextStyle(color: context.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: context.tr('notes_optional'),
                  hintText: context.tr('transfer_notes_hint'),
                  labelStyle: TextStyle(color: context.textSecondary),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                ),
              ),
              const SizedBox(height: 16),

              // Summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('total_deducted_source'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                    Text(context.sar(_totalDeduction), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isTransferring ? null : _executeTransfer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.electricTeal,
                  foregroundColor: context.scaffoldBg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isTransferring
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.scaffoldBg))
                    : Text(context.tr('confirm_transfer'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
