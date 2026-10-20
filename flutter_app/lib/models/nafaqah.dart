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

  const NafaqahPreview({
    this.isFamily = false,
    this.recorderRole,
    this.suggestedClass,
    this.suggestedSpouseId,
    this.wives = const [],
  });

  /// Only the husband or a wife records a Nafaqah class.
  bool get canClassify => isFamily && (recorderRole == 'wife' || recorderRole == 'husband');

  bool get viewerIsWife => recorderRole == 'wife';

  /// The husband of several wives says which wife paid.
  bool get needsWifeChoice => canClassify && recorderRole == 'husband' && wives.length > 1;

  /// The wife preselected for the husband (the only one, or the server's pick).
  String? get defaultSpouseId {
    if (recorderRole != 'husband') return null;
    if (wives.length == 1) return wives.first.id;
    return suggestedSpouseId;
  }

  /// Fields for `/agent/scan-receipt` or `/agent/chat-transaction`: who paid
  /// for whom and the confirmed class, consistent with each other (empty
  /// outside family mode). A wife never names a spouse: she is the spouse.
  Map<String, String> requestFields(String? nafaqahClass, {String? chosenWifeId}) {
    if (!canClassify) return const {};
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
      wives: summary.wives,
    );
  }

  factory NafaqahPreview.fromPreview(Map<String, dynamic>? data) {
    if (data == null || data['household_mode'] != 'family_nafaqah') return const NafaqahPreview();
    final cls = data['nafaqah_class'] as String?;
    return NafaqahPreview(
      isFamily: true,
      recorderRole: data['recorder_role'] as String?,
      suggestedClass: (cls == kWifeReimbursable || cls == kWifePersonal) ? cls : null,
      suggestedSpouseId: data['nafaqah_spouse_id'] as String?,
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

  const ReimbursementBalance({
    this.grossAdvanced = 0.0,
    this.reimbursed = 0.0,
    this.outstanding = 0.0,
  });

  bool get isSettled => outstanding < 0.005;

  factory ReimbursementBalance.fromMap(Map<String, dynamic> map) => ReimbursementBalance(
        grossAdvanced: _num(map['gross_advanced']),
        reimbursed: _num(map['reimbursed']),
        outstanding: _num(map['outstanding']),
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

  bool get isOverspent => remaining < 0;

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

class NafaqahWife {
  final String id;
  final String? displayName;
  final ReimbursementBalance reimbursement;
  final AllowanceStatus allowance;

  const NafaqahWife({
    required this.id,
    this.displayName,
    this.reimbursement = const ReimbursementBalance(),
    this.allowance = const AllowanceStatus(),
  });

  factory NafaqahWife.fromMap(Map<String, dynamic> map) => NafaqahWife(
        id: map['id'] as String? ?? '',
        displayName: map['display_name'] as String?,
        reimbursement: ReimbursementBalance.fromMap(
          Map<String, dynamic>.from(map['reimbursement'] as Map? ?? const {}),
        ),
        allowance: AllowanceStatus.fromMap(
          Map<String, dynamic>.from(map['allowance'] as Map? ?? const {}),
        ),
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
  });

  bool get isFamily => mode == 'family_nafaqah' && wives.isNotEmpty;
  bool get callerIsWife => callerRole == 'wife';

  /// The wife the caller is concerned with: herself, or the first wife.
  NafaqahWife? get primaryWife {
    if (wives.isEmpty) return null;
    if (callerIsWife) {
      return wives.firstWhere((w) => w.id == callerUserId, orElse: () => wives.first);
    }
    return wives.first;
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
    );
  }
}

/// One line of the wife's ledger: an advance she made or a repayment to her.
class NafaqahLedgerEntry {
  final String type; // 'advance' | 'reimbursement'
  final String id;
  final double amount;
  final DateTime? timestamp;
  final String? merchant;
  final String? paymentMethod;
  final String? notes;

  const NafaqahLedgerEntry({
    required this.type,
    required this.id,
    required this.amount,
    this.timestamp,
    this.merchant,
    this.paymentMethod,
    this.notes,
  });

  bool get isAdvance => type == 'advance';

  factory NafaqahLedgerEntry.fromMap(Map<String, dynamic> map) => NafaqahLedgerEntry(
        type: map['type'] as String? ?? 'advance',
        id: map['id']?.toString() ?? '',
        amount: _num(map['amount']),
        timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '')?.toLocal(),
        merchant: map['merchant'] as String?,
        paymentMethod: map['payment_method'] as String?,
        notes: map['notes'] as String?,
      );
}

class NafaqahLedger {
  final ReimbursementBalance balance;
  final List<NafaqahLedgerEntry> history;

  const NafaqahLedger({this.balance = const ReimbursementBalance(), this.history = const []});

  factory NafaqahLedger.fromMap(Map<String, dynamic> map) => NafaqahLedger(
        balance: ReimbursementBalance.fromMap(Map<String, dynamic>.from(map['balance'] as Map? ?? const {})),
        history: (map['history'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => NafaqahLedgerEntry.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// A rejected Nafaqah request. [code] is 'overpayment', 'forbidden',
/// 'not_family', 'invalid' or 'network'.
class NafaqahApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const NafaqahApiException(this.code, this.message, {this.statusCode});

  factory NafaqahApiException.fromResponse(Map<String, dynamic> res) {
    final status = (res['status_code'] as num?)?.toInt();
    final detail = res['detail'];
    final detailCode = detail is Map ? detail['code'] as String? : null;
    final message = res['message']?.toString() ?? '';
    final String code;
    if (detailCode == 'overpayment' || detailCode == 'not_family') {
      code = detailCode!;
    } else if (status == 403) {
      code = 'forbidden';
    } else if (status == 422 || status == 400) {
      code = 'invalid';
    } else {
      code = 'network';
    }
    return NafaqahApiException(code, message, statusCode: status);
  }

  @override
  String toString() => 'NafaqahApiException($code, $statusCode): $message';
}
