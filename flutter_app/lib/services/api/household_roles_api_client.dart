import '../../models/household_membership.dart';
import 'base_api_client.dart';

/// Members, co-admins and the primary admin of a household.
///
/// Every write is checked by the backend with the caller's JWT (admins only;
/// transferring primary admin is for the primary admin only) and re-checked
/// by the database RPCs. Each call throws [HouseholdRolesApiException] when the
/// server refuses, so the UI never shows a role change that did not happen.
class HouseholdRolesApiClient {
  final BaseApiClient baseClient;

  HouseholdRolesApiClient({BaseApiClient? baseClient}) : baseClient = baseClient ?? BaseApiClient();

  static Map<String, dynamic> _ok(Map<String, dynamic> res) {
    if (res['status'] == 'error') throw HouseholdRolesApiException.fromResponse(res);
    return res;
  }

  Future<HouseholdRoster> fetchMembers(String householdId) async {
    final res = await baseClient.get('/households/$householdId/members');
    return HouseholdRoster.fromMap(_ok(res));
  }

  Future<HouseholdRoster> promoteToAdmin(String householdId, String userId) async {
    final res = await baseClient.post('/households/$householdId/members/$userId/admin', const {}, shouldSign: false);
    return HouseholdRoster.fromMap(_ok(res));
  }

  Future<HouseholdRoster> revokeAdmin(String householdId, String userId) async {
    final res = await baseClient.delete('/households/$householdId/members/$userId/admin');
    return HouseholdRoster.fromMap(_ok(res));
  }

  Future<HouseholdRoster> transferPrimaryAdmin(String householdId, String newPrimaryUserId) async {
    final res = await baseClient.post(
      '/households/$householdId/primary-admin',
      {'new_primary_user_id': newPrimaryUserId},
      shouldSign: false,
    );
    return HouseholdRoster.fromMap(_ok(res));
  }
}

/// A refused or failed role request. [code] is `forbidden` (403),
/// `last_admin` (409), `not_found` (404) or `network` (anything else).
class HouseholdRolesApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const HouseholdRolesApiException(this.code, this.message, {this.statusCode});

  factory HouseholdRolesApiException.fromResponse(Map<String, dynamic> res) {
    final status = (res['status_code'] as num?)?.toInt();
    final message = res['message']?.toString() ?? '';
    final String code;
    switch (status) {
      case 403:
        code = 'forbidden';
      case 404:
        code = 'not_found';
      case 409:
        code = 'last_admin';
      default:
        code = 'network';
    }
    return HouseholdRolesApiException(code, message, statusCode: status);
  }

  @override
  String toString() => message.isEmpty ? code : message;
}
