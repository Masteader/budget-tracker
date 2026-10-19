-- ----------------------------------------------------------------------------
-- Migration: 20261020040000_audit_cost_control_codes_policies.sql
-- Audit DB-04 (High): cost_control_codes_insert / _update (role PUBLIC, from
--   20261011_hybrid_category_lifecycle.sql) only required
--   "household_id IS NOT NULL AND is_system = false". anon and any authenticated
--   user could insert categories into any household's taxonomy (UI pollution and
--   squatting on (household_id, code) so the victim cannot create that code),
--   and move their own custom categories into another household. SEC-01/02 only
--   fixed the SELECT policy.
-- Fix: writes restricted to admins of the caller's active household, for
--   non-system rows of that household; no client DELETE (taxonomy rows are
--   deactivated via household_category_settings); anon loses all privileges.
--   ai_service writes with the service role and is unaffected.
-- Proof test: supabase/tests/11_audit_cost_control_codes_policies.sql
-- ----------------------------------------------------------------------------

BEGIN;

DROP POLICY IF EXISTS cost_control_codes_insert ON public.cost_control_codes;
DROP POLICY IF EXISTS cost_control_codes_update ON public.cost_control_codes;
DROP POLICY IF EXISTS cost_control_codes_delete ON public.cost_control_codes;

CREATE POLICY cost_control_codes_insert ON public.cost_control_codes
    FOR INSERT
    TO authenticated
    WITH CHECK (
        is_system = false
        AND household_id IS NOT NULL
        AND household_id = (SELECT public.get_auth_user_household_id())
        AND (SELECT public.get_auth_user_role()) = 'admin'
    );

CREATE POLICY cost_control_codes_update ON public.cost_control_codes
    FOR UPDATE
    TO authenticated
    USING (
        is_system = false
        AND household_id IS NOT NULL
        AND household_id = (SELECT public.get_auth_user_household_id())
        AND (SELECT public.get_auth_user_role()) = 'admin'
    )
    WITH CHECK (
        is_system = false
        AND household_id IS NOT NULL
        AND household_id = (SELECT public.get_auth_user_household_id())
        AND (SELECT public.get_auth_user_role()) = 'admin'
    );

REVOKE ALL ON public.cost_control_codes FROM anon;
REVOKE DELETE, TRUNCATE ON public.cost_control_codes FROM authenticated;

COMMIT;
