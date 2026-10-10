import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('CategoryItem deserializes correctly from JSON', () {
    final json = {
      'code': 'OPEX-DINING',
      'category': 'Dining',
      'is_system': true,
      'is_active': false,
      'keywords': ['al baik', 'kfc'],
    };
    final item = CategoryItem.fromJson(json);
    expect(item.code, 'OPEX-DINING');
    expect(item.name, 'Dining');
    expect(item.isSystem, true);
    expect(item.isActive, false);
    expect(item.keywords.length, 2);
    expect(item.keywords, contains('al baik'));
  });

  test('CategoryItem handles missing optional fields gracefully', () {
    final json = {
      'code': 'CUSTOM-FARM',
      'category': 'Farm',
    };
    final item = CategoryItem.fromJson(json);
    expect(item.code, 'CUSTOM-FARM');
    expect(item.name, 'Farm');
    expect(item.isSystem, false);
    expect(item.isActive, true);
    expect(item.keywords, isEmpty);
  });
}
