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

  test('recordReimbursement posts a 2-decimal amount, the account and the key, and returns the new balance', () async {
    final base = _FakeBase()..response = {'status': 'success', 'outstanding_after': 300.5};
    final after = await NafaqahApiClient(baseClient: base).recordReimbursement(
        householdId: 'hh', amount: 200, paymentMethod: 'cash', wifeUserId: 'w', accountId: 'a-1', requestKey: 'k-1');
    expect(base.method, 'POST');
    expect(base.path, '/households/hh/nafaqah/reimbursements');
    expect(base.body, {'amount': 200.0, 'payment_method': 'cash', 'wife_user_id': 'w', 'account_id': 'a-1', 'request_key': 'k-1'});
    expect(after, 300.5);
  });

  test('an old build is told to update: 426 is app_update_required', () async {
    final base = _FakeBase()..response = {'status': 'error', 'status_code': 426, 'detail': 'Upgrade required'};
    expect(
      () => NafaqahApiClient(baseClient: base)
          .recordReimbursement(householdId: 'hh', amount: 1, paymentMethod: 'cash', accountId: 'a', requestKey: 'k'),
      throwsA(isA<NafaqahApiException>().having((e) => e.code, 'code', 'app_update_required')),
    );
  });

  test('her request, its cancel, approval and decline go to their routes', () async {
    final base = _FakeBase()..response = {'status': 'success', 'outstanding_after': 70};
    final client = NafaqahApiClient(baseClient: base);
    await client.createReimbursementRequest(householdId: 'hh', amount: 30.456, paymentMethod: 'cash', requestKey: 'k-r');
    expect(base.path, '/households/hh/nafaqah/reimbursement-requests');
    expect(base.body, {'amount': 30.46, 'payment_method': 'cash', 'request_key': 'k-r'});
    await client.cancelReimbursementRequest(householdId: 'hh', requestId: 'q-1');
    expect(base.path, '/households/hh/nafaqah/reimbursement-requests/q-1/cancel');
    final after = await client.approveReimbursementRequest(householdId: 'hh', requestId: 'q-1', accountId: 'a-1', requestKey: 'k-a');
    expect(base.path, '/households/hh/nafaqah/reimbursement-requests/q-1/approve');
    expect(base.body, {'account_id': 'a-1', 'request_key': 'k-a'});
    expect(after, 70);
    await client.declineReimbursementRequest(householdId: 'hh', requestId: 'q-1', reason: '  Not yet  ');
    expect(base.path, '/households/hh/nafaqah/reimbursement-requests/q-1/decline');
    expect(base.body, {'reason': 'Not yet'});
    await client.declineReimbursementRequest(householdId: 'hh', requestId: 'q-1');
    expect(base.body, <String, dynamic>{});
  });

  test('reversals post only the key', () async {
    final base = _FakeBase()..response = {'status': 'success', 'outstanding_after': 125, 'remaining': 30, 'event_id': 'e-r'};
    final client = NafaqahApiClient(baseClient: base);
    expect(await client.reverseReimbursement(householdId: 'hh', reimbursementId: 'r-1', requestKey: 'k-v'), 125);
    expect(base.path, '/households/hh/nafaqah/reimbursements/r-1/reversal');
    expect(base.body, {'request_key': 'k-v'});
    final r = await client.reverseFormerMemberDebtPayment(householdId: 'hh', debtId: 'd1', eventId: 'e1', requestKey: 'k-w');
    expect(base.path, '/households/hh/nafaqah/former-member-debts/d1/payments/e1/reversal');
    expect(base.body, {'request_key': 'k-w'});
    expect(r.remaining, 30);
  });

  for (final code in [
    'request_not_pending', 'request_exceeds_outstanding', 'pending_exceeds_outstanding', 'already_reversed',
    'reversal_not_tracked', 'reversal_account_unavailable', 'reversal_after_waiver', 'wife_must_request',
  ]) {
    test('the server code $code reaches the app', () async {
      final base = _FakeBase()..response = {'status': 'error', 'status_code': 409, 'detail': {'code': code, 'available': 12.5}};
      await expectLater(
        NafaqahApiClient(baseClient: base).reverseReimbursement(householdId: 'hh', reimbursementId: 'r', requestKey: 'k'),
        throwsA(isA<NafaqahApiException>().having((e) => e.code, 'code', code).having((e) => e.outstanding, 'amount', 12.5)),
      );
    });
  }

  test('a rejected reimbursement throws instead of looking recorded', () async {
    final base = _FakeBase()
      ..response = {'status': 'error', 'status_code': 409, 'detail': {'code': 'overpayment'}};
    expect(
      () => NafaqahApiClient(baseClient: base)
          .recordReimbursement(householdId: 'hh', amount: 999, paymentMethod: 'cash', accountId: 'a', requestKey: 'k'),
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

  test('a former member payment posts amount, method, key and account, nothing else', () async {
    final base = _FakeBase()
      ..response = {
        'status': 'open',
        'replayed': true,
        'debt_id': 'd1',
        'event_id': 'e1',
        'amount': 150.25,
        'payment_method': 'cash',
        'remaining': 249.75,
      };
    final r = await NafaqahApiClient(baseClient: base).recordFormerMemberDebtPayment(
      householdId: 'hh',
      debtId: 'd1',
      amount: 150.25,
      paymentMethod: 'cash',
      requestKey: 'k-1',
      accountId: 'a-1',
    );
    expect(base.method, 'POST');
    expect(base.path, '/households/hh/nafaqah/former-member-debts/d1/payments');
    expect(base.body, {'amount': 150.25, 'payment_method': 'cash', 'request_key': 'k-1', 'account_id': 'a-1'});
    expect(r.replayed, isTrue);
    expect(r.debtId, 'd1');
    expect(r.amount, 150.25);
    expect(r.paymentMethod, 'cash');
    expect(r.remaining, 249.75);
  });

  test('a former member waiver posts only the key', () async {
    final base = _FakeBase()
      ..response = {'status': 'waived', 'replayed': false, 'debt_id': 'd1', 'event_id': 'e2', 'waived_amount': 400, 'remaining': 0};
    final r = await NafaqahApiClient(baseClient: base).waiveFormerMemberDebt(householdId: 'hh', debtId: 'd1', requestKey: 'k-2');
    expect(base.method, 'POST');
    expect(base.path, '/households/hh/nafaqah/former-member-debts/d1/waiver');
    expect(base.body, {'request_key': 'k-2'});
    expect(r.status, 'waived');
    expect(r.amount, 400);
    expect(r.remaining, 0);
  });

  test('a refused former member write throws its code', () async {
    final base = _FakeBase()
      ..response = {
        'status': 'error',
        'status_code': 409,
        'detail': {'code': 'overpayment', 'outstanding': 12.5},
      };
    final client = NafaqahApiClient(baseClient: base);
    await expectLater(
      client.recordFormerMemberDebtPayment(
          householdId: 'hh', debtId: 'd1', amount: 20, paymentMethod: 'cash', requestKey: 'k', accountId: 'a'),
      throwsA(isA<NafaqahApiException>()
          .having((e) => e.code, 'code', 'overpayment')
          .having((e) => e.outstanding, 'outstanding', 12.5)),
    );
    base.response = {'status': 'error', 'status_code': 409, 'detail': {'code': 'debt_closed'}};
    await expectLater(
      client.waiveFormerMemberDebt(householdId: 'hh', debtId: 'd1', requestKey: 'k'),
      throwsA(isA<NafaqahApiException>().having((e) => e.code, 'code', 'debt_closed')),
    );
    base.response = {'status': 'error', 'status_code': 503};
    await expectLater(
      client.waiveFormerMemberDebt(householdId: 'hh', debtId: 'd1', requestKey: 'k'),
      throwsA(isA<NafaqahApiException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
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
