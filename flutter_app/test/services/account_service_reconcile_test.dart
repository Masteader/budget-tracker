import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/account_service.dart';

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
  });
}
