# Reactive Account State, Budget Allocation Refinement & Installment Management Design

**Date:** 2026-10-30  
**Status:** Approved  
**Author:** Pair Programming Agent (Antigravity) & External Lead Architect (Argon)  
**Branch:** `feat/reactive-account-state-and-installments`  

---

## 1. Context & Background

During comprehensive end-to-end device testing of cycle budgeting, installment payment tracking, and manual/AI transaction ingestion, five distinct defects and architectural gaps were identified:

1. **Budget Allocations Capacity Metric Conflation:**
   On the Budgets tab, the top summary card row displayed the label `total_operating_cash` ("Operating Cash"), but rendered the value of `cycleFunding` (SAR 8,941.00 - total cycle income). This conflated planned cycle funding capacity with real-time remaining liquid cash (SAR 7,076.00). In addition, previous logic compared planned budget allocations directly to declining live cash, causing false deficit warnings (`⚠️ Allocations exceed operating cash`) mid-cycle.

2. **Absence of Reactive Account State Management:**
   While providers existed for `BudgetProvider`, `TransactionProvider`, `RecurringBillsProvider`, and `InstallmentProvider`, there was **no `AccountProvider`** in the application. `DashboardScreen` fetched operating cash into a local private variable (`_operatingCash`) loaded only once on initialization or manual pull-to-refresh. When transactions were logged via manual entry, AI chat, or receipt scan, or when installment payments were recorded, account balances in PostgreSQL updated, but the UI required a pull-to-refresh to reflect the change.

3. **Category Dropdown Desynchronization & "Family Support" Cache Bug:**
   - In `ManualExpenseSheet`, the category dropdown was populated from a static hardcoded list (`CategoryCatalog.pickerCodes`), ignoring the household's actual active categories in the Budgets tab.
   - In `ai_service/salary_cycle.py`, `initial_core` seeded 10 categories, omitting `OPEX-FAMILY-SUPPORT`.
   - When users activated categories in `CategoryLibrarySheet`, `BudgetProvider._cachedHouseholdCategories` was never invalidated, causing the Budgets tab to display stale category lists.

4. **Missing Sub-Category Chips on Cloned/Custom Categories:**
   In `budget_management_screen.dart`, sub-categories rendered under category cards were retrieved exclusively from a static hardcoded Dart map (`kSubCategoriesByParent[code]`). When a category was cloned or created with a new code and subcategories, `kSubCategoriesByParent` returned empty, displaying zero sub-category chips.

5. **Lack of Installment Plan Editing Capabilities:**
   `InstallmentPlansCard` only supported "Delete Plan" and "Record Payment". Users had no ability to edit merchant details, total price, monthly installment amount, remaining installments, or payment schedules for ongoing or mistyped plans.

---

## 2. Goals & Success Criteria

1. **Zero Pull-to-Refresh Requirement:** Any balance change (transaction creation, installment payment, fund transfer, income recording) reactively updates all listening screens and widgets across the app immediately via `AccountProvider`.
2. **Clear Financial Metrics:** The Budget Allocations card explicitly distinguishes **Planned Cycle Income / Capacity** (benchmark for allocations) from **Live Remaining Operating Cash** (liquid funds left). Deficit warnings only trigger if allocations exceed planned cycle funding or an account has insufficient liquidity for remaining unspent commitments.
3. **1:1 Category Synchronization:** The category dropdown in `ManualExpenseSheet` dynamically mirrors the household's active categories from `BudgetProvider`, with immediate cache invalidation on category modifications.
4. **Dynamic Sub-Category Chip Rendering:** Cloned and custom categories display subcategory chips dynamically by inspecting `budget.subAllocations` and database subcategories.
5. **Full Installment Management:** Users can edit any field of an installment plan directly from the dashboard with instant commitment and balance re-calculation.
6. **Strict Trilingual Support & Zero Analyzer Issues:** All UI strings localized in English, Arabic, and Urdu; 0 `flutter analyze` issues; 100% test pass rate.

---

## 3. Architecture & Data Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Root App: MultiProvider                         │
│  ┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐  │
│  │   AccountProvider  │ │   BudgetProvider   │ │InstallmentProvider │  │
│  │ (Accounts, Cash,   │ │ (Allocations, Exp, │ │ (Plans, BNPL dues, │  │
│  │  Cycle Income)     │ │  Active Categories)│ │   Edit / Pay)      │  │
│  └─────────┬──────────┘ └──────────┬─────────┘ └──────────┬─────────┘  │
└────────────┼───────────────────────┼──────────────────────┼────────────┘
             │                       │                      │
             ▼                       ▼                      ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Reactive Consumer Layer                         │
│  • DashboardScreen: Listens to AccountProvider (operatingCash, income) │
│  • BudgetHeroCard: Displays live operating cash & cycle income         │
│  • BudgetManagementScreen: Validates allocations vs. cycle funding     │
│  • ManualExpenseSheet: Reads BudgetProvider.activeCategories           │
│  • InstallmentPlansCard: Full Edit Dialog & instant balance deduction  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Component Specifications

### 4.1. Reactive `AccountProvider`
* **File:** `flutter_app/lib/providers/account_provider.dart`
* **State Managed:**
  * `List<Account> _accounts`
  * `List<IncomeRecord> _cycleIncomeRecords`
  * `double _operatingCash` (liquid checking/operating pool balance)
  * `double _totalNetWorth` (total liquidity across all accounts)
  * `double _cycleIncomeTotal` (sum of net cycle income records)
  * `bool _isLoading`
  * `String? _error`
* **Realtime Subscription:** Listens to `accounts` and `income_records` tables via Supabase Realtime channel for live multi-device synchronization.
* **Public Methods:**
  * `Future<void> init(String householdId, String cycleKey)`
  * `Future<void> refresh()`
  * `Future<void> updateAccountBalance(String accountId, double newBalance)`
  * `Future<void> recordIncome(...)`
  * `Future<void> transferFunds(...)`
  * `void reset()` (on sign-out / household switch)

### 4.2. Budget Allocations Header Refinement
* **File:** `flutter_app/lib/screens/home/budget_management_screen.dart`
* **Metrics Separation:**
  1. **Cycle Funding / Capacity Benchmark:** Labeled as `cycle_income_capacity` (`SAR 8,941.00`). Displays comparison against total allocated: `context.trArgs('within_income_capacity', {'amount': context.sar(fundingMargin)})`.
  2. **Live Operating Cash:** Labeled as `operating_cash_remaining` (`SAR 7,076.00`).
  3. **Capacity Deficit Warning:** Triggered if and only if `totalAllocated > cycleFunding`.
  4. **Account Shortfall Check:** Accurately compares each account's current balance against *unspent remaining commitments*: `(allocated - spent).clamp(0, infinity)`.

### 4.3. Dynamic Category Synchronization & Invalidation
* **Files:**
  * `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart`
  * `flutter_app/lib/providers/budget_provider.dart`
  * `ai_service/salary_cycle.py`
* **Behavior:**
  * `BudgetProvider` exposes `List<CategoryItem> get activeCategories` and `void invalidateCategoriesCache()`.
  * `ManualExpenseSheet` queries `context.read<BudgetProvider>().activeCategories` to populate the dropdown. If offline or empty, falls back safely to `CategoryCatalog.pickerCodes`.
  * In `CategoryLibrarySheet` and `BudgetManagementScreen`, toggling, adding, archiving, or renaming a category invokes `budgetProvider.invalidateCategoriesCache()`, guaranteeing 1:1 parity.
  * In `ai_service/salary_cycle.py`, add `"OPEX-FAMILY-SUPPORT"` to `initial_core` default categories.

### 4.4. Dynamic Sub-Category Chip Rendering
* **File:** `flutter_app/lib/screens/home/budget_management_screen.dart`
* **Resolution Pipeline:**
  ```dart
  List<String> resolveSubCategories(Budget? budget, String categoryCode) {
    if (budget?.subAllocations != null && budget!.subAllocations.isNotEmpty) {
      return budget.subAllocations.keys.toList();
    }
    final dbSubs = cachedSubCategories[categoryCode];
    if (dbSubs != null && dbSubs.isNotEmpty) {
      return dbSubs;
    }
    return kSubCategoriesByParent[categoryCode] ?? const <String>[];
  }
  ```
* Ensures cloned, edited, and custom categories render small rectangular chip buttons identically to system defaults.

### 4.5. Installment Plan Editing Dialog & API
* **Files:**
  * `flutter_app/lib/widgets/dashboard/installment_plans_card.dart`
  * `flutter_app/lib/providers/installment_provider.dart`
  * `flutter_app/lib/services/api_service.dart`
  * `ai_service/routers/installments.py`
* **Features:**
  * 3-dots popup menu contains both **Edit** (`Icons.edit_outlined`) and **Delete** (`Icons.delete_outline`).
  * `_showEditPlanDialog` pre-populates existing values: merchant name, total price, monthly installment amount, remaining installments, due day of month, provider, and biweekly/monthly schedule.
  * Saving invokes `context.read<InstallmentProvider>().updatePlan(...)`, sending `PUT /households/{hid}/installment-plans/{id}`.
  * Recording payment immediately calls `context.read<AccountProvider>().refresh()` and `context.read<InstallmentProvider>().fetchPlans()`.

### 4.6. Unified Data Refresh Pipeline
* **File:** `flutter_app/lib/utils/refresh_app_data.dart`
* A reusable helper `refreshGlobalAppData(BuildContext context)` that runs parallel non-blocking refreshes across:
  * `TransactionProvider.fetchTransactions()`
  * `BudgetProvider.refresh()`
  * `AccountProvider.refresh()`
  * `InstallmentProvider.fetchPlans()`
  * `RecurringBillsProvider.fetchBills()`
* Called upon manual expense logging, AI chat expense confirmation, receipt scanning, and installment payments.

---

## 5. Security, Privacy & Multi-Tenancy

1. **Row Level Security (RLS):** All queries in `AccountProvider` and `InstallmentProvider` are scoped strictly by `household_id` and verified by Supabase RLS.
2. **Atomic Financial Updates:** Balance updates, income logs, and inter-account transfers execute via secure PostgreSQL SECURITY DEFINER RPCs (`record_income`, `reconcile_account_balance`, `transfer_between_accounts`).
3. **Zero SMS Policy:** No SMS ingestion or transmission is permitted under any circumstances.

---

## 6. Trilingual Localization Keys

New and updated translation keys in `flutter_app/lib/l10n/app_localizations.dart`:
* `cycle_income_capacity`: "Cycle Funding Capacity" / "السعة التمويلية للدورة" / "سائیکل فنڈنگ صلاحیت"
* `operating_cash_remaining`: "Operating Cash (Remaining)" / "النقد التشغيلي (المتبقي)" / "آپریٹنگ کیش (بقیہ)"
* `within_income_capacity`: "Within cycle capacity ({amount} buffer)" / "ضمن السعة التمويلية (فائض {amount})" / "سائیکل کی گنجائش کے اندر ({amount} اضافی)"
* `edit_installment_title`: "Edit Installment Plan" / "تعديل خطة الأقساط" / "قسط کے منصوبے میں ترمیم"
* `installment_updated`: "Installment plan updated successfully" / "تم تحديث خطة الأقساط بنجاح" / "قسط کا منصوبہ کامیابی کے ساتھ اپ ڈیٹ ہو گیا"
* `all_active_categories`: "Active Categories" / "الفئات النشطة" / "فعال زمرے"

