import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/budgets/rebalance_budget_sheet.dart';

void main() {
  group('Real-Cash Operating Budget Benchmark', () {
    test('computes operatingCash excluding savings and crypto accounts', () {
      final accounts = [
        const Account(
          id: '1',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Al Rajhi Current',
          accountType: AccountType.bank,
          balance: 7500.0,
        ),
        const Account(
          id: '2',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'STC Pay',
          accountType: AccountType.eWallet,
          balance: 1500.0,
        ),
        const Account(
          id: '3',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Emergency Fund',
          accountType: AccountType.savings,
          balance: 50000.0,
        ),
        const Account(
          id: '4',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Bitcoin Vault',
          accountType: AccountType.crypto,
          balance: 20000.0,
        ),
      ];

      final operatingCash = accounts
          .where((a) => !a.isArchived && a.accountType.isOperatingPool)
          .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));

      // Operating cash is strictly Bank (7,500) + Wallet (1,500) = 9,000 SAR.
      // Savings (50,000) and Crypto (20,000) are protected and excluded!
      expect(operatingCash, 9000.0);
    });

    test('rebalance assistant reduces allocations to operating cash', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-UTILITIES',
          allocatedAmount: 2000,
          spentAmount: 0,
          remainingAmount: 2000,
          month: '2026-10-01',
        ),
        const Budget(
          id: 'b2',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 5000,
          spentAmount: 0,
          remainingAmount: 5000,
          month: '2026-10-01',
        ),
        const Budget(
          id: 'b3',
          householdId: 'h1',
          categoryCode: 'OPEX-SHOPPING',
          allocatedAmount: 3000,
          spentAmount: 0,
          remainingAmount: 3000,
          month: '2026-10-01',
        ),
      ];

      // Total allocated = 10,000 SAR. Operating cash = 9,000 SAR.
      final adjusted = computeProportionalRebalance(
        budgets: budgets,
        targetTotal: 9000.0,
      );

      expect(adjusted['OPEX-UTILITIES'], 2000.0); // Fixed protected
      expect(adjusted['OPEX-GROCERY'], 4375.0);
      expect(adjusted['OPEX-SHOPPING'], 2625.0);
      expect(adjusted.values.reduce((a, b) => a + b), 9000.0);
    });
  });
}
