// Which failed settlements may already be on the server. A request with no answer
// (timeout after commit) or a server fault says nothing about the row; a refusal
// says it was not written. The endpoints have no idempotency key, so the difference
// decides whether a retry records the same money twice.
import 'dart:async';
import 'dart:convert';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api/nafaqah_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MockClient _answering(int status, Object body) => MockClient((_) async => http.Response(jsonEncode(body), status));
final _timesOut = MockClient((_) async => throw TimeoutException('20s'));
final _offline = MockClient((_) async => throw http.ClientException('offline'));

Future<ApiRequestException> _roommateFailure(http.Client client) async {
  try {
    await BudgetApiClient(baseClient: BaseApiClient(client: client)).recordReimbursementPayment(
      request: const ReimbursementRecordRequest(householdId: 'hh', payerId: 'a', recipientId: 'b', amount: 10, paymentMethod: 'cash'),
    );
  } on ApiRequestException catch (e) {
    return e;
  }
  throw StateError('expected a failure');
}

Future<NafaqahApiException> _familyFailure(http.Client client) async {
  try {
    await NafaqahApiClient(baseClient: BaseApiClient(client: client)).recordReimbursement(
      householdId: 'hh',
      amount: 10,
      paymentMethod: 'cash',
      wifeUserId: 'w',
      accountId: 'a',
      requestKey: 'k',
    );
  } on NafaqahApiException catch (e) {
    return e;
  }
  throw StateError('expected a failure');
}

void main() {
  group('roommate settlement', () {
    test('no answer: unknown', () async {
      expect((await _roommateFailure(_timesOut)).outcomeUnknown, isTrue);
      expect((await _roommateFailure(_offline)).outcomeUnknown, isTrue);
    });

    for (final status in [500, 502, 503, 504]) {
      test('$status: unknown, the server failed without saying what it stored', () async {
        expect((await _roommateFailure(_answering(status, {'detail': 'x'}))).outcomeUnknown, isTrue);
      });
    }

    for (final status in [400, 401, 403, 404, 409, 422]) {
      test('$status: a refusal, nothing was written', () async {
        expect((await _roommateFailure(_answering(status, {'detail': 'x'}))).outcomeUnknown, isFalse);
      });
    }

    test('200 with an error body: the server\'s verdict, not a lost answer', () async {
      final e = await _roommateFailure(_answering(200, {'status': 'error', 'message': 'no'}));
      expect(e.statusCode, isNull);
      expect(e.outcomeUnknown, isFalse);
    });
  });

  group('family reimbursement: the same endpoint shape, the same risk', () {
    test('no answer: unknown', () async {
      expect((await _familyFailure(_timesOut)).outcomeUnknown, isTrue);
      expect((await _familyFailure(_offline)).outcomeUnknown, isTrue);
    });

    for (final status in [500, 502, 503, 504]) {
      test('$status: unknown', () async {
        expect((await _familyFailure(_answering(status, {'detail': 'x'}))).outcomeUnknown, isTrue);
      });
    }

    for (final status in [400, 403, 404, 409, 422]) {
      test('$status: a refusal', () async {
        expect((await _familyFailure(_answering(status, {'detail': 'x'}))).outcomeUnknown, isFalse);
      });
    }

    test('an overpayment refusal stays a refusal', () async {
      final e = await _familyFailure(_answering(409, {
        'detail': {'code': 'overpayment', 'message': 'x'}
      }));
      expect(e.code, 'overpayment');
      expect(e.outcomeUnknown, isFalse);
    });

    test('200 with an error body: the server\'s verdict', () async {
      expect((await _familyFailure(_answering(200, {'status': 'error', 'message': 'no'}))).outcomeUnknown, isFalse);
    });
  });
}
