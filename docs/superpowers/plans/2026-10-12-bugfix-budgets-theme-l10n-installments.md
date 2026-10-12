# Six Critical Bugfixes: Budgets, Themes, Multilingual, Recurring Bills, BNPL, and Dependents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the 6 reported bugs across the Flutter app and FastAPI backend: harmonize active/inactive budget categories and purge test categories, make light/dark themes fully adaptive across all screens, implement comprehensive multilingual translations (English, Arabic, Urdu), fix recurring bills toggle persistence, make BNPL installment plans visible and manageable with transaction badges, and introduce prominent "Paid for Whom" dependent management in settings and transaction sheets.

**Architecture:** 
- Backend (`ai_service/`): Fix `toggle_household_recurring_bill` DB query column selection, include `OPEX-ENTERTAINMENT` and `OPEX-GOV` in `initial_core` active categories, purge test category records, and ensure `toggle_category_status` reactivates `budgets` rows.
- Flutter Theme (`flutter_app/lib/theme/` and screens): Replace hardcoded `Color(0xFF0D1117)` / `Color(0xFF161B22)` with adaptive theme colors across AppBars, Scaffolds, dialogs, cards, chips, and input fields.
- Multilingual (`flutter_app/lib/l10n/`): Expand `AppLocalizations` into a comprehensive dictionary and add a `context.tr()` extension, wiring all key screens (Dashboard, Budgets, Transactions, Settings, Modals).
- Dashboard & Transactions: Update `InstallmentPlansCard` to show an actionable empty state with an "+ Add Plan" modal instead of disappearing, add BNPL installment badges in transaction list, and add direct child/dependent creation in Settings and Edit Transaction sheet.

**Tech Stack:** Flutter 3.x, Dart, FastAPI, Python 3.11, Supabase PostgreSQL.

**Spec:** User bug report dated 2026-10-12.

## Global Constraints
- Strict English in all code comments and commit messages.
- Maintain full offline SQLite sync compatibility.
- Ensure RTL and LTR support for Arabic (`ar`), Urdu (`ur`), and English (`en`).
- Preserve existing database schema and backwards compatibility with Supabase RLS.

---

### Task 1: Fix Category Lifecycle, Default Active Core, End-to-End Toggle Bugs, and Purge Test Categories

**Files:**
- Modify: `ai_service/salary_cycle.py:935-985`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:50-75, 545-580`
- Modify: `flutter_app/lib/widgets/categories/category_library_sheet.dart:25-225`
- Test: `ai_service/tests/test_category_lifecycle.py`
- Test: `flutter_app/test/widgets/category_library_sheet_test.dart`

**Interfaces:**
- Consumes: `get_household_categories(household_id: str)`, `toggle_category_status(household_id, category_code, is_active)`
- Produces: `OPEX-ENTERTAINMENT` and `OPEX-GOV` in `initial_core`; exclusion of any category containing "test"; synchronization of `budgets.is_active` on toggle (both true and false); mutable optimistic state in `CategoryLibrarySheet` moving items between active and inactive tabs upon click.

- [ ] **Step 1: Write failing Python unit test for entertainment/gov in initial_core, test category filtering, and budget row reactivation**

```python
# ai_service/tests/test_category_lifecycle.py
def test_entertainment_and_gov_active_by_default(monkeypatch):
    from salary_cycle import get_household_categories
    # Verify OPEX-ENTERTAINMENT and OPEX-GOV are in initial_core
    # and "testing" categories are filtered out
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest ai_service/tests/test_category_lifecycle.py -k test_entertainment_and_gov_active_by_default`
Expected: FAIL

- [ ] **Step 3: Implement backend fixes in `ai_service/salary_cycle.py`**
  - Add `"OPEX-ENTERTAINMENT"` and `"OPEX-GOV"` to `initial_core` so they are active by default.
  - Filter out any category where `code` or `category` lowercased equals or contains `"testing"` or `"test_custom"`.
  - In `toggle_category_status`:
    - When `is_active` is True: update `budgets` table setting `is_active = True`.
    - When `is_active` is False: update `budgets` table setting `is_active = False`.
    - Upsert `household_category_settings`.

- [ ] **Step 4: Update Flutter `CategoryLibrarySheet` and `budget_management_screen.dart`**
  - In `CategoryLibrarySheet`:
    - Convert `activeCategories` and `inactiveCategories` into internal mutable lists `_activeList` and `_inactiveList` in state.
    - When user taps "Activate", immediately move the item from `_inactiveList` to `_activeList` with `setState()`, call `widget.onToggle(item, true)`, and show a checkmark feedback.
    - When user taps "Deactivate", move from `_activeList` to `_inactiveList` with `setState()`, call `widget.onToggle(item, false)`.
  - In `budget_management_screen.dart`:
    - Harmonize active categories with `fetchHouseholdCategories()` so the budgets tab and library sheet are in 100% agreement.

- [ ] **Step 5: Run tests to verify they pass**

Run: `pytest ai_service/tests/test_category_lifecycle.py`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ai_service/salary_cycle.py ai_service/tests/test_category_lifecycle.py flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/widgets/categories/category_library_sheet.dart
git commit -m "fix(categories): default entertainment & gov to active, purge test categories, fix activation sync"
```

---

### Task 2: Fix Recurring Bills & Reservation Switch Persistence

**Files:**
- Modify: `ai_service/recurring_detector.py:447-502`
- Modify: `flutter_app/lib/widgets/dashboard/recurring_bills_card.dart:680-715`
- Test: `ai_service/tests/test_recurring_bills_api.py`

**Interfaces:**
- Consumes: `POST /budgets/recurring-bills/toggle`
- Produces: Correct SQL query selecting `id, sub_allocations, cycle_key, month` so matching budget rows are found and updated.

- [ ] **Step 1: Write failing Python unit test for recurring bill toggle**

```python
# ai_service/tests/test_recurring_bills_api.py
def test_toggle_household_recurring_bill_success(monkeypatch):
    from recurring_detector import toggle_household_recurring_bill
    # Mock client with budgets table returning id, sub_allocations, cycle_key, month
    # Call toggle_household_recurring_bill and assert status == "success"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest ai_service/tests/test_recurring_bills_api.py -k test_toggle_household_recurring_bill_success`
Expected: FAIL

- [ ] **Step 3: Implement fix in `ai_service/recurring_detector.py`**
  - Change line 466:
    `.select("id, sub_allocations, cycle_key, month")`
  - Add fallback: if `matching` by cycle is empty, fallback to the latest budget row for that category code in the household.
  - In Flutter `recurring_bills_card.dart`: update candidate state optimistically upon toggle switch tap and show error snackbar if API call fails.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest ai_service/tests/test_recurring_bills_api.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/recurring_detector.py ai_service/tests/test_recurring_bills_api.py flutter_app/lib/widgets/dashboard/recurring_bills_card.dart
git commit -m "fix(recurring-bills): select cycle_key and month so toggle persists properly in DB"
```

---

### Task 3: Fix BNPL & Installment Plans Disappearing, Direct Supabase Fallback, and Transaction Badges

**Files:**
- Modify: `flutter_app/lib/models/models.dart:30-60`
- Modify: `flutter_app/lib/widgets/dashboard/installment_plans_card.dart:30-160`
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart:900-1025`
- Modify: `flutter_app/lib/screens/home/edit_transaction_sheet.dart:550-600`
- Test: `flutter_app/test/widgets/installment_plans_card_test.dart`

**Interfaces:**
- Consumes: `InstallmentPlan` model, `ApiService.instance.getInstallments`, Supabase client
- Produces: Non-collapsing `InstallmentPlansCard` with direct Supabase table query fallback, empty state CTA with "+ Add Installment Plan" dialog, `Transaction` model helpers (`isInstallment`, `installmentProvider`, `installmentProgress`), and vibrant badges in `TransactionFeedScreen`.

- [ ] **Step 1: Write widget test for `InstallmentPlansCard` empty state and transaction badges**

```dart
testWidgets('InstallmentPlansCard renders empty state with Add button instead of disappearing', (tester) async {
  // test that when plans is empty, SizedBox.shrink() is NOT returned
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/installment_plans_card_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement model getters and empty state in `InstallmentPlansCard`**
  - In `flutter_app/lib/models/models.dart`:
    - Add `bool get isInstallment` (checking if `rawSms` contains `[Financed via` or source is installment).
    - Add `String? get installmentBadgeText` extracting e.g. `Tamara (1/4)` or `Tabby (1/4)`.
  - In `flutter_app/lib/widgets/dashboard/installment_plans_card.dart`:
    - In `_loadPlans()`: try `ApiService.instance.getInstallments()`, and if empty, also query Supabase `installment_plans` table directly using the client as an instant, resilient fallback.
    - Replace `return const SizedBox.shrink();` with a styled card:
      - Title: "Installments & BNPL (Tamara / Tabby)"
      - Subtitle: "Split larger purchases into interest-free installments."
      - Prominent "+ Add Installment Plan" button that opens an installment creation dialog.
  - In `flutter_app/lib/screens/home/transaction_feed_screen.dart`:
    - In `_TransactionCard`: when `tx.isInstallment`, render an eye-catching badge:
      `[Tamara 1/4]` (coral) or `[Tabby 1/4]` (mint green) next to the transaction name and amount.
  - In `flutter_app/lib/screens/home/edit_transaction_sheet.dart`:
    - On conversion success, trigger immediate reload of transactions in `TransactionProvider` and refresh dashboard.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/installment_plans_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/models.dart flutter_app/lib/widgets/dashboard/installment_plans_card.dart flutter_app/lib/screens/home/transaction_feed_screen.dart flutter_app/lib/screens/home/edit_transaction_sheet.dart
git commit -m "fix(bnpl): keep installment card visible with fallback, add +Add Plan dialog, and display installment badges in feed"
```

---

### Task 4: Add Prominent "Paid for Whom (Children & Dependents)" in Settings and Transaction Sheet

**Files:**
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart:740-770`
- Modify: `flutter_app/lib/widgets/settings/household_management_card.dart:190-270`
- Modify: `flutter_app/lib/screens/home/edit_transaction_sheet.dart:860-910`
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart:990-1005`
- Test: `flutter_app/test/widgets/household_management_card_test.dart`

**Interfaces:**
- Consumes: `HouseholdDependent` model, `ApiService.instance.getDependents`, `ApiService.instance.createDependent`
- Produces: Distinct "PAID FOR WHOM (CHILDREN & DEPENDENTS)" card in Settings with "+ Add Child" modal, plus "+ Add Child" shortcut directly inside `EditTransactionSheet`.

- [ ] **Step 1: Write widget test for Paid for Whom dependent section**

```dart
testWidgets('Settings renders dedicated Paid for Whom section with add child action', (tester) async {
  // verify presence of 'Paid for Whom (Children & Dependents)' and add button
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/household_management_card_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement dedicated card in Settings and quick-add in EditTransactionSheet**
  - In `ingestion_settings_screen.dart`:
    - Elevate the dependent section into its own dedicated card: **"Paid for Whom (Children & Dependents)"** with a child avatar, explanation text, and prominent "+ Add Child / Dependent" button.
  - In `edit_transaction_sheet.dart`:
    - When viewing "FOR WHOM?", add a small "+ Add Child" button right next to "CHILDREN & DEPENDENTS" allowing users to add a child on the fly without navigating away.
  - In `transaction_feed_screen.dart`:
    - Pass current household dependents to `EditTransactionSheet.show` so children chips are always loaded.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/household_management_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/settings/ingestion_settings_screen.dart flutter_app/lib/widgets/settings/household_management_card.dart flutter_app/lib/screens/home/edit_transaction_sheet.dart flutter_app/lib/screens/home/transaction_feed_screen.dart
git commit -m "feat(dependents): add dedicated Paid for Whom section in settings and quick-add in transaction sheet"
```

---

### Task 5: Make Light and Dark Themes Fully Adaptive Across All Screens

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Modify: `flutter_app/lib/screens/settings/help_support_screen.dart`
- Modify: `flutter_app/lib/screens/chat/chat_entry_screen.dart`
- Modify: `flutter_app/lib/screens/home/edit_transaction_sheet.dart`
- Modify: `flutter_app/lib/widgets/dashboard/recurring_bills_card.dart`
- Modify: `flutter_app/lib/widgets/dashboard/installment_plans_card.dart`
- Test: `flutter_app/test/theme/app_theme_adaptivity_test.dart`

**Interfaces:**
- Consumes: `Theme.of(context)`, `theme.scaffoldBackgroundColor`, `theme.cardTheme.color`, `theme.colorScheme`
- Produces: Seamless switching between light and dark themes with zero dark artifacts stuck in light mode.

- [ ] **Step 1: Write test verifying theme adaptivity**

```dart
testWidgets('Dashboard and cards render with light background in light theme', (tester) async {
  // test that scaffold and appbar adapt to light mode colors
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/app_theme_adaptivity_test.dart`
Expected: FAIL

- [ ] **Step 3: Refactor hardcoded dark colors to adaptive theme tokens**
  - In `dashboard_screen.dart`: Remove `backgroundColor: const Color(0xFF0D1117)` from Scaffolds and AppBars; use `theme.scaffoldBackgroundColor` and `theme.appBarTheme.backgroundColor`.
  - In `budget_management_screen.dart`, `transaction_feed_screen.dart`, `chat_entry_screen.dart`, and `help_support_screen.dart`: Replace hardcoded dark colors with `theme.scaffoldBackgroundColor`, `theme.cardColor`, and adaptive borders.
  - In `recurring_bills_card.dart`, `installment_plans_card.dart`, and `edit_transaction_sheet.dart`: Use `theme.cardColor` or `isDark ? const Color(0xFF161B22) : Colors.white` and adjust text/border colors appropriately.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/app_theme_adaptivity_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/ flutter_app/lib/widgets/
git commit -m "fix(theme): make all screens, appbars, cards, and sheets adapt dynamically to light/dark mode"
```

---

### Task 6: Comprehensive Multilingual Localization (English, Arabic, Urdu)

**Files:**
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Create: `flutter_app/lib/utils/l10n_extensions.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Test: `flutter_app/test/l10n/app_localizations_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations`, `LocaleProvider`
- Produces: `context.tr('key')` extension with complete dictionaries in English, Arabic, and Urdu covering all navigation, dashboard cards, budget actions, transaction feeds, and settings options.

- [ ] **Step 1: Write unit test for `AppLocalizations` translation coverage**

```dart
test('AppLocalizations returns translated strings for ar and ur locales', () {
  final ar = AppLocalizations(const Locale('ar'));
  final ur = AppLocalizations(const Locale('ur'));
  expect(ar.get('dashboard'), 'لوحة المتابعة');
  expect(ur.get('dashboard'), 'ڈیش بورڈ');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/l10n/app_localizations_test.dart`
Expected: FAIL

- [ ] **Step 3: Expand dictionaries in `app_localizations.dart` & create `l10n_extensions.dart`**
  - Add complete translation sets for:
    - Navigation: Dashboard, Budgets, Transactions, Chat, Settings
    - Dashboard Cards: Hero Budget, Salary Cycle, Partner Settlement, Recurring Bills, BNPL Installments, Quick Actions
    - Categories: Grocery, Dining, Fuel, Utilities, Shopping, Entertainment, Health, Education, Government Fees, Miscellaneous
    - Common actions: Edit, Delete, Save, Cancel, Sync Now, Add, Search, Filter, All, Active, Inactive, Paid for Whom, Me, Partner, Shared
  - Create `context.tr(String key, {Map<String, String>? params})` convenience extension.
  - Wire `context.tr(...)` across bottom navigation, AppBars, and major screen titles.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/l10n/app_localizations_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/l10n/app_localizations.dart flutter_app/lib/utils/l10n_extensions.dart flutter_app/lib/screens/
git commit -m "feat(l10n): implement full Arabic and Urdu translations with context.tr extension"
```

---

### Task 7: Full Verification and APK Build

**Files:**
- Output: `BudgetTracker-v1.0.1-arm64.apk`

- [ ] **Step 1: Run all Python tests**
Run: `pytest ai_service/tests/`
Expected: ALL PASS

- [ ] **Step 2: Run Flutter tests**
Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 3: Build release APK with split-per-abi**
Run: `flutter build apk --split-per-abi`
Expected: SUCCESS

- [ ] **Step 4: Copy updated APK to workspace root with clear naming**
Run: `Copy-Item flutter_app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk BudgetTracker-v1.0.1-arm64.apk`
