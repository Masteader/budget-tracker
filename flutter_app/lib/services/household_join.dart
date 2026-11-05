import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../l10n/app_localizations.dart';

/// The server refused to join or claim a household invite. [code] is the
/// RPC's machine code when it sent one (`already_member`: the user is already
/// a member of that household and may not take an invite meant for someone
/// else, FABLE-DB-01); [message] is the server's own explanation.
class HouseholdJoinException implements Exception {
  final String message;
  final String? code;

  const HouseholdJoinException(this.message, {this.code});

  /// The invite's role does not fit the household type (a roommates
  /// household takes only roommate invites; a family refuses them).
  bool get isRoleMismatch => code == 'invite_role_mismatch';

  bool get isAlreadyMember =>
      code == 'already_member' || message.toLowerCase().contains('already a member of this household');

  @override
  String toString() => message;
}

/// Checks the JSON result of `join_household_by_code` /
/// `create_household_and_claim` (`{success: false, error, code}` on refusal)
/// and returns the household map.
Map<String, dynamic> checkHouseholdJoinResult(Object? result) {
  if (result is! Map) throw const HouseholdJoinException('');
  final map = Map<String, dynamic>.from(result);
  if (map['success'] == false || map['error'] != null) {
    throw HouseholdJoinException(map['error']?.toString() ?? '', code: map['code']?.toString());
  }
  return map;
}

/// Calls a database RPC (defaults to `supabase.rpc`); a seam for tests.
typedef HouseholdRpc = Future<dynamic> Function(String function, Map<String, dynamic> params);

/// The database has no function with these named parameters: an older schema
/// whose `create_household_and_claim` does not take `p_household_type`
/// (PostgREST `PGRST202`, or Postgres `42883` undefined_function).
bool isUnknownFunctionSignature(Object error) {
  if (error is! PostgrestException) return false;
  final message = error.message.toLowerCase();
  return error.code == 'PGRST202' ||
      error.code == '42883' ||
      message.contains('could not find the function') ||
      (message.contains('function') && message.contains('does not exist'));
}

/// Creates a household of [householdType] ('family' | 'roommates') and makes
/// the caller its admin (`create_household_and_claim(p_name, p_household_type)`).
/// Against an older database that does not know `p_household_type` the RPC is
/// called again without it, so creating a household keeps working while the
/// migration is not deployed. Returns the household map, or throws a
/// [HouseholdJoinException] / [PostgrestException] for a refusal.
Future<Map<String, dynamic>> createHouseholdAndClaim({
  required String name,
  required HouseholdRpc rpc,
  String? householdType,
}) async {
  Object? result;
  try {
    result = await rpc('create_household_and_claim', {
      'p_name': name,
      if (householdType != null) 'p_household_type': householdType,
    });
  } on PostgrestException catch (e) {
    if (householdType == null || !isUnknownFunctionSignature(e)) rethrow;
    result = await rpc('create_household_and_claim', {'p_name': name});
  }
  return checkHouseholdJoinResult(result);
}

/// Checks the response of `POST /households/invites/{code}/claim`: a 400 is
/// the server refusing the claim (already a member, invalid or used invite)
/// and is thrown with the server's message. Network failures and other
/// statuses are left to the join call that follows.
void checkInviteClaimResponse(Map<String, dynamic> response) {
  if (response['status'] == 'error' && response['status_code'] == 400) {
    final detail = response['detail'];
    final message = detail is String && detail.isNotEmpty ? detail : response['message']?.toString() ?? '';
    throw HouseholdJoinException(message, code: response['code']?.toString());
  }
}

/// The server's English refusals (`RAISE EXCEPTION` and `{success: false,
/// error}` in `join_household_by_code`, `claim_household_role_invite`,
/// `create_household_and_claim`, `leave_household` and the last-admin trigger,
/// and `supabase_client.claim_household_role_invite`, whose route re-raises only
/// the text) and the key that says the same in the user's language.
const Map<String, String> _refusalKeys = {
  'too many failed join attempts': 'hh_join_rate_limited',
  'invite code has expired': 'hh_invite_expired',
  'invite code has already been used': 'hh_invite_used',
  'invalid, expired, or already used invite code': 'hh_invite_invalid',
  'invalid invite code': 'hh_invite_invalid',
  'invite code is invalid': 'hh_invite_invalid',
  'already a member of this household': 'hh_already_member',
  'does not fit this household type': 'hh_invite_role_mismatch',
  'household creation limit reached': 'set_household_limit_reached',
  'sole admin cannot leave': 'set_leave_promote_admin_first',
  'cannot remove the sole admin': 'set_leave_promote_admin_first',
};

/// The localization key of a household refusal the server explained, or null
/// when [error] is not one it recognises.
String? householdRefusalKey(Object error) {
  final String message;
  if (error is HouseholdJoinException) {
    if (error.isAlreadyMember) return 'hh_already_member';
    if (error.isRoleMismatch) return 'hh_invite_role_mismatch';
    message = error.message;
  } else if (error is PostgrestException) {
    message = error.message;
  } else {
    return null;
  }
  final lower = message.toLowerCase();
  for (final refusal in _refusalKeys.entries) {
    if (lower.contains(refusal.key)) return refusal.value;
  }
  return null;
}

/// What to tell the user when joining or creating a household failed: the
/// reason in their language when it is a known refusal, otherwise a generic
/// failure. Server text is never shown; it is English and can quote internals.
String householdJoinErrorText(BuildContext context, Object error) =>
    context.tr(householdRefusalKey(error) ?? 'action_failed');
