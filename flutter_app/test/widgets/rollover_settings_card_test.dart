import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/settings/rollover_settings_card.dart';

void main() {
  group('RolloverSettingsCard Widget Tests', () {
    testWidgets('Renders all 3 options, accumulated savings, and triggers onSaveRule', (tester) async {
      String? savedRule;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RolloverSettingsCard(
                initialRule: 'send_to_savings',
                accumulatedSavings: 350.0,
                onSaveRule: (rule) async {
                  savedRule = rule;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title and badge
      expect(find.text('Budget Rollover Policy'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);

      // Verify accumulated savings banner
      expect(find.text('Accumulated Surplus in Savings'), findsOneWidget);
      expect(find.text('SAR 350.00'), findsOneWidget);

      // Verify 3 option titles exist
      expect(find.text('Send All to Savings'), findsOneWidget);
      expect(find.text('Rollover to Same Categories'), findsOneWidget);
      expect(find.text('Fresh Start (Zero Carryover)'), findsOneWidget);

      // Verify recommended badge
      expect(find.text('Recommended Default'), findsOneWidget);

      // Switch to Rollover to Same Categories
      await tester.tap(find.text('Rollover to Same Categories'));
      await tester.pumpAndSettle();

      // Verify badge updated to Carryover
      expect(find.text('Carryover'), findsOneWidget);

      // Tap Save Rollover Policy
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Rollover Policy');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify callback was invoked with new rule
      expect(savedRule, 'rollover_to_categories');
    });

    testWidgets('Renders fresh_start selection and saves', (tester) async {
      String? savedRule;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RolloverSettingsCard(
                initialRule: 'rollover_to_categories',
                accumulatedSavings: 0.0,
                onSaveRule: (rule) async {
                  savedRule = rule;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Fresh Start
      await tester.tap(find.text('Fresh Start (Zero Carryover)'));
      await tester.pumpAndSettle();

      expect(find.text('Fresh Start'), findsWidgets);

      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Rollover Policy');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedRule, 'fresh_start');
    });
  });
}
