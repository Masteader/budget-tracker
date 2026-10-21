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

  /// `PUT /households/{id}/type`: an admin changes the household type
  /// ('family' | 'roommates'). Returns the type the server stored.
  Future<String> setHouseholdType(String householdId, String householdType) async {
    final res = await baseClient.put('/households/$householdId/type', body: {'household_type': householdType});
    return (_ok(res)['household_type'] as String?) ?? householdType;
  }

  /// `PUT /households/{id}/members/{user_id}/financial-role`: an admin changes
  /// a member's financial role. Returns the role the server stored.
  Future<String> setFinancialRole(String householdId, String userId, String financialRole) async {
    final res = await baseClient.put(
      '/households/$householdId/members/$userId/financial-role',
      body: {'financial_role': financialRole},
    );
    return (_ok(res)['financial_role'] as String?) ?? financialRole;
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
/// `not_found` (404), the server's `detail.code` for a 409 (e.g.
/// `type_change_blocked`), else `last_admin` (409), `invalid` (422 / 400) or
/// `network` (anything else). [serverMessage] is the server's own
/// explanation from `detail.message`, when it sent one.
class HouseholdRolesApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final String? serverMessage;

  const HouseholdRolesApiException(this.code, this.message, {this.statusCode, this.serverMessage});

  factory HouseholdRolesApiException.fromResponse(Map<String, dynamic> res) {
    final status = (res['status_code'] as num?)?.toInt();
    final message = res['message']?.toString() ?? '';
    final detail = res['detail'];
    final detailCode = detail is Map ? detail['code']?.toString() : null;
    final detailMessage = detail is Map ? detail['message']?.toString() : (detail is String ? detail : null);
    final String code;
    switch (status) {
      case 403:
        code = 'forbidden';
      case 404:
        code = 'not_found';
      case 409:
        code = (detailCode != null && detailCode.isNotEmpty) ? detailCode : 'last_admin';
      case 400:
      case 422:
        code = 'invalid';
      default:
        code = 'network';
    }
    return HouseholdRolesApiException(
      code,
      message,
      statusCode: status,
      serverMessage: (detailMessage != null && detailMessage.trim().isNotEmpty) ? detailMessage.trim() : null,
    );
  }

  @override
  String toString() => message.isEmpty ? code : message;
}
