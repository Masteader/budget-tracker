-- ----------------------------------------------------------------------------
-- Migration: 20261020500000_review_lock_financial_role.sql
-- Final backend review FR-B-04 (High): users.financial_role became
--   security-relevant with 20261020300000 / 20261020400000: it decides who is
--   the wife (creditor of the Nafaqah reimbursement debt), who is the husband
--   (provider, sets the allowance) and whether a household is a family at all
--   (settlement mode, /reimbursements routing). 20261019030000 left it in the
--   client-writable column list of public.users, so any member could set their
--   own row to 'spouse' (turning a roommate household into a "family" and
--   raising debts against the provider), or a wife could drop out of her own
--   ledger.
-- Fix: clients keep updating display_name and payday_day only. financial_role
--   is set by the invite RPCs (SECURITY DEFINER, unaffected) and the service
--   role. No released app build (or the web app) writes financial_role, and
--   live has no family household yet (live_db_preflight.md §4), so nothing that
--   works today stops working.
-- Idempotent (REVOKE of a privilege that is not held is a no-op) and safe on
--   live: one column privilege, no data change.
-- Proof test: supabase/tests/21_review_backend_contracts.sql
-- ----------------------------------------------------------------------------

BEGIN;

REVOKE UPDATE (financial_role) ON public.users FROM PUBLIC, anon, authenticated;

COMMENT ON COLUMN public.users.financial_role IS
    'Household financial role (provider, spouse, peer, family_member, dependent). Set by the invite RPCs / service role only; drives Nafaqah (spouse = wife) and the settlement mode.';

COMMIT;
