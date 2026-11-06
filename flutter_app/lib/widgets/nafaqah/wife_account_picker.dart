import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../models/nafaqah.dart';
import '../../providers/account_provider.dart';
import '../../services/api_service.dart';
import '../../services/household_permissions.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import 'repayment_account_picker.dart';

/// Makes a wife account for [wifeUserId] named [name]; returns its id.
typedef WifeAccountCreator = Future<String> Function({required String wifeUserId, required String name});

/// The longest wife account name, in Unicode code points (the API and the
/// database count code points too).
const int kWifeAccountNameMaxCodePoints = 60;

/// Her usable wife accounts (migration 20261105001300, section 12), as the
/// viewer's [AccountProvider] reads them: hers to her, all of hers to her
/// husband. Empty without a provider.
List<Account> wifeAccountsFor(BuildContext context, {required String householdId, required String wifeUserId, bool listen = true}) {
  try {
    final accounts = Provider.of<AccountProvider>(context, listen: listen).accounts;
    return HouseholdPermissions.wifeAccountsOf(accounts, householdId: householdId, wifeId: wifeUserId);
  } on ProviderNotFoundException {
    return const [];
  }
}

/// The wife account a sheet starts with: [preferred] while it is still one of
/// [accounts], else the only one, else none (the payer picks).
String? defaultWifeAccount(List<Account> accounts, {String? preferred}) {
  if (preferred != null && accounts.any((a) => a.id == preferred)) return preferred;
  return accounts.length == 1 ? accounts.single.id : null;
}

/// Which of her wife accounts a repayment credits ("to her account"), or
/// which one she received it into ("received into", [receiving]). With none,
/// it says so: her husband ([canCreate]) is offered to create one; she is told
/// to ask him.
class WifeAccountPicker extends StatelessWidget {
  final List<Account> accounts;
  final String? selected;
  final ValueChanged<String> onChanged;
  final bool receiving;
  final bool canCreate;
  final VoidCallback? onCreate;

  /// A retry after a lost answer: the choice cannot change.
  final bool locked;

  const WifeAccountPicker({
    super.key,
    required this.accounts,
    required this.selected,
    required this.onChanged,
    this.receiving = false,
    this.canCreate = false,
    this.onCreate,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(receiving ? 'wife_acc_into_title' : 'wife_acc_to_title'),
          style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          WifeAccountRequiredPrompt(canCreate: canCreate, onCreate: onCreate)
        else if (accounts.length == 1 && selected == accounts.single.id)
          _OnlyWifeAccount(key: ValueKey('wife_acc_${accounts.single.id}'), account: accounts.single)
        else
          for (final a in accounts) ...[
            _WifeAccountTile(
              key: ValueKey('wife_acc_${a.id}'),
              account: a,
              selected: selected == a.id,
              onTap: locked ? null : () => onChanged(a.id),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

/// She has no wife account (wife_account_required): her husband is offered
/// to create one; anyone else is told only he can.
class WifeAccountRequiredPrompt extends StatelessWidget {
  final bool canCreate;
  final VoidCallback? onCreate;

  const WifeAccountRequiredPrompt({super.key, required this.canCreate, this.onCreate});

  @override
  Widget build(BuildContext context) {
    final color = context.goldText;
    return Container(
      key: const ValueKey('wife_acc_required'),
      padding: const EdgeInsetsDirectional.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_border_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(canCreate ? 'wife_acc_required_husband' : 'wife_acc_required_other'),
                  style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (canCreate && onCreate != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('wife_acc_create'),
                style: OutlinedButton.styleFrom(foregroundColor: context.accentText),
                onPressed: onCreate,
                icon: const Icon(Icons.add_card_rounded, size: 18),
                label: Text(context.tr('wife_acc_create')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Her only wife account, already chosen: one line, with its balance.
class _OnlyWifeAccount extends StatelessWidget {
  final Account account;

  const _OnlyWifeAccount({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.favorite_rounded, size: 18, color: context.accentText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${account.name} · ${context.trArgs('repay_source_balance', {'amount': context.sar(account.balance)})}',
            style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _WifeAccountTile extends StatelessWidget {
  final Account account;
  final bool selected;
  final VoidCallback? onTap;

  const _WifeAccountTile({super.key, required this.account, required this.selected, required this.onTap});

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
                Icon(Icons.favorite_rounded, size: 20, color: selected ? accent : context.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      Text(
                        context.trArgs('repay_source_balance', {'amount': context.sar(account.balance)}),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                      ),
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

/// One wife the husband may make a wife account for.
class WifeChoice {
  final String id;
  final String name;

  const WifeChoice(this.id, this.name);
}

/// "Add wife account": her husband picks the wife and a name. Pops `true` once
/// the server made it (the accounts reload).
class AddWifeAccountDialog extends StatefulWidget {
  final String householdId;
  final List<WifeChoice> wives;
  final String? initialWifeId;
  final WifeAccountCreator? create;

  const AddWifeAccountDialog({
    super.key,
    required this.householdId,
    required this.wives,
    this.initialWifeId,
    this.create,
  });

  /// Shows the dialog; true once one was made.
  static Future<bool> show(
    BuildContext context, {
    required String householdId,
    required List<WifeChoice> wives,
    String? initialWifeId,
    WifeAccountCreator? create,
  }) async {
    AccountProvider? provider;
    try {
      provider = Provider.of<AccountProvider>(context, listen: false);
    } on ProviderNotFoundException {
      provider = null;
    }
    final made = await showDialog<bool>(
      context: context,
      builder: (_) => AddWifeAccountDialog(householdId: householdId, wives: wives, initialWifeId: initialWifeId, create: create),
    );
    if (made == true) await provider?.refresh(force: true);
    return made == true;
  }

  @override
  State<AddWifeAccountDialog> createState() => _AddWifeAccountDialogState();
}

class _AddWifeAccountDialogState extends State<AddWifeAccountDialog> {
  final _nameCtrl = TextEditingController();
  String? _wifeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _wifeId = widget.initialWifeId ?? (widget.wives.length == 1 ? widget.wives.single.id : null);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final wifeId = _wifeId;
    final name = _nameCtrl.text.trim();
    if (wifeId == null) {
      AppSnackBar.showError(context, context.tr('wife_acc_pick_wife'));
      return;
    }
    if (name.isEmpty || name.runes.length > kWifeAccountNameMaxCodePoints) {
      AppSnackBar.showError(context, context.tr('wife_acc_err_name'));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.create != null) {
        await widget.create!(wifeUserId: wifeId, name: name);
      } else {
        await ApiService.instance.createWifeAccount(widget.householdId, wifeUserId: wifeId, name: name);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBar.showError(context, repaymentErrorText(context, e), title: context.tr('wife_acc_create_failed'));
      return;
    }
    if (!mounted) return;
    AppSnackBar.showSuccess(context, context.trArgs('wife_acc_created', {'name': name}), icon: Icons.check_circle_outline);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('wife_acc_dialog'),
      title: Text(context.tr('wife_acc_add_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('wife_acc_add_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in widget.wives)
                  ChoiceChip(
                    key: ValueKey('wife_acc_wife_${w.id}'),
                    label: Text(w.name.isEmpty ? context.tr('wife_acc_unnamed_wife') : w.name),
                    selected: _wifeId == w.id,
                    onSelected: _saving ? null : (_) => setState(() => _wifeId = w.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('wife_acc_name'),
              controller: _nameCtrl,
              enabled: !_saving,
              inputFormatters: const [CodePointLengthFormatter(kWifeAccountNameMaxCodePoints)],
              decoration: InputDecoration(
                labelText: context.tr('wife_acc_name_label'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          key: const ValueKey('wife_acc_save'),
          onPressed: _saving ? null : _save,
          child: Text(context.tr('wife_acc_create')),
        ),
      ],
    );
  }
}

/// The wives of [summary] her husband may make a wife account for.
List<WifeChoice> wifeChoicesOf(NafaqahSummary summary) =>
    summary.wives.map((w) => WifeChoice(w.id, w.displayName ?? '')).toList();
