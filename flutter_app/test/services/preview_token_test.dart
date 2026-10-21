import 'dart:convert';

import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/chat_api_client.dart';
import 'package:budget_tracker/services/api/preview_token.dart';
import 'package:budget_tracker/services/api/receipt_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records request bodies; answers with [responses] in order (last repeats).
class _Server {
  final List<(int, Map<String, dynamic>)> responses;
  final bodies = <Map<String, dynamic>>[];
  _Server(this.responses);

  BaseApiClient get client => BaseApiClient(
        client: MockClient((request) async {
          bodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
          final r = responses[(bodies.length - 1).clamp(0, responses.length - 1)];
          return http.Response(jsonEncode(r.$2), r.$1, headers: {'content-type': 'application/json'});
        }),
        authTokenProvider: () => 'jwt',
      );
}

const _invalid = (422, {'detail': {'code': 'invalid_preview_token', 'message': 'expired'}});

void main() {
  group('preview_token helpers', () {
    test('previewTokenOf reads a non-empty string only', () {
      expect(previewTokenOf({'preview_token': 'abc'}), 'abc');
      expect(previewTokenOf({'preview_token': ''}), isNull);
      expect(previewTokenOf({'preview_token': 12}), isNull);
      expect(previewTokenOf({}), isNull);
      expect(previewTokenOf(null), isNull);
    });

    test('isInvalidPreviewToken matches only 422 invalid_preview_token', () {
      expect(isInvalidPreviewToken({'status': 'error', 'status_code': 422, 'detail': {'code': 'invalid_preview_token'}}), isTrue);
      expect(isInvalidPreviewToken({'status': 'error', 'status_code': 422, 'detail': {'code': 'other'}}), isFalse);
      expect(isInvalidPreviewToken({'status': 'error', 'status_code': 409, 'detail': {'code': 'invalid_preview_token'}}), isFalse);
      expect(isInvalidPreviewToken({'status': 'success'}), isFalse);
      expect(isInvalidPreviewToken({'status': 'error', 'status_code': 422, 'detail': {'code': 'preview_token_expired'}}), isTrue);
    });
  });

  group('commitWithPreviewToken', () {
    test('commits once with the token when it is accepted', () async {
      final tokens = <String?>[];
      var previews = 0;
      final res = await commitWithPreviewToken(
        token: 't1',
        commit: (t) async {
          tokens.add(t);
          return {'status': 'success'};
        },
        rePreview: () async {
          previews++;
          return {'status': 'pending_confirmation', 'preview_token': 't2'};
        },
      );
      expect(res['status'], 'success');
      expect(tokens, ['t1']);
      expect(previews, 0);
    });

    test('re-runs the preview once and retries with the fresh token', () async {
      final tokens = <String?>[];
      var previews = 0;
      final res = await commitWithPreviewToken(
        token: 'stale',
        commit: (t) async {
          tokens.add(t);
          return t == 'fresh'
              ? {'status': 'success'}
              : {'status': 'error', 'status_code': 422, 'detail': {'code': 'invalid_preview_token'}};
        },
        rePreview: () async {
          previews++;
          return {'status': 'pending_confirmation', 'preview_token': 'fresh'};
        },
      );
      expect(res['status'], 'success');
      expect(tokens, ['stale', 'fresh']);
      expect(previews, 1);
    });

    test('never loops: a second refusal is returned as is', () async {
      var commits = 0;
      var previews = 0;
      final res = await commitWithPreviewToken(
        token: 'a',
        commit: (_) async {
          commits++;
          return {'status': 'error', 'status_code': 422, 'detail': {'code': 'invalid_preview_token'}};
        },
        rePreview: () async {
          previews++;
          return {'status': 'pending_confirmation', 'preview_token': 'b'};
        },
      );
      expect(isInvalidPreviewToken(res), isTrue);
      expect(commits, 2);
      expect(previews, 1);
    });

    test('a failed re-preview returns the original refusal', () async {
      var commits = 0;
      final res = await commitWithPreviewToken(
        token: 'a',
        commit: (_) async {
          commits++;
          return {'status': 'error', 'status_code': 422, 'detail': {'code': 'invalid_preview_token'}};
        },
        rePreview: () async => {'status': 'error', 'status_code': 503},
      );
      expect(commits, 1);
      expect(isInvalidPreviewToken(res), isTrue);
    });
  });

  group('API clients send preview_token back unchanged', () {
    test('chat commit includes it; absent token sends no field', () async {
      final server = _Server([(200, {'status': 'success'})]);
      final chat = ChatApiClient(baseClient: server.client);
      await chat.postChatTransaction(message: 'm', householdId: 'h', previewOnly: false, previewToken: 'tok-1');
      await chat.postChatTransaction(message: 'm', householdId: 'h', previewOnly: false);
      expect(server.bodies[0]['preview_token'], 'tok-1');
      expect(server.bodies[1].containsKey('preview_token'), isFalse);
    });

    test('receipt commit includes it; absent token sends no field', () async {
      final server = _Server([(200, {'status': 'success'})]);
      final receipt = ReceiptApiClient(baseClient: server.client);
      await receipt.scanReceipt(imagesBase64: const ['aGk='], householdId: 'h', previewToken: 'tok-2');
      await receipt.scanReceipt(imagesBase64: const ['aGk='], householdId: 'h');
      expect(server.bodies[0]['preview_token'], 'tok-2');
      expect(server.bodies[1].containsKey('preview_token'), isFalse);
    });

    // UX-12: a corrected amount (and receipt category) travels with the token.
    test('chat commit sends a corrected amount with the token; no amount, no field', () async {
      final server = _Server([(200, {'status': 'success'})]);
      final chat = ChatApiClient(baseClient: server.client);
      await chat.postChatTransaction(message: 'm', householdId: 'h', previewOnly: false, previewToken: 'tok', amount: 186);
      await chat.postChatTransaction(message: 'm', householdId: 'h', previewOnly: false, previewToken: 'tok');
      expect(server.bodies[0]['amount'], 186);
      expect(server.bodies[0]['preview_token'], 'tok');
      expect(server.bodies[1].containsKey('amount'), isFalse);
    });

    test('receipt commit sends a corrected amount and category with the token', () async {
      final server = _Server([(200, {'status': 'success'})]);
      final receipt = ReceiptApiClient(baseClient: server.client);
      await receipt.scanReceipt(
          imagesBase64: const ['aGk='], householdId: 'h', previewToken: 'tok', amount: 85.25, categoryCode: 'OPEX-SHOPPING');
      await receipt.scanReceipt(imagesBase64: const ['aGk='], householdId: 'h', previewToken: 'tok');
      expect(server.bodies[0]['amount'], 85.25);
      expect(server.bodies[0]['category_code'], 'OPEX-SHOPPING');
      expect(server.bodies[1].containsKey('amount'), isFalse);
      expect(server.bodies[1].containsKey('category_code'), isFalse);
    });

    test('a 422 invalid_preview_token reaches the caller recognisably', () async {
      final server = _Server([_invalid]);
      final res = await ChatApiClient(baseClient: server.client)
          .postChatTransaction(message: 'm', householdId: 'h', previewOnly: false, previewToken: 'old');
      expect(isInvalidPreviewToken(res), isTrue);
    });
  });
}
