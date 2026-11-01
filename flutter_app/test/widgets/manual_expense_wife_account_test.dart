import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import '../support/localized_app.dart';

void main() {
  const householdAccount = Account(
    id: 'acc-household-1',
    householdId: 'h-family',
    ownerUserId: 'u-husband',
    name: 'Household Bank Account',
    accountType: AccountType.bank,
    balance: 10.0,
    isSharedPool: true,
  );

  const familyNafaqah = NafaqahSummary(
    mode: 'family_nafaqah',
    callerUserId: 'u-wife',
    callerRole: 'wife',
    husbandName: 'Husband',
    canSetProvider: false,
    wives: [
      NafaqahWife(id: 'u-wife', displayName: 'Wife'),
    ],
  );

  Future<void> openSheet(
    WidgetTester tester, {
    required double amount,
    required Future<void> Function(Map<String, dynamic> row) insertRow,
    required String familyPayerChoice, // kWifePersonal or kWifeReimbursable
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final accountProvider = AccountProvider();
    accountProvider.setAccountsForTesting([householdAccount], householdId: 'h-family');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: accountProvider),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
        ],
        child: localizedApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ManualExpenseSheet(
                      householdId: 'h-family',
                      initialMerchant: 'Personal Store',
                      initialAmount: amount,
                      loadMembers: (_) async => [
                        {'id': 'u-husband', 'display_name': 'Husband', 'role': 'admin', 'financial_role': 'provider'},
                        {'id': 'u-wife', 'display_name': 'Wife', 'role': 'member', 'financial_role': 'spouse'},
                      ],
                      loadAccounts: (_) async => [householdAccount],
                      currentUserId: () => 'u-wife',
                      insertRow: insertRow,
                      loadNafaqah: (_) async => familyNafaqah,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          scaffold: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Select the wife payer option
    final optionFinder = find.byKey(ValueKey('nafaqah_option_$familyPayerChoice'));
    if (optionFinder.evaluate().isNotEmpty) {
      await tester.tap(optionFinder);
      await tester.pumpAndSettle();
    }

    // Tap Save
    final saveButton = find.byKey(const Key('save_expense_button'));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  group('ManualExpenseSheet Wife Expense Account Guard Tests', () {
    testWidgets('wife_personal expense allows save without overdraft and sets account_id to null', (tester) async {
      Map<String, dynamic>? capturedRow;

      await openSheet(
        tester,
        amount: 300.0,
        familyPayerChoice: kWifePersonal,
        insertRow: (row) async {
          capturedRow = row;
        },
      );

      // Verify no insufficient funds alert was shown
      expect(find.text('رصيد الحساب غير كافٍ'), findsNothing);
      expect(find.text('Insufficient Funds'), findsNothing);

      // Verify row was inserted with account_id == null
      expect(capturedRow, isNotNull);
      expect(capturedRow!['account_id'], isNull);
      expect(capturedRow!['amount'], equals(300.0));
      expect(capturedRow!['nafaqah_class'], equals('wife_personal'));
    });

    testWidgets('wife_reimbursable expense allows save without overdraft and sets account_id to null', (tester) async {
      Map<String, dynamic>? capturedRow;

      await openSheet(
        tester,
        amount: 300.0,
        familyPayerChoice: kWifeReimbursable,
        insertRow: (row) async {
          capturedRow = row;
        },
      );

      // Verify no insufficient funds alert was shown
      expect(find.text('رصيد الحساب غير كافٍ'), findsNothing);
      expect(find.text('Insufficient Funds'), findsNothing);

      // Verify row was inserted with account_id == null
      expect(capturedRow, isNotNull);
      expect(capturedRow!['account_id'], isNull);
      expect(capturedRow!['amount'], equals(300.0));
      expect(capturedRow!['nafaqah_class'], equals('wife_reimbursable'));
    });
  });
}
