import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';

void main() {
  testWidgets('FamilyReimbursementCard displays wife reimbursement debt and metrics', (tester) async {
    const summary = FamilyNafaqahSummary(
      wifeReimbursementOwed: 350.0,
      spentOnWife: 120.0,
      spentOnChildren: 450.0,
      familyGeneralTotal: 1200.0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FamilyReimbursementCard(
            householdId: 'hh-test-1',
            summary: summary,
          ),
        ),
      ),
    );

    expect(find.textContaining('350.00'), findsWidgets);
    expect(find.textContaining('450.00'), findsWidgets);
    expect(find.text('Reimburse Wife'), findsOneWidget);
  });

  testWidgets('FamilyReimbursementCard opens settlement dialog on tap', (tester) async {
    const summary = FamilyNafaqahSummary(
      wifeReimbursementOwed: 350.0,
      spentOnWife: 120.0,
      spentOnChildren: 450.0,
      familyGeneralTotal: 1200.0,
    );

    bool callbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyReimbursementCard(
            householdId: 'hh-test-1',
            summary: summary,
            onReimbursed: () {
              callbackCalled = true;
            },
            recordPayment: (_) async => {'status': 'success'},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reimburse Wife'));
    await tester.pumpAndSettle();

    // Dialog title
    expect(find.text('Settle Wife Reimbursement'), findsOneWidget);
    expect(find.text('Full (SAR 350.00)'), findsOneWidget);
    expect(find.text('Record Settlement Payment'), findsOneWidget);

    // Confirm settlement
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(callbackCalled, isTrue);
  });

  testWidgets('FamilyReimbursementCard renders all-settled state when owed is 0', (tester) async {
    const summary = FamilyNafaqahSummary(
      wifeReimbursementOwed: 0.0,
      spentOnWife: 120.0,
      spentOnChildren: 450.0,
      familyGeneralTotal: 1200.0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FamilyReimbursementCard(
            householdId: 'hh-test-1',
            summary: summary,
          ),
        ),
      ),
    );

    expect(find.text('All Settled'), findsOneWidget);
    expect(find.text('Reimburse Wife'), findsNothing);
  });
}
