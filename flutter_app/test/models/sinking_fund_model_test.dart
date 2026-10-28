import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  group('Budget Sinking Fund Helpers', () {
    test('detects sinking fund configuration on sub-category', () {
      final b = Budget.fromMap({
        'id': 'b1',
        'household_id': 'hh1',
        'category_code': 'OPEX-FUEL',
        'allocated_amount': 200.0,
        'spent_amount': 0.0,
        'remaining_amount': 200.0,
        'sub_allocations': {
          'car_maintenance': 200.0,
          '_sinking_fund': {
            'car_maintenance': {'accumulate': true, 'base_amount': 100.0},
          },
        },
      });

      expect(b.subAllocations['car_maintenance'], 200.0);
      expect(b.isSinkingFund('car_maintenance'), isTrue);
      expect(b.sinkingFundBase('car_maintenance'), 100.0);
      expect(b.isSinkingFund('gas_fuel'), isFalse);
    });

    test('detects sinking fund configuration on parent category', () {
      final b = Budget.fromMap({
        'id': 'b2',
        'household_id': 'hh1',
        'category_code': 'OPEX-ENTERTAINMENT',
        'allocated_amount': 300.0,
        'spent_amount': 0.0,
        'remaining_amount': 300.0,
        'sub_allocations': {
          '_sinking_fund': {
            '_parent': {'accumulate': true, 'base_amount': 300.0},
          },
        },
      });

      expect(b.isSinkingFund(), isTrue);
      expect(b.sinkingFundBase(), 300.0);
      expect(b.isSinkingFund('cinema'), isFalse);
    });
  });
}
