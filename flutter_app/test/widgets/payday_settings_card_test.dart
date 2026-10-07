import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/settings/payday_settings_card.dart';

void main() {
  group('PaydaySettingsCard Widget Tests', () {
    testWidgets('Renders current payday and preset chips', (tester) async {
      int? changedDay;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaydaySettingsCard(
                initialPayday: 27,
                onSavePayday: (day) async {
                  changedDay = day;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title and badge
      expect(find.text('Salary & Payday Cycle'), findsOneWidget);
      expect(find.text('27th of month'), findsOneWidget);

      // Verify preset chips exist
      expect(find.text('27th (Govt / Standard)'), findsOneWidget);
      expect(find.text('1st (Calendar Month)'), findsOneWidget);
      expect(find.text('25th'), findsOneWidget);

      // Tap 1st preset chip
      await tester.tap(find.text('1st (Calendar Month)'));
      await tester.pumpAndSettle();

      // Verify badge updated to 1st
      expect(find.text('1st of month'), findsOneWidget);

      // Tap Save Payday
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Payday');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify onSavePayday called with 1
      expect(changedDay, 1);
    });
  });
}
