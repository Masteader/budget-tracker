import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/money.dart';
import '../../models/nafaqah.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../nafaqah/wife_allowance_card.dart';

/// Records a roommate settlement payment (used by the roommate card).
typedef ReimbursementRecorder = Future<Map<String, dynamic>> Function(ReimbursementRecordRequest request);

/// Loads the caller's Nafaqah summary. Defaults to the API; injectable for tests.
typedef NafaqahSummaryLoader = Future<NafaqahSummary> Function(String householdId);

/// Records a repayment to the wife and returns the outstanding balance after it.
typedef NafaqahReimbursementRecorder = Future<double> Function({
  required double amount,
  required String paymentMethod,
  required String wifeUserId,
});

/// Loads one wife's ledger (advances and repayments).
typedef NafaqahLedgerLoader = Future<NafaqahLedger> Function(String householdId, String wifeUserId);

/// Family mode (Islamic Nafaqah). Shared family expenses are the husband's
/// responsibility and are never split between the spouses. The card shows what
/// the husband owes his wife for shared things she paid from her own money,
/// records partial or full repayments, lists the history, and shows her
/// personal allowance for the salary cycle. Renders nothing outside family mode.
class FamilyReimbursementCard extends StatefulWidget {
  final String householdId;
  final NafaqahSummary? summary;
  final VoidCallback? onReimbursed;
  final NafaqahSummaryLoader? loadSummary;
  final NafaqahReimbursementRecorder? recordReimbursement;
  final NafaqahLedgerLoader? loadLedger;
  final AllowanceSetter? setAllowance;

  const FamilyReimbursementCard({
    super.key,
    required this.householdId,
    this.summary,
    this.onReimbursed,
    this.loadSummary,
    this.recordReimbursement,
    this.loadLedger,
    this.setAllowance,
  });

  @override
  State<FamilyReimbursementCard> createState() => _FamilyReimbursementCardState();
}

class _FamilyReimbursementCardState extends State<FamilyReimbursementCard> {
  NafaqahSummary? _summary;
  bool _isLoading = true;

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
  void didUpdateWidget(covariant FamilyReimbursementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.summary != null && widget.summary != oldWidget.summary) {
      _summary = widget.summary;
      _isLoading = false;
    } else if (widget.householdId != oldWidget.householdId) {
      _loadSummary();
    }
  }

  Future<void> _loadSummary() async {
    final loader = widget.loadSummary ?? ApiService.instance.getNafaqahSummary;
    try {
      final res = await loader(widget.householdId);
      if (mounted) {
        setState(() {
          _summary = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.champagneGold),
          ),
        ),
      );
    }

    final summary = _summary;
    if (summary == null || !summary.isFamily) return const SizedBox.shrink();

    final wives = summary.callerIsWife
        ? [summary.primaryWife!]
        : summary.wives;
    final showNames = wives.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < wives.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ReimbursementPanel(
            householdId: widget.householdId,
            summary: summary,
            wife: wives[i],
            showWifeName: showNames,
            recordReimbursement: widget.recordReimbursement,
            loadLedger: widget.loadLedger,
            onReimbursed: () {
              widget.onReimbursed?.call();
              _loadSummary();
            },
          ),
          const SizedBox(height: 12),
          WifeAllowanceCard(
            householdId: widget.householdId,
            wife: wives[i],
            cycleKey: summary.cycleKey,
            viewerIsWife: summary.callerIsWife,
            canSet: summary.canSetAllowance && wives[i].id != summary.callerUserId,
            showWifeName: showNames,
            setAllowance: widget.setAllowance,
            onChanged: _loadSummary,
          ),
        ],
      ],
    );
  }
}

class _ReimbursementPanel extends StatelessWidget {
  final String householdId;
  final NafaqahSummary summary;
  final NafaqahWife wife;
  final bool showWifeName;
  final NafaqahReimbursementRecorder? recordReimbursement;
  final NafaqahLedgerLoader? loadLedger;
  final VoidCallback onReimbursed;

  const _ReimbursementPanel({
    required this.householdId,
    required this.summary,
    required this.wife,
    required this.showWifeName,
    required this.onReimbursed,
    this.recordReimbursement,
    this.loadLedger,
  });

  void _openReimburseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReimburseBottomSheet(
        householdId: householdId,
        wifeUserId: wife.id,
        totalOwed: wife.reimbursement.outstanding,
        recordReimbursement: recordReimbursement,
        onConfirmed: onReimbursed,
      ),
    );
  }

  void _openHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LedgerHistorySheet(householdId: householdId, wifeUserId: wife.id, loadLedger: loadLedger),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gold = AppThemes.champagneGold;
    final balance = wife.reimbursement;
    final isSettled = balance.isSettled;
    final badgeColor = isSettled ? AppThemes.success : gold;
    final owedLabel = summary.callerIsWife ? context.tr('nafaqah_owed_to_you') : context.tr('husband_owes_wife');
    final actionLabel = summary.callerIsWife ? context.tr('nafaqah_confirm_received') : context.tr('reimburse_wife');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSettled ? context.borderColor : gold.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: gold.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.family_restroom_rounded, color: gold, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showWifeName && (wife.displayName ?? '').isNotEmpty
                          ? '${context.tr('family_nafaqah_title')} · ${wife.displayName}'
                          : context.tr('family_nafaqah_title'),
                      style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      context.tr('family_nafaqah_subtitle'),
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSettled ? Icons.check_circle_outline_rounded : Icons.history_edu_rounded,
                      size: 12,
                      color: badgeColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isSettled ? context.tr('settle_all_settled') : context.tr('settle_reimbursement_owed'),
                      style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!isSettled) ...[
            Text('$owedLabel:', style: TextStyle(color: context.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              context.sar(balance.outstanding),
              style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: gold),
            ),
            const SizedBox(height: 2),
            Text(context.tr('settle_wife_advanced'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
            const SizedBox(height: 12),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: AppThemes.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('settle_nafaqah_all_settled'),
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Pill(
                icon: Icons.north_east_rounded,
                label: context.trArgs('nafaqah_advanced_total', {'amount': context.sar(balance.grossAdvanced)}),
                color: gold,
              ),
              _Pill(
                icon: Icons.south_west_rounded,
                label: context.trArgs('nafaqah_reimbursed_total', {'amount': context.sar(balance.reimbursed)}),
                color: AppThemes.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isSettled && summary.canRecordReimbursement) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: AppThemes.deepGlacial,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _openReimburseSheet(context);
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              TextButton.icon(
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

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
          Text(label, style: TextStyle(color: context.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── History ─────────────────────────────────────────────────────────────────

class _LedgerHistorySheet extends StatefulWidget {
  final String householdId;
  final String wifeUserId;
  final NafaqahLedgerLoader? loadLedger;

  const _LedgerHistorySheet({required this.householdId, required this.wifeUserId, this.loadLedger});

  @override
  State<_LedgerHistorySheet> createState() => _LedgerHistorySheetState();
}

class _LedgerHistorySheetState extends State<_LedgerHistorySheet> {
  late final Future<NafaqahLedger> _future;

  @override
  void initState() {
    super.initState();
    final loader = widget.loadLedger ??
        (String hid, String wifeId) => ApiService.instance.getNafaqahLedger(hid, wifeUserId: wifeId);
    _future = loader(widget.householdId, widget.wifeUserId);
  }

  String _methodLabel(BuildContext context, String? method) {
    const known = {'stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other'};
    return context.tr('pay_method_${known.contains(method) ? method : 'other'}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
            context.tr('nafaqah_history_title'),
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<NafaqahLedger>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (snap.hasError) {
                  return Text(
                    context.trArgs('settle_record_failed_msg', {'error': snap.error ?? ''}),
                    style: TextStyle(color: context.dangerColor, fontSize: 12),
                  );
                }
                final history = snap.data?.history ?? const <NafaqahLedgerEntry>[];
                if (history.isEmpty) {
                  return Text(context.tr('nafaqah_history_empty'), style: TextStyle(color: context.textSecondary));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => Divider(color: context.borderColor, height: 1),
                  itemBuilder: (context, i) {
                    final e = history[i];
                    final color = e.isAdvance ? AppThemes.champagneGold : context.successText;
                    final title = e.isAdvance
                        ? context.trArgs('nafaqah_history_advance', {'merchant': e.merchant ?? context.tr('merchant_generic')})
                        : context.trArgs('nafaqah_history_reimbursement', {'method': _methodLabel(context, e.paymentMethod)});
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(e.isAdvance ? Icons.north_east_rounded : Icons.south_west_rounded, color: color),
                      title: Text(title, style: TextStyle(color: context.textPrimary, fontSize: 13)),
                      subtitle: e.timestamp == null
                          ? null
                          : Text(l10n.date(e.timestamp!, 'd MMM yyyy'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                      trailing: Text(
                        '${e.isAdvance ? '+' : '−'}${context.sar(e.amount)}',
                        style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w700),
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

// ── Record a repayment ──────────────────────────────────────────────────────

class _ReimburseBottomSheet extends StatefulWidget {
  final String householdId;
  final String wifeUserId;
  final double totalOwed;
  final VoidCallback onConfirmed;
  final NafaqahReimbursementRecorder? recordReimbursement;

  const _ReimburseBottomSheet({
    required this.householdId,
    required this.wifeUserId,
    required this.totalOwed,
    required this.onConfirmed,
    this.recordReimbursement,
  });

  @override
  State<_ReimburseBottomSheet> createState() => _ReimburseBottomSheetState();
}

class _ReimburseBottomSheetState extends State<_ReimburseBottomSheet> {
  late TextEditingController _amountCtrl;
  String _paymentMethod = 'stc_pay';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.totalOwed.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = parseMoneyInput(_amountCtrl.text.trim()) ?? 0.0;
    if (amt <= 0) {
      AppSnackBar.showError(context, context.tr('settle_invalid_amount'));
      return;
    }
    // Paying back more than is owed would invent a debt for the wife.
    if ((amt * 100).round() > (widget.totalOwed * 100).round()) {
      AppSnackBar.showError(
        context,
        context.trArgs('nafaqah_err_overpayment', {'amount': context.sar(widget.totalOwed)}),
        title: context.tr('settle_record_failed'),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final record = widget.recordReimbursement ??
          ({required double amount, required String paymentMethod, required String wifeUserId}) =>
              ApiService.instance.recordNafaqahReimbursement(
                widget.householdId,
                amount: amount,
                paymentMethod: paymentMethod,
                wifeUserId: wifeUserId,
              );
      await record(amount: amt, paymentMethod: _paymentMethod, wifeUserId: widget.wifeUserId);
    } catch (e) {
      // Never report a repayment as recorded when the server rejected it.
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final String message;
      if (e is NafaqahApiException && e.code == 'overpayment') {
        message = context.trArgs('nafaqah_err_overpayment', {'amount': context.sar(widget.totalOwed)});
      } else if (e is NafaqahApiException && e.code == 'forbidden') {
        message = context.tr('nafaqah_err_forbidden');
      } else {
        message = context.trArgs('settle_record_failed_msg', {'error': e});
      }
      AppSnackBar.showError(context, message, title: context.tr('settle_record_failed'));
      return;
    }

    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      context.trArgs('settle_recorded_via', {'amount': context.sar(amt), 'method': context.tr('pay_method_$_paymentMethod')}),
      title: context.tr('settle_recorded_title'),
      icon: Icons.check_circle_outline,
    );
    Navigator.of(context).pop();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.totalOwed.toStringAsFixed(2);
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
                decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('settle_wife_title'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(context.tr('settle_wife_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ChoiceChip(
              label: Text(context.trArgs('settle_full', {'amount': context.sar(widget.totalOwed)})),
              selected: _amountCtrl.text == full,
              onSelected: (val) {
                if (val) setState(() => _amountCtrl.text = full);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('reimburse_amount_field'),
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('settle_payment_amount'),
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
                _buildMethodChip('stc_pay', Icons.phone_android_rounded),
                _buildMethodChip('bank_transfer', Icons.account_balance_rounded),
                _buildMethodChip('cash', Icons.payments_rounded),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(context.tr('settle_copy_stc_note'), style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final note = context.trArgs('settle_nafaqah_note', {'amount': _amountCtrl.text});
                final copiedMsg = context.trArgs('settle_copied_quote', {'text': note});
                final copiedTitle = context.tr('settle_copied_note');
                await Clipboard.setData(ClipboardData(text: note));
                if (context.mounted) AppSnackBar.showSuccess(context, copiedMsg, title: copiedTitle);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemes.champagneGold,
                  foregroundColor: AppThemes.deepGlacial,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.deepGlacial),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  context.tr('settle_record_payment'),
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

  Widget _buildMethodChip(String id, IconData icon) {
    final isSelected = _paymentMethod == id;
    return ChoiceChip(
      avatar: Icon(icon, size: 14, color: isSelected ? AppThemes.deepGlacial : context.textSecondary),
      label: Text(context.tr('pay_method_$id')),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _paymentMethod = id);
      },
    );
  }
}
