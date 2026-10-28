# Income Ledger Primacy & Sinking Fund Carryover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the static predefined monthly income setting in favor of 100% dynamic cycle income records (`income_records`), remove the confusing rollover settings card, make "send unspent surplus to savings" the silent default, and implement per-category/sub-category accumulating sinking funds (e.g., car maintenance oil 100 SAR/month accumulating until spent, then resetting to base).

**Architecture:**
- **Income Ledger**: All benchmarks (Hero card, PaydayOutlook, BudgetManager unallocated) derive dynamically from cycle `income_records` (salary, overtime, bonus, side gigs, roommate share), falling back to operating account cash or total allocations. The static `households.monthly_income` UI card is removed from Settings.
- **Sinking Fund Engine**: Budget metadata stored under `sub_allocations["_sinking_fund"] = { "<sub_code_or_parent>": { "accumulate": true, "base_amount": 100.0 } }`. On cycle rollover/copy:
  - If `accumulate` is true: `carryover = max(0, prev_allocated - prev_spent)`. `new_allocated = base_amount + carryover`. If fully spent, resets cleanly to `base_amount`. Carryover is retained in the envelope and NOT swept to savings.
  - If `accumulate` is false: `new_allocated = base_amount` (fresh start), and unspent surplus is swept to the savings account.
- **UI Streamlining**: Remove `RolloverSettingsCard` and `IncomeSettingsCard` from `SettingsScreen`. In `BudgetManagementScreen`, remove the redundant rollover popup dialog when copying from the previous month. Add a clean, responsive Sinking Fund toggle to `SubBudgetAllocationDialog` and category edit views.

**Tech Stack:** Python 3.11 (FastAPI, pytest), Flutter/Dart 3 (Provider, GoogleFonts, SharedPreferences), Supabase PostgreSQL.

**Spec:** Direct user instructions from October 28, 2026.

## Global Constraints
- **Zero SMS Policy**: No carrier SMS integration or verification.
- **Backend Service Key Secrecy**: Service role key confined to backend; mobile app uses JWT auth.
- **Strict Trilingual Support**: All user-facing strings localized in Arabic (`ar`), English (`en`), and Urdu (`ur`) via `AppLocalizations`. Zero hardcoded strings.
- **Test-Driven Development (TDD)**: Write failing tests before minimal code changes, verify green test runs.
- **Zero Analyzer Errors**: `flutter analyze` must report 0 issues.

---

### Task 1: AI Service Sinking Fund Engine & Allocation Metadata

**Files:**
- Modify: `ai_service/salary_cycle.py:1195-1260`
- Modify: `ai_service/supabase_client.py:760-815`
- Test: `ai_service/tests/test_sinking_fund_rollover.py`

**Interfaces:**
- Consumes: `sub_allocations` JSONB in `budgets` table.
- Produces: `is_allocation_metadata_key("_sinking_fund") == True`, automatic accumulating rollover in `ensure_household_cycle_budgets`.

- [ ] **Step 1: Write failing pytest for sinking fund accumulation and reset**

Create `ai_service/tests/test_sinking_fund_rollover.py`:
```python
import pytest
from supabase_client import ensure_household_cycle_budgets, get_household_savings_summary
from salary_cycle import is_allocation_metadata_key, save_sub_allocations

HID = "f860188e-23b5-4749-b180-868c956151a6"

def test_sinking_fund_metadata_key_recognized():
    assert is_allocation_metadata_key("_sinking_fund") is True
    assert is_allocation_metadata_key("_recurring_config") is True
    assert is_allocation_metadata_key("car_maintenance") is False

def test_sinking_fund_accumulates_and_resets(fake_supabase):
    # Setup household with default send_to_savings
    fake_supabase.seed("households", [{"id": HID, "payday_day": 27, "rollover_rule": "send_to_savings"}])
    
    # Cycle 1 (2026-09): Car maintenance 100 SAR base, accumulate=True, spent=0
    # Dining out 500 SAR base, accumulate=False, spent=400 (unspent=100)
    fake_supabase.seed("budgets", [
        {
            "id": "b-c1-oil",
            "household_id": HID,
            "cycle_key": "2026-09",
            "category_code": "OPEX-FUEL",
            "allocated_amount": 100.0,
            "spent_amount": 0.0,
            "sub_allocations": {
                "car_maintenance": 100.0,
                "_sinking_fund": {
                    "car_maintenance": {"accumulate": True, "base_amount": 100.0}
                }
            },
            "is_active": True,
        },
        {
            "id": "b-c1-dining",
            "household_id": HID,
            "cycle_key": "2026-09",
            "category_code": "OPEX-DINING",
            "allocated_amount": 500.0,
            "spent_amount": 400.0,
            "sub_allocations": {},
            "is_active": True,
        }
    ])
    
    # 1. Roll over to Cycle 2 (2026-10): Car maintenance should grow to 200 (100 base + 100 unspent)
    # Dining should reset to 500 fresh, and 100 unspent dining swept to savings
    new_budgets = ensure_household_cycle_budgets(HID, payday_day=27, target_cycle_key="2026-10")
    
    oil_b2 = next(b for b in new_budgets if b["category_code"] == "OPEX-FUEL")
    assert oil_b2["allocated_amount"] == 200.0
    assert oil_b2["sub_allocations"]["car_maintenance"] == 200.0
    
    dining_b2 = next(b for b in new_budgets if b["category_code"] == "OPEX-DINING")
    assert dining_b2["allocated_amount"] == 500.0
    
    # Check savings summary: ONLY dining unspent (100) was swept; oil was retained in envelope
    savings = get_household_savings_summary(HID)
    assert savings["accumulated_savings"] == 100.0

    # 2. In Cycle 2, oil spent is 0 again (unspent 200). Roll over to Cycle 3 (2026-11) -> grows to 300!
    oil_b2["spent_amount"] = 0.0
    dining_b2["spent_amount"] = 500.0 # 0 unspent
    
    new_budgets_c3 = ensure_household_cycle_budgets(HID, payday_day=27, target_cycle_key="2026-11")
    oil_b3 = next(b for b in new_budgets_c3 if b["category_code"] == "OPEX-FUEL")
    assert oil_b3["allocated_amount"] == 300.0
    assert oil_b3["sub_allocations"]["car_maintenance"] == 300.0

    # 3. In Cycle 3, spent all 300 SAR! Roll over to Cycle 4 (2026-12) -> resets to original base 100!
    oil_b3["spent_amount"] = 300.0
    new_budgets_c4 = ensure_household_cycle_budgets(HID, payday_day=27, target_cycle_key="2026-12")
    oil_b4 = next(b for b in new_budgets_c4 if b["category_code"] == "OPEX-FUEL")
    assert oil_b4["allocated_amount"] == 100.0
    assert oil_b4["sub_allocations"]["car_maintenance"] == 100.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_sinking_fund_rollover.py -v`
Expected: FAIL (`is_allocation_metadata_key` or oil allocation calculation).

- [ ] **Step 3: Implement sinking fund metadata recognition and rollover logic**

In `ai_service/salary_cycle.py`:
Update `is_allocation_metadata_key` to recognize `_sinking_fund`:
```python
def is_allocation_metadata_key(key: str) -> bool:
    return bool(key and key.startswith("_"))
```
In `ai_service/supabase_client.py`:
Update `ensure_household_cycle_budgets` to calculate accumulating sinking fund allocations:
- For each category row in `missing_prev_rows`:
  - Extract `sub_allocations` and `_sinking_fund` dict.
  - If `sub_allocations` has numeric items:
    - For each `(sub_code, prev_amount)`:
      - If `_sinking_fund.get(sub_code, {}).get("accumulate")`:
        - `base = float(_sinking_fund[sub_code].get("base_amount", prev_amount))`
        - `unspent = max(0.0, prev_amount - prev_sub_spent)` (or if no sub-transactions, from budget proportion)
        - `new_sub = round(base + unspent, 2)`
        - Add `new_sub` to `new_sub_allocations`
      - Else:
        - `new_sub = float(_sinking_fund.get(sub_code, {}).get("base_amount", prev_amount))`
        - Surplus = `max(0.0, prev_amount - prev_sub_spent)` -> swept to savings!
  - If no numeric sub-allocations (parent category):
    - If `_sinking_fund.get("_parent", {}).get("accumulate")`:
      - `base = float(_sinking_fund["_parent"].get("base_amount", prev_allocated))`
      - `unspent = max(0.0, prev_allocated - prev_spent)`
      - `new_allocated = round(base + unspent, 2)`
      - `delta = round(unspent, 2)`
    - Else:
      - `new_allocated = float(_sinking_fund.get("_parent", {}).get("base_amount", prev_allocated))`
      - `delta = 0.0`
      - `surplus += max(0.0, prev_allocated - prev_spent)` (swept to savings!)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ai_service && python -m pytest tests/test_sinking_fund_rollover.py -v`
Expected: PASS.

- [ ] **Step 5: Run existing cycle rollover tests**

Run: `cd ai_service && python -m pytest tests/test_cycle_rollover_fix.py tests/test_rollover_rule.py -v`
Expected: ALL PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add ai_service/salary_cycle.py ai_service/supabase_client.py ai_service/tests/test_sinking_fund_rollover.py
git commit -m "feat(ai_service): implement sinking fund envelope accumulation and automatic reset"
```

---

### Task 2: Flutter Budget Model & Sinking Fund Helpers

**Files:**
- Modify: `flutter_app/lib/models/models.dart:34-110`
- Test: `flutter_app/test/models/sinking_fund_model_test.dart`

**Interfaces:**
- Consumes: `Budget` model with `sub_allocations` map.
- Produces: `b.isSinkingFund(subCode)`, `b.sinkingFundBase(subCode)`, `b.withSinkingFund(subCode, enabled, base)`.

- [ ] **Step 1: Write failing unit test for Budget model sinking fund helpers**

Create `flutter_app/test/models/sinking_fund_model_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  group('Budget Sinking Fund Helpers', () {
    test('detects sinking fund configuration on sub-category', () {
      final b = Budget(
        id: 'b1',
        householdId: 'hh1',
        categoryCode: 'OPEX-FUEL',
        allocatedAmount: 200,
        spentAmount: 0,
        subAllocations: {
          'car_maintenance': 200.0,
          '_sinking_fund': {
            'car_maintenance': {'accumulate': true, 'base_amount': 100.0},
          },
        },
      );

      expect(b.isSinkingFund('car_maintenance'), isTrue);
      expect(b.sinkingFundBase('car_maintenance'), 100.0);
      expect(b.isSinkingFund('gas_fuel'), isFalse);
    });

    test('detects sinking fund configuration on parent category', () {
      final b = Budget(
        id: 'b2',
        householdId: 'hh1',
        categoryCode: 'OPEX-ENTERTAINMENT',
        allocatedAmount: 300,
        spentAmount: 0,
        subAllocations: {
          '_sinking_fund': {
            '_parent': {'accumulate': true, 'base_amount': 300.0},
          },
        },
      );

      expect(b.isSinkingFund(), isTrue);
      expect(b.sinkingFundBase(), 300.0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/models/sinking_fund_model_test.dart`
Expected: FAIL (`isSinkingFund` not defined on `Budget`).

- [ ] **Step 3: Implement helpers on Budget class**

In `flutter_app/lib/models/models.dart`:
Add methods to `Budget`:
```dart
  bool isSinkingFund([String? subCode]) {
    final key = subCode ?? '_parent';
    final sf = subAllocations['_sinking_fund'];
    if (sf is Map && sf[key] is Map) {
      return (sf[key] as Map)['accumulate'] == true;
    }
    return false;
  }

  double sinkingFundBase([String? subCode]) {
    final key = subCode ?? '_parent';
    final sf = subAllocations['_sinking_fund'];
    if (sf is Map && sf[key] is Map) {
      final base = (sf[key] as Map)['base_amount'];
      if (base is num) return base.toDouble();
    }
    return subCode != null ? (subAllocations[subCode] as num?)?.toDouble() ?? 0.0 : allocatedAmount;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/models/sinking_fund_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add flutter_app/lib/models/models.dart flutter_app/test/models/sinking_fund_model_test.dart
git commit -m "feat(models): add sinking fund query helpers to Budget model"
```

---

### Task 3: Cycle Income Ledger Primacy (Eliminating Static Income)

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart:310-385`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:130-160`
- Modify: `flutter_app/lib/models/household_setup.dart:15-65`
- Modify: `flutter_app/lib/widgets/dashboard/household_setup_card.dart:340-360`
- Test: `flutter_app/test/widgets/cycle_income_ledger_test.dart`

**Interfaces:**
- Consumes: `AccountService.instance.getCycleIncome(householdId, cycleKey)`
- Produces: Hero card, Budget manager, and Setup card deriving 100% of benchmark income from logged cycle `income_records` or operating cash.

- [ ] **Step 1: Write failing widget test for dynamic cycle income loading**

Create `flutter_app/test/widgets/cycle_income_ledger_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:budget_tracker/models/household_setup.dart';

void main() {
  test('HouseholdSetupData treats logged cycle income as completed step', () {
    final dataWithLoggedIncome = HouseholdSetupData(
      paydayDay: 27,
      paydayConfirmed: true,
      monthlyIncome: 15000.0, // populated from logged income_records sum
    );
    expect(dataWithLoggedIncome.isDone(SetupStep.income, hasBudgets: false), isTrue);

    final dataWithoutIncome = HouseholdSetupData(
      paydayDay: 27,
      paydayConfirmed: true,
      monthlyIncome: 0.0,
    );
    expect(dataWithoutIncome.isDone(SetupStep.income, hasBudgets: false), isFalse);
  });
}
```

- [ ] **Step 2: Update DashboardScreen to fetch cycle income from income_records**

In `flutter_app/lib/screens/home/dashboard_screen.dart`:
- Add `double? _cycleLoggedIncome;` state variable.
- In `_loadDashboardData(hid)` or when cycle changes:
  ```dart
  Future<void> _fetchCycleIncome(String hid, String cycleKey) async {
    try {
      final records = await AccountService.instance.getCycleIncome(hid, cycleKey);
      final total = records.fold<double>(0.0, (sum, r) => sum + r.netAmount);
      if (mounted) {
        setState(() => _cycleLoggedIncome = total > 0 ? total : null);
      }
    } catch (_) {}
  }
  ```
- Pass `monthlyIncome: _cycleLoggedIncome` to `BudgetHeroCard` so it uses actual logged cycle income.

- [ ] **Step 3: Update BudgetManagementScreen unallocated computation**

In `flutter_app/lib/screens/home/budget_management_screen.dart`:
Replace lines 134-142 (`households.monthly_income` query) with:
```dart
      double income = 0.0;
      try {
        final records = await AccountService.instance.getCycleIncome(householdId, _currentCycleKey);
        income = records.fold<double>(0.0, (s, r) => s + r.netAmount);
      } catch (_) {}
      
      // If no income logged yet in cycle, check operating cash from accounts
      if (income <= 0) {
        try {
          final accounts = await AccountService.instance.getAccounts(householdId);
          income = accounts
              .where((a) => !a.isArchived && a.accountType.isOperatingPool)
              .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));
        } catch (_) {}
      }
```

- [ ] **Step 4: Update HouseholdSetupCard tapping SetupStep.income**

In `flutter_app/lib/widgets/dashboard/household_setup_card.dart`:
When `SetupStep.income` is tapped (lines 341-352), instead of opening the static `IncomeSettingsCard`, open:
```dart
      case SetupStep.income:
        await RecordIncomeSheet.show(
          context,
          householdId: householdId,
        );
        onChanged();
```

- [ ] **Step 5: Run tests to verify passing**

Run: `cd flutter_app && flutter test test/widgets/cycle_income_ledger_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add flutter_app/lib/screens/home/dashboard_screen.dart flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/widgets/dashboard/household_setup_card.dart flutter_app/test/widgets/cycle_income_ledger_test.dart
git commit -m "feat(income): derive all benchmarks dynamically from logged income records and cash"
```

---

### Task 4: Settings Screen Streamlining (Remove Income & Rollover Settings Cards)

**Files:**
- Modify: `flutter_app/lib/screens/settings/settings_screen.dart:180-330`
- Test: `flutter_app/test/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsScreen`.
- Produces: Clean settings screen free of static monthly income and confusing 3-option rollover radio card.

- [ ] **Step 1: Remove IncomeSettingsCard and RolloverSettingsCard from SettingsScreen**

In `flutter_app/lib/screens/settings/settings_screen.dart`:
- Remove `IncomeSettingsCard` rendering block and its local state.
- Remove `RolloverSettingsCard` rendering block and its local state.
- Keep payday configuration, currency, language, dark mode, accounts, and member management.

- [ ] **Step 2: Update existing settings screen test**

In `flutter_app/test/screens/settings_screen_test.dart` (or create if absent):
Verify that neither `IncomeSettingsCard` nor `RolloverSettingsCard` appears in `SettingsScreen`.

- [ ] **Step 3: Run Flutter tests**

Run: `cd flutter_app && flutter test test/screens/settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit Task 4**

```bash
git add flutter_app/lib/screens/settings/settings_screen.dart
git commit -m "refactor(settings): remove static income and rollover settings cards"
```

---

### Task 5: Per-Category & Sub-Category Sinking Fund UI Toggle

**Files:**
- Modify: `flutter_app/lib/widgets/sub_budget_allocation_dialog.dart:80-680`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/sinking_fund_dialog_test.dart`

**Interfaces:**
- Consumes: Sub-category definition & parent budget metadata.
- Produces: User toggle to turn Sinking Fund accumulation ON/OFF per sub-category or category, stored in `_sinking_fund`.

- [ ] **Step 1: Add localization keys for Sinking Fund**

In `flutter_app/lib/l10n/app_localizations.dart`:
Add in `en`, `ar`, `ur`:
- `sinking_fund_toggle`: "Accumulate unspent (Sinking fund)" / "ترحيل الفائض (صندوق تراكمي)" / "بچ جانے والی رقم محفوظ رکھیں (سنکنگ فنڈ)"
- `sinking_fund_desc`: "Carries over unspent funds each cycle; resets to base when spent." / "يرحّل الفائض دورياً للرصيد، ويعود للأساس عند صرفه بالكامل." / "خرچ ہونے پر دوبارہ بنیادی رقم پر آجائے گا۔"
- `sinking_fund_base_hint`: "Base monthly allocation" / "المخصص الشهري الأساسي" / "ماہانہ بنیادی رقم"

- [ ] **Step 2: Add Sinking Fund state and toggle to SubBudgetAllocationDialog**

In `flutter_app/lib/widgets/sub_budget_allocation_dialog.dart`:
- In `_SubCategoryItemDef`, add:
  `bool isSinkingFund;`
  `double baseAmount;`
- In `_loadSubCategories`:
  Read `_sinking_fund` from `bData['sub_allocations']`.
  If present for `subCode`, set `item.isSinkingFund = true` and `item.baseAmount = ...`.
- In the item row build method:
  Add an interactive chip or switch:
  When clicked, toggle `item.isSinkingFund = !item.isSinkingFund`.
  Show a badge or indicator when active.
- In `_handleSave`:
  Pack `_sinking_fund` metadata into the payload:
  ```dart
  final sfMap = <String, dynamic>{};
  for (final item in _subItems) {
    if (item.isSinkingFund) {
      final base = parseMoneyInput(item.controller.text.trim()) ?? item.baseAmount;
      sfMap[item.subCode] = {'accumulate': true, 'base_amount': base};
    }
  }
  // Store _sinking_fund in subAllocations
  ```
  Pass to `ApiService.instance.saveSubAllocations`.

- [ ] **Step 3: Run widget test to verify toggle behavior**

Create `flutter_app/test/widgets/sinking_fund_dialog_test.dart` to verify that toggling sinking fund on a subcategory updates the saved metadata map.
Run: `cd flutter_app && flutter test test/widgets/sinking_fund_dialog_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit Task 5**

```bash
git add flutter_app/lib/widgets/sub_budget_allocation_dialog.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/sinking_fund_dialog_test.dart
git commit -m "feat(ui): add sinking fund accumulation toggle to sub-budget allocation dialog"
```

---

### Task 6: Silent Sinking-Fund-Aware Rollover Copy in Budget Management

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:240-320`
- Test: `flutter_app/test/screens/budget_management_copy_test.dart`

**Interfaces:**
- Consumes: `_copyFromPreviousMonth` in `budget_management_screen.dart`.
- Produces: Silent copy that accumulates items with sinking fund toggle ON, resets non-sinking items to base, and records surplus without showing redundant dialogs.

- [ ] **Step 1: Refactor `_copyFromPreviousMonth` to remove popup dialog and apply sinking fund logic**

In `flutter_app/lib/screens/home/budget_management_screen.dart`:
- Remove lines 256-290 (the `showDialog` with `bm_option_sweep` vs `bm_option_rollover`).
- For each `b` in `prevBudgets`:
  - Check `b['sub_allocations']?['_sinking_fund']`:
    - For sub-allocations:
      - If `_sinking_fund[sub_code]['accumulate'] == true`:
        - Calculate carryover: `unspent = max(0, prev_sub_alloc - prev_sub_spent)`
        - `new_sub_alloc = base + unspent`
      - Else:
        - `new_sub_alloc = base`
    - For parent category:
      - If `_sinking_fund['_parent']['accumulate'] == true`:
        - `carryover = max(0, prev_allocated - prev_spent)`
        - `new_allocated = base + carryover`
        - `delta = carryover`
      - Else:
        - `new_allocated = base`
        - `delta = 0.0`
- Insert `newEntries` into `budgets`.
- Show success snackbar: `AppSnackBar.showSuccess(context, context.tr('bm_copied_silent_success'))`.

- [ ] **Step 2: Run test to verify silent copy**

Run: `cd flutter_app && flutter test test/screens/budget_management_copy_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit Task 6**

```bash
git add flutter_app/lib/screens/home/budget_management_screen.dart
git commit -m "feat(budgets): replace redundant copy dialog with silent sinking-fund-aware carryover"
```

---

### Task 7: Localization Verification (Arabic, English, Urdu)

**Files:**
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/l10n/localization_completeness_test.dart`

**Interfaces:**
- Produces: Complete translation coverage for all new strings in English, Arabic, and Urdu.

- [ ] **Step 1: Verify all keys exist in ar, en, ur dictionaries in `app_localizations.dart`**
- [ ] **Step 2: Run flutter analyzer**

Run: `cd flutter_app && flutter analyze`
Expected: 0 issues found.

- [ ] **Step 3: Commit Task 7**

```bash
git add flutter_app/lib/l10n/app_localizations.dart
git commit -m "feat(l10n): complete trilingual strings for sinking funds and cycle income"
```

---

### Task 8: End-to-End Verification & Test Suite Execution

**Files:**
- Test: `ai_service/tests/`
- Test: `flutter_app/test/`

- [ ] **Step 1: Run all Python tests in `ai_service`**

Run: `cd ai_service && python -m pytest -v`
Expected: All tests pass.

- [ ] **Step 2: Run all Flutter unit & widget tests**

Run: `cd flutter_app && flutter test`
Expected: All tests pass (>= 968 tests passing).

- [ ] **Step 3: Run Flutter Analyzer**

Run: `cd flutter_app && flutter analyze`
Expected: 0 issues found.

- [ ] **Step 4: Build release APK to verify production compilation**

Run: `cd flutter_app && flutter build apk --release`
Expected: Built `build/app/outputs/flutter-apk/app-release.apk` cleanly without compilation or proguard errors.
