import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/payday_outlook.dart';

void main() {
  group('PaydayOutlook Tests (CRITICAL-01)', () {
    final cycleStart = DateTime.utc(2026, 10, 27);
    final cycleEnd = DateTime.utc(2026, 11, 26);

    test('left, afterCommitments, safeDaily with income set and no operatingCash', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 5000,
          spentAmount: 3000,
          remainingAmount: 2000,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      // 10 days left: today is Nov 17 (Nov 17 to Nov 26 inclusive = 10 days)
      final today = DateTime.utc(2026, 11, 17);

      final outlook = PaydayOutlook.compute(
        budgets: budgets,
        monthlyIncome: 10000.0,
        operatingCash: null,
        pendingCommitments: 4162.0,
        today: today,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      // left = monthlyIncome - totalSpent = 10000 - 3000 = 7000
      expect(outlook.left, 7000.0);
      // afterCommitments = left - pendingCommitments = 7000 - 4162 = 2838
      expect(outlook.afterCommitments, 2838.0);
      expect(outlook.daysLeft, 10);
      // safeDaily = afterCommitments / daysLeft = 2838 / 10 = 283.8
      expect(outlook.safeDaily, 283.8);
    });

    test('operatingCash takes precedence over monthlyIncome as verified physical cash SSOT', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 5000,
          spentAmount: 3000,
          remainingAmount: 2000,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      final today = DateTime.utc(2026, 11, 17);

      final outlook = PaydayOutlook.compute(
        budgets: budgets,
        monthlyIncome: 10000.0,
        operatingCash: 6370.26,
        pendingCommitments: 4162.0,
        today: today,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      // Base reflects cycle capacity: operatingCash + totalSpent = 6370.26 + 3000 = 9370.26
      expect(outlook.base, 9370.26);
      // Left reflects verified physical cash = 6370.26
      expect(outlook.left, 6370.26);
      // Invariant: left + totalSpent == base
      expect(outlook.left + outlook.totalSpent, outlook.base);
      // afterCommitments = 6370.26 - 4162.0 = 2208.26
      expect(outlook.afterCommitments, closeTo(2208.26, 0.001));
      expect(outlook.safeDaily, closeTo(2208.26 / 10, 0.001));
    });

    test('left with income null reflects liquid balance gross of commitments', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 2000,
          spentAmount: 1000,
          remainingAmount: 1000,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      final today = DateTime.utc(2026, 11, 17);

      final outlook = PaydayOutlook.compute(
        budgets: budgets,
        monthlyIncome: null,
        operatingCash: 6370.26,
        pendingCommitments: 4162.0,
        today: today,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      // Base is liquidBalance + spent = 6370.26 + 1000 = 7370.26
      // left is base - spent = 6370.26 (the liquid balance)
      expect(outlook.left, 6370.26);
      // afterCommitments = 6370.26 - 4162.0 = 2208.26
      expect(outlook.afterCommitments, closeTo(2208.26, 0.001));
      expect(outlook.safeDaily, closeTo(2208.26 / 10, 0.001));
    });

    test('deficit when pendingCommitments exceeds left: afterCommitments is negative and safeDaily is 0', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 1000,
          spentAmount: 500,
          remainingAmount: 500,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      final today = DateTime.utc(2026, 11, 17);

      final outlook = PaydayOutlook.compute(
        budgets: budgets,
        monthlyIncome: 1000.0,
        operatingCash: 500.0,
        pendingCommitments: 2000.0, // exceeds left (500)
        today: today,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      expect(outlook.left, 500.0);
      expect(outlook.afterCommitments, -1500.0);
      expect(outlook.safeDaily, 0.0);
    });

    test('daysLeft is 0: no division by zero', () {
      final budgets = [
        const Budget(
          id: 'b1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 1000,
          spentAmount: 500,
          remainingAmount: 500,
          month: '2026-11-01',
          isActive: true,
        ),
      ];

      // After cycle end: daysLeft is 0
      final today = DateTime.utc(2026, 11, 28);

      final outlook = PaydayOutlook.compute(
        budgets: budgets,
        monthlyIncome: 1000.0,
        operatingCash: 500.0,
        pendingCommitments: 100.0,
        today: today,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      expect(outlook.daysLeft, 0);
      expect(outlook.safeDaily, 0.0);
      expect(outlook.isClosed, isTrue);
    });
  });
}
