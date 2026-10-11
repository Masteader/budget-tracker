# Dependents & Hybrid Subcategories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 2D attribution with custom household dependents (children), dynamic LLM-driven subcategory classification, and interactive confirmation in chat and transaction edit sheets.

**Architecture:** Add `household_dependents` table with Supabase RLS; expand AI service with dynamic taxonomy and dependents injection; update settlement engine for child-attributed shared expenses; update Flutter `Transaction` model and UI components (`PendingExpenseConfirmationCard`, `EditTransactionSheet`, `HouseholdManagementCard`).

**Tech Stack:** PostgreSQL (Supabase RLS), Python (FastAPI, LiteLLM, Pytest), Flutter / Dart (Provider, Google Fonts).

**Spec:** docs/superpowers/specs/2026-10-11-dependents-and-hybrid-subcategories-design.md

## Global Constraints
- All backend routes must validate authentication and household boundaries.
- All Flutter changes must preserve dark fintech aesthetics (`#0D1117`, `#161B22`, `#00C896`, `#58A6FF`, `#BC8CFF`).
- English-only docstrings, UI labels accompanied by localization where appropriate.
- Never delete existing transactions or schema columns; maintain full backwards compatibility with legacy `spent_by`.

---

### Task 1: Supabase Database Migration for Dependents & Subcategory Keywords

**Files:**
- Create: `supabase/migrations/20261011_household_dependents_and_subcategories.sql`
- Test: `ai_service/tests/test_dependents_schema.py`

**Interfaces:**
- Produces: `household_dependents` table in PostgreSQL with columns `(id, household_id, name, avatar_icon, created_at)`.
- Updates: `cost_control_sub_categories` keywords with Saudi food, dining, and plural terms.

- [ ] **Step 1: Write the schema verification test**

Create `ai_service/tests/test_dependents_schema.py`:
```python
import pytest
from supabase_client import get_client

def test_household_dependents_schema_structure():
    """Verify household_dependents table can be queried and has expected columns."""
    client = get_client()
    res = client.table("household_dependents").select("id, household_id, name, avatar_icon, created_at").limit(0).execute()
    assert res.data is not None

def test_dining_keywords_expanded():
    """Verify restaurants_dinners subcategory keywords include shawarma, broasted, and plural forms."""
    client = get_client()
    res = client.table("cost_control_sub_categories").select("keywords").eq("parent_code", "OPEX-DINING").eq("sub_code", "restaurants_dinners").execute()
    assert len(res.data) > 0
    keywords = res.data[0]["keywords"] or []
    assert any("شاورما" in kw for kw in keywords)
    assert any("مطاعم" in kw for kw in keywords)
```

- [ ] **Step 2: Run test to verify it fails before migration**

Run: `pytest ai_service/tests/test_dependents_schema.py -v`
Expected: FAIL (relation `household_dependents` does not exist yet)

- [ ] **Step 3: Write the SQL migration**

Create `supabase/migrations/20261011_household_dependents_and_subcategories.sql`:
```sql
-- Migration: 20261011_household_dependents_and_subcategories.sql
-- Description: Creates household_dependents table with RLS and enriches subcategory keywords.

-- 1. Create household_dependents table
CREATE TABLE IF NOT EXISTS public.household_dependents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    avatar_icon TEXT DEFAULT 'child',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dependents_household ON public.household_dependents(household_id);

-- 2. Enable RLS
ALTER TABLE public.household_dependents ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
DROP POLICY IF EXISTS "dependents_select_household" ON public.household_dependents;
CREATE POLICY "dependents_select_household" ON public.household_dependents
    FOR SELECT USING (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "dependents_insert_household" ON public.household_dependents;
CREATE POLICY "dependents_insert_household" ON public.household_dependents
    FOR INSERT WITH CHECK (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "dependents_update_household" ON public.household_dependents;
CREATE POLICY "dependents_update_household" ON public.household_dependents
    FOR UPDATE USING (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "dependents_delete_household" ON public.household_dependents;
CREATE POLICY "dependents_delete_household" ON public.household_dependents
    FOR DELETE USING (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

-- 4. Update cost_control_sub_categories dining keywords with Saudi vernacular & plurals
UPDATE public.cost_control_sub_categories
SET keywords = ARRAY['restaurant', 'dinner', 'lunch', 'burger', 'مطعم', 'مطاعم', 'شاورما', 'بروستد', 'وجبة', 'غداء', 'عشاء', 'سندويش', 'مشويات', 'فطور', 'كبسة', 'بخاري', 'برجر', 'بيت الشاورما', 'البيك']
WHERE parent_code = 'OPEX-DINING' AND sub_code = 'restaurants_dinners';

UPDATE public.cost_control_sub_categories
SET keywords = ARRAY['coffee', 'cafe', 'starbucks', 'dunkin', 'قهوة', 'كافيه', 'مخبز', 'حلا', 'كيك', 'كرواسون', 'شاهي', 'شاي', 'دونات', 'لاتيه', 'سبانش']
WHERE parent_code = 'OPEX-DINING' AND sub_code = 'coffee_bakeries';
```

- [ ] **Step 4: Apply migration and run verification test**

Run: Apply via Supabase client / migration script and run:
`pytest ai_service/tests/test_dependents_schema.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261011_household_dependents_and_subcategories.sql ai_service/tests/test_dependents_schema.py
git commit -m "feat(db): add household_dependents table and expand dining subcategory keywords"
```

---

### Task 2: Backend Dependents Management API & Fair-Share Settlement Engine Updates

**Files:**
- Create: `ai_service/dependents_service.py`
- Modify: `ai_service/main.py:650-710`
- Modify: `ai_service/settlement_engine.py:70-135`
- Test: `ai_service/tests/test_dependents_api.py`
- Test: `ai_service/tests/test_settlement_dependents.py`

**Interfaces:**
- Consumes: `household_dependents` table from Task 1.
- Produces:
  - `GET /households/{household_id}/dependents` -> `List[{"id": str, "name": str, "avatar_icon": str}]`
  - `POST /households/{household_id}/dependents` -> `{"status": "success", "dependent": Dict}`
  - `DELETE /households/{household_id}/dependents/{dependent_id}` -> `{"status": "success"}`
  - `calculate_partner_settlement` treats dependent beneficiaries as shared family expenses.

- [ ] **Step 1: Write failing tests for Dependents API & Settlement Engine**

Create `ai_service/tests/test_dependents_api.py`:
```python
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_dependents_crud_endpoints():
    household_id = "test-household-001"
    # Create dependent
    post_res = client.post(f"/households/{household_id}/dependents", json={"name": "Sarah", "avatar_icon": "child"})
    assert post_res.status_code == 200
    data = post_res.json()
    dep_id = data["dependent"]["id"]
    assert data["dependent"]["name"] == "Sarah"

    # List dependents
    get_res = client.get(f"/households/{household_id}/dependents")
    assert get_res.status_code == 200
    deps = get_res.json()["dependents"]
    assert any(d["name"] == "Sarah" for d in deps)

    # Delete dependent
    del_res = client.delete(f"/households/{household_id}/dependents/{dep_id}")
    assert del_res.status_code == 200
```

Create `ai_service/tests/test_settlement_dependents.py`:
```python
import pytest
from settlement_engine import calculate_partner_settlement

def test_dependent_beneficiary_treated_as_shared_family_expense(monkeypatch):
    household_id = "test-household-001"
    mock_txs = [
        {
            "id": "tx-child-1",
            "amount": 200.0,
            "category_code": "OPEX-SHOPPING",
            "paid_by": "me",
            "beneficiary": "Sarah",  # Child expense
            "timestamp": "2026-10-10T12:00:00Z",
            "raw_sms": "Clothes for Sarah"
        }
    ]
    # Verify partner owes their fair share (50% = 100 SAR)
    res = calculate_partner_settlement(household_id, mock_transactions=mock_txs, split_ratio=0.50)
    assert res["shared_paid_by_me"] == 200.0
    assert res["partner_owes_me"] == 100.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest ai_service/tests/test_dependents_api.py ai_service/tests/test_settlement_dependents.py -v`
Expected: FAIL

- [ ] **Step 3: Implement `dependents_service.py` and mount FastAPI endpoints**

Create `ai_service/dependents_service.py`:
```python
from typing import List, Dict, Any, Optional
from supabase_client import get_client

def get_household_dependents(household_id: str) -> List[Dict[str, Any]]:
    client = get_client()
    res = client.table("household_dependents").select("*").eq("household_id", household_id).order("created_at").execute()
    return res.data or []

def create_household_dependent(household_id: str, name: str, avatar_icon: Optional[str] = "child") -> Dict[str, Any]:
    client = get_client()
    payload = {
        "household_id": household_id,
        "name": name.strip(),
        "avatar_icon": avatar_icon or "child",
    }
    res = client.table("household_dependents").insert(payload).execute()
    return res.data[0] if res.data else payload

def delete_household_dependent(household_id: str, dependent_id: str) -> bool:
    client = get_client()
    res = client.table("household_dependents").delete().eq("household_id", household_id).eq("id", dependent_id).execute()
    return True
```

In `ai_service/main.py`, mount:
```python
@app.get("/households/{household_id}/dependents", tags=["dependents"])
async def list_dependents(household_id: str):
    from dependents_service import get_household_dependents
    deps = await asyncio.to_thread(get_household_dependents, household_id)
    return {"status": "success", "dependents": deps}

@app.post("/households/{household_id}/dependents", tags=["dependents"])
async def add_dependent(household_id: str, req: DependentCreateRequest):
    from dependents_service import create_household_dependent
    dep = await asyncio.to_thread(create_household_dependent, household_id, req.name, req.avatar_icon)
    return {"status": "success", "dependent": dep}

@app.delete("/households/{household_id}/dependents/{dependent_id}", tags=["dependents"])
async def remove_dependent(household_id: str, dependent_id: str):
    from dependents_service import delete_household_dependent
    await asyncio.to_thread(delete_household_dependent, household_id, dependent_id)
    return {"status": "success", "message": "Dependent removed."}
```

In `ai_service/settlement_engine.py`:
Update settlement logic so that if `beneficiary not in ("me", "partner", "both")` (e.g., a child name), it is classified as a shared family expense (`shared_txs`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest ai_service/tests/test_dependents_api.py ai_service/tests/test_settlement_dependents.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/dependents_service.py ai_service/main.py ai_service/settlement_engine.py ai_service/tests/
git commit -m "feat(api): add household dependents endpoints and update settlement engine"
```

---

### Task 3: Dynamic LLM Subcategory Classification & 2D Attribution in AI Chat Parser

**Files:**
- Modify: `ai_service/chat_parser.py:57-118, 440-540`
- Modify: `ai_service/supabase_client.py:255-285`
- Test: `ai_service/tests/test_chat_parser_subcategories.py`

**Interfaces:**
- Consumes: Active household categories, sub-categories, and dependents from Task 2.
- Produces:
  - `ParsedChatExpense` schema with `sub_category`, `paid_by`, `beneficiary`, item-level `sub_category`.
  - `handle_chat_expense` preview payload returns `sub_category`, `available_categories`, `available_sub_categories`, `paid_by`, `beneficiary`, and `dependents`.

- [ ] **Step 1: Write failing test for AI chat subcategory & attribution extraction**

Create `ai_service/tests/test_chat_parser_subcategories.py`:
```python
import pytest
from chat_parser import handle_chat_expense

def test_shawarma_chat_expense_preview_returns_dining_sub_category(monkeypatch):
    """Verify Beit Al Shawarma generates OPEX-DINING with restaurants_dinners subcategory in preview."""
    msg = "ضيف سندويش شاورما 10 ريال من بيت الشاورما تحت بند المطاعم"
    res = handle_chat_expense(
        message=msg,
        household_id="test-household-001",
        preview_only=True
    )
    assert res["status"] == "pending_confirmation"
    assert res["category_code"] == "OPEX-DINING"
    assert res["sub_category"] == "restaurants_dinners"
    assert "available_sub_categories" in res
    assert res["paid_by"] == "me"
    assert len(res["items"]) >= 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest ai_service/tests/test_chat_parser_subcategories.py -v`
Expected: FAIL (sub_category is None / missing from preview payload)

- [ ] **Step 3: Implement dynamic taxonomy injection and schema updates in `chat_parser.py`**

In `ai_service/chat_parser.py`:
1. Update `SYSTEM_PROMPT` to instruct LLM:
   - Identify `category_code` and `sub_category` from the available taxonomy.
   - For line items, assign item-level `sub_category`.
   - Identify `paid_by` (`me` | `partner`) and `beneficiary` (`me` | `partner` | `both` | dependent name).
2. In `handle_chat_expense`:
   - Fetch active household categories and subcategories:
     ```python
     from salary_cycle import get_household_categories, get_sub_categories_for_parent
     from dependents_service import get_household_dependents
     ```
   - In `preview_only: true`, include:
     ```python
     "sub_category": detected_sub_category,
     "available_sub_categories": sub_cats_for_category,
     "paid_by": parsed.paid_by,
     "beneficiary": parsed.beneficiary,
     "dependents": [d["name"] for d in dependents],
     ```
3. Update `insert_transaction` in `supabase_client.py` to persist `sub_category`, `paid_by`, and `beneficiary`.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest ai_service/tests/test_chat_parser_subcategories.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/chat_parser.py ai_service/supabase_client.py ai_service/tests/test_chat_parser_subcategories.py
git commit -m "feat(ai): add dynamic subcategory & 2D attribution extraction to chat parser"
```

---

### Task 4: Flutter Data Models & API Client Updates

**Files:**
- Modify: `flutter_app/lib/models/models.dart:4-50, 480-510`
- Modify: `flutter_app/lib/services/api/household_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/models/models_dependents_test.dart`

**Interfaces:**
- Produces:
  - `Transaction.subCategory` field in Dart.
  - `HouseholdDependent` model (`id`, `householdId`, `name`, `avatarIcon`, `createdAt`).
  - `ApiService.getDependents`, `createDependent`, `deleteDependent`.

- [ ] **Step 1: Write failing Dart unit test for models**

Create `flutter_app/test/models/models_dependents_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('Transaction model parses subCategory and beneficiary correctly', () {
    final map = {
      'id': 'tx-123',
      'household_id': 'hh-001',
      'amount': 25.0,
      'currency': 'SAR',
      'merchant': 'Al Baik',
      'category_code': 'OPEX-DINING',
      'sub_category': 'restaurants_dinners',
      'timestamp': '2026-10-11T12:00:00Z',
      'created_at': '2026-10-11T12:00:00Z',
      'paid_by': 'me',
      'beneficiary': 'Sarah',
    };
    final tx = Transaction.fromMap(map);
    expect(tx.subCategory, equals('restaurants_dinners'));
    expect(tx.paidBy, equals('me'));
    expect(tx.beneficiary, equals('Sarah'));
  });

  test('HouseholdDependent parses from JSON correctly', () {
    final map = {
      'id': 'dep-001',
      'household_id': 'hh-001',
      'name': 'Sarah',
      'avatar_icon': 'child',
      'created_at': '2026-10-11T12:00:00Z',
    };
    final dep = HouseholdDependent.fromMap(map);
    expect(dep.name, equals('Sarah'));
    expect(dep.avatarIcon, equals('child'));
  });
}
```

- [ ] **Step 2: Run Dart test to verify failure**

Run: `flutter test test/models/models_dependents_test.dart`
Expected: FAIL (`subCategory` and `HouseholdDependent` not defined)

- [ ] **Step 3: Implement `subCategory` in `Transaction` & `HouseholdDependent` model**

In `flutter_app/lib/models/models.dart`:
- Add `final String? subCategory;` to `Transaction`.
- Update constructor and `Transaction.fromMap` to read `map['sub_category']`.
- Add `HouseholdDependent` class with `fromMap` and `toMap`.

In `flutter_app/lib/services/api/household_api_client.dart` & `api_service.dart`:
- Add methods for `getDependents`, `createDependent`, `deleteDependent`.

- [ ] **Step 4: Run Dart test to verify it passes**

Run: `flutter test test/models/models_dependents_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/models.dart flutter_app/lib/services/ flutter_app/test/models/
git commit -m "feat(mobile): add subCategory to Transaction and HouseholdDependent model"
```

---

### Task 5: Household Management Card: Add Dependents & Children UI

**Files:**
- Modify: `flutter_app/lib/widgets/settings/household_management_card.dart`
- Test: `flutter_app/test/widgets/household_management_card_test.dart`

**Interfaces:**
- Consumes: `HouseholdDependent` model and `ApiService` from Task 4.
- Produces: Family Dependents & Children management UI section inside household settings.

- [ ] **Step 1: Write widget test for Dependents section in `HouseholdManagementCard`**

Update `flutter_app/test/widgets/household_management_card_test.dart`:
```dart
testWidgets('renders Family Dependents & Children section and displays child chip', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HouseholdManagementCard(
          householdName: 'My Household',
          inviteCode: 'ABC12345',
          userRole: 'admin',
          members: const [],
          dependents: const [
            HouseholdDependent(id: '1', householdId: 'h1', name: 'Sarah', avatarIcon: 'child', createdAt: null),
          ],
          onCopyInviteCode: () {},
          onLeaveHousehold: () {},
          onSwitchHousehold: () {},
          onCreateHousehold: () {},
          onAddDependent: () {},
          onRemoveDependent: (_) {},
        ),
      ),
    ),
  );
  expect(find.text('Family Dependents & Children'), findsOneWidget);
  expect(find.text('Sarah'), findsOneWidget);
  expect(find.text('+ Add Child / Dependent'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test to verify failure**

Run: `flutter test test/widgets/household_management_card_test.dart`
Expected: FAIL

- [ ] **Step 3: Update `HouseholdManagementCard`**

In `flutter_app/lib/widgets/settings/household_management_card.dart`:
- Add `dependents`, `onAddDependent`, `onRemoveDependent` parameters.
- Add "Family Dependents & Children" section with:
  - Header with icon `Icons.child_care_rounded`.
  - Wrap of chips showing dependents with delete icon for admin.
  - "+ Add Child / Dependent" button triggering a neat modal dialog for entering child name.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/household_management_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/settings/household_management_card.dart flutter_app/test/widgets/household_management_card_test.dart
git commit -m "feat(mobile): add dependents management to HouseholdManagementCard"
```

---

### Task 6: Interactive Chat Preview Card: Category, Subcategory, & 2D Attribution

**Files:**
- Modify: `flutter_app/lib/widgets/chat/pending_expense_confirmation_card.dart`
- Modify: `flutter_app/lib/widgets/chat/chat_message_bubble.dart`
- Modify: `flutter_app/lib/screens/chat/chat_entry_screen.dart`
- Test: `flutter_app/test/widgets/pending_expense_confirmation_card_test.dart`

**Interfaces:**
- Consumes: Preview payload containing `category_code`, `sub_category`, `available_sub_categories`, `dependents` from Task 3.
- Produces: Confirmation card allowing editing Category, Subcategory, Who Paid, and For Whom (including child chips) before saving.

- [ ] **Step 1: Write widget test for `PendingExpenseConfirmationCard`**

Create `flutter_app/test/widgets/pending_expense_confirmation_card_test.dart`:
```dart
testWidgets('renders category, subcategory dropdown and for whom child chips', (tester) async {
  final pendingData = {
    'merchant': 'Beit Al Shawarma',
    'amount': 10.0,
    'category_code': 'OPEX-DINING',
    'sub_category': 'restaurants_dinners',
    'paid_by': 'me',
    'beneficiary': 'Sarah',
    'available_sub_categories': [
      {'sub_code': 'restaurants_dinners', 'name_en': 'Restaurants & Meals', 'name_ar': 'المطاعم والوجبات'},
      {'sub_code': 'coffee_bakeries', 'name_en': 'Coffee & Bakeries', 'name_ar': 'القهوة والمخابز'},
    ],
    'dependents': ['Sarah', 'Fahad'],
  };

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PendingExpenseConfirmationCard(
          pendingData: pendingData,
          onConfirm: (store, cat, subCat, paidBy, beneficiary) {},
          onCancel: () {},
        ),
      ),
    ),
  );

  expect(find.text('Beit Al Shawarma'), findsOneWidget);
  expect(find.text('Restaurants & Meals'), findsOneWidget);
  expect(find.text('Sarah'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test to verify failure**

Run: `flutter test test/widgets/pending_expense_confirmation_card_test.dart`
Expected: FAIL

- [ ] **Step 3: Update `PendingExpenseConfirmationCard` and wiring**

In `flutter_app/lib/widgets/chat/pending_expense_confirmation_card.dart`:
- Add Category & cascading Sub-category dropdown selectors.
- Add "WHO PAID?" segmented button (`Me` / `Partner`).
- Add "FOR WHOM?" chip list (`Me` / `Partner` / `Both` / Child chips).
- Render line items with their item-level sub-category badges.
- Expand `onConfirm` callback to pass `(store, categoryCode, subCategory, paidBy, beneficiary)`.
In `chat_message_bubble.dart` and `chat_entry_screen.dart`:
- Update handler `_confirmPendingExpense` to send all confirmed fields to backend.

- [ ] **Step 4: Run widget test to verify it passes**

Run: `flutter test test/widgets/pending_expense_confirmation_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/chat/ flutter_app/lib/screens/chat/ flutter_app/test/widgets/pending_expense_confirmation_card_test.dart
git commit -m "feat(mobile): add category, subcategory, and 2D attribution to chat preview card"
```

---

### Task 7: Edit Transaction Sheet: Subcategory Dropdown & Children Attribution

**Files:**
- Modify: `flutter_app/lib/screens/home/edit_transaction_sheet.dart`
- Test: `flutter_app/test/widgets/edit_transaction_sheet_test.dart`

**Interfaces:**
- Consumes: `Transaction.subCategory`, `HouseholdDependent` list.
- Produces: Full editing of main category, subcategory, and child beneficiaries in the edit sheet.

- [ ] **Step 1: Write widget test for `EditTransactionSheet`**

Create `flutter_app/test/widgets/edit_transaction_sheet_test.dart`:
```dart
testWidgets('EditTransactionSheet displays subcategory dropdown and child beneficiary chips', (tester) async {
  final tx = Transaction(
    id: 'tx-1',
    householdId: 'h1',
    amount: 50.0,
    currency: 'SAR',
    merchant: 'Al Baik',
    categoryCode: 'OPEX-DINING',
    subCategory: 'restaurants_dinners',
    timestamp: DateTime.now(),
    isReallocated: false,
    createdAt: DateTime.now(),
    paidBy: 'me',
    beneficiary: 'Sarah',
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EditTransactionSheet(transaction: tx, householdDependents: const ['Sarah', 'Fahad']),
      ),
    ),
  );

  expect(find.text('Sub-Category'), findsOneWidget);
  expect(find.text('Sarah'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/widgets/edit_transaction_sheet_test.dart`
Expected: FAIL

- [ ] **Step 3: Update `EditTransactionSheet`**

In `flutter_app/lib/screens/home/edit_transaction_sheet.dart`:
- Add `_selectedSubCategory` state variable.
- Load sub-categories for `_selectedCategory` dynamically using `ApiService.instance.getSubCategories`.
- Add Sub-Category `DropdownButtonFormField` directly underneath the Category dropdown.
- In "FOR WHOM?", add dynamic chips for household dependents.
- In `_saveChanges()`, save `sub_category`, `paid_by`, and `beneficiary`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/edit_transaction_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/home/edit_transaction_sheet.dart flutter_app/test/widgets/edit_transaction_sheet_test.dart
git commit -m "feat(mobile): add subcategory dropdown and child attribution to EditTransactionSheet"
```

---

### Task 8: End-to-End Verification & Integration Test

**Files:**
- Test: All backend tests (`ai_service/tests/`)
- Test: All Flutter tests (`flutter_app/test/`)

- [ ] **Step 1: Run all Python backend tests**

Run: `pytest ai_service/tests/ -v`
Expected: ALL PASS

- [ ] **Step 2: Run all Flutter unit & widget tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 3: Run Flutter static analyzer**

Run: `flutter analyze`
Expected: 0 errors / clean analyzer

- [ ] **Step 4: Final verification commit**

```bash
git commit --allow-empty -m "chore(test): verify all unit and integration tests pass across backend and mobile"
```
