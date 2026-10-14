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

- [x] **Step 1: Write migration SQL file**
- [x] **Step 2: Commit migration file**

---

### Task 2: Backend Settlement Engine Refactor (Family Nafaqah & Multi-Party Matrix)

- [x] **Step 1: Write failing unit tests for Family Nafaqah and Multi-Roommate math**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `calculate_family_nafaqah`, `calculate_roommate_pairwise_debts`, and `simplify_debts` in `settlement_engine.py`**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit**

---

### Task 3: Backend Reimbursement & Role-Based Invite Endpoints

- [x] **Step 1: Write failing API test**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement Pydantic models & FastAPI endpoints in `models.py` and `main.py`**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit**

---

### Task 4: Flutter Models & API Client Domain Extensions

- [x] **Step 1: Write failing unit test for models and client methods**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement data models in `models.dart` and methods in `budget_api_client.dart` & `api_service.dart`**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit**

---

### Task 5: Mobile Family Reimbursement Card Widget

- [x] **Step 1: Write failing widget test**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `FamilyReimbursementCard` widget with STC Pay / Cash settlement dialog**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit**

---

### Task 6: Mobile Multi-Roommate Settlement Card Widget

- [x] **Step 1: Write failing widget test**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `MultiRoommateSettlementCard`**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit**

---

### Task 7: Role-Aware Invites & Joining Flow

- [x] **Step 1: Write failing widget test for role invite dialog**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `RoleInviteDialog` and update `household_management_card.dart` & `household_screen.dart`**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit**

---

### Task 8: Trilingual Localization, Dashboard Integration & End-to-End Verification

- [x] **Step 1: Add localization keys across English, Arabic, and Urdu**
- [x] **Step 2: Update `DashboardScreen` to dynamically render the appropriate settlement card**
- [x] **Step 3: Run full static analyzer**
- [x] **Step 4: Run full Flutter test suite**
- [x] **Step 5: Run full Pytest test suite**
- [x] **Step 6: Commit and finalize**
