# Implementation Plan: Dashboard Synchronization, Commitments SSOT & Active Budget Category Picker

**Sensitive:** yes, because it alters financial HUD calculations on the dashboard, commitments aggregation, and transaction category mapping.

---

## 1. Issue Analysis & Root Causes

### Issue 1: Commitments Mismatch on Dashboard (Hero Card SAR 1,162 vs Accounts Card SAR 3,027)
- **Root Cause:**
  - `BudgetHeroCard` reads `snapshot.pendingCommitments` via `AccountProvider` and `CommitmentsService`, which correctly filters unpaid obligations due **within the active salary cycle**.
  - `AccountsSummaryCard` (`accounts_summary_card.dart:115-132`) bypassed `AccountProvider` and performed its own raw sum of ALL bills in `billsSummary` and ALL active plans in `installmentPlans`, regardless of due dates.
- **Fix:**
  - Refactor `AccountsSummaryCard` to consume `AccountProvider.operatingCashSnapshot.pendingCommitments`.
  - Ensures both cards on the Dashboard display the exact same commitments amount (**SAR 1,162.00**).

### Issue 2: Dashboard Hero Card (SAR 3,302.89) Did Not Reflect Manual Bank Account Edit (SAR 3,353.75)
- **Root Cause:**
  - When `monthlyIncome` is passed to `PaydayOutlook.compute`, `left` is strictly computed as `monthlyIncome - totalSpent` (8,944.54 - 5,641.65 = 3,302.89).
  - Manual account balance edits directly change `accounts.balance` (`liquidBalance = 3,353.75`), which bypassed `income_records`.
  - This created a 50.86 SAR divergence between recorded income inflow and physical bank balance.
- **Fix:**
  - In `BudgetHeroCard`, when operating accounts are tracked (`snapshot != null`), `left` should reflect true spendable cash (`snapshot.liquidBalance`), or adjust the baseline so Left Until Payday equals actual bank balance.

### Issue 3: Category Dropdown in Edit Transaction Shows Inactive Categories (e.g. Fuel)
- **Root Cause:**
  - `edit_transaction_sheet.dart:1443` uses `CategoryCatalog.pickerCodesIncluding(_selectedCategory)`, returning all 20+ hardcoded global taxonomy codes.
  - The user's active household budget does not include "Fuel", leading to unbudgeted transactions and confusing over-budget warnings.
- **Fix:**
  - Update `edit_transaction_sheet.dart` to read `BudgetProvider.activeCategories` (matching `manual_expense_sheet.dart`).
  - If a transaction has a legacy/inactive category (like Fuel), include it with an `(Unbudgeted)` label, while presenting active budget categories for all new selections.

---

## 2. File Modification Inventory
1. `flutter_app/lib/widgets/dashboard/accounts_summary_card.dart`:
   - Bind `totalCommitments` and `actualAvailable` to `AccountProvider.snapshot`.
2. `flutter_app/lib/widgets/dashboard/budget_hero_card.dart` & `flutter_app/lib/models/payday_outlook.dart`:
   - Synchronize `left` with verified `snapshot.liquidBalance`.
3. `flutter_app/lib/screens/home/edit_transaction_sheet.dart`:
   - Scope category dropdown to `BudgetProvider.activeCategories`.
4. Unit and Widget Tests:
   - `flutter_app/test/widgets/accounts_summary_card_commitments_sync_test.dart`
   - `flutter_app/test/widgets/budget_hero_card_liquid_sync_test.dart`
   - `flutter_app/test/screens/edit_transaction_active_categories_test.dart`
