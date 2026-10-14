# Family Nafaqah Reimbursement & Multi-Roommate Settlement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the culturally accurate Islamic Family *Nafaqah* reimbursement flow (where husband reimburses wife for household advances) alongside a Splitwise-grade multi-roommate pairwise settlement engine with debt simplification, receipt line-item tagging, and role-aware household invitations.

**Architecture:** 
1. Database schema updates in Supabase establish `financial_role` on users, a `household_invites` table, relationship/allowance fields on dependents, and line-item/settlement metadata on transactions.
2. The FastAPI `settlement_engine.py` is upgraded to calculate both Family Nafaqah (husband owes wife 100% for household advances, wife owes husband 0 SAR) and Multi-Party Pairwise Roommate Ledgers with debt simplification.
3. Flutter mobile app introduces dedicated dashboard widgets: `FamilyReimbursementCard` (with full/partial STC Pay reimbursement actions) and `MultiRoommateSettlementCard` (pairwise matrix with debt simplification), tied together by role-aware invite dialogs and line-item receipt tagging.

**Tech Stack:** Flutter (Dart 3.x, Provider), Python (FastAPI 0.115, Pydantic v2, Pytest), Supabase (PostgreSQL, RLS).

**Spec:** [`docs/superpowers/specs/2026-10-15-family-nafaqah-and-multi-roommate-settlement-design.md`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-15-family-nafaqah-and-multi-roommate-settlement-design.md)

## Global Constraints
- Zero compiler errors, zero runtime warnings, and **0 analyzer issues** (`flutter analyze` clean).
- Full trilingual support: English, Arabic (`ar`), and Urdu (`ur`) in `app_localizations.dart`.
- TDD required: tests written and verified before implementation code.
- Backward compatibility: existing transactions without line-items or new roles continue to operate seamlessly.

---

### Task 1: Supabase Database Migration & Schema Extensions

**Files:**
- Create: `supabase/migrations/20261015_family_nafaqah_and_multi_roommate_settlement.sql`
- Test: `ai_service/tests/test_migration_schema.py`

**Interfaces:**
- Produces: `financial_role` column on `users`, `household_invites` table with RLS, `relationship` and `monthly_allowance` on `household_dependents`, and `beneficiary_type`, `beneficiary_id`, `is_settlement`, `settlement_target_id`, `line_items` on `transactions`.

- [ ] **Step 1: Write migration SQL file**

```sql
-- Migration: 20261015_family_nafaqah_and_multi_roommate_settlement.sql
-- Description: Extends users, transactions, dependents, and creates household_invites for role-aware settlements.

-- 1. Users financial_role
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS financial_role TEXT DEFAULT 'provider';

-- 2. Household Invites Table
CREATE TABLE IF NOT EXISTS public.household_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    invite_code VARCHAR(8) UNIQUE NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'peer',
    created_by UUID REFERENCES public.users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    used_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invites_code ON public.household_invites(invite_code);

-- 3. Household Dependents extensions
ALTER TABLE public.household_dependents
ADD COLUMN IF NOT EXISTS relationship TEXT DEFAULT 'child',
ADD COLUMN IF NOT EXISTS monthly_allowance NUMERIC(10, 2) DEFAULT 0.0;

-- 4. Transactions settlement & line items
ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS beneficiary_type TEXT DEFAULT 'household',
ADD COLUMN IF NOT EXISTS beneficiary_id TEXT,
ADD COLUMN IF NOT EXISTS is_settlement BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS settlement_target_id TEXT,
ADD COLUMN IF NOT EXISTS line_items JSONB DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_transactions_settlement_flag ON public.transactions(household_id, is_settlement);
```

- [ ] **Step 2: Commit migration file**

```bash
git add supabase/migrations/20261015_family_nafaqah_and_multi_roommate_settlement.sql
git commit -m "feat(supabase): add family nafaqah, multi-roommate settlement, and invite tables migration"
```

---

### Task 2: Backend Settlement Engine Refactor (Family Nafaqah & Multi-Party Matrix)

**Files:**
- Modify: `ai_service/settlement_engine.py`
- Create: `ai_service/tests/test_multi_party_settlement.py`

**Interfaces:**
- Consumes: `transactions` rows with `paid_by`, `beneficiary_type`, `beneficiary_id`, `is_settlement`, `line_items`.
- Produces: `calculate_settlement_v2(household_id: str, cycle_start: Optional[str] = None)` returning:
  - `mode`: `'family_nafaqah'` or `'multi_roommate'`
  - `family_summary`: `{ "wife_reimbursement_owed": float, "spent_on_wife": float, "spent_on_children": float, "family_general_total": float }`
  - `pairwise_debts`: `[ { "from_id": str, "to_id": str, "from_name": str, "to_name": str, "amount": float } ]`
  - `simplified_debts`: `[ ... ]`
  - `roommate_balances`: `{ "user_id": float }`

- [ ] **Step 1: Write failing unit tests for Family Nafaqah and Multi-Roommate math**

Create `ai_service/tests/test_multi_party_settlement.py`:
```python
import pytest
from settlement_engine import calculate_family_nafaqah, calculate_roommate_pairwise_debts, simplify_debts

def test_family_nafaqah_husband_pays_no_debt_to_wife():
    # Husband paying for groceries or kids should produce 0 debt against wife
    txs = [
        {"paid_by": "husband", "beneficiary_type": "household", "amount": 500.0, "is_settlement": False},
        {"paid_by": "husband", "beneficiary_type": "individual", "beneficiary_id": "child_sarah", "amount": 150.0, "is_settlement": False},
    ]
    res = calculate_family_nafaqah(txs, husband_id="husband", wife_id="wife")
    assert res["wife_reimbursement_owed"] == 0.0
    assert res["spent_on_children"] == 150.0
    assert res["family_general_total"] == 500.0

def test_family_nafaqah_wife_pays_husband_owes_100_percent():
    # Wife paying for household/kids creates 100% reimbursement debt for husband
    txs = [
        {"paid_by": "wife", "beneficiary_type": "household", "amount": 350.0, "is_settlement": False},
        {"paid_by": "husband", "beneficiary_type": "household", "amount": 500.0, "is_settlement": False},
    ]
    res = calculate_family_nafaqah(txs, husband_id="husband", wife_id="wife")
    assert res["wife_reimbursement_owed"] == 350.0

def test_family_nafaqah_partial_reimbursement_settlement():
    txs = [
        {"paid_by": "wife", "beneficiary_type": "household", "amount": 350.0, "is_settlement": False},
        {"paid_by": "husband", "beneficiary_type": "individual", "beneficiary_id": "wife", "amount": 200.0, "is_settlement": True},
    ]
    res = calculate_family_nafaqah(txs, husband_id="husband", wife_id="wife")
    assert res["wife_reimbursement_owed"] == 150.0

def test_roommate_pairwise_and_simplification():
    # Omar owes Ahmed 100, Ibrahim owes Ahmed 200, Tariq owes Omar 200
    debts = [
        {"from_id": "omar", "to_id": "ahmed", "amount": 100.0},
        {"from_id": "ibrahim", "to_id": "ahmed", "amount": 200.0},
        {"from_id": "tariq", "to_id": "omar", "amount": 200.0},
    ]
    simplified = simplify_debts(debts)
    # Total cash transferred in simplified must equal net balance
    assert sum(d["amount"] for d in simplified) <= sum(d["amount"] for d in debts)
    # Omar net is +100 (-100 + 200), so Omar receives 100 without paying Ahmed
    omar_net = sum(d["amount"] for d in simplified if d["to_id"] == "omar") - sum(d["amount"] for d in simplified if d["from_id"] == "omar")
    assert omar_net == 100.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest -q tests/test_multi_party_settlement.py`
Expected: FAIL (functions not yet implemented)

- [ ] **Step 3: Implement `calculate_family_nafaqah`, `calculate_roommate_pairwise_debts`, and `simplify_debts` in `settlement_engine.py`**

- [ ] **Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest -q tests/test_multi_party_settlement.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/settlement_engine.py ai_service/tests/test_multi_party_settlement.py
git commit -m "feat(ai_service): implement family nafaqah reimbursement and multi-party roommate settlement engine"
```

---

### Task 3: Backend Reimbursement & Role-Based Invite Endpoints

**Files:**
- Modify: `ai_service/models.py`
- Modify: `ai_service/main.py`
- Create: `ai_service/tests/test_reimbursement_api.py`

**Interfaces:**
- Produces:
  - `POST /households/{id}/reimbursements` (records settlement transaction with full/partial amount)
  - `POST /households/{id}/invites` (generates role-tagged 8-character invite code)
  - `GET /households/invites/{code}` (inspects invite details: household name, role)
  - `POST /households/invites/{code}/join` (joins household with confirmed role)

- [ ] **Step 1: Write failing API test**

Create `ai_service/tests/test_reimbursement_api.py`:
```python
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)
AUTH = {"X-App-Token": "bt_sec_99a81f3d4c72e01b88e2"}

def test_create_and_inspect_role_invite(monkeypatch):
    hid = "hh_test_inv_123"
    # Create spouse invite
    res = client.post(
        f"/households/{hid}/invites",
        json={"role": "spouse"},
        headers=AUTH,
    )
    assert res.status_code == 200
    code = res.json()["invite_code"]
    assert len(code) == 8
    assert res.json()["role"] == "spouse"

    # Inspect invite code
    inspect_res = client.get(f"/households/invites/{code}", headers=AUTH)
    assert inspect_res.status_code == 200
    assert inspect_res.json()["role"] == "spouse"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.\.venv\Scripts\python.exe -m pytest -q tests/test_reimbursement_api.py`
Expected: FAIL (endpoints not found)

- [ ] **Step 3: Implement Pydantic models & FastAPI endpoints in `models.py` and `main.py`**

- [ ] **Step 4: Run test to verify it passes**

Run: `.\.venv\Scripts\python.exe -m pytest -q tests/test_reimbursement_api.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/models.py ai_service/main.py ai_service/tests/test_reimbursement_api.py
git commit -m "feat(ai_service): add reimbursement recording and role-based invite endpoints"
```

---

### Task 4: Flutter Models & API Client Domain Extensions

**Files:**
- Modify: `flutter_app/lib/models/models.dart`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Create: `flutter_app/test/services/multi_party_api_client_test.dart`

**Interfaces:**
- Produces:
  - `HouseholdInvite` model
  - `ReimbursementRecordRequest`
  - `SettlementV2Summary` model
  - API methods: `createRoleInvite()`, `inspectInviteCode()`, `recordReimbursementPayment()`, `fetchSettlementV2()`

- [ ] **Step 1: Write failing unit test for models and client methods**

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/multi_party_api_client_test.dart`

- [ ] **Step 3: Implement data models in `models.dart` and methods in `budget_api_client.dart` & `api_service.dart`**

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/multi_party_api_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/models.dart flutter_app/lib/services/api/budget_api_client.dart flutter_app/lib/services/api_service.dart flutter_app/test/services/multi_party_api_client_test.dart
git commit -m "feat(flutter_app): add multi-party settlement models and domain api methods"
```

---

### Task 5: Mobile Family Reimbursement Card Widget

**Files:**
- Create: `flutter_app/lib/widgets/dashboard/family_reimbursement_card.dart`
- Create: `flutter_app/test/widgets/family_reimbursement_card_test.dart`

**Interfaces:**
- Produces: `FamilyReimbursementCard` widget displaying:
  - Total spent on Wife (*Nafaqah* attribution).
  - Total spent on Children (*Sarah*, *Fahad*, etc.).
  - Pending reimbursement balance to wife with 1-tap **"Reimburse Wife"** dialog (supporting Full payment, Custom partial amount, or Rollover into next cycle Masroof).

- [ ] **Step 1: Write failing widget test**

Create `flutter_app/test/widgets/family_reimbursement_card_test.dart`:
- Verifies rendering of wife reimbursement balance.
- Verifies tapping "Reimburse Wife" opens dialog with Full / Partial chips.
- Verifies confirming reimbursement invokes callback.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/family_reimbursement_card_test.dart`

- [ ] **Step 3: Implement `FamilyReimbursementCard` widget with STC Pay / Cash settlement dialog**

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/family_reimbursement_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/dashboard/family_reimbursement_card.dart flutter_app/test/widgets/family_reimbursement_card_test.dart
git commit -m "feat(flutter_app): implement FamilyReimbursementCard with partial/full settlement actions"
```

---

### Task 6: Mobile Multi-Roommate Settlement Card Widget

**Files:**
- Create: `flutter_app/lib/widgets/dashboard/multi_roommate_settlement_card.dart`
- Create: `flutter_app/test/widgets/multi_roommate_settlement_card_test.dart`

**Interfaces:**
- Produces: `MultiRoommateSettlementCard` widget:
  - Displays pairwise debt matrix (*Omar owes Ahmed 100 SAR, Ibrahim owes Ahmed 200 SAR*).
  - Debt Simplification toggle switch.
  - Settle button on each row opening **Record Settle Payment** bottom sheet with partial amount support.

- [ ] **Step 1: Write failing widget test**

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/multi_roommate_settlement_card_test.dart`

- [ ] **Step 3: Implement `MultiRoommateSettlementCard`**

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/multi_roommate_settlement_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/dashboard/multi_roommate_settlement_card.dart flutter_app/test/widgets/multi_roommate_settlement_card_test.dart
git commit -m "feat(flutter_app): implement MultiRoommateSettlementCard with pairwise matrix and simplification"
```

---

### Task 7: Role-Aware Invites & Joining Flow

**Files:**
- Create: `flutter_app/lib/widgets/settings/role_invite_dialog.dart`
- Modify: `flutter_app/lib/widgets/settings/household_management_card.dart`
- Modify: `flutter_app/lib/screens/onboarding/household_screen.dart`
- Create: `flutter_app/test/widgets/role_invite_dialog_test.dart`

**Interfaces:**
- Produces:
  - `RoleInviteDialog`: radio options to generate invite for **Wife / Spouse**, **Roommate**, or **Family Dependent**.
  - `HouseholdScreen`: parses invite code and displays role confirmation ("Joining as Wife / Spouse").

- [ ] **Step 1: Write failing widget test for role invite dialog**

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/role_invite_dialog_test.dart`

- [ ] **Step 3: Implement `RoleInviteDialog` and update `household_management_card.dart` & `household_screen.dart`**

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/role_invite_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/settings/role_invite_dialog.dart flutter_app/lib/widgets/settings/household_management_card.dart flutter_app/lib/screens/onboarding/household_screen.dart flutter_app/test/widgets/role_invite_dialog_test.dart
git commit -m "feat(flutter_app): add role-aware invite generation and join confirmation"
```

---

### Task 8: Trilingual Localization, Dashboard Integration & End-to-End Verification

**Files:**
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`

**Interfaces:**
- Produces:
  - Complete Arabic, English, Urdu dictionary keys for Nafaqah, Wife Reimbursement, Roommate Pairwise Settlement, and Invite Roles.
  - Dynamic card rendering on `DashboardScreen`: displays `FamilyReimbursementCard` if household has a spouse/dependents, and `MultiRoommateSettlementCard` if household has multiple peer payers.

- [ ] **Step 1: Add localization keys across English, Arabic, and Urdu**

- [ ] **Step 2: Update `DashboardScreen` to dynamically render the appropriate settlement card**

- [ ] **Step 3: Run full static analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run full Flutter test suite**

Run: `flutter test`
Expected: All tests pass (95+ passing tests)

- [ ] **Step 5: Run full Pytest test suite**

Run: `.\.venv\Scripts\python.exe -m pytest -q`
Expected: All unit & integration tests pass

- [ ] **Step 6: Commit and finalize**

```bash
git add flutter_app/lib/l10n/app_localizations.dart flutter_app/lib/screens/home/dashboard_screen.dart
git commit -m "feat: complete family nafaqah and multi-roommate settlement integration with full localization"
```
