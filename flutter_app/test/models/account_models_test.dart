import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';

void main() {
  group('Account Model Tests', () {
    test('Calculates capacity margin and status correctly', () {
      const acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'STC Pay',
        accountType: AccountType.eWallet,
        currency: 'SAR',
        balance: 1800.0,
      );

      // Deficit test: balance 1800 - committed 2300 = -500
      expect(acc.calculateMargin(2300.0), -500.0);
      expect(acc.getStatus(2300.0), AccountCapacityStatus.deficit);

      // Zero-based test: balance 1800 - committed 1800 = 0
      expect(acc.calculateMargin(1800.0), 0.0);
      expect(acc.getStatus(1800.0), AccountCapacityStatus.zeroBased);

      // Surplus test: balance 1800 - committed 1500 = +300
      expect(acc.calculateMargin(1500.0), 300.0);
      expect(acc.getStatus(1500.0), AccountCapacityStatus.surplus);
    });

    test('Serializes to and from Map', () {
      final map = {
        'id': 'acc-1',
        'household_id': 'hh-1',
        'owner_user_id': 'u-1',
        'name': 'Al Rajhi Main',
        'account_type': 'bank',
        'currency': 'SAR',
        'balance': 25000.50,
        'is_shared_pool': false,
        'color_hex': '#00E5BF',
        'icon_name': 'account_balance_rounded',
        'is_archived': false,
        'created_at': '2026-10-18T10:00:00Z',
        'updated_at': '2026-10-18T10:00:00Z',
      };

      final acc = Account.fromMap(map);
      expect(acc.id, 'acc-1');
      expect(acc.name, 'Al Rajhi Main');
      expect(acc.accountType, AccountType.bank);
      expect(acc.balance, 25000.50);
      expect(acc.isSharedPool, false);

      final out = acc.toMap();
      expect(out['name'], 'Al Rajhi Main');
      expect(out['account_type'], 'bank');
      expect(out['balance'], 25000.50);
    });

    test('IncomeRecord calculates net amount correctly', () {
      final inc = IncomeRecord(
        id: 'inc-1',
        householdId: 'hh-1',
        userId: 'u-1',
        accountId: 'acc-1',
        cycleKey: '2026-11',
        sourceType: IncomeSourceType.salary,
        title: 'October Salary',
        baseAmount: 18000.0,
        overtime: 1200.0,
        bonus: 2000.0,
        deductions: 1500.0,
        receivedAt: DateTime.parse('2026-10-27T00:00:00Z'),
      );

      // Net = 18000 + 1200 + 2000 - 1500 = 19700
      expect(inc.netAmount, 19700.0);
    });

    test('AccountTransfer model serializes correctly', () {
      final xfer = AccountTransfer(
        id: 'tx-1',
        householdId: 'hh-1',
        userId: 'u-1',
        fromAccountId: 'acc-1',
        toAccountId: 'acc-2',
        amount: 2000.0,
        fee: 5.75,
        timestamp: DateTime.parse('2026-10-27T12:00:00Z'),
        notes: 'Monthly STC Pay top-up',
      );

      expect(xfer.totalDeduction, 2005.75);
      final map = xfer.toMap();
      expect(map['amount'], 2000.0);
      expect(map['fee'], 5.75);
    });
  });
}
