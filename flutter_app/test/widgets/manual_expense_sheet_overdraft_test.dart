import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

void main() {
  const testAccountSar = Account(
    id: 'acc1',
    householdId: 'h1',
    ownerUserId: 'u1',
    name: 'Al Rajhi Current',
    accountType: AccountType.bank,
    balance: 300.0,
    currency: 'SAR',
  );

  const testAccountUsd = Account(
    id: 'acc2',
    householdId: 'h1',
    ownerUserId: 'u1',
    name: 'Chase Checking',
    accountType: AccountType.bank,
    balance: 300.0,
    currency: 'USD',
  );

  group('ManualExpenseSheet Overdraft Guard Widget Tests', () {
    Future<void> openSheet(
      WidgetTester tester, {
      required double initialAmount,
      required Account account,
      required Future<void> Function(Map<String, dynamic> row) insertRow,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(localizedApp(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ManualExpenseSheet(
                  householdId: 'h1',
                  initialMerchant: 'Panda Hypermarket',
                  initialAmount: initialAmount,
                  loadMembers: (_) async => [
                    {'id': 'u1', 'display_name': 'Tester', 'role': 'admin', 'financial_role': 'provider'}
                  ],
                  loadAccounts: (_) async => [account],
                  currentUserId: () => 'u1',
                  insertRow: insertRow,
                  loadNafaqah: (_) async => const NafaqahSummary(
                    mode: 'not_family',
                    callerUserId: 'u1',
                    callerRole: 'admin',
                    husbandName: 'Tester',
                    canSetProvider: true,
                    wives: [],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      lang: 'en',
      scaffold: false,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('SAR overdraft shows dialog; confirming inserts the row', (tester) async {
      bool insertCalled = false;

      await openSheet(
        tester,
        initialAmount: 500.0, // Account only has 300.0 SAR
        account: testAccountSar,
        insertRow: (row) async {
          insertCalled = true;
        },
      );

      final saveButton = find.byIcon(Icons.check_rounded);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(insertCalled, isFalse);

      // Confirm the dialog
      final confirmBtn = find.byKey(const ValueKey('overdraft_confirm_button'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(insertCalled, isTrue, reason: 'Insert must proceed after soft confirmation');
    });

    testWidgets('SAR overdraft shows dialog; cancelling aborts insert', (tester) async {
      bool insertCalled = false;

      await openSheet(
        tester,
        initialAmount: 500.0, // Account only has 300.0 SAR
        account: testAccountSar,
        insertRow: (row) async {
          insertCalled = true;
        },
      );

      final saveButton = find.byIcon(Icons.check_rounded);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Dialog appears
      expect(find.byType(AlertDialog), findsOneWidget);

      // Cancel
      final cancelBtn = find.byKey(const ValueKey('overdraft_cancel_button'));
      expect(cancelBtn, findsOneWidget);
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      expect(insertCalled, isFalse);
      expect(find.byType(ManualExpenseSheet), findsOneWidget);
    });

    testWidgets('USD account produces no dialog and inserts directly even if amount exceeds balance', (tester) async {
      bool insertCalled = false;

      await openSheet(
        tester,
        initialAmount: 500.0, // Account only has 300.0 USD
        account: testAccountUsd,
        insertRow: (row) async {
          insertCalled = true;
        },
      );

      final saveButton = find.byIcon(Icons.check_rounded);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // No dialog for non-SAR accounts
      expect(find.byType(AlertDialog), findsNothing);
      expect(insertCalled, isTrue);
    });
  });
}
