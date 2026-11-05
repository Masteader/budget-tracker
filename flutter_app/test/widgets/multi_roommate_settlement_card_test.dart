import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';

void main() {
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
    expect(capturedRequest!.notes, 'Tariq paid Ahmed via STC Pay');
  });

  testWidgets('MultiRoommateSettlementCard records settlement note in Arabic', (tester) async {
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
    expect(capturedRequest!.notes, 'Tariq دفع لـ Ahmed عبر STC Pay');
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
