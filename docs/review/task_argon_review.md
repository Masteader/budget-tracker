# TASK: Review and Validate External Audit Findings from Gemini-Argon-High

You are Claude Opus 5.5, Lead Architect and Auditor for Budget Tracker.
Gemini-Argon-High performed an external audit on branch `feat/provider-sot-operating-cash` (@ commit `af353b8`) and reported the following 6 Critical/High issues with a verdict of `REVISE`.

Evaluate each of these 6 findings against:
- `.agents/rules/01-architecture-and-tech-stack.md`
- `.agents/rules/02-saudi-fintech-and-islamic-compliance.md`
- `.agents/rules/03-ui-ux-and-design-system.md`
- `.agents/rules/04-security-and-privacy.md`
- `.agents/rules/05-code-quality-and-testing.md`
- `.agents/rules/06-pr-and-audit-pipeline.md`

Validate whether each finding is sound and correct, refine the exact implementation steps if needed, and produce a surgical execution plan for Antigravity (Gemini 3.8 Flash High) to execute.

---

### External Lead Architect Audit (`feat/provider-sot-operating-cash` @ `af353b8`)
**Verdict:** `REVISE` — Fix 6 Critical/High Issues Before Merge

Resolve the following 6 issues on `feat/provider-sot-operating-cash` using TDD (Rule 05):

#### 1. `CRITICAL-01` — Fix `BudgetHeroCard` Hardcoded `pendingCommitments: 0` (`flutter_app/lib/widgets/dashboard/budget_hero_card.dart`)
- On lines 88–96 of `budget_hero_card.dart`, `PaydayOutlook.compute` is called with `pendingCommitments: 0` and `operatingCash: effectiveOperatingCash` (`snapshot.operatingCash`, which already subtracted `pendingCommitments`).
- This breaks `outlook.safeDaily` (`SAR X a day until payday`) whenever `monthlyIncome` is set (because `pendingCommitments: 0` ignores all unpaid bills/installments when computing daily safe spend), and double-subtracts or misaligns `outlook.left` vs `_HeroCommitmentsTip` when `monthlyIncome` is null.
- **Fix:**
  - Pass `operatingCash: s != null ? s.liquidBalance : operatingCash` and `pendingCommitments: effectiveCommitments` into `PaydayOutlook.compute(...)`.
  - In `_HeroCommitmentsTip` (line 251), pass `actualAvailable: outlook.left - effectiveCommitments` so the "After commitments" pill is always `LeftUntilPayday - Commitments` and `safeDaily` is `(LeftUntilPayday - Commitments) / daysLeft`.

#### 2. `CRITICAL-02` — Keep `Operating Cash (Remaining)` Synchronized Across Dashboard, Accounts, and Budgets (`flutter_app/lib/screens/home/budget_management_screen.dart`)
- On `BudgetManagementScreen` (lines 1476–1482), `displayOperatingCash` was bound to `snapshot.operatingCash` (`liquidBalance - pendingCommitments`). Because the user already allocates budget categories for bills (`Utilities & Bills`) on `BudgetManagementScreen`, subtracting `pendingCommitments` there double-counts bills and makes `BudgetManagementScreen` Row 2 (`2,208.26`) disagree with `AccountsOverviewScreen` (`6,370.26`) and `BudgetHeroCard` (`6,370.26`).
- **Fix:**
  - In `budget_management_screen.dart`, bind `displayOperatingCash` (Row 2) to `snapshot.liquidBalance` (when `isCurrentCycle && accountProvider.hasLoaded`), and use `snapshot.liquidBalance + totalSpent` for fallback `cycleFunding` when `verifiedCycleIncome <= 0`.

#### 3. `CRITICAL-03` — Fix PostgreSQL `23514` Check Constraint Crash in `buildPriorSpendRow` (`flutter_app/lib/screens/home/budget_management_screen.dart`)
- In `BudgetManagementScreen.buildPriorSpendRow` (lines 69–96), setting `row['source'] = 'prior_adjustment'` violates the PostgreSQL `transactions_source_check` constraint (`source IN ('chat', 'receipt_scan', 'manual')`). Also, `row.remove('cycle_key')` drops the cycle key passed to `_showPriorSpendingDialog`.
- Note that `AccountService.reconcileUnlinkedTransactions` (`account_service.dart:352`) ALREADY filters `.inFilter('source', ['chat', 'receipt_scan'])`, so `'manual'` rows with `account_id: null` are already excluded from auto-linking!
- **Fix:** Keep `row['source'] = 'manual'` (do NOT set `'prior_adjustment'`), keep `account_id: null`, and accept/preserve `cycleKey` (`YYYY-MM`) in `buildPriorSpendRow`. Update the unit tests in `budget_management_sync_math_test.dart` and `account_service_reconcile_test.dart` accordingly.

#### 4. `CRITICAL-04` — Resolve Authorized Default Debitable `account_id` on the Backend & Fix Client Refresh Order (`ai_service/supabase_client.py`, `chat_parser.py`, `receipt_scanner.py`, `chat_entry_screen.dart`)
- When a husband/admin logs a chat or receipt expense without explicitly sending `account_id` in the payload, leaving `account_id = None` on the server causes `trg_update_account_balance_on_transaction` not to fire, and in `ChatEntryScreen` `_refreshGlobalProviders()` runs *before* `unawaited(reconcileUnlinkedTransactions(...))`.
- **Fix:**
  - Create a helper `resolve_default_debitable_account(household_id, user_id, category_code, nafaqah_class)` in `ai_service/supabase_client.py`:
    - If `nafaqah_class in ("wife_personal", "wife_reimbursable")` or `not user_id`, return `None`.
    - Otherwise, check active budget's `account_id` for `category_code`, or the household's non-archived operating pool account (`is_shared_pool` or owned by `user_id`), and return it **only if** `assert_account_debitable(household_id, user_id, candidate_id)` succeeds (catching `ForbiddenAccountError` and returning `None` for non-admin members who cannot debit the shared pool).
  - Use this fallback in `process_chat_transaction` and `process_receipt_scan` on commit (`preview_only=False`) when `stored_account_id is None`.
  - In `ChatEntryScreen` (`chat_entry_screen.dart:530, 695`), `await AccountService.instance.reconcileUnlinkedTransactions(...)` BEFORE calling `_refreshGlobalProviders()`.

#### 5. `HIGH-05` — Fix Biweekly Installment Counting in `CommitmentsService` (`flutter_app/lib/services/commitments_service.dart`)
- In `getPendingCommitments` (lines 88–118), `if (plan.nextDueAt != null)` only emits a single `PendingCommitment` and skips `plan.dueDates(...)`, which under-counts `biweekly` Tabby/Tamara plans that have 2 due dates in the current salary cycle.
- **Fix:** When `plan.frequency.toLowerCase() == 'biweekly'`, generate the remaining due dates in the cycle via `plan.dueDates(...)` (rolling any overdue `nextDueAt` into `cycleKey`) so all unpaid biweekly installments due within `cycleKey` are included.

#### 6. `HIGH-06` — Verify & Apply Pending SQL Migrations on Live Supabase via MCP
- Check whether `supabase/migrations/20261101000000_nafaqah_wife_no_account.sql` and `supabase/migrations/20261101000100_nafaqah_wife_account_owner_guard.sql` (and `trg_update_account_balance_on_transaction`) are applied on the live Supabase database. If not yet applied, apply them in order and verify the trigger and constraints pass.

