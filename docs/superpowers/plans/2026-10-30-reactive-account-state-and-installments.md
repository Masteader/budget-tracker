# Reactive Account State, Budget Allocation Refinement & Installment Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate manual pull-to-refresh across all balance and transaction updates via a reactive `AccountProvider`, distinguish live operating cash from planned cycle funding capacity on the Budgets tab, synchronize transaction categories with active budget categories, render sub-category chips dynamically, and provide full installment editing from the dashboard.

**Architecture:** Introduce `AccountProvider` extending `ChangeNotifier` into the top-level `MultiProvider` to stream account balances and cycle income via Supabase Realtime and broadcast immediate updates on financial actions. Connect `DashboardScreen`, `BudgetHeroCard`, and `BudgetManagementScreen` to this reactive provider. Dynamically populate category pickers from `BudgetProvider` with immediate cache invalidation. Render sub-category chips from budget row allocations and database records instead of a static map. Provide an edit modal and API integration in `InstallmentPlansCard`.

**Tech Stack:** Flutter 3.3+, Dart, Provider (6.1.2), Supabase Flutter (Realtime channels & RPCs), Python FastAPI backend, Google Fonts, Flutter Localizations (trilingual: AR, EN, UR).

**Spec:** [`docs/superpowers/specs/2026-10-30-reactive-account-state-and-installments-design.md`](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-30-reactive-account-state-and-installments-design.md)

## Global Constraints

- Zero SMS policy: No SMS parsing or permissions.
- Trilingual requirement: English, Arabic (primary RTL), and Urdu with zero hardcoded strings.
- Pure design system adherence: Sovereign OS & Iced Ocean HUD theme; zero raw hex colors in widgets (`context.scaffoldBg`, `context.electricTeal`, etc.).
- Multi-tenancy & RLS: All queries scoped strictly to `household_id`.
- Test-Driven Development (TDD): Failing test written before code; 0 `flutter analyze` warnings; 100% test pass rate.
- External Argon Audit Compliance: Develop strictly on dedicated branch `feat/reactive-account-state-and-installments`; no direct commits to `main`.

---

## File Structure & Responsibilities

| File Path | Responsibility |
| :--- | :--- |
| `flutter_app/lib/providers/account_provider.dart` | Reactive state management for accounts, live operating cash, net worth, and cycle income records. |
| `flutter_app/lib/main.dart` | Registers `AccountProvider` in root `MultiProvider`. |
| `flutter_app/lib/screens/home/dashboard_screen.dart` | Consumes `AccountProvider` for live balance updates without pull-to-refresh. |
| `flutter_app/lib/screens/home/budget_management_screen.dart` | Refines allocations card to cleanly separate Cycle Income Capacity from live Operating Cash; renders dynamic sub-category chips. |
| `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart` | Queries active household categories dynamically from `BudgetProvider`; broadcasts account updates upon saving. |
| `flutter_app/lib/providers/budget_provider.dart` | Exposes `activeCategories` and provides `invalidateCategoriesCache()`. |
| `flutter_app/lib/widgets/dashboard/installment_plans_card.dart` | Adds Edit Plan modal and dispatches updates; triggers `AccountProvider.refresh()` on payment. |
| `flutter_app/lib/providers/installment_provider.dart` | Adds `updatePlan(...)` method. |
| `flutter_app/lib/services/api_service.dart` | Adds `updateInstallmentPlan(...)` client method. |
| `flutter_app/lib/utils/refresh_app_data.dart` | Unified helper function `refreshGlobalAppData(context)` to refresh all providers in parallel. |
| `ai_service/salary_cycle.py` | Adds `OPEX-FAMILY-SUPPORT` to backend `initial_core` default categories. |
| `flutter_app/lib/l10n/app_localizations.dart` | Trilingual translation keys across EN, AR, UR. |

---

### Task 1: Create Reactive `AccountProvider` & Register in `MultiProvider`

**Files:**
- Create: `flutter_app/lib/providers/account_provider.dart`
- Create: `flutter_app/test/providers/account_provider_test.dart`
- Modify: `flutter_app/lib/main.dart:102-112`

**Interfaces:**
- Consumes: `AccountService.instance.getAccounts()`, `AccountService.instance.getCycleIncome()`, `AccountService.instance.streamAccounts()`.
- Produces: `AccountProvider` with getters `accounts`, `operatingCash`, `totalNetWorth`, `cycleIncomeRecords`, `cycleIncomeTotal`, `isLoading`, and methods `init(hid, cycleKey)`, `refresh()`, `updateBalance(...)`.

- [ ] **Step 1: Write the failing unit test for `AccountProvider`**

```dart
// flutter_app/test/providers/account_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/account_type.dart';
import 'package:budget_tracker/providers/account_provider.dart';

void main() {
  test('AccountProvider calculates operatingCash and totalNetWorth correctly', () {
    final provider = AccountProvider.test(
      mockAccounts: [
        Account(
          id: 'acc-1',
          householdId: 'hh-1',
          ownerUserId: 'u-1',
          name: 'Rajhi Main',
          accountType: AccountType.checking,
          currency: 'SAR',
          balance: 7076.0,
          isSharedPool: true,
          colorHex: '#10B981',
          iconName: 'account_balance',
          isArchived: false,
          createdAt: DateTime.now(),
        ),
        Account(
          id: 'acc-2',
          householdId: 'hh-1',
          ownerUserId: 'u-1',
          name: 'Emergency Savings',
          accountType: AccountType.savings,
          currency: 'SAR',
          balance: 10000.0,
          isSharedPool: true,
          colorHex: '#3B82F6',
          iconName: 'savings',
          isArchived: false,
          createdAt: DateTime.now(),
        ),
      ],
    );

    expect(provider.operatingCash, 7076.0);
    expect(provider.totalNetWorth, 17076.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/providers/account_provider_test.dart`  
Expected: FAIL (cannot find `AccountProvider`).

- [ ] **Step 3: Implement `AccountProvider`**

```dart
// flutter_app/lib/providers/account_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../services/account_service.dart';

class AccountProvider extends ChangeNotifier {
  final AccountService _service;
  StreamSubscription<List<Account>>? _streamSub;

  String? _householdId;
  String? _cycleKey;
  List<Account> _accounts = [];
  List<IncomeRecord> _cycleIncomeRecords = [];
  bool _isLoading = false;
  String? _error;

  AccountProvider({AccountService? service}) : _service = service ?? AccountService.instance;

  @visibleForTesting
  AccountProvider.test({required List<Account> mockAccounts, List<IncomeRecord> mockIncome = const []})
      : _service = AccountService.instance,
        _accounts = mockAccounts,
        _cycleIncomeRecords = mockIncome;

  List<Account> get accounts => _accounts;
  List<IncomeRecord> get cycleIncomeRecords => _cycleIncomeRecords;
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get operatingCash => _accounts
      .where((a) => !a.isArchived && a.accountType.isOperatingPool)
      .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));

  double get totalNetWorth => _accounts
      .where((a) => !a.isArchived)
      .fold<double>(0.0, (s, a) => s + a.balance);

  double get cycleIncomeTotal =>
      _cycleIncomeRecords.fold<double>(0.0, (s, r) => s + r.netAmount);

  Future<void> init(String householdId, String cycleKey) async {
    if (_householdId == householdId && _cycleKey == cycleKey && _accounts.isNotEmpty) return;
    _householdId = householdId;
    _cycleKey = cycleKey;
    _listenToRealtime(householdId);
    await refresh();
  }

  void _listenToRealtime(String householdId) {
    _streamSub?.cancel();
    _streamSub = _service.streamAccounts(householdId).listen(
      (list) {
        _accounts = list;
        notifyListeners();
      },
      onError: (err) {
        _error = err.toString();
        notifyListeners();
      },
    );
  }

  Future<void> refresh() async {
    if (_householdId == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      final accFuture = _service.getAccounts(_householdId!);
      final incFuture = _cycleKey != null
          ? _service.getCycleIncome(_householdId!, _cycleKey!)
          : Future.value(<IncomeRecord>[]);
      final results = await Future.wait([accFuture, incFuture]);
      _accounts = results[0] as List<Account>;
      _cycleIncomeRecords = results[1] as List<IncomeRecord>;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _streamSub?.cancel();
    _householdId = null;
    _cycleKey = null;
    _accounts = [];
    _cycleIncomeRecords = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Register in `MultiProvider` in `main.dart`**

Modify `flutter_app/lib/main.dart` to insert `ChangeNotifierProvider(create: (_) => AccountProvider())` into `providers` list.

- [ ] **Step 5: Run tests to verify pass**

Run: `cd flutter_app && flutter test test/providers/account_provider_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/providers/account_provider.dart flutter_app/lib/main.dart flutter_app/test/providers/account_provider_test.dart
git commit -m "feat(state): create reactive AccountProvider and wire into MultiProvider"
```

---

### Task 2: Refactor `DashboardScreen` and `BudgetHeroCard` to Consume `AccountProvider` Reactively

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart:284-298, 479-507`
- Modify: `flutter_app/lib/widgets/dashboard/budget_hero_card.dart`
- Test: `flutter_app/test/screens/dashboard_no_repair_test.dart`

**Interfaces:**
- Consumes: `context.watch<AccountProvider>().operatingCash`, `context.watch<AccountProvider>().cycleIncomeTotal`.
- Produces: Seamless reactive balance and hero card updates without needing pull-to-refresh.

- [ ] **Step 1: Write test checking reactive rebuild of Dashboard when AccountProvider notifies**

Create/update widget test in `flutter_app/test/screens/dashboard_reactive_account_test.dart` verifying `BudgetHeroCard` updates when `accountProvider.notifyListeners()` triggers with new balance.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/screens/dashboard_reactive_account_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Update `DashboardScreen`**

Replace the isolated local variables `_operatingCash` and `_accountsCount` with values read directly from `context.watch<AccountProvider>()`. In `_loadDashboardData`, call `context.read<AccountProvider>().init(hid, _currentCycleKey)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/screens/dashboard_reactive_account_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/home/dashboard_screen.dart flutter_app/lib/widgets/dashboard/budget_hero_card.dart flutter_app/test/screens/dashboard_reactive_account_test.dart
git commit -m "refactor(dashboard): wire BudgetHeroCard and QuickAccess to reactive AccountProvider"
```

---

### Task 3: Refine `BudgetManagementScreen` Allocations Header & Capacity Benchmark

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:1410-1650`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/screens/budget_management_screen_capacity_test.dart`

**Interfaces:**
- Consumes: `staticData.monthlyIncome` as planned Cycle Funding Capacity; `accountProvider.operatingCash` as Live Remaining Operating Cash.
- Produces: Unambiguous UI distinguishing planned cycle capacity from live remaining liquid cash, with deficit warnings restricted to actual capacity overruns.

- [ ] **Step 1: Write widget test verifying label and metric separation**

```dart
// flutter_app/test/screens/budget_management_screen_capacity_test.dart
import 'package:flutter_test/flutter_test.dart';
// Test verifying that 'Cycle Funding Capacity' displays SAR 8,941.00
// and 'Operating Cash (Remaining)' displays SAR 7,076.00 without false deficit warnings.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/screens/budget_management_screen_capacity_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement clean separation of metrics in `BudgetManagementScreen`**

1. Define localized strings in `app_localizations.dart`:
   - `cycle_income_capacity`: "Cycle Funding Capacity" (EN), "السعة التمويلية للدورة" (AR), "سائیکل فنڈنگ صلاحیت" (UR).
   - `operating_cash_remaining`: "Operating Cash (Remaining)" (EN), "النقد التشغيلي (المتبقي)" (AR), "آپریٹنگ کیش (بقیہ)" (UR).
   - `within_income_capacity`: "Within cycle capacity ({amount} buffer)" (EN), "ضمن السعة التمويلية (فائض {amount})" (AR), "سائیکل کی گنجائش کے اندر ({amount} اضافی)" (UR).
2. Render two distinct rows in the 3D surface card:
   - Row 1: `cycle_income_capacity` showing `context.sar(cycleFunding)` with buffer vs `totalAllocated`.
   - Row 2: `operating_cash_remaining` showing `context.sar(operatingCash)`.
3. Deficit alert only displays if `totalAllocated > cycleFunding`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/screens/budget_management_screen_capacity_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/screens/budget_management_screen_capacity_test.dart
git commit -m "fix(budgets): separate planned cycle capacity from live operating cash and refine deficit warnings"
```

---

### Task 4: Dynamic Category Synchronization & Immediate Cache Invalidation

**Files:**
- Modify: `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart:145-170`
- Modify: `flutter_app/lib/providers/budget_provider.dart:76-100`
- Modify: `ai_service/salary_cycle.py:1313-1317`
- Test: `flutter_app/test/widgets/manual_expense_sheet_categories_test.dart`

**Interfaces:**
- Consumes: `BudgetProvider.activeCategories` (dynamically loaded from DB/API).
- Produces: 1:1 synchronization between categories in Budgets tab and Add Expense dropdown; instant invalidation on category toggle.

- [ ] **Step 1: Write failing test verifying dynamic category population in `ManualExpenseSheet`**

Test that `ManualExpenseSheet` loads categories from `BudgetProvider` instead of a static list.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/widgets/manual_expense_sheet_categories_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Update `BudgetProvider` and `ManualExpenseSheet`**

1. In `BudgetProvider`, add:
   ```dart
   void invalidateCategoriesCache() {
     _cachedHouseholdCategories = null;
     _categoriesLastFetched = null;
     notifyListeners();
   }
   ```
2. In `ManualExpenseSheet`, populate dropdown dynamically from `context.read<BudgetProvider>().cachedActiveCategories` (with fallback to `CategoryCatalog.pickerCodes`).
3. In `ai_service/salary_cycle.py`, add `"OPEX-FAMILY-SUPPORT"` into `initial_core`.
4. In `CategoryLibrarySheet` and `BudgetManagementScreen`, call `budgetProvider.invalidateCategoriesCache()` whenever a category is toggled, added, or renamed.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/widgets/manual_expense_sheet_categories_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/transactions/manual_expense_sheet.dart flutter_app/lib/providers/budget_provider.dart ai_service/salary_cycle.py flutter_app/test/widgets/manual_expense_sheet_categories_test.dart
git commit -m "feat(categories): synchronize Add Expense categories with active budgets and invalidate cache dynamically"
```

---

### Task 5: Dynamic Sub-Category Chip Rendering in `BudgetManagementScreen`

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:1725-1735, 1950-1970`
- Test: `flutter_app/test/screens/budget_management_subcategories_test.dart`

**Interfaces:**
- Consumes: `Budget.subAllocations` (copied or configured), database `cost_control_sub_categories`.
- Produces: Small rectangular text buttons rendered cleanly under both system and cloned/custom categories.

- [ ] **Step 1: Write test for sub-category rendering on cloned category**

Test that a budget with custom code `OPEX-CUSTOM-FOOD` and subAllocations `{'Groceries': 300.0, 'Snacks': 100.0}` renders sub-category chip buttons.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/screens/budget_management_subcategories_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement dynamic sub-category resolution**

In `BudgetManagementScreen`, resolve sub-categories from:
1. `existing?.subAllocations?.keys.toList()` (if present).
2. Database subcategories from `staticData.subCategoriesByParent[code]`.
3. Fallback: `kSubCategoriesByParent[code]`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/screens/budget_management_subcategories_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/test/screens/budget_management_subcategories_test.dart
git commit -m "fix(budgets): render sub-category chips dynamically for cloned and custom categories"
```

---

### Task 6: Full Installment Editing & Management from Dashboard

**Files:**
- Modify: `flutter_app/lib/widgets/dashboard/installment_plans_card.dart:920-975`
- Modify: `flutter_app/lib/providers/installment_provider.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/installment_plans_card_edit_test.dart`

**Interfaces:**
- Consumes: Existing `InstallmentPlan` model.
- Produces: `_showEditPlanDialog` in `InstallmentPlansCard`, `InstallmentProvider.updatePlan(...)`, instant balance & dues recalculation.

- [ ] **Step 1: Write widget test for editing installment plan**

Test opening 3-dots menu -> selecting "Edit" -> modifying merchant name & monthly payment -> saving -> verifying `InstallmentProvider.updatePlan` is called with updated values.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/widgets/installment_plans_card_edit_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement Edit dialog & API update**

1. Add `updatePlan` to `InstallmentProvider` and `ApiService`.
2. Add "Edit" item to `PopupMenuButton` in `InstallmentPlansCard`.
3. Implement `_showEditPlanDialog` pre-filled with existing plan attributes (merchant, total price, monthly payment, remaining installments, provider, frequency).
4. On save, call `context.read<InstallmentProvider>().updatePlan(updatedPlan)` and trigger `refreshGlobalAppData(context)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/widgets/installment_plans_card_edit_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/dashboard/installment_plans_card.dart flutter_app/lib/providers/installment_provider.dart flutter_app/lib/services/api_service.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/installment_plans_card_edit_test.dart
git commit -m "feat(installments): add full edit modal, update API integration, and reactive dues recalculation"
```

---

### Task 7: Unified Data Refresh Pipeline Across Transaction Flows

**Files:**
- Create: `flutter_app/lib/utils/refresh_app_data.dart`
- Modify: `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart:480-495`
- Modify: `flutter_app/lib/screens/chat/chat_entry_screen.dart:338-344, 524-527`
- Modify: `flutter_app/lib/widgets/accounts/record_income_sheet.dart:158-166`
- Modify: `flutter_app/lib/widgets/dashboard/installment_plans_card.dart:1045-1050`
- Test: `flutter_app/test/utils/refresh_app_data_test.dart`

**Interfaces:**
- Produces: `Future<void> refreshGlobalAppData(BuildContext context)` executing non-blocking parallel updates across `TransactionProvider`, `BudgetProvider`, `AccountProvider`, `InstallmentProvider`, and `RecurringBillsProvider`.

- [ ] **Step 1: Write test for `refreshGlobalAppData`**

Test that `refreshGlobalAppData` calls `refresh()` on all registered providers.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/utils/refresh_app_data_test.dart`  
Expected: FAIL.

- [ ] **Step 3: Implement `refreshGlobalAppData`**

```dart
// flutter_app/lib/utils/refresh_app_data.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/installment_provider.dart';
import '../providers/recurring_bills_provider.dart';
import '../providers/transaction_provider.dart';

Future<void> refreshGlobalAppData(BuildContext context) async {
  if (!context.mounted) return;
  try {
    await Future.wait([
      context.read<AccountProvider>().refresh(),
      context.read<BudgetProvider>().refresh(),
      context.read<TransactionProvider>().fetchTransactions(),
      context.read<InstallmentProvider>().fetchPlans(),
      context.read<RecurringBillsProvider>().fetchBills(),
    ]);
  } catch (e) {
    debugPrint('[refreshGlobalAppData] Error refreshing providers: $e');
  }
}
```

- [ ] **Step 4: Wire into all action handlers**

Call `refreshGlobalAppData(context)` in:
- `ManualExpenseSheet._refreshProviders()`
- `ChatEntryScreen._refreshGlobalProviders()`
- `RecordIncomeSheet._saveIncome()`
- `InstallmentPlansCard` payment record callback

- [ ] **Step 5: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/utils/refresh_app_data_test.dart`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/utils/refresh_app_data.dart flutter_app/lib/widgets/transactions/manual_expense_sheet.dart flutter_app/lib/screens/chat/chat_entry_screen.dart flutter_app/lib/widgets/accounts/record_income_sheet.dart flutter_app/lib/widgets/dashboard/installment_plans_card.dart flutter_app/test/utils/refresh_app_data_test.dart
git commit -m "feat(sync): add unified refreshGlobalAppData pipeline across manual, chat, income, and installment flows"
```

---

### Task 8: Verification Gate & External Argon Audit Bundle Preparation

**Files:**
- Create: `docs/review/PR_AUDIT_BUNDLE.md`

- [ ] **Step 1: Run Flutter Analyzer**

Run: `cd flutter_app && flutter analyze`  
Expected: 0 issues.

- [ ] **Step 2: Run Full Flutter Test Suite**

Run: `cd flutter_app && flutter test`  
Expected: All tests pass.

- [ ] **Step 3: Run Backend Test Suite**

Run: `cd ai_service && .venv\Scripts\pytest -v`  
Expected: All tests pass.

- [ ] **Step 4: Generate PR Audit Bundle**

Generate `docs/review/PR_AUDIT_BUNDLE.md` containing:
- Section 1: Implementation Plan & Architectural Intent
- Section 2: Test & Analyzer Output Summary
- Section 3: Baseline Context & Unified Diff (`git diff feat/income-tracking-and-reporting...HEAD`)
Copy to clipboard for immediate review by Lead Architect (Argon).

