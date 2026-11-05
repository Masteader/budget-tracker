/// The account deletion request as the client RPCs report it
/// (`supabase/migrations/20261105000200_account_deletion_rpcs.sql`).
library;

/// `status` of `get_account_deletion_status()`. A request in `processing` or
/// `failed` can no longer be cancelled.
enum AccountDeletionState { none, scheduled, processing, failed }

/// A household that goes when this account does.
class MarkedHousehold {
  final String id;
  final String name;
  final DateTime? scheduledFor;

  const MarkedHousehold({required this.id, required this.name, this.scheduledFor});

  factory MarkedHousehold.fromMap(Map<String, dynamic> map) => MarkedHousehold(
        id: map['household_id']?.toString() ?? '',
        name: map['household_name']?.toString() ?? '',
        scheduledFor: _parseDate(map['scheduled_for']),
      );
}

class AccountDeletionStatus {
  final AccountDeletionState state;
  final String? requestId;
  final DateTime? requestedAt;
  final DateTime? scheduledFor;
  final String? locale;
  final bool canCancel;
  final List<MarkedHousehold> markedHouseholds;

  const AccountDeletionStatus({
    required this.state,
    this.requestId,
    this.requestedAt,
    this.scheduledFor,
    this.locale,
    this.canCancel = false,
    this.markedHouseholds = const [],
  });

  static const AccountDeletionStatus none = AccountDeletionStatus(state: AccountDeletionState.none);

  /// What this device remembers while the server cannot be reached. The server
  /// still decides whether a cancel succeeds.
  factory AccountDeletionStatus.fromDeviceFlag(DateTime scheduledFor) => AccountDeletionStatus(
        state: AccountDeletionState.scheduled,
        scheduledFor: scheduledFor,
        canCancel: true,
      );

  factory AccountDeletionStatus.fromMap(Map<String, dynamic> map) {
    final marked = map['marked_households'];
    return AccountDeletionStatus(
      state: _parseState(map['status']?.toString()),
      requestId: map['request_id']?.toString(),
      requestedAt: _parseDate(map['requested_at']),
      scheduledFor: _parseDate(map['scheduled_for']),
      locale: map['locale']?.toString(),
      canCancel: map['can_cancel'] == true,
      markedHouseholds: marked is List
          ? marked.whereType<Map>().map((m) => MarkedHousehold.fromMap(Map<String, dynamic>.from(m))).toList()
          : const [],
    );
  }

  bool get isPending => state != AccountDeletionState.none;

  /// An unknown status is treated as a request nobody can cancel: reading it as
  /// `none` would hide a deletion that is under way.
  static AccountDeletionState _parseState(String? status) => switch (status) {
        'none' => AccountDeletionState.none,
        'scheduled' => AccountDeletionState.scheduled,
        'processing' => AccountDeletionState.processing,
        _ => AccountDeletionState.failed,
      };
}

/// `position` of a household in `get_account_deletion_preflight()`.
enum HouseholdDeletionPosition { member, soleMember, primaryAdmin, coAdmin }

/// A member the caller may hand a household to. [pendingDeletion] members are
/// listed but cannot be chosen; the server refuses them either way.
class AccountDeletionCandidate {
  final String userId;
  final String? displayName;
  final bool pendingDeletion;

  const AccountDeletionCandidate({required this.userId, this.displayName, this.pendingDeletion = false});

  factory AccountDeletionCandidate.fromMap(Map<String, dynamic> map) => AccountDeletionCandidate(
        userId: map['user_id']?.toString() ?? '',
        displayName: map['display_name']?.toString(),
        pendingDeletion: map['pending_deletion'] == true,
      );
}

class AccountDeletionHousehold {
  final String id;
  final String name;
  final HouseholdDeletionPosition position;
  final bool needsChoice;
  final List<AccountDeletionCandidate> candidates;

  const AccountDeletionHousehold({
    required this.id,
    required this.name,
    required this.position,
    this.needsChoice = false,
    this.candidates = const [],
  });

  factory AccountDeletionHousehold.fromMap(Map<String, dynamic> map) {
    final candidates = map['candidates'];
    return AccountDeletionHousehold(
      id: map['household_id']?.toString() ?? '',
      name: map['household_name']?.toString() ?? '',
      position: switch (map['position']?.toString()) {
        'sole_member' => HouseholdDeletionPosition.soleMember,
        'primary_admin' => HouseholdDeletionPosition.primaryAdmin,
        'co_admin' => HouseholdDeletionPosition.coAdmin,
        _ => HouseholdDeletionPosition.member,
      },
      needsChoice: map['needs_choice'] == true,
      candidates: candidates is List
          ? candidates.whereType<Map>().map((m) => AccountDeletionCandidate.fromMap(Map<String, dynamic>.from(m))).toList()
          : const [],
    );
  }

  bool get hasSelectableSuccessor => candidates.any((c) => !c.pendingDeletion);
}

class AccountDeletionPreflight {
  final AccountDeletionStatus deletion;
  final List<AccountDeletionHousehold> households;

  const AccountDeletionPreflight({required this.deletion, this.households = const []});

  factory AccountDeletionPreflight.fromMap(Map<String, dynamic> map) {
    final deletion = map['deletion'];
    final households = map['households'];
    return AccountDeletionPreflight(
      deletion: deletion is Map ? AccountDeletionStatus.fromMap(Map<String, dynamic>.from(deletion)) : AccountDeletionStatus.none,
      households: households is List
          ? households.whereType<Map>().map((m) => AccountDeletionHousehold.fromMap(Map<String, dynamic>.from(m))).toList()
          : const [],
    );
  }

  /// The households the caller must decide about.
  List<AccountDeletionHousehold> get householdsNeedingChoice => households.where((h) => h.needsChoice).toList();
}

/// An element of `p_household_choices`.
class HouseholdDeletionChoice {
  final String householdId;
  final String action;
  final String? successorUserId;

  const HouseholdDeletionChoice.transfer(this.householdId, String this.successorUserId) : action = 'transfer';
  const HouseholdDeletionChoice.delete(this.householdId)
      : action = 'delete',
        successorUserId = null;

  Map<String, dynamic> toJson() => {
        'household_id': householdId,
        'action': action,
        // The server refuses any successor on a household being deleted.
        if (successorUserId != null) 'successor_user_id': successorUserId,
      };
}

/// `households.deletion_scheduled_for` of one household as this user can read it.
class HouseholdDeletionMark {
  /// False when no row came back: the household is gone, or no longer the
  /// user's active one (RLS shows only that).
  final bool readable;
  final DateTime? scheduledFor;

  const HouseholdDeletionMark({required this.readable, this.scheduledFor});
}

/// The localization key of a refusal the grace-period guards raise (database
/// hint, or `detail.code` of the API's 409), or null for anything else.
String? accountDeletionGuardKey(String? code) => switch (code) {
      'account_pending_deletion' => 'del_err_account_pending',
      'household_pending_deletion' => 'del_err_household_pending',
      'successor_pending_deletion' => 'del_err_successor_pending',
      _ => null,
    };

/// A failed deletion step. [code] is the RPC's hint or one of the client codes
/// below; the server's own text is never kept, because it is English and is
/// never shown.
class AccountDeletionException implements Exception {
  final String code;

  const AccountDeletionException(this.code);

  /// The password was wrong.
  static const String invalidCredentials = 'invalid_credentials';

  /// The emailed code was wrong or has expired.
  static const String invalidCode = 'invalid_code';

  /// Too many attempts for now.
  static const String rateLimited = 'rate_limited';

  /// The emailed code could not be sent.
  static const String codeNotSent = 'code_not_sent';

  /// No answer arrived.
  static const String network = 'network';

  /// Anything else the server refused.
  static const String unknown = 'unknown';

  bool get needsReauthentication => code == 'reauthentication_required';

  /// The stored choices no longer fit the household: the flow has to ask again.
  bool get choicesOutOfDate => const {
        'household_choice_missing',
        'household_choice_invalid',
        'successor_invalid',
        'successor_pending_deletion',
      }.contains(code);

  /// The localization key of the message to show.
  String get messageKey =>
      accountDeletionGuardKey(code) ??
      switch (code) {
        'reauthentication_required' => 'del_err_reauth_required',
        'confirmation_mismatch' => 'del_err_confirmation_mismatch',
        'household_choice_missing' => 'del_err_choice_missing',
        'household_choice_invalid' => 'del_err_choice_invalid',
        'successor_invalid' => 'del_err_successor_invalid',
        'deletion_in_progress' => 'del_err_in_progress',
        invalidCredentials => 'del_err_wrong_password',
        invalidCode => 'del_err_wrong_code',
        rateLimited => 'del_err_rate_limited',
        codeNotSent => 'del_err_code_not_sent',
        network => 'del_err_network',
        _ => 'del_err_generic',
      };

  @override
  String toString() => 'AccountDeletionException($code)';
}

// The fold `request_account_deletion` applies before comparing, in its order:
// 1. Urdu letters an Arabic keyboard lacks become the Arabic ones it types:
//    U+06A9 (keheh) to U+0643 (kaf), U+06CC (farsi yeh) to U+064A (yeh),
//    U+06BA (noon ghunna) to U+0646 (noon), and U+0649 (alef maksura) to U+064A.
// 2. Zero-width and embedding marks a mobile keyboard may add are dropped
//    (U+200B to U+200D, U+202A to U+202E, U+2066 to U+2069, U+FEFF).
// 3. The direction marks U+200E and U+200F, U+00A0 and every other space are
//    spaces; a run of them becomes one, and the ends are trimmed.
// 4. Case is ignored.
const Map<String, String> _letterFold = {
  '\u06A9': '\u0643',
  '\u06CC': '\u064A',
  '\u06BA': '\u0646',
  '\u0649': '\u064A',
};
final RegExp _foldedLetters = RegExp('[\u06A9\u06CC\u06BA\u0649]');
final RegExp _invisibleMarks = RegExp('[\u200B-\u200D\u202A-\u202E\u2066-\u2069\uFEFF]');
// Dart's `\s` is Unicode White_Space: U+00A0, U+1680, U+2000 to U+200A, U+2028,
// U+2029, U+202F, U+205F and U+3000 besides the ASCII ones.
final RegExp _spaces = RegExp('[\\s\u00A0\u200E\u200F]+');

/// [typed] folded the way the server folds it before comparing.
String foldConfirmationWord(String typed) => typed
    .replaceAllMapped(_foldedLetters, (m) => _letterFold[m[0]]!)
    .replaceAll(_invisibleMarks, '')
    .replaceAll(_spaces, ' ')
    .trim()
    .toLowerCase();

/// The confirmation words the server accepts, in any app language, folded.
final Set<String> _confirmationWords = {'delete', 'حذف', 'حذف کریں'}.map(foldConfirmationWord).toSet();

/// Whether [typed] is a word the server would accept after the same fold
/// ([foldConfirmationWord]).
bool confirmationWordMatches(String typed) => _confirmationWords.contains(foldConfirmationWord(typed));

DateTime? _parseDate(Object? value) => value == null ? null : DateTime.tryParse(value.toString());
