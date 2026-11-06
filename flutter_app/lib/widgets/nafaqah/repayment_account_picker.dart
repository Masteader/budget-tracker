import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../providers/account_provider.dart';
import '../../providers/household_role_provider.dart';
import '../../services/household_permissions.dart';
import '../../models/nafaqah.dart';
import '../../theme/app_themes.dart';
import '../accounts/add_edit_account_dialog.dart';

int _halalas(double sar) => (sar * 100).round();

/// Accounts the viewer may repay the wife from (rule 02, migration
/// 20261105001300): their own personal accounts, plus the household's shared
/// pools when they are an admin; never archived or outside SAR. The server
/// checks the same, and refuses an account that does not hold the amount.
/// Every repayment leaves one of them (owner decision 2026-11-06): a cash
/// payment comes out of his Cash account, and there is no "not tracked".
/// A wife pays nothing, from a pool least of all, even as an admin
/// ([isWife], review R1-01): none for her.
List<Account> repaymentAccounts(
  List<Account> accounts, {
  required String householdId,
  required String? currentUserId,
  required bool isAdmin,
  bool isWife = false,
}) =>
    isWife
        ? const []
        : accounts
            .where((a) =>
                a.householdId == householdId &&
                !a.isArchived &&
                a.currency == 'SAR' &&
                HouseholdPermissions.canWithdrawFrom(a, currentUserId: currentUserId, isAdmin: isAdmin))
            .toList();

/// The longest decline reason, in Unicode code points (review R1-09). The API
/// (Python `len`) and the database (`char_length`) count code points, so the
/// app does too: an Arabic reason with harakat that fits here fits there.
/// Graphemes would let through a reason the server refuses; UTF-16 units
/// would cut one it accepts.
const int kDeclineReasonMaxCodePoints = 200;

/// Keeps a text field within [maxCodePoints] Unicode code points, never
/// splitting a surrogate pair.
class CodePointLengthFormatter extends TextInputFormatter {
  final int maxCodePoints;

  const CodePointLengthFormatter(this.maxCodePoints);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final runes = newValue.text.runes;
    if (runes.length <= maxCodePoints) return newValue;
    final text = String.fromCharCodes(runes.take(maxCodePoints));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// The accounts the providers above [context] say the viewer can repay from,
/// and whether they are known yet. Without an [AccountProvider] (nothing to
/// pay from in the app) the list is empty and known.
class RepaymentSources {
  final List<Account> accounts;
  final bool loaded;
  final AccountProvider? provider;

  const RepaymentSources(this.accounts, {required this.loaded, this.provider});

  /// [viewerIsWife]: she pays from nothing (review R1-01).
  static RepaymentSources of(BuildContext context, String householdId, {bool listen = true, bool viewerIsWife = false}) {
    AccountProvider? provider;
    try {
      provider = Provider.of<AccountProvider>(context, listen: listen);
    } on ProviderNotFoundException {
      return const RepaymentSources([], loaded: true);
    }
    String? currentUserId;
    try {
      currentUserId = Provider.of<HouseholdRoleProvider>(context, listen: listen).currentUserId;
    } on ProviderNotFoundException {
      currentUserId = null;
    }
    final list = repaymentAccounts(
      provider.accounts,
      householdId: householdId,
      currentUserId: currentUserId,
      isAdmin: viewerIsAdminOf(context, householdId),
      isWife: viewerIsWife,
    );
    return RepaymentSources(list, loaded: provider.hasLoaded, provider: provider);
  }

  /// The account behind [selection], if it is one of [accounts].
  Account? accountFor(String? selection) =>
      selection == null ? null : accounts.where((a) => a.id == selection).firstOrNull;

  /// Loads the accounts once if they are not yet, for this household only.
  static void ensureLoaded(BuildContext context, String householdId) {
    try {
      final provider = Provider.of<AccountProvider>(context, listen: false);
      final bound = provider.householdId;
      if (!provider.hasLoaded && (bound == null || bound == householdId)) {
        provider.ensureLoaded(householdId);
      }
    } on ProviderNotFoundException {
      return;
    }
  }
}

/// The name of the account a past repayment was paid from, when the viewer can
/// see it; null otherwise (a husband's personal account is his alone).
String? repaymentAccountName(BuildContext context, String? accountId) {
  if (accountId == null || accountId.isEmpty) return null;
  try {
    final accounts = Provider.of<AccountProvider>(context, listen: false).accounts;
    return accounts.where((a) => a.id == accountId).firstOrNull?.name;
  } on ProviderNotFoundException {
    return null;
  }
}

/// The localization key for a refusal of the chosen account, or null for any
/// other refusal (migration 20261105001300's hints, as the API maps them).
String? repaymentAccountErrorKey(String code) => const {
      'insufficient_funds': 'repay_err_funds',
      'account_unavailable': 'repay_err_unavailable',
      'account_forbidden': 'repay_err_account_forbidden',
    }[code];

/// The localized text for a refusal that tracked repayments, requests and
/// reversals bring (migration 20261105001300), the account refusals included;
/// null for any other. [owedNow] fills the amount of
/// 'request_exceeds_outstanding' and 'pending_exceeds_outstanding' when the
/// server sends none.
String? trackedRepaymentErrorText(BuildContext context, Object error, {double? owedNow}) {
  if (error is! NafaqahApiException) return null;
  final amount = error.outstanding ?? owedNow ?? 0;
  switch (error.code) {
    case 'app_update_required':
      return context.tr('repay_err_update_app');
    case 'wife_must_request':
      return context.tr('repay_err_wife_must_request');
    case 'request_not_pending':
      return context.tr('req_err_not_pending');
    case 'request_not_found':
      return context.tr('req_err_not_found');
    case 'request_exceeds_outstanding':
      return context.trArgs('req_err_exceeds', {'amount': context.sar(amount)});
    case 'pending_exceeds_outstanding':
      return context.trArgs('req_err_pending_cap', {'amount': context.sar(amount)});
    case 'already_reversed':
      return context.tr('rev_err_already');
    case 'reversal_not_tracked':
      return context.tr('rev_err_not_tracked');
    case 'reversal_account_unavailable':
      return context.tr('rev_err_account');
    case 'reversal_after_waiver':
      return context.tr('rev_err_after_waiver');
    case 'not_reversible':
      return context.tr('rev_err_not_reversible');
    case 'reimbursement_not_found':
    case 'payment_not_found':
      return context.tr('rev_err_not_found');
    // Review R1-09: these fell back to the generic failure.
    case 'request_key_reused':
      return context.tr('repay_err_key_reused');
    case 'account_required':
      return context.tr('repay_source_required');
    case 'request_key_required':
      return context.tr('repay_err_update_app');
    case 'invalid_reason':
      return context.tr('req_err_reason_long');
  }
  final accountKey = repaymentAccountErrorKey(error.code);
  return accountKey == null ? null : context.tr(accountKey);
}

/// The localized text for any refusal of a repayment, an approval, a decline,
/// a request, a cancel or a reversal (review R1-09): every code in
/// [kNafaqahErrorCodes] has its own message, in en, ar and ur; only an
/// unknown failure gets the generic one. [owedNow] fills the amount of an
/// overpayment or a request above what is owed when the server sends none.
String repaymentErrorText(BuildContext context, Object error, {double? owedNow}) {
  final tracked = trackedRepaymentErrorText(context, error, owedNow: owedNow);
  if (tracked != null) return tracked;
  if (error is NafaqahApiException) {
    switch (error.code) {
      case 'overpayment':
        return context.trArgs('nafaqah_err_overpayment', {'amount': context.sar(error.outstanding ?? owedNow ?? 0)});
      case 'not_family':
        return context.tr('nafaqah_err_not_family');
      case 'ledger_would_be_overpaid':
        return context.tr('nafaqah_err_ledger_overpaid');
      case 'no_provider':
        return context.tr('nafaqah_err_no_provider');
      case 'no_wife':
        return context.tr('nafaqah_err_no_wife');
      case 'account_pending_deletion':
        return context.tr('del_err_account_pending');
      case 'debt_closed':
        return context.tr('fmd_err_closed');
      case 'debt_not_found':
        return context.tr('fmd_err_not_found');
      case 'forbidden':
        return context.tr('repay_err_forbidden');
      case 'invalid':
        return context.tr('nafaqah_err_invalid_amount');
    }
  }
  return context.tr('settle_record_failed_msg');
}

/// The history line under a repayment: which account it came from (or, for a
/// reversal, went back to), or that it moved no balance (a row from before
/// every repayment was tracked). Null for rows from a server that does not say.
String? repaymentSourceLine(BuildContext context, {required bool? movedBalance, String? accountId, bool reversal = false}) {
  if (movedBalance == null) return null;
  if (!movedBalance) return context.tr('repay_history_not_tracked');
  final name = repaymentAccountName(context, accountId);
  if (reversal) {
    return name == null ? context.tr('repay_history_back_to_account') : context.trArgs('repay_history_back_to', {'account': name});
  }
  return name == null ? context.tr('repay_history_from_account') : context.trArgs('repay_history_from', {'account': name});
}

/// Said in a sheet whose answer was lost (review R1-06): it may already be
/// recorded; the sheet keeps what was sent and its key, so trying again is
/// safe. The inputs stay as they were sent.
class RepaymentUnconfirmedNote extends StatelessWidget {
  const RepaymentUnconfirmedNote({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.goldText;
    return Container(
      padding: const EdgeInsetsDirectional.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('repay_unconfirmed_hold'),
              style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a repayment to the wife (or of a former member's record, or an
/// approval of her request) is paid from: one of [accounts], with its
/// balance. The choice is required; what it will do is said under it. With no
/// account to pay from, it says so and offers to add one.
class RepaymentAccountPicker extends StatelessWidget {
  final String householdId;
  final List<Account> accounts;
  final String? selected;
  final double amount;
  final ValueChanged<String> onChanged;

  /// A former member: she is gone, so the line under the choice says nothing of her.
  final bool formerMember;

  /// Opens "Add account"; by default the app's account dialog, after which
  /// the accounts reload.
  final VoidCallback? onAddAccount;

  const RepaymentAccountPicker({
    super.key,
    required this.householdId,
    required this.accounts,
    required this.selected,
    required this.amount,
    required this.onChanged,
    this.formerMember = false,
    this.onAddAccount,
  });

  void _addAccount(BuildContext context) {
    if (onAddAccount != null) {
      onAddAccount!();
      return;
    }
    AccountProvider? provider;
    try {
      provider = Provider.of<AccountProvider>(context, listen: false);
    } on ProviderNotFoundException {
      provider = null;
    }
    AddEditAccountDialog.show(context, householdId: householdId, onSuccess: () => provider?.refresh(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final chosen = accounts.where((a) => a.id == selected).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('repay_source_title'),
          style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final a in accounts) ...[
          _SourceTile(
            key: ValueKey('repay_source_${a.id}'),
            icon: a.accountType.defaultIcon,
            title: a.name,
            subtitle: HouseholdPermissions.isSharedPool(a)
                ? '${context.tr('account_type_pool')} · ${context.trArgs('repay_source_balance', {'amount': context.sar(a.balance)})}'
                : context.trArgs('repay_source_balance', {'amount': context.sar(a.balance)}),
            warning: _halalas(amount) > 0 && _halalas(a.balance) < _halalas(amount) ? context.tr('repay_low_balance') : null,
            selected: selected == a.id,
            onTap: () => onChanged(a.id),
          ),
          const SizedBox(height: 6),
        ],
        if (accounts.isEmpty) ...[
          Text(
            context.tr('repay_no_accounts'),
            key: const ValueKey('repay_no_accounts'),
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('repay_add_account'),
              style: OutlinedButton.styleFrom(foregroundColor: context.accentText),
              onPressed: () => _addAccount(context),
              icon: const Icon(Icons.add_card_rounded, size: 18),
              label: Text(context.tr('add_account')),
            ),
          ),
        ],
        if (chosen != null) ...[
          const SizedBox(height: 8),
          Text(
            context.trArgs(formerMember ? 'repay_effect_former' : 'repay_effect', {
              'account': chosen.name,
              'amount': context.sar(amount),
            }),
            key: const ValueKey('repay_source_effect'),
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? warning;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentText;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? context.accentSubtleBg : context.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? accent : context.borderColor, width: selected ? 1.4 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: selected ? accent : context.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      Text(subtitle, style: TextStyle(color: context.textSecondary, fontSize: 11)),
                      if (warning != null)
                        Text(warning!, style: TextStyle(color: context.dangerColor, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? accent : context.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
