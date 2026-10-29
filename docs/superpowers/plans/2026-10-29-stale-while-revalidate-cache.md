# Stale-While-Revalidate In-Memory Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the 3–5 second page loading delay on Dashboard and Budget Management screens, achieving sub-second (< 300ms perceived) instant page navigation via Stale-While-Revalidate in-memory caching and removal of UI blocking repair routines.

**Architecture:** 
1. Cache category libraries and salary cycles inside `BudgetProvider` so that subsequent screen visits retrieve them in 0 ms.
2. Remove `BudgetRepairService.repairHouseholdBudgets` from UI `initState()` lifecycles, ensuring repair/recalculation is never run as a blocking UI task.
3. Decouple `_BudgetDashboard` and `BudgetManagementScreen` from redundant `users.select('household_id')` queries by consuming state from parent/providers.
4. Parallelize independent queries (`income_records`, `accounts`) using `Future.wait`.

**Tech Stack:** Flutter 3.22+, Dart 3.x, Provider (`ChangeNotifierProvider`), Supabase Flutter client.

**Spec:** In-memory Stale-While-Revalidate architecture agreed upon in brainstorming (Phase 1 client-side performance enhancement).

## Global Constraints
- Zero `flutter analyze` errors or warnings.
- All existing Flutter tests must pass: `cd flutter_app && flutter test`.
- No new external package dependencies (use existing `provider` and in-memory caching).
- Maintain trilingual RTL/LTR support without changing user-facing strings.
- Never run `BudgetRepairService.repairHouseholdBudgets()` on UI widget `initState()`.

---

## File Structure

```
flutter_app/
├── lib/
│   ├── providers/
│   │   └── budget_provider.dart          # Modified: add category library cache and silent revalidation
│   ├── screens/
│   │   └── home/
│   │       ├── dashboard_screen.dart     # Modified: remove repair from initState, receive hid, parallelize setup
│   │       └── budget_management_screen.dart # Modified: consume cached categories & cycles, parallelize income/accounts
│   └── services/
│       └── budget_repair_service.dart    # Preserved as standalone utility; removed from screen render paths
└── test/
    ├── providers/
    │   └── budget_provider_cache_test.dart # New: test category caching & revalidation behavior
    └── screens/
        └── budget_instant_load_test.dart   # New: test instant load without repair invocation
```

---

### Task 1: Add Category Library & Cycle In-Memory Caching to `BudgetProvider`

**Files:**
- Modify: `flutter_app/lib/providers/budget_provider.dart`
- Test: `flutter_app/test/providers/budget_provider_cache_test.dart`

**Interfaces:**
- Consumes: `ApiService.instance.fetchHouseholdCategories(householdId)`
- Produces: 
  - `Map<String, List<CategoryItem>>? get cachedCategories`
  - `Future<Map<String, List<CategoryItem>>> getHouseholdCategories(String householdId, {bool forceRefresh = false})`
  - `List<SalaryCycleInfo> get cycles`

- [ ] **Step 1: Write the failing unit test**
Create `flutter_app/test/providers/budget_provider_cache_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/services/api_service.dart';

class MockBudgetApi extends ApiService {
  int fetchCategoriesCallCount = 0;

  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async {
    fetchCategoriesCallCount++;
    return {
      'active': [
        CategoryItem(code: 'OPEX-FOOD', name: 'Food', isSystem: true),
      ],
      'archived': [],
    };
  }
}

void main() {
  test('BudgetProvider caches categories and does not re-fetch unless forced', () async {
    final mockApi = MockBudgetApi();
    final provider = BudgetProvider(api: mockApi);

    // First fetch
    final cats1 = await provider.getHouseholdCategories('hid-1');
    expect(cats1['active']?.length, 1);
    expect(mockApi.fetchCategoriesCallCount, 1);

    // Second fetch - should use cache
    final cats2 = await provider.getHouseholdCategories('hid-1');
    expect(cats2['active']?.length, 1);
    expect(mockApi.fetchCategoriesCallCount, 1); // No increase

    // Force refresh
    await provider.getHouseholdCategories('hid-1', forceRefresh: true);
    expect(mockApi.fetchCategoriesCallCount, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/providers/budget_provider_cache_test.dart`
Expected: FAIL (method `getHouseholdCategories` does not exist on `BudgetProvider`).

- [ ] **Step 3: Implement category caching in `BudgetProvider`**
In `flutter_app/lib/providers/budget_provider.dart`:
Add cached fields and `getHouseholdCategories`:
```dart
  Map<String, List<CategoryItem>>? _cachedHouseholdCategories;
  DateTime? _categoriesLastFetched;

  Map<String, List<CategoryItem>>? get cachedCategories => _cachedHouseholdCategories;

  Future<Map<String, List<CategoryItem>>> getHouseholdCategories(
    String householdId, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final isStale = _categoriesLastFetched == null ||
        now.difference(_categoriesLastFetched!).inMinutes > 15;

    if (!forceRefresh && _cachedHouseholdCategories != null && !isStale) {
      return _cachedHouseholdCategories!;
    }

    try {
      final res = await _api.fetchHouseholdCategories(householdId);
      _cachedHouseholdCategories = res;
      _categoriesLastFetched = now;
      notifyListeners();
      return res;
    } catch (e) {
      if (_cachedHouseholdCategories != null) {
        return _cachedHouseholdCategories!;
      }
      rethrow;
    }
  }
```
Update `_clearData()` to also reset `_cachedHouseholdCategories = null; _categoriesLastFetched = null;`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/providers/budget_provider_cache_test.dart`
Expected: PASS.

---

### Task 2: Remove `BudgetRepairService` from Screen Lifecycles and Parallelize Dashboard

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart:188-255`
- Test: `flutter_app/test/screens/dashboard_no_repair_test.dart`

**Interfaces:**
- Consumes: `DashboardScreenState._householdId`, `BudgetProvider`
- Produces: `_BudgetDashboard(householdId: hid)` with parallelized `Future.wait` for setup, accounts count, and income.

- [x] **Step 1: Write widget test verifying Dashboard initialization without repair**
Create `flutter_app/test/screens/dashboard_no_repair_test.dart` verifying that `_BudgetDashboard` renders without calling `recalculateBudgets`.

- [x] **Step 2: Run test to verify current baseline**
Run: `flutter test test/screens/dashboard_no_repair_test.dart`

- [x] **Step 3: Refactor `_BudgetDashboard` in `dashboard_screen.dart`**
1. Update `_BudgetDashboard` to accept `final String? householdId;`.
2. In `_BudgetDashboardState`:
   - Remove `BudgetRepairService.instance.repairHouseholdBudgets(hid);`.
   - Remove redundant `_fetchCycles(hid);` (cycles are already in `SalaryCycleService` and `BudgetProvider`).
   - Group independent remote lookups into parallel execution:
     ```dart
     Future<void> _loadDashboardData(String hid) async {
       await Future.wait([
         _fetchSetup(hid),
         _fetchAccountsCount(hid),
         _fetchCycleIncome(hid, _currentCycleKey),
       ]);
     }
     ```
3. Pass `_householdId` from `DashboardScreenState` down to `_BudgetDashboard(householdId: _householdId)` to prevent querying `users` twice.

- [x] **Step 4: Run test to verify it passes**
Run: `flutter test test/screens/dashboard_no_repair_test.dart`
Expected: PASS.

---

### Task 3: Optimize `BudgetManagementScreen` with In-Memory Caching & Parallel Hydration

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:60-155`
- Test: `flutter_app/test/screens/budget_management_instant_load_test.dart`

**Interfaces:**
- Consumes: `BudgetProvider.getHouseholdCategories`, `HouseholdRoleProvider`
- Produces: `_loadStaticData()` with Stale-While-Revalidate (render existing `_staticData` immediately, revalidate silently).

- [ ] **Step 1: Write test for instant load in `BudgetManagementScreen`**
Create `flutter_app/test/screens/budget_management_instant_load_test.dart`:
Verify that `BudgetManagementScreen` uses cached categories from `BudgetProvider` without invoking `BudgetRepairService` or stalling on 6 serial awaits.

- [ ] **Step 2: Run test to verify baseline failure**
Run: `flutter test test/screens/budget_management_instant_load_test.dart`

- [ ] **Step 3: Refactor `_loadStaticData()` in `budget_management_screen.dart`**
1. Remove `BudgetRepairService.instance.repairHouseholdBudgets(hid);`.
2. Replace direct API fetch of categories with:
   ```dart
   final catData = await context.read<BudgetProvider>().getHouseholdCategories(hid);
   ```
3. Read `role` and `household_id` from `context.read<HouseholdRoleProvider>()` when already available, falling back to a single user query only if not yet set.
4. Parallelize income and accounts fetching:
   ```dart
   final results = await Future.wait([
     AccountService.instance.getCycleIncome(hid, _currentCycleKey).catchError((_) => <IncomeRecord>[]),
     AccountService.instance.getAccounts(hid).catchError((_) => <Account>[]),
   ]);
   final incomeRecords = results[0] as List<IncomeRecord>;
   final accounts = results[1] as List<Account>;
   ```
5. If `_staticData` was already loaded, do not blank out the UI with a 5-item shimmer during background refresh.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/screens/budget_management_instant_load_test.dart`
Expected: PASS.

---

### Task 4: Full App Regression & Analyzer Gate

**Files:**
- Verification only

- [ ] **Step 1: Run Flutter static analyzer**
Run: `cd flutter_app && flutter analyze`
Expected: `No issues found! (zero warnings, zero errors)`

- [ ] **Step 2: Run entire Flutter test suite**
Run: `cd flutter_app && flutter test`
Expected: All test suites pass.

- [ ] **Step 3: Verification of tab switch latency**
Ensure no screen invokes `POST /budgets/recalculate` on tab load and all tab switches render in < 300ms.

