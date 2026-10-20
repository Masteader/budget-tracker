import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import 'api/household_roles_api_client.dart';

/// Client-side mirror of the household permission rules (owner decision on
/// audit items DB-16 / DB-18, family and roommate households alike).
///
/// The database (RLS, triggers, RPCs) and the API enforce these rules; the app
/// only hides actions the user cannot take and explains a refusal.
class HouseholdPermissions {
  const HouseholdPermissions._();

  /// A member edits or deletes their own transactions; an admin any
  /// transaction of the household. Legacy rows without a creator are admin-only.
  static bool canModifyTransaction({
    required String? currentUserId,
    required String? creatorUserId,
    required bool isAdmin,
  }) {
    if (currentUserId == null || currentUserId.isEmpty) return false;
    if (isAdmin) return true;
    return creatorUserId != null && creatorUserId == currentUserId;
  }

  static bool isSharedPool(Account account) =>
      account.isSharedPool || account.accountType == AccountType.sharedPool;

  /// Money leaves a shared pool only by an admin; a personal account only by its owner.
  static bool canWithdrawFrom(Account account, {required String? currentUserId, required bool isAdmin}) {
    if (isSharedPool(account)) return isAdmin;
    return currentUserId != null && account.ownerUserId == currentUserId;
  }

  /// Source accounts the user may move money out of.
  static List<Account> withdrawableAccounts(
    List<Account> accounts, {
    required String? currentUserId,
    required bool isAdmin,
  }) =>
      accounts.where((a) => canWithdrawFrom(a, currentUserId: currentUserId, isAdmin: isAdmin)).toList();

  /// True when [error] is the server refusing the action for lack of rights
  /// (PostgREST 42501 / HTTP 403), as opposed to a network or validation error.
  static bool isPermissionDenied(Object error) {
    if (error is PostgrestException) {
      return error.code == '42501' || error.message.startsWith('Forbidden');
    }
    if (error is HouseholdRolesApiException) return error.code == 'forbidden';
    return false;
  }
}
