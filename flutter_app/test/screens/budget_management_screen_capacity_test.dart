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

  testWidgets('BudgetManagementScreen separates cycle funding capacity from live operating cash', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();

    // Account has 7,076 SAR liquid cash
    final acc = Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Rajhi Main',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 7076.0,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );

    // Verified cycle income record is 8,941 SAR
    final incRecord = IncomeRecord(
      id: 'inc-1',
      householdId: 'hh-1',
      userId: 'u-1',
      accountId: 'acc-1',
      cycleKey: currentCycleKey,
      sourceType: IncomeSourceType.salary,
      title: 'Salary',
      baseAmount: 8941.0,
      receivedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    accountProvider.setAccountsForTesting([acc], householdId: 'hh-1', cycleKey: currentCycleKey);
    accountProvider.setCycleIncomeForTesting([incRecord], cycleKey: currentCycleKey);

    // Static data with 7,412 allocated budgets (fully covered by 8,941 income)
    final staticData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: true,
      allCodes: [
        {'code': 'OPEX-GROCERY', 'category': 'Groceries', 'is_system': 'true'},
      ],
      monthlyIncome: 8941.0,
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
              'allocated_amount': 7412.0,
              'spent_amount': 1865.0,
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

    // Verify both capacity (8,941) and live operating cash (7,076) appear
    expect(find.textContaining('8,941'), findsWidgets);
    expect(find.textContaining('7,076'), findsWidgets);

    // Verify no false capacity deficit alert exists (since 7,412 <= 8,941)
    expect(find.byKey(const Key('shrink_to_match_cash_button')), findsNothing);
  });
}
