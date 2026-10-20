-- ----------------------------------------------------------------------------
-- Migration: 20261020005000_preflight_live_alignment.sql
-- Pre-flight for the 20261020* audit migrations. Captures the live-only
-- objects found by the read-only catalog comparison
-- (docs/review/audit/live_db_preflight.md) so a rebuild from the repository
-- matches the live project. Idempotent, and it loses no data: it only adds a
-- column when it is missing and revokes one function privilege.
--
--   1. households.rollover_rule exists on live (text, DEFAULT 'accumulate') but
--      no migration creates it. ai_service reads and writes it
--      (get_/set_household_rollover_rule) and falls back to 'send_to_savings'
--      for values it does not recognise, such as the live default. Captured
--      as it is on live; changing the default is a product decision.
--   2. public.rls_auto_enable() is the function behind the platform's
--      `ensure_rls` event trigger (it enables RLS on every new public table).
--      Live has it in public with the default EXECUTE grant to PUBLIC, so anon
--      holds EXECUTE on it (guardrail test 14). An event-trigger function
--      cannot be called directly, and the event trigger still fires after the
--      revoke (verified on the replica). The function exists only on hosted
--      projects that have the feature, so the revoke is guarded.
-- Proof: supabase/tests/14_audit_catalog_guardrails.sql (replica and rebuild)
-- ----------------------------------------------------------------------------

BEGIN;

ALTER TABLE public.households
    ADD COLUMN IF NOT EXISTS rollover_rule text DEFAULT 'accumulate';

DO $$
BEGIN
    IF to_regprocedure('public.rls_auto_enable()') IS NOT NULL THEN
        REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
    END IF;
END $$;

COMMIT;
