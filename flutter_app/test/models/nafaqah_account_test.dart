import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah_account.dart';

void main() {
  group('accountForNafaqahClass tests', () {
    const wifeAcc = Account(
      id: 'acc-wife',
      householdId: 'h-1',
      name: 'Wife Checking',
      accountType: AccountType.bank,
      balance: 1000,
      currency: 'SAR',
      ownerUserId: 'u-wife',
      isSharedPool: false,
    );

    const sharedAcc = Account(
      id: 'acc-shared',
      householdId: 'h-1',
      name: 'Household Shared',
      accountType: AccountType.bank,
      balance: 5000,
      currency: 'SAR',
      ownerUserId: 'u-husband',
      isSharedPool: true,
    );

    const husbandAcc = Account(
      id: 'acc-husband',
      householdId: 'h-1',
      name: 'Husband Checking',
      accountType: AccountType.bank,
      balance: 3000,
      currency: 'SAR',
      ownerUserId: 'u-husband',
      isSharedPool: false,
    );

    final accounts = [wifeAcc, sharedAcc, husbandAcc];

    test('wife_personal: wife personal account is kept', () {
      expect(
        accountForNafaqahClass(
          'wife_personal',
          'acc-wife',
          accounts: accounts,
          spouseId: 'u-wife',
        ),
        equals('acc-wife'),
      );
    });

    test('wife_personal: shared pool returns null', () {
      expect(
        accountForNafaqahClass(
          'wife_personal',
          'acc-shared',
          accounts: accounts,
          spouseId: 'u-wife',
        ),
        isNull,
      );
    });

    test('wife_personal: husband personal account returns null', () {
      expect(
        accountForNafaqahClass(
          'wife_personal',
          'acc-husband',
          accounts: accounts,
          spouseId: 'u-wife',
        ),
        isNull,
      );
    });

    test('wife_reimbursable: wife personal account is kept', () {
      expect(
        accountForNafaqahClass(
          'wife_reimbursable',
          'acc-wife',
          accounts: accounts,
          spouseId: 'u-wife',
        ),
        equals('acc-wife'),
      );
    });

    test('wife_reimbursable: shared pool returns null', () {
      expect(
        accountForNafaqahClass(
          'wife_reimbursable',
          'acc-shared',
          accounts: accounts,
          spouseId: 'u-wife',
        ),
        isNull,
      );
    });

    test('null nafaqahClass returns the given accountId', () {
      expect(accountForNafaqahClass(null, 'acc-789'), equals('acc-789'));
      expect(accountForNafaqahClass(null, null), isNull);
    });

    test('any other nafaqahClass or standard expense returns given accountId', () {
      expect(accountForNafaqahClass('none', 'acc-999'), equals('acc-999'));
      expect(accountForNafaqahClass('standard', 'acc-999'), equals('acc-999'));
    });
  });
}

