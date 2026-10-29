import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/services/api_service.dart';

class MockBudgetApi extends ApiService {
  int fetchCategoriesCallCount = 0;
  bool shouldThrow = false;

  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async {
    fetchCategoriesCallCount++;
    if (shouldThrow) {
      throw Exception('Network error');
    }
    return {
      'active': [
        const CategoryItem(code: 'OPEX-FOOD', name: 'Food', isSystem: true),
      ],
      'archived': [],
    };
  }
}

void main() {
  group('BudgetProvider category caching', () {
    test('caches categories and does not re-fetch unless forced', () async {
      final mockApi = MockBudgetApi();
      final provider = BudgetProvider(api: mockApi);

      expect(provider.cachedCategories, isNull);

      // First fetch
      final cats1 = await provider.getHouseholdCategories('hid-1');
      expect(cats1['active']?.length, 1);
      expect(mockApi.fetchCategoriesCallCount, 1);
      expect(provider.cachedCategories, isNotNull);
      expect(provider.cachedCategories!['active']?.length, 1);

      // Second fetch - should use cache without calling API
      final cats2 = await provider.getHouseholdCategories('hid-1');
      expect(cats2['active']?.length, 1);
      expect(mockApi.fetchCategoriesCallCount, 1); // No increase

      // Force refresh
      final cats3 = await provider.getHouseholdCategories('hid-1', forceRefresh: true);
      expect(cats3['active']?.length, 1);
      expect(mockApi.fetchCategoriesCallCount, 2);
    });

    test('reset() clears cached categories and causes subsequent call to re-query API', () async {
      final mockApi = MockBudgetApi();
      final provider = BudgetProvider(api: mockApi);

      await provider.getHouseholdCategories('hid-1');
      expect(mockApi.fetchCategoriesCallCount, 1);
      expect(provider.cachedCategories, isNotNull);

      // Reset clears cache
      provider.reset();
      expect(provider.cachedCategories, isNull);

      // Next call re-queries API
      await provider.getHouseholdCategories('hid-1');
      expect(mockApi.fetchCategoriesCallCount, 2);
    });

    test('returns cached categories when API throws an error during refresh', () async {
      final mockApi = MockBudgetApi();
      final provider = BudgetProvider(api: mockApi);

      await provider.getHouseholdCategories('hid-1');
      expect(mockApi.fetchCategoriesCallCount, 1);

      // Make API throw on next call
      mockApi.shouldThrow = true;

      // Force refresh with API throwing - should fall back to cached categories
      final fallbackCats = await provider.getHouseholdCategories('hid-1', forceRefresh: true);
      expect(fallbackCats['active']?.length, 1);
      expect(mockApi.fetchCategoriesCallCount, 2);
    });
  });
}
