import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/widgets/dashboard/recurring_bills_card.dart';

void main() {
  group('RecurringBillsCard Widget Tests', () {
    testWidgets('Renders recurring bills with reserved amounts and filter tabs', (tester) async {
      final billsProvider = RecurringBillsProvider();
      final txProvider = TransactionProvider();
      final budgetProvider = BudgetProvider();

      const summary = RecurringBillsSummary(
        cycleKey: '2026-10',
        cycleLabel: 'October 2026',
        totalRecurringMonthly: 4350.0,
        paidThisCycle: 350.0,
        reservedAmount: 4000.0,
        bills: [
          RecurringBillItem(
            merchant: 'Housing Rent',
            normalizedMerchant: 'housing rent',
            categoryCode: 'OPEX-UTILITIES',
            subCode: 'rent',
            averageAmount: 4000.0,
            expectedDayOfMonth: 1,
            status: 'UPCOMING',
          ),
          RecurringBillItem(
            merchant: 'Saudi Electricity Co.',
            normalizedMerchant: 'saudi electricity co.',
            categoryCode: 'OPEX-UTILITIES',
            subCode: 'electricity',
            averageAmount: 350.0,
            expectedDayOfMonth: 28,
            status: 'PAID_THIS_CYCLE',
          ),
        ],
      );

      billsProvider.setSummaryForTesting(summary, householdId: 'hh_test');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RecurringBillsProvider>.value(value: billsProvider),
            ChangeNotifierProvider<TransactionProvider>.value(value: txProvider),
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate()],
            supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
            locale: Locale('en'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecurringBillsCard(householdId: 'hh_test'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and bills
      expect(find.text('Recurring Bills & Reserves'), findsOneWidget);
      expect(find.text('Housing Rent'), findsOneWidget);
      expect(find.text('Saudi Electricity Co.'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);

      // Verify filter chips
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Pending (1)'), findsOneWidget);
      expect(find.text('Paid (1)'), findsOneWidget);

      // Tap 'Pending (1)' chip
      await tester.tap(find.text('Pending (1)'));
      await tester.pumpAndSettle();

      // Only Housing Rent should remain
      expect(find.text('Housing Rent'), findsOneWidget);
      expect(find.text('Saudi Electricity Co.'), findsNothing);
    });

    testWidgets('Renders empty/configure card when no recurring bills are configured', (tester) async {
      final billsProvider = RecurringBillsProvider();
      final txProvider = TransactionProvider();
      final budgetProvider = BudgetProvider();

      const summary = RecurringBillsSummary(
        cycleKey: '2026-10',
        cycleLabel: 'October 2026',
        totalRecurringMonthly: 0.0,
        paidThisCycle: 0.0,
        reservedAmount: 0.0,
        bills: [],
      );

      billsProvider.setSummaryForTesting(summary, householdId: 'hh_test');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RecurringBillsProvider>.value(value: billsProvider),
            ChangeNotifierProvider<TransactionProvider>.value(value: txProvider),
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate()],
            supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
            locale: Locale('en'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecurringBillsCard(householdId: 'hh_test'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Recurring Bills & Reserves'), findsOneWidget);
      expect(find.text('Configure'), findsOneWidget);
    });
  });
}
