import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/widgets/onboarding/app_setup_tutor_dialog.dart';

import '../support/localized_app.dart';

const _admin = TutorViewer(isAdmin: true);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('an admin walks the five setup steps with their buttons', (tester) async {
    await tester.pumpWidget(localizedApp(
      const AppSetupTutorDialog(householdId: 'h1', viewer: _admin),
      lang: 'en',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Payday & Income'), findsOneWidget);
    expect(find.text('Set Payday'), findsOneWidget);
    expect(find.text('Record Income'), findsOneWidget);

    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();
    expect(find.text('Operating Accounts vs. Savings Vaults'), findsOneWidget);
    expect(find.text('Set Up Bank & Savings'), findsOneWidget);

    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();
    expect(find.text('Envelope Budgeting & Joining Mid-Cycle'), findsOneWidget);
    expect(find.text('Configure Envelopes'), findsOneWidget);

    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();
    expect(find.text('Living Model: Family & Roommates'), findsOneWidget);
    expect(find.text('Members & Admins'), findsOneWidget);

    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();
    expect(find.text('Three Ways to Record'), findsOneWidget);
    expect(find.text('Start Using Qawam Money'), findsOneWidget);
    expect(find.text('Finish & Start Tracking'), findsOneWidget);
  });

  testWidgets('renders localized in Arabic', (tester) async {
    await tester.pumpWidget(localizedApp(
      const AppSetupTutorDialog(householdId: 'h1', viewer: _admin),
      lang: 'ar',
    ));
    await tester.pumpAndSettle();

    expect(find.text('يوم الراتب والدخل'), findsOneWidget);
    expect(find.text('تحديد يوم الراتب'), findsOneWidget);
    expect(find.text('الخطوة التالية'), findsOneWidget);
  });

  testWidgets('the stage 1 button closes the tutor with the payday action', (tester) async {
    TutorAction? closedWith;
    var closed = false;
    await tester.pumpWidget(localizedApp(
      AppSetupTutorDialog(
        householdId: 'h1',
        viewer: _admin,
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
