import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';

class _FakeBudgetApi extends BudgetApiClient {
  final Map<String, Completer<Map<String, dynamic>>> breakdowns = {};
  int payday = 25;

  @override
  Future<List<Map<String, dynamic>>> fetchSalaryCycles({required String householdId, int? paydayDay}) async => [
        {'cycle_key': '2026-10', 'cycle_start': '2026-09-25', 'cycle_end': '2026-10-24', 'is_current': false},
        {'cycle_key': '2026-11', 'cycle_start': '2026-10-25', 'cycle_end': '2026-11-24', 'is_current': true},
      ];

  @override
  Future<Map<String, dynamic>> fetchSalaryCycleForecast({required String householdId, int? paydayDay}) async =>
      {'status': 'success'};

  @override
  Future<int> fetchHouseholdPayday({required String householdId}) async => payday;

  @override
  Future<Map<String, dynamic>> fetchBudgetBreakdown({required String householdId, String? cycleKey}) {
    final key = '$householdId/$cycleKey';
    return (breakdowns[key] ??= Completer<Map<String, dynamic>>()).future;
  }

  void answer(String householdId, String cycleKey, String categoryCode) {
    (breakdowns['$householdId/$cycleKey'] ??= Completer<Map<String, dynamic>>()).complete({
      'categories': [
        {'category_code': categoryCode, 'category': categoryCode, 'allocated_amount': 100, 'spent_amount': 10, 'remaining_amount': 90},
      ],
    });
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SalaryCycleService.paydayDay = SalaryCycleService.defaultPaydayDay;
  });

  tearDown(() {
    SalaryCycleService.paydayDay = SalaryCycleService.defaultPaydayDay;
  });

  test('MOB-17: a slow breakdown for a previously selected cycle cannot overwrite the newer one', () async {
    final fake = _FakeBudgetApi();
    final provider = BudgetProvider(api: ApiService(budget: fake));

    final initFuture = provider.init('h-1');
    await Future<void>.delayed(Duration.zero);
    fake.answer('h-1', '2026-11', 'CURRENT');
    await initFuture;
    expect(provider.categories.single.categoryCode, 'CURRENT');

    fake.breakdowns.remove('h-1/2026-11');
    final older = provider.selectCycle(0); // user taps the October cycle...
    final newer = provider.selectCycle(1); // ...then quickly back to November
    fake.answer('h-1', '2026-11', 'NOVEMBER');
    await newer;
    fake.answer('h-1', '2026-10', 'OCTOBER'); // the stale October answer arrives last
    await older;

    expect(provider.activeCycle!.cycleKey, '2026-11');
    expect(provider.categories.single.categoryCode, 'NOVEMBER');
  });

  test('MOB-13: refresh applies the household payday to client cycle arithmetic', () async {
    final fake = _FakeBudgetApi()..payday = 25;
    final provider = BudgetProvider(api: ApiService(budget: fake));
    final f = provider.init('h-1');
    await Future<void>.delayed(Duration.zero);
    fake.answer('h-1', '2026-11', 'X');
    await f;

    expect(SalaryCycleService.paydayDay, 25);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(SalaryCycleService.paydayPrefKey), 25);
  });

  test('MOB-16: switching household clears the previous household budgets immediately', () async {
    final fake = _FakeBudgetApi();
    final provider = BudgetProvider(api: ApiService(budget: fake));
    final f = provider.init('h-1');
    await Future<void>.delayed(Duration.zero);
    fake.answer('h-1', '2026-11', 'H1-ONLY');
    await f;
    expect(provider.categories, isNotEmpty);

    final g = provider.init('h-2');
    expect(provider.categories, isEmpty);
    expect(provider.cycles, isEmpty);
    await Future<void>.delayed(Duration.zero);
    fake.answer('h-2', '2026-11', 'H2');
    await g;
    expect(provider.categories.single.categoryCode, 'H2');

    provider.reset();
    expect(provider.categories, isEmpty);
  });
}
