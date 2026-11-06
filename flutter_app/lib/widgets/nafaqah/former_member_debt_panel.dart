import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/three_d_icon_puck.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../models/money.dart';
import '../../models/nafaqah.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../utils/failure_log.dart';
import '../app_snackbar.dart';
import '../settings/settings_section.dart' show isLargeText;
import 'repayment_account_picker.dart';

/// Records a payment of a former member's record. [requestKey] is the same for
/// every retry from one sheet, so the server records the payment once.
/// [accountId] is the account it is paid from: every payment leaves one
/// (owner decision 2026-11-06).
typedef FormerMemberDebtPaymentRecorder = Future<FormerMemberDebtReceipt> Function({
  required String debtId,
  required double amount,
  required String paymentMethod,
  required String requestKey,
  required String accountId,
});

/// Reverses a tracked payment of a former member's record: the money goes back
/// to its account and the amount back to what remains.
typedef FormerMemberDebtReverser = Future<FormerMemberDebtReceipt> Function({
  required String debtId,
  required String eventId,
  required String requestKey,
});

/// Records her waiver (إبراء) of what remains of a former member's record.
typedef FormerMemberDebtWaiver = Future<FormerMemberDebtReceipt> Function({
  required String debtId,
  required String requestKey,
});

const _knownMethods = {'stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other'};

String _methodLabel(BuildContext context, String? method) =>
    context.tr('pay_method_${_knownMethods.contains(method) ? method : 'other'}');

int _halalas(double sar) => (sar * 100).round();

bool _isUnknownOutcome(Object error) => error is! NafaqahApiException || error.outcomeUnknown;

/// The record changed since it was shown: refresh the card.
bool _isStale(Object error) => error is NafaqahApiException && (error.code == 'debt_closed' || error.code == 'debt_not_found');

/// The localized reason a payment ([payment]) or a waiver of a former member's
/// record was refused. [remaining] is what the sheet showed, for an overpayment
/// the server did not quantify.
String formerMemberDebtErrorText(BuildContext context, Object error, {required double remaining, required bool payment}) {
  final fallback = context.tr(payment ? 'settle_record_failed_msg' : 'fmd_waive_failed');
  if (error is! NafaqahApiException) return fallback;
  if (error.code != 'overpayment') {
    final tracked = trackedRepaymentErrorText(context, error, owedNow: remaining);
    if (tracked != null) return tracked;
  }
  switch (error.code) {
    case 'overpayment':
      return context.trArgs('fmd_pay_over', {'amount': context.sar(error.outstanding ?? remaining)});
    case 'debt_closed':
      return context.tr('fmd_err_closed');
    case 'debt_not_found':
      return context.tr('fmd_err_not_found');
    case 'request_key_reused':
      return context.tr('fmd_err_key_reused');
    case 'forbidden':
      return context.tr('fmd_err_forbidden');
    case 'invalid':
      return payment ? context.tr('fmd_err_invalid') : fallback;
  }
  return fallback;
}

/// What a wife who deleted her account was still owed, kept by the household
/// with no name (rule 02: the husband's debt to her does not vanish with her
/// account). Every member sees it; the husband (provider) or an admin closes it
/// by recording payments, or her waiver (إبراء) in which no money moves.
class FormerMemberDebtPanel extends StatelessWidget {
  final FormerMemberDebt debt;
  final bool canManage;
  final String householdId;
  final FormerMemberDebtPaymentRecorder? recordPayment;
  final FormerMemberDebtWaiver? waive;
  final FormerMemberDebtReverser? reverse;

  /// A payment or a waiver was recorded.
  final VoidCallback onChanged;

  /// The outcome is unknown or the record changed elsewhere: reload it.
  final VoidCallback onRefresh;

  const FormerMemberDebtPanel({
    super.key,
    required this.debt,
    required this.canManage,
    required this.householdId,
    required this.onChanged,
    required this.onRefresh,
    this.recordPayment,
    this.waive,
    this.reverse,
  });

  void _openPaymentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FormerDebtPaymentSheet(
        householdId: householdId,
        debtId: debt.id,
        remaining: debt.remaining,
        recordPayment: recordPayment,
        onConfirmed: onChanged,
        onRefresh: onRefresh,
      ),
    );
  }

  Future<void> _openWaiver(BuildContext context) async {
    final waived = await showDialog<bool>(
      context: context,
      builder: (ctx) => _FormerDebtWaiverDialog(
        householdId: householdId,
        debtId: debt.id,
        remaining: debt.remaining,
        waive: waive,
        onRefresh: onRefresh,
      ),
    );
    if (waived != true || !context.mounted) return;
    AppSnackBar.showSuccess(context, context.tr('fmd_waived_success'), icon: Icons.check_circle_outline);
    onChanged();
  }

  void _openHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FormerDebtHistorySheet(
        debt: debt,
        householdId: householdId,
        reverse: reverse,
        onChanged: onChanged,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gold = context.goldText;
    final closed = debt.isSettled || debt.isWaived;
    final manage = canManage && debt.isOpen;
    final badgeColor = debt.isWaived ? context.accentText : context.successText;

    const puck = ThreeDIconPuck(
      icon: Icons.history_edu_rounded,
      size: 44,
      isRoseGold: true,
      isSquircle: true,
    );
    final headerText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('fmd_title'),
          style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        Text(context.tr('fmd_subtitle'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
        if (closed) ...[
          const SizedBox(height: 6),
          Container(
            key: ValueKey('fmd_status_${debt.id}'),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  debt.isWaived ? Icons.volunteer_activism_outlined : Icons.check_circle_outline_rounded,
                  size: 12,
                  color: badgeColor,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    context.tr(debt.isWaived ? 'fmd_status_waived' : 'fmd_status_settled'),
                    style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return ThreeDSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      customBorder: Border.all(
        color: closed ? context.borderColor : gold.withValues(alpha: 0.35),
        width: 1.2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLargeText(context)) ...[
            puck,
            const SizedBox(height: 8),
            headerText,
          ] else
            Row(
              children: [
                puck,
                const SizedBox(width: 12),
                Expanded(child: headerText),
              ],
            ),
          const SizedBox(height: 14),
          if (!closed) ...[
            Text('${context.tr('fmd_remaining')}:', style: TextStyle(color: context.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              context.sar(debt.remaining),
              style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: gold),
            ),
            const SizedBox(height: 12),
          ] else if (debt.closedAt != null) ...[
            Text(
              context.trArgs('fmd_closed_on', {'date': l10n.date(debt.closedAt!, 'd MMM yyyy')}),
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _DebtPill(
                icon: Icons.north_east_rounded,
                label: context.trArgs('fmd_original_total', {'amount': context.sar(debt.originalAmount)}),
                color: gold,
              ),
              _DebtPill(
                icon: Icons.south_west_rounded,
                label: context.trArgs('fmd_paid_total', {'amount': context.sar(debt.paidAmount)}),
                color: context.accentText,
              ),
              if (_halalas(debt.waivedAmount) > 0)
                _DebtPill(
                  icon: Icons.volunteer_activism_outlined,
                  label: context.trArgs('fmd_waived_total', {'amount': context.sar(debt.waivedAmount)}),
                  color: context.accentText,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (manage) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: ValueKey('fmd_pay_${debt.id}'),
                style: ElevatedButton.styleFrom(
                  // The fixed rose-gold fill, as on the wife's panel (goldText is an ink colour).
                  backgroundColor: AppThemes.champagneGold,
                  foregroundColor: VelvetBurgundyColors.primaryLight,
                  elevation: 0,
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(context.tr('fmd_record_payment'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _openPaymentSheet(context);
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              if (manage)
                TextButton.icon(
                  key: ValueKey('fmd_waive_${debt.id}'),
                  style: TextButton.styleFrom(foregroundColor: context.accentText),
                  onPressed: () => _openWaiver(context),
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                  label: Text(context.tr('fmd_waive_action')),
                ),
              TextButton.icon(
                key: ValueKey('fmd_history_${debt.id}'),
                style: TextButton.styleFrom(foregroundColor: context.accentText),
                onPressed: () => _openHistory(context),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(context.tr('nafaqah_history')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DebtPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkMode ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label, style: TextStyle(color: context.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── History ─────────────────────────────────────────────────────────────────

class _FormerDebtHistorySheet extends StatefulWidget {
  final FormerMemberDebt debt;
  final String householdId;
  final FormerMemberDebtReverser? reverse;

  /// A reversal was recorded: the record changed.
  final VoidCallback onChanged;

  /// The outcome is unknown or the record changed elsewhere: reload it.
  final VoidCallback onRefresh;

  const _FormerDebtHistorySheet({
    required this.debt,
    required this.householdId,
    required this.onChanged,
    required this.onRefresh,
    this.reverse,
  });

  @override
  State<_FormerDebtHistorySheet> createState() => _FormerDebtHistorySheetState();
}

class _FormerDebtHistorySheetState extends State<_FormerDebtHistorySheet> {
  bool _busy = false;

  Future<void> _reverse(FormerMemberDebtEvent e) async {
    final account = repaymentAccountName(context, e.accountId) ?? context.tr('repay_history_from_account');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: ctx.cardBg,
        title: Text(ctx.tr('rev_confirm_title'), style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          ctx.trArgs('rev_confirm_body_former', {'amount': ctx.sar(e.amount), 'account': account}),
          key: const ValueKey('rev_confirm_body'),
          style: TextStyle(color: ctx.textPrimary),
        ),
        actions: [
          TextButton(
            key: const ValueKey('rev_confirm_cancel'),
            style: TextButton.styleFrom(foregroundColor: ctx.textSecondary),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          ElevatedButton(
            key: const ValueKey('rev_confirm_ok'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.champagneGold,
              foregroundColor: VelvetBurgundyColors.primaryLight,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('rev_action')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final sources = RepaymentSources.of(context, widget.householdId, listen: false);
    try {
      final reverse = widget.reverse ??
          ({required String debtId, required String eventId, required String requestKey}) =>
              ApiService.instance.reverseFormerMemberDebtPayment(widget.householdId,
                  debtId: debtId, eventId: eventId, requestKey: requestKey);
      await reverse(debtId: widget.debt.id, eventId: e.id, requestKey: const Uuid().v4());
    } catch (err) {
      logFailure('FormerMemberDebt.reverse', err);
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackBar.showError(
        context,
        _isUnknownOutcome(err)
            ? context.tr('fmd_unconfirmed_msg')
            : formerMemberDebtErrorText(context, err, remaining: widget.debt.remaining, payment: true),
        title: context.tr('settle_record_failed'),
      );
      widget.onRefresh();
      return;
    }
    // The money is back in its account: the balances show it now.
    sources.provider?.refresh(force: true);
    if (!mounted) return;
    AppSnackBar.showSuccess(context, context.trArgs('rev_done', {'amount': context.sar(e.amount)}), icon: Icons.check_circle_outline);
    Navigator.of(context).pop();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[
      _HistoryRow(
        icon: Icons.north_east_rounded,
        color: context.goldText,
        title: context.tr('fmd_history_opened'),
        amount: context.sar(debt.originalAmount),
        date: debt.createdAt == null ? null : l10n.date(debt.createdAt!, 'd MMM yyyy'),
      ),
      for (final e in debt.events)
        _HistoryRow(
          key: e.id.isEmpty ? null : ValueKey('fmd_event_${e.id}'),
          icon: e.isWaiver
              ? Icons.volunteer_activism_outlined
              : e.isReversal
                  ? Icons.undo_rounded
                  : Icons.south_west_rounded,
          color: e.isWaiver
              ? context.accentText
              : e.isReversal
                  ? context.goldText
                  : context.successText,
          title: e.isWaiver
              ? context.tr('fmd_history_waiver')
              : e.isReversal
                  ? context.tr('rev_entry')
                  : context.trArgs('fmd_history_payment', {'method': _methodLabel(context, e.paymentMethod)}),
          // What remains: a payment or waiver takes away, a reversal adds back.
          amount: '${e.isReversal ? '+' : '−'}${context.sar(e.amount)}',
          source: e.isWaiver
              ? null
              : repaymentSourceLine(context, movedBalance: e.movedBalance, accountId: e.accountId, reversal: e.isReversal),
          date: e.createdAt == null ? null : l10n.date(e.createdAt!, 'd MMM yyyy'),
          reversed: e.reversed,
          reversedKey: 'fmd_rev_badge_${e.id}',
          action: e.canReverse && !e.reversed
              ? TextButton.icon(
                  key: ValueKey('fmd_reverse_${e.id}'),
                  style: TextButton.styleFrom(foregroundColor: context.accentText),
                  onPressed: _busy ? null : () => _reverse(e),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: Text(context.tr('rev_action')),
                )
              : null,
        ),
    ];
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
            context.tr('fmd_history_title'),
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(color: context.borderColor, height: 1),
              itemBuilder: (_, i) => rows[i],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String amount;
  final String? date;

  /// Which account a payment came from (or a reversal went back to), or that
  /// it moved no balance.
  final String? source;

  /// A payment that a later reversal undid: it stays, with a "Reversed" badge.
  final bool reversed;
  final String? reversedKey;

  /// Reverse, when the viewer may.
  final Widget? action;

  const _HistoryRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.amount,
    this.date,
    this.source,
    this.reversed = false,
    this.reversedKey,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final titleText = Text(title, style: TextStyle(color: context.textPrimary, fontSize: 13));
    final amountText = Text(amount, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w700));
    final details = [if (source != null) source!, if (date != null) date!];
    final dateText = details.isEmpty
        ? null
        : Text(details.join(' · '), style: TextStyle(color: context.textSecondary, fontSize: 11));
    final large = isLargeText(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText,
                if (large) amountText,
                if (dateText != null) dateText,
                if (reversed) ...[
                  const SizedBox(height: 4),
                  Container(
                    key: reversedKey == null ? null : ValueKey(reversedKey),
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.textSecondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.textSecondary.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      context.tr('rev_badge'),
                      style: TextStyle(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                if (action != null) Align(alignment: AlignmentDirectional.centerStart, child: action!),
              ],
            ),
          ),
          if (!large) ...[
            const SizedBox(width: 8),
            amountText,
          ],
        ],
      ),
    );
  }
}

// ── Record a payment ────────────────────────────────────────────────────────

class _FormerDebtPaymentSheet extends StatefulWidget {
  final String householdId;
  final String debtId;
  final double remaining;
  final FormerMemberDebtPaymentRecorder? recordPayment;
  final VoidCallback onConfirmed;
  final VoidCallback onRefresh;

  const _FormerDebtPaymentSheet({
    required this.householdId,
    required this.debtId,
    required this.remaining,
    required this.onConfirmed,
    required this.onRefresh,
    this.recordPayment,
  });

  @override
  State<_FormerDebtPaymentSheet> createState() => _FormerDebtPaymentSheetState();
}

class _FormerDebtPaymentSheetState extends State<_FormerDebtPaymentSheet> {
  late final TextEditingController _amountCtrl;

  /// One key per opening of the sheet, reused by every retry: a payment whose
  /// answer was lost is replayed by the server, never recorded twice.
  late final String _requestKey;
  String _paymentMethod = 'stc_pay';
  bool _isSubmitting = false;

  /// The account it is paid from; null until chosen.
  String? _source;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.remaining.toStringAsFixed(2));
    _requestKey = const Uuid().v4();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) RepaymentSources.ensureLoaded(context, widget.householdId);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirm(double amount, Account account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: ctx.cardBg,
        title: Text(ctx.tr('fmd_pay_confirm_title'), style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.trArgs('fmd_pay_confirm_body', {'amount': ctx.sar(amount), 'method': _methodLabel(ctx, _paymentMethod)}),
              style: TextStyle(color: ctx.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              ctx.trArgs('repay_effect_former', {'account': account.name, 'amount': ctx.sar(amount)}),
              key: const ValueKey('fmd_confirm_source'),
              style: TextStyle(color: ctx.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('fmd_confirm_cancel'),
            style: TextButton.styleFrom(foregroundColor: ctx.textSecondary),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          ElevatedButton(
            key: const ValueKey('fmd_confirm_ok'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.champagneGold,
              foregroundColor: VelvetBurgundyColors.primaryLight,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('fmd_pay_confirm_ok')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit() async {
    final rounded = roundedMoneyTextIfRounded(_amountCtrl.text);
    if (rounded != null) setState(() => _amountCtrl.text = rounded); // show what is stored
    final amt = parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0;
    if (_halalas(amt) <= 0) {
      AppSnackBar.showError(context, context.tr('settle_invalid_amount'));
      return;
    }
    // Paying more than remains would invent a debt the household never had.
    if (_halalas(amt) > _halalas(widget.remaining)) {
      AppSnackBar.showError(
        context,
        context.trArgs('fmd_pay_over', {'amount': context.sar(widget.remaining)}),
        title: context.tr('settle_record_failed'),
      );
      return;
    }
    // Where the money comes from (rule 02): every payment leaves an account.
    final sources = RepaymentSources.of(context, widget.householdId, listen: false);
    if (_source == null) {
      AppSnackBar.showError(
        context,
        context.tr(sources.accounts.isEmpty ? 'repay_no_accounts' : 'repay_source_required'),
        title: context.tr('settle_record_failed'),
      );
      return;
    }
    final account = sources.accountFor(_source);
    if (account == null) {
      setState(() => _source = null);
      AppSnackBar.showError(context, context.tr('repay_err_unavailable'), title: context.tr('settle_record_failed'));
      return;
    }
    if (_halalas(account.balance) < _halalas(amt)) {
      AppSnackBar.showError(
        context,
        context.trArgs('repay_err_insufficient', {
          'account': account.name,
          'balance': context.sar(account.balance),
          'amount': context.sar(amt),
        }),
        title: context.tr('settle_record_failed'),
      );
      return;
    }
    if (!await _confirm(amt, account) || !mounted) return;

    var method = _paymentMethod;
    var recorded = amt;
    setState(() => _isSubmitting = true);
    try {
      final record = widget.recordPayment ??
          ({
            required String debtId,
            required double amount,
            required String paymentMethod,
            required String requestKey,
            required String accountId,
          }) =>
              ApiService.instance.recordFormerMemberDebtPayment(
                widget.householdId,
                debtId: debtId,
                amount: amount,
                paymentMethod: paymentMethod,
                requestKey: requestKey,
                accountId: accountId,
              );
      final receipt = await record(
        debtId: widget.debtId,
        amount: amt,
        paymentMethod: method,
        requestKey: _requestKey,
        accountId: account.id,
      );
      // A retry of a lost answer replays what the server stored first, whatever was typed since.
      if (receipt.amount > 0) recorded = receipt.amount;
      if (_knownMethods.contains(receipt.paymentMethod)) method = receipt.paymentMethod!;
    } catch (e) {
      // Never report a payment as recorded when the server did not say so.
      logFailure('FormerMemberDebt.pay', e);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (_isUnknownOutcome(e)) {
        // It may be stored. The sheet stays open: a retry sends the same key,
        // which the server records once.
        AppSnackBar.showWarning(context, context.tr('fmd_unconfirmed_msg'), title: context.tr('settle_unconfirmed_title'));
        widget.onRefresh();
        return;
      }
      if (_isStale(e)) widget.onRefresh();
      // The balance or the account changed since the sheet opened.
      if (e is NafaqahApiException && repaymentAccountErrorKey(e.code) != null) sources.provider?.refresh(force: true);
      AppSnackBar.showError(
        context,
        formerMemberDebtErrorText(context, e, remaining: widget.remaining, payment: true),
        title: context.tr('settle_record_failed'),
      );
      return;
    }

    // His balance changed on the server: the accounts show it now.
    sources.provider?.refresh(force: true);
    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      context.trArgs('repay_paid_from', {'amount': context.sar(recorded), 'account': account.name}),
      title: context.tr('settle_recorded_title'),
      icon: Icons.check_circle_outline,
    );
    Navigator.of(context).pop();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.remaining.toStringAsFixed(2);
    // The fill is fixed rose gold in both modes, so one ink works for both.
    const onGold = VelvetBurgundyColors.primaryLight;
    final sources = RepaymentSources.of(context, widget.householdId);
    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('fmd_pay_title'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(context.tr('fmd_pay_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ChoiceChip(
              label: Text(context.trArgs('settle_full', {'amount': context.sar(widget.remaining)})),
              selected: _amountCtrl.text == full,
              onSelected: (val) {
                if (val) setState(() => _amountCtrl.text = full);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('fmd_amount_field'),
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('settle_payment_amount'),
                floatingLabelStyle: TextStyle(color: context.accentText),
                prefixIcon: const Icon(Icons.payments_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('settle_payment_method'),
              style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _methodChip('stc_pay', Icons.phone_android_rounded),
                _methodChip('bank_transfer', Icons.account_balance_rounded),
                _methodChip('cash', Icons.payments_rounded),
              ],
            ),
            const SizedBox(height: 16),
            if (!sources.loaded)
              Center(child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText))
            else
              RepaymentAccountPicker(
                householdId: widget.householdId,
                accounts: sources.accounts,
                selected: _source,
                amount: parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0,
                formerMember: true,
                onChanged: (id) => setState(() => _source = id),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const ValueKey('fmd_pay_submit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemes.champagneGold,
                  foregroundColor: onGold,
                  disabledBackgroundColor: AppThemes.champagneGold,
                  disabledForegroundColor: onGold,
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 14, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: onGold),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  context.tr('fmd_record_payment'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: _isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(String id, IconData icon) {
    final isSelected = _paymentMethod == id;
    return ChoiceChip(
      avatar: Icon(icon, size: 14, color: isSelected ? context.accentText : context.textSecondary),
      label: Text(context.tr('pay_method_$id')),
      selected: isSelected,
      selectedColor: context.accentSubtleBg,
      backgroundColor: context.cardBg,
      checkmarkColor: context.accentText,
      labelStyle: TextStyle(
        color: isSelected ? context.accentText : context.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(color: isSelected ? context.accentText : context.borderColor),
      onSelected: (val) {
        if (val) setState(() => _paymentMethod = id);
      },
    );
  }
}

// ── Her waiver (إبراء) ──────────────────────────────────────────────────────

/// Confirms and records her waiver; pops `true` once the server recorded it.
class _FormerDebtWaiverDialog extends StatefulWidget {
  final String householdId;
  final String debtId;
  final double remaining;
  final FormerMemberDebtWaiver? waive;
  final VoidCallback onRefresh;

  const _FormerDebtWaiverDialog({
    required this.householdId,
    required this.debtId,
    required this.remaining,
    required this.onRefresh,
    this.waive,
  });

  @override
  State<_FormerDebtWaiverDialog> createState() => _FormerDebtWaiverDialogState();
}

class _FormerDebtWaiverDialogState extends State<_FormerDebtWaiverDialog> {
  /// One key per opening of the dialog, reused by every retry from it.
  late final String _requestKey;
  bool _busy = false;
  String? _message;
  bool _messageIsWarning = false;

  @override
  void initState() {
    super.initState();
    _requestKey = const Uuid().v4();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final waive = widget.waive ??
          ({required String debtId, required String requestKey}) =>
              ApiService.instance.waiveFormerMemberDebt(widget.householdId, debtId: debtId, requestKey: requestKey);
      await waive(debtId: widget.debtId, requestKey: _requestKey);
    } catch (e) {
      logFailure('FormerMemberDebt.waive', e);
      if (!mounted) return;
      final unknown = _isUnknownOutcome(e);
      setState(() {
        _busy = false;
        _messageIsWarning = unknown;
        _message = unknown
            ? context.tr('fmd_unconfirmed_msg')
            : formerMemberDebtErrorText(context, e, remaining: widget.remaining, payment: false);
      });
      if (unknown || _isStale(e)) widget.onRefresh();
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: context.cardBg,
      title: Text(context.tr('fmd_waive_title'), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.trArgs('fmd_waive_body', {'amount': context.sar(widget.remaining)}),
            style: TextStyle(color: context.textPrimary),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              key: const ValueKey('fmd_waive_message'),
              style: TextStyle(
                color: _messageIsWarning ? context.goldText : context.dangerColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('fmd_waive_cancel'),
          style: TextButton.styleFrom(foregroundColor: context.textSecondary),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          key: const ValueKey('fmd_waive_ok'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemes.champagneGold,
            foregroundColor: VelvetBurgundyColors.primaryLight,
            disabledBackgroundColor: AppThemes.champagneGold,
            disabledForegroundColor: VelvetBurgundyColors.primaryLight,
          ),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: VelvetBurgundyColors.primaryLight),
                )
              : Text(context.tr('fmd_waive_ok')),
        ),
      ],
    );
  }
}
