# Sub-Category Budget Allocations with Auto-Summing Parent Category Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable users to set budget allocations at the sub-category level in the "Budgets" tab, with the parent category automatically computing and displaying the sum of all its sub-budgets, and itemized spent vs allocated progress in the breakdown sheet.

**Architecture:** Add a `sub_allocations` JSONB column to the `budgets` table. Provide a backend endpoint `POST /budgets/sub-allocations` that saves sub-allocations and recalculates parent `allocated_amount = SUM(sub_allocations.values())`. In Flutter, add an interactive `SubBudgetAllocationDialog` in `BudgetManagementScreen` with live total summing as the user types, and enhance `SubBudgetBreakdownSheet` to display itemized spent vs allocated progress per sub-category.

**Tech Stack:** FastAPI (Python 3.12+), Supabase PostgreSQL, Flutter / Dart 3.x, Flutter Material 3, GoogleFonts.

**Spec:** User request from 2026-10-02: "in the budgets bottom tap i need to specify the budget for the sub categories and the main category will have a sum of all the categories with a main title" and deduplication of transaction sub-categories.

## Global Constraints
- Salary cycle runs from 27th of month $M-1$ to 26th of month $M$ (labeled as Month $M$).
- Parent category `allocated_amount` is always equal to the sum of its active sub-allocations.
- No pixel overflows on any screen size.
- Maintain existing SMS toggle exclusively in `IngestionSettingsScreen`.
- Strict type safety in Flutter and Python.

---

### Task 1: Database Migration for Sub-Allocations

**Files:**
- Create: `supabase/migrations/20261002_add_sub_allocations_to_budgets.sql`
- Test: `ai_service/tests/test_sub_allocations_schema.py`

**Interfaces:**
- Consumes: `budgets` table schema
- Produces: `sub_allocations` JSONB column on `budgets` table with default `'{}'::jsonb`

- [ ] **Step 1: Write the failing test**

```python
# ai_service/tests/test_sub_allocations_schema.py
import pytest
from supabase_client import get_client

def test_budgets_table_has_sub_allocations_column():
    sb = get_client()
    res = sb.table("budgets").select("id, sub_allocations").limit(1).execute()
    assert res.data is not None
    if len(res.data) > 0:
        assert "sub_allocations" in res.data[0]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest ai_service/tests/test_sub_allocations_schema.py -v`
Expected: FAIL with `column budgets.sub_allocations does not exist`

- [ ] **Step 3: Write migration SQL and apply it**

```sql
-- supabase/migrations/20261002_add_sub_allocations_to_budgets.sql
ALTER TABLE budgets 
ADD COLUMN IF NOT EXISTS sub_allocations JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Comment for PostgREST schema documentation
COMMENT ON COLUMN budgets.sub_allocations IS 'Dictionary of sub_code to allocated_amount for granular sub-budgets';
```

Apply migration to Supabase using a runner script via `get_client()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest ai_service/tests/test_sub_allocations_schema.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261002_add_sub_allocations_to_budgets.sql ai_service/tests/test_sub_allocations_schema.py
git commit -m "feat(db): add sub_allocations JSONB column to budgets table"
```

---

### Task 2: Backend API for Sub-Category Allocations & Enhanced Breakdown

**Files:**
- Modify: `ai_service/salary_cycle.py`
- Modify: `ai_service/main.py`
- Modify: `ai_service/models.py`
- Test: `ai_service/tests/test_sub_allocations_api.py`

**Interfaces:**
- Produces: `POST /budgets/sub-allocations`
  - Request: `{"household_id": str, "category_code": str, "cycle_key": str, "sub_allocations": Dict[str, float]}`
  - Response: Updated budget dict with auto-summed `allocated_amount`
- Modifies: `GET /budgets/breakdown`
  - Sub-categories now include `allocated_amount` and `remaining_amount`

- [ ] **Step 1: Write the failing test**

```python
# ai_service/tests/test_sub_allocations_api.py
from fastapi.testclient import TestClient
from main import app, APP_AUTH_TOKEN

client = TestClient(app)
AUTH_HEADERS = {"X-App-Token": APP_AUTH_TOKEN}
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"

def test_save_sub_allocations_auto_sums_parent():
    payload = {
        "household_id": HOUSEHOLD_ID,
        "category_code": "OPEX-UTILITIES",
        "cycle_key": "2026-10",
        "sub_allocations": {
            "housing_rent": 3000.0,
            "electricity_sec": 150.0,
            "fiber_internet": 250.0,
            "mobile_sims": 100.0,
            "water_municipal": 50.0
        }
    }
    resp = client.post("/budgets/sub-allocations", json=payload, headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["budget"]["allocated_amount"] == 3550.0
    assert data["budget"]["sub_allocations"]["housing_rent"] == 3000.0

def test_breakdown_includes_sub_allocation_amounts():
    resp = client.get(f"/budgets/breakdown?household_id={HOUSEHOLD_ID}&cycle_key=2026-10", headers=AUTH_HEADERS)
    assert resp.status_code == 200
    categories = resp.json().get("categories", [])
    util = next((c for c in categories if c["category_code"] == "OPEX-UTILITIES"), None)
    assert util is not None
    rent = next((s for s in util["sub_categories"] if s["sub_code"] == "housing_rent"), None)
    assert rent is not None
    assert rent["allocated_amount"] == 3000.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest ai_service/tests/test_sub_allocations_api.py -v`
Expected: FAIL with 404 or 405 (endpoint not found)

- [ ] **Step 3: Implement minimal code in `salary_cycle.py` and `main.py`**

1. In `ai_service/models.py`:
   Add `SubAllocationsRequest`:
   ```python
   class SubAllocationsRequest(BaseModel):
       household_id: str
       category_code: str
       cycle_key: str
       sub_allocations: dict[str, float]
   ```
2. In `ai_service/salary_cycle.py`:
   Add `save_sub_allocations(household_id, category_code, cycle_key, sub_allocations)`:
   - Compute `total = round(sum(sub_allocations.values()), 2)`
   - Update `budgets` where `household_id=hid`, `category_code=cat`, `cycle_key=ck` with `allocated_amount=total`, `sub_allocations=sub_allocations`.
3. In `get_cycle_breakdown`:
   - Pass `b.get("sub_allocations") or {}`
   - In `sub_items.append({...})`, include `allocated_amount = round(float(sub_alloc_map.get(sc_code, 0.0)), 2)`.
4. In `ai_service/main.py`:
   Add route:
   ```python
   @app.post("/budgets/sub-allocations", tags=["budgets"])
   async def set_sub_allocations(req: SubAllocationsRequest):
       from salary_cycle import save_sub_allocations
       return save_sub_allocations(req.household_id, req.category_code, req.cycle_key, req.sub_allocations)
   ```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest ai_service/tests/test_sub_allocations_api.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/models.py ai_service/salary_cycle.py ai_service/main.py ai_service/tests/test_sub_allocations_api.py
git commit -m "feat(api): add sub-allocations endpoint and itemized allocated amounts in breakdown"
```

---

### Task 3: Flutter Models and ApiService Updates

**Files:**
- Modify: `flutter_app/lib/models/models.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/sub_allocations_model_test.dart`

**Interfaces:**
- `Budget.subAllocations`: `Map<String, double>`
- `SubCategoryBreakdownItem.allocatedAmount`: `double`
- `ApiService.saveSubAllocations(householdId, categoryCode, cycleKey, subAllocations)`

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/sub_allocations_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('SubCategoryBreakdownItem parses allocatedAmount and progress', () {
    final map = {
      'sub_code': 'housing_rent',
      'name': 'Housing Rent',
      'allocated_amount': 3000.0,
      'spent_amount': 3000.0,
      'transaction_count': 1,
    };
    final item = SubCategoryBreakdownItem.fromMap(map);
    expect(item.allocatedAmount, 3000.0);
    expect(item.spentAmount, 3000.0);
    expect(item.usagePercent, 1.0);
  });

  test('Budget parses subAllocations correctly', () {
    final map = {
      'id': '123',
      'household_id': 'hid',
      'month': '2026-10-01',
      'category_code': 'OPEX-UTILITIES',
      'allocated_amount': 3550.0,
      'spent_amount': 3000.0,
      'sub_allocations': {
        'housing_rent': 3000.0,
        'electricity_sec': 150.0,
      },
    };
    final b = Budget.fromMap(map);
    expect(b.subAllocations['housing_rent'], 3000.0);
    expect(b.subAllocations['electricity_sec'], 150.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sub_allocations_model_test.dart`
Expected: Compilation failure or missing fields

- [ ] **Step 3: Implement model and ApiService updates**

1. In `flutter_app/lib/models/models.dart`:
   - Add `subAllocations` to `Budget`.
   - Add `allocatedAmount` to `SubCategoryBreakdownItem`, with getter `double get usagePercent => allocatedAmount > 0 ? (spentAmount / allocatedAmount).clamp(0.0, 1.0) : 0.0;`.
2. In `flutter_app/lib/services/api_service.dart`:
   - Add `Future<Map<String, dynamic>> saveSubAllocations({required String householdId, required String categoryCode, required String cycleKey, required Map<String, double> subAllocations})`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sub_allocations_model_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/models.dart flutter_app/lib/services/api_service.dart flutter_app/test/sub_allocations_model_test.dart
git commit -m "feat(flutter): update models and ApiService for sub-allocations"
```

---

### Task 4: Flutter Sub-Budget Allocation Dialog with Real-Time Auto-Sum

**Files:**
- Create: `flutter_app/lib/widgets/sub_budget_allocation_dialog.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`

**Interfaces:**
- `SubBudgetAllocationDialog.show(...)`
  - Arguments: `BuildContext context`, `String householdId`, `String categoryCode`, `String categoryName`, `String cycleKey`, `Map<String, double> existingAllocations`
  - Feature: Live auto-summing header `Sum Total: SAR X,XXX.XX` as user types in sub-category fields.

- [ ] **Step 1: Create `SubBudgetAllocationDialog`**

```dart
// flutter_app/lib/widgets/sub_budget_allocation_dialog.dart
// Interactive dialog listing all sub-categories for a parent category.
// Each row has sub-category name, icon, and TextEditingController.
// On any text change, re-computes sum and updates top header chip.
// On Save: calls ApiService.instance.saveSubAllocations and pops with true.
```

- [ ] **Step 2: Connect `BudgetManagementScreen` edit button & card tap**

1. Update `_editBudget` in `budget_management_screen.dart`:
   - If category has predefined sub-categories in `kSubCategoriesByParent[code]`:
     Open `SubBudgetAllocationDialog.show(...)`.
   - Else fallback to lump-sum amount dialog.
2. In each category card, show sub-allocation breakdown if set (e.g. `Rent: SAR 3,000 • Electricity: SAR 150...`).

- [ ] **Step 3: Verify with flutter analyze**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/widgets/sub_budget_allocation_dialog.dart flutter_app/lib/screens/home/budget_management_screen.dart
git commit -m "feat(ui): add interactive sub-budget allocation dialog with real-time auto-summing"
```

---

### Task 5: Enhance Sub-Budget Breakdown Sheet & Dashboard UI

**Files:**
- Modify: `flutter_app/lib/widgets/sub_budget_breakdown_sheet.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`

**Interfaces:**
- Each sub-category item in `SubBudgetBreakdownSheet` renders:
  - If `allocatedAmount > 0`:
    - `SAR ${spent} of SAR ${allocated}`
    - Mini progress bar with usage percent
  - If `allocatedAmount == 0`:
    - `SAR ${spent} spent (no sub-limit set)`

- [ ] **Step 1: Update `SubBudgetBreakdownSheet` list item renderer**

Add allocated amount and progress indicator for sub-categories that have a specific allocation limit.

- [ ] **Step 2: Verify with flutter analyze**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/widgets/sub_budget_breakdown_sheet.dart flutter_app/lib/screens/home/dashboard_screen.dart
git commit -m "feat(ui): display spent vs allocated progress bars per sub-category in breakdown sheet"
```

---

### Task 6: End-to-End Verification on Device

**Files:**
- Full test suites across backend and flutter
- Device APK build and install via adb

- [ ] **Step 1: Run full Python and Flutter test suites**

Run:
`pytest ai_service/tests/ -v`
`flutter test`
`flutter analyze`

- [ ] **Step 2: Deploy & verify live on connected phone**

Run:
`flutter build apk --debug`
`adb install -r build/app/outputs/flutter-apk/app-debug.apk`
`adb shell am start -n com.budgettracker/.MainActivity`

Verify live on device:
1. Tap "Budgets" tab.
2. Tap "Edit" on Utilities & Bills -> `SubBudgetAllocationDialog` opens.
3. Enter sub-allocations (Rent: 3000, Electricity: 150, Internet: 250, Mobile: 100, Water: 50).
4. Watch header auto-sum update in real time to `SAR 3,550.00`.
5. Tap Save -> card updates with parent sum `SAR 3,550.00`.
6. Tap card -> opens Breakdown Sheet showing `Housing Rent: SAR 3,000 / SAR 3,000 (100%)`.

- [ ] **Step 3: Commit and push**

```bash
git push origin main
```
