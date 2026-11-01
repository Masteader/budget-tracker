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

  test('Item 3: buildPriorSpendRow never contains cycle_key', () {
    final row = BudgetManagementScreen.buildPriorSpendRow(
      id: 'tx-1',
      householdId: 'hh-1',
      userId: 'u-1',
      amount: 500.0,
      merchant: 'Adjustment',
      categoryCode: 'OPEX-UTIL',
      occurredAt: DateTime(2026, 2, 1),
    );
    expect(row.containsKey('cycle_key'), isFalse);
    expect(row['amount'], equals(500.0));
    expect(row['spent_by'], equals('me'));
  });

  test('Item 15: buildCarryForwardRow preserves metadata and accumulates unspent for sinking funds', () {
    final prevBudget = {
      'category_code': 'OPEX-AUTO',
      'allocated_amount': 1000.0,
      'spent_amount': 400.0,
      'account_id': 'acc-1',
      'sub_allocations': <String, dynamic>{},
      'metadata': {
        '_sinking_fund': {
          '_parent': {
            'accumulate': true,
            'base_amount': 1000.0,
          },
        },
      },
    };

    final row = BudgetManagementScreen.buildCarryForwardRow(
      b: prevBudget,
      householdId: 'hh-1',
      month: '2026-03-01',
      cycleKey: '2026-02-27_2026-03-26',
    );

    // Unspent was 1000 - 400 = 600. Accumulated new alloc = base (1000) + unspent (600) = 1600.0
    expect(row['allocated_amount'], equals(1600.0));
    expect(row['previous_cycle_delta'], equals(600.0));
    expect(row['metadata'], equals(prevBudget['metadata']));
  });

  testWidgets('BudgetManagementScreen: Row 1 is SAR 8,900.00, Row 2 is SAR 6,370.26, and no false deficit alert', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();

    // Reconciled cash on single operating account: SAR 6,370.26
    final acc = Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Rajhi Main account',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 6370.26,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );

    accountProvider.setAccountsForTesting([acc], householdId: 'hh-1', cycleKey: currentCycleKey);
    // Configured monthly income fallback: 8,900 SAR (no individual income records inserted)
    accountProvider.setConfiguredMonthlyIncomeForTesting(8900.0);

    // Static data with total allocated 7,412.00 SAR
    final staticData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: true,
      allCodes: [
        {'code': 'OPEX-UTIL', 'category': 'Utilities & Bills', 'is_system': 'true'},
        {'code': 'OPEX-FAMILY', 'category': 'Family Support', 'is_system': 'true'},
        {'code': 'OPEX-SHOPPING', 'category': 'Shopping & Retail', 'is_system': 'true'},
      ],
      monthlyIncome: 8900.0,
      accounts: [acc],
    );

    // Categories with overspending:
    // Family Support allocated 500, spent 1009 (over by 509)
    // Shopping allocated 1000, spent 2466.37 (over by 1466.37)
    // Utilities allocated 5912, spent 0 (unspent 5912)
    // Total allocated = 7,412.00, Total spent = 3,475.37
    // Net remaining commitment = max(0, 7412 - 3475.37) = 3,936.63 SAR <= account cash 6,370.26 SAR -> NO DEFICIT!
    final budgetRows = [
      {
        'id': 'b-1',
        'household_id': 'hh-1',
        'category_code': 'OPEX-UTIL',
        'allocated_amount': 5912.0,
        'spent_amount': 0.0,
        'account_id': 'acc-1',
        'cycle_key': currentCycleKey,
        'month': currentCycleKey,
        'is_active': true,
        'sub_allocations': <String, dynamic>{
          'sub_housing_rent': 2000.0,
          'Housing Rent': 2000.0, // Duplicate custom key with same translation
        },
      },
      {
        'id': 'b-2',
        'household_id': 'hh-1',
        'category_code': 'OPEX-FAMILY',
        'allocated_amount': 500.0,
        'spent_amount': 1009.0,
        'account_id': 'acc-1',
        'cycle_key': currentCycleKey,
        'month': currentCycleKey,
        'is_active': true,
      },
      {
        'id': 'b-3',
        'household_id': 'hh-1',
        'category_code': 'OPEX-SHOPPING',
        'allocated_amount': 1000.0,
        'spent_amount': 1520.74,
        'account_id': 'acc-1',
        'cycle_key': currentCycleKey,
        'month': currentCycleKey,
        'is_active': true,
      },
    ];

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetManagementScreen(
          initialStaticData: staticData,
          loadStaticDataOverride: () async => staticData,
          budgetStreamOverride: (_) => Stream.value(budgetRows),
        ),
        accountProvider: accountProvider,
      ),
    );

    await tester.pumpAndSettle();

    // Verify Row 1: Cycle Funding Capacity contains 8,900.00
    expect(find.textContaining('8,900.00'), findsOneWidget);

    // Verify Row 2: Operating Cash (Remaining) contains 6,370.26
    expect(find.textContaining('6,370.26'), findsWidgets);

    // Verify NO deficit alert banner is displayed
    expect(find.textContaining('عجز:'), findsNothing);
    expect(find.textContaining('Deficit:'), findsNothing);
    expect(find.textContaining('400.37'), findsNothing);
    expect(find.textContaining('1,041.74'), findsNothing);

    // Verify sub-category chips deduplication: 'Housing Rent' / 'إيجار السكن' appears only once
    expect(find.text('إيجار السكن'), findsOneWidget);
  });

  testWidgets('BudgetManagementScreen: Row 2 reflects AccountProvider single source of truth operating cash (6,457.72)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();

    // Cash on single operating account: SAR 6,457.72
    final staleAcc = Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Rajhi Main account',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 6457.72,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );

    accountProvider.setAccountsForTesting([staleAcc], householdId: 'hh-1', cycleKey: currentCycleKey);
    accountProvider.setConfiguredMonthlyIncomeForTesting(8900.0);

    final staticData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: true,
      allCodes: [
        {'code': 'OPEX-UTIL', 'category': 'Utilities & Bills', 'is_system': 'true'},
      ],
      monthlyIncome: 8900.0,
      accounts: [staleAcc],
    );

    final budgetRows = [
      {
        'id': 'b-1',
        'household_id': 'hh-1',
        'category_code': 'OPEX-UTIL',
        'allocated_amount': 7412.0,
        'spent_amount': 2529.74,
        'account_id': 'acc-1',
        'cycle_key': currentCycleKey,
        'month': currentCycleKey,
        'is_active': true,
      },
    ];

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetManagementScreen(
          initialStaticData: staticData,
          loadStaticDataOverride: () async => staticData,
          budgetStreamOverride: (_) => Stream.value(budgetRows),
        ),
        accountProvider: accountProvider,
      ),
    );

    await tester.pumpAndSettle();

    // Verify Row 1: Cycle Funding Capacity is 8,900.00
    expect(find.textContaining('8,900.00'), findsOneWidget);

    // Verify Row 2: Operating Cash (Remaining) is 6,457.72 from AccountProvider
    expect(find.textContaining('6,457.72'), findsWidgets);

    // Item 8: verify ':  • : ' is gone and localized text with 2,529.74 appears
    expect(find.text(':  • : '), findsNothing);
    expect(find.textContaining('المصروف 2,529.74'), findsOneWidget);
  });

  testWidgets('Item 10 & 11: category library and log_prior_spending_button hidden when isAdmin is false', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();

    final nonAdminData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: false,
      allCodes: [
        {'code': 'OPEX-UTIL', 'category': 'Utilities & Bills', 'is_system': 'true'},
      ],
      monthlyIncome: 1000.0,
      accounts: [],
    );

    // Over-allocated budget (allocated 5000 vs income 1000) to trigger shortfall
    final budgetRows = [
      {
        'id': 'b-1',
        'household_id': 'hh-1',
        'category_code': 'OPEX-UTIL',
        'allocated_amount': 5000.0,
        'spent_amount': 0.0,
        'account_id': null,
        'cycle_key': currentCycleKey,
        'month': currentCycleKey,
        'is_active': true,
      },
    ];

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetManagementScreen(
          initialStaticData: nonAdminData,
          loadStaticDataOverride: () async => nonAdminData,
          budgetStreamOverride: (_) => Stream.value(budgetRows),
        ),
        accountProvider: accountProvider,
      ),
    );
    await tester.pumpAndSettle();

    // Item 10: category library icon button finds nothing
    expect(find.byIcon(Icons.category_outlined), findsNothing);

    // Item 11: log_prior_spending_button finds nothing
    expect(find.byKey(const Key('log_prior_spending_button')), findsNothing);
  });

  testWidgets('Item 13: mappedAccount reflects live AccountProvider update over stale staticData', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;
    final accountProvider = AccountProvider();

    final liveAcc = Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Live Name',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 5000.0,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );

    final staleAcc = liveAcc.copyWith(name: 'Stale Name');

    accountProvider.setAccountsForTesting([liveAcc], householdId: 'hh-1', cycleKey: currentCycleKey);

    final staticData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: true,
      allCodes: [
        {'code': 'OPEX-UTIL', 'category': 'Utilities & Bills', 'is_system': 'true'},
      ],
      monthlyIncome: 5000.0,
      accounts: [staleAcc],
    );

    final budgetRows = [
      {
        'id': 'b-1',
        'household_id': 'hh-1',
        'category_code': 'OPEX-UTIL',
        'allocated_amount': 1000.0,
        'spent_amount': 0.0,
        'account_id': 'acc-1',
        'cycle_key': currentCycleKey,
        'month': currentCycleKey,
        'is_active': true,
      },
    ];

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetManagementScreen(
          initialStaticData: staticData,
          loadStaticDataOverride: () async => staticData,
          budgetStreamOverride: (_) => Stream.value(budgetRows),
        ),
        accountProvider: accountProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live Name'), findsOneWidget);
    expect(find.text('Stale Name'), findsNothing);
  });
}
