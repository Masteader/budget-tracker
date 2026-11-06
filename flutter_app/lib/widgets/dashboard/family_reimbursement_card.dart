import 'package:flutter/material.dart';

import '../../utils/failure_log.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../models/models.dart';
import '../../models/money.dart';
import '../../models/nafaqah.dart';
import '../../services/api_service.dart';
import '../../services/nafaqah_write_errors.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../card_error_state.dart';
import '../nafaqah/former_member_debt_panel.dart';
import '../nafaqah/repayment_account_picker.dart';
import '../nafaqah/wife_allowance_card.dart';
import '../settings/settings_section.dart' show isLargeText;

export '../nafaqah/former_member_debt_panel.dart'
    show FormerMemberDebtPaymentRecorder, FormerMemberDebtWaiver, FormerMemberDebtReverser;

/// Records a roommate settlement payment (used by the roommate card).
typedef ReimbursementRecorder = Future<Map<String, dynamic>> Function(ReimbursementRecordRequest request);

/// Loads the caller's Nafaqah summary. Defaults to the API; injectable for tests.
typedef NafaqahSummaryLoader = Future<NafaqahSummary> Function(String householdId);

/// The husband (or an admin) records a repayment to the wife from [accountId]
/// and gets back the outstanding balance after it. Every repayment leaves an
/// account (owner decision 2026-11-06); [requestKey] is the same for every
/// retry from one sheet.
typedef NafaqahReimbursementRecorder = Future<double> Function({
  required double amount,
  required String paymentMethod,
  required String wifeUserId,
  required String accountId,
  required String requestKey,
});

/// Loads one wife's ledger (advances, repayments, reversals and her requests).
typedef NafaqahLedgerLoader = Future<NafaqahLedger> Function(String householdId, String wifeUserId);

/// The wife marks what she received: a pending request.
typedef NafaqahRequestCreator = Future<void> Function({
  required double amount,
  required String paymentMethod,
  required String requestKey,
});

/// She cancels her own pending request.
typedef NafaqahRequestCanceller = Future<void> Function({required String requestId});

/// The husband or an admin approves her request from [accountId]; returns
/// what is owed after it.
typedef NafaqahRequestApprover = Future<double> Function({
  required String requestId,
  required String accountId,
  required String requestKey,
});

/// The husband or an admin declines her request, with an optional reason.
typedef NafaqahRequestDecliner = Future<void> Function({required String requestId, String? reason});

/// Reverses a tracked repayment; returns what is owed after it.
typedef NafaqahReimbursementReverser = Future<double> Function({
  required String reimbursementId,
  required String requestKey,
});

const _knownMethods = {'stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other'};

String _methodLabel(BuildContext context, String? method) =>
    context.tr('pay_method_${_knownMethods.contains(method) ? method : 'other'}');

int _halalas(double sar) => (sar * 100).round();

/// The request may have taken effect: no answer, or the server failed without saying.
bool _isUnknownOutcome(Object error) => error is! NafaqahApiException || error.outcomeUnknown;

/// Family mode (Islamic Nafaqah). Shared family expenses are the husband's
/// responsibility and are never split between the spouses. The card shows what
/// the husband owes his wife for shared things she paid from her own money,
/// lists the history and her requests, and shows her personal allowance for
/// the salary cycle. The husband (or an admin) records repayments from an
/// account and approves or declines her requests; she marks what she received
/// (a request) and can cancel it. Renders nothing outside family mode; a
/// failed load is an error with a retry, never "nothing owed" (UX-01).
class FamilyReimbursementCard extends StatefulWidget {
  final String householdId;
  final NafaqahSummary? summary;
  final VoidCallback? onReimbursed;

  /// Every summary the card loads (first load, retry, after a repayment), so
  /// the dashboard hero can show what is owed to the wife.
  final ValueChanged<NafaqahSummary>? onSummaryLoaded;
  final NafaqahSummaryLoader? loadSummary;
  final NafaqahReimbursementRecorder? recordReimbursement;
  final NafaqahLedgerLoader? loadLedger;
  final AllowanceSetter? setAllowance;
  final NafaqahRequestCreator? createRequest;
  final NafaqahRequestCanceller? cancelRequest;
  final NafaqahRequestApprover? approveRequest;
  final NafaqahRequestDecliner? declineRequest;
  final NafaqahReimbursementReverser? reverseReimbursement;
  final FormerMemberDebtPaymentRecorder? recordFormerMemberDebtPayment;
  final FormerMemberDebtWaiver? waiveFormerMemberDebt;
  final FormerMemberDebtReverser? reverseFormerMemberDebtPayment;
  final Widget? emptyPlaceholder;

  const FamilyReimbursementCard({
    super.key,
    required this.householdId,
    this.summary,
    this.onReimbursed,
    this.onSummaryLoaded,
    this.loadSummary,
    this.recordReimbursement,
    this.loadLedger,
    this.setAllowance,
    this.createRequest,
    this.cancelRequest,
    this.approveRequest,
    this.declineRequest,
    this.reverseReimbursement,
    this.recordFormerMemberDebtPayment,
    this.waiveFormerMemberDebt,
    this.reverseFormerMemberDebtPayment,
    this.emptyPlaceholder,
  });

  @override
  State<FamilyReimbursementCard> createState() => _FamilyReimbursementCardState();
}

class _FamilyReimbursementCardState extends State<FamilyReimbursementCard> {
  NafaqahSummary? _summary;
  bool _isLoading = true;
  bool _failed = false;
  DateTime? _lastUpdated;

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
      // Never show the previous household's ledger while this one loads.
      _summary = null;
      _isLoading = true;
      _failed = false;
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
          _failed = false;
          _lastUpdated = DateTime.now();
        });
        widget.onSummaryLoaded?.call(res);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = true;
        });
      }
    }
  }

  void _retry() {
    setState(() => _isLoading = _summary == null);
    _loadSummary();
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
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.goldText),
          ),
        ),
      );
    }

    final summary = _summary;
    if (summary == null && _failed) {
      return CardErrorState(
        title: context.tr('family_nafaqah_title'),
        message: context.tr('load_error_nafaqah'),
        icon: Icons.family_restroom_rounded,
        onRetry: _retry,
      );
    }
    if (summary == null || !summary.isFamily) return widget.emptyPlaceholder ?? const SizedBox.shrink();

    final wives = summary.callerIsWife && summary.primaryWife != null
        ? [summary.primaryWife!]
        : summary.wives;
    final showNames = wives.length > 1;
    final debts = summary.formerMemberDebts;

    if (wives.isEmpty && !summary.needsProvider && debts.isEmpty && !_failed) {
      return widget.emptyPlaceholder ?? const SizedBox.shrink();
    }

    void onChanged() {
      widget.onReimbursed?.call();
      _loadSummary();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed) ...[
          CardErrorBanner(lastUpdated: _lastUpdated, onRetry: _retry),
          const SizedBox(height: 8),
        ],
        if (summary.needsProvider) ...[
          _NoticeBanner(
            key: const ValueKey('nafaqah_needs_provider'),
            icon: Icons.person_search_rounded,
            title: context.tr('nafaqah_provider_missing_title'),
            message: context.tr(
              summary.canSetProvider ? 'nafaqah_provider_missing_settings' : 'nafaqah_provider_missing_member',
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < wives.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ReimbursementPanel(
            householdId: widget.householdId,
            summary: summary,
            wife: wives[i],
            showWifeName: showNames,
            actions: _LedgerActions(
              householdId: widget.householdId,
              wifeUserId: wives[i].id,
              record: widget.recordReimbursement,
              loadLedger: widget.loadLedger,
              createRequest: widget.createRequest,
              cancelRequest: widget.cancelRequest,
              approveRequest: widget.approveRequest,
              declineRequest: widget.declineRequest,
              reverse: widget.reverseReimbursement,
            ),
            onChanged: onChanged,
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
        // A deleted wife's record outlives her membership: shown even when no
        // wife remains (the settings placeholder still explains the missing role).
        if (debts.isNotEmpty && wives.isEmpty && !summary.needsProvider && widget.emptyPlaceholder != null) ...[
          widget.emptyPlaceholder!,
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < debts.length; i++) ...[
          if (i > 0 || wives.isNotEmpty) const SizedBox(height: 12),
          FormerMemberDebtPanel(
            key: ValueKey('fmd_panel_${debts[i].id}'),
            debt: debts[i],
            canManage: summary.canManageFormerMemberDebts,
            householdId: widget.householdId,
            recordPayment: widget.recordFormerMemberDebtPayment,
            waive: widget.waiveFormerMemberDebt,
            reverse: widget.reverseFormerMemberDebtPayment,
            onChanged: onChanged,
            onRefresh: _loadSummary,
          ),
        ],
      ],
    );
  }
}

/// The server calls of one wife's panel: the injected ones, or the API's.
class _LedgerActions {
  final String householdId;
  final String wifeUserId;
  final NafaqahReimbursementRecorder? record;
  final NafaqahLedgerLoader? loadLedger;
  final NafaqahRequestCreator? createRequest;
  final NafaqahRequestCanceller? cancelRequest;
  final NafaqahRequestApprover? approveRequest;
  final NafaqahRequestDecliner? declineRequest;
  final NafaqahReimbursementReverser? reverse;

  const _LedgerActions({
    required this.householdId,
    required this.wifeUserId,
    this.record,
    this.loadLedger,
    this.createRequest,
    this.cancelRequest,
    this.approveRequest,
    this.declineRequest,
    this.reverse,
  });

  Future<double> recordRepayment({
    required double amount,
    required String paymentMethod,
    required String accountId,
    required String requestKey,
  }) =>
      record != null
          ? record!(amount: amount, paymentMethod: paymentMethod, wifeUserId: wifeUserId, accountId: accountId, requestKey: requestKey)
          : ApiService.instance.recordNafaqahReimbursement(
              householdId,
              amount: amount,
              paymentMethod: paymentMethod,
              wifeUserId: wifeUserId,
              accountId: accountId,
              requestKey: requestKey,
            );

  Future<NafaqahLedger> ledger() => loadLedger != null
      ? loadLedger!(householdId, wifeUserId)
      : ApiService.instance.getNafaqahLedger(householdId, wifeUserId: wifeUserId);

  Future<void> ask({required double amount, required String paymentMethod, required String requestKey}) =>
      createRequest != null
          ? createRequest!(amount: amount, paymentMethod: paymentMethod, requestKey: requestKey)
          : ApiService.instance
              .createNafaqahReimbursementRequest(householdId, amount: amount, paymentMethod: paymentMethod, requestKey: requestKey);

  Future<void> cancel(String requestId) => cancelRequest != null
      ? cancelRequest!(requestId: requestId)
      : ApiService.instance.cancelNafaqahReimbursementRequest(householdId, requestId: requestId);

  Future<double> approve({required String requestId, required String accountId, required String requestKey}) =>
      approveRequest != null
          ? approveRequest!(requestId: requestId, accountId: accountId, requestKey: requestKey)
          : ApiService.instance
              .approveNafaqahReimbursementRequest(householdId, requestId: requestId, accountId: accountId, requestKey: requestKey);

  Future<void> decline({required String requestId, String? reason}) => declineRequest != null
      ? declineRequest!(requestId: requestId, reason: reason)
      : ApiService.instance.declineNafaqahReimbursementRequest(householdId, requestId: requestId, reason: reason);

  Future<double> reverseRepayment({required String reimbursementId, required String requestKey}) => reverse != null
      ? reverse!(reimbursementId: reimbursementId, requestKey: requestKey)
      : ApiService.instance.reverseNafaqahReimbursement(householdId, reimbursementId: reimbursementId, requestKey: requestKey);
}

class _ReimbursementPanel extends StatelessWidget {
  final String householdId;
  final NafaqahSummary summary;
  final NafaqahWife wife;
  final bool showWifeName;
  final _LedgerActions actions;
  final VoidCallback onChanged;

  const _ReimbursementPanel({
    required this.householdId,
    required this.summary,
    required this.wife,
    required this.showWifeName,
    required this.actions,
    required this.onChanged,
  });

  void _openReimburseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReimburseBottomSheet(
        householdId: householdId,
        totalOwed: wife.reimbursement.outstanding,
        actions: actions,
        onConfirmed: onChanged,
      ),
    );
  }

  void _openRequestSheet(BuildContext context) {
    final balance = wife.reimbursement;
    final available = (_halalas(balance.outstanding) - _halalas(balance.pendingRequested)).clamp(0, 1 << 52) / 100;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestSheet(available: available.toDouble(), actions: actions, onSent: onChanged),
    );
  }

  void _openHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LedgerHistorySheet(actions: actions, onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.goldText;
    final balance = wife.reimbursement;
    final isSettled = balance.isSettled;
    final badgeColor = isSettled ? context.accentText : gold;
    final canRequest = summary.canRequestFor(wife);
    final canDecide = summary.canDecideFor(wife);
    final pending = wife.pendingRequests;
    final pendingTotal = pending.fold<int>(0, (sum, r) => sum + _halalas(r.amount)) / 100;
    final owedLabel = summary.callerIsWife ? context.tr('nafaqah_owed_to_you') : context.tr('husband_owes_wife');
    final historyButton = TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: context.accentText),
      onPressed: () => _openHistory(context),
      icon: const Icon(Icons.receipt_long_outlined, size: 18),
      label: Text(context.tr('nafaqah_history')),
    );
    const puck = ThreeDIconPuck(
      icon: Icons.family_restroom_rounded,
      size: 44,
      isRoseGold: true,
      isSquircle: true,
    );
    final headerText = Column(
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
        const SizedBox(height: 6),
        // Under the title: beside it, large text or a long label would
        // squeeze both until words break (UX-14).
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _StatusBadge(
              color: badgeColor,
              icon: isSettled ? Icons.check_circle_outline_rounded : Icons.history_edu_rounded,
              label: isSettled ? context.tr('settle_all_settled') : context.tr('settle_reimbursement_owed'),
            ),
            // The in-app pending indicator: requests awaiting the husband's approval.
            if (pending.isNotEmpty)
              _StatusBadge(
                key: ValueKey('req_badge_${wife.id}'),
                color: context.accentText,
                icon: Icons.hourglass_top_rounded,
                label: context.trArgs('req_pending_badge', {'amount': context.sar(pendingTotal)}),
              ),
          ],
        ),
      ],
    );

    final Widget? primary;
    if (canDecide && !isSettled) {
      primary = _GoldButton(
        key: ValueKey('nafaqah_reimburse_${wife.id}'),
        icon: Icons.payments_outlined,
        label: context.tr('reimburse_wife'),
        onPressed: () {
          HapticFeedback.lightImpact();
          _openReimburseSheet(context);
        },
      );
    } else if (canRequest && !isSettled) {
      primary = _GoldButton(
        key: ValueKey('nafaqah_mark_received_${wife.id}'),
        icon: Icons.move_to_inbox_rounded,
        label: context.tr('nafaqah_mark_received'),
        onPressed: () {
          HapticFeedback.lightImpact();
          _openRequestSheet(context);
        },
      );
    } else {
      primary = null;
    }

    return ThreeDSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      customBorder: Border.all(
        color: isSettled ? context.borderColor : gold.withValues(alpha: 0.35),
        width: 1.2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // At very large text the title's longest word needs the whole width.
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
          if (wife.pendingDeletion != null) ...[
            _NoticeBanner(
              key: ValueKey('fmd_pending_deletion_${wife.id}'),
              icon: Icons.event_busy_rounded,
              title: context.tr('fmd_notice_title'),
              message: context.trArgs('fmd_notice_body', {
                'name': (wife.displayName ?? '').trim().isNotEmpty
                    ? wife.displayName!.trim()
                    : context.tr(summary.callerRole == 'husband' ? 'fmd_notice_your_wife' : 'fmd_notice_the_wife'),
                'date': AppLocalizations.of(context).date(wife.pendingDeletion!.scheduledFor, 'd MMMM yyyy'),
                'amount': context.sar(wife.pendingDeletion!.outstanding),
              }),
            ),
            const SizedBox(height: 12),
          ],
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
                Icon(Icons.verified_rounded, color: context.accentText, size: 20),
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
          if (balance.isOverpaid) ...[
            _NoticeBanner(
              key: ValueKey('nafaqah_overpaid_${wife.id}'),
              icon: Icons.warning_amber_rounded,
              title: context.trArgs('nafaqah_overpaid', {'amount': context.sar(balance.overpaid)}),
              message: context.tr('nafaqah_overpaid_hint'),
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
                color: context.accentText,
              ),
            ],
          ),
          if (pending.isNotEmpty || (canRequest && wife.requests.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _RequestsSection(
              key: ValueKey('req_section_${wife.id}'),
              requests: wife.requests,
              asWife: canRequest,
              asDecider: canDecide,
              totalOwed: balance.outstanding,
              actions: actions,
              onChanged: onChanged,
            ),
          ],
          const SizedBox(height: 12),
          _ActionsRow(primary: primary, secondary: historyButton),
        ],
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _GoldButton({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        // The fixed rose-gold fill: goldText is an ink colour and is a dark
        // amber in light mode, where the maroon label cannot be read on it.
        backgroundColor: AppThemes.champagneGold,
        foregroundColor: VelvetBurgundyColors.primaryLight,
        disabledBackgroundColor: AppThemes.champagneGold,
        disabledForegroundColor: VelvetBurgundyColors.primaryLight,
        elevation: 0,
        padding: const EdgeInsetsDirectional.symmetric(vertical: 12, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      onPressed: onPressed,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _StatusBadge({super.key, required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// The main action and history: side by side, or stacked at very large text.
class _ActionsRow extends StatelessWidget {
  final Widget? primary;
  final Widget secondary;

  const _ActionsRow({required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    if (isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (primary != null) primary!,
          Align(alignment: AlignmentDirectional.centerStart, child: secondary),
        ],
      );
    }
    return Row(
      children: [
        if (primary != null) ...[
          Expanded(child: primary!),
          const SizedBox(width: 8),
        ],
        secondary,
      ],
    );
  }
}

/// A warning line inside the Nafaqah card (missing provider, overpaid ledger).
class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _NoticeBanner({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = context.dangerColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkMode ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(message, style: TextStyle(color: context.textSecondary, fontSize: 11)),
              ],
            ),
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
          Flexible(
            child: Text(label, style: TextStyle(color: context.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Her requests ────────────────────────────────────────────────────────────

/// Her requests: the pending ones (with Cancel for her, Approve and Decline for
/// the husband or an admin), and for her the latest outcomes.
class _RequestsSection extends StatefulWidget {
  final List<ReimbursementRequest> requests;
  final bool asWife;
  final bool asDecider;
  final double totalOwed;
  final _LedgerActions actions;
  final VoidCallback onChanged;

  const _RequestsSection({
    super.key,
    required this.requests,
    required this.asWife,
    required this.asDecider,
    required this.totalOwed,
    required this.actions,
    required this.onChanged,
  });

  @override
  State<_RequestsSection> createState() => _RequestsSectionState();
}

class _RequestsSectionState extends State<_RequestsSection> {
  String? _busy;

  Future<void> _cancel(ReimbursementRequest r) async {
    setState(() => _busy = r.id);
    try {
      await widget.actions.cancel(r.id);
    } catch (e) {
      logFailure('NafaqahRequest.cancel', e);
      if (!mounted) return;
      setState(() => _busy = null);
      _showError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = null);
    AppSnackBar.showSuccess(context, context.tr('req_cancelled_done'), icon: Icons.check_circle_outline);
    widget.onChanged();
  }

  void _showError(BuildContext context, Object e) {
    final message = trackedRepaymentErrorText(context, e, owedNow: widget.totalOwed) ??
        (e is NafaqahApiException && e.code == 'forbidden' ? context.tr('nafaqah_err_forbidden') : context.tr('settle_record_failed_msg'));
    AppSnackBar.showError(context, message, title: context.tr('settle_record_failed'));
    // The request changed elsewhere, or the answer was lost: show what is stored now.
    if (_isUnknownOutcome(e) || (e is NafaqahApiException && (e.code == 'request_not_pending' || e.code == 'request_not_found'))) {
      widget.onChanged();
    }
  }

  void _approve(ReimbursementRequest r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApproveRequestSheet(
        householdId: widget.actions.householdId,
        request: r,
        totalOwed: widget.totalOwed,
        actions: widget.actions,
        onDone: widget.onChanged,
      ),
    );
  }

  Future<void> _decline(ReimbursementRequest r) async {
    final declined = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeclineRequestDialog(request: r, actions: widget.actions),
    );
    if (declined != true || !mounted) return;
    AppSnackBar.showSuccess(context, context.tr('req_declined_done'), icon: Icons.check_circle_outline);
    widget.onChanged();
  }

  String _statusLabel(BuildContext context, ReimbursementRequest r) {
    if (r.status == kRequestDeclined && (r.reason ?? '').isNotEmpty) {
      return context.trArgs('req_declined_reason', {'reason': r.reason!});
    }
    const known = {kRequestPending, kRequestApproved, kRequestDeclined, kRequestCancelled, kRequestClosed};
    return context.tr('req_status_${known.contains(r.status) ? r.status : kRequestClosed}');
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.requests.where((r) => r.isPending).toList();
    // She also sees what became of her latest requests.
    final answered = widget.asWife ? widget.requests.where((r) => !r.isPending).take(3).toList() : const <ReimbursementRequest>[];
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.accentSubtleBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending.isNotEmpty)
            Text(
              context.trArgs('req_pending_title', {'count': '${pending.length}'}),
              style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          for (final r in pending) ...[
            const SizedBox(height: 8),
            Text(
              context.trArgs('req_line', {'amount': context.sar(r.amount), 'method': _methodLabel(context, r.paymentMethod)}),
              key: ValueKey('req_row_${r.id}'),
              style: TextStyle(color: context.textPrimary, fontSize: 12),
            ),
            if (r.createdAt != null)
              Text(l10n.date(r.createdAt!, 'd MMM yyyy'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                if (widget.asWife)
                  TextButton.icon(
                    key: ValueKey('req_cancel_${r.id}'),
                    style: TextButton.styleFrom(foregroundColor: context.textSecondary),
                    onPressed: _busy == null ? () => _cancel(r) : null,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(context.tr('req_cancel')),
                  ),
                if (widget.asDecider) ...[
                  TextButton.icon(
                    key: ValueKey('req_approve_${r.id}'),
                    style: TextButton.styleFrom(foregroundColor: context.accentText),
                    onPressed: _busy == null ? () => _approve(r) : null,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(context.tr('req_approve')),
                  ),
                  TextButton.icon(
                    key: ValueKey('req_decline_${r.id}'),
                    style: TextButton.styleFrom(foregroundColor: context.dangerColor),
                    onPressed: _busy == null ? () => _decline(r) : null,
                    icon: const Icon(Icons.block_rounded, size: 16),
                    label: Text(context.tr('req_decline')),
                  ),
                ],
              ],
            ),
          ],
          if (answered.isNotEmpty) ...[
            if (pending.isNotEmpty) Divider(color: context.borderColor, height: 16),
            Text(
              context.tr('req_recent_title'),
              style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            for (final r in answered) ...[
              const SizedBox(height: 6),
              Text(
                '${context.sar(r.amount)} · ${_statusLabel(context, r)}',
                key: ValueKey('req_outcome_${r.id}'),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// She marks what she received: a pending request. Nothing moves until it is approved.
class _RequestSheet extends StatefulWidget {
  final double available;
  final _LedgerActions actions;
  final VoidCallback onSent;

  const _RequestSheet({required this.available, required this.actions, required this.onSent});

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  late final TextEditingController _amountCtrl;

  /// One key per opening of the sheet: a retry is sent once.
  late final String _requestKey;
  String _paymentMethod = 'cash';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.available > 0 ? widget.available.toStringAsFixed(2) : '');
    _requestKey = const Uuid().v4();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rounded = roundedMoneyTextIfRounded(_amountCtrl.text);
    if (rounded != null) setState(() => _amountCtrl.text = rounded);
    final amt = parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0;
    if (_halalas(amt) <= 0) {
      AppSnackBar.showError(context, context.tr('settle_invalid_amount'));
      return;
    }
    if (_halalas(amt) > _halalas(widget.available)) {
      AppSnackBar.showError(context, context.trArgs('req_err_pending_cap', {'amount': context.sar(widget.available)}),
          title: context.tr('settle_record_failed'));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.actions.ask(amount: amt, paymentMethod: _paymentMethod, requestKey: _requestKey);
    } catch (e) {
      logFailure('NafaqahRequest.create', e);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (_isUnknownOutcome(e)) {
        // It may be stored; a retry sends the same key, which the server keeps once.
        AppSnackBar.showWarning(context, context.tr('fmd_unconfirmed_msg'), title: context.tr('settle_unconfirmed_title'));
        widget.onSent();
        return;
      }
      AppSnackBar.showError(
        context,
        trackedRepaymentErrorText(context, e, owedNow: widget.available) ??
            (e is NafaqahApiException && e.code == 'invalid' ? context.tr('nafaqah_err_invalid_amount') : context.tr('settle_record_failed_msg')),
        title: context.tr('settle_record_failed'),
      );
      return;
    }
    if (!mounted) return;
    AppSnackBar.showSuccess(context, context.tr('req_sent'), title: context.tr('settle_recorded_title'), icon: Icons.check_circle_outline);
    Navigator.of(context).pop();
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    const onGold = VelvetBurgundyColors.primaryLight;
    return _SheetFrame(
      children: [
        Text(
          context.tr('req_sheet_title'),
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(context.tr('req_sheet_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('req_amount_field'),
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
        _MethodChips(selected: _paymentMethod, onChanged: (m) => setState(() => _paymentMethod = m)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: _GoldButton(
            key: const ValueKey('req_send'),
            icon: Icons.send_rounded,
            label: context.tr('req_send'),
            onPressed: _isSubmitting ? null : _submit,
          ),
        ),
        if (_isSubmitting) ...[
          const SizedBox(height: 8),
          const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: onGold))),
        ],
      ],
    );
  }
}

/// The husband or an admin approves her request: exactly its amount, from the
/// account he picks.
class _ApproveRequestSheet extends StatefulWidget {
  final String householdId;
  final ReimbursementRequest request;
  final double totalOwed;
  final _LedgerActions actions;
  final VoidCallback onDone;

  const _ApproveRequestSheet({
    required this.householdId,
    required this.request,
    required this.totalOwed,
    required this.actions,
    required this.onDone,
  });

  @override
  State<_ApproveRequestSheet> createState() => _ApproveRequestSheetState();
}

class _ApproveRequestSheetState extends State<_ApproveRequestSheet> {
  late final String _requestKey;
  String? _source;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _requestKey = const Uuid().v4();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) RepaymentSources.ensureLoaded(context, widget.householdId);
    });
  }

  Future<void> _submit() async {
    final amt = widget.request.amount;
    final sources = RepaymentSources.of(context, widget.householdId, listen: false);
    final account = _chosenAccount(context, sources, _source, amt, onStale: () => setState(() => _source = null));
    if (account == null) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.actions.approve(requestId: widget.request.id, accountId: account.id, requestKey: _requestKey);
    } catch (e) {
      logFailure('NafaqahRequest.approve', e);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (_isUnknownOutcome(e)) {
        // It may be stored. The sheet stays open: a retry sends the same key.
        AppSnackBar.showWarning(context, context.tr('fmd_unconfirmed_msg'), title: context.tr('settle_unconfirmed_title'));
        widget.onDone();
        return;
      }
      if (e is NafaqahApiException && repaymentAccountErrorKey(e.code) != null) sources.provider?.refresh(force: true);
      AppSnackBar.showError(
        context,
        trackedRepaymentErrorText(context, e, owedNow: widget.totalOwed) ?? context.tr('settle_record_failed_msg'),
        title: context.tr('settle_record_failed'),
      );
      if (e is NafaqahApiException && (e.code == 'request_not_pending' || e.code == 'request_not_found')) {
        Navigator.of(context).pop();
        widget.onDone();
      }
      return;
    }
    // His balance changed on the server: the accounts show it now.
    sources.provider?.refresh(force: true);
    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      context.trArgs('req_approved_done', {'amount': context.sar(amt), 'account': account.name}),
      title: context.tr('settle_recorded_title'),
      icon: Icons.check_circle_outline,
    );
    Navigator.of(context).pop();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final sources = RepaymentSources.of(context, widget.householdId);
    final amount = widget.request.amount;
    return _SheetFrame(
      children: [
        Text(
          context.trArgs('req_approve_title', {'amount': context.sar(amount)}),
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          context.trArgs('req_approve_desc', {'amount': context.sar(amount)}),
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (!sources.loaded)
          Center(child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText))
        else
          RepaymentAccountPicker(
            householdId: widget.householdId,
            accounts: sources.accounts,
            selected: _source,
            amount: amount,
            onChanged: (id) => setState(() => _source = id),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: _GoldButton(
            key: const ValueKey('req_approve_submit'),
            icon: Icons.check_circle_outline_rounded,
            label: context.tr('req_approve_submit'),
            onPressed: _isSubmitting ? null : _submit,
          ),
        ),
      ],
    );
  }
}

/// The account a payment leaves, as the sheet checks it before the server:
/// chosen, still one the viewer may use, and holding [amount]. Shows why not
/// and returns null otherwise.
Account? _chosenAccount(BuildContext context, RepaymentSources sources, String? choice, double amount,
    {required VoidCallback onStale}) {
  if (choice == null) {
    AppSnackBar.showError(
      context,
      context.tr(sources.accounts.isEmpty ? 'repay_no_accounts' : 'repay_source_required'),
      title: context.tr('settle_record_failed'),
    );
    return null;
  }
  final account = sources.accountFor(choice);
  if (account == null) {
    onStale();
    AppSnackBar.showError(context, context.tr('repay_err_unavailable'), title: context.tr('settle_record_failed'));
    return null;
  }
  if (_halalas(account.balance) < _halalas(amount)) {
    AppSnackBar.showError(
      context,
      context.trArgs('repay_err_insufficient', {
        'account': account.name,
        'balance': context.sar(account.balance),
        'amount': context.sar(amount),
      }),
      title: context.tr('settle_record_failed'),
    );
    return null;
  }
  return account;
}

/// Declines her request with an optional short reason; pops `true` once the
/// server recorded it.
class _DeclineRequestDialog extends StatefulWidget {
  final ReimbursementRequest request;
  final _LedgerActions actions;

  const _DeclineRequestDialog({required this.request, required this.actions});

  @override
  State<_DeclineRequestDialog> createState() => _DeclineRequestDialogState();
}

class _DeclineRequestDialogState extends State<_DeclineRequestDialog> {
  final _reasonCtrl = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.actions.decline(requestId: widget.request.id, reason: _reasonCtrl.text);
    } catch (e) {
      logFailure('NafaqahRequest.decline', e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _isUnknownOutcome(e)
            ? context.tr('fmd_unconfirmed_msg')
            : trackedRepaymentErrorText(context, e) ??
                (e is NafaqahApiException && e.code == 'forbidden' ? context.tr('nafaqah_err_forbidden') : context.tr('settle_record_failed_msg'));
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: context.cardBg,
      title: Text(context.tr('req_decline_title'), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.trArgs('req_line', {
              'amount': context.sar(widget.request.amount),
              'method': _methodLabel(context, widget.request.paymentMethod),
            }),
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(context.tr('req_decline_body'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('req_decline_reason'),
            controller: _reasonCtrl,
            maxLength: 200,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: context.tr('req_decline_reason'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: TextStyle(color: context.dangerColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('req_decline_cancel'),
          style: TextButton.styleFrom(foregroundColor: context.textSecondary),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        OutlinedButton(
          key: const ValueKey('req_decline_ok'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.dangerColor,
            side: BorderSide(color: context.dangerColor),
          ),
          onPressed: _busy ? null : _submit,
          child: Text(context.tr('req_decline')),
        ),
      ],
    );
  }
}

/// The frame of a bottom sheet: a handle, padding above the keyboard, scrolling.
class _SheetFrame extends StatelessWidget {
  final List<Widget> children;

  const _SheetFrame({required this.children});

  @override
  Widget build(BuildContext context) {
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
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MethodChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _MethodChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String id, IconData icon) {
      final isSelected = selected == id;
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
          if (val) onChanged(id);
        },
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        chip('stc_pay', Icons.phone_android_rounded),
        chip('bank_transfer', Icons.account_balance_rounded),
        chip('cash', Icons.payments_rounded),
      ],
    );
  }
}

// ── History ─────────────────────────────────────────────────────────────────

class _LedgerHistorySheet extends StatefulWidget {
  final _LedgerActions actions;
  final VoidCallback onChanged;

  const _LedgerHistorySheet({required this.actions, required this.onChanged});

  @override
  State<_LedgerHistorySheet> createState() => _LedgerHistorySheetState();
}

class _LedgerHistorySheetState extends State<_LedgerHistorySheet> {
  late Future<NafaqahLedger> _future;
  String? _reversing;

  @override
  void initState() {
    super.initState();
    _future = widget.actions.ledger();
  }

  Future<void> _reverse(NafaqahLedgerEntry e) async {
    final account = repaymentAccountName(context, e.accountId) ?? context.tr('repay_history_from_account');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReverseConfirmDialog(
        body: ctx.trArgs('rev_confirm_body', {'amount': ctx.sar(e.amount), 'account': account}),
        title: ctx.tr('rev_confirm_title'),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _reversing = e.id);
    final requestKey = const Uuid().v4();
    final sources = RepaymentSources.of(context, widget.actions.householdId, listen: false);
    try {
      await widget.actions.reverseRepayment(reimbursementId: e.id, requestKey: requestKey);
    } catch (err) {
      logFailure('FamilyReimbursement.reverse', err);
      if (!mounted) return;
      setState(() => _reversing = null);
      AppSnackBar.showError(
        context,
        _isUnknownOutcome(err)
            ? context.tr('fmd_unconfirmed_msg')
            : trackedRepaymentErrorText(context, err) ??
                (err is NafaqahApiException && err.code == 'forbidden' ? context.tr('nafaqah_err_forbidden') : context.tr('settle_record_failed_msg')),
        title: context.tr('settle_record_failed'),
      );
      setState(() {
        _future = widget.actions.ledger();
      });
      widget.onChanged();
      return;
    }
    // The money is back in its account: the balances show it now.
    sources.provider?.refresh(force: true);
    if (!mounted) return;
    AppSnackBar.showSuccess(context, context.trArgs('rev_done', {'amount': context.sar(e.amount)}), icon: Icons.check_circle_outline);
    setState(() {
      _reversing = null;
      _future = widget.actions.ledger();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            context.tr('nafaqah_history_title'),
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<NafaqahLedger>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText)),
                  );
                }
                if (snap.hasError) {
                  return Text(
                    context.tr('load_error_generic'),
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
                    final color = e.isAdvance || e.isReversal ? context.goldText : context.successText;
                    final title = e.isAdvance
                        ? context.trArgs('nafaqah_history_advance', {'merchant': e.merchant ?? context.tr('merchant_generic')})
                        : e.isReversal
                            ? context.tr('rev_entry')
                            : context.trArgs('nafaqah_history_reimbursement', {'method': _methodLabel(context, e.paymentMethod)});
                    final source = e.isAdvance
                        ? null
                        : repaymentSourceLine(context, movedBalance: e.movedBalance, accountId: e.accountId, reversal: e.isReversal);
                    final details = [
                      if (source != null) source,
                      if (e.timestamp != null) l10n.date(e.timestamp!, 'd MMM yyyy'),
                    ];
                    // What is owed: an advance or a reversal adds, a repayment takes away.
                    final sign = e.isAdvance || e.isReversal ? '+' : '−';
                    return _HistoryEntry(
                      icon: e.isAdvance
                          ? Icons.north_east_rounded
                          : e.isReversal
                              ? Icons.undo_rounded
                              : Icons.south_west_rounded,
                      color: color,
                      title: title,
                      details: details.join(' · '),
                      amount: '$sign${context.sar(e.amount)}',
                      reversedBadge: e.reversed
                          ? _StatusBadge(
                              key: ValueKey('rev_badge_${e.id}'),
                              color: context.textSecondary,
                              icon: Icons.undo_rounded,
                              label: context.tr('rev_badge'),
                            )
                          : null,
                      action: e.canReverse && !e.reversed
                          ? TextButton.icon(
                              key: ValueKey('rev_action_${e.id}'),
                              style: TextButton.styleFrom(foregroundColor: context.accentText),
                              onPressed: _reversing == null ? () => _reverse(e) : null,
                              icon: const Icon(Icons.undo_rounded, size: 16),
                              label: Text(context.tr('rev_action')),
                            )
                          : null,
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

/// One line of a history: what, where from and when, the amount, and for a
/// repayment its "Reversed" badge or Reverse action. Stacks at large text.
class _HistoryEntry extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String details;
  final String amount;
  final Widget? reversedBadge;
  final Widget? action;

  const _HistoryEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.details,
    required this.amount,
    this.reversedBadge,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final large = isLargeText(context);
    final amountText = Text(amount, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w700));
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
                Text(title, style: TextStyle(color: context.textPrimary, fontSize: 13)),
                if (large) amountText,
                if (details.isNotEmpty) Text(details, style: TextStyle(color: context.textSecondary, fontSize: 11)),
                if (reversedBadge != null) ...[const SizedBox(height: 4), reversedBadge!],
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

/// Asks before a reversal: it returns the money and adds the amount back to what is owed.
class _ReverseConfirmDialog extends StatelessWidget {
  final String title;
  final String body;

  const _ReverseConfirmDialog({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: context.cardBg,
      title: Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      content: Text(body, key: const ValueKey('rev_confirm_body'), style: TextStyle(color: context.textPrimary)),
      actions: [
        TextButton(
          key: const ValueKey('rev_confirm_cancel'),
          style: TextButton.styleFrom(foregroundColor: context.textSecondary),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          key: const ValueKey('rev_confirm_ok'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemes.champagneGold,
            foregroundColor: VelvetBurgundyColors.primaryLight,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.tr('rev_action')),
        ),
      ],
    );
  }
}

// ── Record a repayment (the husband or an admin) ────────────────────────────

class _ReimburseBottomSheet extends StatefulWidget {
  final String householdId;
  final double totalOwed;
  final _LedgerActions actions;
  final VoidCallback onConfirmed;

  const _ReimburseBottomSheet({
    required this.householdId,
    required this.totalOwed,
    required this.actions,
    required this.onConfirmed,
  });

  @override
  State<_ReimburseBottomSheet> createState() => _ReimburseBottomSheetState();
}

class _ReimburseBottomSheetState extends State<_ReimburseBottomSheet> {
  late TextEditingController _amountCtrl;
  String _paymentMethod = 'stc_pay';
  bool _isSubmitting = false;

  /// The account it is paid from; null until chosen.
  String? _source;

  /// One key per opening of the sheet, reused by every retry from it.
  late final String _requestKey;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.totalOwed.toStringAsFixed(2));
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

  Future<void> _submit() async {
    final rounded = roundedMoneyTextIfRounded(_amountCtrl.text);
    if (rounded != null) setState(() => _amountCtrl.text = rounded); // show what is stored
    final amt = parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0;
    if (amt <= 0) {
      AppSnackBar.showError(context, context.tr('settle_invalid_amount'));
      return;
    }
    // Paying back more than is owed would invent a debt for the wife.
    if (_halalas(amt) > _halalas(widget.totalOwed)) {
      AppSnackBar.showError(
        context,
        context.trArgs('nafaqah_err_overpayment', {'amount': context.sar(widget.totalOwed)}),
        title: context.tr('settle_record_failed'),
      );
      return;
    }

    // Where the money comes from (rule 02): every repayment leaves an account.
    final sources = RepaymentSources.of(context, widget.householdId, listen: false);
    final account = _chosenAccount(context, sources, _source, amt, onStale: () => setState(() => _source = null));
    if (account == null) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.actions.recordRepayment(
        amount: amt,
        paymentMethod: _paymentMethod,
        accountId: account.id,
        requestKey: _requestKey,
      );
    } catch (e) {
      // Never report a repayment as recorded when the server rejected it.
      logFailure('FamilyReimbursement.record', e);
      if (!mounted) return;
      // It may be stored. A retry from this sheet sends the same key, which the
      // server records once; the card reloads to show what is stored.
      if (e is NafaqahApiException && e.outcomeUnknown) {
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
      final String message;
      final tracked = trackedRepaymentErrorText(context, e, owedNow: widget.totalOwed);
      if (e is NafaqahApiException && repaymentAccountErrorKey(e.code) != null) {
        // The balance or the account changed since the sheet opened.
        sources.provider?.refresh(force: true);
        message = tracked!;
      } else if (tracked != null) {
        message = tracked;
      } else if (e is NafaqahApiException && e.code == 'overpayment') {
        message = context.trArgs('nafaqah_err_overpayment', {'amount': context.sar(e.outstanding ?? widget.totalOwed)});
      } else if (e is NafaqahApiException && e.code == 'forbidden') {
        message = context.tr('nafaqah_err_forbidden');
      } else if (e is NafaqahApiException && e.code == 'no_wife') {
        message = context.tr('nafaqah_err_no_wife');
      } else if (e is NafaqahApiException && e.code == 'invalid') {
        message = context.tr('nafaqah_err_invalid_amount');
      } else if (nafaqahWriteRefusalOf(e) != null) {
        message = nafaqahWriteRefusalText(context, nafaqahWriteRefusalOf(e)!);
      } else {
        message = context.tr('settle_record_failed_msg');
      }
      AppSnackBar.showError(context, message, title: context.tr('settle_record_failed'));
      return;
    }

    // His balance changed on the server: the accounts show it now.
    sources.provider?.refresh(force: true);
    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      context.trArgs('repay_paid_from', {'amount': context.sar(amt), 'account': account.name}),
      title: context.tr('settle_recorded_title'),
      icon: Icons.check_circle_outline,
    );
    Navigator.of(context).pop();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.totalOwed.toStringAsFixed(2);
    // The fill is fixed rose gold in both modes, so one ink works for both.
    const onGold = VelvetBurgundyColors.primaryLight;
    final sources = RepaymentSources.of(context, widget.householdId);
    return _SheetFrame(
      children: [
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
        _MethodChips(selected: _paymentMethod, onChanged: (m) => setState(() => _paymentMethod = m)),
        const SizedBox(height: 16),
        if (!sources.loaded)
          Center(child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText))
        else
          RepaymentAccountPicker(
            householdId: widget.householdId,
            accounts: sources.accounts,
            selected: _source,
            amount: parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0,
            onChanged: (id) => setState(() => _source = id),
          ),
        const SizedBox(height: 16),
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
              foregroundColor: onGold,
              disabledBackgroundColor: AppThemes.champagneGold,
              disabledForegroundColor: onGold,
              padding: const EdgeInsets.symmetric(vertical: 14),
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
              context.tr('settle_record_payment'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _isSubmitting ? null : _submit,
          ),
        ),
      ],
    );
  }
}
