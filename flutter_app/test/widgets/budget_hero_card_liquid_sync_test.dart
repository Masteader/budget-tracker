import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/models/payday_outlook.dart';
import 'package:budget_tracker/widgets/dashboard/budget_hero_card.dart';

void main() {
  group('BudgetHeroCard & PaydayOutlook Physical Cash Sync Tests (Issue 2)', () {
    final now = DateTime.utc(2026, 11, 2, 12);
    final cycleStart = DateTime.utc(2026, 10, 27);
    final cycleEnd = DateTime.utc(2026, 11, 26);

    test('PaydayOutlook.compute synchronizes left with verified operatingCash and preserves halala invariant', () {
      // User scenario:
      // Rajhi account balance edited to 2,508.75 SAR + other accounts bringing total physical cash to 3,353.75 SAR.
      // Total spent = 5,641.65 SAR.
      // Recorded monthly income = 8,944.54 SAR.
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 4000.0,
          spentAmount: 3641.65,
          remainingAmount: 358.35,
          month: '2026-11-01',
          isActive: true,
        ),
        const Budget(
          id: 'b2',
          householdId: 'h1',
          categoryCode: 'OPEX-DINING',
          allocatedAmount: 2000.0,
          spentAmount: 2000.00,
          remainingAmount: 0.0,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      // Total spent across budgets = 5,641.65 SAR
      expect(budgets.fold<double>(0.0, (s, b) => s + b.spentAmount), 5641.65);

      final outlook = PaydayOutlook.compute(
        budgets: budgets,
        monthlyIncome: 8944.54,
        operatingCash: 3353.75, // Physical bank balance SSOT
        pendingCommitments: 1162.00,
        today: now,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      // 1. Left strictly reflects verified physical bank balance (3,353.75 SAR), NOT theoretical 3,302.89 SAR
      expect(outlook.left, 3353.75);
      expect(outlook.left, isNot(closeTo(3302.89, 0.01)));

      // 2. Base reflects dynamic cycle capacity = operatingCash + totalSpent = 3,353.75 + 5,641.65 = 8,995.40 SAR
      expect(outlook.base, closeTo(8995.40, 0.001));

      // 3. Halala precision invariant: left + totalSpent == base
      expect((outlook.left + outlook.totalSpent).toStringAsFixed(2), outlook.base.toStringAsFixed(2));

      // 4. afterCommitments = 3,353.75 - 1,162.00 = 2,191.75 SAR
      expect(outlook.afterCommitments, closeTo(2191.75, 0.001));
    });

    testWidgets('BudgetHeroCard displays verified physical bank balance (3,353.75) and adjusted capacity', (tester) async {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 4000.0,
          spentAmount: 5641.65,
          remainingAmount: -1641.65,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      const snapshot = OperatingCashSnapshot(
        householdId: 'h1',
        cycleKey: '2026-11',
        liquidHalalas: 335375, // 3,353.75 SAR
        pendingCommitmentsHalalas: 116200, // 1,162.00 SAR
        cycleIncomeHalalas: 894454, // 8,944.54 SAR
        accountsCount: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BudgetHeroCard(
                budgets: budgets,
                now: now,
                monthlyIncome: snapshot.cycleIncome,
                snapshot: snapshot,
                pendingCommitments: snapshot.pendingCommitments,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Big number displays verified physical cash: 3,353.75
      expect(find.text('3,353.75'), findsOneWidget);
      expect(find.text('3,302.89'), findsNothing);

      // Base headline displays 8,995 income capacity (3,353.75 + 5,641.65 = 8,995.40 rounded to 8,995)
      expect(find.textContaining('8,995'), findsOneWidget);

      // Commitments tip displays 2,191.75 after commitments
      expect(find.textContaining('2,191.75'), findsOneWidget);
      expect(find.textContaining('1,162.00'), findsOneWidget);
    });

    testWidgets('BudgetHeroCard renders 0.00 cash cleanly without reverting to income', (tester) async {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 4000.0,
          spentAmount: 1500.0,
          remainingAmount: 2500.0,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      const snapshot = OperatingCashSnapshot(
        householdId: 'h1',
        cycleKey: '2026-11',
        liquidHalalas: 0, // 0.00 SAR in bank
        pendingCommitmentsHalalas: 0,
        cycleIncomeHalalas: 1000000, // 10,000.00 SAR monthly income
        accountsCount: 1, // Bank account exists and is tracked!
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BudgetHeroCard(
                budgets: budgets,
                now: now,
                monthlyIncome: snapshot.cycleIncome,
                snapshot: snapshot,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Big number must display 0.00, NOT 8,500.00!
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('8,500.00'), findsNothing);
    });

    testWidgets('BudgetHeroCard renders overdraft negative balance cleanly with overspent verdict', (tester) async {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 4000.0,
          spentAmount: 1500.0,
          remainingAmount: 2500.0,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      const snapshot = OperatingCashSnapshot(
        householdId: 'h1',
        cycleKey: '2026-11',
        liquidHalalas: -25000, // -250.00 SAR in bank
        pendingCommitmentsHalalas: 0,
        cycleIncomeHalalas: 1000000, // 10,000.00 SAR monthly income
        accountsCount: 1, // Bank account exists and is tracked!
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BudgetHeroCard(
                budgets: budgets,
                now: now,
                monthlyIncome: snapshot.cycleIncome,
                snapshot: snapshot,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Overspent headline: Over by SAR 250.00
      expect(find.textContaining('Over by SAR 250.00'), findsOneWidget);
      expect(find.text('-250.00'), findsOneWidget);
      expect(find.text('8,500.00'), findsNothing);
    });
  });
}
