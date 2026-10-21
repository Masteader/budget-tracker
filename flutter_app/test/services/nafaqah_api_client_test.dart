import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/nafaqah_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBase extends BaseApiClient {
  Map<String, dynamic> response = {};
  String? method;
  String? path;
  Map<String, dynamic>? body;
  Map<String, dynamic>? query;

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParams, Duration timeout = const Duration(seconds: 15)}) async {
    method = 'GET';
    this.path = path;
    query = queryParams;
    return response;
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool shouldSign = true, Duration timeout = const Duration(seconds: 20), Map<String, String>? extraHeaders}) async {
    method = 'POST';
    this.path = path;
    this.body = body;
    return response;
  }

  @override
  Future<Map<String, dynamic>> put(String path,
      {Map<String, dynamic>? body, bool shouldSign = false, Duration timeout = const Duration(seconds: 15)}) async {
    method = 'PUT';
    this.path = path;
    this.body = body;
    return response;
  }
}

void main() {
  test('fetchSummary hits the household Nafaqah summary', () async {
    final base = _FakeBase()..response = {'mode': 'family_nafaqah', 'wives': [{'id': 'w'}]};
    final s = await NafaqahApiClient(baseClient: base).fetchSummary(householdId: 'hh', cycleKey: '2026-11');
    expect(base.path, '/households/hh/nafaqah');
    expect(base.query, {'cycle_key': '2026-11'});
    expect(s.isFamily, isTrue);
  });

  test('recordReimbursement posts a 2-decimal amount and returns the new balance', () async {
    final base = _FakeBase()..response = {'status': 'success', 'outstanding_after': 300.5};
    final after = await NafaqahApiClient(baseClient: base)
        .recordReimbursement(householdId: 'hh', amount: 200, paymentMethod: 'cash', wifeUserId: 'w');
    expect(base.method, 'POST');
    expect(base.path, '/households/hh/nafaqah/reimbursements');
    expect(base.body, {'amount': 200.0, 'payment_method': 'cash', 'wife_user_id': 'w'});
    expect(after, 300.5);
  });

  test('a rejected reimbursement throws instead of looking recorded', () async {
    final base = _FakeBase()
      ..response = {'status': 'error', 'status_code': 409, 'detail': {'code': 'overpayment'}};
    expect(
      () => NafaqahApiClient(baseClient: base).recordReimbursement(householdId: 'hh', amount: 999, paymentMethod: 'cash'),
      throwsA(isA<NafaqahApiException>().having((e) => e.code, 'code', 'overpayment')),
    );
  });

  test('setAllowance PUTs the cycle amount', () async {
    final base = _FakeBase()
      ..response = {'cycle_key': '2026-11', 'is_set': true, 'allocated': 1500, 'spent': 1700, 'remaining': -200};
    final st = await NafaqahApiClient(baseClient: base)
        .setAllowance(householdId: 'hh', amount: 1500, wifeUserId: 'w', cycleKey: '2026-11');
    expect(base.method, 'PUT');
    expect(base.path, '/households/hh/nafaqah/allowance');
    expect(base.body, {'amount': 1500.0, 'wife_user_id': 'w', 'cycle_key': '2026-11'});
    expect(st.remaining, -200);
    expect(st.isOverspent, isTrue);
  });

  test('setProvider PUTs the chosen member and returns the new summary', () async {
    final base = _FakeBase()
      ..response = {
        'status': 'success',
        'provider_user_id': 'u2',
        'previous_provider_user_id': 'u1',
        'summary': {'mode': 'family_nafaqah', 'husband': {'id': 'u2'}, 'wives': [{'id': 'w'}]},
      };
    final change = await NafaqahApiClient(baseClient: base).setProvider(householdId: 'hh', userId: 'u2');
    expect(base.method, 'PUT');
    expect(base.path, '/households/hh/nafaqah/provider');
    expect(base.body, {'user_id': 'u2'});
    expect(change.providerUserId, 'u2');
    expect(change.summary!.husbandId, 'u2');
  });

  test('a refused provider change throws (403 forbidden, 422 invalid)', () async {
    final base = _FakeBase()..response = {'status': 'error', 'status_code': 403, 'message': 'Household admin required'};
    final client = NafaqahApiClient(baseClient: base);
    await expectLater(
      client.setProvider(householdId: 'hh', userId: 'u2'),
      throwsA(isA<NafaqahApiException>().having((e) => e.code, 'code', 'forbidden')),
    );
    base.response = {'status': 'error', 'status_code': 422, 'message': 'A wife cannot be the Nafaqah provider.'};
    await expectLater(
      client.setProvider(householdId: 'hh', userId: 'w'),
      throwsA(isA<NafaqahApiException>().having((e) => e.code, 'code', 'invalid')),
    );
  });

  test('fetchLedger forwards the wife id', () async {
    final base = _FakeBase()..response = {'balance': {'outstanding': 1}, 'history': []};
    final l = await NafaqahApiClient(baseClient: base).fetchLedger(householdId: 'hh', wifeUserId: 'w');
    expect(base.path, '/households/hh/nafaqah/reimbursements');
    expect(base.query, {'wife_user_id': 'w'});
    expect(l.balance.outstanding, 1);
  });
}
