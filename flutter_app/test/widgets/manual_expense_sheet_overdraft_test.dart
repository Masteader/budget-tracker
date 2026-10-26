import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testAccount = Account(
    id: 'acc1',
    householdId: 'h1',
    ownerUserId: 'u1',
    name: 'Al Rajhi Current',
    accountType: AccountType.bank,
    balance: 300.0,
  );

  group('Zero-Balance Overdraft Guard Logic', () {
    test('detects overdraft when expense amount exceeds account balance', () {
      bool isOverdraft(double amount, Account acc) {
        return amount > acc.balance;
      }

      expect(isOverdraft(500.0, testAccount), isTrue);
      expect(isOverdraft(300.0, testAccount), isFalse);
      expect(isOverdraft(100.0, testAccount), isFalse);
    });
  });

  group('ManualExpenseSheet Overdraft Guard Widget Tests', () {
    Future<void> openSheet(
      WidgetTester tester, {
      required double initialAmount,
      required Future<void> Function(Map<String, dynamic> row) insertRow,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
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
                    loadAccounts: (_) async => [testAccount],
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
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('blocks expense saving when amount exceeds available account balance', (tester) async {
      bool insertCalled = false;

      await openSheet(
        tester,
        initialAmount: 500.0, // Account only has 300.0
        insertRow: (row) async {
          insertCalled = true;
        },
      );

      final saveButton = find.byIcon(Icons.check_rounded);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(insertCalled, isFalse, reason: 'Insert must be blocked by overdraft guard');
      expect(find.byType(ManualExpenseSheet), findsOneWidget, reason: 'Sheet remains open when overdraft occurs');
    });

    testWidgets('allows expense saving when amount is within available account balance', (tester) async {
      bool insertCalled = false;

      await openSheet(
        tester,
        initialAmount: 150.0, // Account has 300.0
        insertRow: (row) async {
          insertCalled = true;
        },
      );

      final saveButton = find.byIcon(Icons.check_rounded);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(insertCalled, isTrue, reason: 'Insert must proceed when balance is sufficient');
    });
  });
}
