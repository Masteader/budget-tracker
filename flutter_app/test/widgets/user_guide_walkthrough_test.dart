import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/widgets/onboarding/user_guide_walkthrough_dialog.dart';

void main() {
  testWidgets('UserGuideWalkthroughDialog displays 5 steps with next and skip', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserGuideWalkthroughDialog(
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    // Initial step 1: Scanner
    expect(find.text('AI Invoice & ZATCA Scanner'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Tap Next through the cards
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Voice & Dialect Chat'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Salary Cycles & Payday (27th)'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Recurring Bills & Installments'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Household & 2D Partner Split'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Get Started
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
