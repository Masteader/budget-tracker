import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/household_setup.dart';

void main() {
  group('Cycle Income Ledger Tests', () {
    test('HouseholdSetupData marks income step done when cycle income is logged', () {
      const setupWithIncome = HouseholdSetupData(
        paydayDay: 27,
        paydayConfirmed: true,
        monthlyIncome: 12000.0, // Cycle income from income_records
      );
      expect(setupWithIncome.isDone(SetupStep.income, hasBudgets: false), isTrue);

      const setupWithoutIncome = HouseholdSetupData(
        paydayDay: 27,
        paydayConfirmed: true,
        monthlyIncome: 0.0,
      );
      expect(setupWithoutIncome.isDone(SetupStep.income, hasBudgets: false), isFalse);
    });
  });
}
