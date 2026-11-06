/// Islamic family Nafaqah models (family mode = married couple).
///
/// Owner rules (see `.agents/rules/02-saudi-fintech-and-islamic-compliance.md`):
/// 1. Shared family expenses are the husband's Nafaqah: never split between
///    the spouses (no 50/50 or any percentage).
/// 2. The wife paying from her own money for something shared is a debt the
///    husband owes her ([kWifeReimbursable]); reimbursements reduce it.
/// 3. A personal purchase by the wife is charged to her per-cycle allowance
///    ([kWifePersonal]); overspend shows as a negative remainder.
/// 4. Whatever the husband pays is an ordinary household expense (no class).
library;

import 'dart:math' as math;

const String kWifeReimbursable = 'wife_reimbursable';
const String kWifePersonal = 'wife_personal';

double _num(Object? v) => (v as num?)?.toDouble() ?? 0.0;

/// Nafaqah class of an expense from the recorder's point of view (mirrors
/// `nafaqah_service.classify_nafaqah`). `paidBy`/`beneficiary` use the app's
/// relative vocabulary: 'me' is the recorder, 'partner' the other spouse.
/// Only an expense the wife paid from her own money gets a class.
String? classifyNafaqah(String? recorderRole, String paidBy, String beneficiary) {
  final role = (recorderRole ?? '').toLowerCase();
  final pb = paidBy.trim().toLowerCase();
  final ben = beneficiary.trim().toLowerCase();
  const wifeAliases = {'wife', 'spouse'};
  final bool wifePaid;
  final bool forWife;
  if (role == 'wife') {
    wifePaid = pb == 'me' || wifeAliases.contains(pb);
    forWife = ben == 'me' || wifeAliases.contains(ben);
  } else if (role == 'husband') {
    wifePaid = pb == 'partner' || wifeAliases.contains(pb);
    forWife = ben == 'partner' || wifeAliases.contains(ben);
  } else {
    return null;
  }
  if (!wifePaid) return null;
  return forWife ? kWifePersonal : kWifeReimbursable;
}

/// What the expense endpoints take for "no class": the husband paid (rule 4).
const String kNafaqahNone = 'none';

/// Recorder-relative `paid_by` / `beneficiary` that express a Nafaqah choice
/// (mirrors `nafaqah_service.attribution_for_class`), so the server never sees
/// a class that contradicts who paid for whom. `null` = the husband paid.
({String paidBy, String beneficiary}) nafaqahAttribution(String? recorderRole, String? nafaqahClass) {
  final isWife = (recorderRole ?? '').toLowerCase() == 'wife';
  final wifeSide = isWife ? 'me' : 'partner';
  final husbandSide = isWife ? 'partner' : 'me';
  switch (nafaqahClass) {
    case kWifePersonal:
      return (paidBy: wifeSide, beneficiary: wifeSide);
    case kWifeReimbursable:
      return (paidBy: wifeSide, beneficiary: 'both');
    default:
      return (paidBy: husbandSide, beneficiary: 'both');
  }
}

/// Family-mode context of an expense preview from `/agent/chat-transaction`
/// or `/agent/scan-receipt` (`household_mode`, `recorder_role`,
/// `nafaqah_class`, `nafaqah_spouse_id`, `wives`).
class NafaqahPreview {
  final bool isFamily;
  final String? recorderRole; // 'wife' | 'husband' | 'member'
  final String? suggestedClass;
  final String? suggestedSpouseId;
  final List<NafaqahWife> wives;

  /// The husband's (provider's) display name when known, so a family entry
  /// says "Ahmed paid" instead of "the husband" (UX-03). Optional: the chat
  /// and receipt previews may not carry it.
  final String? husbandName;

  /// The recorder is a household admin. Owner rule: only the wife, the
  /// Nafaqah provider (husband) or an admin may classify a family expense as
  /// wife_reimbursable / wife_personal.
  final bool callerIsAdmin;

  const NafaqahPreview({
    this.isFamily = false,
    this.recorderRole,
    this.suggestedClass,
    this.suggestedSpouseId,
    this.wives = const [],
    this.callerIsAdmin = false,
    this.husbandName,
  });

  bool get _isSpouse => recorderRole == 'wife' || recorderRole == 'husband';

  /// Only the wife, the husband (provider) or an admin records a Nafaqah class.
  bool get canClassify => isFamily && (_isSpouse || callerIsAdmin || recorderRole == null);

  /// An admin who is neither spouse: classifies on the wife's behalf, naming her.
  bool get isAdminClassifier => canClassify && !_isSpouse;

  bool get viewerIsWife => recorderRole == 'wife';

  /// 'wife', 'husband' or 'admin': whose point of view the Nafaqah question takes.
  String get viewerRole => viewerIsWife ? 'wife' : (recorderRole == 'husband' ? 'husband' : 'admin');

  /// The display name of the wife [wifeId] names (else the only wife), or null.
  String? wifeNameFor(String? wifeId) {
    NafaqahWife? wife;
    for (final w in wives) {
      if (wifeId != null && w.id == wifeId) wife = w;
    }
    wife ??= wives.length == 1 ? wives.first : null;
    final name = (wife?.displayName ?? '').trim();
    return name.isEmpty ? null : name;
  }

  /// The husband (or an admin) in a family with several wives says which wife paid.
  bool get needsWifeChoice => canClassify && !viewerIsWife && wives.length > 1;

  /// The wife preselected for the husband or an admin (the only one, or the server's pick).
  String? get defaultSpouseId {
    if (!canClassify || viewerIsWife) return null;
    if (wives.length == 1) return wives.first.id;
    return suggestedSpouseId;
  }

  /// The same context with the viewer's admin flag (the preview of
  /// `/agent/chat-transaction` and `/agent/scan-receipt` may not carry it).
  NafaqahPreview withAdmin(bool isAdmin) => NafaqahPreview(
        isFamily: isFamily,
        recorderRole: recorderRole,
        suggestedClass: suggestedClass,
        suggestedSpouseId: suggestedSpouseId,
        wives: wives,
        callerIsAdmin: callerIsAdmin || isAdmin,
        husbandName: husbandName,
      );

  /// Fields for `/agent/scan-receipt` or `/agent/chat-transaction`: who paid
  /// for whom and the confirmed class, consistent with each other (empty
  /// outside family mode). A wife never names a spouse: she is the spouse.
  Map<String, String> requestFields(String? nafaqahClass, {String? chosenWifeId}) {
    if (!canClassify) return const {};
    if (isAdminClassifier) {
      // An admin who is neither spouse: no class leaves the attribution as
      // entered; a class names the wife who paid ('partner' resolved by the
      // server with nafaqah_spouse_id).
      if (nafaqahClass == null) return const {'nafaqah_class': kNafaqahNone};
      return {
        'paid_by': 'partner',
        'beneficiary': nafaqahClass == kWifePersonal ? 'partner' : 'both',
        'nafaqah_class': nafaqahClass,
        if (chosenWifeId != null && chosenWifeId.isNotEmpty) 'nafaqah_spouse_id': chosenWifeId,
      };
    }
    final attribution = nafaqahAttribution(recorderRole, nafaqahClass);
    final spouse = viewerIsWife || nafaqahClass == null ? null : chosenWifeId;
    return {
      'paid_by': attribution.paidBy,
      'beneficiary': attribution.beneficiary,
      'nafaqah_class': nafaqahClass ?? kNafaqahNone,
      if (spouse != null && spouse.isNotEmpty) 'nafaqah_spouse_id': spouse,
    };
  }

  /// `nafaqah_class` / `nafaqah_spouse_id` for a direct `transactions` insert
  /// (the database requires both together; empty when there is no class).
  Map<String, String> transactionColumns(String? nafaqahClass, {String? chosenWifeId, String? currentUserId}) {
    if (!canClassify || nafaqahClass == null) return const {};
    final spouse = viewerIsWife ? currentUserId : chosenWifeId;
    if (spouse == null || spouse.isEmpty) return const {};
    return {'nafaqah_class': nafaqahClass, 'nafaqah_spouse_id': spouse};
  }

  /// Where nothing is previewed (the multi-page scanner saves directly): the
  /// caller's role from `GET /households/{id}/nafaqah`. The suggestion mirrors
  /// the server default (the recorder paid for the household).
  factory NafaqahPreview.fromSummary(NafaqahSummary summary) {
    if (!summary.isFamily) return const NafaqahPreview();
    final role = summary.callerRole;
    return NafaqahPreview(
      isFamily: true,
      recorderRole: role,
      suggestedClass: role == 'wife' ? kWifeReimbursable : null,
      // The wives the caller may name (review R3-01: a wife herself only).
      wives: summary.wifeRoster,
      // `can_set_provider` is true for household admins.
      callerIsAdmin: summary.canSetProvider,
      husbandName: summary.husbandName,
    );
  }

  factory NafaqahPreview.fromPreview(Map<String, dynamic>? data) {
    if (data == null || data['household_mode'] != 'family_nafaqah') return const NafaqahPreview();
    final cls = data['nafaqah_class'] as String?;
    final spouseId = (data['nafaqah_spouse_id'] ?? data['default_spouse_id']) as String?;
    return NafaqahPreview(
      isFamily: true,
      recorderRole: data['recorder_role'] as String?,
      suggestedClass: (cls == kWifeReimbursable || cls == kWifePersonal) ? cls : null,
      suggestedSpouseId: spouseId,
      callerIsAdmin: data['caller_is_admin'] == true || data['can_classify'] == true,
      husbandName: (data['husband'] is Map ? (data['husband'] as Map)['display_name'] : data['husband_name']) as String?,
      wives: (data['wives'] as List? ?? const [])
          .whereType<Map>()
          .map((w) => NafaqahWife.fromMap(Map<String, dynamic>.from(w)))
          .where((w) => w.id.isNotEmpty)
          .toList(),
    );
  }
}

/// What the husband owes his wife for her advances (rule 2).
class ReimbursementBalance {
  final double grossAdvanced;
  final double reimbursed;
  final double outstanding;

  /// Repaid more than advanced (an advance was cut or removed after a
  /// repayment, before the ledger guard existed). Never negative.
  final double overpaid;

  /// Her requests awaiting approval: shown, never subtracted from [outstanding].
  final double pendingRequested;
  final int pendingCount;

  const ReimbursementBalance({
    this.grossAdvanced = 0.0,
    this.reimbursed = 0.0,
    this.outstanding = 0.0,
    this.overpaid = 0.0,
    this.pendingRequested = 0.0,
    this.pendingCount = 0,
  });

  bool get isSettled => outstanding < 0.005;

  bool get isOverpaid => overpaid >= 0.005;

  factory ReimbursementBalance.fromMap(Map<String, dynamic> map) => ReimbursementBalance(
        grossAdvanced: _num(map['gross_advanced']),
        reimbursed: _num(map['reimbursed']),
        outstanding: _num(map['outstanding']),
        overpaid: _num(map['overpaid']),
        pendingRequested: _num(map['pending_requested']),
        pendingCount: (map['pending_count'] as num?)?.toInt() ?? 0,
      );
}

/// The wife's personal allowance (مصروفها) for one salary cycle (rule 3).
class AllowanceStatus {
  final String cycleKey;
  final bool isSet;
  final double allocated;
  final double spent;
  final double remaining;
  final int transactionCount;

  const AllowanceStatus({
    this.cycleKey = '',
    this.isSet = false,
    this.allocated = 0.0,
    this.spent = 0.0,
    this.remaining = 0.0,
    this.transactionCount = 0,
  });

  /// An allowance was set for the cycle. A working wife may have none: her
  /// personal purchases are then shown as plain spending, never "overspent".
  bool get hasAllowance => isSet || allocated > 0;

  bool get isOverspent => hasAllowance && remaining < 0;

  /// Share of the allowance used, clamped to [0, 1] for progress bars.
  double get usedFraction {
    if (allocated <= 0) return spent > 0 ? 1.0 : 0.0;
    return (spent / allocated).clamp(0.0, 1.0);
  }

  factory AllowanceStatus.fromMap(Map<String, dynamic> map) => AllowanceStatus(
        cycleKey: map['cycle_key'] as String? ?? '',
        isSet: map['is_set'] as bool? ?? false,
        allocated: _num(map['allocated']),
        spent: _num(map['spent']),
        remaining: _num(map['remaining']),
        transactionCount: (map['transaction_count'] as num?)?.toInt() ?? 0,
      );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// The wife has scheduled her account's deletion while the husband still owes
/// her. Sent only to the creditor (the husband, or the admins of a family with
/// no provider), so he can settle before the purge keeps an anonymised record.
class NafaqahPendingDeletion {
  final DateTime scheduledFor;
  final double outstanding;

  const NafaqahPendingDeletion({required this.scheduledFor, required this.outstanding});

  /// Null for anything but a map with a readable date: no date, no notice.
  static NafaqahPendingDeletion? fromValue(Object? value) {
    if (value is! Map) return null;
    final when = _date(value['scheduled_for']);
    if (when == null) return null;
    return NafaqahPendingDeletion(scheduledFor: when, outstanding: _num(value['outstanding']));
  }
}

const String kRequestPending = 'pending';
const String kRequestApproved = 'approved';
const String kRequestDeclined = 'declined';
const String kRequestCancelled = 'cancelled';
const String kRequestClosed = 'closed';

/// Closed because what is owed dropped below it (a repayment, an approval or a
/// smaller advance, review R1-03); nothing moved for it.
const String kRequestAlreadyRepaid = 'already_repaid';

/// The wife's "I received X" (migration 20261105001300): pending until the
/// husband or an admin approves it (a repayment from his account) or declines
/// it, or she cancels it, or an account deletion closes it. A pending request
/// moves no money and lowers nothing owed.
class ReimbursementRequest {
  final String id;
  final double amount;
  final String? paymentMethod;

  /// [kRequestPending], [kRequestApproved], [kRequestDeclined],
  /// [kRequestCancelled], [kRequestClosed] or [kRequestAlreadyRepaid].
  final String status;

  /// Only a decline carries one, and only if he gave it.
  final String? reason;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  /// The wife account she said it went into (the approval credits it unless
  /// her husband picks another of hers).
  final String? wifeAccountId;

  const ReimbursementRequest({
    required this.id,
    required this.amount,
    this.paymentMethod,
    this.status = kRequestPending,
    this.reason,
    this.createdAt,
    this.decidedAt,
    this.wifeAccountId,
  });

  bool get isPending => status == kRequestPending;

  factory ReimbursementRequest.fromMap(Map<String, dynamic> map) => ReimbursementRequest(
        id: map['id']?.toString() ?? '',
        amount: _num(map['amount']),
        paymentMethod: map['payment_method'] as String?,
        status: map['status']?.toString() ?? kRequestPending,
        reason: (map['reason'] as String?)?.trim().isEmpty ?? true ? null : (map['reason'] as String).trim(),
        createdAt: _date(map['created_at']),
        decidedAt: _date(map['decided_at']),
        wifeAccountId: map['wife_account_id']?.toString(),
      );

  static List<ReimbursementRequest> listFrom(Object? raw) => (raw is List ? raw : const [])
      .whereType<Map>()
      .map((r) => ReimbursementRequest.fromMap(Map<String, dynamic>.from(r)))
      .where((r) => r.id.isNotEmpty)
      .toList();
}

class NafaqahWife {
  final String id;
  final String? displayName;
  final ReimbursementBalance reimbursement;
  final AllowanceStatus allowance;
  final NafaqahPendingDeletion? pendingDeletion;

  /// Her requests and their outcomes, newest first.
  final List<ReimbursementRequest> requests;

  /// The viewer is this wife and may ask; null from a server that does not say.
  final bool? canRequest;

  /// The viewer is the husband or an admin (never this wife) and may record,
  /// approve, decline and reverse; null from a server that does not say.
  final bool? canDecide;

  const NafaqahWife({
    required this.id,
    this.displayName,
    this.reimbursement = const ReimbursementBalance(),
    this.allowance = const AllowanceStatus(),
    this.pendingDeletion,
    this.requests = const [],
    this.canRequest,
    this.canDecide,
  });

  List<ReimbursementRequest> get pendingRequests => requests.where((r) => r.isPending).toList();

  factory NafaqahWife.fromMap(Map<String, dynamic> map) => NafaqahWife(
        id: map['id'] as String? ?? '',
        displayName: map['display_name'] as String?,
        reimbursement: ReimbursementBalance.fromMap(
          Map<String, dynamic>.from(map['reimbursement'] as Map? ?? const {}),
        ),
        allowance: AllowanceStatus.fromMap(
          Map<String, dynamic>.from(map['allowance'] as Map? ?? const {}),
        ),
        pendingDeletion: NafaqahPendingDeletion.fromValue(map['pending_deletion']),
        requests: ReimbursementRequest.listFrom(map['requests']),
        canRequest: map['can_request'] as bool?,
        canDecide: map['can_decide'] as bool?,
      );
}

const String kFormerMemberDebtOpen = 'open';
const String kFormerMemberDebtSettled = 'settled';
const String kFormerMemberDebtWaived = 'waived';

/// One step that reduced a former member's record: a payment, or her waiver
/// (إبراء) of what remained, in which no money moved.
class FormerMemberDebtEvent {
  /// Empty from a server that does not send it (no reverse action then).
  final String id;
  final String kind; // 'payment' | 'waiver' | 'reversal'
  final double amount;
  final String? paymentMethod;
  final double remainingAfter;
  final DateTime? createdAt;

  /// Whether it moved money in an account in the app (migration
  /// 20261105001300), and which: the account a payment left, or the one a
  /// reversal returned it to; null from a server that does not say.
  final bool? movedBalance;
  final String? accountId;

  /// A payment that a later reversal undid (it stays, marked reversed).
  final bool reversed;

  /// The viewer may reverse this payment now (the server decides).
  final bool canReverse;

  const FormerMemberDebtEvent({
    required this.kind,
    required this.amount,
    this.id = '',
    this.paymentMethod,
    this.remainingAfter = 0.0,
    this.createdAt,
    this.movedBalance,
    this.accountId,
    this.reversed = false,
    this.canReverse = false,
  });

  bool get isWaiver => kind == 'waiver';
  bool get isReversal => kind == 'reversal';

  factory FormerMemberDebtEvent.fromMap(Map<String, dynamic> map) => FormerMemberDebtEvent(
        id: map['id']?.toString() ?? '',
        kind: map['kind']?.toString() ?? 'payment',
        amount: _num(map['amount']),
        paymentMethod: map['payment_method'] as String?,
        remainingAfter: _num(map['remaining_after']),
        createdAt: _date(map['created_at']),
        movedBalance: map['moved_balance'] as bool?,
        accountId: map['account_id']?.toString(),
        reversed: map['reversed'] == true,
        canReverse: map['can_reverse'] == true && (map['id']?.toString() ?? '').isNotEmpty,
      );
}

/// What a wife who deleted her account was still owed, kept by the household
/// without her name (one record per household). The husband or an admin
/// closes it by payments or by recording her waiver; it then stays in history.
class FormerMemberDebt {
  final String id;
  final double originalAmount;
  final double paidAmount;
  final double remaining;

  /// 'open' | 'settled' | 'waived'. Anything else is shown but offers no action.
  final String status;
  final DateTime? createdAt;
  final DateTime? closedAt;

  /// Oldest first.
  final List<FormerMemberDebtEvent> events;

  const FormerMemberDebt({
    required this.id,
    this.originalAmount = 0.0,
    this.paidAmount = 0.0,
    this.remaining = 0.0,
    this.status = '',
    this.createdAt,
    this.closedAt,
    this.events = const [],
  });

  bool get isOpen => status == kFormerMemberDebtOpen;
  bool get isSettled => status == kFormerMemberDebtSettled;
  bool get isWaived => status == kFormerMemberDebtWaived;

  /// What her waiver released (no money moved for it).
  double get waivedAmount => events.where((e) => e.isWaiver).fold(0.0, (sum, e) => sum + e.amount);

  factory FormerMemberDebt.fromMap(Map<String, dynamic> map) {
    final original = _num(map['original_amount']);
    final paid = _num(map['paid_amount']);
    final rawEvents = map['events'];
    return FormerMemberDebt(
      id: map['id']?.toString() ?? '',
      originalAmount: original,
      paidAmount: paid,
      remaining: map['remaining'] is num
          ? _num(map['remaining'])
          : math.max(0, ((original - paid) * 100).round()) / 100,
      status: map['status']?.toString() ?? '',
      createdAt: _date(map['created_at']),
      closedAt: _date(map['closed_at']),
      events: (rawEvents is List ? rawEvents : const [])
          .whereType<Map>()
          .map((e) => FormerMemberDebtEvent.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// The answer to a payment or a waiver of a former member's record.
/// [replayed]: the server had already recorded this request key.
class FormerMemberDebtReceipt {
  final String? status;
  final bool replayed;
  final String? debtId;
  final String? eventId;

  /// The payment, or for a waiver what it released.
  final double amount;
  final String? paymentMethod;
  final double remaining;

  /// The account the payment came out of; null when not tracked in the app.
  final String? accountId;

  const FormerMemberDebtReceipt({
    this.status,
    this.replayed = false,
    this.debtId,
    this.eventId,
    this.amount = 0.0,
    this.paymentMethod,
    this.remaining = 0.0,
    this.accountId,
  });

  factory FormerMemberDebtReceipt.fromMap(Map<String, dynamic> map) => FormerMemberDebtReceipt(
        status: map['status'] as String?,
        replayed: map['replayed'] == true,
        debtId: map['debt_id']?.toString(),
        eventId: map['event_id']?.toString(),
        amount: _num(map['amount'] ?? map['waived_amount']),
        paymentMethod: map['payment_method'] as String?,
        remaining: _num(map['remaining']),
        accountId: map['account_id']?.toString(),
      );
}

/// `GET /households/{id}/nafaqah` from the caller's point of view.
class NafaqahSummary {
  final String mode; // 'family_nafaqah' | 'not_family'
  final String? callerRole; // 'husband' | 'wife' | 'member'
  final String? callerUserId;
  final String? cycleKey;
  final String? husbandId;
  final String? husbandName;
  final List<NafaqahWife> wives;
  final bool canSetAllowance;
  final bool canRecordReimbursement;

  /// `households.nafaqah_provider_user_id` (the husband), as stored.
  final String? providerUserId;

  /// A family without a valid provider: classified expenses are refused until
  /// a household admin chooses one.
  final bool needsProvider;

  /// The caller is a household admin and may choose the provider.
  final bool canSetProvider;

  /// 'family' | 'roommates' (`household_type`), when the server sends it.
  final String? householdType;

  /// Wives whose allowance the caller sets but whose repayment ledger the
  /// caller does not read (an admin while the husband is there, review
  /// R3-01): only their allowance.
  final List<NafaqahWife> allowanceWives;

  /// What deleted wives were still owed, newest first: sent only to whoever
  /// manages them (her husband; an admin who is not a wife once he is gone).
  final List<FormerMemberDebt> formerMemberDebts;

  /// The caller (the husband/provider or an admin who is not a wife) may
  /// record payments or a waiver. Never a wife, whatever the server says
  /// (review R1-01).
  final bool canManageFormerMemberDebts;

  const NafaqahSummary({
    this.mode = 'not_family',
    this.callerRole,
    this.callerUserId,
    this.cycleKey,
    this.husbandId,
    this.husbandName,
    this.wives = const [],
    this.canSetAllowance = false,
    this.canRecordReimbursement = false,
    this.providerUserId,
    this.needsProvider = false,
    this.canSetProvider = false,
    this.householdType,
    this.allowanceWives = const [],
    this.formerMemberDebts = const [],
    this.canManageFormerMemberDebts = false,
  });

  bool get isFamily => mode == 'family_nafaqah' || householdType == 'family' || wives.isNotEmpty;
  bool get callerIsWife => callerRole == 'wife';

  /// Whether the caller reads [wife]'s repayment ledger (review R3-01): she
  /// herself, or whoever settles it (her husband; an admin who is not a wife
  /// once he is gone). The server sends no other entry; the app shows none,
  /// whatever a server sends.
  bool canSeeLedgerOf(NafaqahWife wife) =>
      callerIsWife ? wife.id == callerUserId : (callerRole == 'husband' || canDecideFor(wife));

  /// The wives whose ledger the card shows: a wife her own entry only.
  List<NafaqahWife> get visibleWives => wives.where(canSeeLedgerOf).toList();

  /// The viewer is [wife] herself: she marks what she received (a request).
  bool canRequestFor(NafaqahWife wife) => wife.canRequest ?? (callerIsWife && callerUserId == wife.id);

  /// The viewer is the husband or an admin who is not a wife: records,
  /// approves and declines repayments to [wife]. Never a wife, not even a
  /// co-wife who is an admin, whatever the server says (review R1-01).
  bool canDecideFor(NafaqahWife wife) => !callerIsWife && (wife.canDecide ?? canRecordReimbursement);

  /// Whether the caller reads [wife]'s personal allowance (owner decision
  /// 2026-11-06): she herself, her husband, or an admin who is not a wife.
  /// Among those who are not wives, the ones who read it are exactly the ones
  /// who set it, so `can_set_allowance` stands for the admin. Never a co-wife,
  /// even an admin, and never an ordinary member, whatever a server sends.
  bool canSeeAllowanceOf(NafaqahWife wife) =>
      callerIsWife ? wife.id == callerUserId : (callerRole == 'husband' || canSetAllowance);

  /// Whether the caller may change [wife]'s allowance: the husband or an
  /// admin who is not a wife; never a wife, for herself or a co-wife.
  bool canSetAllowanceFor(NafaqahWife wife) =>
      canSetAllowance && !callerIsWife && wife.id != callerUserId;

  /// The allowance figure the dashboard names, for [primaryWife]: only when
  /// the caller reads it.
  double? get primaryWifeAllowance {
    final wife = primaryWife;
    return wife != null && canSeeAllowanceOf(wife) ? wife.allowance.allocated : null;
  }

  /// Every wife the caller may name (classifying an expense, her allowance):
  /// the wives the server sent, in either list. Who a wife is is not her
  /// ledger; a wife still names only herself (review R3-01).
  List<NafaqahWife> get wifeRoster {
    if (callerIsWife) return wives.where((w) => w.id == callerUserId).toList();
    final ids = {for (final w in wives) w.id};
    return [...wives, for (final w in allowanceWives) if (!ids.contains(w.id)) w];
  }

  /// The wife the caller is concerned with: herself (never a co-wife), or the
  /// first wife the caller may name.
  NafaqahWife? get primaryWife {
    final roster = wifeRoster;
    if (callerIsWife) {
      for (final w in roster) {
        if (w.id == callerUserId) return w;
      }
      return null;
    }
    return roster.isEmpty ? null : roster.first;
  }

  factory NafaqahSummary.fromMap(Map<String, dynamic> map) {
    final husband = map['husband'] is Map ? Map<String, dynamic>.from(map['husband'] as Map) : null;
    return NafaqahSummary(
      mode: map['mode'] as String? ?? 'not_family',
      callerRole: map['caller_role'] as String?,
      callerUserId: map['caller_user_id'] as String?,
      cycleKey: map['cycle_key'] as String?,
      husbandId: husband?['id'] as String?,
      husbandName: husband?['display_name'] as String?,
      wives: (map['wives'] as List? ?? const [])
          .whereType<Map>()
          .map((w) => NafaqahWife.fromMap(Map<String, dynamic>.from(w)))
          .toList(),
      canSetAllowance: map['can_set_allowance'] as bool? ?? false,
      canRecordReimbursement: map['can_record_reimbursement'] as bool? ?? false,
      providerUserId: map['provider_user_id'] as String?,
      needsProvider: map['needs_provider'] as bool? ?? false,
      canSetProvider: map['can_set_provider'] as bool? ?? false,
      householdType: map['household_type'] as String?,
      allowanceWives: (map['allowance_wives'] as List? ?? const [])
          .whereType<Map>()
          .map((w) => NafaqahWife.fromMap(Map<String, dynamic>.from(w)))
          .where((w) => w.id.isNotEmpty)
          .toList(),
      formerMemberDebts: (map['former_member_debts'] is List ? map['former_member_debts'] as List : const [])
          .whereType<Map>()
          .map((d) => FormerMemberDebt.fromMap(Map<String, dynamic>.from(d)))
          .where((d) => d.id.isNotEmpty)
          .toList(),
      canManageFormerMemberDebts: map['can_manage_former_member_debts'] == true && map['caller_role'] != 'wife',
    );
  }
}

/// `PUT /households/{id}/nafaqah/provider`: the new provider and the
/// refreshed Nafaqah summary from the caller's point of view.
class NafaqahProviderChange {
  final String? providerUserId;
  final String? previousProviderUserId;
  final NafaqahSummary? summary;

  const NafaqahProviderChange({this.providerUserId, this.previousProviderUserId, this.summary});

  factory NafaqahProviderChange.fromMap(Map<String, dynamic> map) => NafaqahProviderChange(
        providerUserId: map['provider_user_id'] as String?,
        previousProviderUserId: map['previous_provider_user_id'] as String?,
        summary: map['summary'] is Map ? NafaqahSummary.fromMap(Map<String, dynamic>.from(map['summary'] as Map)) : null,
      );
}

/// One line of the wife's ledger: an advance she made, a repayment to her, or
/// the reversal of one.
class NafaqahLedgerEntry {
  final String type; // 'advance' | 'reimbursement'
  final String id;
  final double amount;
  final DateTime? timestamp;
  final String? merchant;
  final String? paymentMethod;
  final String? notes;

  /// A repayment or reversal: whether it moved money in an account in the app
  /// (migration 20261105001300), and which (the account a repayment left, or
  /// the one a reversal returned it to); null from a server that does not say.
  final bool? movedBalance;
  final String? accountId;

  /// The wife account a repayment credited (a reversal: took back from); null
  /// before the wife account (migration 20261105001300, section 12).
  final String? wifeAccountId;

  /// 'payment' or 'reversal' (a repayment's reversing entry).
  final String kind;

  /// A repayment that a later reversal undid: it stays, marked reversed.
  final bool reversed;

  /// The viewer may reverse this repayment now (the server decides).
  final bool canReverse;

  const NafaqahLedgerEntry({
    required this.type,
    required this.id,
    required this.amount,
    this.timestamp,
    this.merchant,
    this.paymentMethod,
    this.notes,
    this.movedBalance,
    this.accountId,
    this.wifeAccountId,
    this.kind = 'payment',
    this.reversed = false,
    this.canReverse = false,
  });

  bool get isAdvance => type == 'advance';
  bool get isReversal => !isAdvance && kind == 'reversal';

  factory NafaqahLedgerEntry.fromMap(Map<String, dynamic> map) => NafaqahLedgerEntry(
        type: map['type'] as String? ?? 'advance',
        id: map['id']?.toString() ?? '',
        amount: _num(map['amount']),
        timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '')?.toLocal(),
        merchant: map['merchant'] as String?,
        paymentMethod: map['payment_method'] as String?,
        notes: map['notes'] as String?,
        movedBalance: map['moved_balance'] as bool?,
        accountId: map['account_id']?.toString(),
        wifeAccountId: map['wife_account_id']?.toString(),
        kind: map['kind']?.toString() ?? 'payment',
        reversed: map['reversed'] == true,
        canReverse: map['can_reverse'] == true,
      );
}

class NafaqahLedger {
  final ReimbursementBalance balance;
  final List<NafaqahLedgerEntry> history;
  final List<ReimbursementRequest> requests;

  const NafaqahLedger({this.balance = const ReimbursementBalance(), this.history = const [], this.requests = const []});

  factory NafaqahLedger.fromMap(Map<String, dynamic> map) => NafaqahLedger(
        balance: ReimbursementBalance.fromMap(Map<String, dynamic>.from(map['balance'] as Map? ?? const {})),
        history: (map['history'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => NafaqahLedgerEntry.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        requests: ReimbursementRequest.listFrom(map['requests']),
      );
}

/// A rejected Nafaqah request. [code] is 'overpayment', 'forbidden',
/// 'not_family', 'ledger_would_be_overpaid' (an edit would leave the wife's
/// ledger repaid beyond her advances), 'no_provider' (the family has no
/// Nafaqah provider yet), 'no_wife' (the family has no wife member, so there
/// is no allowance or reimbursement to record), 'invalid' or 'network'.
/// A former member's record adds 'debt_closed' (already settled or waived),
/// 'debt_not_found' and 'request_key_reused' (the key was used for another
/// request). Tracked repayments (migration 20261105001300) add the account
/// refusals, 'app_update_required' (HTTP 426: this build predates them),
/// 'wife_must_request', the request codes ('request_not_found',
/// 'request_not_pending', 'request_exceeds_outstanding',
/// 'pending_exceeds_outstanding') and the reversal codes
/// ('already_reversed', 'reversal_not_tracked', 'reversal_account_unavailable',
/// 'reversal_after_waiver', 'not_reversible', 'reimbursement_not_found',
/// 'payment_not_found').
/// Every code the Nafaqah API names in `detail.code`. Each one has a
/// localized message (`repaymentErrorText`, review R1-09).
const Set<String> kNafaqahErrorCodes = {
  'overpayment',
  'not_family',
  'ledger_would_be_overpaid',
  'no_provider',
  'no_wife',
  'account_pending_deletion',
  'debt_closed',
  'debt_not_found',
  'request_key_reused',
  // Migration 20261105001300: the account a repayment is paid from,
  // the wife's requests and reversals.
  'account_unavailable',
  'account_forbidden',
  'insufficient_funds',
  'app_update_required',
  'wife_must_request',
  'request_not_found',
  'request_not_pending',
  'request_exceeds_outstanding',
  'pending_exceeds_outstanding',
  'reimbursement_not_found',
  'payment_not_found',
  'not_reversible',
  'already_reversed',
  'reversal_not_tracked',
  'reversal_account_unavailable',
  'reversal_after_waiver',
  'account_required',
  'request_key_required',
  'invalid_reason',
  // Section 12: the wife account.
  'wife_account_required',
  'wife_account_invalid',
  'wife_account_insufficient_funds',
  'wife_account_forbidden',
  'wife_account_has_history',
  'not_a_wife',
  'invalid_name',
  'account_not_found',
};

class NafaqahApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const NafaqahApiException(this.code, this.message, {this.statusCode, this.noResponse = false, this.outstanding});

  /// No answer arrived at all (offline, DNS, timeout).
  final bool noResponse;

  /// With 'overpayment' or 'request_exceeds_outstanding': what the server says
  /// is owed now (`detail.outstanding`). With 'pending_exceeds_outstanding':
  /// what she can still ask for (`detail.available`).
  final double? outstanding;

  /// The request may have taken effect: no answer came back, or the server
  /// failed without saying what it stored. See `ApiRequestException.outcomeUnknown`.
  bool get outcomeUnknown => noResponse || (statusCode ?? 0) >= 500;

  factory NafaqahApiException.fromResponse(Map<String, dynamic> res) {
    final status = (res['status_code'] as num?)?.toInt();
    final detail = res['detail'];
    final detailCode = detail is Map ? detail['code'] as String? : null;
    final message = res['message']?.toString() ?? '';
    final String code;
    if (kNafaqahErrorCodes.contains(detailCode)) {
      code = detailCode!;
    } else if (status == 426) {
      // Upgrade Required: this build predates what the server now asks for.
      code = 'app_update_required';
    } else if (status == 403) {
      code = 'forbidden';
    } else if (status == 422 || status == 400) {
      code = 'invalid';
    } else {
      code = 'network';
    }
    // 'wife_account_insufficient_funds' sends what her account holds as `available`.
    final outstanding = detail is Map ? (detail['outstanding'] ?? detail['available']) : null;
    // `BaseApiClient.networkErrorKey`: a model does not depend on the API layer.
    return NafaqahApiException(
      code,
      message,
      statusCode: status,
      noResponse: res['network_error'] == true,
      outstanding: outstanding is num ? outstanding.toDouble() : double.tryParse('${outstanding ?? ''}'),
    );
  }

  @override
  String toString() => 'NafaqahApiException($code, $statusCode): $message';
}
