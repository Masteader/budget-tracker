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

    // UX-28: the core promise first, then the household rules, then the
    // ways to record an expense.
    expect(find.text("Know what's left until payday"), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("Wife expenses, allowance & roommate settling"), findsOneWidget);
    expect(find.textContaining('50/50'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Voice & Dialect Chat'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('AI Invoice & ZATCA Scanner'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Recurring Bills & Installments'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Get Started
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
