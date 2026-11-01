import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';

void main() {
  group('OperatingCashCalculator', () {
    const householdId = 'h-test-123';
    const cycleKey = '2026-11';

    test('Case 1: Bank 1000.00 + STC Pay 250.50 + Cash 49.50 with no commitments', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Al Rajhi',
          accountType: AccountType.bank,
          balance: 1000.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-2',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'STC Pay',
          accountType: AccountType.eWallet,
          balance: 250.50,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-3',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Cash Wallet',
          accountType: AccountType.cash,
          balance: 49.50,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: const [],
        cycleIncomeHalalas: 1000000,
      );

      expect(snapshot.liquidHalalas, equals(130000)); // 1300.00 SAR
      expect(snapshot.operatingCashHalalas, equals(130000));
      expect(snapshot.operatingCash, equals(1300.00));
      expect(snapshot.accountsCount, equals(3));
      expect(snapshot.isDeficit, isFalse);
    });

    test('Case 2: An archived bank account is excluded from liquid and operating cash', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Active Bank',
          accountType: AccountType.bank,
          balance: 500.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-2',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Old Closed Bank',
          accountType: AccountType.bank,
          balance: 2000.00,
          isArchived: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: const [],
        cycleIncomeHalalas: 50000,
      );

      expect(snapshot.liquidHalalas, equals(50000));
      expect(snapshot.operatingCashHalalas, equals(50000));
      expect(snapshot.accountsCount, equals(1));
    });

    test('Case 3: Crypto, savings and non-operating accounts are excluded', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Current Bank',
          accountType: AccountType.bank,
          balance: 800.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-2',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Emergency Savings Vault',
          accountType: AccountType.savings,
          balance: 50000.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-3',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Bitcoin Vault',
          accountType: AccountType.crypto,
          balance: 15000.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: const [],
        cycleIncomeHalalas: 80000,
      );

      expect(snapshot.liquidHalalas, equals(80000)); // only 800 SAR from Current Bank
      expect(snapshot.operatingCashHalalas, equals(80000));
      expect(snapshot.accountsCount, equals(1));
    });

    test('Case 4: An unpaid bill due in the current cycle is subtracted; paid bill is not', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Current Bank',
          accountType: AccountType.bank,
          balance: 2000.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final commitments = [
        const PendingCommitment(
          id: 'bill-1',
          kind: CommitmentKind.recurringBill,
          amountHalalas: 35000, // 350.00 SAR (Electricity)
          cycleKey: cycleKey,
          isPaid: false,
        ),
        const PendingCommitment(
          id: 'bill-2',
          kind: CommitmentKind.recurringBill,
          amountHalalas: 20000, // 200.00 SAR (Internet, already paid)
          cycleKey: cycleKey,
          isPaid: true,
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: commitments,
        cycleIncomeHalalas: 200000,
      );

      expect(snapshot.liquidHalalas, equals(200000)); // 2000.00 SAR
      expect(snapshot.pendingCommitmentsHalalas, equals(35000)); // only unpaid bill-1
      expect(snapshot.operatingCashHalalas, equals(165000)); // 2000 - 350 = 1650 SAR
      expect(snapshot.operatingCash, equals(1650.00));
    });

    test('Case 5: Installment due in next cycle is not subtracted; current cycle is', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Current Bank',
          accountType: AccountType.bank,
          balance: 3000.00,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final commitments = [
        const PendingCommitment(
          id: 'inst-1',
          kind: CommitmentKind.installment,
          amountHalalas: 50000, // 500.00 SAR due in current cycle (2026-11)
          cycleKey: '2026-11',
          isPaid: false,
        ),
        const PendingCommitment(
          id: 'inst-2',
          kind: CommitmentKind.installment,
          amountHalalas: 50000, // 500.00 SAR due in next cycle (2026-12)
          cycleKey: '2026-12',
          isPaid: false,
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: '2026-11',
        accounts: accounts,
        commitments: commitments,
        cycleIncomeHalalas: 300000,
      );

      expect(snapshot.pendingCommitmentsHalalas, equals(50000)); // only inst-1
      expect(snapshot.operatingCashHalalas, equals(250000)); // 3000 - 500 = 2500 SAR
    });

    test('Case 6: Commitments greater than liquid balance yield negative cash with isDeficit == true (no zero-clamping)', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Current Bank',
          accountType: AccountType.bank,
          balance: 400.00, // 400 SAR
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final commitments = [
        const PendingCommitment(
          id: 'bill-rent',
          kind: CommitmentKind.recurringBill,
          amountHalalas: 150000, // 1500.00 SAR
          cycleKey: cycleKey,
          isPaid: false,
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: commitments,
        cycleIncomeHalalas: 40000,
      );

      expect(snapshot.liquidHalalas, equals(40000)); // 400.00 SAR
      expect(snapshot.pendingCommitmentsHalalas, equals(150000)); // 1500.00 SAR
      expect(snapshot.operatingCashHalalas, equals(-110000)); // -1100.00 SAR deficit
      expect(snapshot.operatingCash, equals(-1100.00));
      expect(snapshot.isDeficit, isTrue);
    });

    test('Case 7: Exact halala precision prevents floating-point drift (0.10 + 0.20 == 0.30)', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Bank 1',
          accountType: AccountType.bank,
          balance: 0.10,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-2',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Wallet 2',
          accountType: AccountType.cash,
          balance: 0.20,
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: const [],
        cycleIncomeHalalas: 30,
      );

      expect(snapshot.liquidHalalas, equals(30)); // Exactly 30 halalas
      expect(snapshot.operatingCashHalalas, equals(30));
      expect(snapshot.operatingCash, equals(0.30));
    });

    test('Case 8: Provider cycleKey is strictly propagated into the snapshot', () {
      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: '2026-12',
        accounts: const [],
        commitments: const [],
        cycleIncomeHalalas: 0,
      );

      expect(snapshot.householdId, equals(householdId));
      expect(snapshot.cycleKey, equals('2026-12'));
    });

    test('Case 9: Overdrawn operating account (negative balance) is summed: Bank 1000 + Wallet -250 == 75000 halalas', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Main Bank',
          accountType: AccountType.bank,
          balance: 1000.0,
          currency: 'SAR',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-2',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'Overdrawn Wallet',
          accountType: AccountType.eWallet,
          balance: -250.0,
          currency: 'SAR',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: const [],
        cycleIncomeHalalas: 75000,
      );

      expect(snapshot.liquidHalalas, equals(75000)); // 750.00 SAR
      expect(snapshot.operatingCash, equals(750.00));
      expect(snapshot.accountsCount, equals(2));
    });

    test('Case 10: Non-SAR operating account (currency: USD, balance: 500) is excluded', () {
      final accounts = [
        Account(
          id: 'acc-1',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'SAR Bank',
          accountType: AccountType.bank,
          balance: 1000.0,
          currency: 'SAR',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        Account(
          id: 'acc-2',
          householdId: householdId,
          ownerUserId: 'u-1',
          name: 'USD Bank',
          accountType: AccountType.bank,
          balance: 500.0,
          currency: 'USD',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final snapshot = OperatingCashCalculator.compute(
        householdId: householdId,
        cycleKey: cycleKey,
        accounts: accounts,
        commitments: const [],
        cycleIncomeHalalas: 100000,
      );

      expect(snapshot.liquidHalalas, equals(100000)); // 1000.00 SAR only
      expect(snapshot.accountsCount, equals(1)); // Only the SAR account is counted
    });
  });
}
