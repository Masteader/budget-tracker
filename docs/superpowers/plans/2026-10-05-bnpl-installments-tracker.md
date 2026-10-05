# Installment & BNPL Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track BNPL installment commitments (Tamara, Tabby, Bank installment plans), amortize purchases over monthly terms (e.g. eXtra SAR 7,408 across 4 months at SAR 1,852/month), prevent upfront budget deficits, and reserve monthly payments in the active 27th payday cycle.

**Architecture:** 
- Supabase table `installment_plans` storing purchase metadata, provider (Tamara/Tabby), total amount, term length, paid installments, and link to original transaction.
- FastAPI endpoints for CRUD and payment progression, automatically reserving upcoming monthly installments alongside recurring utility bills.
- Flutter mobile model, API client methods, `InstallmentPlansCard` widget on the dashboard, and 1-tap conversion on transactions over SAR 500.

**Tech Stack:** Python 3.14 (FastAPI, Pytest, Supabase), Flutter 3.38+ (Dart, Material 3, GoogleFonts Outfit).

---

## Tasks

### Task 1: Supabase Database Migration & Model Schema
**Files:**
- Create: `supabase/migrations/20261005_add_installment_plans.sql`
- Test: Verify schema creation via Supabase service client query

- [ ] **Step 1: Write migration SQL**
```sql
CREATE TABLE IF NOT EXISTS public.installment_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    merchant TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'Tamara',
    total_amount NUMERIC(12, 2) NOT NULL,
    installment_count INTEGER NOT NULL DEFAULT 4,
    monthly_amount NUMERIC(12, 2) NOT NULL,
    paid_installments INTEGER NOT NULL DEFAULT 1,
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    day_of_month INTEGER NOT NULL DEFAULT 27,
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    category_code TEXT DEFAULT 'OPEX-SHOPPING',
    original_transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
```
- [ ] **Step 2: Apply migration to Supabase database**
- [ ] **Step 3: Commit migration**

---

### Task 2: Backend Pytest & Installment Endpoints
**Files:**
- Create: `ai_service/installment_service.py`
- Modify: `ai_service/main.py`
- Modify: `ai_service/recurring_detector.py`
- Create: `ai_service/tests/test_installment_service.py`

- [ ] **Step 1: Write failing tests in `test_installment_service.py`**
- [ ] **Step 2: Run pytest to verify RED state**
- [ ] **Step 3: Implement `installment_service.py` and routes in `main.py`**
- [ ] **Step 4: Update `recurring_detector.py` to reserve active monthly installments in cycle calculation**
- [ ] **Step 5: Run pytest to verify GREEN state**
- [ ] **Step 6: Commit backend changes**

---

### Task 3: Mobile Model & API Client Integration
**Files:**
- Create: `flutter_app/lib/models/installment_plan.dart`
- Modify: `flutter_app/lib/services/api/budget_api_client.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Create: `flutter_app/test/models/installment_plan_test.dart`

- [ ] **Step 1: Write failing test `installment_plan_test.dart`**
- [ ] **Step 2: Run `flutter test` to verify RED state**
- [ ] **Step 3: Implement `InstallmentPlan` model and client methods**
- [ ] **Step 4: Run `flutter test` to verify GREEN state**
- [ ] **Step 5: Commit mobile client changes**

---

### Task 4: Mobile UI: `InstallmentPlansCard` & 1-Tap Transaction Convert
**Files:**
- Create: `flutter_app/lib/widgets/dashboard/installment_plans_card.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/widgets/transaction_item_breakdown_card.dart`
- Create: `flutter_app/test/widgets/installment_plans_card_test.dart`

- [ ] **Step 1: Write failing widget test `installment_plans_card_test.dart`**
- [ ] **Step 2: Run `flutter test` to verify RED state**
- [ ] **Step 3: Implement `InstallmentPlansCard` and transaction conversion dialog**
- [ ] **Step 4: Run `flutter test` to verify GREEN state**
- [ ] **Step 5: Commit UI changes**

---

### Task 5: Live Verification & eXtra SAR 7,408 Conversion
- [ ] **Step 1: Convert eXtra transaction to Tamara 4-month installment**
- [ ] **Step 2: Verify budget adjustment in backend and mobile**
- [ ] **Step 3: Capture screenshot on Realme 8 device**
- [ ] **Step 4: Push `feat/bnpl-installments-tracking` to GitHub**
