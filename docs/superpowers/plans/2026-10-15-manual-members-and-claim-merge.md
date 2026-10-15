# Pre-Created Manual Household Members & Claim-Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or step-by-step TDD with verification after each task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable household owners to pre-create manual profiles for wives/spouses, roommates, and children before they create accounts, attribute expenses and settlements to them immediately, and automatically claim/merge those profiles when the user joins via a targeted invite code.

**Architecture:**
1. Database schema in Supabase links `household_dependents.linked_user_id` to `users(id)` and `household_invites.target_member_id` to `household_dependents(id)`.
2. Backend API in FastAPI (`ai_service`) extends dependent creation with role & allowance, issues targeted invites, and provides an atomic `/households/invites/{code}/claim` endpoint.
3. Mobile app introduces the `AddHouseholdMemberSheet` and refactors `HouseholdManagementCard` into a unified "Household & Living Group" hub with pre-account vs active indicators and invite actions.
4. Onboarding join flow (`household_screen.dart`) inspects targeted invites, displays personal welcome message, and claims the pre-created profile.

**Tech Stack:** Flutter (Dart 3.x, Provider), Python (FastAPI 0.115, Pydantic v2, Pytest), Supabase (PostgreSQL, RLS).

**Spec:** [`docs/superpowers/specs/2026-10-15-manual-members-and-claim-merge-design.md`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/docs/superpowers/specs/2026-10-15-manual-members-and-claim-merge-design.md)

---

### Task 1: Supabase Migration & Backend Claim Endpoints

**Files:**
- Create: `supabase/migrations/20261015_manual_members_and_claim_merge.sql`
- Modify: `ai_service/models.py`
- Modify: `ai_service/dependents_service.py`
- Modify: `ai_service/supabase_client.py`
- Modify: `ai_service/main.py`
- Create: `ai_service/tests/test_manual_member_claim.py`

**Interfaces:**
- Produces:
  - `household_dependents.linked_user_id` column
  - `household_invites.target_member_id` column
  - `POST /households/{id}/dependents` accepts `relationship`, `monthly_allowance`, `avatar_icon`
  - `POST /households/{id}/invites` accepts optional `target_member_id`
  - `GET /households/invites/{code}` returns `target_member_id` and `target_member_name`
  - `POST /households/invites/{code}/claim` links user to dependent record and assigns `financial_role`

- [ ] **Step 1: Write migration SQL file**
- [ ] **Step 2: Write failing unit test in `test_manual_member_claim.py`**
- [ ] **Step 3: Run test to verify failure**
- [ ] **Step 4: Implement schema changes, models, and endpoints in `dependents_service.py`, `supabase_client.py`, and `main.py`**
- [ ] **Step 5: Run test to verify it passes**
- [ ] **Step 6: Commit**

---

### Task 2: Flutter Models & API Client Extensions

**Files:**
- Modify: `flutter_app/lib/models/models.dart`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Create: `flutter_app/test/services/manual_members_api_test.dart`

**Interfaces:**
- Produces:
  - `HouseholdDependent.linkedUserId`, `isClaimed` getter, `isSpouse`, `isPeer`, `isChild` getters
  - `HouseholdInvite.targetMemberId`, `targetMemberName`
  - `createHouseholdDependent(householdId, name, {relationship, avatarIcon, monthlyAllowance})`
  - `claimMemberProfile(inviteCode, userId)`
  - `createRoleInvite({householdId, role, targetMemberId})`

- [ ] **Step 1: Write failing unit test in `manual_members_api_test.dart`**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement model properties and API client methods**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 3: Mobile "Add Household Member" Sheet & Unified Hub

**Files:**
- Create: `flutter_app/lib/widgets/settings/add_household_member_sheet.dart`
- Modify: `flutter_app/lib/widgets/settings/household_management_card.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Create: `flutter_app/test/widgets/add_household_member_sheet_test.dart`
- Modify: `flutter_app/test/widgets/household_management_card_test.dart`

**Interfaces:**
- Produces:
  - `AddHouseholdMemberSheet` widget (Name, Role selector chips: Wife / Spouse 💍, Roommate 🤝, Child 👶, Monthly Masroof input)
  - `HouseholdManagementCard` renders a unified member list with Active 🟢 vs Pre-Account ⏳ badges, allowance tags, and individual "Invite" actions.

- [ ] **Step 1: Write failing widget test for `AddHouseholdMemberSheet`**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `AddHouseholdMemberSheet` and update `HouseholdManagementCard`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 4: Onboarding Claim-on-Join Experience

**Files:**
- Modify: `flutter_app/lib/screens/onboarding/household_screen.dart`
- Create: `flutter_app/test/widgets/household_screen_claim_test.dart`

**Interfaces:**
- Produces:
  - When invite code is inspected and has `targetMemberId`:
    - Shows personalized greeting: *"Welcome [Name]! Joining as [Role]."*
    - Calls `claimMemberProfile(code, uid)` on join to atomically link profile and set `financial_role`.

- [ ] **Step 1: Write failing widget test for personalized join claim**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement claim-on-join handling in `household_screen.dart`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 5: Trilingual Localization & End-to-End Verification

**Files:**
- Modify: `flutter_app/lib/l10n/app_localizations.dart`

**Interfaces:**
- Produces:
  - English, Arabic (`ar`), and Urdu (`ur`) translations for pre-account manual members, allowance, claiming, and invitations.
  - Complete verification across flutter analyzer, flutter tests, and pytest.

- [ ] **Step 1: Add localization keys across English, Arabic, and Urdu**
- [ ] **Step 2: Run static analyzer (`flutter analyze` - must be 0 issues)**
- [ ] **Step 3: Run full Flutter test suite (`flutter test` - all passing)**
- [ ] **Step 4: Run backend pytest test suite (`pytest` - all passing)**
- [ ] **Step 5: Commit and finalize**
