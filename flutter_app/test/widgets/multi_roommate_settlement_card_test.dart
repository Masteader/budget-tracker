import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';

import '../support/fake_settings_supabase.dart';

void main() {
  // A settlement reloads the summary: answered in memory, never over the network.
  setUp(() {
    final original = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = original);
  });

  const testSummary = SettlementV2Summary(
    mode: 'multi_roommate',
    pairwiseDebts: [
      PairwiseDebt(
        fromId: 'omar',
        toId: 'ahmed',
        fromName: 'Omar',
        toName: 'Ahmed',
        amount: 100.0,
      ),
      PairwiseDebt(
        fromId: 'ibrahim',
        toId: 'ahmed',
        fromName: 'Ibrahim',
        toName: 'Ahmed',
        amount: 200.0,
      ),
      PairwiseDebt(
        fromId: 'tariq',
        toId: 'omar',
        fromName: 'Tariq',
        toName: 'Omar',
        amount: 200.0,
      ),
    ],
    simplifiedDebts: [
      SimplifiedDebt(
        fromId: 'tariq',
        toId: 'ahmed',
        fromName: 'Tariq',
        toName: 'Ahmed',
        amount: 100.0,
      ),
      SimplifiedDebt(
        fromId: 'tariq',
        toId: 'omar',
        fromName: 'Tariq',
        toName: 'Omar',
        amount: 100.0,
      ),
      SimplifiedDebt(
        fromId: 'ibrahim',
        toId: 'ahmed',
        fromName: 'Ibrahim',
        toName: 'Ahmed',
        amount: 200.0,
      ),
    ],
    roommateBalances: {
      'ahmed': 300.0,
      'omar': 100.0,
      'ibrahim': -200.0,
      'tariq': -200.0,
    },
  );

  testWidgets('MultiRoommateSettlementCard renders simplified debts and balances by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh-flat-1',
            summary: testSummary,
          ),
        ),
      ),
    );

    expect(find.text('Roommate Settlements'), findsOneWidget);
    expect(find.text('Fewest transfers'), findsOneWidget);
    expect(find.textContaining('Ahmed'), findsWidgets);
    expect(find.textContaining('Tariq'), findsWidgets);
    expect(find.text('+SAR 300.00'), findsOneWidget);
    expect(find.text('-SAR 200.00'), findsWidgets);
  });

  testWidgets('MultiRoommateSettlementCard toggles between simplified and pairwise debts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh-flat-1',
            summary: testSummary,
          ),
        ),
      ),
    );

    // Toggle debt simplification off
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Now in Pairwise mode
    expect(find.textContaining('Omar owes Ahmed'), findsOneWidget);
  });

  testWidgets('MultiRoommateSettlementCard opens settle payment bottom sheet and confirms', (tester) async {
    bool callbackCalled = false;
    ReimbursementRecordRequest? capturedRequest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh-flat-1',
            summary: testSummary,
            onSettled: () {
              callbackCalled = true;
            },
            recordPayment: (req) async {
              capturedRequest = req;
              return {'status': 'success'};
            },
          ),
        ),
      ),
    );

    // Tap first Settle button
    final settleButtons = find.widgetWithText(ElevatedButton, 'Settle');
    expect(settleButtons, findsWidgets);
    await tester.tap(settleButtons.first);
    await tester.pumpAndSettle();

    // Bottom sheet should be visible
    expect(find.text('Record Roommate Settlement'), findsOneWidget);
    expect(find.text('Record Settlement Payment'), findsOneWidget);

    // Tap confirm
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(callbackCalled, isTrue);
    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.notes, roommateSettlementNote(from: 'Tariq', to: 'Ahmed', method: 'stc_pay'));
  });

  testWidgets('MultiRoommateSettlementCard stores a language-neutral note from an Arabic screen', (tester) async {
    ReimbursementRecordRequest? capturedRequest;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh-flat-1',
            summary: testSummary,
            onSettled: () {},
            recordPayment: (req) async {
              capturedRequest = req;
              return {'status': 'success'};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap first Settle button (تسوية in Arabic)
    final settleButtons = find.widgetWithText(ElevatedButton, 'تسوية');
    expect(settleButtons, findsWidgets);
    await tester.tap(settleButtons.first);
    await tester.pumpAndSettle();

    // Tap confirm in bottom sheet (تسجيل دفعة التسوية)
    final confirmButtons = find.widgetWithText(ElevatedButton, 'تسجيل دفعة التسوية');
    expect(confirmButtons, findsOneWidget);
    await tester.tap(confirmButtons);
    await tester.pumpAndSettle();

    expect(capturedRequest, isNotNull);
    // The same note whatever language the payer uses: it is read by everyone.
    expect(capturedRequest!.notes, roommateSettlementNote(from: 'Tariq', to: 'Ahmed', method: 'stc_pay'));
  });

  group('the stored note (S10)', () {
    Future<ReimbursementRecordRequest?> settle(WidgetTester tester, String from, String to, {String lang = 'en', String? chip}) async {
      ReimbursementRecordRequest? captured;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh',
            currentUserId: 'me',
            onSettled: () {},
            summary: SettlementV2Summary(
              mode: 'multi_roommate',
              simplifiedDebts: [SimplifiedDebt(fromId: 'x', toId: 'y', fromName: from, toName: to, amount: 10)],
            ),
            recordPayment: (req) async {
              captured = req;
              return const {'status': 'success'};
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final l = AppLocalizations(Locale(lang));
      await tester.tap(find.widgetWithText(ElevatedButton, l.get('settle_now')));
      await tester.pumpAndSettle();
      if (chip != null) {
        await tester.tap(find.text(l.get(chip)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(ElevatedButton, l.get('settle_record_payment')));
      await tester.pumpAndSettle();
      return captured;
    }

    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('$lang: names and the method code, the same in every language', (tester) async {
        final req = await settle(tester, 'Omar', 'Sami', lang: lang, chip: 'pay_method_cash');
        expect(req!.notes, roommateSettlementNote(from: 'Omar', to: 'Sami', method: 'cash'));
        expect(req.paymentMethod, 'cash');
      });
    }

    testWidgets('a name that looks like a placeholder is stored as written', (tester) async {
      final req = await settle(tester, '{to}', 'Omar');
      expect(req!.notes, roommateSettlementNote(from: '{to}', to: 'Omar', method: 'stc_pay'));
      expect(req.notes, contains('{to}'));
    });

    testWidgets('Arabic names stay searchable in the note', (tester) async {
      final req = await settle(tester, 'عمر', 'سامي', lang: 'ar');
      expect(req!.notes, contains('عمر'));
      expect(req.notes, contains('سامي'));
    });
  });

  group('the reload after a settlement (B4)', () {
    const debt = SettlementV2Summary(
      mode: 'multi_roommate',
      simplifiedDebts: [SimplifiedDebt(fromId: 'x', toId: 'y', fromName: 'Faisal', toName: 'Imran', amount: 10)],
    );

    testWidgets('a failed reload offers Retry, never the debt just settled', (tester) async {
      final api = FakeSettingsApi()
        ..failSettlement = true
        ..settlement = const SettlementV2Summary(mode: 'multi_roommate');
      ApiService.instance = api;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh',
            currentUserId: 'me',
            summary: debt,
            recordPayment: (_) async => const {'status': 'success'},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final l = AppLocalizations(const Locale('en'));
      await tester.tap(find.widgetWithText(ElevatedButton, l.get('settle_now')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, l.get('settle_record_payment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('roommate_debt_title')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, l.get('settle_now')), findsNothing);
      expect(find.text(l.get('roles_retry')), findsOneWidget);

      api.failSettlement = false;
      await tester.tap(find.text(l.get('roles_retry')));
      await tester.pumpAndSettle();
      expect(find.text(l.get('settle_all_settled')), findsOneWidget);
    });
  });

  group('what the parent passes (B4)', () {
    const debt = SettlementV2Summary(
      mode: 'multi_roommate',
      simplifiedDebts: [SimplifiedDebt(fromId: 'x', toId: 'y', fromName: 'Faisal', toName: 'Imran', amount: 10)],
    );
    const settled = SettlementV2Summary(mode: 'multi_roommate');

    Widget host(SettlementV2Summary summary, {String householdId = 'hh'}) => MaterialApp(
          home: Scaffold(body: MultiRoommateSettlementCard(householdId: householdId, currentUserId: 'me', summary: summary)),
        );

    testWidgets('a different summary replaces the card\'s', (tester) async {
      await tester.pumpWidget(host(debt));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roommate_debt_title')), findsOneWidget);
      await tester.pumpWidget(host(settled));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roommate_debt_title')), findsNothing);
    });

    testWidgets('a rebuild with the same summary does not', (tester) async {
      await tester.pumpWidget(host(debt));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpWidget(host(debt));
      await tester.pumpAndSettle();
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse, reason: 'the same state, not a remount');
    });
  });

  testWidgets('MultiRoommateSettlementCard displays all settled when no debts', (tester) async {
    const emptySummary = SettlementV2Summary(
      mode: 'multi_roommate',
      pairwiseDebts: [],
      simplifiedDebts: [],
      roommateBalances: {},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MultiRoommateSettlementCard(
            householdId: 'hh-flat-1',
            summary: emptySummary,
          ),
        ),
      ),
    );

    expect(find.text('All Settled'), findsOneWidget);
    expect(find.text('No pending roommate debts. Everyone is squared away!'), findsOneWidget);
  });
}
