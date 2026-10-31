import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/account_service.dart';

void main() {
  group('AccountService Unit Tests', () {
    test('instance returns singleton', () {
      final s1 = AccountService.instance;
      final s2 = AccountService.instance;
      expect(identical(s1, s2), isTrue);
    });

    test('getHouseholdConfiguredIncome returns 0.0 when client is uninitialized', () async {
      final service = AccountService();
      final inc = await service.getHouseholdConfiguredIncome('hh-nonexistent');
      expect(inc, equals(0.0));
    });

    test('getAccounts returns empty list when uninitialized', () async {
      final service = AccountService();
      final accounts = await service.getAccounts('hh-nonexistent');
      expect(accounts, isEmpty);
    });

    test('reconcileUnlinkedTransactions returns safely without throwing when uninitialized', () async {
      final service = AccountService();
      await expectLater(service.reconcileUnlinkedTransactions('hh-nonexistent'), completes);
    });
  });
}
