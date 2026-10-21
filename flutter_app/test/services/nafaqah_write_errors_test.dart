// FABLE-LOGIC-02 / -04: the app explains a transaction write the database or
// API refused for a Nafaqah rule instead of a raw error.
import 'dart:convert';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/chat_api_client.dart';
import 'package:budget_tracker/services/api/receipt_api_client.dart';
import 'package:budget_tracker/services/sync_worker.dart' show SyncWorker;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/nafaqah_write_errors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('nafaqahWriteRefusalOf', () {
    test('the ledger guard (PostgREST 22023 + hint, or its message)', () {
      expect(
        nafaqahWriteRefusalOf(const PostgrestException(
          message: 'Nafaqah ledger overpaid: advances 100.00 < repayments 200.00',
          code: '22023',
          hint: 'ledger_would_be_overpaid',
        )),
        NafaqahWriteRefusal.ledgerWouldBeOverpaid,
      );
      expect(
        nafaqahWriteRefusalOf(const PostgrestException(message: 'Nafaqah ledger overpaid', code: '22023')),
        NafaqahWriteRefusal.ledgerWouldBeOverpaid,
      );
    });

    test('the missing provider (PostgREST 23514 + hint)', () {
      expect(
        nafaqahWriteRefusalOf(const PostgrestException(
          message: 'This family has no Nafaqah provider',
          code: '23514',
          hint: 'no_nafaqah_provider',
        )),
        NafaqahWriteRefusal.noProvider,
      );
    });

    test('API 409 codes, as an exception or as the client error map', () {
      expect(
        nafaqahWriteRefusalOf(const NafaqahApiException('ledger_would_be_overpaid', '', statusCode: 409)),
        NafaqahWriteRefusal.ledgerWouldBeOverpaid,
      );
      expect(
        nafaqahWriteRefusalOf(const NafaqahApiException('no_provider', '', statusCode: 409)),
        NafaqahWriteRefusal.noProvider,
      );
      expect(
        nafaqahWriteRefusalOf({
          'status': 'error',
          'status_code': 409,
          'detail': {'code': 'no_provider', 'message': 'x'},
        }),
        NafaqahWriteRefusal.noProvider,
      );
      expect(
        nafaqahWriteRefusalOf({
          'status': 'error',
          'status_code': 409,
          'detail': {'code': 'ledger_would_be_overpaid'},
        }),
        NafaqahWriteRefusal.ledgerWouldBeOverpaid,
      );
    });

    test('anything else is not a Nafaqah refusal', () {
      expect(nafaqahWriteRefusalOf(const PostgrestException(message: 'Forbidden', code: '42501')), isNull);
      expect(nafaqahWriteRefusalOf(const PostgrestException(message: 'bad', code: '22023')), isNull);
      expect(nafaqahWriteRefusalOf(const NafaqahApiException('overpayment', '')), isNull);
      expect(nafaqahWriteRefusalOf({'status': 'success', 'detail': {'code': 'no_provider'}}), isNull);
      expect(nafaqahWriteRefusalOf(Exception('offline')), isNull);
      expect(nafaqahWriteRefusalOf(null), isNull);
    });
  });

  testWidgets('explanations are localized in en, ar and ur', (tester) async {
    final texts = <String, List<String?>>{};
    for (final lang in ['en', 'ar', 'ur']) {
      await tester.pumpWidget(Localizations(
        locale: Locale(lang),
        delegates: const [AppLocalizationsDelegate(), DefaultWidgetsLocalizations.delegate],
        child: Builder(builder: (context) {
          texts[lang] = [
            nafaqahWriteErrorText(context, const NafaqahApiException('ledger_would_be_overpaid', '')),
            nafaqahWriteErrorText(context, const NafaqahApiException('no_provider', '')),
            nafaqahWriteErrorText(context, Exception('offline')),
          ];
          return const SizedBox();
        }),
      ));
      await tester.pump();
    }
    expect(texts['en']![0], startsWith('Not saved: the husband has already repaid'));
    expect(texts['en']![1], contains('no Nafaqah provider'));
    expect(texts['en']![2], isNull);
    expect(texts['ar']![0], startsWith('لم يُحفظ'));
    expect(texts['ur']![1], contains('نفقہ دینے والا'));
  });

  // FABLE2-APP-03 (app side): a 409 {"detail": {"code": ...}} from the chat or
  // receipt commit reaches the screens as a localized Nafaqah refusal and is
  // not queued for a replay that would be refused again.
  group('chat and receipt commits refused with 409', () {
    BaseApiClient refusing(String code) => BaseApiClient(
          client: MockClient((request) async => http.Response(
                jsonEncode({'detail': {'code': code, 'message': 'refused'}}),
                409,
                headers: {'content-type': 'application/json'},
              )),
          authTokenProvider: () => 'jwt',
        );

    for (final entry in {
      'no_provider': NafaqahWriteRefusal.noProvider,
      'ledger_would_be_overpaid': NafaqahWriteRefusal.ledgerWouldBeOverpaid,
    }.entries) {
      test('chat commit: ${entry.key}', () async {
        final res = await ChatApiClient(baseClient: refusing(entry.key)).postChatTransaction(
          message: 'groceries 120',
          householdId: 'h1',
          previewOnly: false,
          nafaqahClass: 'wife_reimbursable',
        );
        expect(nafaqahWriteRefusalOf(res), entry.value);
        expect(SyncWorker.shouldQueueAfterOnlineFailure(res), isFalse);
      });

      test('receipt commit: ${entry.key}', () async {
        final res = await ReceiptApiClient(baseClient: refusing(entry.key)).scanReceipt(
          imagesBase64: const ['aGk='],
          householdId: 'h1',
          previewOnly: false,
        );
        expect(nafaqahWriteRefusalOf(res), entry.value);
        expect(SyncWorker.shouldQueueAfterOnlineFailure(res), isFalse);
      });
    }
  });

  group('only the wife, the provider or an admin classifies', () {
    test('API code, current API message and database hint are recognised', () {
      expect(
        nafaqahWriteRefusalOf({'status': 'error', 'status_code': 403, 'detail': {'code': 'not_classifier'}}),
        NafaqahWriteRefusal.notClassifier,
      );
      expect(
        nafaqahWriteRefusalOf({
          'status': 'error',
          'status_code': 422,
          'detail': 'Only the husband or a wife can classify a family expense.',
          'message': 'Only the husband or a wife can classify a family expense.',
        }),
        NafaqahWriteRefusal.notClassifier,
      );
      expect(
        nafaqahWriteRefusalOf(const PostgrestException(message: 'refused', code: '42501', hint: 'nafaqah_classifier_only')),
        NafaqahWriteRefusal.notClassifier,
      );
    });

    testWidgets('the refusal is explained in en, ar and ur', (tester) async {
      final texts = <String, String?>{};
      for (final lang in ['en', 'ar', 'ur']) {
        await tester.pumpWidget(Localizations(
          locale: Locale(lang),
          delegates: const [AppLocalizationsDelegate(), DefaultWidgetsLocalizations.delegate],
          child: Builder(builder: (context) {
            texts[lang] = nafaqahWriteErrorText(context, const NafaqahApiException('not_classifier', ''));
            return const SizedBox();
          }),
        ));
        await tester.pump();
      }
      expect(texts['en'], contains('only the wife, the Nafaqah provider (husband) or an admin'));
      expect(texts['ar'], contains('المشرف'));
      expect(texts['ur'], contains('ایڈمن'));
    });
  });
}
