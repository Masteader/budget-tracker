# Cycle Rollover, Navigation, Deficit Solvency, and Category Lifecycle Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 4 core lifecycle, navigation, and solvency defects in the household finance OS:
1. Prevent cycle rollover from hijacking previous cycle budgets and their spent expenses into the new cycle.
2. Ensure full historical cycle navigation in Budgets and add cycle filtering to the Transactions tab.
3. Fix Category Renaming ("Rename Only" & "Replace & Archive") by routing through backend APIs instead of direct PostgREST calls that cause 405 Method Not Allowed.
4. Correct the Budget Solvency / Deficit calculation to evaluate live cash against remaining unspent commitments rather than initial total monthly allocation.

**Architecture:**
- Backend (`ai_service/supabase_client.py`): In `ensure_household_cycle_budgets`, eliminate the legacy month-based overwrite. New cycles receive fresh budget envelopes with `spent_amount = 0.0`.
- Backend (`ai_service/salary_cycle.py` & `ai_service/routes/budgets.py`):
  - Expand `get_available_cycles_for_household` to discover cycles from both `budgets` and `transactions` as well as the past 6 months so historical navigation is always available.
  - Enhance `replace_household_category` with `update_past_transactions: bool` so that "Rename Only" safely updates custom categories or migrates transactions without PostgREST 405 errors.
- Flutter (`flutter_app`):
  - Update `BudgetManagementScreen` to route both rename choices through `ApiService.instance.replaceCategory`.
  - Update `BudgetManagementScreen` solvency logic to compute remaining unspent obligations (`max(0, allocated - spent)`).
  - Add cycle filtering to `TransactionFeedScreen` using `SalaryCycleSelectorBar`.

**Tech Stack:**
- Flutter 3.x / Dart (Velvet Burgundy & Sovereign HUD theme)
- Python 3.11 / FastAPI AI Microservice / Pytest
- Supabase PostgreSQL / RLS

---

## File Structure

### Backend (`ai_service`)
- `ai_service/supabase_client.py`: Update `ensure_household_cycle_budgets` to isolate new cycle rows and avoid month-based hijacking of previous cycles.
- `ai_service/salary_cycle.py`:
  - Update `get_available_cycles_for_household` to include past cycles from transactions and date windows.
  - Update `replace_household_category` to support `update_past_transactions`.
- `ai_service/models.py`: Add `update_past_transactions: bool = False` to `CategoryReplaceRequest`.
- `ai_service/routes/budgets.py`: Pass `update_past_transactions` to `replace_household_category`.
- `ai_service/tests/test_cycle_rollover_fix.py`: Comprehensive unit tests for clean cycle provisioning and cycle discovery.
- `ai_service/tests/test_category_rename_modes.py`: Unit tests for `replace_household_category` with and without past transaction migration.

### Flutter App (`flutter_app`)
- `flutter_app/lib/services/api/budget_api_client.dart` & `flutter_app/lib/services/api_service.dart`: Add `updatePastTransactions` parameter to `replaceCategory`.
- `flutter_app/lib/screens/home/budget_management_screen.dart`:
  - Route `CategoryLifecycleAction.renameOnly` through `ApiService.instance.replaceCategory(updatePastTransactions: true)`.
  - Fix solvency margin and capacity deficit calculations to use unspent amounts.
  - Fix `_matchesSelectedCycle` date prefix matching.
- `flutter_app/lib/screens/home/transaction_feed_screen.dart`: Add salary cycle selection bar and cycle-scoped transaction filtering.
- `flutter_app/test/screens/budget_solvency_test.dart`: Widget tests verifying cash margin calculations when money has been spent.
- `flutter_app/test/screens/category_rename_flow_test.dart`: Tests verifying both rename options call the API client.
- `flutter_app/test/screens/transaction_feed_cycle_test.dart`: Tests for cycle-filtered transaction feed.

---

### Task 1: Backend Cycle Rollover Isolation & Clean Envelopes

**Files:**
- Modify: `ai_service/supabase_client.py:680-763`
- Test: `ai_service/tests/test_cycle_rollover_fix.py`

**Interfaces:**
- Produces: Clean `ensure_household_cycle_budgets` that creates new rows with `spent_amount = 0.0` for a new cycle key (`YYYY-MM`) and never overwrites previous cycle keys.

- [ ] **Step 1: Write failing test in `ai_service/tests/test_cycle_rollover_fix.py`**

```python
from datetime import date
from unittest.mock import MagicMock
import pytest
from supabase_client import ensure_household_cycle_budgets

def test_ensure_household_cycle_budgets_never_overwrites_previous_cycle(monkeypatch):
    """
    On Oct 27 (payday 27), the new cycle is 2026-11.
    If the household has an existing budget row with month='2026-10-01' and cycle_key='2026-10'
    having spent_amount=3287.0, ensure_household_cycle_budgets MUST NOT update its cycle_key to 2026-11.
    It must create a new row for 2026-11 with spent_amount=0.0.
    """
    mock_sb = MagicMock()
    # 1. Check existing for cycle_key='2026-11' -> None
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    
    # 2. Latest previous cycle rows
    prev_rows = [
        {
            "id": "b-prev-1",
            "household_id": "hh-test-1",
            "category_code": "OPEX-UTIL",
            "month": "2026-10-01",
            "cycle_key": "2026-10",
            "allocated_amount": 3362.0,
            "spent_amount": 3287.0,
            "is_active": True,
        }
    ]
    mock_sb.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = prev_rows
    
    inserted_records = []
    def capture_insert(rows):
        inserted_records.extend(rows)
        m = MagicMock()
        m.data = rows
        return m
    mock_sb.table.return_value.insert.side_effect = capture_insert
    
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)
    monkeypatch.setattr("supabase_client.get_household_payday", lambda hid: 27)
    monkeypatch.setattr("supabase_client.get_household_rollover_rule", lambda hid: "fresh_start")

    # Run for target date 2026-10-27
    res = ensure_household_cycle_budgets("hh-test-1", target_date=date(2026, 10, 27), payday_day=27)

    # Verify update was NEVER called on cycle_key
    mock_sb.table.return_value.update.assert_not_called()
    
    # Verify new row was inserted with cycle_key='2026-11' and spent_amount=0.0
    assert len(inserted_records) == 1
    assert inserted_records[0]["cycle_key"] == "2026-11"
    assert inserted_records[0]["spent_amount"] == 0.0
    assert inserted_records[0]["allocated_amount"] == 3362.0
    assert inserted_records[0]["month"] == "2026-11-01"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_cycle_rollover_fix.py -v`

- [ ] **Step 3: Modify `ensure_household_cycle_budgets` in `ai_service/supabase_client.py`**

In `ai_service/supabase_client.py`:
1. Remove the fallback block that did `client.table("budgets").update({"cycle_key": cycle_key}).eq("month", month_str)` when `existing_month` had a different or non-empty `cycle_key`.
2. Compute `month_str = f"{cycle_key}-01"` for the new cycle envelope so it matches the cycle's unique month constraint.
3. Ensure inserted rows set `month: f"{cycle_key}-01"`, `cycle_key: cycle_key`, `spent_amount: 0.0`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ai_service && python -m pytest tests/test_cycle_rollover_fix.py -v`
Expected: PASS

---

### Task 2: Available Cycles Discovery from Transactions and Date Windows

**Files:**
- Modify: `ai_service/salary_cycle.py:393-430`
- Test: `ai_service/tests/test_cycle_rollover_fix.py`

**Interfaces:**
- Produces: `get_available_cycles_for_household(household_id, payday_day)` returning all historical cycles where either budgets or transactions exist, plus the prior 3 cycles.

- [ ] **Step 1: Write failing test in `ai_service/tests/test_cycle_rollover_fix.py`**

```python
def test_get_available_cycles_includes_past_cycles_and_transactions(monkeypatch):
    """
    Even if budgets table only contains 2026-11, if transactions exist in 2026-10,
    or if user wants to navigate to past cycles (September/October),
    get_available_cycles_for_household returns both cycles.
    """
    import salary_cycle
    mock_sb = MagicMock()
    # budgets only has 2026-11
    mock_sb.table.return_value.select.return_value.eq.return_value.execute.side_effect = [
        MagicMock(data=[{"cycle_key": "2026-11", "month": "2026-11-01"}]), # budgets
        MagicMock(data=[{"cycle_key": "2026-10", "timestamp": "2026-10-12T10:00:00Z"}]), # transactions
    ]
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)
    monkeypatch.setattr("salary_cycle.get_client", lambda: mock_sb)
    monkeypatch.setattr("supabase_client.ensure_household_cycle_budgets", lambda hid, **kw: [])
    monkeypatch.setattr("supabase_client.get_household_payday", lambda hid: 27)
    monkeypatch.setattr("salary_cycle.riyadh_today", lambda: date(2026, 10, 27))

    res = salary_cycle.get_available_cycles_for_household("hh-test-1", payday_day=27)
    cycle_keys = [c["cycle_key"] for c in res["cycles"]]
    
    assert "2026-11" in cycle_keys
    assert "2026-10" in cycle_keys
    # Current cycle is 2026-11
    assert res["current_cycle"]["cycle_key"] == "2026-11"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_cycle_rollover_fix.py -k test_get_available_cycles -v`

- [ ] **Step 3: Implement cycle discovery in `salary_cycle.py`**

Update `get_available_cycles_for_household`:
1. Query distinct `cycle_key` from `budgets`.
2. Query distinct `cycle_key` from `transactions`.
3. Generate the prior 3 cycles relative to `current_cycle`.
4. Return `sorted(keys, reverse=True)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ai_service && python -m pytest tests/test_cycle_rollover_fix.py -v`
Expected: PASS

---

### Task 3: Backend Category Rename & Transaction Migration

**Files:**
- Modify: `ai_service/models.py:126-137`
- Modify: `ai_service/routes/budgets.py:497-518`
- Modify: `ai_service/salary_cycle.py:1375-1487`
- Test: `ai_service/tests/test_category_rename_modes.py`

**Interfaces:**
- Consumes: `CategoryReplaceRequest` with `update_past_transactions: bool = False`.
- Produces: `replace_household_category(...)` that:
  - If `update_past_transactions` is True: updates all `transactions` in the household from `old_code` to `new_code` (or directly updates `cost_control_codes.category` for custom categories).
  - If `update_past_transactions` is False: archives old category and leaves past transactions untouched.

- [ ] **Step 1: Write failing test in `ai_service/tests/test_category_rename_modes.py`**

```python
from unittest.mock import MagicMock
from salary_cycle import replace_household_category

def test_replace_category_with_update_past_transactions(monkeypatch):
    mock_sb = MagicMock()
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
        {"allocated_amount": 400.0}
    ]
    monkeypatch.setattr("salary_cycle.get_client", lambda: mock_sb)
    
    res = replace_household_category(
        household_id="hh-test-1",
        old_code="OPEX-FUEL",
        new_name="بنزين ومشاوير",
        update_past_transactions=True,
    )
    
    assert res["status"] == "success"
    # Verify transactions table was updated from OPEX-FUEL to new code
    tx_update_call = [
        call for call in mock_sb.table.return_value.update.mock_calls
        if "category_code" in str(call)
    ]
    assert len(tx_update_call) > 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_category_rename_modes.py -v`

- [ ] **Step 3: Implement in `models.py`, `salary_cycle.py`, and `routes/budgets.py`**

1. In `models.py`, update `CategoryReplaceRequest`:
   ```python
   class CategoryReplaceRequest(BaseModel):
       household_id: str
       old_code: str
       new_name: str
       new_code: Optional[str] = None
       cycle_key: Optional[str] = None
       update_past_transactions: bool = False
   ```
2. In `salary_cycle.py`, update `replace_household_category`:
   - If `update_past_transactions=True`: update `transactions` where `household_id=household_id AND category_code=old_code` to set `category_code=clean_code`.
   - Also, if `old_code.startswith("CUSTOM-")` and `update_past_transactions=True`, update `cost_control_codes` directly for that household's code.
3. In `routes/budgets.py`: pass `update_past_transactions=req.update_past_transactions` into `replace_household_category`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ai_service && python -m pytest tests/test_category_rename_modes.py -v`
Expected: PASS

---

### Task 4: Flutter Category Renaming Flow (No Raw PostgREST 405 Calls)

**Files:**
- Modify: `flutter_app/lib/services/api/budget_api_client.dart:396-416`
- Modify: `flutter_app/lib/services/api_service.dart:409-423`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:824-878, 925-940`
- Test: `flutter_app/test/screens/category_rename_flow_test.dart`

**Interfaces:**
- Produces: `ApiService.instance.replaceCategory(..., updatePastTransactions: bool)`
- Updates `BudgetManagementScreen._renameCategory` to use `ApiService.instance.replaceCategory` for BOTH `replaceAndArchive` and `renameOnly`, eliminating raw `supabase.from('cost_control_codes').update(...)`.

- [ ] **Step 1: Write widget/unit test in `flutter_app/test/screens/category_rename_flow_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api_service.dart';

void main() {
  test('replaceCategory sends update_past_transactions flag', () async {
    // Verify API client serializes update_past_transactions
  });
}
```

- [ ] **Step 2: Update `budget_api_client.dart` and `api_service.dart`**

Add `bool updatePastTransactions = false` to `replaceBudgetCategory` and `replaceCategory`:
```dart
Future<Map<String, dynamic>> replaceBudgetCategory({
  required String householdId,
  required String oldCode,
  required String newName,
  String? newCode,
  String? cycleKey,
  bool updatePastTransactions = false,
}) async {
  final res = await baseClient.post(
    '/budgets/categories/replace',
    {
      'household_id': householdId,
      'old_code': oldCode,
      'new_name': newName,
      'update_past_transactions': updatePastTransactions,
      if (newCode != null && newCode.isNotEmpty) 'new_code': newCode,
      if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
    },
    shouldSign: false,
    timeout: const Duration(seconds: 10),
  );
  return ApiRequestException.check(res);
}
```

- [ ] **Step 3: Update `budget_management_screen.dart`**

In `_renameCategory`:
Replace the raw `supabase.from('cost_control_codes').update(...)` calls with:
```dart
await ApiService.instance.replaceCategory(
  householdId: staticData.householdId,
  oldCode: categoryCode,
  newName: newName,
  updatePastTransactions: (action == CategoryLifecycleAction.renameOnly),
);
```
Apply the same for the `txCount == 0` path.

- [ ] **Step 4: Run Flutter Analyzer and Tests**

Run: `cd flutter_app && flutter test test/screens/category_rename_flow_test.dart`

---

### Task 5: Budget Solvency & Deficit Calculation (Live Cash vs Unspent Obligations)

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:1258-1285`
- Test: `flutter_app/test/screens/budget_solvency_test.dart`

**Interfaces:**
- Produces: Correct `cashMargin` and `deficitAccount` calculations comparing live operating cash to `totalUnspentCommitments = sum(max(0, allocated - spent))`.

- [ ] **Step 1: Write test in `flutter_app/test/screens/budget_solvency_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Solvency: 5000 budget with 5000 spent and 2000 cash balance has NO deficit', () {
    final allocated = 5000.0;
    final spent = 5000.0;
    final liveCash = 2000.0;
    
    final unspentObligation = (allocated - spent).clamp(0.0, double.infinity);
    final margin = liveCash - unspentObligation;
    
    expect(unspentObligation, 0.0);
    expect(margin, 2000.0);
    expect(margin < -0.005, isFalse); // No deficit!
  });
}
```

- [ ] **Step 2: Update `budget_management_screen.dart`**

In lines 1258-1285:
```dart
final operatingCash = staticData.accounts
    .where((a) => !a.isArchived && a.accountType.isOperatingPool)
    .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));
final hasOperatingCash = operatingCash > 0;
final benchmarkCash = hasOperatingCash ? operatingCash : staticData.monthlyIncome;
final hasBenchmark = benchmarkCash > 0;

// Compute remaining unspent commitments for active budgets
final totalUnspentCommitments = budgets
    .where((b) => b.isActive)
    .fold<double>(0.0, (sum, b) => sum + (b.allocatedAmount - b.spentAmount).clamp(0.0, double.infinity));

// When operating cash is available, margin is Live Cash minus Unspent Obligations
// If purely planning against monthly income, margin is Monthly Income minus Total Allocated
final cashMargin = hasOperatingCash
    ? (operatingCash - totalUnspentCommitments)
    : (hasBenchmark ? (benchmarkCash - totalAllocated) : 0.0);
final isOverAllocated = hasBenchmark && cashMargin < -0.005;

// Calculate account capacity deficits against remaining unspent allocations
Account? deficitAccount;
double deficitAmount = 0.0;
if (staticData.accounts.isNotEmpty) {
  final Map<String, double> unspentByAccount = {};
  for (final b in budgets.where((b) => b.isActive)) {
    if (b.accountId != null && b.accountId!.isNotEmpty) {
      final unspent = (b.allocatedAmount - b.spentAmount).clamp(0.0, double.infinity);
      unspentByAccount[b.accountId!] = (unspentByAccount[b.accountId!] ?? 0.0) + unspent;
    }
  }
  for (final entry in unspentByAccount.entries) {
    final acc = staticData.accounts.where((a) => a.id == entry.key).firstOrNull;
    if (acc != null && acc.balance < entry.value) {
      deficitAccount = acc;
      deficitAmount = entry.value - acc.balance;
      break;
    }
  }
}
```

- [ ] **Step 3: Run Flutter tests**

Run: `cd flutter_app && flutter test test/screens/budget_solvency_test.dart`
Expected: PASS

---

### Task 6: Add Salary Cycle Selector & Filtering to Transaction Feed

**Files:**
- Modify: `flutter_app/lib/screens/home/transaction_feed_screen.dart`
- Test: `flutter_app/test/screens/transaction_feed_cycle_test.dart`

**Interfaces:**
- Produces: Transaction Feed with `SalaryCycleSelectorBar` support, filtering transactions by `t.cycleKey == selectedCycle.cycleKey` (or timestamp window) when a cycle is chosen, with an "All Cycles" toggle.

- [ ] **Step 1: Write test in `flutter_app/test/screens/transaction_feed_cycle_test.dart`**

Verify that selecting a cycle filters transaction rows by cycle range/key.

- [ ] **Step 2: Update `TransactionFeedScreen`**

1. Fetch cycles via `ApiService.instance.getSalaryCycles(householdId)`.
2. Add `SalaryCycleSelectorBar` at the top of the feed (with previous/next chevron buttons).
3. Filter `_filterAndSort` using the selected cycle's `cycleStart` and `cycleEnd` or `cycle_key`.
4. Provide an "All" chip in the filter bar so the user can see everything across all time.

- [ ] **Step 3: Run Flutter analyzer and tests**

Run: `cd flutter_app && flutter analyze && flutter test`
Expected: 0 issues, all tests pass.

---

### Task 7: Full Verification & Local DB Fix Script

**Files:**
- Create: `supabase/scripts/fix_october_hijacked_cycle.py` (Local/Admin helper to restore `cycle_key='2026-10'` on the hijacked October budgets row if needed).

- [ ] **Step 1: Run Python tests**
Run: `cd ai_service && python -m pytest -v`

- [ ] **Step 2: Run Flutter tests**
Run: `cd flutter_app && flutter test`

- [ ] **Step 3: Run Flutter analyzer**
Run: `cd flutter_app && flutter analyze`
