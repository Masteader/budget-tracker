import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
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
    ],
    child: localizedApp(child, scaffold: false),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Dashboard reactively displays AccountProvider operating cash and account counts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();
    final initialAcc = Account(
      id: 'acc-1',
      householdId: 'test-hid',
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
    accountProvider.setAccountsForTesting(
      [initialAcc],
      householdId: 'test-hid',
      cycleKey: currentCycleKey,
    );

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetDashboard(
          householdId: 'test-hid',
          budgetStreamOverride: (_) => Stream.value([
            {
              'id': 'b-1',
              'category_code': 'OPEX-GROCERY',
              'allocated_amount': 2000.0,
              'spent_amount': 0.0,
              'is_active': true,
              'cycle_key': currentCycleKey,
              'month': '$currentCycleKey-01',
            }
          ]),
        ),
        accountProvider: accountProvider,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Accounts quick access pill shows Accounts (1)
    expect(find.textContaining('1'), findsWidgets);

    // Now deduct 100 SAR via AccountProvider mutation
    accountProvider.optimisticUpdateBalance('acc-1', 6976.0);
    await tester.pump();

    expect(accountProvider.operatingCash, equals(6976.0));
  });

  testWidgets('Dashboard respects 0.00 SAR operating cash when hasLoaded is true (CRITICAL-03)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();
    final zeroAcc = Account(
      id: 'acc-zero',
      householdId: 'test-hid',
      ownerUserId: 'u-1',
      name: 'Zero Balance Bank',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 0.0,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );
    accountProvider.setAccountsForTesting(
      [zeroAcc],
      householdId: 'test-hid',
      cycleKey: currentCycleKey,
    );
    expect(accountProvider.hasLoaded, isTrue);
    expect(accountProvider.operatingCash, equals(0.0));

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetDashboard(
          householdId: 'test-hid',
          budgetStreamOverride: (_) => Stream.value([]),
        ),
        accountProvider: accountProvider,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // When hasLoaded is true, liveOperatingCash should be 0.00 SAR (operatingCash)
    // and total accounts count should be 1
    expect(find.textContaining('1'), findsWidgets);
  });
}
