# IMPLEMENTATION PLAN: Database Cleanup (Remove Historical Jargon & Zombie Columns, Consolidate Schema Baseline)

**Sensitive:** yes, because database schema columns are renamed/dropped across migrations, client, and backend (transactions.raw_sms -> notes, dropping users.payday_day), and transaction ledger insertion logic is updated.

**Review Pipeline Mandate:**
- **Round 1:** Opus 5.5 high (`reviewer-spec`)
- **Round 2:** Opus 5.5 high (`reviewer-break`)
- **Round 3:** Fable high (`reviewer-fable`) (mandated by [docs/sensitive.md](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/docs/sensitive.md))

---

## 1. Architectural & Operational Context

### 1.1 Background & Root Cause
The Budget Tracker application strictly enforces a **Zero SMS Policy** ([Rule 04](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/.agents/rules/04-security-and-privacy.md)): expenses originate solely from receipt OCR photos, ZATCA Phase 2 TLV QR barcodes, interactive chat/voice entries, and manual user inputs. SMS reading/inbox scraping was eliminated in earlier architectural iterations.

However, historical artifacts remained:
1. `transactions.raw_sms` persisted as jargon for the free-text audit trail note (holding chat transcripts, receipt OCR item summaries, or manual attribution tags like `Manual: Groceries | PaidBy: ...`).
2. `users.payday_day` is an obsolete zombie column. Salary cycle calculation and budget rollover in Saudi Fintech follow [Rule 02](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/.agents/rules/02-saudi-fintech-and-islamic-compliance.md), where `households.payday_day` (defaulting to the 27th) is the sole single source of truth. Triggers like `trg_populate_transaction_cycle_key` and API services strictly query `households.payday_day`. The column on `users` is dead weight.
3. `supabase/schema.sql` was an initial 5-table prototype (`households`, `users`, `cost_control_codes`, `budgets`, `transactions`) that drifted behind 53 incremental migrations. New contributors and auditors lacked a single authoritative baseline representing the modern 15-table relational architecture.

### 1.2 User Constraint & Rollout Context
The application owner is currently the sole user of the application (~4 active accounts max across family/flatmate modes) and explicitly instructed:
> *"dont mind the current users and data in the app i am the only one using the app currently maybe around 4 accounts maks if there is implementation which fixes a root cuz then imoplement it with no need to take care of the customer. only for this tase"*

Therefore, root-cause structural cleanups (renaming `raw_sms` to `notes`, dropping `users.payday_day`) are executed cleanly across the entire stack without maintaining legacy alias bloat.

### 1.3 System Inventory of Affected Components
- **Database Migrations:**
  - `supabase/migrations/20261102000000_cleanup_database_jargon_and_zombie_columns.sql` (NEW)
  - `supabase/tests/34_cleanup_jargon_and_zombie_columns.sql` (NEW)
  - `supabase/schema.sql` (CONSOLIDATED)
  - Regression test suite updates: `18_remove_sms_artifacts.sql`, `21_review_backend_contracts.sql`, `23_fable_db_hardening.sql`, `30_wife_class_no_account.sql`, `31_wife_class_backfill.sql`, `32_wife_class_account_owner.sql`, `33_prior_spend_manual_row.sql`.
- **Backend (Python 3.11+ / FastAPI):**
  - [ai_service/supabase_client.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/supabase_client.py) (`insert_transaction`, `record_roommate_settlement`, fallback payloads)
  - [ai_service/chat_parser.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/chat_parser.py) (`commit_chat_expense`)
  - [ai_service/receipt_scanner.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/receipt_scanner.py) (`commit_receipt_expense`)
  - [ai_service/settlement_engine.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/settlement_engine.py) (`_PARTNER_TX_COLUMNS`, `audit_tag`, `_legacy_tags`)
  - [ai_service/installment_service.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/installment_service.py) (plan adjustment updates and legacy scan queries)
  - [ai_service/dedup_engine.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/dedup_engine.py) (enrichment fallbacks)
  - [ai_service/utils.py](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/utils.py) (audit note comment header)
  - 15 unit test suites in [ai_service/tests/](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/ai_service/tests/) and e2e tests in [tests/e2e/](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/tests/e2e/).
- **Frontend (Flutter / Dart):**
  - [flutter_app/lib/models/models.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/models/models.dart) (`Transaction` model: field, `fromMap`, `toMap`, `copyWith`)
  - [flutter_app/lib/models/manual_expense_row.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/models/manual_expense_row.dart) (`buildManualExpenseRow`)
  - [flutter_app/lib/models/transaction_attribution.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/models/transaction_attribution.dart) (`storedPayerRef`)
  - [flutter_app/lib/screens/home/edit_transaction_sheet.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/screens/home/edit_transaction_sheet.dart) (attribution edits and installment conversions)
  - [flutter_app/lib/screens/home/transaction_feed_screen.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/screens/home/transaction_feed_screen.dart) (CSV export mapping)
  - [flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart) (direct insert payload)
  - [flutter_app/lib/widgets/scanner/batch_item_review_sheet.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/widgets/scanner/batch_item_review_sheet.dart) (batch review insert)
  - [flutter_app/lib/widgets/transactions/manual_expense_sheet.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/widgets/transactions/manual_expense_sheet.dart) (manual insert note enrichment)
  - [flutter_app/lib/providers/recurring_bills_provider.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/providers/recurring_bills_provider.dart) (`recordBillPayment`)
  - 10 unit and widget test files in [flutter_app/test/](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/test/).

---

## 2. Test-Driven Development (TDD) Strategy & Verification

Per Rule 05 (TDD), every single phase follows the Red-Green-Refactor sequence:
1. Write database assertion tests in `34_cleanup_jargon_and_zombie_columns.sql` before running the migration.
2. In Python, run pytest to ensure tests assert against `notes` and fail if `raw_sms` is expected.
3. In Flutter, update tests to assert `'notes'` on payload maps and model fields, ensuring red state before implementation.
4. Pass all verification gates with 0 errors, 0 warnings, and 100% test success.

---

## 3. Step-by-Step Implementation Instructions

### Step 1: Write SQL Regression Test `34_cleanup_jargon_and_zombie_columns.sql`
- **File:** `supabase/tests/34_cleanup_jargon_and_zombie_columns.sql`
- **Action:** CREATE
- **TDD Test Definition (write first):**
  Verify the expected schema state post-migration:
  1. `public.transactions` has column `notes` with `data_type = 'text'`.
  2. `public.transactions` does NOT have column `raw_sms`.
  3. `public.users` does NOT have column `payday_day`.
  4. `public.households` STILL has column `payday_day` (proving the true source of truth remains untouched).
  5. `col_description('public.transactions'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'notes'))` contains `'Free-text audit note'`.
  6. Functional validation:
     - Insert a transaction row with `notes = 'TDD audit note verification'` and verify retrieval.
     - Verify an insert into `public.users` without `payday_day` succeeds.
     - Verify an insert into `public.transactions` specifying `raw_sms` fails with `undefined_column` (`42703`).

### Step 2: Implement Migration `20261102000000_cleanup_database_jargon_and_zombie_columns.sql`
- **File:** `supabase/migrations/20261102000000_cleanup_database_jargon_and_zombie_columns.sql`
- **Action:** CREATE
- **Details:**
  Use an idempotent `DO $$` block to guarantee safety on both fresh rebuilds and live environments:
  ```sql
  -- ============================================================================
  -- Migration: 20261102000000_cleanup_database_jargon_and_zombie_columns.sql
  -- 1. Remove historical jargon: rename transactions.raw_sms to notes.
  -- 2. Drop dead zombie column: users.payday_day (households.payday_day is sole SOT).
  -- ============================================================================
  BEGIN;

  DO $$
  BEGIN
      -- Rename raw_sms to notes if raw_sms exists
      IF EXISTS (
          SELECT 1 FROM information_schema.columns 
          WHERE table_schema = 'public' 
            AND table_name = 'transactions' 
            AND column_name = 'raw_sms'
      ) THEN
          ALTER TABLE public.transactions RENAME COLUMN raw_sms TO notes;
      ELSIF NOT EXISTS (
          SELECT 1 FROM information_schema.columns 
          WHERE table_schema = 'public' 
            AND table_name = 'transactions' 
            AND column_name = 'notes'
      ) THEN
          ALTER TABLE public.transactions ADD COLUMN notes TEXT;
      END IF;
  END $$;

  -- Drop dead zombie column payday_day from public.users
  ALTER TABLE public.users DROP COLUMN IF EXISTS payday_day;

  -- Re-document public.transactions.notes
  COMMENT ON COLUMN public.transactions.notes IS 
      'Free-text audit note (chat message text, receipt OCR summary, manual expense tags). The app never reads SMS.';

  COMMIT;
  ```

### Step 3: Adapt Existing SQL Test Suite for Replay Consistency
- **Files:**
  - `supabase/tests/18_remove_sms_artifacts.sql`
  - `supabase/tests/21_review_backend_contracts.sql`
  - `supabase/tests/23_fable_db_hardening.sql`
  - `supabase/tests/30_wife_class_no_account.sql`
  - `supabase/tests/31_wife_class_backfill.sql`
  - `supabase/tests/32_wife_class_account_owner.sql`
  - `supabase/tests/33_prior_spend_manual_row.sql`
- **Action:** MODIFY
- **Details:**
  Because `run_tests.py` replays the entire migration chain and executes test scripts against the resulting schema:
  - In `18_remove_sms_artifacts.sql`: Update the audit note check to test `notes` column documentation.
  - In `21_review_backend_contracts.sql`: Remove the test line `UPDATE public.users SET payday_day = 25` and update `raw_sms` to `notes` in transaction inserts.
  - In `23_fable_db_hardening.sql`: In test 5/FABLE-DB-09, remove `payday_day` from the explicit column insert:
    `INSERT INTO public.users (id, display_name, household_id, role)`.
  - In `30_wife_class_no_account.sql`, `31_wife_class_backfill.sql`, `32_wife_class_account_owner.sql`, and `33_prior_spend_manual_row.sql`: Replace column `raw_sms` with `notes` in all transaction insert statements.

### Step 4: Consolidate `supabase/schema.sql` to Modern 15-Table Baseline
- **File:** `supabase/schema.sql`
- **Action:** CONSOLIDATE / REWRITE
- **Details:**
  Consolidate `supabase/schema.sql` from its obsolete 5-table draft into the complete, authoritative 15-table baseline reflecting all architectural and security migrations to date:
  1. `public.households` (including `payday_day INT NOT NULL DEFAULT 27`, `monthly_income`, `rollover_rule`, `owner_user_id`, `household_type`, `accumulated_savings`, `last_rollover_date`, `last_rollover_amount`).
  2. `public.users` (linked to `auth.users`, with `display_name`, `household_id`, `role`, `financial_role`, `created_at` — **WITHOUT** `payday_day`).
  3. `public.cost_control_codes` (taxonomy codes, `keywords`, `is_flexible`, `household_id`, `is_system`).
  4. `public.cost_control_sub_categories` (sub-allocations, keywords, scoping).
  5. `public.cost_control_templates` (autonomous taxonomy defaults).
  6. `public.household_category_settings` (custom category enable/disable rules).
  7. `public.budgets` (monthly allocations, `spent_amount`, generated `remaining_amount`, `cycle_key`, `sub_allocations`).
  8. `public.transactions` (with `notes TEXT`, `source`, `items`, `spent_by`, `beneficiary_type`, `beneficiary_id`, `account_id`, `cycle_key`, `dedup_fingerprint`, `qr_code_raw`, `nafaqah_class`, `nafaqah_spouse_id`, `is_settlement`, `settlement_target_id`, `line_items` — **NO** `raw_sms`).
  9. `public.accounts` (checking, bank, wallet, cash, savings, `balance`, `currency`, `is_active`, `is_archived`, `color_hex`, `icon_name`).
  10. `public.account_transfers` (transfers between liquid accounts with fee and timestamps).
  11. `public.income_records` (salary, bonus, overtime, deduction components linked to cycles and accounts).
  12. `public.installment_plans` (BNPL providers Tabby/Tamara, counts, monthly amount, `next_due_at`, `frequency`).
  13. `public.household_dependents` (manual members/dependents, avatar, relationship, `monthly_allowance`, `linked_user_id`).
  14. `public.household_invites` (secure 8-char invite codes, creator/used_by cascades, expiration).
  15. `public.household_memberships` (user to household mappings, `financial_role`).
  - Secondary tables included: `member_allowances`, `spouse_reimbursements`, `api_quota`, `invite_attempt_log`, `inquiries`.
  - Include all active RLS policies, helper functions (`get_auth_user_household_id`, `reallocate_budget`, `create_household_and_claim`, `join_household_by_code`), triggers, and publication bindings.

### Step 5: Backend Updates in `ai_service/`
- **Files & Changes:**
  1. `ai_service/supabase_client.py`:
     - In `insert_transaction(...)`:
       - Update parameter: change `raw_sms: str` to `notes: str`. To maintain backwards compatibility during any transition, accept `notes: Optional[str] = None` and `raw_sms: Optional[str] = None`, assigning `resolved_notes = notes if notes is not None else (raw_sms or "")`.
       - Update `match_sub_category` keyword invocation: `f"{merchant} {resolved_notes}"`.
       - Update `payload` and `base_payload`: `"notes": resolved_notes` (remove `"raw_sms"`).
     - In `record_roommate_settlement(...)`:
       - In `tx_data`: change `"raw_sms": audit` to `"notes": audit`.
       - Update docstrings referencing `raw_sms`.
  2. `ai_service/chat_parser.py`:
     - Line 1201: pass `notes=audit_text` to `insert_transaction`.
  3. `ai_service/receipt_scanner.py`:
     - Line 1050: pass `notes=audit_text` to `insert_transaction`.
  4. `ai_service/settlement_engine.py`:
     - Update `_PARTNER_TX_COLUMNS`, `_PARTNER_TX_COLUMNS_PRE_NAFAQAH`, `_V2_TX_COLUMNS`: replace `raw_sms` with `notes`.
     - Update `audit_tag(notes: Any, tag: str)` and `_legacy_tags(notes: Any)` signatures.
     - When reading transaction rows, check `tx.get("notes") or tx.get("raw_sms") or ""` for robust fallback.
  5. `ai_service/installment_service.py`:
     - In `convert_to_installment_plan`: `.select("notes, household_id")`.
     - Read base note: `re.sub(..., tx.data.get("notes") or tx.data.get("raw_sms") or "")`.
     - Update payload: `"notes": notes`.
     - In `backfill_legacy_installments`: `.select("id, household_id, merchant, amount, notes, category_code, timestamp")` and search `tx.get("notes") or tx.get("raw_sms")`.
  6. `ai_service/dedup_engine.py`:
     - In `enrich_transaction_items`: `.select("notes")` and `.update({"notes": enriched_note})`.
  7. `ai_service/utils.py`:
     - Update header comment to `# ─── Audit notes (transactions.notes) ─────────────────────────────────────────`.
  8. `ai_service/tests/`:
     - Update test files asserting or providing `raw_sms` to use `notes`:
       - `test_api_audit.py`
       - `test_chat_account_balance.py`
       - `test_fable_attribution.py`
       - `test_final_review_backend.py`
       - `test_financial_enhancements.py`
       - `test_household_permissions.py`
       - `test_installment_service.py`
       - `test_nafaqah.py`
       - `test_product_budget_recalc.py`
       - `test_salary_cycle_riyadh.py`
       - `test_settlement_dependents.py`
       - `test_sms_removal.py` (update `raw_sms="note"` -> `notes="note"`)
       - `test_taxonomy_and_bnpl.py`
       - `test_unknown_category_code.py`
       - `test_wife_class_account_strip.py`
  9. `tests/e2e/`:
     - Update `test_08_fable_api_fixes.py`, `test_09_fable2_api_fixes.py`, `test_10_taxonomy_and_bnpl.py` to query and assert on `notes`.

### Step 6: Frontend Updates in `flutter_app/`
- **Files & Changes:**
  1. `lib/models/models.dart`:
     - In `class Transaction`:
       - Replace `final String? rawSms;` with `final String? notes;`.
       - Add backward-compatibility getter: `String? get rawSms => notes;`.
       - In constructor: `this.notes,` (deprecate/remove `this.rawSms`).
       - In `Transaction.fromMap`:
         `final raw = (map['notes'] as String?) ?? (map['raw_sms'] as String?) ?? '';`
         and parse `notes: raw`.
       - In `Transaction.toMap`:
         `'notes': notes,`
       - In `Transaction.copyWith`:
         `String? notes,`
  2. `lib/models/manual_expense_row.dart`:
     - Line 54: change `'raw_sms'` to `'notes'`.
     - Update library docstring comment.
  3. `lib/models/transaction_attribution.dart`:
     - Line 153: `final raw = (row['notes'] as String?) ?? (row['raw_sms'] as String?) ?? '';`.
  4. `lib/providers/recurring_bills_provider.dart`:
     - Line 131: change `'raw_sms'` to `'notes'`.
  5. `lib/screens/home/edit_transaction_sheet.dart`:
     - Line 373: change `'raw_sms'` to `'notes'`, referencing `auditNoteHead(widget.transaction.notes, ...)`.
     - Line 1112: update transactions table with `'notes': updatedNotes`.
  6. `lib/screens/home/transaction_feed_screen.dart`:
     - Line 746: export `'notes': t.notes`.
  7. `lib/screens/scanner/receipt_scanner_sheet.dart`:
     - Line 1055: change `'raw_sms'` to `'notes'`.
  8. `lib/widgets/scanner/batch_item_review_sheet.dart`:
     - Line 274: change `'raw_sms'` to `'notes'`.
  9. `lib/widgets/transactions/manual_expense_sheet.dart`:
     - Line 568-569: read `row['notes'] ?? row['raw_sms']` and assign `row['notes'] = '$currentNotes$noteSuffix'`.
  10. `flutter_app/test/`:
      - Update test fixtures and expectations across:
        - `test/models/manual_expense_row_test.dart`
        - `test/models/models_dependents_test.dart`
        - `test/models/transaction_attribution_test.dart`
        - `test/models/transaction_source_test.dart`
        - `test/providers/recurring_bills_provider_test.dart`
        - `test/providers/transaction_undo_restore_test.dart`
        - `test/services/client_config_test.dart`
        - `test/widgets/edit_transaction_attribution_test.dart`
        - `test/widgets/edit_transaction_sheet_test.dart`
        - `test/widgets/nafaqah_classifier_rule_test.dart`

---

## 4. Verification Gates & Execution Commands

Every gate must pass cleanly without warning or error:

### Gate 1: Flutter Static Analysis
```powershell
Set-Location flutter_app
flutter analyze
```
*Acceptance criterion:* `No issues found!` (0 errors, 0 warnings, 0 lints).

### Gate 2: Flutter Test Suite
```powershell
Set-Location flutter_app
flutter test
```
*Acceptance criterion:* All tests pass (100% success rate, 0 failures).

### Gate 3: Python Backend Test Suite
```powershell
Set-Location ai_service
.venv\Scripts\pytest -v
```
*Acceptance criterion:* All 1100+ tests pass (0 failures, 0 errors).

### Gate 4: Database Catalog & Migration Assertions
Verify SQL test `34_cleanup_jargon_and_zombie_columns.sql` executes and passes:
- `raw_sms` does not exist on `transactions`.
- `notes` exists on `transactions` with type `text`.
- `payday_day` does not exist on `users`.
- `payday_day` exists on `households`.

---

## 5. Multi-Round Review Pipeline Execution Plan

Because this change alters database schema columns, drops a user column, and touches money ledger insertion logic, it is classified as **SENSITIVE** under [docs/sensitive.md](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/docs/sensitive.md).

The review pipeline will proceed through three formal rounds:

1. **Round 1: Opus 5.5 high (`reviewer-spec`)**
   - **Focus:** Complete spec compliance, schema alignment with consolidated baseline, zero references to SMS, and complete TDD coverage across Python and Flutter suites.
   - **Deliverable:** Spec compliance verdict and gap analysis.

2. **Round 2: Opus 5.5 high (`reviewer-break`)**
   - **Focus:** Adversarial edge-case analysis. What breaks if offline queue replays an old cached transaction? Does any PostgREST select query fail? Are there lingering `raw_sms` column privileges or checks?
   - **Deliverable:** Stress-test findings and resilience confirmation.

3. **Round 3: Fable high (`reviewer-fable`)**
   - **Focus:** Mandatory sensitive path audit. Verification of zero data loss, ledger accuracy, single source of truth for `households.payday_day`, Saudi salary cycle parity, and Nafaqah Islamic compliance boundaries.
   - **Deliverable:** Final safety verdict and sign-off recommendation.
