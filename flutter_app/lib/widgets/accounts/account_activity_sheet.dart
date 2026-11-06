import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../providers/account_provider.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../../utils/failure_log.dart';

/// Loads an account's latest movements; the account service by default,
/// injectable for tests.
typedef AccountMovementsLoader = Future<List<AccountMovement>> Function(String householdId, String accountId);

/// The line an account's own history shows for [movement] (review R1-13).
/// A repayment to the wife, a payment of a former member's record and their
/// reversals say what they were and name nobody: a former member's line never
/// carries her name. A transfer names the other account when the viewer has
/// it in the app.
String accountMovementLabel(BuildContext context, AccountMovement movement, String accountId,
    {String? Function(String accountId)? accountName}) {
  switch (movement.purpose) {
    case kMovementWifeRepayment:
      return context.tr('acct_line_wife_repayment');
    case kMovementWifeRepaymentReversal:
      return context.tr('acct_line_wife_repayment_reversal');
    case kMovementFormerMemberPayment:
      return context.tr('acct_line_former_member_payment');
    case kMovementFormerMemberPaymentReversal:
      return context.tr('acct_line_former_member_payment_reversal');
  }
  final into = movement.isInto(accountId);
  final other = into ? movement.fromAccountId : movement.toAccountId;
  final name = other == null ? null : accountName?.call(other);
  if (name == null || name.isEmpty) return context.tr(into ? 'acct_line_transfer_in' : 'acct_line_transfer_out');
  return context.trArgs(into ? 'acct_line_transfer_from' : 'acct_line_transfer_to', {'account': name});
}

/// What moved an account's balance by transfers, newest first: transfers in
/// and out, and every repayment to the wife or payment of a former member's
/// record it paid, and their reversals (review R1-13).
class AccountActivitySheet extends StatefulWidget {
  final Account account;
  final String householdId;
  final AccountMovementsLoader? load;

  const AccountActivitySheet({super.key, required this.account, required this.householdId, this.load});

  static Future<void> show(BuildContext context, {required Account account, required String householdId, AccountMovementsLoader? load}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AccountActivitySheet(account: account, householdId: householdId, load: load),
    );
  }

  @override
  State<AccountActivitySheet> createState() => _AccountActivitySheetState();
}

class _AccountActivitySheetState extends State<AccountActivitySheet> {
  late Future<List<AccountMovement>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AccountMovement>> _load() async {
    final load = widget.load ??
        (String householdId, String accountId) =>
            AccountService.instance.listMovements(householdId: householdId, accountId: accountId);
    try {
      return await load(widget.householdId, widget.account.id);
    } catch (e) {
      logFailure('AccountActivity.load', e);
      rethrow;
    }
  }

  String? _accountName(String id) {
    try {
      return Provider.of<AccountProvider>(context, listen: false).accounts.where((a) => a.id == id).firstOrNull?.name;
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = widget.account;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('acct_activity_title'),
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          Text(account.name, style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(context.tr('acct_activity_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<List<AccountMovement>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText)),
                  );
                }
                if (snap.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('load_error_generic'), style: TextStyle(color: context.dangerColor, fontSize: 12)),
                      TextButton(
                        key: const ValueKey('acct_activity_retry'),
                        style: TextButton.styleFrom(foregroundColor: context.accentText),
                        onPressed: () => setState(() {
                          _future = _load();
                        }),
                        child: Text(context.tr('try_again')),
                      ),
                    ],
                  );
                }
                final movements = snap.data ?? const <AccountMovement>[];
                if (movements.isEmpty) {
                  return Text(context.tr('acct_activity_empty'),
                      key: const ValueKey('acct_activity_empty'), style: TextStyle(color: context.textSecondary));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: movements.length,
                  separatorBuilder: (_, __) => Divider(color: context.borderColor, height: 1),
                  itemBuilder: (context, i) {
                    final m = movements[i];
                    final change = m.changeFor(account.id);
                    final into = change > 0;
                    final color = into ? context.successText : context.textPrimary;
                    final details = [
                      if (m.timestamp != null) l10n.date(m.timestamp!.toLocal(), 'd MMM yyyy'),
                      if (!into && m.fee > 0) context.trArgs('acct_line_fee', {'amount': context.money(m.fee, account.currency)}),
                    ].join(' · ');
                    return Padding(
                      key: ValueKey('acct_movement_${m.id}'),
                      padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(into ? Icons.south_west_rounded : Icons.north_east_rounded, size: 20, color: color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // The amount sits at the end of the label's line when both
                                // fit, and goes under it when not: 320 px wide, text scale
                                // 2.0, a large amount (review R2-03).
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      accountMovementLabel(context, m, account.id, accountName: _accountName),
                                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                                    ),
                                    Text(
                                      context.money(change, account.currency, signed: true),
                                      key: ValueKey('acct_movement_amount_${m.id}'),
                                      style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                if (details.isNotEmpty)
                                  Text(details, style: TextStyle(color: context.textSecondary, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
