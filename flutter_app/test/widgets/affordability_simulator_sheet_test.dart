import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/widgets/simulator/affordability_simulator_sheet.dart';

void main() {
  group('AffordabilitySimulatorSheet Widget Tests', () {
    testWidgets('Renders inputs, category selector, presets, and simulate CTA', (tester) async {
      final budgetProvider = BudgetProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate()],
            supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
            locale: Locale('en'),
            home: Scaffold(
              body: AffordabilitySimulatorSheet(
                defaultItem: 'AirPods Pro',
                defaultAmount: 950.0,
                defaultCategory: 'OPEX-SHOPPING',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title and description
      expect(find.text('Can I Afford This?'), findsWidgets);
      expect(find.text('AirPods Pro'), findsOneWidget);
      expect(find.text('950'), findsOneWidget);

      // Verify preset chips
      expect(find.text('+100'), findsOneWidget);
      expect(find.text('+500'), findsOneWidget);
      expect(find.text('+1,000'), findsOneWidget);

      // Verify simulate button exists
      expect(find.text('Simulate Purchase'), findsOneWidget);
    });

    testWidgets('Executes offline simulation and displays daily allowance impact and BNPL split', (tester) async {
      final budgetProvider = BudgetProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate()],
            supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
            locale: Locale('en'),
            home: Scaffold(
              body: AffordabilitySimulatorSheet(
                defaultItem: 'PlayStation 5',
                defaultAmount: 2400.0,
                defaultCategory: 'OPEX-ENTERTAINMENT',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap simulate button
      final simulateBtn = find.text('Simulate Purchase');
      expect(simulateBtn, findsOneWidget);
      await tester.tap(simulateBtn);
      await tester.pumpAndSettle();

      // Check that simulation result displays impact
      expect(find.textContaining('PlayStation 5 • SAR 2400.00'), findsOneWidget);
      expect(find.text('Current Daily'), findsOneWidget);
      expect(find.text('After Purchase'), findsOneWidget);

      // Verify Tabby/Tamara 4-month installment split appears
      expect(find.textContaining('Or split with Tabby/Tamara in 4 interest-free payments: 4 × SAR 600.00/mo'), findsOneWidget);

      // Verify Record Expense CTA appears
      expect(find.text('Record Expense'), findsOneWidget);
    });
  });
}
