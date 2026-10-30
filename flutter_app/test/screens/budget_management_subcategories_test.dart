import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import '../support/localized_app.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
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

  testWidgets('BudgetManagementScreen displays dynamic sub-category chips on cloned category', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final currentCycleKey = SalaryCycleService.currentCycle().key;

    // A cloned category with code 'OPEX-CLONED-FOOD' and 2 subcategories
    final staticData = BudgetStaticData(
      householdId: 'hh-1',
      isAdmin: true,
      allCodes: [
        {'code': 'OPEX-CLONED-FOOD', 'category': 'Cloned Food Category', 'is_system': 'false'},
      ],
      monthlyIncome: 5000.0,
      accounts: [],
    );

    await tester.pumpWidget(
      _wrap(
        BudgetManagementScreen(
          initialStaticData: staticData,
          loadStaticDataOverride: () async => staticData,
          budgetStreamOverride: (_) => Stream.value([
            {
              'id': 'b-cloned',
              'household_id': 'hh-1',
              'category_code': 'OPEX-CLONED-FOOD',
              'allocated_amount': 1500.0,
              'spent_amount': 0.0,
              'is_active': true,
              'cycle_key': currentCycleKey,
              'month': '$currentCycleKey-01',
              'sub_allocations': {
                'Fresh Produce': 800.0,
                'Specialty Bakery': 700.0,
              },
            }
          ]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify sub-category chips appear on screen
    expect(find.text('Fresh Produce'), findsOneWidget);
    expect(find.text('Specialty Bakery'), findsOneWidget);
  });
}

