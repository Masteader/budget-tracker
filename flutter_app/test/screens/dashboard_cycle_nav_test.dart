import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/commitments_service.dart';
import '../support/localized_app.dart';

class _CountingAccountService extends AccountService {
  int getAccountsCalls = 0;

  @override
  Future<List<Account>> getAccounts(String householdId) async {
    getAccountsCalls++;
    return [];
  }

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => [];

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => 0.0;

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();
}

class _EmptyCommitmentsService extends CommitmentsService {
  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async => [];
}

class _SpyAccountProvider extends AccountProvider {
  _SpyAccountProvider({
    required super.accounts,
    required super.commitments,
    required super.income,
  });

  int setCycleKeyCalls = 0;

  @override
  Future<void> setCycleKey(String cycleKey) async {
    setCycleKeyCalls++;
    return super.setCycleKey(cycleKey);
  }
}

Widget _wrapWithProviders(Widget child, {required AccountProvider accountProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>.value(value: accountProvider),
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

  testWidgets('Dashboard cycle nav does not mutate AccountProvider cycleKey and eagerly loads accounts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final countingService = _CountingAccountService();
    final commitmentsService = _EmptyCommitmentsService();
    final spyProvider = _SpyAccountProvider(
      accounts: countingService,
      commitments: commitmentsService,
      income: AccountServiceIncomeSource(countingService),
    );

    await tester.pumpWidget(
      _wrapWithProviders(
        BudgetDashboard(
          householdId: 'test-hid',
          fetchHouseholdIdOverride: () async => 'test-hid',
          budgetStreamOverride: (_) => Stream.value([
            {
              'id': 'b-1',
              'category_code': 'OPEX-GROCERY',
              'allocated_amount': 2000.0,
              'spent_amount': 0.0,
              'is_active': true,
              'cycle_key': '2026-11',
              'month': '2026-11-01',
            }
          ]),
        ),
        accountProvider: spyProvider,
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Item 11 test: verify eager load called getAccounts exactly once
    expect(countingService.getAccountsCalls, equals(1));

    final initialCycleKey = spyProvider.cycleKey;

    // Item 5 test: Tap previous cycle chevron button
    final prevButton = find.byIcon(Icons.chevron_left_rounded);
    expect(prevButton, findsOneWidget);
    await tester.tap(prevButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify setCycleKey was never called and provider cycleKey is unchanged
    expect(spyProvider.setCycleKeyCalls, equals(0));
    expect(spyProvider.cycleKey, equals(initialCycleKey));
  });
}
