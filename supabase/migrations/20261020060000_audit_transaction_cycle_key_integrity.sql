-- ----------------------------------------------------------------------------
-- Migration: 20261020060000_audit_transaction_cycle_key_integrity.sql
-- Audit DB-08 (Medium): trg_populate_transaction_cycle_key (20261019080000)
--   fires only on UPDATE OF timestamp, household_id. A household member can
--   UPDATE transactions SET cycle_key = '<any>' and the forged key is kept;
--   update_budget_on_transaction_update then removes the amount from the real
--   cycle budget (spent_amount drops, overspending is hidden from the household).
-- Fix: also fire when cycle_key is assigned, so the server-derived value
--   (timestamp in Asia/Riyadh + household payday) always wins.
-- Proof test: supabase/tests/13_audit_cycle_key_integrity.sql
-- ----------------------------------------------------------------------------

BEGIN;

DROP TRIGGER IF EXISTS trg_populate_transaction_cycle_key ON public.transactions;
CREATE TRIGGER trg_populate_transaction_cycle_key
BEFORE INSERT OR UPDATE OF timestamp, household_id, cycle_key ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.populate_transaction_cycle_key();

-- No data backfill here on purpose: a stored key that differs from today's
-- derivation can also stem from a legitimate households.payday_day change, and
-- silently re-keying history would move spending between past budgets. The
-- detection query for tampered rows is in docs/review/audit/db.md (DB-08).

COMMIT;
