import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/settings/income_settings_card.dart';

void main() {
  testWidgets('IncomeSettingsCard renders initial configured income and enters edit mode', (tester) async {
    double savedValue = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncomeSettingsCard(
            initialIncome: 12000.0,
            onSaveIncome: (val) async {
              savedValue = val;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Monthly Salary / Income'), findsOneWidget);
    expect(find.text('12,000.00 SAR'), findsOneWidget);

    // Tap edit button
    final editButton = find.byIcon(Icons.edit_rounded);
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Verify text field and preset buttons appear
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('15,000 SAR'), findsOneWidget);

    // Tap 15,000 SAR preset
    await tester.tap(find.text('15,000 SAR'));
    await tester.pumpAndSettle();

    // Tap save button
    final saveButton = find.text('Save Income');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedValue, equals(15000.0));
  });
}
