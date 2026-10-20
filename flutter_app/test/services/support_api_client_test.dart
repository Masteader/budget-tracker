import 'dart:async';
import 'dart:convert';

import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/support_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

SupportApiClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  String? token = 'user-jwt',
}) {
  return SupportApiClient(
    baseClient: BaseApiClient(
      client: MockClient(handler),
      authTokenProvider: () => token,
      sessionRefresher: () async => null,
    ),
  );
}

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('SupportApiClient exposes postSupportChat and ApiService facade', () {
    final client = SupportApiClient();
    expect(client, isNotNull);
    expect(ApiService.instance.support, isNotNull);
  });

  group('sendSupportInquiry', () {
    test('posts the message with the user JWT and reports sent only on {"status":"sent"}', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _json(200, {'status': 'sent', 'reference': 'abc123def456'});
      });

      final result = await client.sendSupportInquiry(
        message: '  Sync fails after scanning a ZATCA receipt  ',
        locale: 'ar',
        householdId: '00000000-0000-4000-8000-000000000001',
      );

      expect(result.isSent, isTrue);
      expect(result.reference, 'abc123def456');
      expect(captured.method, 'POST');
      expect(captured.url.path, endsWith('/support/inquiries'));
      expect(captured.headers['Authorization'], 'Bearer user-jwt');
      expect(jsonDecode(captured.body), {
        'message': 'Sync fails after scanning a ZATCA receipt',
        'locale': 'ar',
        'household_id': '00000000-0000-4000-8000-000000000001',
      });
    });

    test('never sends an identity of its own: only message, locale and household', () async {
      late Map<String, dynamic> body;
      final client = _client((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(200, {'status': 'sent', 'reference': 'r'});
      });
      await client.sendSupportInquiry(message: 'Hello');
      expect(body.keys, ['message']);
    });

    test('empty or oversized messages are rejected without a request', () async {
      var calls = 0;
      final client = _client((request) async {
        calls++;
        return _json(200, {'status': 'sent'});
      });
      expect((await client.sendSupportInquiry(message: '   ')).outcome, SupportInquiryOutcome.invalid);
      expect(
        (await client.sendSupportInquiry(message: 'x' * (SupportApiClient.maxInquiryLength + 1))).outcome,
        SupportInquiryOutcome.invalid,
      );
      expect(calls, 0);
    });

    final statusCases = <int, SupportInquiryOutcome>{
      401: SupportInquiryOutcome.unauthorized,
      422: SupportInquiryOutcome.invalid,
      429: SupportInquiryOutcome.rateLimited,
      502: SupportInquiryOutcome.unavailable,
      503: SupportInquiryOutcome.unavailable,
    };
    statusCases.forEach((code, outcome) {
      test('HTTP $code maps to $outcome and is never reported as sent', () async {
        final client = _client((request) async => _json(code, {'detail': 'nope'}));
        final result = await client.sendSupportInquiry(message: 'Help');
        expect(result.outcome, outcome);
        expect(result.isSent, isFalse);
      });
    });

    test('a 2xx answer without status "sent" is not a success', () async {
      final client = _client((request) async => _json(200, {'status': 'queued'}));
      final result = await client.sendSupportInquiry(message: 'Help');
      expect(result.outcome, SupportInquiryOutcome.unavailable);
    });

    test('transport failures map to network', () async {
      final client = _client((request) async => throw TimeoutException('offline'));
      final result = await client.sendSupportInquiry(message: 'Help');
      expect(result.outcome, SupportInquiryOutcome.network);
    });
  });
}
