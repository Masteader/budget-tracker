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
  /// Nothing is transferred out of a wife account (migration 20261105001300,
  /// section 12), nor paid from it: she spends from it ([canSpendFrom]).
  static bool canWithdrawFrom(Account account, {required String? currentUserId, required bool isAdmin}) {
    if (account.isWifeAccount) return false;
    if (isSharedPool(account)) return isAdmin;
    return currentUserId != null && account.ownerUserId == currentUserId;
  }

  /// A wife account the viewer spends from: hers (assigned to her), not
  /// archived, in SAR. Only her personal purchases and her advances go on it;
  /// her husband funds it and does not spend from it.
  static bool isHerWifeAccount(Account account, {required String? currentUserId}) =>
      account.isWifeAccount &&
      !account.isArchived &&
      account.currency.toUpperCase() == 'SAR' &&
      currentUserId != null &&
      account.assignedWifeId == currentUserId;

  /// Where the viewer may move money to: every account they see but their own
  /// wife account (she does not fund it; its owner or her ledger's managers do).
  static List<Account> transferDestinations(List<Account> accounts, {required String? currentUserId}) =>
      accounts.where((a) => !(a.isWifeAccount && a.assignedWifeId == currentUserId)).toList();

  /// The usable wife accounts of [wifeId] in [householdId], as the viewer sees
  /// them (her own; all of hers for her husband).
  static List<Account> wifeAccountsOf(List<Account> accounts, {required String householdId, required String? wifeId}) =>
      accounts
          .where((a) =>
              a.isWifeAccount &&
              a.householdId == householdId &&
              !a.isArchived &&
              a.currency.toUpperCase() == 'SAR' &&
              wifeId != null &&
              a.assignedWifeId == wifeId)
          .toList();

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
