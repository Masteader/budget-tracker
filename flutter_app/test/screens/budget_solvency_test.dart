import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  group('Zero-Based Budget Solvency & Deficit Logic', () {
    test('spent expenses reduce commitment so mid-month cash drop does NOT cause false deficit', () {
      // Household starts cycle with 7,000 SAR in bank and allocates 5,000 SAR
      // During month, 5,000 SAR is spent on those categories, so bank balance drops to 2,000 SAR.
      const operatingCash = 2000.0;
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 3000.0,
          spentAmount: 3000.0, // Fully spent
          remainingAmount: 0.0,
          month: '2026-10-01',
          isActive: true,
        ),
        const Budget(
          id: 'b2',
          householdId: 'h1',
          categoryCode: 'OPEX-UTILITIES',
          allocatedAmount: 2000.0,
          spentAmount: 2000.0, // Fully spent
          remainingAmount: 0.0,
          month: '2026-10-01',
          isActive: true,
        ),
      ];

      final totalAllocated = budgets.fold<double>(0.0, (s, b) => s + b.allocatedAmount);
      expect(totalAllocated, 5000.0);

      // Remaining unspent commitments
      final totalUnspentCommitments = budgets
          .where((b) => b.isActive)
          .fold<double>(0.0, (s, b) => s + (b.allocatedAmount - b.spentAmount).clamp(0.0, double.infinity));
      expect(totalUnspentCommitments, 0.0);

      const hasOperatingCash = operatingCash > 0;
      final cashMargin = hasOperatingCash
          ? (operatingCash - totalUnspentCommitments)
          : (7000.0 - totalAllocated);
      final isOverAllocated = cashMargin < -0.005;

      // Solvency must be positive (+2,000 SAR surplus) and NOT over-allocated!
      expect(cashMargin, 2000.0);
      expect(isOverAllocated, isFalse);
    });

    test('real liquidity shortage is correctly flagged as deficit', () {
      // 2,000 SAR cash left in bank, but 4,000 SAR unspent commitments remaining
      const operatingCash = 2000.0;
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 3000.0,
          spentAmount: 1000.0, // 2,000 unspent
          remainingAmount: 2000.0,
          month: '2026-10-01',
          isActive: true,
        ),
        const Budget(
          id: 'b2',
          householdId: 'h1',
          categoryCode: 'OPEX-UTILITIES',
          allocatedAmount: 2000.0,
          spentAmount: 0.0, // 2,000 unspent
          remainingAmount: 2000.0,
          month: '2026-10-01',
          isActive: true,
        ),
      ];

      final totalUnspentCommitments = budgets
          .where((b) => b.isActive)
          .fold<double>(0.0, (s, b) => s + (b.allocatedAmount - b.spentAmount).clamp(0.0, double.infinity));
      expect(totalUnspentCommitments, 4000.0);

      final cashMargin = operatingCash - totalUnspentCommitments;
      final isOverAllocated = cashMargin < -0.005;

      expect(cashMargin, -2000.0);
      expect(isOverAllocated, isTrue);
    });

    test('account linked budget does not flag deficit after funds are spent', () {
      final accounts = [
        const Account(
          id: 'acc-1',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Grocery Account',
          accountType: AccountType.bank,
          balance: 200.0, // Dropped from 1000 to 200 because 800 was spent
        ),
      ];

      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 1000.0,
          spentAmount: 800.0, // 800 spent from this account
          remainingAmount: 200.0,
          month: '2026-10-01',
          accountId: 'acc-1',
          isActive: true,
        ),
      ];

      final Map<String, double> unspentByAccount = {};
      for (final b in budgets) {
        if (b.isActive && b.accountId != null && b.accountId!.isNotEmpty) {
          final unspent = (b.allocatedAmount - b.spentAmount).clamp(0.0, double.infinity);
          unspentByAccount[b.accountId!] = (unspentByAccount[b.accountId!] ?? 0.0) + unspent;
        }
      }

      Account? deficitAccount;
      double deficitAmount = 0.0;
      for (final entry in unspentByAccount.entries) {
        final acc = accounts.where((a) => a.id == entry.key).firstOrNull;
        if (acc != null && acc.balance < entry.value) {
          deficitAccount = acc;
          deficitAmount = entry.value - acc.balance;
          break;
        }
      }

      // 200 balance equals 200 unspent -> NO deficit!
      expect(deficitAccount, isNull);
      expect(deficitAmount, 0.0);
    });
  });
}
