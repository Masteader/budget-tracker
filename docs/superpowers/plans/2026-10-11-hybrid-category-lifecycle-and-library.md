# Hybrid Category Lifecycle, Custom Categories & Category Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the hybrid category architecture where system categories are read-only, households can toggle categories active/inactive, create custom root categories, manage them in a dedicated Category Library, and resolve transactions incoming to inactive categories.

**Architecture:** 
- Database: Add `is_system` and `household_id` to `cost_control_codes`, create `household_category_settings` for per-household active/inactive preferences, and configure RLS.
- Backend: Update `ai_service` to expose category management APIs (`GET /households/{id}/categories`, `POST /households/{id}/categories/toggle`, `POST /households/{id}/categories/custom`) and update `chat_parser.py` / `receipt_scanner.py` to flag transactions matched to inactive categories with `is_category_inactive: true`.
- Mobile Client: Create Flutter `CategoryLibrarySheet` (Active vs Inactive/Available tabs + Custom Category creation) and `InactiveCategoryResolutionDialog` (Reactivate vs Reassign).

**Tech Stack:** PostgreSQL (Supabase), Python 3.11 (FastAPI, pytest), Dart 3 / Flutter 3.29 (Provider, Material 3).

**Spec:** `docs/superpowers/specs/2026-10-11-hybrid-category-lifecycle-and-library-design.md`

## Global Constraints
- System categories (`is_system = true`, `household_id = NULL`) cannot be renamed, edited, or deleted by any user.
- New developer categories added to `cost_control_codes` default to `is_active = false` for existing households and appear in their Category Library.
- Inactivating a category must preserve past transactions and cycle analytics, while zeroing its active allocation and returning funds to the household Savings Reserve.
- All code changes must have passing automated tests (pytest for Python, flutter test for Flutter).

---

### Task 1: Database Migration – Hybrid Categories & Settings Table

**Files:**
- Create: `supabase/migrations/20261011_hybrid_category_lifecycle.sql`

**Interfaces:**
- Produces:
  - Columns `is_system` and `household_id` on `public.cost_control_codes`.
  - Table `public.household_category_settings(id, household_id, category_code, is_active, created_at, updated_at)`.
  - RLS policies protecting system categories while allowing tenant-specific custom categories and settings.

- [ ] **Step 1: Write the migration SQL file**

```sql
-- Migration: 20261011_hybrid_category_lifecycle.sql
-- Description: Adds system flag and household_id to cost_control_codes,
--              creates household_category_settings for active/inactive state.

-- 1. Alter cost_control_codes
ALTER TABLE public.cost_control_codes
  ADD COLUMN IF NOT EXISTS household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false;

-- 2. Mark existing standard seeded codes as system
UPDATE public.cost_control_codes
SET is_system = true, household_id = NULL
WHERE code LIKE 'OPEX-%' OR code LIKE 'CAPEX-%';

-- 3. Create household_category_settings table
CREATE TABLE IF NOT EXISTS public.household_category_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  category_code VARCHAR(60) NOT NULL REFERENCES public.cost_control_codes(code) ON UPDATE CASCADE ON DELETE CASCADE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_household_category UNIQUE (household_id, category_code)
);

CREATE INDEX IF NOT EXISTS idx_hh_cat_settings_active 
  ON public.household_category_settings(household_id, is_active);

-- 4. Enable RLS
ALTER TABLE public.cost_control_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_category_settings ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for cost_control_codes
DROP POLICY IF EXISTS "cost_control_codes_select" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_select" ON public.cost_control_codes
  FOR SELECT USING (household_id IS NULL OR household_id = auth.uid());

DROP POLICY IF EXISTS "cost_control_codes_insert" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_insert" ON public.cost_control_codes
  FOR INSERT WITH CHECK (household_id IS NOT NULL AND is_system = false);

DROP POLICY IF EXISTS "cost_control_codes_update" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_update" ON public.cost_control_codes
  FOR UPDATE USING (household_id IS NOT NULL AND is_system = false);

DROP POLICY IF EXISTS "cost_control_codes_delete" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_delete" ON public.cost_control_codes
  FOR DELETE USING (household_id IS NOT NULL AND is_system = false);

-- 6. RLS Policies for household_category_settings
DROP POLICY IF EXISTS "household_category_settings_all" ON public.household_category_settings;
CREATE POLICY "household_category_settings_all" ON public.household_category_settings
  FOR ALL USING (household_id = auth.uid());
```

- [ ] **Step 2: Commit the migration**

```bash
git add supabase/migrations/20261011_hybrid_category_lifecycle.sql
git commit -m "db: add hybrid category lifecycle migration and RLS policies"
```

---

### Task 2: Backend Supabase Client & Category Endpoints

**Files:**
- Modify: `ai_service/supabase_client.py`
- Modify: `ai_service/salary_cycle.py`
- Modify: `ai_service/main.py`
- Test: `ai_service/tests/test_category_lifecycle.py`

**Interfaces:**
- Produces:
  - `GET /households/{id}/categories` -> returns `{"active": [...], "inactive": [...]}`
  - `POST /households/{id}/categories/toggle` -> body `{"category_code": str, "is_active": bool}`
  - `POST /households/{id}/categories/custom` -> body `{"code": str, "category": str, "keywords": list[str], "is_flexible": bool, "allocated_amount": float}`

- [ ] **Step 1: Write failing tests in `ai_service/tests/test_category_lifecycle.py`**

```python
import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_get_household_categories_split(monkeypatch):
    from salary_cycle import get_household_categories
    mock_sb = MagicMock()
    
    # Mock cost_control_codes
    mock_sb.table("cost_control_codes").select("*").execute.return_value.data = [
        {"code": "OPEX-DINING", "category": "Dining", "is_system": True, "household_id": None, "keywords": ["al baik"]},
        {"code": "OPEX-FUEL", "category": "Fuel", "is_system": True, "household_id": None, "keywords": ["petrol"]},
        {"code": "OPEX-PETS", "category": "Pets", "is_system": True, "household_id": None, "keywords": ["cat"]},
    ]
    
    # Mock settings: Dining active, Fuel inactive, Pets has no record (new developer category)
    mock_sb.table("household_category_settings").select("*").eq("household_id", "hh-123").execute.return_value.data = [
        {"category_code": "OPEX-DINING", "is_active": True},
        {"category_code": "OPEX-FUEL", "is_active": False},
    ]
    
    monkeypatch.setattr("salary_cycle.get_client", lambda: mock_sb)
    
    result = get_household_categories("hh-123")
    assert len(result["active"]) == 1
    assert result["active"][0]["code"] == "OPEX-DINING"
    
    inactive_codes = [c["code"] for c in result["inactive"]]
    assert "OPEX-FUEL" in inactive_codes
    assert "OPEX-PETS" in inactive_codes  # New developer category defaults to inactive

def test_toggle_category_activation(monkeypatch):
    from salary_cycle import toggle_category_status
    mock_sb = MagicMock()
    mock_sb.table("household_category_settings").upsert.return_value.execute.return_value.data = [{"status": "ok"}]
    monkeypatch.setattr("salary_cycle.get_client", lambda: mock_sb)
    
    res = toggle_category_status("hh-123", "OPEX-FUEL", True)
    assert res["status"] == "success"
    assert res["is_active"] is True
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PYTHONPATH="."
.\venv\Scripts\pytest ai_service/tests/test_category_lifecycle.py -v
```

- [ ] **Step 3: Implement category functions in `salary_cycle.py` & routes in `main.py`**

In `salary_cycle.py`:
```python
def get_household_categories(household_id: str) -> Dict[str, List[Dict[str, Any]]]:
    client = get_client()
    
    # 1. Fetch system codes + custom codes for this household
    all_codes_resp = client.table("cost_control_codes").select("*").execute()
    all_codes = all_codes_resp.data or []
    
    # Filter for global OR this household
    hh_codes = [
        c for c in all_codes 
        if c.get("household_id") is None or c.get("household_id") == household_id
    ]
    
    # 2. Fetch household settings
    settings_resp = (
        client.table("household_category_settings")
        .select("*")
        .eq("household_id", household_id)
        .execute()
    )
    settings_map = {s["category_code"]: s["is_active"] for s in (settings_resp.data or [])}
    
    active = []
    inactive = []
    
    for cat in hh_codes:
        code = cat["code"]
        # If in settings, use that; if not in settings, standard initial categories default to true,
        # but new ones default to false if not part of the initial core set
        if code in settings_map:
            is_active = settings_map[code]
        else:
            initial_core = {
                "OPEX-GROCERY", "OPEX-DINING", "OPEX-FUEL", "OPEX-UTILITIES",
                "OPEX-SHOPPING", "OPEX-HEALTH", "CAPEX-EDUCATION", "OPEX-MISC"
            }
            is_active = code in initial_core
        
        cat_info = {**cat, "is_active": is_active}
        if is_active:
            active.append(cat_info)
        else:
            inactive.append(cat_info)
            
    return {"active": active, "inactive": inactive}

def toggle_category_status(household_id: str, category_code: str, is_active: bool) -> Dict[str, Any]:
    client = get_client()
    now_iso = datetime.now(timezone.utc).isoformat()
    client.table("household_category_settings").upsert({
        "household_id": household_id,
        "category_code": category_code,
        "is_active": is_active,
        "updated_at": now_iso,
    }, on_conflict="household_id,category_code").execute()
    
    # If set to inactive, also mark corresponding budget is_active = false
    if not is_active:
        client.table("budgets").update({"is_active": False}).eq("household_id", household_id).eq("category_code", category_code).execute()
        
    return {"status": "success", "category_code": category_code, "is_active": is_active}
```

In `main.py`:
Expose:
- `GET /households/{household_id}/categories`
- `POST /households/{household_id}/categories/toggle`
- `POST /households/{household_id}/categories/custom`

- [ ] **Step 4: Run tests to verify they pass**

```powershell
$env:PYTHONPATH="."
.\venv\Scripts\pytest ai_service/tests/test_category_lifecycle.py -v
```

- [ ] **Step 5: Commit backend category management**

```bash
git add ai_service/salary_cycle.py ai_service/main.py ai_service/tests/test_category_lifecycle.py
git commit -m "feat(api): add household category retrieval and toggle endpoints"
```

---

### Task 3: AI Service Inactive Category Detection in Ingestion

**Files:**
- Modify: `ai_service/chat_parser.py`
- Modify: `ai_service/receipt_scanner.py`
- Test: `ai_service/tests/test_inactive_detection.py`

**Interfaces:**
- Produces:
  - `parse_chat_message` and `scan_receipt_image` return `"is_category_inactive": bool` when the matched category is inactive for the user's household.

- [ ] **Step 1: Write failing test in `ai_service/tests/test_inactive_detection.py`**

```python
import pytest
from unittest.mock import MagicMock
from chat_parser import check_category_active_status

def test_check_category_active_status():
    categories_state = {
        "active": [{"code": "OPEX-GROCERY"}],
        "inactive": [{"code": "OPEX-DINING"}]
    }
    
    assert check_category_active_status("OPEX-GROCERY", categories_state) is True
    assert check_category_active_status("OPEX-DINING", categories_state) is False
    assert check_category_active_status("UNKNOWN", categories_state) is True  # Unknown defaults to active handling
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PYTHONPATH="."
.\venv\Scripts\pytest ai_service/tests/test_inactive_detection.py -v
```

- [ ] **Step 3: Implement helper and metadata tagging in `chat_parser.py` and `receipt_scanner.py`**

```python
def check_category_active_status(category_code: str, categories_state: dict) -> bool:
    inactive_codes = {c["code"] for c in categories_state.get("inactive", [])}
    return category_code not in inactive_codes
```

In parse pipelines, when returning the transaction dictionary, enrich:
```python
is_active = check_category_active_status(parsed_code, household_categories)
result["is_category_inactive"] = not is_active
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
$env:PYTHONPATH="."
.\venv\Scripts\pytest ai_service/tests/test_inactive_detection.py -v
```

- [ ] **Step 5: Commit AI ingestion changes**

```bash
git add ai_service/chat_parser.py ai_service/receipt_scanner.py ai_service/tests/test_inactive_detection.py
git commit -m "feat(ai): flag incoming transactions matched to inactive categories"
```

---

### Task 4: Flutter Models & API Client Integration

**Files:**
- Modify: `flutter_app/lib/models/models.dart`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/services/category_api_test.dart`

**Interfaces:**
- Produces:
  - `CategoryItem` model with `code`, `name`, `isSystem`, `isActive`, `keywords`.
  - `fetchHouseholdCategories(String householdId)` -> returns `CategoryBundle(active: [...], inactive: [...])`.
  - `toggleCategoryStatus(String householdId, String code, bool isActive)`.
  - `createCustomCategory(String householdId, String code, String name, List<String> keywords, double budget)`.

- [ ] **Step 1: Write model and API test in Flutter**

```dart
// test/services/category_api_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('CategoryItem deserializes correctly', () {
    final json = {
      'code': 'OPEX-DINING',
      'category': 'Dining',
      'is_system': true,
      'is_active': false,
      'keywords': ['al baik', 'kfc'],
    };
    final item = CategoryItem.fromJson(json);
    expect(item.code, 'OPEX-DINING');
    expect(item.name, 'Dining');
    expect(item.isSystem, true);
    expect(item.isActive, false);
    expect(item.keywords.length, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
flutter test test/services/category_api_test.dart
```

- [ ] **Step 3: Implement `CategoryItem` in `models.dart` and methods in `BudgetApiClient` & `ApiService`**

In `models.dart`:
```dart
class CategoryItem {
  final String code;
  final String name;
  final bool isSystem;
  final bool isActive;
  final List<String> keywords;

  CategoryItem({
    required this.code,
    required this.name,
    this.isSystem = false,
    this.isActive = true,
    this.keywords = const [],
  });

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    return CategoryItem(
      code: json['code'] as String? ?? '',
      name: json['category'] as String? ?? json['name'] as String? ?? '',
      isSystem: json['is_system'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      keywords: (json['keywords'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}
```

In `BudgetApiClient`:
```dart
Future<Map<String, List<CategoryItem>>> getHouseholdCategories(String householdId) async {
  final res = await get('/households/$householdId/categories');
  final activeList = (res['active'] as List? ?? []).map((e) => CategoryItem.fromJson(e)).toList();
  final inactiveList = (res['inactive'] as List? ?? []).map((e) => CategoryItem.fromJson(e)).toList();
  return {'active': activeList, 'inactive': inactiveList};
}

Future<void> toggleCategory(String householdId, String code, bool isActive) async {
  await post('/households/$householdId/categories/toggle', {
    'category_code': code,
    'is_active': isActive,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

```powershell
flutter test test/services/category_api_test.dart
```

- [ ] **Step 5: Commit client models and API client**

```bash
git add flutter_app/lib/models/models.dart flutter_app/lib/services/api/budget_api_client.dart flutter_app/lib/services/api_service.dart flutter_app/test/services/category_api_test.dart
git commit -m "feat(flutter): add CategoryItem model and household category endpoints"
```

---

### Task 5: Category Library Bottom Sheet & Management UI

**Files:**
- Create: `flutter_app/lib/widgets/categories/category_library_sheet.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Test: `flutter_app/test/widgets/category_library_sheet_test.dart`

**Interfaces:**
- Produces:
  - `CategoryLibrarySheet`: Tabbed UI for Active vs Inactive categories.
  - Inactive categories list shows "✨ New Available Category" badge for unactivated system codes.
  - "Activate & Set Budget" dialog.
  - "Inactivate" confirmation dialog warning about Savings Reserve release.

- [ ] **Step 1: Write widget test for `CategoryLibrarySheet`**

```dart
// test/widgets/category_library_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/categories/category_library_sheet.dart';

void main() {
  testWidgets('Renders active and inactive categories in library', (tester) async {
    final active = [
      CategoryItem(code: 'OPEX-DINING', name: 'Dining', isActive: true, isSystem: true),
    ];
    final inactive = [
      CategoryItem(code: 'OPEX-PETS', name: 'Pets', isActive: false, isSystem: true),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryLibrarySheet(
          activeCategories: active,
          inactiveCategories: inactive,
          onToggle: (cat, active) {},
          onAddCustom: () {},
        ),
      ),
    ));

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Library (Inactive)'), findsOneWidget);
    expect(find.text('Dining'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
flutter test test/widgets/category_library_sheet_test.dart
```

- [ ] **Step 3: Implement `CategoryLibrarySheet`**

Create `flutter_app/lib/widgets/categories/category_library_sheet.dart` with:
- Top TabBar: `Active (count)` and `Library / Inactive (count)`.
- Active items: category name, chips, switch/button to Deactivate.
- Inactive items: category name, "Activate & Set Budget" button.
- "Add Custom Category" FAB or bottom button.
Integrate into `BudgetManagementScreen` with an action icon in the AppBar.

- [ ] **Step 4: Run test to verify it passes**

```powershell
flutter test test/widgets/category_library_sheet_test.dart
```

- [ ] **Step 5: Commit Category Library UI**

```bash
git add flutter_app/lib/widgets/categories/category_library_sheet.dart flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/test/widgets/category_library_sheet_test.dart
git commit -m "feat(ui): add CategoryLibrarySheet with active/inactive management"
```

---

### Task 6: Inactive Category Resolution Dialog

**Files:**
- Create: `flutter_app/lib/widgets/transactions/inactive_category_resolution_dialog.dart`
- Modify: `flutter_app/lib/screens/chat/chat_entry_screen.dart`
- Test: `flutter_app/test/widgets/inactive_category_resolution_dialog_test.dart`

**Interfaces:**
- Produces:
  - `InactiveCategoryResolutionDialog`: Modal presented when incoming transaction hits an inactive category.
  - Buttons: `Reactivate "[Category]"` or `File Under Another Category`.

- [ ] **Step 1: Write widget test for resolution dialog**

```dart
// test/widgets/inactive_category_resolution_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/transactions/inactive_category_resolution_dialog.dart';

void main() {
  testWidgets('Resolution dialog shows both choices', (tester) async {
    bool reactivateTapped = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InactiveCategoryResolutionDialog(
          categoryName: 'Dining',
          amount: 45.0,
          merchant: 'Al Baik',
          onReactivate: () => reactivateTapped = true,
          onChangeCategory: () {},
        ),
      ),
    ));

    expect(find.textContaining('Dining'), findsWidgets);
    expect(find.textContaining('Al Baik'), findsOneWidget);
    expect(find.text('Reactivate Category'), findsOneWidget);
    expect(find.text('File Under Other Category'), findsOneWidget);

    await tester.tap(find.text('Reactivate Category'));
    expect(reactivateTapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
flutter test test/widgets/inactive_category_resolution_dialog_test.dart
```

- [ ] **Step 3: Implement `InactiveCategoryResolutionDialog` & hook into ingestion**

Build `InactiveCategoryResolutionDialog`:
- Displays amount, merchant, and alert banner: *"This expense matched an inactive category."*
- Primary button: `Reactivate Category`.
- Outlined button: `File Under Other Category`.
Hook into `ChatEntryScreen` and receipt ingestion when `is_category_inactive == true`.

- [ ] **Step 4: Run test to verify it passes**

```powershell
flutter test test/widgets/inactive_category_resolution_dialog_test.dart
```

- [ ] **Step 5: Commit resolution dialog**

```bash
git add flutter_app/lib/widgets/transactions/inactive_category_resolution_dialog.dart flutter_app/lib/screens/chat/chat_entry_screen.dart flutter_app/test/widgets/inactive_category_resolution_dialog_test.dart
git commit -m "feat(ui): add InactiveCategoryResolutionDialog for transaction conflict handling"
```

---

### Task 7: Full System Verification & Regression Suite

**Files:**
- All tests in `ai_service/tests/` and `flutter_app/test/`

- [ ] **Step 1: Run full Python backend test suite**

```powershell
cd c:\Users\A\OneDrive\Python projects\budget-tracker\ai_service
$env:PYTHONPATH="."
.\venv\Scripts\pytest -v
```
Expected: All tests pass.

- [ ] **Step 2: Run full Flutter test suite**

```powershell
cd c:\Users\A\OneDrive\Python projects\budget-tracker\flutter_app
flutter test
```
Expected: All tests pass.

- [ ] **Step 3: Verify git status and commit final documentation update**

```bash
git status
```
