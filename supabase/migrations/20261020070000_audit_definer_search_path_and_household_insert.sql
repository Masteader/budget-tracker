-- ----------------------------------------------------------------------------
-- Migration: 20261020070000_audit_definer_search_path_and_household_insert.sql
-- Audit DB-09 (Low): sync_user_household_membership() (20261018) is SECURITY
--   DEFINER without a pinned search_path, so it resolves unqualified objects
--   (operators, casts, functions) through the caller's search_path.
-- Audit DB-10 (Low): households_insert_authenticated allows any authenticated
--   client to INSERT households directly, bypassing create_household_and_claim
--   (5-household quota, server-generated 16-hex invite code). The invite_code
--   UNIQUE violation doubles as an un-rate-limited existence oracle for other
--   households' static join codes. No client inserts households directly
--   (Flutter/ai_service use the RPC or the service role).
-- Proof test: supabase/tests/14_audit_catalog_guardrails.sql
-- ----------------------------------------------------------------------------

BEGIN;

ALTER FUNCTION public.sync_user_household_membership() SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.sync_user_household_membership() FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS households_insert_authenticated ON public.households;
REVOKE INSERT, DELETE, TRUNCATE ON public.households FROM anon, authenticated;
REVOKE ALL ON public.households FROM anon;

COMMIT;
