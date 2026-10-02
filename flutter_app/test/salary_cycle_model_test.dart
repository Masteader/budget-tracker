import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  group('Salary Cycle & Sub-Budget Models', () {
    test('SalaryCycleInfo parses correctly', () {
      final map = {
        'cycle_key': '2026-10',
        'cycle_start': '2026-09-27',
        'cycle_end': '2026-10-26',
        'label': 'October 2026 Budget (Sep 27 - Oct 26)',
        'month_name': 'October 2026',
        'is_current': true,
      };

      final info = SalaryCycleInfo.fromMap(map);
      expect(info.cycleKey, '2026-10');
      expect(info.cycleStart, '2026-09-27');
      expect(info.cycleEnd, '2026-10-26');
      expect(info.label, 'October 2026 Budget (Sep 27 - Oct 26)');
      expect(info.monthName, 'October 2026');
      expect(info.isCurrent, isTrue);
    });

    test('SubCategoryBreakdownItem parses correctly', () {
      final map = {
        'sub_code': 'meat',
        'name': 'Meat & Poultry',
        'spent_amount': 350.50,
        'transaction_count': 3,
      };

      final item = SubCategoryBreakdownItem.fromMap(map);
      expect(item.subCode, 'meat');
      expect(item.name, 'Meat & Poultry');
      expect(item.spentAmount, 350.50);
      expect(item.transactionCount, 3);
    });

    test('CategoryBreakdownItem parses with nested sub-categories', () {
      final map = {
        'category_code': 'OPEX-GROCERY',
        'category_name': 'Groceries',
        'allocated_amount': 2000.0,
        'spent_amount': 750.0,
        'remaining_amount': 1250.0,
        'previous_cycle_delta': 150.0,
        'sub_categories': [
          {
            'sub_code': 'meat',
            'name': 'Meat & Poultry',
            'spent_amount': 350.0,
            'transaction_count': 2,
          },
          {
            'sub_code': 'vegetables_fruit',
            'name': 'Fresh Produce',
            'spent_amount': 200.0,
            'transaction_count': 4,
          },
        ],
      };

      final cat = CategoryBreakdownItem.fromMap(map);
      expect(cat.categoryCode, 'OPEX-GROCERY');
      expect(cat.categoryName, 'Groceries');
      expect(cat.allocatedAmount, 2000.0);
      expect(cat.spentAmount, 750.0);
      expect(cat.remainingAmount, 1250.0);
      expect(cat.previousCycleDelta, 150.0);
      expect(cat.subCategories.length, 2);
      expect(cat.subCategories[0].name, 'Meat & Poultry');
      expect(cat.usagePercent, 0.375);
    });

    test('Budget parses with cycleKey and previousCycleDelta', () {
      final map = {
        'id': 'b-123',
        'household_id': 'h-456',
        'month': '2026-10-01',
        'category_code': 'OPEX-DINING',
        'allocated_amount': 1200.0,
        'spent_amount': 400.0,
        'remaining_amount': 800.0,
        'cycle_key': '2026-10',
        'previous_cycle_delta': -85.5,
        'is_active': true,
      };

      final b = Budget.fromMap(map);
      expect(b.cycleKey, '2026-10');
      expect(b.previousCycleDelta, -85.5);
      expect(b.isActive, isTrue);
      expect(b.remainingAmount, 800.0);
    });
  });
}
