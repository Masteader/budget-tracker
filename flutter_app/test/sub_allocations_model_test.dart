import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  group('Sub Allocations Models Test', () {
    test('Budget parses sub_allocations from map correctly', () {
      final map = {
        'id': 'b1',
        'household_id': 'h1',
        'month': '2026-10-01',
        'category_code': 'OPEX-UTILITIES',
        'allocated_amount': 3750.0,
        'spent_amount': 3000.0,
        'remaining_amount': 750.0,
        'cycle_key': '2026-10',
        'previous_cycle_delta': 0.0,
        'is_active': true,
        'sub_allocations': {
          'housing_rent': 3000.0,
          'electricity_sec': 350.0,
          'fiber_internet': 250.0,
          'mobile_sims': 100.0,
          'water_municipal': 50.0,
        },
      };

      final budget = Budget.fromMap(map);
      expect(budget.allocatedAmount, 3750.0);
      expect(budget.subAllocations['housing_rent'], 3000.0);
      expect(budget.subAllocations['electricity_sec'], 350.0);
      expect(budget.subAllocations.length, 5);
    });

    test('SubCategoryBreakdownItem parses allocatedAmount and calculates usagePercent', () {
      final map = {
        'sub_code': 'housing_rent',
        'name': 'Housing Rent',
        'allocated_amount': 3000.0,
        'spent_amount': 1500.0,
        'transaction_count': 1,
      };

      final item = SubCategoryBreakdownItem.fromMap(map);
      expect(item.subCode, 'housing_rent');
      expect(item.name, 'Housing Rent');
      expect(item.allocatedAmount, 3000.0);
      expect(item.spentAmount, 1500.0);
      expect(item.usagePercent, 0.5);
    });
  });
}
