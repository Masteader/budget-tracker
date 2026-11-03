import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import '../support/localized_app.dart';

Widget _wrapWithProviders(Widget child, {AccountProvider? accountProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>.value(value: accountProvider ?? AccountProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
      ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
      ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
      ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => HouseholdRoleProvider()),
    ],
    child: localizedApp(child, scaffold: false),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BudgetManagementScreen: No layout overflow on narrow 360px viewport with large amounts', (tester) async {
    // Exact narrow mobile viewport dimensions where overflow previously triggered
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();

    // Large numbers matching user report: Operating cash 3,353.75, Income 9,000.00
    final acc = Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Alinma Main',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 3353.75,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );

    final incRecord = IncomeRecord(
      id: 'inc-1',
      householdId: 'hh-1',
      userId: 'u-1',
      accountId: 'acc-1',
      cycleKey: currentCycleKey,
      sourceType: IncomeSourceType.salary,
      title: 'Salary',
      baseAmount: 9000.0,
      receivedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    accountProvider.setAccountsForTesting([acc], householdId: 'hh-1', cycleKey: currentCycleKey);
    accountProvider.setCycleIncomeForTesting([incRecord], cycleKey: currentCycleKey);

    // Allocated 5,646.25 (leaving 3,353.75 buffer within 9,000 income capacity)
    // Spent 5,641.65 (totalSpent > 0 triggers the second text)
    final staticData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: true,
      allCodes: [
        {'code': 'OPEX-GROCERY', 'category': 'Groceries', 'is_system': 'true'},
      ],
      monthlyIncome: 9000.0,
      accounts: [acc],
    );

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetManagementScreen(
          initialStaticData: staticData,
          loadStaticDataOverride: () async => staticData,
          budgetStreamOverride: (_) => Stream.value([
            {
              'id': 'b-1',
              'household_id': 'hh-1',
              'category_code': 'OPEX-GROCERY',
              'allocated_amount': 5646.25,
              'spent_amount': 5641.65,
              'is_active': true,
              'cycle_key': currentCycleKey,
              'month': '$currentCycleKey-01',
              'account_id': 'acc-1',
            }
          ]),
        ),
        accountProvider: accountProvider,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Must be ZERO overflow exceptions captured
    expect(tester.takeException(), isNull);

    // Verify the Wrap widget is used for capacity text layout
    final wrapFinder = find.byWidgetPredicate(
      (widget) => widget is Wrap && widget.children.length >= 2,
    );
    expect(wrapFinder, findsWidgets);

    // Verify both capacity and spent vs cash texts render cleanly
    expect(find.textContaining('3,353.75'), findsWidgets);
    expect(find.textContaining('5,641.65'), findsWidgets);
  });
}
