import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('Transaction model parses subCategory and beneficiary correctly', () {
    final map = {
      'id': 'tx-123',
      'household_id': 'hh-001',
      'amount': 25.0,
      'currency': 'SAR',
      'merchant': 'Al Baik',
      'category_code': 'OPEX-DINING',
      'sub_category': 'restaurants_dinners',
      'timestamp': '2026-10-11T12:00:00Z',
      'created_at': '2026-10-11T12:00:00Z',
      'paid_by': 'me',
      'beneficiary': 'Sarah',
      'items': [
        {
          'name': 'Broasted Meal',
          'quantity': 1,
          'price': 25.0,
          'sub_category': 'restaurants_dinners',
        }
      ],
    };
    final tx = Transaction.fromMap(map);
    expect(tx.subCategory, equals('restaurants_dinners'));
    expect(tx.paidBy, equals('me'));
    expect(tx.beneficiary, equals('Sarah'));
    expect(tx.items.first['sub_category'], equals('restaurants_dinners'));

    final outMap = tx.toMap();
    expect(outMap['sub_category'], equals('restaurants_dinners'));
    expect(outMap['paid_by'], equals('me'));
    expect(outMap['beneficiary'], equals('Sarah'));
  });

  test('HouseholdDependent parses from JSON correctly', () {
    final map = {
      'id': 'dep-001',
      'household_id': 'hh-001',
      'name': 'Sarah',
      'avatar_icon': 'child',
      'created_at': '2026-10-11T12:00:00Z',
    };
    final dep = HouseholdDependent.fromMap(map);
    expect(dep.name, equals('Sarah'));
    expect(dep.avatarIcon, equals('child'));
    expect(dep.householdId, equals('hh-001'));

    final outMap = dep.toMap();
    expect(outMap['name'], equals('Sarah'));
    expect(outMap['avatar_icon'], equals('child'));
  });
}
