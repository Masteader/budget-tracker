import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/services/commitments_service.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';

void main() {
  group('AccountProvider Unit Tests', () {
    test('initial state has empty accounts, 0 cash, and is not loading', () {
      final provider = AccountProvider();
      expect(provider.accounts, isEmpty);
      expect(provider.hasLoaded, isFalse);
      expect(provider.operatingCash, equals(0.0));
      expect(provider.totalNetWorth, equals(0.0));
      expect(provider.cycleIncomeRecords, isEmpty);
      expect(provider.cycleIncomeTotal, equals(0.0));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.householdId, isNull);
    });

    test('operatingCash calculates only unarchived operating pool accounts, totalNetWorth includes all non-archived', () {
      final provider = AccountProvider();
      var notified = false;
      provider.addListener(() => notified = true);

      final accounts = [
        Account(
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
        ),
        Account(
          id: 'acc-2',
          householdId: 'hh-1',
          ownerUserId: 'u-1',
          name: 'Emergency Savings Vault',
          accountType: AccountType.savings,
          currency: 'SAR',
          balance: 10000.0,
          isSharedPool: true,
          colorHex: '#3B82F6',
          iconName: 'savings',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-3',
          householdId: 'hh-1',
          ownerUserId: 'u-1',
          name: 'Old Archived Account',
          accountType: AccountType.bank,
          currency: 'SAR',
          balance: 500.0,
          isSharedPool: true,
          colorHex: '#64748B',
          iconName: 'account_balance',
          isArchived: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      provider.setAccountsForTesting(accounts, householdId: 'hh-1');
      expect(notified, isTrue);
      // bank is operating pool -> 7076.0; savings is not operating pool
      expect(provider.operatingCash, equals(7076.0));
      // totalNetWorth is non-archived -> 7076 + 10000 = 17076.0
      expect(provider.totalNetWorth, equals(17076.0));
      expect(provider.householdId, equals('hh-1'));
    });

    test('cycleIncomeTotal sums netAmount of cycle income records', () {
      final provider = AccountProvider();
      final records = [
        IncomeRecord(
          id: 'inc-1',
          householdId: 'hh-1',
          userId: 'u-1',
          accountId: 'acc-1',
          cycleKey: '2026-10',
          sourceType: IncomeSourceType.salary,
          title: 'Primary Salary',
          baseAmount: 8500.0,
          overtime: 500.0,
          bonus: 441.0,
          deductions: 500.0,
          receivedAt: DateTime(2026, 10, 27),
          createdAt: DateTime(2026, 10, 27),
        ),
      ];

      provider.setCycleIncomeForTesting(records, cycleKey: '2026-10');
      expect(provider.cycleIncomeTotal, equals(8941.0));
      expect(provider.effectiveCycleIncome, equals(8941.0));
      expect(provider.cycleKey, equals('2026-10'));
    });

    test('cycleIncomeTotal falls back to configuredMonthlyIncome when cycleIncomeRecords is empty', () {
      final provider = AccountProvider();
      provider.setConfiguredMonthlyIncomeForTesting(8900.0);
      expect(provider.cycleIncomeRecords, isEmpty);
      expect(provider.cycleIncomeTotal, equals(8900.0));
      expect(provider.effectiveCycleIncome, equals(8900.0));
    });

    test('cycleIncomeTotal prioritizes cycleIncomeRecords over configuredMonthlyIncome when records exist', () {
      final provider = AccountProvider();
      provider.setConfiguredMonthlyIncomeForTesting(8900.0);
      final records = [
        IncomeRecord(
          id: 'inc-1',
          householdId: 'hh-1',
          userId: 'u-1',
          accountId: 'acc-1',
          cycleKey: '2026-10',
          sourceType: IncomeSourceType.salary,
          title: 'Primary Salary',
          baseAmount: 9200.0,
          receivedAt: DateTime(2026, 10, 27),
          createdAt: DateTime(2026, 10, 27),
        ),
      ];
      provider.setCycleIncomeForTesting(records, cycleKey: '2026-10');
      expect(provider.cycleIncomeTotal, equals(9200.0));
      expect(provider.effectiveCycleIncome, equals(9200.0));
    });

    test('optimisticUpdateBalance updates account balance instantly and notifies listeners', () {
      final provider = AccountProvider();
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
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      // Deduct 34.40 spent
      provider.optimisticUpdateBalance('acc-1', 7041.60);
      expect(notifyCount, equals(1));
      expect(provider.operatingCash, equals(7041.60));
      expect(provider.accounts.first.balance, equals(7041.60));
    });

    test('deductExpense updates balance on specified account optimistically', () async {
      final provider = AccountProvider();
      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Rajhi Main',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 1000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      await provider.deductExpense(accountId: 'acc-1', amount: 250.0);
      expect(provider.accounts.first.balance, equals(750.0));
      expect(provider.operatingCash, equals(750.0));
    });

    test('deductExpense falls back to default operating account when accountId is null', () async {
      final provider = AccountProvider();
      final acc1 = Account(
        id: 'acc-savings',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Savings',
        accountType: AccountType.savings,
        currency: 'SAR',
        balance: 5000.0,
        isSharedPool: true,
        colorHex: '#3B82F6',
        iconName: 'savings',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      final acc2 = Account(
        id: 'acc-op',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Checking Operating',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 2000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 2),
      );
      provider.setAccountsForTesting([acc1, acc2], householdId: 'hh-1');

      await provider.deductExpense(amount: 500.0);
      expect(provider.accounts.firstWhere((a) => a.id == 'acc-op').balance, equals(1500.0));
      expect(provider.accounts.firstWhere((a) => a.id == 'acc-savings').balance, equals(5000.0));
    });

    test('deductExpense skips deduction when nafaqahClass is wife_personal', () async {
      final provider = AccountProvider();
      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Rajhi Main',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 1000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      await provider.deductExpense(amount: 300.0, nafaqahClass: 'wife_personal');
      expect(provider.accounts.first.balance, equals(1000.0));
    });

    test('deductExpense skips deduction when nafaqahClass is wife_reimbursable', () async {
      final provider = AccountProvider();
      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Rajhi Main',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 1000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      await provider.deductExpense(amount: 300.0, nafaqahClass: 'wife_reimbursable');
      expect(provider.accounts.first.balance, equals(1000.0));
    });

    test('deductExpense never calls AccountService.updateBalance', () async {
      final mockService = _MockAccountService();
      final provider = AccountProvider(service: mockService);
      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Rajhi Main',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 1000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      await provider.deductExpense(amount: 300.0);
      expect(provider.accounts.first.balance, equals(700.0));
      expect(mockService.updateBalanceCalls, equals(0));
    });

    test('deductExpense allows negative optimistic balance', () async {
      final provider = AccountProvider();
      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Rajhi Main',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 100.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      await provider.deductExpense(amount: 300.0);
      expect(provider.accounts.first.balance, equals(-200.0));
    });

    test('reset clears accounts and income and notifies listeners', () {
      final provider = AccountProvider();
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
      provider.setAccountsForTesting([acc], householdId: 'hh-1');

      provider.reset();
      expect(provider.accounts, isEmpty);
      expect(provider.operatingCash, equals(0.0));
      expect(provider.householdId, isNull);
      expect(provider.hasLoaded, isFalse);
    });

    test('hasLoaded is true after setAccountsForTesting', () {
      final provider = AccountProvider();
      expect(provider.hasLoaded, isFalse);
      provider.setAccountsForTesting([], householdId: 'hh-1');
      expect(provider.hasLoaded, isTrue);
    });

    test('refresh preserves existing accounts and sets error on service failure (CRITICAL-02)', () async {
      final fakeService = _FailingAccountService();
      final provider = AccountProvider(service: fakeService);

      final initialAcc = Account(
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
      provider.setAccountsForTesting([initialAcc], householdId: 'hh-1');

      await provider.refresh();

      expect(provider.accounts.length, equals(1));
      expect(provider.accounts.first.balance, equals(7076.0));
      expect(provider.operatingCash, equals(7076.0));
      expect(provider.error, contains('Simulated network failure'));
      expect(provider.isLoading, isFalse);
    });

    test('SSOT 1: Deduplication - three concurrent ensureLoaded calls trigger exactly 1 getAccounts call', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);

      await Future.wait([
        provider.ensureLoaded(),
        provider.ensureLoaded(),
        provider.ensureLoaded(),
      ]);

      expect(fakeAccounts.getAccountsCalls, equals(1));
    });

    test('SSOT 2: Cache hit - ensureLoaded after completed load makes 0 additional calls', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);
      await provider.ensureLoaded();
      expect(fakeAccounts.getAccountsCalls, equals(1));

      await provider.ensureLoaded();
      expect(fakeAccounts.getAccountsCalls, equals(1));
    });

    test('SSOT 3: Forced refresh - refresh(force: true) while load in flight queues follow-up sequentially', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);

      final completer = Completer<List<Account>>();
      fakeAccounts.nextGetAccountsCompleter = completer;

      final f1 = provider.refresh();
      expect(fakeAccounts.getAccountsCalls, equals(1));

      final f2 = provider.refresh(force: true);
      expect(fakeAccounts.getAccountsCalls, equals(1));

      fakeAccounts.nextGetAccountsCompleter = null;
      completer.complete([]);

      await Future.wait([f1, f2]);
      expect(fakeAccounts.getAccountsCalls, equals(2));
    });

    test('SSOT 4: Stale-response guard - slow h1 completing after fast h2 does not overwrite h2', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );

      final h1Completer = Completer<List<Account>>();
      fakeAccounts.nextGetAccountsCompleter = h1Completer;

      provider.bindHousehold('h1', paydayDay: 27);
      final f1 = provider.ensureLoaded();

      fakeAccounts.nextGetAccountsCompleter = null;
      fakeAccounts.accountsToReturn = [
        Account(
          id: 'acc-h2',
          householdId: 'h2',
          ownerUserId: 'u-1',
          name: 'H2 Bank',
          accountType: AccountType.bank,
          balance: 5000.0,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      provider.bindHousehold('h2', paydayDay: 27);
      await provider.ensureLoaded();

      expect(provider.snapshot.householdId, equals('h2'));
      expect(provider.accounts.first.id, equals('acc-h2'));

      h1Completer.complete([
        Account(
          id: 'acc-h1',
          householdId: 'h1',
          ownerUserId: 'u-1',
          name: 'H1 Bank',
          accountType: AccountType.bank,
          balance: 1000.0,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
      await f1;

      expect(provider.snapshot.householdId, equals('h2'));
      expect(provider.accounts.first.id, equals('acc-h2'));
    });

    test('SSOT 5: Household switch - bindHousehold immediately clears accounts and snapshot to empty', () {
      final provider = AccountProvider();
      provider.setAccountsForTesting([
        Account(
          id: 'acc-1',
          householdId: 'h1',
          ownerUserId: 'u-1',
          name: 'Bank',
          accountType: AccountType.bank,
          balance: 1000.0,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ], householdId: 'h1');

      expect(provider.accounts.length, equals(1));
      expect(provider.snapshot.householdId, equals('h1'));

      var notified = false;
      provider.addListener(() => notified = true);

      provider.bindHousehold('h2', paydayDay: 27);

      expect(notified, isTrue);
      expect(provider.accounts, isEmpty);
      expect(provider.snapshot, equals(OperatingCashSnapshot.empty));
      expect(provider.hasLoaded, isFalse);
    });

    test('SSOT 6: Atomic publish - refresh triggers exactly 2 listener notifications (loading -> loaded)', () async {
      final fakeAccounts = _FakeAccountService();
      fakeAccounts.accountsToReturn = [
        Account(
          id: 'acc-1',
          householdId: 'h1',
          ownerUserId: 'u-1',
          name: 'Bank',
          accountType: AccountType.bank,
          balance: 2000.0,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);

      final states = <(bool loading, int halalas)>[];
      provider.addListener(() {
        states.add((provider.isLoading, provider.snapshot.liquidHalalas));
      });

      await provider.refresh();

      expect(states.length, equals(2));
      expect(states[0], equals((true, 0)));
      expect(states[1], equals((false, 200000)));
    });

    test('SSOT 7: Error handling - service exception sets error, keeps previous snapshot, isLoading false, does not throw', () async {
      final fakeAccounts = _FakeAccountService();
      final provider = AccountProvider(accounts: fakeAccounts);
      provider.setAccountsForTesting([
        Account(
          id: 'acc-1',
          householdId: 'h1',
          ownerUserId: 'u-1',
          name: 'Bank',
          accountType: AccountType.bank,
          balance: 1000.0,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ], householdId: 'h1');

      final prevSnapshot = provider.snapshot;

      final failingCompleter = Completer<List<Account>>();
      fakeAccounts.nextGetAccountsCompleter = failingCompleter;
      failingCompleter.completeError(Exception('Network drop'));

      await provider.refresh(force: true);

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.snapshot, equals(prevSnapshot));
    });

    test('SSOT 8: Payday change - onPaydayChanged recomputes cycleKey and refetches', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);
      await provider.ensureLoaded();
      expect(fakeAccounts.getAccountsCalls, equals(1));

      await provider.onPaydayChanged(10);

      expect(fakeAccounts.getAccountsCalls, equals(2));
      expect(provider.paydayDay, equals(10));
    });

    test('SSOT 9: configured income does not leak across households', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      fakeIncome.configuredIncome = 9000.0;

      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);
      await provider.ensureLoaded();
      expect(provider.cycleIncomeTotal, equals(9000.0));
      expect(provider.configuredMonthlyIncome, equals(9000.0));

      provider.bindHousehold('h2', paydayDay: 27);
      fakeIncome.shouldThrowForConfigured = true;
      await provider.ensureLoaded();

      expect(provider.cycleIncomeTotal, equals(0.0));
      expect(provider.configuredMonthlyIncome, isNull);
    });

    test('SSOT 10: stale h1 completion does not clear h2 in-flight', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();

      final c1 = Completer<List<Account>>();
      final c2 = Completer<List<Account>>();
      fakeAccounts.completers.addAll([c1, c2]);

      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );

      provider.bindHousehold('h1', paydayDay: 27);
      final h1Future = provider.ensureLoaded();

      provider.bindHousehold('h2', paydayDay: 27);
      final h2Future = provider.ensureLoaded();

      // Complete h1
      c1.complete([]);
      await h1Future;

      // Call ensureLoaded() twice while h2 is still pending
      final f1 = provider.ensureLoaded();
      final f2 = provider.ensureLoaded();

      // Complete h2
      c2.complete([]);
      await Future.wait([h2Future, f1, f2]);

      // Expect getAccountsCalls == 2 total (1 for h1, 1 for h2), not 3
      expect(fakeAccounts.getAccountsCalls, equals(2));
    });

    test('setCycleKey refetches with new cycle key', () async {
      final fakeAccounts = _FakeAccountService();
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();
      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );
      provider.bindHousehold('h1', paydayDay: 27);
      await provider.ensureLoaded();
      expect(fakeAccounts.getAccountsCalls, equals(1));

      await provider.setCycleKey('2026-12-27_2027-01-26');
      expect(fakeAccounts.getAccountsCalls, equals(2));
      expect(fakeCommitments.lastCycleKey, equals('2026-12-27_2027-01-26'));
      expect(provider.cycleKey, equals('2026-12-27_2027-01-26'));
    });

    test('bindHousehold honours non-27 payday', () {
      final provider = AccountProvider();
      final now = DateTime.now();
      provider.bindHousehold('h1', paydayDay: 10);
      expect(provider.paydayDay, equals(10));
      expect(provider.cycleKey, equals(SalaryCycleService.cycleKeyForInstant(now, paydayDay: 10)));
    });

    test('SSOT 11: commitments service failure does not block account loading and operating cash', () async {
      final fakeAccounts = _FakeAccountService();
      fakeAccounts.accountsToReturn = [
        Account(
          id: 'acc-1',
          householdId: 'h1',
          ownerUserId: 'u-1',
          name: 'Main Bank',
          accountType: AccountType.bank,
          currency: 'SAR',
          balance: 1000.0,
          isSharedPool: true,
          colorHex: '#10B981',
          iconName: 'account_balance',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      final failingCommitments = _FailingCommitmentsService();
      final fakeIncome = _FakeIncomeSource();

      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: failingCommitments,
        income: fakeIncome,
      );

      provider.bindHousehold('h1', paydayDay: 27);
      await provider.ensureLoaded();

      expect(provider.hasLoaded, isTrue);
      expect(provider.operatingCash, equals(1000.0));
      expect(provider.error, isNotNull);
    });

    test('Realtime stream emission updates accounts and operating cash without calling getAccounts network refetch', () async {
      final streamController = StreamController<List<Account>>.broadcast();
      final fakeAccounts = _StreamFakeAccountService(streamController.stream);
      final fakeCommitments = _FakeCommitmentsService();
      final fakeIncome = _FakeIncomeSource();

      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: fakeCommitments,
        income: fakeIncome,
      );

      provider.bindHousehold('h1', paydayDay: 27);
      expect(fakeAccounts.getAccountsCalls, equals(0));

      final testAccount = Account(
        id: 'acc-stream',
        householdId: 'h1',
        ownerUserId: 'u-1',
        name: 'Streamed Wallet',
        accountType: AccountType.eWallet,
        currency: 'SAR',
        balance: 450.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );

      streamController.add([testAccount]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeAccounts.getAccountsCalls, equals(0));
      expect(provider.accounts.length, equals(1));
      expect(provider.accounts.first.balance, equals(450.0));
      expect(provider.operatingCash, equals(450.0));
      expect(provider.hasLoaded, isTrue);

      await streamController.close();
    });

    test('dispose during in-flight load completes safely without throwing', () async {
      final fakeAccounts = _FakeAccountService();
      final c = Completer<List<Account>>();
      fakeAccounts.nextGetAccountsCompleter = c;

      final provider = AccountProvider(
        accounts: fakeAccounts,
        commitments: _FakeCommitmentsService(),
        income: _FakeIncomeSource(),
      );

      provider.bindHousehold('h1', paydayDay: 27);
      final loadFuture = provider.ensureLoaded();

      provider.dispose();
      c.complete([]);
      await expectLater(loadFuture, completes);
    });

    test('deductExpense with non-existent accountId does not fall back to debiting another account', () async {
      final provider = AccountProvider();
      final acc1 = Account(
        id: 'acc-1',
        householdId: 'h1',
        ownerUserId: 'u-1',
        name: 'Primary Bank',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 1000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );
      provider.setAccountsForTesting([acc1], householdId: 'h1');

      await provider.deductExpense(accountId: 'missing-id', amount: 200.0);

      expect(provider.accounts.first.balance, equals(1000.0));
    });
  });
}

class _FakeAccountService extends AccountService {
  int getAccountsCalls = 0;
  Completer<List<Account>>? nextGetAccountsCompleter;
  final List<Completer<List<Account>>> completers = [];
  List<Account> accountsToReturn = [];

  @override
  Future<List<Account>> getAccounts(String householdId) async {
    getAccountsCalls++;
    if (completers.isNotEmpty) {
      return completers.removeAt(0).future;
    }
    if (nextGetAccountsCompleter != null) {
      return nextGetAccountsCompleter!.future;
    }
    return accountsToReturn;
  }

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => [];

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => 0.0;

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();
}

class _FakeCommitmentsService extends CommitmentsService {
  int getCommitmentsCalls = 0;
  List<PendingCommitment> commitmentsToReturn = [];
  String? lastCycleKey;

  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async {
    getCommitmentsCalls++;
    lastCycleKey = cycleKey;
    return commitmentsToReturn;
  }
}

class _FakeIncomeSource implements IncomeSource {
  int getIncomeCalls = 0;
  List<IncomeRecord> records = [];
  double configuredIncome = 0.0;
  bool shouldThrowForConfigured = false;

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async {
    getIncomeCalls++;
    return records;
  }

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async {
    if (shouldThrowForConfigured) {
      throw Exception('Failed to load configured income');
    }
    return configuredIncome;
  }
}

class _FailingAccountService extends AccountService {
  @override
  Future<List<Account>> getAccounts(String householdId) async {
    throw Exception('Simulated network failure');
  }

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async {
    return [];
  }

  @override
  Stream<List<Account>> streamAccounts(String householdId) {
    return const Stream.empty();
  }
}

class _MockAccountService extends AccountService {
  int updateBalanceCalls = 0;
  double? lastUpdatedBalance;

  @override
  Future<void> updateBalance(String accountId, double newBalance) async {
    updateBalanceCalls++;
    lastUpdatedBalance = newBalance;
  }

  @override
  Future<List<Account>> getAccounts(String householdId) async {
    return [];
  }

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async {
    return [];
  }

  @override
  Stream<List<Account>> streamAccounts(String householdId) {
    return const Stream.empty();
  }
}

class _FailingCommitmentsService extends CommitmentsService {
  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async {
    throw Exception('FastAPI commitments 500 error');
  }
}

class _StreamFakeAccountService extends AccountService {
  _StreamFakeAccountService(this._stream);
  final Stream<List<Account>> _stream;
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
  Stream<List<Account>> streamAccounts(String householdId) => _stream;
}
