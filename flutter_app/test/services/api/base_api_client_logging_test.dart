// What a failed API call may leave in the device log. `debugPrint` is not
// stripped from release builds and response bodies can carry balances.
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secretBody = 'Insufficient funds: balance (1234.56) owner@example.com';
const _secretPath = '/households/invites/SECRETCODE/claim';

/// Runs [body] and returns everything it sent through `debugPrint`.
Future<List<String>> _captureLog(Future<void> Function() body) async {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return lines;
}

BaseApiClient _refusing() => BaseApiClient(
      client: MockClient((_) async => http.Response(jsonEncode({'detail': _secretBody}), 409)),
    );

BaseApiClient _offline() => BaseApiClient(
      client: MockClient((_) async => throw const SocketException('Failed host lookup: $_secretBody')),
    );

void main() {
  tearDown(() => BaseApiClient.logFailureDetail = BaseApiClient.defaultLogFailureDetail(releaseMode: kReleaseMode));

  group('the default', () {
    test('a release build logs no detail; any other build does', () {
      expect(BaseApiClient.defaultLogFailureDetail(releaseMode: true), isFalse);
      expect(BaseApiClient.defaultLogFailureDetail(releaseMode: false), isTrue);
    });

    test('is what the client starts with in this build', () {
      expect(BaseApiClient.initialLogFailureDetail, BaseApiClient.defaultLogFailureDetail(releaseMode: kReleaseMode));
      expect(BaseApiClient.initialLogFailureDetail, !kReleaseMode);
    });
  });

  group('release builds', () {
    setUp(() => BaseApiClient.logFailureDetail = false);

    test('a refused request logs its status and nothing of the body or URL', () async {
      Map<String, dynamic>? res;
      final log = await _captureLog(() async => res = await _refusing().post(_secretPath, const {}));

      expect(log, hasLength(1));
      expect(log.single, contains('409'));
      expect(log.single, contains('POST'));
      expect(log.single, isNot(contains('1234.56')));
      expect(log.single, isNot(contains('owner@example.com')));
      expect(log.single, isNot(contains('SECRETCODE')));
      // The caller still gets the response: only the log is restricted.
      expect(res!['status_code'], 409);
      expect(res!['message'], _secretBody);
    });

    test('a network failure logs its type and nothing of its message or URL', () async {
      Map<String, dynamic>? res;
      final log = await _captureLog(() async => res = await _offline().get(_secretPath));

      expect(log, hasLength(1));
      expect(log.single, contains('SocketException'));
      expect(log.single, isNot(contains('1234.56')));
      expect(log.single, isNot(contains('Failed host lookup')));
      expect(log.single, isNot(contains('SECRETCODE')));
      expect(res![BaseApiClient.networkErrorKey], isTrue);
    });
  });

  test('debug builds keep the detail a developer needs', () async {
    expect(BaseApiClient.logFailureDetail, isTrue, reason: 'tests run in debug mode');

    final refused = await _captureLog(() => _refusing().post(_secretPath, const {}));
    expect(refused.single, contains('1234.56'));
    expect(refused.single, contains('SECRETCODE'));

    final offline = await _captureLog(() => _offline().get(_secretPath));
    expect(offline.single, contains('Failed host lookup'));
  });
}
