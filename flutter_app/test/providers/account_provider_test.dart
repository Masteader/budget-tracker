import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/services/account_service.dart';

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
      expect(provider.cycleKey, equals('2026-10'));
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
  });
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
