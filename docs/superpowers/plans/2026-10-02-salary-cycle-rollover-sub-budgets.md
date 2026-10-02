# Salary Cycle Budgeting, Auto-Rollover with Surplus Tracking, Dynamic Category Management & Sub-Budgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the budgeting system to align with the Saudi 27th salary cycle, enable automatic cycle rollovers with surplus/overspend tracking, allow dynamic category addition/removal, and implement tag-based hierarchical sub-budgets.

**Architecture:** Database schema updates in Supabase add cycle tracking and sub-categories; FastAPI microservice provides cycle math, auto-rollover calculation, and sub-budget breakdown endpoints; Flutter frontend introduces salary cycle navigation (`Sep 27 - Oct 26`), previous-cycle surplus badges, sub-budget drilldown sheets, and dynamic category management.

**Tech Stack:** PostgreSQL (Supabase), Python 3.12+ (FastAPI, Pydantic v2, Pytest), Flutter 3.24+ (Dart, Riverpod/Stateful streams, Google Fonts).

**Spec:** `docs/superpowers/specs/2026-10-02-salary-cycle-rollover-sub-budgets-design.md`

## Global Constraints
- Cycle Date Window: strictly 27th of Month $M-1$ (00:00:00) to 26th of Month $M$ (23:59:59).
- Cycle Key: format `YYYY-MM` corresponding to Month $M$ (the Payday Month).
- Surplus/Deficit: `previous_cycle_delta = allocated_amount - spent_amount` from previous cycle.
- Sub-Budgets: tag-based model under parent category ceiling.
- No Breaking Changes to existing transaction history or SMS receiver webhook.

---

### Task 1: Database Migration & Sub-Categories Seed

**Files:**
- Create: `supabase/migrations/20261002_salary_cycle_and_sub_budgets.sql`
- Script: `ai_service/scripts/apply_migration.py`
- Test: `ai_service/tests/test_migration_schema.py`

**Interfaces:**
- Consumes: Existing Supabase `budgets`, `transactions`, `cost_control_codes` tables.
- Produces: `budgets.cycle_key`, `budgets.previous_cycle_delta`, `budgets.is_active`, `transactions.sub_category`, `transactions.cycle_key`, and `cost_control_sub_categories` table.

- [ ] **Step 1: Write the SQL migration file**
Create `supabase/migrations/20261002_salary_cycle_and_sub_budgets.sql` with:
```sql
ALTER TABLE budgets 
  ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7),
  ADD COLUMN IF NOT EXISTS previous_cycle_delta NUMERIC(12, 2) DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_budgets_household_cycle ON budgets(household_id, cycle_key);

ALTER TABLE transactions 
  ADD COLUMN IF NOT EXISTS sub_category VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7);

CREATE INDEX IF NOT EXISTS idx_transactions_cycle ON transactions(household_id, cycle_key);

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

-- Seed Initial Sub-Categories
INSERT INTO cost_control_sub_categories (parent_code, sub_code, name_en, name_ar, keywords) VALUES
('OPEX-GROCERY', 'meat', 'Meat & Poultry', 'اللحوم والدواجن', ARRAY['meat', 'chicken', 'beef', 'lamb', 'لحم', 'دجاج']),
('OPEX-GROCERY', 'vegetables_fruit', 'Fresh Produce & Fruits', 'الخضار والفواكه', ARRAY['produce', 'vegetables', 'fruit', 'خضار', 'فواكه']),
('OPEX-GROCERY', 'dairy_eggs', 'Dairy & Eggs', 'الألبان والبيض', ARRAY['milk', 'cheese', 'yogurt', 'eggs', 'حليب', 'جبن', 'بيض']),
('OPEX-GROCERY', 'snacks_chips', 'Snacks, Chips & Sweets', 'الشيبس والسناكات والحلويات', ARRAY['chips', 'snack', 'chocolate', 'candy', 'شيبس', 'بسكويت']),
('OPEX-GROCERY', 'beverages', 'Beverages & Water', 'المشروبات والمياه', ARRAY['water', 'juice', 'soda', 'pepsi', 'ماء', 'عصير']),
('OPEX-GROCERY', 'pantry_staples', 'Pantry & Staples', 'التموين والمؤن', ARRAY['rice', 'oil', 'flour', 'sugar', 'أرز', 'زيت', 'سكر']),
('OPEX-GROCERY', 'cleaning_household', 'Cleaning & Household Supplies', 'المنظفات ومستلزمات المنزل', ARRAY['soap', 'detergent', 'tissue', 'صابون', 'مناديل']),

('OPEX-UTILITIES', 'housing_rent', 'Housing Rent', 'إيجار السكن', ARRAY['rent', 'apartment', 'housing', 'إيجار']),
('OPEX-UTILITIES', 'electricity_sec', 'Electricity (SEC)', 'فاتورة الكهرباء', ARRAY['electricity', 'sec', 'كهرباء']),
('OPEX-UTILITIES', 'fiber_internet', 'Home Fiber Internet', 'الإنترنت المنزلي', ARRAY['internet', 'fiber', 'stc fiber', 'mobily fiber', 'إنترنت']),
('OPEX-UTILITIES', 'mobile_sims', 'Mobile SIMs & Data', 'باقات الجوال والاتصالات', ARRAY['sim', 'prepaid', 'postpaid', 'stc', 'mobily', 'zain', 'شحن']),
('OPEX-UTILITIES', 'water_municipal', 'Water & Municipal Bills', 'المياه والخدمات البلدية', ARRAY['water', 'nwc', 'مياه']),

('OPEX-DINING', 'restaurants_dinners', 'Restaurants & Meals', 'المطاعم والوجبات', ARRAY['restaurant', 'dinner', 'lunch', 'burger', 'مطعم']),
('OPEX-DINING', 'coffee_bakeries', 'Coffee & Bakeries', 'القهوة والمخابز', ARRAY['coffee', 'cafe', 'starbucks', 'dunkin', 'قهوة', 'كافيه']),
('OPEX-DINING', 'delivery_apps', 'Delivery Apps', 'تطبيقات التوصيل', ARRAY['hungerstation', 'jahez', 'toyou', 'هنقرستيشن', 'جاهز']),

('OPEX-FUEL', 'gas_fuel', 'Gasoline & Fuel', 'بنزين ووقود', ARRAY['gas', 'fuel', 'petrol', 'aramco', 'بنزين', 'وقود']),
('OPEX-FUEL', 'car_maintenance', 'Car Maintenance & Oil', 'صيانة وتغيير الزيت', ARRAY['oil change', 'mechanic', 'tires', 'صيانة', 'زيت']),
('OPEX-FUEL', 'ride_hailing', 'Ride Hailing (Uber/Bolt)', 'تطبيقات النقل والتوصيل', ARRAY['uber', 'bolt', 'careem', 'أوبر', 'بوليت']),

('OPEX-HEALTH', 'prescriptions_meds', 'Prescriptions & Medicines', 'الأدوية والوصفات', ARRAY['pharmacy', 'medicine', 'dawaa', 'nahdi', 'صيدلية', 'دواء']),
('OPEX-HEALTH', 'clinics_dental', 'Clinics & Dental', 'العيادات والأسنان', ARRAY['clinic', 'dental', 'doctor', 'hospital', 'عيادة', 'أسنان']),

('OPEX-SHOPPING', 'clothing_fashion', 'Clothing & Fashion', 'الملابس والأزياء', ARRAY['clothes', 'fashion', 'zara', 'h&m', 'ملابس']),
('OPEX-SHOPPING', 'electronics_gadgets', 'Electronics & Gadgets', 'الإلكترونيات والتقنية', ARRAY['jarir', 'extra', 'apple', 'electronics', 'إلكترونيات']),
('OPEX-SHOPPING', 'home_furniture', 'Home Goods & Furniture', 'الأثاث والمفروشات', ARRAY['ikea', 'furniture', 'home', 'أثاث'])
ON CONFLICT (parent_code, sub_code) DO NOTHING;
```

- [ ] **Step 2: Write test for database migration schema**
Create `ai_service/tests/test_migration_schema.py`:
```python
from dotenv import load_dotenv
load_dotenv()
from supabase_client import get_client

def test_migration_columns_and_sub_categories():
    client = get_client()
    # Verify budgets table columns
    b = client.table("budgets").select("cycle_key, previous_cycle_delta, is_active").limit(1).execute()
    assert b is not None
    # Verify sub_categories exist
    subs = client.table("cost_control_sub_categories").select("*").limit(5).execute()
    assert len(subs.data) >= 5
```

- [ ] **Step 3: Execute migration via migration runner**
Apply migration using Python runner and verify output:
```bash
python ai_service/scripts/apply_migration.py
```

- [ ] **Step 4: Run test to verify migration success**
```bash
pytest ai_service/tests/test_migration_schema.py -v
```

- [ ] **Step 5: Commit migration**
```bash
git add supabase/migrations/20261002_salary_cycle_and_sub_budgets.sql ai_service/tests/test_migration_schema.py
git commit -m "feat(db): add salary cycle columns and sub_categories seed table"
```

---

### Task 2: Backend Cycle Calculation & Auto-Rollover Engine

**Files:**
- Modify: `ai_service/salary_cycle.py`
- Modify: `ai_service/supabase_client.py`
- Test: `ai_service/tests/test_salary_cycle.py`

**Interfaces:**
- Consumes: Dates, `budgets` rows, `household_id`.
- Produces: 
  - `get_cycle_for_date(target_date: date) -> Dict[str, Any]`
  - `ensure_household_cycle_budgets(household_id: str, target_date: Optional[date]) -> List[Dict[str, Any]]`

- [ ] **Step 1: Write failing unit test for cycle calculation & rollover**
Create `ai_service/tests/test_salary_cycle.py`:
```python
from datetime import date
from salary_cycle import get_cycle_for_date

def test_get_cycle_for_date_october_early():
    # Oct 2, 2026 is inside the October cycle (starts Sep 27, ends Oct 26)
    info = get_cycle_for_date(date(2026, 10, 2))
    assert info["cycle_key"] == "2026-10"
    assert info["cycle_start"] == "2026-09-27"
    assert info["cycle_end"] == "2026-10-26"
    assert "October 2026" in info["label"]

def test_get_cycle_for_date_day_27_transitions_to_next():
    # Oct 27, 2026 starts the November cycle (starts Oct 27, ends Nov 26)
    info = get_cycle_for_date(date(2026, 10, 27))
    assert info["cycle_key"] == "2026-11"
    assert info["cycle_start"] == "2026-10-27"
    assert info["cycle_end"] == "2026-11-26"
```

- [ ] **Step 2: Run test to confirm it fails**
```bash
pytest ai_service/tests/test_salary_cycle.py -v
```

- [ ] **Step 3: Implement `get_cycle_for_date` and `ensure_household_cycle_budgets`**
In `ai_service/salary_cycle.py`:
```python
def get_cycle_for_date(target_date: Optional[date] = None) -> Dict[str, Any]:
    today = target_date or datetime.now(timezone.utc).date()
    if today.day >= 27:
        start_date = today.replace(day=27)
        year = today.year + (1 if today.month == 12 else 0)
        month = 1 if today.month == 12 else today.month + 1
        end_date = date(year, month, 26)
        cycle_key = f"{year:04d}-{month:02d}"
        cycle_month_name = date(year, month, 1).strftime("%B %Y")
    else:
        year = today.year - (1 if today.month == 1 else 0)
        prev_month = 12 if today.month == 1 else today.month - 1
        start_date = date(year, prev_month, 27)
        end_date = today.replace(day=26)
        cycle_key = f"{today.year:04d}-{today.month:02d}"
        cycle_month_name = today.strftime("%B %Y")

    return {
        "cycle_key": cycle_key,
        "cycle_start": start_date.isoformat(),
        "cycle_end": end_date.isoformat(),
        "label": f"{cycle_month_name} Budget ({start_date.strftime('%b %d')} - {end_date.strftime('%b %d')})",
        "month_name": cycle_month_name,
    }
```
In `ai_service/supabase_client.py`:
Implement `ensure_household_cycle_budgets(household_id: str, target_date: Optional[date] = None)`:
- Queries `budgets` for `household_id` and `cycle_key`.
- If empty: finds latest prior cycle. Calculates `previous_cycle_delta = allocated_amount - spent_amount`.
- Inserts new rows with `spent_amount = 0.0`, `cycle_key`, and `previous_cycle_delta`.

- [ ] **Step 4: Run test to confirm it passes**
```bash
pytest ai_service/tests/test_salary_cycle.py -v
```

- [ ] **Step 5: Commit cycle calculation & rollover logic**
```bash
git add ai_service/salary_cycle.py ai_service/supabase_client.py ai_service/tests/test_salary_cycle.py
git commit -m "feat(ai_service): implement 27th-cycle calculation and auto-rollover engine"
```

---

### Task 3: Backend Sub-Category Categorization & Breakdown API

**Files:**
- Modify: `ai_service/models.py`
- Modify: `ai_service/main.py`
- Modify: `ai_service/chat_parser.py`
- Modify: `ai_service/receipt_scanner.py`
- Test: `ai_service/tests/test_sub_budget_api.py`

**Interfaces:**
- Endpoints:
  - `GET /budgets/cycles?household_id={id}` $\rightarrow$ returns active and past salary cycles
  - `GET /budgets/breakdown?household_id={id}&cycle_key={key}` $\rightarrow$ returns categories with sub-budget spending aggregates
  - `POST /budgets/categories` $\rightarrow$ add/create category
  - `DELETE /budgets/categories/{code}?household_id={id}` $\rightarrow$ deactivate category

- [ ] **Step 1: Write failing test for breakdown and cycle endpoints**
Create `ai_service/tests/test_sub_budget_api.py`:
```python
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_get_cycles_endpoint():
    resp = client.get("/budgets/cycles?household_id=f860188e-23b5-4749-b180-868c956151a6", headers={"X-App-Token": "bt_sec_99a81f3d4c72e01b88e2"})
    assert resp.status_code == 200
    data = resp.json()
    assert "current_cycle" in data
    assert "cycles" in data

def test_get_category_breakdown():
    resp = client.get("/budgets/breakdown?household_id=f860188e-23b5-4749-b180-868c956151a6&cycle_key=2026-10", headers={"X-App-Token": "bt_sec_99a81f3d4c72e01b88e2"})
    assert resp.status_code == 200
    assert "categories" in resp.json()
```

- [ ] **Step 2: Run test to confirm it fails**
```bash
pytest ai_service/tests/test_sub_budget_api.py -v
```

- [ ] **Step 3: Implement endpoints in `main.py` and enrich parsers**
- In `main.py`, implement `/budgets/cycles`, `/budgets/breakdown`, `/budgets/categories` (POST/DELETE).
- In `chat_parser.py` and `receipt_scanner.py`, include sub-category keyword matching from `cost_control_sub_categories` so transactions and item breakdowns automatically tag `sub_category`.

- [ ] **Step 4: Run test to verify it passes**
```bash
pytest ai_service/tests/test_sub_budget_api.py -v
```

- [ ] **Step 5: Commit API endpoints and tagging enhancements**
```bash
git add ai_service/models.py ai_service/main.py ai_service/chat_parser.py ai_service/receipt_scanner.py ai_service/tests/test_sub_budget_api.py
git commit -m "feat(api): add cycle breakdown, category management, and sub-budget tagging"
```

---

### Task 4: Flutter Models & Service Layer for Salary Cycle and Sub-Budgets

**Files:**
- Modify: `flutter_app/lib/models/models.dart`
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/salary_cycle_model_test.dart`

**Interfaces:**
- Consumes: Backend endpoints `/budgets/cycles`, `/budgets/breakdown`.
- Produces: `SalaryCycleInfo`, `SubCategoryBreakdownItem`, `Budget` with `cycleKey` and `previousCycleDelta`.

- [ ] **Step 1: Write test for updated models**
Create `flutter_app/test/salary_cycle_model_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('Budget model parses cycleKey and previousCycleDelta', () {
    final map = {
      'id': 'b-1',
      'household_id': 'h-1',
      'month': '2026-10-01',
      'cycle_key': '2026-10',
      'category_code': 'OPEX-GROCERY',
      'allocated_amount': 2500.0,
      'spent_amount': 500.0,
      'previous_cycle_delta': 150.0,
      'is_active': true,
    };
    final b = Budget.fromMap(map);
    assert(b.cycleKey == '2026-10');
    assert(b.previousCycleDelta == 150.0);
  });
}
```

- [ ] **Step 2: Update Dart models and API methods**
- Update `Budget` class in `flutter_app/lib/models/models.dart` to include `cycleKey`, `previousCycleDelta`, `isActive`.
- Add `SubCategoryBreakdown` model.
- Add `ApiService.getSalaryCycles()` and `ApiService.getCategoryBreakdown()`.

- [ ] **Step 3: Run test to verify it passes**
```bash
flutter test test/salary_cycle_model_test.dart
```

- [ ] **Step 4: Commit model updates**
```bash
git add flutter_app/lib/models/models.dart flutter_app/lib/services/api_service.dart flutter_app/test/salary_cycle_model_test.dart
git commit -m "feat(flutter): support cycleKey, surplus delta, and sub-category models"
```

---

### Task 5: Flutter Cycle Navigation Header & Surplus Badges in Dashboard

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/widgets/salary_cycle_widget.dart`

**Interfaces:**
- Replaces calendar month text with `SalaryCycleInfo.label` (e.g. `October 2026 (Sep 27 - Oct 26)`).
- Renders `+SAR 150 surplus from Sept` or `-SAR 50 overspent` beside base allocation in `_BudgetCard`.

- [ ] **Step 1: Update Dashboard AppBar with Cycle Switcher**
In `dashboard_screen.dart`:
- Replace calendar dates with salary cycle dates (27th-to-26th).
- Filter budgets by `cycle_key` (fallback to `month` for backwards compatibility).
- In `_BudgetCard`:
  - If `budget.previousCycleDelta > 0`: render green chip `+SAR ${fmt.format(budget.previousCycleDelta)} prev surplus`.
  - If `budget.previousCycleDelta < 0`: render red/orange chip `-SAR ${fmt.format(budget.previousCycleDelta.abs())} overspent`.

- [ ] **Step 2: Verify with flutter analyze**
```bash
flutter analyze lib/screens/home/dashboard_screen.dart
```

- [ ] **Step 3: Commit dashboard cycle and surplus badges**
```bash
git add flutter_app/lib/screens/home/dashboard_screen.dart flutter_app/lib/widgets/salary_cycle_widget.dart
git commit -m "feat(ui): display salary cycle headers and previous cycle surplus badges"
```

---

### Task 6: Flutter Sub-Budget Breakdown Sheet

**Files:**
- Create: `flutter_app/lib/widgets/sub_budget_breakdown_sheet.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`

**Interfaces:**
- Triggered when tapping any `_BudgetCard` on the dashboard.
- Displays:
  - Total category spent vs allocated.
  - Sub-category items breakdown (e.g. *Meat: 850 SAR, Veggies: 420 SAR, Snacks & Chips: 310 SAR*).
  - Progress percentage bars per sub-tag.

- [ ] **Step 1: Create `SubBudgetBreakdownSheet` widget**
Create `flutter_app/lib/widgets/sub_budget_breakdown_sheet.dart` with:
- Category Header & icon.
- Circular or stacked horizontal progress breakdown.
- List of sub-categories with amount spent, transaction count, and percentage of parent spend.

- [ ] **Step 2: Connect tap event in `_BudgetCard`**
In `_BudgetCard`:
- Wrap in `InkWell`: on tap, call `showModalBottomSheet` rendering `SubBudgetBreakdownSheet(budget: widget.budget, householdId: widget.householdId)`.

- [ ] **Step 3: Verify with flutter analyze**
```bash
flutter analyze lib/widgets/sub_budget_breakdown_sheet.dart lib/screens/home/dashboard_screen.dart
```

- [ ] **Step 4: Commit sub-budget sheet**
```bash
git add flutter_app/lib/widgets/sub_budget_breakdown_sheet.dart flutter_app/lib/screens/home/dashboard_screen.dart
git commit -m "feat(ui): add hierarchical sub-budget drilldown bottom sheet"
```

---

### Task 7: Flutter Dynamic Category Management (Add & Remove Budgets)

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Create: `flutter_app/lib/widgets/add_category_modal.dart`

**Interfaces:**
- Allows household admin to:
  - Add new budget category with custom or predefined sub-tags and monthly target.
  - Delete / Deactivate existing budget category with safety confirmation.
  - View previous cycle surplus / deficit beside each allocation.

- [ ] **Step 1: Create `AddCategoryModal`**
In `flutter_app/lib/widgets/add_category_modal.dart`:
- Selection between standard Saudi expense catalog or Custom Category.
- Category name, icon selector, initial allocated amount, and sub-category chips.
- [Save to Household Budget] action button.

- [ ] **Step 2: Add Remove / Archive Action to `BudgetManagementScreen`**
In `budget_management_screen.dart`:
- Add delete button (`Icons.delete_outline`) for admins.
- Show dialog: "Archive Category? Historical transactions will be retained."
- Calls API/Supabase to set `is_active = false`.
- Floating action button: "Add Category" $\rightarrow$ opens `AddCategoryModal`.

- [ ] **Step 3: Verify with flutter analyze**
```bash
flutter analyze lib/screens/home/budget_management_screen.dart lib/widgets/add_category_modal.dart
```

- [ ] **Step 4: Commit category management updates**
```bash
git add flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/widgets/add_category_modal.dart
git commit -m "feat(ui): add category creation and archiving in budget manager"
```

---

### Task 8: End-to-End Verification on Device

**Files:**
- All touched files

- [ ] **Step 1: Run full test suites**
```bash
pytest ai_service/tests/ -v
flutter test
```

- [ ] **Step 2: Deploy & verify live on connected phone (`SM-S938B`)**
- Compile and install updated APK.
- Verify October 2026 shows `Sep 27 - Oct 26`.
- Verify surplus badge appears beside allocations.
- Tap a category and confirm sub-budget breakdown opens.
- Test adding a new custom category and confirm it persists.
