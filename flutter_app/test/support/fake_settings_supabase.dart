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
  Future<HouseholdMembership?> getHouseholdMembership(String householdId) async => null;

  @override
  Future<List<HouseholdDependent>> getDependents(String householdId) async => const [
        HouseholdDependent(id: 'd-1', householdId: fakeSettingsHouseholdId, name: 'Noura', relationship: 'spouse', monthlyAllowance: 2000),
        HouseholdDependent(id: 'd-2', householdId: fakeSettingsHouseholdId, name: 'Salem', monthlyAllowance: 300),
      ];

  int settlementCallCount = 0;
  bool failSettlement = false;

  /// Answers per household; [settlement] for the others.
  final Map<String, SettlementV2Summary> byHousehold = {};

  /// A household listed here answers only when its completer does.
  final Map<String, Completer<SettlementV2Summary>> gates = {};

  /// Every request of a household listed here waits for its completer.
  final Map<String, Completer<void>> holds = {};

  /// Households whose settlement requests fail.
  final Set<String> failingHouseholds = {};

  @override
  Future<SettlementV2Summary> getSettlementV2(String householdId, {String? cycleStart}) async {
    settlementCallCount++;
    final gate = gates.remove(householdId);
    if (gate != null) return gate.future;
    if (holds[householdId] != null) await holds[householdId]!.future;
    await Future<void>.delayed(Duration.zero);
    if (failSettlement || failingHouseholds.contains(householdId)) {
      throw Exception('Failed to fetch settlement');
    }
    return byHousehold[householdId] ?? settlement;
  }

  /// The memberships the switch sheet lists.
  List<HouseholdMembership> memberships = const [];

  /// Called by a successful switch; the harness moves the active household.
  void Function(String householdId)? onSwitched;

  /// False makes the switch refuse without throwing, as the RPC client does.
  bool switchSucceeds = true;

  @override
  Future<List<HouseholdMembership>> getUserHouseholds() async => memberships;

  @override
  Future<bool> switchActiveHousehold(String householdId) async {
    if (writeError != null) throw writeError!;
    if (!switchSucceeds) return false;
    onSwitched?.call(householdId);
    return true;
  }

  /// Runs on each recorded settlement; a test can throw or change the answer.
  Future<Map<String, dynamic>> Function(ReimbursementRecordRequest request)? onRecordPayment;

  @override
  Future<Map<String, dynamic>> recordReimbursementPayment(ReimbursementRecordRequest request) async =>
      onRecordPayment == null ? const {'status': 'success'} : await onRecordPayment!(request);

  /// Thrown by the writes the error tests provoke.
  Object? writeError;

  @override
  Future<bool> setHouseholdPayday(String householdId, int day) async {
    if (writeError != null) throw writeError!;
    return true;
  }

  @override
  Future<HouseholdDependent?> createDependent(
    String householdId,
    String name, {
    String? relationship,
    double? monthlyAllowance,
    String? avatarIcon,
  }) async {
    if (writeError != null) throw writeError!;
    return HouseholdDependent(id: 'd-new', householdId: householdId, name: name);
  }

  @override
  Future<bool> deleteDependent(String householdId, String dependentId) async {
    if (writeError != null) throw writeError!;
    return true;
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
const fakeSettingsPassword = 'correct-password';
const fakeSettingsEmailCode = '123456';

/// One RPC the client called.
class FakeRpcCall {
  final String function;
  final Map<String, dynamic> params;
  const FakeRpcCall(this.function, this.params);
}

/// A refusal raised with a machine hint. A hint under SQLSTATE 42501 reaches the
/// client as HTTP 403, under 22023 as HTTP 400.
class FakeRpcRefusal {
  final String hint;
  final String code;
  final int status;
  final String message;
  const FakeRpcRefusal(this.hint, {this.code = '22023', this.status = 400, this.message = 'raw server text'});
}

/// Answers the PostgREST calls SettingsScreen makes; every other path is `[]`.
class FakeSettingsHttpClient extends http.BaseClient {
  /// Rows of the `transactions` export; null makes the request fail.
  List<Map<String, dynamic>>? transactions = const [];

  /// The members the household has; two or more shows partner settlement.
  int memberCount = 2;
  http.BaseRequest? lastTransactionRequest;

  /// Every `transactions` request, in order.
  final List<Uri> transactionRequests = [];

  /// What PostgREST caps a response to, answering 200 with partial rows.
  int rowCap = 1000;

  /// When set, `transactions` requests answer only after this completes.
  Completer<void>? transactionGate;

  /// The household `users.household_id` reports for the signed-in user.
  String activeHouseholdId = fakeSettingsHouseholdId;

  /// `households.payday_day` per household; absent means 27. Set
  /// [failPaydayRead] to make that read fail.
  final Map<String, int> paydayByHousehold = {};
  bool failPaydayRead = false;
  int householdReads = 0;

  /// RPCs that fail, by function name: the Postgres error message they raise.
  final Map<String, String> rpcErrors = {};

  /// Answers of RPCs that do not fail, by function name.
  final Map<String, Object?> rpcResults = {};

  /// RPCs that fail the way PostgREST reports a `RAISE EXCEPTION ... USING HINT`.
  final Map<String, FakeRpcRefusal> rpcRefusals = {};

  /// RPCs that never get an answer: the request itself fails.
  final Set<String> rpcOffline = {};

  /// Every RPC called, in order, with its decoded parameters.
  final List<FakeRpcCall> rpcCalls = [];

  /// `households.deletion_scheduled_for` per household, as the server sends it.
  final Map<String, String?> householdDeletionDates = {};

  /// Households the signed-in user can no longer read: RLS answers no row.
  final Set<String> unreadableHouseholds = {};

  /// False when the `users` row of the signed-in user is gone (purged).
  bool userRowExists = true;

  /// The password `signInWithPassword` accepts, and the code `verifyOTP` accepts.
  String validPassword = fakeSettingsPassword;
  String validEmailCode = fakeSettingsEmailCode;

  /// Every Auth call: `password:<email>`, `otp:<email>:<shouldCreateUser>`,
  /// `verify:<email>:<type>`.
  final List<String> authCalls = [];

  /// When set, every Auth call fails with this status and error code.
  ({int status, String code})? authFailure;

  /// When set, Auth calls and RPCs answer only after it completes: a test can
  /// act while a call is still on its way.
  Completer<void>? authGate;
  Completer<void>? rpcGate;

  void resetScenario() {
    transactions = const [];
    memberCount = 2;
    lastTransactionRequest = null;
    transactionRequests.clear();
    rowCap = 1000;
    transactionGate = null;
    activeHouseholdId = fakeSettingsHouseholdId;
    paydayByHousehold.clear();
    failPaydayRead = false;
    householdReads = 0;
    rpcErrors.clear();
    rpcResults.clear();
    rpcRefusals.clear();
    rpcOffline.clear();
    rpcCalls.clear();
    householdDeletionDates.clear();
    unreadableHouseholds.clear();
    userRowExists = true;
    validPassword = fakeSettingsPassword;
    validEmailCode = fakeSettingsEmailCode;
    authCalls.clear();
    authFailure = null;
    authGate = null;
    rpcGate = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    final query = url.query;
    Object? body = const <Object>[];
    var status = 200;
    if (url.path.contains('/auth/v1/')) {
      final gate = authGate;
      if (gate != null) {
        // Recorded on arrival, as the server would see it.
        final answer = _answerAuth(request);
        await gate.future;
        return answer;
      }
      return _answerAuth(request);
    }
    if (url.path.endsWith('/rest/v1/users')) {
      if (query.contains('household_id=eq.') && !query.contains('id=eq.$fakeSettingsUserId')) {
        body = List.generate(memberCount, (i) => {'display_name': 'Member $i', 'role': i == 0 ? 'admin' : 'member'});
      } else {
        body = userRowExists
            ? [
                {'id': fakeSettingsUserId, 'household_id': activeHouseholdId, 'display_name': 'Owner', 'role': 'admin'},
              ]
            : const <Object>[];
      }
    } else if (url.path.endsWith('/rest/v1/households') && request.method == 'GET') {
      householdReads++;
      if (failPaydayRead) {
        status = 500;
        body = {'message': 'raw payday failure', 'code': 'XX000'};
      } else {
        final hid = url.queryParameters['id']?.replaceFirst('eq.', '');
        body = unreadableHouseholds.contains(hid)
            ? const <Object>[]
            : [
                {'payday_day': paydayByHousehold[hid] ?? 27, 'deletion_scheduled_for': householdDeletionDates[hid]},
              ];
      }
    } else if (url.path.endsWith('/rest/v1/transactions')) {
      lastTransactionRequest = request;
      transactionRequests.add(url);
      if (transactionGate != null) await transactionGate!.future;
      if (transactions == null) {
        status = 500;
        body = {'message': 'PostgrestException raw server detail', 'code': 'XX000'};
      } else {
        body = _transactionsPage(url);
      }
    } else if (url.path.contains('/rest/v1/rpc/')) {
      final fn = url.pathSegments.last;
      final sent = request is http.Request && request.body.isNotEmpty ? jsonDecode(request.body) : null;
      rpcCalls.add(FakeRpcCall(fn, sent is Map ? Map<String, dynamic>.from(sent) : const {}));
      if (rpcGate != null) await rpcGate!.future;
      if (rpcOffline.contains(fn)) throw http.ClientException('Connection refused', url);
      final error = rpcErrors[fn];
      final refusal = rpcRefusals[fn];
      if (refusal != null) {
        status = refusal.status;
        body = {'message': refusal.message, 'code': refusal.code, 'hint': refusal.hint, 'details': null};
      } else if (error != null) {
        status = 400;
        body = {'message': error, 'code': 'P0001'};
      } else {
        body = rpcResults[fn] ?? const <String, Object?>{};
        // As on the server, a status read after a request or cancel that went
        // through reports it.
        if (fn == 'request_account_deletion' && body is Map && body['status'] != null) {
          rpcResults['get_account_deletion_status'] = body;
        } else if (fn == 'cancel_account_deletion' && body is Map && body['cancelled'] == true) {
          rpcResults['get_account_deletion_status'] = const {'status': 'none', 'can_cancel': false};
        }
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

  /// What GoTrue would answer. A wrong password is a 400, a wrong code a 403; a
  /// failed call leaves the session as it was.
  http.StreamedResponse _answerAuth(http.BaseRequest request) {
    http.StreamedResponse answer(int status, Object body) => http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(body))),
          status,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    http.StreamedResponse refuse(int status, String code) =>
        answer(status, {'code': status, 'error_code': code, 'msg': 'raw auth server text'});

    final sent = request is http.Request && request.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(request.body) as Map)
        : const <String, dynamic>{};
    final path = request.url.path;
    if (path.endsWith('/token')) {
      authCalls.add('password:${sent['email']}');
      if (authFailure != null) return refuse(authFailure!.status, authFailure!.code);
      if (sent['password'] != validPassword) return refuse(400, 'invalid_credentials');
      return answer(200, jsonDecode(_sessionJson()) as Object);
    }
    if (path.endsWith('/otp')) {
      authCalls.add('otp:${sent['email']}:${sent['create_user']}');
      if (authFailure != null) return refuse(authFailure!.status, authFailure!.code);
      return answer(200, const <String, Object?>{});
    }
    if (path.endsWith('/verify')) {
      authCalls.add('verify:${sent['email']}:${sent['type']}');
      if (authFailure != null) return refuse(authFailure!.status, authFailure!.code);
      if (sent['token'] != validEmailCode) return refuse(403, 'otp_expired');
      return answer(200, jsonDecode(_sessionJson()) as Object);
    }
    return answer(200, const <String, Object?>{});
  }

  /// What PostgREST would answer: this household and cycle, by `offset` and
  /// `limit`, never more than [rowCap]. A row without those columns matches.
  List<Map<String, dynamic>> _transactionsPage(Uri url) {
    final q = url.queryParameters;
    final hid = q['household_id']?.replaceFirst('eq.', '');
    final key = q['cycle_key']?.replaceFirst('eq.', '');
    final matching = transactions!
        .where((r) => (!r.containsKey('household_id') || r['household_id'] == hid) && (!r.containsKey('cycle_key') || r['cycle_key'] == key));
    final offset = int.tryParse(q['offset'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '') ?? rowCap;
    return matching.skip(offset).take(limit < rowCap ? limit : rowCap).toList();
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

/// Keeps the PKCE verifier in memory: widget tests run on a fake clock, where the
/// default storage's first read of SharedPreferences never completes.
class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
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
      pkceAsyncStorage: _MemoryAsyncStorage(),
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
