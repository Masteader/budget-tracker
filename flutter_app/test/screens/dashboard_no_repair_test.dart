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
  });

  group('_BudgetDashboard without repair service', () {
    // The budget repair service rewrote budget rows' cycle_key and month from
    // the client and was removed. Neither screen may bring a repair step back.
    const repairMarkers = [
      'BudgetRepairService',
      'budget_repair_service',
      'repairHouseholdBudgets',
    ];

    test('the budget repair service no longer exists', () {
      expect(
        File('lib/services/budget_repair_service.dart').existsSync(),
        isFalse,
        reason: 'Budget rows are written through the backend; no client-side repair service',
      );
    });

    for (final path in const [
      'lib/screens/home/dashboard_screen.dart',
      'lib/screens/home/budget_management_screen.dart',
    ]) {
      test('$path references no budget repair service', () {
        final src = File(path).readAsStringSync();
        for (final marker in repairMarkers) {
          expect(
            src.contains(marker),
            isFalse,
            reason: '$path must not reference $marker',
          );
        }
      });
    }

    testWidgets('_BudgetDashboard initializes and renders with no repair step', (tester) async {
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

      expect(find.byType(BudgetDashboard), findsOneWidget);
      expect(tester.takeException(), isNull);
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
