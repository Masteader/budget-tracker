import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';

void main() {
  group('AccountCard Widget Tests', () {
    testWidgets('Renders surplus buffer correctly', (tester) async {
      const account = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Al Rajhi Salary',
        accountType: AccountType.bank,
        balance: 10000.0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountCard(
              account: account,
              committedBudgets: 6000.0,
              householdId: 'hh-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Al Rajhi Salary'), findsOneWidget);
      expect(find.text('SAR 10,000.00'), findsOneWidget);
      expect(find.textContaining('Surplus Buffer'), findsOneWidget);
      expect(find.text('Reconcile'), findsOneWidget);
      expect(find.text('Transfer Out'), findsOneWidget);
    });

    testWidgets('Renders deficit alert and quick transfer button', (tester) async {
      const account = Account(
        id: 'acc-2',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'STC Pay',
        accountType: AccountType.eWallet,
        balance: 500.0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountCard(
              account: account,
              committedBudgets: 1200.0,
              householdId: 'hh-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STC Pay'), findsOneWidget);
      expect(find.text('SAR 500.00'), findsOneWidget);
      expect(find.textContaining('Deficit'), findsWidgets);

      // Verify Quick Transfer button exists for deficit resolution
      expect(find.textContaining('⚡ Quick Transfer'), findsOneWidget);
      expect(find.textContaining('700.00'), findsWidgets);
    });
  });
}
