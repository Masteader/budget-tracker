import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/widgets/accounts/reconcile_balance_dialog.dart';

void main() {
  group('ReconcileBalanceDialog Widget Tests', () {
    testWidgets('Renders current balance and variance calculations', (tester) async {
      const account = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Urpay Wallet',
        accountType: AccountType.eWallet,
        balance: 1500.0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReconcileBalanceDialog(account: account),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reconcile Balance'), findsOneWidget);
      expect(find.text('SAR 1,500.00'), findsOneWidget);
      expect(find.text('Update Balance'), findsOneWidget);

      // Enter a new balance of 1800.00
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, '1800.00');
      await tester.pumpAndSettle();

      // Variance of +300.00 should be displayed
      expect(find.textContaining('300.00'), findsOneWidget);
    });
  });
}
