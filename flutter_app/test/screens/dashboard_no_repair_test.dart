import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/budget_repair_service.dart';
import '../support/localized_app.dart';

Widget _wrapWithProviders(Widget child) {
  return MultiProvider(
    providers: [
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
    BudgetRepairService.instance.repairCallCount = 0;
  });

  group('_BudgetDashboard without repair service', () {
    test('dashboard_screen.dart source code contains no references to BudgetRepairService', () {
      final src = File('lib/screens/home/dashboard_screen.dart').readAsStringSync();
      expect(
        src.contains('BudgetRepairService'),
        isFalse,
        reason: 'BudgetRepairService must not be referenced or invoked during dashboard lifecycle',
      );
    });

    testWidgets('_BudgetDashboard initializes and renders without calling BudgetRepairService', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrapWithProviders(
          BudgetDashboard(
            householdId: 'test-hid',
            budgetStreamOverride: (_) => Stream.value([]),
          ),
        ),
      );
      await tester.pump();

      expect(BudgetRepairService.instance.repairCallCount, equals(0));
    });

    testWidgets('uses provided householdId without querying users table again', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var usersTableQueried = false;

      await tester.pumpWidget(
        _wrapWithProviders(
          BudgetDashboard(
            householdId: 'test-hid',
            fetchHouseholdIdOverride: () async {
              usersTableQueried = true;
              return 'test-hid';
            },
            budgetStreamOverride: (_) => Stream.value([]),
          ),
        ),
      );
      await tester.pump();

      expect(usersTableQueried, isFalse);
    });

    testWidgets('falls back to querying users table when householdId is null', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var usersTableQueried = false;

      await tester.pumpWidget(
        _wrapWithProviders(
          BudgetDashboard(
            householdId: null,
            fetchHouseholdIdOverride: () async {
              usersTableQueried = true;
              return 'fallback-hid';
            },
            budgetStreamOverride: (_) => Stream.value([]),
          ),
        ),
      );
      await tester.pump();

      expect(usersTableQueried, isTrue);
    });
  });
}
