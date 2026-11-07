import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
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
    // The setup tutor is marked seen: these tests are about the accounts (the
    // old "contains 1" check only ever matched the tutor's step badge).
    SharedPreferences.setMockInitialValues({'has_seen_setup_tutor_v3': true});
    // The setup loads (payday 27, no income figure), so the dashboard renders
    // its hero card and Quick Access instead of the loading placeholder.
    HouseholdSetupPrefs.loadOverride = (_) async => const HouseholdSetupData(paydayDay: 27, monthlyIncome: 0);
    addTearDown(() => HouseholdSetupPrefs.loadOverride = null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

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
    await settle(tester);

    // The hero shows the operating cash, and Quick Access counts one account.
    expect(find.text('7,076.00'), findsOneWidget);
    expect(find.textContaining('(1)'), findsWidgets);

    // Now deduct 100 SAR via AccountProvider mutation: the hero follows.
    accountProvider.optimisticUpdateBalance('acc-1', 6976.0);
    await settle(tester);

    expect(accountProvider.operatingCash, equals(6976.0));
    expect(find.text('6,976.00'), findsOneWidget);
    expect(find.text('7,076.00'), findsNothing);
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
          // One budget, so the hero card (not the setup card) is shown.
          budgetStreamOverride: (_) => Stream.value([
            {
              'id': 'b-1',
              'category_code': 'OPEX-GROCERY',
              'allocated_amount': 500.0,
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
    await settle(tester);

    // When hasLoaded is true, the hero shows 0.00 SAR (not a fallback figure)
    // and Quick Access counts one account.
    expect(find.text('0.00'), findsOneWidget);
    expect(find.textContaining('(1)'), findsWidgets);
  });
}
