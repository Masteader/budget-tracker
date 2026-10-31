import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/screens/accounts/accounts_overview_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import '../support/localized_app.dart';

class _MockAccountService extends AccountService {
  final List<Account> testAccounts;
  final double testConfiguredIncome;
  final Map<String, double> testCommitted;

  _MockAccountService({
    required this.testAccounts,
    required this.testConfiguredIncome,
    required this.testCommitted,
  });

  @override
  Stream<List<Account>> streamAccounts(String householdId) => Stream.value(testAccounts);

  @override
  Future<List<Account>> getAccounts(String householdId) async => testAccounts;

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => [];

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => testConfiguredIncome;

  @override
  Future<Map<String, double>> getCommittedBudgetsByAccount(String householdId, String cycleKey) async => testCommitted;

  @override
  Future<void> reconcileUnlinkedTransactions(String householdId) async {}
}

void main() {
  testWidgets('AccountsOverviewScreen: displays configured income and remaining commitments when records are empty', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final originalService = AccountService.instance;
    addTearDown(() => AccountService.instance = originalService);

    final acc = Account(
      id: 'acc-rajhi',
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

    AccountService.instance = _MockAccountService(
      testAccounts: [acc],
      testConfiguredIncome: 8900.0,
      testCommitted: {'acc-rajhi': 4882.26},
    );

    await tester.pumpWidget(
      localizedApp(
        const AccountsOverviewScreen(householdId: 'hh-1'),
        scaffold: false,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Cycle Income displays configured income 8,900.00 (not 0.00)
    expect(find.textContaining('8,900.00'), findsOneWidget);

    // Verify Rajhi Main account balance is 6,370.26
    expect(find.textContaining('6,370.26'), findsWidgets);

    // Verify Remaining Commitments displays 4,882.26
    expect(find.textContaining('4,882.26'), findsOneWidget);

    // Verify Surplus Buffer displays +1,488.00 (6,370.26 - 4,882.26)
    expect(find.textContaining('1,488.00'), findsOneWidget);
  });
}
