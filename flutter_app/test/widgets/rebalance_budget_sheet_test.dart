import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/budgets/rebalance_budget_sheet.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  group('computeProportionalRebalance', () {
    test('proportional shrink protects fixed categories and scales variable ones', () {
      final budgets = <Budget>[
        const Budget(
          id: '1',
          householdId: 'h1',
          categoryCode: 'OPEX-UTILITIES', // Fixed
          allocatedAmount: 2000,
          spentAmount: 0,
          remainingAmount: 2000,
          month: '2026-10-01',
        ),
        const Budget(
          id: '2',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY', // Variable
          allocatedAmount: 5000,
          spentAmount: 0,
          remainingAmount: 5000,
          month: '2026-10-01',
        ),
        const Budget(
          id: '3',
          householdId: 'h1',
          categoryCode: 'OPEX-DINING', // Variable
          allocatedAmount: 3000,
          spentAmount: 0,
          remainingAmount: 3000,
          month: '2026-10-01',
        ),
      ];
      // Total = 10,000 SAR. Target cash = 8,000 SAR. Deficit = 2,000 SAR.
      // Fixed (Utilities) = 2,000 SAR -> remains 2,000 SAR.
      // Variable total = 8,000 SAR.
      // Grocery reduction = 2,000 * (5,000 / 8,000) = 1,250 -> 3,750 SAR.
      // Dining reduction = 2,000 * (3,000 / 8,000) = 750 -> 2,250 SAR.
      final adjusted = computeProportionalRebalance(budgets: budgets, targetTotal: 8000);
      expect(adjusted['OPEX-UTILITIES'], 2000.0);
      expect(adjusted['OPEX-GROCERY'], 3750.0);
      expect(adjusted['OPEX-DINING'], 2250.0);

      final sum = adjusted.values.reduce((a, b) => a + b);
      expect(sum, 8000.0);
    });

    test('returns untouched amounts if current allocations already <= target', () {
      final budgets = <Budget>[
        const Budget(
          id: '1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 1000,
          spentAmount: 0,
          remainingAmount: 1000,
          month: '2026-10-01',
        ),
        const Budget(
          id: '2',
          householdId: 'h1',
          categoryCode: 'OPEX-DINING',
          allocatedAmount: 500,
          spentAmount: 0,
          remainingAmount: 500,
          month: '2026-10-01',
        ),
      ];
      final adjusted = computeProportionalRebalance(budgets: budgets, targetTotal: 3000);
      expect(adjusted['OPEX-GROCERY'], 1000.0);
      expect(adjusted['OPEX-DINING'], 500.0);
    });
  });
}
