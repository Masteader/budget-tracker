import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../core/theme/velvet_burgundy_theme.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';
import '../../main.dart' show supabase;
import '../../models/household_dues.dart';
import 'family_reimbursement_card.dart' show ReimbursementRecorder;

/// Roommate balances, centred on the viewer (UX-16): their net balance first,
/// then the debts they are part of ("You owe Faisal", "Imran owes you"), then
/// the others.
class MultiRoommateSettlementCard extends StatefulWidget {
  final String householdId;
  final SettlementV2Summary? summary;
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
    if (widget.summary != null) {
      _summary = widget.summary;
      _isLoading = false;
    }
  }

  Future<void> _loadSummary() async {
    try {
      final res = await ApiService.instance.getSettlementV2(widget.householdId);
      if (mounted) {
        setState(() {
          _summary = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        onConfirmed: () {
          widget.onSettled?.call();
          _loadSummary();
        },
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
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
          ),
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
                        ? (context.isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight)
                        : context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                  ),
                ),
              ),
              Switch(
                value: _simplifyDebts,
                activeThumbColor: context.isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight,
                activeTrackColor: (context.isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight).withValues(alpha: 0.3),
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
                    ? const Color(0xFF10B981)
                    : (isNegative ? const Color(0xFFFF6B6B) : context.textSecondary);

                final sign = isPositive ? '+' : (isNegative ? '-' : '');
                final displayAmt = '$sign${context.sar(balance.abs())}';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: context.isDarkMode ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.key.toUpperCase()}: ',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        displayAmt,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 20),
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
                    color: context.isDark ? const Color(0xFF14060C) : const Color(0xFFFAF5F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: context.isDark ? const Color(0x33FFD2E1) : VelvetBurgundyColors.roseBorderLight,
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
                                color: context.isDark
                                    ? VelvetBurgundyColors.roseGoldGlow
                                    : VelvetBurgundyColors.primaryLight,
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
                          color: context.isDark
                              ? VelvetBurgundyColors.roseGoldGlow
                              : VelvetBurgundyColors.primaryLight,
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
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.isDark
                              ? VelvetBurgundyColors.primaryDark
                              : VelvetBurgundyColors.primaryLight,
                          foregroundColor: Colors.white,
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
          notes: '${widget.fromName} paid ${widget.toName} via ${_paymentMethod.toUpperCase()}',
        ),
      );
    } catch (e) {
      // Never report a settlement as recorded when the server rejected it.
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppSnackBar.showError(
        context,
        context.trArgs('settle_record_failed_msg', {'error': e}),
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
            Row(
              children: [
                _buildMethodChip('stc_pay', context.tr('pay_method_stc_pay'), Icons.phone_android_rounded),
                const SizedBox(width: 8),
                _buildMethodChip('bank_transfer', context.tr('pay_method_bank_transfer'), Icons.account_balance_rounded),
                const SizedBox(width: 8),
                _buildMethodChip('cash', context.tr('pay_method_cash'), Icons.payments_rounded),
              ],
            ),
            const SizedBox(height: 16),

            // Copy note
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
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
                  backgroundColor: context.isDark
                      ? VelvetBurgundyColors.primaryDark
                      : VelvetBurgundyColors.primaryLight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
      avatar: Icon(icon, size: 14, color: isSelected ? Colors.black : context.textSecondary),
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _paymentMethod = id);
      },
    );
  }
}
