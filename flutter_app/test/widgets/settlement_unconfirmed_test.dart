// A settlement whose outcome is unknown must not invite a second tap: no claim it
// failed, no sheet with the same amount ready, and the balance reloaded. A refusal
// the server did answer stays "not recorded" with the sheet open to correct.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/payer_account.dart';

import '../support/fake_settings_supabase.dart';
import '../support/localized_app.dart';

const _noAnswer = ApiRequestException('timed out', noResponse: true);
const _serverFault = ApiRequestException('boom', statusCode: 500);
const _refusal = ApiRequestException('no', statusCode: 403);

const _debt = SettlementV2Summary(
  mode: 'multi_roommate',
  simplifiedDebts: [SimplifiedDebt(fromId: 'x', toId: 'y', fromName: 'Faisal', toName: 'Imran', amount: 10)],
);

NafaqahSummary _family() => const NafaqahSummary(
      mode: 'family_nafaqah',
      callerRole: 'husband',
      callerUserId: 'h',
      cycleKey: '2026-11',
      canRecordReimbursement: true,
      canSetAllowance: true,
      wives: [
        NafaqahWife(
          id: 'w',
          displayName: 'Noura',
          reimbursement: ReimbursementBalance(grossAdvanced: 350, outstanding: 350),
          allowance: AllowanceStatus(cycleKey: '2026-11', isSet: true, allocated: 1000, spent: 400, remaining: 600),
        ),
      ],
    );

void main() {
  late FakeSettingsApi api;

  setUp(() {
    final original = ApiService.instance;
    api = FakeSettingsApi()..settlement = const SettlementV2Summary(mode: 'multi_roommate');
    ApiService.instance = api;
    addTearDown(() => ApiService.instance = original);
  });

  group('roommate settlement', () {
    Future<int Function()> settleFailing(WidgetTester tester, Object error, {String lang = 'en'}) async {
      var settled = 0;
      await tester.pumpWidget(localizedApp(
        MultiRoommateSettlementCard(
          householdId: 'hh',
          currentUserId: 'me',
          summary: _debt,
          onSettled: () => settled++,
          recordPayment: (_) async => throw error,
        ),
        lang: lang,
      ));
      await tester.pumpAndSettle();
      final l = AppLocalizations(Locale(lang));
      await tester.tap(find.widgetWithText(ElevatedButton, l.get('settle_now')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, l.get('settle_record_payment')));
      await tester.pumpAndSettle();
      return () => settled;
    }

    for (final lang in ['en', 'ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));

      testWidgets('$lang: no answer closes the sheet, says to check, and reloads', (tester) async {
        final settled = await settleFailing(tester, _noAnswer, lang: lang);
        expect(find.text(l.get('settle_unconfirmed_msg')), findsOneWidget);
        expect(find.text(l.get('settle_unconfirmed_title')), findsOneWidget);
        expect(find.text(l.get('settle_record_failed_msg')), findsNothing, reason: 'it may be recorded');
        expect(find.text(l.get('settle_recorded_title')), findsNothing, reason: 'it may not be');
        expect(find.widgetWithText(ElevatedButton, l.get('settle_record_payment')), findsNothing, reason: 'the sheet closed');
        expect(settled(), 1);
        expect(api.settlementCallCount, 1, reason: 'the card reloads what the server holds');
        expect(find.byKey(const Key('roommate_debt_title')), findsNothing, reason: 'the server says nothing is owed');
      });

      testWidgets('$lang: a refusal keeps the sheet open and says not recorded', (tester) async {
        final settled = await settleFailing(tester, _refusal, lang: lang);
        expect(find.text(l.get('settle_record_failed_msg')), findsOneWidget);
        expect(find.text(l.get('settle_unconfirmed_msg')), findsNothing);
        expect(find.widgetWithText(ElevatedButton, l.get('settle_record_payment')), findsOneWidget);
        expect(settled(), 0);
        expect(api.settlementCallCount, 0);
      });
    }

    testWidgets('a server fault is treated like no answer', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      final settled = await settleFailing(tester, _serverFault);
      expect(find.text(l.get('settle_unconfirmed_msg')), findsOneWidget);
      expect(settled(), 1);
    });

    testWidgets('an error that is not from the API keeps today\'s message', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      final settled = await settleFailing(tester, StateError('bug'));
      expect(find.text(l.get('settle_record_failed_msg')), findsOneWidget);
      expect(settled(), 0);
    });

    testWidgets('an unknown outcome with the reload failing offers Retry, not the debt', (tester) async {
      api.failSettlement = true;
      final l = AppLocalizations(const Locale('en'));
      await settleFailing(tester, _noAnswer);
      expect(find.byKey(const Key('roommate_debt_title')), findsNothing);
      expect(find.text(l.get('roles_retry')), findsOneWidget);
    });
  });

  group('family reimbursement', () {
    Future<int Function()> reimburseFailing(WidgetTester tester, Object error, {String lang = 'en'}) async {
      var reimbursed = 0;
      await tester.pumpWidget(withPayerAccount(localizedApp(
        FamilyReimbursementCard(
          householdId: 'hh',
          summary: _family(),
          onReimbursed: () => reimbursed++,
          recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId, required String accountId, required String requestKey, String? wifeAccountId}) async => throw error,
        ),
        lang: lang,
      )));
      await tester.pumpAndSettle();
      final l = AppLocalizations(Locale(lang));
      await tester.tap(find.text(l.get('reimburse_wife')));
      await tester.pumpAndSettle();
      await pickPayerAccount(tester);
      await tester.ensureVisible(find.text(l.get('settle_record_payment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.get('settle_record_payment')));
      await tester.pumpAndSettle();
      return () => reimbursed;
    }

    for (final lang in ['en', 'ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));

      // Review R1-06: the sheet stays with what it sent and its key, offers a safe
      // retry, and the card reloads.
      testWidgets('$lang: no answer keeps the sheet with a safe retry, and reloads', (tester) async {
        final reimbursed = await reimburseFailing(tester, const NafaqahApiException('network', 'timed out', noResponse: true), lang: lang);
        expect(find.text(l.get('repay_unconfirmed_hold')), findsOneWidget);
        expect(find.text(l.get('settle_record_failed_msg')), findsNothing);
        expect(find.text(l.get('try_again')), findsOneWidget, reason: 'the sheet stays open');
        expect(reimbursed(), 1);
      });
    }

    testWidgets('a server fault is treated like no answer', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      final reimbursed = await reimburseFailing(tester, const NafaqahApiException('network', 'boom', statusCode: 500));
      expect(find.text(l.get('repay_unconfirmed_hold')), findsOneWidget);
      expect(reimbursed(), 1);
    });

    testWidgets('a refusal keeps the sheet open and says why', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      final reimbursed = await reimburseFailing(tester, const NafaqahApiException('forbidden', 'no', statusCode: 403));
      expect(find.text(l.get('repay_err_forbidden')), findsOneWidget);
      expect(find.text(l.get('repay_unconfirmed_hold')), findsNothing);
      expect(find.text(l.get('settle_record_payment')), findsOneWidget);
      expect(reimbursed(), 0);
    });
  });
}
