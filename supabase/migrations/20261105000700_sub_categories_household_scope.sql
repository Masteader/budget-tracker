-- ============================================================================
-- Migration: 20261105000700_sub_categories_household_scope.sql
--
-- 20261026120000 replaced the E2E-05 rule of 20261020600000 with "household_id IS NULL
-- OR my household", and gave clients direct writes. Test 22 forbids both.
--
-- Reads: every row created before that migration has a NULL household_id, so a custom
-- category's sub-categories, with the names a household chose, became readable by every
-- signed-in user. Now a signed-in user reads:
--   * rows of their active household;
--   * NULL-household rows under a custom category of their active household;
--   * NULL-household rows under a system category, which are the seeded catalog, except
--     those with a 'sub-' code. Only the API makes that code, from a name someone typed,
--     and none of the 46 seeded rows has it, so those old rows stay with the service role.
--
-- Writes: no client writes this table. The app adds, renames and deletes through
-- ai_service (ApiService.addSubCategory), which uses the service role. The only direct
-- client access is one read in sub_budget_allocation_dialog.dart. So the write policies
-- and grants go, and the service role keeps everything.
--
-- Live has drifted from the chain and may not have 20261026120000, so may not have the
-- household_id column. Without it there is no cross-household rule to replace and no write
-- policy from that migration: the read policy is created only where the column exists, and
-- whatever read policy the database has otherwise stays. The grants below apply either way.
-- Safe to run again.
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS cost_control_sub_categories_select_autonomous ON public.cost_control_sub_categories;
DROP POLICY IF EXISTS cost_control_sub_categories_insert ON public.cost_control_sub_categories;
DROP POLICY IF EXISTS cost_control_sub_categories_update ON public.cost_control_sub_categories;
DROP POLICY IF EXISTS cost_control_sub_categories_delete ON public.cost_control_sub_categories;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'cost_control_sub_categories'
                 AND column_name = 'household_id') THEN
        EXECUTE 'DROP POLICY IF EXISTS cost_control_sub_categories_select_scoped ON public.cost_control_sub_categories';
        EXECUTE $policy$
            CREATE POLICY cost_control_sub_categories_select_scoped ON public.cost_control_sub_categories
                FOR SELECT
                TO authenticated
                USING (
                    household_id = (SELECT public.get_auth_user_household_id())
                    OR (
                        household_id IS NULL
                        AND EXISTS (
                            SELECT 1
                            FROM public.cost_control_codes c
                            WHERE c.code = cost_control_sub_categories.parent_code
                              AND (c.household_id = (SELECT public.get_auth_user_household_id())
                                   OR (c.household_id IS NULL
                                       AND cost_control_sub_categories.sub_code NOT LIKE 'sub-%'))
                        )
                    )
                )
        $policy$;
    ELSE
        RAISE NOTICE 'cost_control_sub_categories has no household_id here: its read policy is left as it is';
    END IF;
END $$;

REVOKE ALL ON public.cost_control_sub_categories FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.cost_control_sub_categories FROM authenticated;
GRANT SELECT ON public.cost_control_sub_categories TO authenticated;
GRANT ALL ON public.cost_control_sub_categories TO service_role;

COMMIT;
