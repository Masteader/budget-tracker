import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/widgets/onboarding/app_setup_tutor_dialog.dart';

import '../support/localized_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AppSetupTutorDialog renders 5-stage setup wizard with direct action buttons', (tester) async {
    await tester.pumpWidget(localizedApp(
      const AppSetupTutorDialog(householdId: 'h1'),
      lang: 'en',
    ));
    await tester.pumpAndSettle();

    // Stage 1 elements
    expect(find.text('1. Payday Cycle & Liquid Pool'), findsOneWidget);
    expect(find.text('Set Payday & Income'), findsOneWidget);

    // Tap Next
    final nextBtn = find.text('Next Step');
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // Stage 2 elements
    expect(find.text('2. Operating Accounts vs. Savings Vaults'), findsOneWidget);
    expect(find.text('Set Up Bank & Savings'), findsOneWidget);

    // Tap Next
    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();

    // Stage 3 elements
    expect(find.text('3. Envelope Budgeting & Mid-Cycle Joining'), findsOneWidget);
    expect(find.text('Configure Envelopes'), findsOneWidget);

    // Tap Next
    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();

    // Stage 4 elements
    expect(find.text('4. Living Model: Family & Roommates'), findsOneWidget);
    expect(find.text('Configure Household Mode'), findsOneWidget);

    // Tap Next
    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();

    // Stage 5 elements
    expect(find.text('5. Three Frictionless Ways to Record'), findsOneWidget);
    expect(find.text('Start Using Qawam Money'), findsOneWidget);
    expect(find.text('Finish & Start Tracking'), findsOneWidget);
  });

  testWidgets('AppSetupTutorDialog renders localized in Arabic', (tester) async {
    await tester.pumpWidget(localizedApp(
      const AppSetupTutorDialog(householdId: 'h1'),
      lang: 'ar',
    ));
    await tester.pumpAndSettle();

    expect(find.text('١. دورة الراتب والسيولة النقدية'), findsOneWidget);
    expect(find.text('تحديد يوم الراتب والدخل'), findsOneWidget);
    expect(find.text('الخطوة التالية'), findsOneWidget);
  });

  testWidgets('the stage 1 button closes the tutor with the payday action', (tester) async {
    TutorAction? closedWith;
    var closed = false;
    await tester.pumpWidget(localizedApp(
      AppSetupTutorDialog(
        householdId: 'h1',
        onClose: (action) {
          closed = true;
          closedWith = action;
        },
      ),
      lang: 'en',
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tutor_action_payday')));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(closedWith, TutorAction.payday);
  });
}
