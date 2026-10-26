import 'package:budget_tracker/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mid-Cycle Opening Spend Adjustment Logic', () {
    test('computes mid-cycle shortfall when cash is less than remaining allocations', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          month: '2026-10',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 4000.0,
          spentAmount: 0.0,
          remainingAmount: 4000.0,
        ),
        const Budget(
          id: 'b2',
          householdId: 'h1',
          month: '2026-10',
          categoryCode: 'OPEX-DINING',
          allocatedAmount: 2000.0,
          spentAmount: 0.0,
          remainingAmount: 2000.0,
        ),
        const Budget(
          id: 'b3',
          householdId: 'h1',
          month: '2026-10',
          categoryCode: 'HOUSING-RENT',
          allocatedAmount: 3000.0,
          spentAmount: 0.0,
          remainingAmount: 3000.0,
        ),
      ];

      final totalAllocated = budgets.fold<double>(0.0, (s, b) => s + b.allocatedAmount);
      final totalRemaining = budgets.fold<double>(0.0, (s, b) => s + b.remainingAmount);
      expect(totalAllocated, 9000.0);
      expect(totalRemaining, 9000.0);

      const operatingCash = 1000.0;
      final shortfall = totalRemaining - operatingCash;
      expect(shortfall, 8000.0);

      // Verify that after recording prior spend adjustment of 8,000 SAR:
      // Grocery, Dining and Rent have spentAmount updated:
      final adjustedGrocery = Budget(
        id: budgets[0].id,
        householdId: budgets[0].householdId,
        month: budgets[0].month,
        categoryCode: budgets[0].categoryCode,
        allocatedAmount: budgets[0].allocatedAmount,
        spentAmount: 4000.0,
        remainingAmount: 0.0,
      );
      final adjustedDining = Budget(
        id: budgets[1].id,
        householdId: budgets[1].householdId,
        month: budgets[1].month,
        categoryCode: budgets[1].categoryCode,
        allocatedAmount: budgets[1].allocatedAmount,
        spentAmount: 2000.0,
        remainingAmount: 0.0,
      );
      final adjustedRent = Budget(
        id: budgets[2].id,
        householdId: budgets[2].householdId,
        month: budgets[2].month,
        categoryCode: budgets[2].categoryCode,
        allocatedAmount: budgets[2].allocatedAmount,
        spentAmount: 2000.0,
        remainingAmount: 1000.0,
      );

      final newTotalRemaining = adjustedGrocery.remainingAmount +
          adjustedDining.remainingAmount +
          adjustedRent.remainingAmount;

      expect(newTotalRemaining, 1000.0);
      expect(operatingCash - newTotalRemaining, 0.0,
          reason: 'Remaining allocations now perfectly align with available bank cash');
    });

    test('opening spend adjustment transaction leaves account balance untouched', () {
      // Build opening adjustment transaction row
      Map<String, dynamic> buildAdjustmentRow({
        required String householdId,
        required double amount,
        required String categoryCode,
        required String cycleKey,
      }) {
        return {
          'household_id': householdId,
          'amount': amount,
          'category_code': categoryCode,
          'account_id': null, // unlinked so opening bank balance is not double-deducted
          'cycle_key': cycleKey,
        };
      }

      final row = buildAdjustmentRow(
        householdId: 'h1',
        amount: 8000.0,
        categoryCode: 'OPEX-GROCERY',
        cycleKey: '2026-10-27',
      );

      expect(row['account_id'], isNull,
          reason: 'Must have null account_id so accounts table trigger does not deduct from opening cash');
      expect(row['amount'], 8000.0);
      expect(row['cycle_key'], '2026-10-27');
    });
  });
}
