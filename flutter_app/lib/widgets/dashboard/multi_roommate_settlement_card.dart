import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/api/base_api_client.dart' show ApiRequestException;
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';
import '../../main.dart' show supabase;
import '../../models/household_dues.dart';
import '../../utils/failure_log.dart';
import 'family_reimbursement_card.dart' show ReimbursementRecorder;

/// Roommate balances, centred on the viewer (UX-16): their net balance first,
/// then the debts they are part of ("You owe Faisal", "Imran owes you"), then
/// the others.
class MultiRoommateSettlementCard extends StatefulWidget {
  final String householdId;
  final SettlementV2Summary? summary;

  /// Called after a settlement is recorded, for the parent to refetch [summary].
  final VoidCallback? onSettled;
  final ReimbursementRecorder? recordPayment;

  /// The signed-in user; defaults to the Supabase session.
  final String? currentUserId;

  const MultiRoommateSettlementCard({
    super.key,
    required this.householdId,
    this.summary,
    this.onSettled,
    this.recordPayment,
    this.currentUserId,
  });

  @override
  State<MultiRoommateSettlementCard> createState() => _MultiRoommateSettlementCardState();
}

class _MultiRoommateSettlementCardState extends State<MultiRoommateSettlementCard> {
  SettlementV2Summary? _summary;
  bool _isLoading = true;
  bool _simplifyDebts = true;

  /// The refetch after a settlement failed: what [_summary] holds may include
  /// the debt just settled, so it is not offered for settling again.
  bool _loadFailed = false;

  /// Only the newest load may answer; a summary from the parent replaces any.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.summary != null) {
      _summary = widget.summary;
      _isLoading = false;
    } else {
      _loadSummary();
    }
  }

  @override
  void didUpdateWidget(covariant MultiRoommateSettlementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.householdId != oldWidget.householdId) {
      _summary = widget.summary;
      _isLoading = widget.summary == null;
      _loadFailed = false;
      _loadGeneration++;
      if (widget.summary == null) _loadSummary();
      return;
    }
    // A parent rebuild passes the same summary it had: adopting that would put
    // back a debt this card has since seen settled.
    if (widget.summary != null && !identical(widget.summary, oldWidget.summary)) {
      _summary = widget.summary;
      _isLoading = false;
      _loadFailed = false;
      _loadGeneration++;
    }
  }

  Future<void> _loadSummary() async {
    final generation = ++_loadGeneration;
    try {
      final res = await ApiService.instance.getSettlementV2(widget.householdId);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _summary = res;
          _isLoading = false;
          _loadFailed = false;
        });
      }
    } catch (e) {
      logFailure('RoommateSettlementCard.load', e);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _reloadAfterSettlement() {
    if (!mounted) return;
    // Until the new summary arrives the settled debt must not be tappable.
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    widget.onSettled?.call();
    _loadSummary();
  }

  void _showSettleSheet(
    BuildContext context, {
    required String fromId,
    required String toId,
    required String fromName,
    required String toName,
    required double amount,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RoommateSettleBottomSheet(
        householdId: widget.householdId,
        fromId: fromId,
        toId: toId,
        fromName: fromName,
        toName: toName,
        amount: amount,
        recordPayment: widget.recordPayment,
        onConfirmed: _reloadAfterSettlement,
      ),
    );
  }

  String? get _meId {
    if (widget.currentUserId != null) return widget.currentUserId;
    try {
      return supabase.auth.currentUser?.id;
    } catch (_) {
      return null; // no Supabase session (tests, signed out)
    }
  }

  String _debtTitle(BuildContext context, _DebtItem debt, String? me) {
    if (me != null && debt.fromId == me) return context.trArgs('settle_you_owe', {'to': debt.toName});
    if (me != null && debt.toId == me) return context.trArgs('settle_owes_you', {'from': debt.fromName});
    return context.trArgs('settle_owes', {'from': debt.fromName, 'to': debt.toName});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor),
        ),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.infoColor),
          ),
        ),
      );
    }

    if (_loadFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.tr('load_error_generic'),
                style: TextStyle(color: context.dangerColor, fontSize: 12),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.accentText),
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _loadFailed = false;
                });
                _loadSummary();
              },
              child: Text(context.tr('roles_retry')),
            ),
          ],
        ),
      );
    }

    final summary = _summary ?? const SettlementV2Summary(mode: 'multi_roommate');
    final me = _meId;
    final allDebts = _simplifyDebts
        ? summary.simplifiedDebts.map((d) => _DebtItem(d.fromId, d.toId, d.fromName, d.toName, d.amount)).toList()
        : summary.pairwiseDebts.map((d) => _DebtItem(d.fromId, d.toId, d.fromName, d.toName, d.amount)).toList();
    // Mine first: what I owe, then what I am owed (largest first), then the rest.
    int rank(_DebtItem d) => me == null ? 2 : (d.fromId == me ? 0 : (d.toId == me ? 1 : 2));
    final activeDebts = stableSorted(allDebts, (a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0 || rank(a) == 2) return byRank;
      return b.amount.compareTo(a.amount);
    });
    // The viewer's net balance (the same with or without simplification).
    final myLines = roommateDueLines(summary, me);
    final myOwe = myLines.where((l) => l.kind == DueKind.iOwe).fold(0.0, (s, l) => s + l.amount);
    final myOwed = myLines.where((l) => l.kind == DueKind.owedByRoommate).fold(0.0, (s, l) => s + l.amount);
    final myNet = myOwed - myOwe;
    // Shown while there are debts; with none, "All settled" says it.
    final isMember = me != null && (summary.simplifiedDebts.isNotEmpty || summary.pairwiseDebts.isNotEmpty);

    final isAllSettled = activeDebts.isEmpty;

    return ThreeDSurfaceCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const ThreeDIconPuck(
                      size: 40,
                      isRoseGold: true,
                      icon: Icons.group_outlined,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('roommate_settlements_title'),
                            style: GoogleFonts.outfit(
                              color: context.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                          ),
                          Text(
                            context.tr('roommate_settlements_subtitle'),
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 11,
                              fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // "Fewest transfers" (was the jargon "Simplify debts"), on its own
          // line so large text cannot push it off the card (UX-14).
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('simplify_debts'),
                  style: TextStyle(
                    color: _simplifyDebts
                        ? context.accentText
                        : context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                  ),
                ),
              ),
              Switch(
                value: _simplifyDebts,
                activeThumbColor: context.accentText,
                activeTrackColor: context.accentText.withValues(alpha: 0.3),
                onChanged: (val) {
                  setState(() => _simplifyDebts = val);
                },
              ),
            ],
          ),
          Text(
            context.tr('simplify_debts_hint'),
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),

          // The viewer's own net balance first (UX-16).
          if (isMember) ...[
            Text(
              myNet <= -0.005
                  ? context.trArgs('settle_my_net_owe', {'amount': context.sar(-myNet)})
                  : myNet >= 0.005
                      ? context.trArgs('settle_my_net_owed', {'amount': context.sar(myNet)})
                      : context.tr('settle_my_net_even'),
              key: const Key('roommate_my_net'),
              style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
          ],

          // Member Net Balances
          if (summary.roommateBalances.isNotEmpty) ...[
            Text(
              context.tr('settle_net_balances'),
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: summary.roommateBalances.entries.map((entry) {
                final balance = entry.value;
                final isPositive = balance > 0.01;
                final isNegative = balance < -0.01;
                final color = isPositive
                    ? context.successText : (isNegative ? context.dangerColor : context.textSecondary);

                final sign = isPositive ? '+' : (isNegative ? '-' : '');
                final displayAmt = '$sign${context.sar(balance.abs())}';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  // One paragraph, so name and amount share the width and the name
                  // breaks between words. The amount is one inline unit: it can
                  // never split across digits, and it keeps its own bidi order. It
                  // shrinks only if it is wider than a whole line.
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      children: [
                        TextSpan(text: '${entry.key.toUpperCase()}: '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              displayAmt,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // Debts List
          if (isAllSettled) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.alertSuccessBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.alertSuccessBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: context.successText, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('settle_all_settled'),
                          style: TextStyle(
                            color: context.accentText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          context.tr('all_roommates_settled'),
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeDebts.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final debt = activeDebts[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.subtleCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: context.borderColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _debtTitle(context, debt, me),
                              key: const Key('roommate_debt_title'),
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.sar(debt.amount),
                              style: GoogleFonts.outfit(
                                color: context.accentText,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 1-Click WhatsApp Settle Share Action
                      IconButton(
                        tooltip: context.tr('settle_share_whatsapp'),
                        icon: Icon(
                          Icons.share_rounded,
                          size: 18,
                          color: context.accentText,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          final text = context.trArgs('settle_whatsapp_msg', {'from': debt.fromName, 'amount': context.sar(debt.amount), 'to': debt.toName});
                          Clipboard.setData(ClipboardData(text: text));
                          AppSnackBar.showSuccess(
                            context,
                            context.tr('settle_whatsapp_copied'),
                            title: context.tr('settle_one_click'),
                            icon: Icons.check_circle_outline_rounded,
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.primaryButtonBg,
                            foregroundColor: context.primaryButtonFg,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            context.tr('settle_now'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showSettleSheet(
                              context,
                              fromId: debt.fromId,
                              toId: debt.toId,
                              fromName: debt.fromName,
                              toName: debt.toName,
                              amount: debt.amount,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The note stored with a settlement: read by everyone, so in no one's language,
/// and concatenated, because a name may itself look like a template.
///
/// U+2192 does not mirror, so in right-to-left text a bare `payer → recipient`
/// paints the payer on the right and the arrow pointing at them. The whole note
/// is therefore a left-to-right isolate, with each name in its own isolate so its
/// script keeps its own order: payer, arrow, recipient in any paragraph. Bidi
/// controls in a name are dropped so it cannot break out of its isolate.
String roommateSettlementNote({required String from, required String to, required String method}) {
  String name(String value) => '\u2068${value.replaceAll(RegExp('[\u202A-\u202E\u2066-\u2069]'), '')}\u2069';
  return '\u2066${name(from)} \u2192 ${name(to)} \u00B7 $method\u2069';
}

class _DebtItem {
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final double amount;

  _DebtItem(this.fromId, this.toId, this.fromName, this.toName, this.amount);
}

// ── Bottom Sheet for Recording Roommate Settlement ──────────────────────────

class _RoommateSettleBottomSheet extends StatefulWidget {
  final String householdId;
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final double amount;
  final VoidCallback onConfirmed;
  final ReimbursementRecorder? recordPayment;

  const _RoommateSettleBottomSheet({
    required this.householdId,
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.onConfirmed,
    this.recordPayment,
  });

  @override
  State<_RoommateSettleBottomSheet> createState() => _RoommateSettleBottomSheetState();
}

class _RoommateSettleBottomSheetState extends State<_RoommateSettleBottomSheet> {
  late TextEditingController _amountCtrl;
  String _paymentMethod = 'stc_pay';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.amount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSettlement() async {
    final amt = parseMoneyInput(_amountCtrl.text.trim()) ?? 0.0;
    if (amt <= 0) {
      AppSnackBar.showError(context, context.tr('settle_invalid_amount'));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final record = widget.recordPayment ?? ApiService.instance.recordReimbursementPayment;
      await record(
        ReimbursementRecordRequest(
          householdId: widget.householdId,
          payerId: widget.fromId,
          recipientId: widget.toId,
          amount: amt,
          paymentMethod: _paymentMethod,
          notes: roommateSettlementNote(from: widget.fromName, to: widget.toName, method: _paymentMethod),
        ),
      );
    } catch (e) {
      // Never report a settlement as recorded when the server rejected it.
      logFailure('RoommateSettlementCard.record', e);
      if (!mounted) return;
      // The server may have stored it, and this endpoint has no idempotency key:
      // the same amount left ready to tap would record it twice.
      if (e is ApiRequestException && e.outcomeUnknown) {
        AppSnackBar.showWarning(
          context,
          context.tr('settle_unconfirmed_msg'),
          title: context.tr('settle_unconfirmed_title'),
        );
        Navigator.of(context).pop();
        widget.onConfirmed();
        return;
      }
      setState(() => _isSubmitting = false);
      AppSnackBar.showError(
        context,
        context.tr('settle_record_failed_msg'),
        title: context.tr('settle_record_failed'),
      );
      return;
    }

    if (mounted) {
      AppSnackBar.showSuccess(
        context,
        context.trArgs('settle_roommate_recorded', {'from': widget.fromName, 'to': widget.toName, 'amount': context.sar(amt)}),
        title: context.tr('settle_recorded_title'),
      );
      Navigator.of(context).pop();
      widget.onConfirmed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('settle_roommate_title'),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.trArgs('settle_pays', {'from': widget.fromName, 'to': widget.toName}),
              style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Quick Chips
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(context.trArgs('settle_full', {'amount': context.sar(widget.amount)})),
                  selected: _amountCtrl.text == widget.amount.toStringAsFixed(2),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _amountCtrl.text = widget.amount.toStringAsFixed(2));
                    }
                  },
                ),
                ChoiceChip(
                  label: Text(context.trArgs('settle_half', {'amount': context.sar(widget.amount / 2)})),
                  selected: _amountCtrl.text == (widget.amount / 2).toStringAsFixed(2),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _amountCtrl.text = (widget.amount / 2).toStringAsFixed(2));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.tr('amount_sar'),
                floatingLabelStyle: TextStyle(color: context.accentText),
                prefixIcon: const Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Method Selector
            Text(
              context.tr('settle_payment_method'),
              style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Wraps: three chips do not fit one line in long languages or large text.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildMethodChip('stc_pay', context.tr('pay_method_stc_pay'), Icons.phone_android_rounded),
                _buildMethodChip('bank_transfer', context.tr('pay_method_bank_transfer'), Icons.account_balance_rounded),
                _buildMethodChip('cash', context.tr('pay_method_cash'), Icons.payments_rounded),
              ],
            ),
            const SizedBox(height: 16),

            // Copy note
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.textPrimary,
                side: BorderSide(color: context.borderColor),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(context.tr('settle_copy_stc_note'), style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final amt = _amountCtrl.text;
                await Clipboard.setData(
                  ClipboardData(text: context.trArgs('settle_roommate_note', {'amount': amt, 'to': widget.toName})),
                );
                if (context.mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    context.trArgs('settle_copied_quote', {'text': context.trArgs('settle_roommate_note', {'amount': amt, 'to': widget.toName})}),
                    title: context.tr('settle_copied_note'),
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primaryButtonBg,
                  foregroundColor: context.primaryButtonFg,
                  disabledBackgroundColor: context.primaryButtonBg,
                  disabledForegroundColor: context.primaryButtonFg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSubmitting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: context.primaryButtonFg),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  context.tr('settle_record_payment'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: _isSubmitting ? null : _submitSettlement,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodChip(String id, String label, IconData icon) {
    final isSelected = _paymentMethod == id;
    return ChoiceChip(
      avatar: Icon(icon, size: 14, color: isSelected ? context.accentText : context.textSecondary),
      label: Text(label),
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
