import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';

class _SpyAccountService extends AccountService {
  int updateBalanceCalls = 0;
  @override
  Future<void> updateBalance(String accountId, double newBalance) async {
    updateBalanceCalls++;
  }
}

void main() {
  group('AccountService.reconcileUnlinkedTransactions', () {
    const householdId = 'hh-test-123';
    final primaryAccount = Account(
      id: 'acc-primary-1',
      householdId: householdId,
      ownerUserId: 'user-1',
      name: 'Primary Checking',
      accountType: AccountType.bank,
      balance: 5000.0,
      currency: 'SAR',
      isSharedPool: true,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('wife_personal and wife_reimbursable rows are never linked', () async {
      final linkedTxIds = <String>[];
      final targetAccountIds = <String>[];

      final service = AccountService();

      await service.reconcileUnlinkedTransactions(
        householdId,
        callerIsAdmin: true,
        fetchAccounts: (_) async => [primaryAccount],
        fetchUnlinked: (_) async => [
          {
            'id': 'tx-wife-pers',
            'amount': 250.0,
            'category_code': 'OPEX-CLOTHING',
            'nafaqah_class': 'wife_personal',
          },
          {
            'id': 'tx-wife-reimb',
            'amount': 350.0,
            'category_code': 'OPEX-GROCERIES',
            'nafaqah_class': 'wife_reimbursable',
          },
          {
            'id': 'tx-standard',
            'amount': 100.0,
            'category_code': 'OPEX-TRANSPORT',
            'nafaqah_class': null,
          },
        ],
        linkTransaction: (txId, accId) async {
          linkedTxIds.add(txId);
          targetAccountIds.add(accId);
        },
      );

      // Only the standard transaction should be linked
      expect(linkedTxIds, equals(['tx-standard']));
      expect(targetAccountIds, equals(['acc-primary-1']));
      expect(linkedTxIds.contains('tx-wife-pers'), isFalse);
      expect(linkedTxIds.contains('tx-wife-reimb'), isFalse);
    });

    test('no transactions linked if only wife rows are present', () async {
      final linkedTxIds = <String>[];
      final service = AccountService();

      await service.reconcileUnlinkedTransactions(
        householdId,
        callerIsAdmin: true,
        fetchAccounts: (_) async => [primaryAccount],
        fetchUnlinked: (_) async => [
          {
            'id': 'tx-wife-1',
            'amount': 150.0,
            'category_code': 'OPEX-CLOTHING',
            'nafaqah_class': 'wife_personal',
          },
          {
            'id': 'tx-wife-2',
            'amount': 200.0,
            'category_code': 'OPEX-GROCERIES',
            'nafaqah_class': 'wife_reimbursable',
          },
        ],
        linkTransaction: (txId, accId) async {
          linkedTxIds.add(txId);
        },
      );

      expect(linkedTxIds, isEmpty);
    });

    test('reconcileUnlinkedTransactions never calls updateBalance (relies on DB trigger)', () async {
      final spy = _SpyAccountService();
      await spy.reconcileUnlinkedTransactions(
        householdId,
        callerIsAdmin: true,
        fetchAccounts: (_) async => [primaryAccount],
        fetchUnlinked: (_) async => [
          {
            'id': 'tx-standard',
            'amount': 100.0,
            'category_code': 'OPEX-TRANSPORT',
            'nafaqah_class': null,
          },
        ],
        linkTransaction: (_, __) async {},
      );
      expect(spy.updateBalanceCalls, equals(0));
    });

    test('source guard: account_service.dart does not contain forged cycle_key or direct balance update', () {
      final src = File('lib/services/account_service.dart').readAsStringSync();
      expect(src.contains("'cycle_key': currentKey"), isFalse);
      expect(src.contains('reconciledBalance'), isFalse);
      expect(src.contains(".update({'balance'"), isFalse);
    });

    test('prior_adjustment rows are never linked', () async {
      final linkedTxIds = <String>[];
      final service = AccountService();

      await service.reconcileUnlinkedTransactions(
        householdId,
        callerIsAdmin: true,
        fetchAccounts: (_) async => [primaryAccount],
        fetchUnlinked: (_) async => [
          {
            'id': 'tx-prior-1',
            'amount': 500.0,
            'category_code': 'OPEX-GROCERIES',
            'nafaqah_class': null,
            'source': 'prior_adjustment',
          },
        ],
        linkTransaction: (txId, accId) async {
          linkedTxIds.add(txId);
        },
      );

      expect(linkedTxIds, isEmpty);
    });

    test('source guard: buildPriorSpendRow emits source == manual and null account_id (complies with 23514 check)', () {
      final row = BudgetManagementScreen.buildPriorSpendRow(
        id: 'test-id',
        householdId: 'test-hh',
        userId: 'test-user',
        amount: 100.0,
        merchant: 'Prior Spending',
        categoryCode: 'OPEX-GROCERY',
        cycleKey: '2026-11',
        paydayDay: 27,
      );
      expect(row['source'], equals('manual'));
      expect(row['account_id'], isNull);
      expect(row.containsKey('cycle_key'), isFalse);
    });

    test('member never links to shared pool', () async {
      final linkedTxIds = <String>[];
      final service = AccountService();
      final sharedPool = Account(
        id: 'acc-shared-admin',
        householdId: householdId,
        ownerUserId: 'admin-user',
        name: 'Shared Family Account',
        accountType: AccountType.bank,
        balance: 5000.0,
        currency: 'SAR',
        isSharedPool: true,
        isArchived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await service.reconcileUnlinkedTransactions(
        householdId,
        callerIsAdmin: false,
        currentUserId: 'member-user',
        fetchAccounts: (_) async => [sharedPool],
        fetchUnlinked: (_) async => [
          {
            'id': 'tx-member-1',
            'amount': 50.0,
            'category_code': 'OPEX-GROCERIES',
            'nafaqah_class': null,
          },
        ],
        linkTransaction: (txId, accId) async {
          linkedTxIds.add(txId);
        },
      );

      expect(linkedTxIds, isEmpty);
    });

    test('budget-linked account owned by another member is ignored', () async {
      final linkedTxIds = <String>[];
      final targetAccountIds = <String>[];
      final service = AccountService();

      final memberOwnAccount = Account(
        id: 'acc-member-personal',
        householdId: householdId,
        ownerUserId: 'member-user',
        name: 'Member Checking',
        accountType: AccountType.bank,
        balance: 1000.0,
        currency: 'SAR',
        isSharedPool: false,
        isArchived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final otherMemberAccount = Account(
        id: 'acc-other-personal',
        householdId: householdId,
        ownerUserId: 'other-user',
        name: 'Other Member Personal',
        accountType: AccountType.bank,
        balance: 2000.0,
        currency: 'SAR',
        isSharedPool: false,
        isArchived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await service.reconcileUnlinkedTransactions(
        householdId,
        callerIsAdmin: false,
        currentUserId: 'member-user',
        fetchAccounts: (_) async => [memberOwnAccount, otherMemberAccount],
        fetchUnlinked: (_) async => [
          {
            'id': 'tx-1',
            'amount': 40.0,
            'category_code': 'OPEX-GROCERIES',
            'nafaqah_class': null,
          },
        ],
        linkTransaction: (txId, accId) async {
          linkedTxIds.add(txId);
          targetAccountIds.add(accId);
        },
      );

      expect(linkedTxIds, equals(['tx-1']));
      expect(targetAccountIds, equals(['acc-member-personal']));
    });
  });
}
