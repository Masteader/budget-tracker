# Salary Cycle Budgeting, Auto-Rollover with Surplus Tracking, Dynamic Category Management & Hierarchical Sub-Budgets Design Specification

- **Date:** 2026-10-02
- **Status:** Approved
- **Target Components:** Supabase DB, FastAPI Backend (`ai_service`), Flutter Frontend (`flutter_app`)

---

## 1. System Overview & Problem Statement

### 1.1 Problems Addressed
1. **Calendar vs. Salary Month Mismatch:** In Saudi Arabia, salaries arrive on the 27th of the month. Using a calendar month (`yyyy-MM-01` to month-end) causes new months to start with 0 budgets and decouples spending tracking from the actual salary arrival.
2. **Empty Allocations on Month Switch:** When transitioning from one month to the next (e.g. September $\rightarrow$ October), users were faced with empty/unset budgets because monthly rows did not carry forward automatically.
3. **Lack of Surplus / Overspend Visibility:** Unspent funds from previous cycles were not clearly visible alongside the current cycle's base allocation limits.
4. **Rigid Budget Categories:** Users could not dynamically add new categories or remove obsolete ones.
5. **No Granular Sub-Budgets:** Users could not track sub-expenses under broad categories (e.g. within Groceries: meat vs. vegetables vs. snacks; within Utilities: housing rent vs. electricity vs. internet).

---

## 2. Core Architecture & Specifications

### 2.1 Salary Cycle Mechanics (27th-to-26th)
A cycle is designated by the month in which its active spending primarily occurs (the "Payday Month"):
- **Cycle Range:** Runs from the 27th of month $M-1$ at 00:00:00 to the 26th of month $M$ at 23:59:59.
- **Cycle Naming:** 
  - `2026-09-27` to `2026-10-26` is named **October Cycle (`2026-10`)**.
  - `2026-10-27` to `2026-11-26` is named **November Cycle (`2026-11`)**.
- **Cycle Key Formatting:** Standardized as `YYYY-MM` string matching the target month.
- **Weekend / Payday Adjustment:** While the budgeting window is strictly 27th-to-26th, the salary forecast indicator retains awareness of official banking adjustments (Friday payout moves to Thursday 26th; Saturday payout moves to Sunday 28th).

### 2.2 Automatic Rollover & Surplus Tracking
1. **Fixed Base Allocation:**
   - Each category has a household fixed monthly allocation (e.g., `OPEX-GROCERY: SAR 2,500.00`).
2. **Auto-Jump Trigger:**
   - When a user opens the app or an SMS/receipt transaction is received in cycle $C_n$, if no budget entries exist for $C_n$ in that household:
     - The system automatically creates budget records for cycle $C_n$ copying the base allocations.
     - `spent_amount` is initialized to `0.0`.
     - `previous_cycle_delta` is computed from cycle $C_{n-1}$:
       $$\text{previous\_cycle\_delta} = \text{allocated\_amount}_{n-1} - \text{spent\_amount}_{n-1}$$
3. **Surplus / Overspend Display:**
   - In UI budget cards and management lists:
     - If $\text{delta} > 0$: Display green badge `+SAR X unspent from previous cycle`.
     - If $\text{delta} < 0$: Display red badge `-SAR X overspent from previous cycle`.
     - If $\text{delta} = 0$: Display neutral or no badge.

### 2.3 Sub-Budget Taxonomy (Tagging Model)
Main categories hold the hard budget limit, while sub-categories categorize line items and transactions for deep intelligence and breakdown analytics:

| Main Category Code | Category Name | Proposed Sub-Budgets (Tags) |
|---|---|---|
| `OPEX-GROCERY` | Groceries & Supermarkets | `meat`, `vegetables_fruit`, `dairy_eggs`, `snacks_chips`, `beverages`, `pantry_staples`, `cleaning_household` |
| `OPEX-UTILITIES` | Utilities & Bills | `housing_rent`, `electricity_sec`, `fiber_internet`, `mobile_sims`, `water_municipal` |
| `OPEX-DINING` | Dining & Cafes | `restaurants_dinners`, `coffee_bakeries`, `delivery_apps` |
| `OPEX-FUEL` | Transportation & Fuel | `gas_fuel`, `car_maintenance`, `ride_hailing_uber_bolt`, `parking_tolls` |
| `OPEX-HEALTH` | Healthcare & Pharmacy | `prescriptions_meds`, `clinics_dental`, `wellness_vitamins` |
| `OPEX-SHOPPING` | Shopping & Retail | `clothing_fashion`, `electronics_gadgets`, `home_furniture`, `personal_care` |
| `OPEX-ENTERTAINMENT` | Entertainment & Leisure | `cinema_movies`, `streaming_subscriptions`, `activities_events` |
| `CAPEX-EDUCATION` | Education & Tuition | `school_fees`, `books_supplies`, `courses_training` |
| `OPEX-GOV` | Government & Legal | `iqama_visas`, `traffic_fines`, `civil_licenses` |
| `OPEX-MISC` | Miscellaneous & Uncategorized | `general_cash`, `tips`, `others` |

### 2.4 Dynamic Budget Category Management
- **Add Category:**
  - Household admins can add new budget categories with custom names, icon identifiers, default allocation amounts, and associated sub-budget tags.
  - New categories immediately apply to the active cycle and future auto-rollovers.
- **Remove / Archive Category:**
  - Removing a category flags it as inactive (`is_active = false`).
  - Historical transactions associated with the category remain intact.
  - Optionally allows re-assigning ongoing transactions to `OPEX-MISC`.

---

## 3. Database Schema Changes (Supabase / PostgreSQL)

### 3.1 Migration: `budgets` Table Updates
```sql
ALTER TABLE budgets 
  ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7),
  ADD COLUMN IF NOT EXISTS previous_cycle_delta NUMERIC(12, 2) DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_budgets_household_cycle ON budgets(household_id, cycle_key);
```

### 3.2 Migration: `sub_categories` Table
```sql
CREATE TABLE IF NOT EXISTS cost_control_sub_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_code VARCHAR(50) NOT NULL REFERENCES cost_control_codes(code) ON DELETE CASCADE,
  sub_code VARCHAR(50) NOT NULL,
  name_en VARCHAR(100) NOT NULL,
  name_ar VARCHAR(100) NOT NULL,
  keywords TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uq_parent_sub UNIQUE (parent_code, sub_code)
);
```

### 3.3 Migration: `transactions` Sub-Category Field
```sql
ALTER TABLE transactions 
  ADD COLUMN IF NOT EXISTS sub_category VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7);

CREATE INDEX IF NOT EXISTS idx_transactions_cycle ON transactions(household_id, cycle_key);
```

---

## 4. Backend (`ai_service`) Enhancements

1. **Cycle Date Helper (`salary_cycle.py`):**
   - Universal function `get_cycle_for_date(date)` returning `cycle_key` (`YYYY-MM`), `cycle_start` (27th), `cycle_end` (26th), and friendly label (`"October 2026 Budget"`).
2. **Auto-Rollover Engine (`supabase_client.py`):**
   - `ensure_household_cycle_budgets(household_id, target_date)`: checks if budget records exist for the cycle. If missing:
     - Copies active budget categories from previous cycle or templates.
     - Calculates `previous_cycle_delta`.
     - Inserts the new cycle rows in a single batch.
3. **Sub-Category Classifier:**
   - In `chat_parser.py` and `receipt_scanner.py`, LLM prompt includes sub-category tags to classify items (e.g. "Chips" $\rightarrow$ `snacks_chips`, "Electricity bill" $\rightarrow$ `electricity_sec`).
4. **API Endpoints:**
   - `GET /budgets/cycles?household_id={id}`: Returns list of available cycles and current active cycle.
   - `GET /budgets/breakdown?household_id={id}&cycle_key={key}`: Returns category spend with sub-category breakdown.
   - `POST /budgets/categories`: Add custom budget category.
   - `DELETE /budgets/categories/{code}`: Archive category.

---

## 5. Flutter App (`flutter_app`) Enhancements

1. **Cycle-Based Navigation Header:**
   - Replace standard calendar month switcher with Salary Cycle switcher:
     - e.g., `< October 2026 (Sep 27 - Oct 26) >`
2. **Budget Cards with Surplus Badges:**
   - Display allocated amount, spent amount, progress bar, and the surplus/deficit badge:
     - `+150.00 SAR surplus from Sept` in muted green.
3. **Sub-Budget Breakdown Sheet:**
   - Tapping any budget card opens an expandable bottom sheet / breakdown showing:
     - Progress bar of category spend.
     - Breakdown by sub-budget tags (e.g. *Meat: SAR 850, Produce: SAR 420, Snacks: SAR 310*).
4. **Manage Allocations Screen (`budget_management_screen.dart`):**
   - Add new category button with bottom sheet.
   - Delete / Archive category with confirmation dialog.
   - Instant edit of fixed allocation limit.

---

## 6. Testing & Verification Strategy

1. **Database Migration Verification:**
   - Run SQL script in Supabase, verify table schemas and indexes.
2. **Backend Unit & Integration Tests:**
   - Test `get_cycle_for_date` across leap years, Dec/Jan boundary, and 26th vs 27th.
   - Test auto-rollover logic: given a mock September cycle with 142 SAR unspent, ensure October cycle creates with `previous_cycle_delta: 142.0`.
   - Test receipt & chat sub-budget tagging in `ai_service/tests/`.
3. **Flutter Frontend Verification:**
   - Verify `flutter analyze` passes with 0 warnings.
   - Test cycle switcher on device (`SM-S938B`).
   - Test adding and deleting a budget category on device.
   - Verify sub-budget breakdown displays accurately.
