// A signed-in Supabase client whose HTTP traffic never leaves the test process,
// so SettingsScreen can be pumped with a household without any live service.
import 'dart:async';
import 'dart:convert';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The settings page's API calls, answered in memory.
class FakeSettingsApi extends ApiService {
  /// Family by default; set to a roommate summary for the roommate card.
  SettlementV2Summary settlement = const SettlementV2Summary(mode: 'family_nafaqah');

  @override
  Future<int> getHouseholdPayday(String householdId) async => 27;

  @override
  Future<List<HouseholdMembership>> getUserHouseholds() async => const [];

  @override
  Future<HouseholdMembership?> getHouseholdMembership(String householdId) async => null;

  @override
  Future<List<HouseholdDependent>> getDependents(String householdId) async => const [
        HouseholdDependent(id: 'd-1', householdId: fakeSettingsHouseholdId, name: 'Noura', relationship: 'spouse', monthlyAllowance: 2000),
        HouseholdDependent(id: 'd-2', householdId: fakeSettingsHouseholdId, name: 'Salem', monthlyAllowance: 300),
      ];

  int settlementCallCount = 0;
  bool failSettlement = false;

  @override
  Future<SettlementV2Summary> getSettlementV2(String householdId, {String? cycleStart}) async {
    settlementCallCount++;
    await Future<void>.delayed(Duration.zero);
    if (failSettlement) {
      throw Exception('Failed to fetch settlement');
    }
    return settlement;
  }

  @override
  Future<HouseholdRoster> getHouseholdMembers(String householdId) async => const HouseholdRoster(
        householdId: fakeSettingsHouseholdId,
        householdType: 'family',
        canChangeHouseholdType: true,
        callerIsPrimary: true,
        callerRole: 'admin',
        canManageAdmins: true,
        canSetNafaqahProvider: true,
        members: [
          HouseholdMember(userId: fakeSettingsUserId, displayName: 'Owner', role: 'admin', isPrimary: true, isSelf: true),
          HouseholdMember(userId: 'user-2', displayName: 'Noura', financialRole: 'spouse'),
        ],
      );

  @override
  Future<NafaqahSummary> getNafaqahSummary(String householdId, {String? cycleKey}) async => const NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: 'husband',
        callerUserId: fakeSettingsUserId,
        cycleKey: '2026-11',
        canRecordReimbursement: true,
        canSetAllowance: true,
        wives: [
          NafaqahWife(
            id: 'user-2',
            displayName: 'Noura',
            reimbursement: ReimbursementBalance(grossAdvanced: 350, outstanding: 350),
            allowance: AllowanceStatus(cycleKey: '2026-11', isSet: true, allocated: 1000, spent: 400, remaining: 600),
          ),
        ],
      );
}

const fakeSettingsUserId = 'user-1';
const fakeSettingsHouseholdId = 'hh-1';
const fakeSettingsEmail = 'owner@example.com';

/// Answers the PostgREST calls SettingsScreen makes; every other path is `[]`.
class FakeSettingsHttpClient extends http.BaseClient {
  /// Rows of the `transactions` export; null makes the request fail.
  List<Map<String, dynamic>>? transactions = const [];

  /// The members the household has; two or more shows partner settlement.
  int memberCount = 2;
  http.BaseRequest? lastTransactionRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    final query = url.query;
    Object? body = const <Object>[];
    var status = 200;
    if (url.path.endsWith('/rest/v1/users')) {
      body = query.contains('household_id=eq.') && !query.contains('id=eq.$fakeSettingsUserId')
          ? List.generate(memberCount, (i) => {'display_name': 'Member $i', 'role': i == 0 ? 'admin' : 'member'})
          : [
              {'household_id': fakeSettingsHouseholdId, 'display_name': 'Owner', 'role': 'admin'},
            ];
    } else if (url.path.endsWith('/rest/v1/transactions')) {
      lastTransactionRequest = request;
      if (transactions == null) {
        status = 500;
        body = {'message': 'PostgrestException raw server detail', 'code': 'XX000'};
      } else {
        body = transactions;
      }
    }
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class _SessionStorage extends LocalStorage {
  final String session;
  const _SessionStorage(this.session);

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<String?> accessToken() async => session;
  @override
  Future<void> removePersistedSession() async {}
  @override
  Future<void> persistSession(String persistSessionString) async {}
}

String _fakeJwt() {
  String part(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  const farFuture = 4102444800; // 2100-01-01
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': fakeSettingsUserId, 'exp': farFuture})}.sig';
}

String _sessionJson() => jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': 4102444800,
      'refresh_token': 'refresh',
      'user': {
        'id': fakeSettingsUserId,
        'aud': 'authenticated',
        'email': fakeSettingsEmail,
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    });

/// Call once per test file, before pumping. The singleton lasts for the file.
Future<void> initFakeSettingsSupabase(FakeSettingsHttpClient client) async {
  await Supabase.initialize(
    url: 'http://localhost:54321',
    publishableKey: 'test-publishable-key',
    httpClient: client,
    authOptions: FlutterAuthClientOptions(
      localStorage: _SessionStorage(_sessionJson()),
      autoRefreshToken: false,
      detectSessionInUri: false,
    ),
    debug: false,
  );
}

/// Restores the fake authenticated user session if a test signed out.
Future<void> resetFakeSettingsAuth() async {
  await Supabase.instance.client.auth.recoverSession(_sessionJson());
}
