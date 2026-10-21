-- ----------------------------------------------------------------------------
-- Migration: 20261020600000_e2e_helper_rpcs_and_sub_category_visibility.sql
--
-- E2E-04 (Low, docs/review/audit/e2e_results.md): the SECURITY DEFINER helpers
--   household_primary_admin_id(uuid)          (20261020400000)
--   nafaqah_husband_id(uuid)                  (20261020300000, replaced in 20261020400000)
--   nafaqah_is_spouse_member(uuid, uuid)      (20261020300000)
-- were EXECUTE-able by every authenticated user through PostgREST
-- (POST /rest/v1/rpc/...). They take any household id and have no membership
-- check, so any signed-in user could read another household's primary-admin
-- or husband user id, and probe whether a user is the wife of a household.
--
-- Fix: EXECUTE is revoked from PUBLIC, anon and authenticated; service_role
-- keeps it. Every caller is internal and runs as the function owner:
--   * household_primary_admin_id: protect_primary_admin_membership() (trigger),
--     get_household_members, promote_member_to_admin, revoke_admin, remove_member
--   * nafaqah_husband_id: set_member_allowance, get_spouse_reimbursement_balance,
--     record_spouse_reimbursement
--   * nafaqah_is_spouse_member: validate_transaction_nafaqah_class() (trigger),
--     get_member_allowance_status, set_member_allowance,
--     get_spouse_reimbursement_balance, record_spouse_reimbursement
-- All of them are SECURITY DEFINER functions owned by postgres (the helpers'
-- owner), so they keep working for authenticated callers. No RLS policy, view,
-- column default or CHECK constraint references the helpers, and no client
-- calls them: ai_service, the Flutter app and the web app (current branch and
-- origin/main) never .rpc() them. The guard below re-checks this on the target
-- database and aborts the migration (rolling everything back) if it is wrong.
--
-- E2E-05 (Medium, listing half): cost_control_sub_categories has no
-- household_id, and its SELECT policy was USING (true): any signed-in user
-- could read another household's custom sub-categories (custom parent codes are
-- guessable CUSTOM-...). Sub-category rows are now readable only when their
-- parent category is readable, i.e. the same rule as cost_control_codes_select:
-- a global/system code, or a code of the caller's active household. The deployed
-- app (origin/main, sub_budget_allocation_dialog.dart) reads this table directly
-- only by parent_code of a category of its own active household, which stays
-- visible; it never writes it (writes go through ai_service with the service
-- role, which bypasses RLS). Client write privileges, never usable under RLS
-- (no write policy), and every anon privilege are revoked.
--
-- Idempotent (REVOKE/GRANT, DROP POLICY IF EXISTS + CREATE POLICY), no data
-- change, no schema change. Rollback: see the end of this file.
-- Proof test: supabase/tests/22_e2e_helper_rpcs_and_sub_category_visibility.sql
-- ----------------------------------------------------------------------------

BEGIN;

-- A. E2E-04: internal helpers are not client-callable --------------------------

DO $$
DECLARE
    v_bad text;
BEGIN
    -- No policy may depend on the helpers: policies run as the invoking role.
    SELECT string_agg(format('%I.%I.%I', schemaname, tablename, policyname), ', ') INTO v_bad
    FROM pg_policies
    WHERE coalesce(qual, '') || ' ' || coalesce(with_check, '')
          ~ '(household_primary_admin_id|nafaqah_husband_id|nafaqah_is_spouse_member)';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'E2E-04 guard: policies call the helpers (%); revoking EXECUTE would break RLS', v_bad;
    END IF;

    -- Every function calling a helper must be SECURITY DEFINER and owned by a role
    -- that keeps EXECUTE on it (the owner of the helpers).
    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc p
    WHERE p.prosrc ~ '(household_primary_admin_id|nafaqah_husband_id|nafaqah_is_spouse_member)'
      AND p.oid NOT IN ('public.household_primary_admin_id(uuid)'::regprocedure,
                        'public.nafaqah_husband_id(uuid)'::regprocedure,
                        'public.nafaqah_is_spouse_member(uuid, uuid)'::regprocedure)
      AND (NOT p.prosecdef
           OR p.proowner IS DISTINCT FROM (SELECT proowner FROM pg_proc
                                           WHERE oid = 'public.nafaqah_is_spouse_member(uuid, uuid)'::regprocedure)
           OR p.proowner IS DISTINCT FROM (SELECT proowner FROM pg_proc
                                           WHERE oid = 'public.nafaqah_husband_id(uuid)'::regprocedure)
           OR p.proowner IS DISTINCT FROM (SELECT proowner FROM pg_proc
                                           WHERE oid = 'public.household_primary_admin_id(uuid)'::regprocedure));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'E2E-04 guard: invoker or foreign-owned callers of the helpers (%)', v_bad;
    END IF;

    -- No view or constraint may depend on them either.
    SELECT string_agg(format('%I.%I', schemaname, viewname), ', ') INTO v_bad
    FROM pg_views
    WHERE definition ~ '(household_primary_admin_id|nafaqah_husband_id|nafaqah_is_spouse_member)';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'E2E-04 guard: views call the helpers (%)', v_bad;
    END IF;
    SELECT string_agg(conname, ', ') INTO v_bad
    FROM pg_constraint
    WHERE contype = 'c'
      AND pg_get_constraintdef(oid) ~ '(household_primary_admin_id|nafaqah_husband_id|nafaqah_is_spouse_member)';
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'E2E-04 guard: CHECK constraints call the helpers (%)', v_bad;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.household_primary_admin_id(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.nafaqah_husband_id(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.nafaqah_is_spouse_member(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.household_primary_admin_id(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.nafaqah_husband_id(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.nafaqah_is_spouse_member(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.household_primary_admin_id(uuid) IS
    'Internal: primary admin of a household. Not client-callable (E2E-04); used by SECURITY DEFINER functions.';
COMMENT ON FUNCTION public.nafaqah_husband_id(uuid) IS
    'Internal: Nafaqah provider of a family household. Not client-callable (E2E-04); used by SECURITY DEFINER functions.';
COMMENT ON FUNCTION public.nafaqah_is_spouse_member(uuid, uuid) IS
    'Internal: is the user a spouse member of the household. Not client-callable (E2E-04); used by SECURITY DEFINER functions.';

-- B. E2E-05: sub-category rows follow their parent category's visibility --------

ALTER TABLE public.cost_control_sub_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cost_control_sub_categories_select_all ON public.cost_control_sub_categories;
DROP POLICY IF EXISTS cost_control_sub_categories_select_visible_parent ON public.cost_control_sub_categories;

CREATE POLICY cost_control_sub_categories_select_visible_parent ON public.cost_control_sub_categories
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.cost_control_codes c
            WHERE c.code = cost_control_sub_categories.parent_code
              AND (c.household_id IS NULL
                   OR c.household_id = (SELECT public.get_auth_user_household_id()))
        )
    );

REVOKE ALL ON public.cost_control_sub_categories FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.cost_control_sub_categories FROM authenticated;
GRANT SELECT ON public.cost_control_sub_categories TO authenticated;
GRANT ALL ON public.cost_control_sub_categories TO service_role;

COMMIT;

-- Rollback (restores the previous, leaky behaviour; run only if this migration
-- must be undone):
--   BEGIN;
--   GRANT EXECUTE ON FUNCTION public.household_primary_admin_id(uuid) TO authenticated;
--   GRANT EXECUTE ON FUNCTION public.nafaqah_husband_id(uuid) TO authenticated;
--   GRANT EXECUTE ON FUNCTION public.nafaqah_is_spouse_member(uuid, uuid) TO authenticated;
--   DROP POLICY IF EXISTS cost_control_sub_categories_select_visible_parent ON public.cost_control_sub_categories;
--   CREATE POLICY cost_control_sub_categories_select_all ON public.cost_control_sub_categories
--       FOR SELECT TO authenticated USING (true);
--   GRANT ALL ON public.cost_control_sub_categories TO anon, authenticated;
--   COMMIT;
