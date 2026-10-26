import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';

void main() {
  group('AccountType.savings and isOperatingPool', () {
    test('parses savings from string correctly', () {
      expect(AccountTypeExtension.fromString('savings'), AccountType.savings);
      expect(AccountType.savings.value, 'savings');
      expect(AccountType.savings.translationKey, 'account_type_savings');
    });

    test('isOperatingPool returns true only for operating accounts', () {
      expect(AccountType.bank.isOperatingPool, isTrue);
      expect(AccountType.eWallet.isOperatingPool, isTrue);
      expect(AccountType.cash.isOperatingPool, isTrue);
      expect(AccountType.sharedPool.isOperatingPool, isTrue);

      // Savings vaults and crypto are protected from monthly operating budgets
      expect(AccountType.savings.isOperatingPool, isFalse);
      expect(AccountType.crypto.isOperatingPool, isFalse);
    });
  });
}
