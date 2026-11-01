import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/screens/accounts/accounts_overview_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/commitments_service.dart';
import '../support/localized_app.dart';

class _MockAccountService extends AccountService {
  final Map<String, double> testCommitted;
  final List<Account> testAccounts;
  final double testIncome;

  _MockAccountService({
    required this.testCommitted,
    required this.testAccounts,
    required this.testIncome,
  });

  @override
  Future<List<Account>> getAccounts(String householdId) async => testAccounts;

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => testIncome;

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => [];

  @override
  Future<Map<String, double>> getCommittedBudgetsByAccount(String householdId, String cycleKey) async => testCommitted;

  @override
  Future<void> reconcileUnlinkedTransactions(
    String householdId, {
    required bool callerIsAdmin,
    String? currentUserId,
    Future<List<Account>> Function(String p1)? fetchAccounts,
    Future<List<Map<String, dynamic>>> Function(String p1)? fetchUnlinked,
    Future<void> Function(String p1, String p2)? linkTransaction,
  }) async {}
}

class _MockCommitmentsService extends CommitmentsService {
  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async => [];
}

void main() {
  testWidgets('AccountsOverviewScreen: displays configured income from AccountProvider and remaining commitments', (tester) async {
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

    final mockService = _MockAccountService(
      testCommitted: {'acc-rajhi': 4882.26},
      testAccounts: [acc],
      testIncome: 8900.0,
    );
    AccountService.instance = mockService;

    final accountProvider = AccountProvider(
      accounts: mockService,
      commitments: _MockCommitmentsService(),
    );
    accountProvider.bindHousehold('hh-1', paydayDay: 27);
    accountProvider.setAccountsForTesting([acc], householdId: 'hh-1');
    accountProvider.setConfiguredMonthlyIncomeForTesting(8900.0);

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: accountProvider,
        child: localizedApp(
          const AccountsOverviewScreen(householdId: 'hh-1'),
          scaffold: false,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Cycle Income displays configured income 8,900.00 from AccountProvider
    expect(find.textContaining('8,900.00'), findsOneWidget);

    // Verify Rajhi Main account balance is 6,370.26
    expect(find.textContaining('6,370.26'), findsWidgets);

    // Verify Remaining Commitments displays 4,882.26
    expect(find.textContaining('4,882.26'), findsOneWidget);

    // Verify Surplus Buffer displays +1,488.00 (6,370.26 - 4,882.26)
    expect(find.textContaining('1,488.00'), findsOneWidget);
  });
}
