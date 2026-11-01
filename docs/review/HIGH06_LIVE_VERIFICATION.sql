-- ============================================================================
-- READ-ONLY. Owner runs after AUDIT VERDICT: APPROVED and before merging feat/provider-sot-operating-cash to main.
--
-- Verification script for HIGH-06: Live Supabase Schema & Constraint Integrity
-- This script contains ONLY read-only introspection queries. It performs NO modifications.
-- ============================================================================

-- 1. Verify schema migrations applied for nafaqah wife class guards
SELECT version, inserted_at
  FROM supabase_migrations.schema_migrations
 WHERE version LIKE '20261101%'
 ORDER BY 1;
-- Expected output:
-- 20261101000000
-- 20261101000100

-- 2. Verify triggers on public.transactions
-- Ensures trg_enforce_wife_class_account and trg_update_account_balance_on_transaction are enabled (tgenabled = 'O')
SELECT tgname, tgenabled, tgtype
  FROM pg_trigger
 WHERE tgrelid = 'public.transactions'::regclass
   AND NOT tgisinternal
 ORDER BY tgname;
-- Expected triggers include:
-- trg_enforce_wife_class_account (BEFORE INSERT OR UPDATE)
-- trg_populate_transaction_cycle_key (BEFORE INSERT OR UPDATE)
-- trg_update_account_balance_on_transaction (AFTER INSERT OR UPDATE OR DELETE)
-- update_budget_on_transaction_trigger (AFTER INSERT OR UPDATE OR DELETE)

-- 3. Verify constraints on public.transactions
SELECT conname, pg_get_constraintdef(oid) AS definition
  FROM pg_constraint
 WHERE conrelid = 'public.transactions'::regclass
 ORDER BY conname;
-- Expected constraints include:
-- transactions_source_check: CHECK (source IN ('chat', 'receipt_scan', 'manual'))
-- Note: rigid CHECK transactions_wife_class_no_account was replaced by dynamic trigger trg_enforce_wife_class_account

-- 4. Verify function security & pinned search_path for guard functions
SELECT proname, prosecdef, proconfig
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN ('enforce_wife_class_account', 'update_account_balance_on_transaction')
 ORDER BY proname;
-- Expected:
-- prosecdef = true (SECURITY DEFINER)
-- proconfig = {search_path=public, pg_temp} (pinned search_path)
