# Design Spec: Hybrid Category Lifecycle, Custom Categories & Category Library

**Date:** 2026-10-11  
**Status:** Draft / Pending Review  
**Author:** AI Architecture Team  
**Scope:** Supabase Database Schema, AI Classification Service, Flutter Mobile Client  

---

## 1. Problem Statement & Motivation

Currently in the Budget Tracker app:
1. `cost_control_codes` is a single, global taxonomy table shared across all households.
2. Standard system categories (`OPEX-DINING`, `OPEX-GROCERY`, etc.) cannot be safely customized per household. If a user tries to rename "Dining" to a specific merchant or restaurant (e.g. "Al Baik"), it semantically distorts historical reports, breaks AI prompts, and creates multi-tenant conflicts.
3. Households have no mechanism to deactivate irrelevant system categories (e.g. a household without a car wanting to hide "Fuel & Transport") without deleting the category and risking foreign-key cascades on past transactions.
4. Developers have no clean, non-disruptive way to push new system categories to existing households without suddenly injecting unallocated budgets into their active cycles.

---

## 2. Architecture & Design Principles

We adopt the **"System Catalog with Multi-Tenant Extensions"** pattern:

1. **System Categories are Read-Only & Protected:**
   - Core categories (`OPEX-DINING`, `OPEX-GROCERY`, `OPEX-FUEL`, `OPEX-UTILITIES`, `OPEX-SHOPPING`, `OPEX-HEALTH`, etc.) are owned by the system (`is_system = true`, `household_id = NULL`).
   - Users cannot edit their code, display name, or delete them.
2. **Household Root Custom Categories:**
   - Households can create their own top-level categories (e.g., `CUSTOM_<household_id>_FARM`), scoped strictly to their `household_id`.
   - Other households cannot see or use these categories.
3. **Active / Inactive Lifecycle per Household:**
   - Categories are never deleted if they have transaction history.
   - Users can toggle any category (system or custom) **Inactive**.
   - Inactive categories are kept in the **Category Library** and can be reactivated at any time.
   - Inactivating a category removes it from the current month's active budget list and zeroes its allocation, releasing those funds back to the **Savings Reserve**.
4. **Developer Extensibility (Opt-in by Default):**
   - New system categories added by developers (via SQL migrations/seeds) appear as **Inactive / Available** in the household's Category Library.
   - They do not disturb ongoing monthly cycles until the user explicitly taps **Activate & Set Budget**.
5. **Smart Ingestion Conflict Resolution:**
   - If an incoming SMS, receipt, or manual entry is matched to an **inactive category**, the system does not silently fail or force a classification.
   - Instead, the app prompts the user:
     - **Option A:** *Reactivate "[Category]" and set budget.*
     - **Option B:** *Reassign to another category (or Miscellaneous).*

---

## 3. Database Schema & Migration Plan

### 3.1 Schema Additions

#### A. Alter `cost_control_codes`
Add tenant ownership and system flag:
```sql
ALTER TABLE public.cost_control_codes
  ADD COLUMN IF NOT EXISTS household_id UUID REFERENCES public.households(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false;

-- Mark existing standard seeded codes as system
UPDATE public.cost_control_codes
SET is_system = true, household_id = NULL
WHERE code LIKE 'OPEX-%' OR code LIKE 'CAPEX-%';
```

#### B. Create `household_category_settings`
Tracks per-household active/inactive preferences:
```sql
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
```

### 3.2 Row Level Security (RLS)

1. **`cost_control_codes`:**
   - **SELECT:** `household_id IS NULL OR household_id = auth_household_id()`
   - **INSERT:** `household_id = auth_household_id() AND is_system = false`
   - **UPDATE / DELETE:** `household_id = auth_household_id() AND is_system = false` (System categories are strictly immutable to users).
2. **`household_category_settings`:**
   - **ALL:** `household_id = auth_household_id()`

---

## 4. AI Service & Ingestion Engine

### 4.1 Category Retrieval with State Awareness
In [`ai_service/supabase_client.py`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/ai_service/supabase_client.py):
- Implement `fetch_categories_for_household(household_id: str)`:
  - Queries `cost_control_codes` where `household_id IS NULL OR household_id = household_id`.
  - Joins with `household_category_settings`.
  - Returns two distinct groups:
    1. `active_categories`: list of categories where `is_active = true`.
    2. `inactive_categories`: list of categories where `is_active = false` or newly added system categories with no active setting.

### 4.2 Classification Pipeline (`chat_parser.py` & `receipt_scanner.py`)
1. **Prompt Structure:**
   - Active categories are listed as the primary target taxonomy.
   - Inactive categories are listed under a special section: `"INACTIVE_CATEGORIES (Match only if explicit, flag for reactivation)"`.
2. **LLM Output Contract:**
   When an expense is matched, the engine returns:
   ```json
   {
     "category_code": "OPEX-DINING",
     "confidence": 0.95,
     "is_category_inactive": true,
     "suggested_alternative": "OPEX-MISC"
   }
   ```
3. If `is_category_inactive == true`:
   - The transaction is staged or flagged with status `requires_category_resolution = true`.
   - The mobile client or Telegram bot presents the resolution prompt to the user.

---

## 5. Mobile Client Architecture (Flutter)

### 5.1 Models & State
- Add `CategorySetting` and update `CostControlCode` in [`flutter_app/lib/models/models.dart`](file:///c:/Users/A/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/models/models.dart):
  - `isSystem`: bool
  - `householdId`: String?
  - `isActive`: bool
- In `BudgetProvider` / `BudgetManagementScreen`:
  - Separate state into `activeBudgets` and `inactiveCategories`.

### 5.2 UI Components

#### 1. "Category Library" Screen / Sheet
Accessible from `BudgetManagementScreen` via top bar action (`Icons.category_outlined` / `Library`):
- **Tab 1: Active Categories:**
  - Lists all enabled categories with allocation, sub-category count, and an **"Inactivate"** toggle/action.
  - Tapping Inactivate warns:
    > *"Inactivating will remove this category from your active monthly budget and return unspent allocations to your Savings Reserve. Past transaction history remains safe."*
- **Tab 2: Category Library & Available:**
  - Displays:
    1. Inactive categories previously disabled by this household.
    2. Newly added developer categories with a badge: `✨ New Available Category`.
  - Each item features:
    - Category name, icon, keywords.
    - **"Activate & Set Budget"** primary button.
    - Opens a quick dialog to enter monthly allocated amount (defaulting to 0 or desired sum).

#### 2. Inactive Category Conflict Dialog
When a transaction is parsed or entered for an inactive category:
- **Title:** `Inactive Category Detected`
- **Body:** *"This expense (SAR 45.00 at Al Baik) matches the inactive category 'Dining'."*
- **Actions:**
  - **Button 1 (Primary Emerald):** `Reactivate 'Dining'` (Sets active and saves expense).
  - **Button 2 (Outlined):** `File Under Another Category` (Opens dropdown with active categories e.g. Miscellaneous).

#### 3. "Add Custom Category" Dialog
- Allows user to create a new root category:
  - Title: Name (English/Arabic).
  - Keywords: Comma-separated merchant keywords for SMS/receipt matching.
  - Flexibility: Flexible budget toggle.
  - Saved with `household_id = currentHousehold.id`, `is_system = false`.

---

## 6. Developer Extensibility Workflow

When the developer adds a new global category in future updates:
1. Developer runs a database migration or seed:
   ```sql
   INSERT INTO public.cost_control_codes (code, category, is_system, keywords, is_flexible)
   VALUES ('OPEX-PETS', 'Pets & Veterinary', true, ARRAY['pet', 'vet', 'قطط', 'بيطري'], true);
   ```
2. Existing households have **no entry** in `household_category_settings` for `OPEX-PETS`.
3. Application queries treat missing settings for new system categories as **`is_active = false`**.
4. When users open **Category Library**, `OPEX-PETS` appears at the top under **"Available New Categories"** with a badge.
5. Zero disruption to current budget cycles, zero unexpected overdrafts or changes to Savings Reserves.

---

## 7. Verification & Testing Plan

1. **Database Tests:**
   - Verify `cost_control_codes` RLS prevents unauthorized edits to `is_system = true` rows.
   - Verify inserting custom root category with `household_id` succeeds and is hidden from other households.
   - Verify `household_category_settings` updates toggle `is_active` correctly.
2. **AI Service Tests:**
   - Test `test_inactive_category_flagging`: mock transaction matching inactive category returns `is_category_inactive: true`.
   - Test custom category keyword matching.
3. **Flutter Widget & Integration Tests:**
   - Test `CategoryLibraryScreen`: displays active vs. inactive lists, toggles activation, activates with custom budget.
   - Test `InactiveCategoryResolutionDialog`: verifies choosing "Reactivate" calls activation API, choosing "Reassign" updates transaction category.
   - Verify Savings Reserve accurately increases when a category is deactivated.
