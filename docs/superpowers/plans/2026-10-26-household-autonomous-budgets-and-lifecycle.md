# Household Autonomous Budgets, Sub-Budgets & Category Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide each household with 100% autonomous control over their budget categories and sub-categories (with preloaded Saudi starters) while protecting historical reports through a two-track category lifecycle ("Rename Only" vs "Replace & Archive Old").

**Architecture:** Database migration introduces household-scoped ownership and a master template table with an atomic category replacement RPC. The Python FastAPI AI service adapts merchant matching to query dynamic household categories rather than static global codes. The Flutter client implements a transaction-aware lifecycle dialog and unconstrained sub-budget CRUD.

**Tech Stack:** PostgreSQL (Supabase RLS, Stored Procedures), Python 3.11 (FastAPI, Pytest), Flutter 3.29 (Dart, Riverpod/Provider, ThreeD UI, AppLocalizations).

**Spec:** [`docs/superpowers/specs/2026-10-26-household-autonomous-budgets-and-lifecycle-design.md`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-26-household-autonomous-budgets-and-lifecycle-design.md)

## Global Constraints

- Never mutate or delete transaction records during category edits; preserve historical ledger immutability.
- Strict trilingual RTL/LTR support (Arabic primary, English, Urdu) via `AppLocalizations`; zero hardcoded strings.
- Zero `flutter analyze` issues and 100% green test suites (`pytest` and `flutter test`).
- Work strictly on branch `feat/ai-chat-guardrails-and-setup-tutor`.

---

### Task 1: Database Migration: Master Templates, Household Sub-Categories & Replacement RPC

**Files:**
- Create: `supabase/migrations/20261026000000_household_autonomous_taxonomy.sql`
- Test: `supabase/tests/test_household_taxonomy.py`

**Interfaces:**
- Produces:
  - Table: `public.cost_control_templates (code, default_name_en, default_name_ar, icon_key, keywords)`
  - Column: `public.cost_control_sub_categories.household_id UUID REFERENCES public.households(id)`
  - RPC: `public.replace_household_category(p_household_id UUID, p_old_code VARCHAR, p_new_name VARCHAR, p_new_code VARCHAR, p_cycle_key VARCHAR) -> JSONB`
  - Function: `public.seed_household_default_taxonomy(p_household_id UUID) -> VOID`

- [ ] **Step 1: Write the failing test for taxonomy replacement RPC and household sub-categories**

```python
# supabase/tests/test_household_taxonomy.py
import pytest

def test_replace_household_category_archives_old_and_creates_new(db):
    hh_id = db.create_household("Autonomous HH")
    # Old category with existing transaction
    db.seed_category(hh_id, "OPEX-GROCERY", "Groceries")
    db.insert_transaction(hh_id, "OPEX-GROCERY", 150.0, "Panda")
    
    # Execute RPC
    res = db.rpc("replace_household_category", {
        "p_household_id": hh_id,
        "p_old_code": "OPEX-GROCERY",
        "p_new_name": "Electronics",
        "p_new_code": "CUSTOM-ELEC",
        "p_cycle_key": "2026-10"
    })
    
    assert res["status"] == "success"
    # Old category must be inactive in settings
    setting = db.get_category_setting(hh_id, "OPEX-GROCERY")
    assert setting["is_active"] is False
    # New category must exist and be active
    new_cat = db.get_category(hh_id, "CUSTOM-ELEC")
    assert new_cat["category"] == "Electronics"
    # Past transaction must still point to OPEX-GROCERY
    txn = db.get_transaction(hh_id)
    assert txn["category_code"] == "OPEX-GROCERY"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest supabase/tests/test_household_taxonomy.py -v`
Expected: FAIL (RPC `replace_household_category` does not exist).

- [ ] **Step 3: Write the database migration SQL**

```sql
-- supabase/migrations/20261026000000_household_autonomous_taxonomy.sql

-- 1. Master template table for new households
CREATE TABLE IF NOT EXISTS public.cost_control_templates (
  code VARCHAR(60) PRIMARY KEY,
  default_name_en VARCHAR(100) NOT NULL,
  default_name_ar VARCHAR(100) NOT NULL,
  icon_key VARCHAR(50),
  keywords TEXT[] DEFAULT '{}'::TEXT[]
);

INSERT INTO public.cost_control_templates (code, default_name_en, default_name_ar, icon_key, keywords)
VALUES
  ('OPEX-FUEL', 'Fuel & Transportation', 'الوقود والمواصلات', 'car', ARRAY['sasco', 'adrees', 'petrol', 'fuel', 'uber', 'bolt']),
  ('OPEX-GROCERY', 'Groceries & Food', 'البقالة والمقاضي', 'shopping_basket', ARRAY['panda', 'othaim', 'lulu', 'danube', 'tamimi']),
  ('OPEX-UTILITIES', 'Utilities & Bills', 'الفواتير والخدمات', 'bolt', ARRAY['sec', 'electricity', 'stc', 'mobily', 'water']),
  ('OPEX-HOUSING', 'Housing & Rent', 'السكن والإيجار', 'home', ARRAY['rent', 'building', 'maintenance']),
  ('OPEX-DINING', 'Dining & Cafes', 'المطاعم والكافيهات', 'coffee', ARRAY['mcdonalds', 'albaik', 'starbucks', 'barns']),
  ('OPEX-SHOPPING', 'Shopping & Personal', 'التسوق والمستلزمات', 'shopping_bag', ARRAY['jarir', 'noon', 'amazon', 'extra']),
  ('OPEX-HEALTH', 'Healthcare & Pharmacy', 'الصحة والصيدلية', 'health', ARRAY['nahdi', 'dawaa', 'hospital', 'clinic'])
ON CONFLICT (code) DO NOTHING;

-- 2. Add household_id to cost_control_sub_categories
ALTER TABLE public.cost_control_sub_categories
  ADD COLUMN IF NOT EXISTS household_id UUID REFERENCES public.households(id) ON DELETE CASCADE;

-- 3. RLS update for cost_control_sub_categories
DROP POLICY IF EXISTS cost_control_sub_categories_admin_all ON public.cost_control_sub_categories;
CREATE POLICY cost_control_sub_categories_admin_all ON public.cost_control_sub_categories
  FOR ALL USING (
    household_id IS NULL OR household_id IN (
      SELECT household_id FROM public.household_members WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    household_id IN (
      SELECT household_id FROM public.household_members WHERE user_id = auth.uid() AND role IN ('admin', 'co_admin')
    )
  );

-- 4. Category Lifecycle Replacement RPC
CREATE OR REPLACE FUNCTION public.replace_household_category(
  p_household_id UUID,
  p_old_code VARCHAR,
  p_new_name VARCHAR,
  p_new_code VARCHAR,
  p_cycle_key VARCHAR
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_allocated NUMERIC(12, 2) := 0.0;
BEGIN
  -- 1. Fetch current allocated amount of the old budget envelope
  SELECT allocated_amount INTO v_allocated
  FROM public.budgets
  WHERE household_id = p_household_id
    AND category_code = p_old_code
    AND (cycle_key = p_cycle_key OR cycle_key = substring(p_cycle_key from 1 for 7))
  LIMIT 1;

  IF v_allocated IS NULL THEN
    v_allocated := 0.0;
  END IF;

  -- 2. Deactivate old category in household_category_settings
  INSERT INTO public.household_category_settings (household_id, category_code, is_active, updated_at)
  VALUES (p_household_id, p_old_code, false, now())
  ON CONFLICT (household_id, category_code)
  DO UPDATE SET is_active = false, updated_at = now();

  -- 3. Deactivate old budget envelope
  UPDATE public.budgets
  SET is_active = false
  WHERE household_id = p_household_id
    AND category_code = p_old_code
    AND (cycle_key = p_cycle_key OR cycle_key = substring(p_cycle_key from 1 for 7));

  -- 4. Create new category in cost_control_codes
  INSERT INTO public.cost_control_codes (code, category, is_system, household_id)
  VALUES (p_new_code, p_new_name, false, p_household_id)
  ON CONFLICT (code) DO UPDATE SET category = p_new_name;

  -- 5. Activate new category in settings
  INSERT INTO public.household_category_settings (household_id, category_code, is_active, updated_at)
  VALUES (p_household_id, p_new_code, true, now())
  ON CONFLICT (household_id, category_code)
  DO UPDATE SET is_active = true, updated_at = now();

  -- 6. Create or update new budget envelope with transferred allocation
  INSERT INTO public.budgets (household_id, category_code, cycle_key, allocated_amount, spent_amount, is_active)
  VALUES (p_household_id, p_new_code, p_cycle_key, v_allocated, 0.0, true)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'status', 'success',
    'old_code', p_old_code,
    'new_code', p_new_code,
    'new_name', p_new_name,
    'allocated_transferred', v_allocated
  );
END;
$$;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest supabase/tests/test_household_taxonomy.py -v`
Expected: PASS.

- [ ] **Step 5: Commit database migration**

```bash
git add supabase/migrations/20261026000000_household_autonomous_taxonomy.sql supabase/tests/test_household_taxonomy.py
git commit -m "feat(db): add autonomous household taxonomy migration, master templates and replacement RPC"
```

---

### Task 2: Backend AI Microservice: Dynamic Household-Scoped Matching & Sub-Category Autonomy

**Files:**
- Modify: `ai_service/routes/budgets.py:430-495`
- Modify: `ai_service/receipt_scanner.py:930-970`
- Modify: `ai_service/chat_parser.py:980-1010`
- Test: `ai_service/tests/test_household_autonomous_budgets.py`

**Interfaces:**
- Consumes: RPC `replace_household_category` from Task 1.
- Produces:
  - Route: `POST /budgets/categories/replace` (Payload: `{household_id, old_code, new_name, cycle_key}`)
  - Route: `DELETE /budgets/sub-categories` (Scoped to household)
  - Function: `get_household_active_category_names(household_id: str) -> List[Dict]`

- [ ] **Step 1: Write failing tests for replacement endpoint and dynamic receipt matching**

```python
# ai_service/tests/test_household_autonomous_budgets.py
import pytest
from fastapi import status

def test_replace_category_endpoint(client, auth_headers):
    payload = {
        "household_id": "hh-1",
        "old_code": "OPEX-GROCERY",
        "new_name": "Electronics & Gadgets",
        "cycle_key": "2026-10"
    }
    resp = client.post("/budgets/categories/replace", json=payload, headers=auth_headers)
    assert resp.status_code == status.HTTP_200_OK
    data = resp.json()
    assert data["status"] == "success"
    assert data["new_name"] == "Electronics & Gadgets"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && pytest tests/test_household_autonomous_budgets.py -v`
Expected: FAIL (404 Not Found on `/budgets/categories/replace`).

- [ ] **Step 3: Implement replacement route and lift subcategory restrictions**

In `ai_service/routes/budgets.py`:
- Add `CategoryReplaceRequest` model.
- Add `@router.post("/budgets/categories/replace")`.
- In `rename_sub_category_endpoint` and `delete_sub_category_endpoint`, check if the sub-category belongs to `household_id` or is a custom sub-category, allowing household admins to freely rename/delete their sub-budgets.
- In `ai_service/receipt_scanner.py`, update `match_category` to match against the household's active category names and keywords.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ai_service && pytest tests/test_household_autonomous_budgets.py -v`
Expected: PASS.

- [ ] **Step 5: Commit AI microservice changes**

```bash
git add ai_service/routes/budgets.py ai_service/receipt_scanner.py ai_service/tests/test_household_autonomous_budgets.py
git commit -m "feat(ai): support category replacement lifecycle and household dynamic category matching"
```

---

### Task 3: Flutter Client: Category Lifecycle Replacement Dialog & Transaction History Check

**Files:**
- Create: `flutter_app/lib/widgets/categories/category_lifecycle_dialog.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/category_lifecycle_dialog_test.dart`

**Interfaces:**
- Consumes: `ApiService.instance.replaceCategory(householdId, oldCode, newName, cycleKey)`
- Produces: `CategoryLifecycleDialog.show(context, ...)`

- [ ] **Step 1: Write failing widget test for CategoryLifecycleDialog**

```dart
// flutter_app/test/widgets/category_lifecycle_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/categories/category_lifecycle_dialog.dart';

void main() {
  testWidgets('CategoryLifecycleDialog displays both Rename Only and Replace options when txns exist', (tester) async {
    CategoryLifecycleAction? selectedAction;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryLifecycleDialog(
          categoryCode: 'OPEX-GROCERY',
          currentName: 'Groceries',
          transactionCount: 15,
          onConfirm: (action, newName) {
            selectedAction = action;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Replace & Archive Old (Recommended)'), findsOneWidget);
    expect(find.text('Rename Only'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/category_lifecycle_dialog_test.dart`
Expected: FAIL (File does not exist).

- [ ] **Step 3: Implement CategoryLifecycleDialog and wire to BudgetManagementScreen**

1. Create `flutter_app/lib/widgets/categories/category_lifecycle_dialog.dart`:
   - Renders clean 3D dialog.
   - Shows past expense count pill (e.g. *"15 past expenses recorded"*).
   - Radio selection: `CategoryLifecycleAction.replaceAndArchive` (default) vs `CategoryLifecycleAction.renameOnly`.
   - Clear explanatory bullets.
2. In `flutter_app/lib/screens/home/budget_management_screen.dart`:
   - In `_renameCategory`:
     - Query transaction count:
       ```dart
       final txCount = await supabase
           .from('transactions')
           .select('id')
           .eq('household_id', staticData.householdId)
           .eq('category_code', categoryCode)
           .count();
       ```
     - If `txCount == 0`: prompt for new name and directly update `cost_control_codes`.
     - If `txCount > 0`: open `CategoryLifecycleDialog.show(...)`.
       - If user picks `renameOnly`: update `cost_control_codes.category`.
       - If user picks `replaceAndArchive`: call `ApiService.instance.replaceCategory(...)`.
3. Add trilingual localizations in `app_localizations.dart` across en, ar, ur.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/category_lifecycle_dialog_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit Flutter lifecycle dialog changes**

```bash
git add flutter_app/lib/widgets/categories/category_lifecycle_dialog.dart flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/services/ flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/category_lifecycle_dialog_test.dart
git commit -m "feat(ui): add category lifecycle dialog with transaction-aware replacement vs rename"
```

---

### Task 4: Flutter Client: Full Sub-Budget Management (Add, Rename, Delete)

**Files:**
- Modify: `flutter_app/lib/widgets/sub_budget_allocation_dialog.dart`
- Modify: `flutter_app/lib/screens/home/sub_budget_breakdown_sheet.dart`
- Test: `flutter_app/test/widgets/sub_budget_autonomous_test.dart`

**Interfaces:**
- Enables editing and deleting for all sub-categories owned by the household.

- [ ] **Step 1: Write failing widget test for sub-category editing and deletion**

```dart
// flutter_app/test/widgets/sub_budget_autonomous_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';

void main() {
  testWidgets('Allows editing sub-categories without system restriction locks', (tester) async {
    // Harness and assertions verifying edit icon is tappable and opens rename dialog
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/sub_budget_autonomous_test.dart`
Expected: FAIL.

- [ ] **Step 3: Update SubBudgetAllocationDialog**

- Update `SubBudgetAllocationDialog` to display edit and delete buttons for household sub-categories.
- Provide confirmation dialog on deleting a sub-category:
  - If sub-category has expenses: soft-deactivates or merges remaining allocation.
  - If sub-category has no expenses: removes sub-allocation entry.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/sub_budget_autonomous_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit sub-budget autonomy changes**

```bash
git add flutter_app/lib/widgets/sub_budget_allocation_dialog.dart flutter_app/lib/screens/home/sub_budget_breakdown_sheet.dart flutter_app/test/widgets/sub_budget_autonomous_test.dart
git commit -m "feat(ui): unlock full sub-budget management for household envelopes"
```

---

### Task 5: Full Regression, Trilingual Verification & Release APK Build

**Files:**
- All modified repository files.

- [ ] **Step 1: Run l10n guard test**

Run: `cd flutter_app && flutter test test/ui_l10n_guard_test.dart`
Expected: PASS (all 17 checks green across en, ar, ur).

- [ ] **Step 2: Run full flutter test suite**

Run: `cd flutter_app && flutter test`
Expected: PASS (960+ tests green).

- [ ] **Step 3: Run flutter analyzer**

Run: `cd flutter_app && flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 4: Run python AI service test suite**

Run: `cd ai_service && pytest -v`
Expected: PASS (all tests green).

- [ ] **Step 5: Compile Release APK**

Run: `cd flutter_app && flutter build apk --release`
Expected: Built `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 6: Final Commit**

```bash
git commit --allow-empty -m "chore(release): complete household autonomous budgets and category lifecycle verification"
```
