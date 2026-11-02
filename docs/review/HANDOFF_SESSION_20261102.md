# Session Handoff: Dashboard HUD Synchronization, Commitments SSOT & Active Budget Category Scoping

**Timestamp:** 2026-11-02 14:04 UTC+3  
**Branch:** `main` (Tracking `origin/main` @ commit `a7e4961`)  
**Context Window Status:** ~235,000 / 250,000 tokens (**~94%** of active session compaction limit, exceeding the 70%/80% guardrail).  
**Governance:** Strict Claude Opus 5.5 Orchestrator model.

---

## 1. What Was Completed & Verified in This Session

1. **Root Cause Database Cleanup:**
   - Purged historical `raw_sms` jargon in favor of `notes` across SQL, FastAPI, and Flutter.
   - Dropped obsolete `users.payday_day` zombie column in favor of `households.payday_day` SSOT.
   - Consolidated `supabase/schema.sql` into the modern 15-table baseline.
2. **Void / Delete Income Record (`void_income_record`):**
   - Implemented security-definer RPC `public.void_income_record` with atomic balance reversal and row locks.
   - Added UI delete icon in `AccountsOverviewScreen` with trilingual confirmation dialog and balance updates.
   - Passed full 3-round review pipeline (Round 1 Spec, Round 2 Break, Round 3 Fable).
3. **Deployment & Mobile Sideloading:**
   - Merged and pushed to `origin/main` (`a7e4961`), deploying backend to `budget.fmsco.com.sa`.
   - Built optimized split-ABI release APK (`29.6 MB`).
   - Sideloaded and running live on user's Samsung Galaxy (`SM_S938B`, PID `907`).

---

## 2. Issues Discovered from User's Device & Screenshots

### Issue 1: Commitments Mismatch on Dashboard (Hero Card SAR 1,162.00 vs Accounts Card SAR 3,027.00)
- **Cause:** `budget_hero_card.dart` uses `snapshot.pendingCommitments` (cycle-filtered via `CommitmentsService`). `accounts_summary_card.dart:115-132` bypassed `AccountProvider` and summed ALL bills and active installment plans across the entire database without cycle due-date filtering.
- **Fix:** Refactor `accounts_summary_card.dart` to consume `AccountProvider.operatingCashSnapshot.pendingCommitments`.

### Issue 2: Hero Card Left Until Payday (SAR 3,302.89) vs Actual Bank Cash (SAR 3,353.75)
- **Cause:** When `monthlyIncome` is passed to `PaydayOutlook.compute`, `left` is derived as `monthlyIncome - totalSpent` (8,944.54 - 5,641.65 = 3,302.89). The user manually edited their Rajhi bank account balance to 2,508.75 SAR (total cash: 3,353.75 SAR), which did not pass through `income_records`. Thus, theoretical income minus spent drifted by 50.86 SAR from physical bank balances.
- **Fix:** In `BudgetHeroCard`, when operating accounts are tracked (`s != null`), `left` must align with `s.liquidBalance` (the verified physical cash).

### Issue 3: Category Dropdown in Edit Transaction Shows Inactive Global Categories (e.g. Fuel)
- **Cause:** `edit_transaction_sheet.dart:1443` hardcoded `CategoryCatalog.pickerCodesIncluding(_selectedCategory)`, displaying all global system categories even if not active in household budgets.
- **Fix:** Scope category selection in `edit_transaction_sheet.dart` to `BudgetProvider.activeCategories`, matching `manual_expense_sheet.dart`.

---

## 3. Immediate Action Plan for Next Fresh Session
1. Read `docs/review/DASHBOARD_SYNC_AND_CATEGORY_PLAN.md`.
2. Create feature branch `fix/dashboard-sync-commitments-and-categories`.
3. Implement fixes in `accounts_summary_card.dart`, `budget_hero_card.dart`, and `edit_transaction_sheet.dart`.
4. Verify tests (`flutter analyze`, `flutter test`, `pytest`).
5. Run 3-round review pipeline (Opus 5.5 High Round 1, Round 2, and Fable High Round 3).
6. Merge and push to `main`, rebuild and sideload APK to phone.
