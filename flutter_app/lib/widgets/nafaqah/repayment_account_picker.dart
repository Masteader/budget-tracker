import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../providers/account_provider.dart';
import '../../providers/household_role_provider.dart';
import '../../services/household_permissions.dart';
import '../../theme/app_themes.dart';

/// The "cash, not tracked in the app" choice: the amount and method are
/// recorded, and no balance changes.
const String kRepayNotTracked = 'not_tracked';

int _halalas(double sar) => (sar * 100).round();

/// Accounts the viewer may repay the wife from (rule 02, migration
/// 20261105001300): their own personal accounts, plus the household's shared
/// pools when they are an admin; never archived or outside SAR. The server
/// checks the same, and refuses an account that does not hold the amount.
List<Account> repaymentAccounts(
  List<Account> accounts, {
  required String householdId,
  required String? currentUserId,
  required bool isAdmin,
}) =>
    accounts
        .where((a) =>
            a.householdId == householdId &&
            !a.isArchived &&
            a.currency == 'SAR' &&
            HouseholdPermissions.canWithdrawFrom(a, currentUserId: currentUserId, isAdmin: isAdmin))
        .toList();

/// The accounts the providers above [context] say the viewer can repay from,
/// and whether they are known yet. Without an [AccountProvider] (nothing to
/// pay from in the app) the list is empty and known.
class RepaymentSources {
  final List<Account> accounts;
  final bool loaded;
  final AccountProvider? provider;

  const RepaymentSources(this.accounts, {required this.loaded, this.provider});

  static RepaymentSources of(BuildContext context, String householdId, {bool listen = true}) {
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
    );
    return RepaymentSources(list, loaded: provider.hasLoaded, provider: provider);
  }

  /// The account behind [selection], if it is one of [accounts].
  Account? accountFor(String? selection) =>
      selection == null || selection == kRepayNotTracked ? null : accounts.where((a) => a.id == selection).firstOrNull;

  /// What counts as chosen: [selection], or "not tracked" when the viewer has
  /// no account in the app to pay from (nothing else could be chosen).
  String? effective(String? selection) =>
      selection ?? (loaded && accounts.isEmpty ? kRepayNotTracked : null);

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

/// The history line under a repayment: which account it came from, or that it
/// moved no balance. Null for rows read from a server that does not say.
String? repaymentSourceLine(BuildContext context, {required bool? movedBalance, String? accountId}) {
  if (movedBalance == null) return null;
  if (!movedBalance) return context.tr('repay_history_not_tracked');
  final name = repaymentAccountName(context, accountId);
  return name == null ? context.tr('repay_history_from_account') : context.trArgs('repay_history_from', {'account': name});
}

/// Where a repayment to the wife (or of a former member's record) is paid
/// from: one of [accounts], with its balance, or [kRepayNotTracked]. The choice
/// is required; what it will do is said under it.
class RepaymentAccountPicker extends StatelessWidget {
  final List<Account> accounts;
  final String? selected;
  final double amount;
  final ValueChanged<String> onChanged;

  /// A former member: she is gone, so nothing is credited to her.
  final bool formerMember;

  const RepaymentAccountPicker({
    super.key,
    required this.accounts,
    required this.selected,
    required this.amount,
    required this.onChanged,
    this.formerMember = false,
  });

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
          Text(context.tr('repay_no_accounts'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
        ],
        _SourceTile(
          key: const ValueKey('repay_source_not_tracked'),
          icon: Icons.money_off_csred_outlined,
          title: context.tr('repay_not_tracked'),
          subtitle: context.tr('repay_not_tracked_desc'),
          selected: selected == kRepayNotTracked,
          onTap: () => onChanged(kRepayNotTracked),
        ),
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
