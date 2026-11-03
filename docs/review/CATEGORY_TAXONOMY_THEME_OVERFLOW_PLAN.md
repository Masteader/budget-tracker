# Implementation Plan: Category Taxonomy Synchronization, Theme Contrast & Budget Screen Overflow

**Sensitive:** yes, because it alters category allocation resolution, `budget_management_screen.dart`, `budget_api_client.dart`, and transaction categorization models.

---

## 1. Summary of Changes

This plan addresses 4 reported defects:
1. **Accounts Overview Theme & "Funded" Contrast:** Fix invisible white-on-white text in `AccountsOverviewScreen` badge under light mode, and harmonize first card theme tokens.
2. **Budget Management Capacity Card Overflow:** Replace unconstrained `Row` with responsive `Wrap` for cycle margin and spent/cash stats to prevent horizontal text overflow.
3. **Custom Category Subcategory Listing in Edit Transaction:** Enable `EditTransactionSheet` to list subcategories for custom envelopes by passing `household_id` to API and merging active `subAllocations`.
4. **Custom Category Display Name Uniformity:** Ensure custom categories display their user-defined names ("Car and Transport") instead of raw strings (`custom_car_transport`) across edit transaction dropdowns, budget options menus, and allocation dialog headers.

---

## 2. File Inventory & Planned Edits

| File Path | Description of Changes |
|---|---|
| `flutter_app/lib/screens/accounts/accounts_overview_screen.dart` | Replace hardcoded `color: Colors.white` in "Funded" badge with `deficitCount == 0 ? context.successText : (isDark ? Colors.redAccent : Colors.red.shade800)`. Ensure theme-adaptive pill and card styling. |
| `flutter_app/lib/screens/home/budget_management_screen.dart` | Replace unconstrained `Row` on lines 1860-1885 with `Wrap` (alignment `spaceBetween`, runSpacing `4`). Pass `categoryName: displayName` to `LinkAccountSheet.show`. |
| `flutter_app/lib/services/api/budget_api_client.dart` | In `getSubCategories(String parentCode, {String? householdId})`, include `household_id` in query parameters when present. |
| `flutter_app/lib/screens/home/edit_transaction_sheet.dart` | Pass `householdId` when fetching subcategories. In addition, resolve subcategories from `BudgetProvider.activeCategories` (merging envelope `subAllocations`). Resolve display names in `_buildCategoryDropdownItems` via `BudgetProvider` before falling back to `trCat`. |
| `flutter_app/lib/widgets/sub_budget_allocation_dialog.dart` | In lines 852 and 861, use `widget.categoryName` instead of discarding it and calling `context.trCat(widget.categoryCode)`. |
| `flutter_app/lib/widgets/sub_budget_breakdown_sheet.dart` | In line 284, use `_categoryData?.categoryName ?? widget.categoryCode` instead of hardcoding `context.trCat`. |

---

## 3. Step-by-Step Execution Plan

### Step 1: Branch Setup & Test Scaffold
- Create feature branch: `fix/category-taxonomy-theme-overflow`.
- Add test suites:
  - `flutter_app/test/screens/accounts_overview_funded_contrast_test.dart`
  - `flutter_app/test/screens/budget_management_cycle_card_overflow_test.dart`
  - `flutter_app/test/screens/edit_transaction_custom_category_display_test.dart`

### Step 2: Implementation of Fixes
- Task 2.1: Fix "Funded" badge text contrast and theme tokens in `accounts_overview_screen.dart`.
- Task 2.2: Implement responsive `Wrap` on `budget_management_screen.dart:1860-1885`.
- Task 2.3: Update `budget_api_client.dart` and `edit_transaction_sheet.dart` to resolve subcategories for custom envelopes from both API and `subAllocations`.
- Task 2.4: Update category display name resolution in `edit_transaction_sheet.dart`, `sub_budget_allocation_dialog.dart`, `sub_budget_breakdown_sheet.dart`, and `budget_management_screen.dart`.

### Step 3: Verification Gate
- Run `flutter analyze` (0 issues).
- Run `flutter test` (100% passing across all tests).
- Run Python tests `cd ai_service && pytest -v`.

### Step 4: Multi-Round Audit Pipeline
- Round 1: Claude Opus 5.5 High (Specification Fidelity).
- Round 2: Claude Opus 5.5 High (Adversarial Break Testing).
- Round 3: Fable High (Mandatory sensitive audit for budget/ledger safety).

