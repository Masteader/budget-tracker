-- ============================================================================
-- Test 48: the release on live's measured state keeps every sub-category and closes what
-- 20261026120000 opens
--
-- Migrations: 20261026120000_household_autonomous_taxonomy.sql, 20261101000100_nafaqah_wife_account_owner_guard.sql,
--             20261105000600_limit_anonymous_contact_form.sql, 20261105000700_sub_categories_household_scope.sql
--
-- run_tests.py's live scenario rebuilds the chain without the two older files, makes it look
-- like live (000500 and REVOKE TRUNCATE on inquiries done, 50 sub-category rows, no
-- household_id), snapshots the rows into rollout_check.sub_categories_before, then runs the
-- two older files and the batch. On every other build there is no snapshot and part 1 is
-- skipped.
--   1. Every row from before is still there, unchanged, once each, with a NULL household_id.
--   2. Nothing 20261026120000 opens stays open: no write or cross-household sub-category
--      policy, no anon policy on inquiries or templates, no client execute on its functions.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION '%: got %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

-- 1 ------------------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('rollout_check.sub_categories_before') IS NULL THEN
        RAISE NOTICE 'PASSED: no live snapshot on this build; part 1 skipped.';
        RETURN;
    END IF;
    PERFORM pg_temp.expect('every row is still there, unchanged',
        (SELECT count(*)::text FROM rollout_check.sub_categories_before b
         WHERE NOT EXISTS (SELECT 1 FROM public.cost_control_sub_categories s
                           WHERE s.id = b.id AND s.parent_code = b.parent_code AND s.sub_code = b.sub_code
                             AND s.name_en = b.name_en AND s.name_ar = b.name_ar)), '0');
    PERFORM pg_temp.expect('no row added or doubled',
        (SELECT count(*)::text FROM public.cost_control_sub_categories),
        (SELECT count(*)::text FROM rollout_check.sub_categories_before));
    PERFORM pg_temp.expect('old rows belong to no household',
        (SELECT count(*)::text FROM public.cost_control_sub_categories s
         JOIN rollout_check.sub_categories_before b ON b.id = s.id WHERE s.household_id IS NOT NULL), '0');
    RAISE NOTICE 'PASSED: the 50 live sub-category rows survive the release unchanged.';
END $$;

-- 2 ------------------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('no sub-category write or cross-household policy',
        (SELECT string_agg(policyname, ',' ORDER BY policyname) FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'cost_control_sub_categories'),
        'cost_control_sub_categories_select_scoped');
    PERFORM pg_temp.expect('no anon policy on inquiries or templates',
        (SELECT count(*)::text FROM pg_policies WHERE schemaname = 'public'
           AND tablename IN ('inquiries', 'cost_control_templates')
           AND NOT (roles <@ ARRAY['authenticated', 'service_role']::name[])), '0');
    PERFORM pg_temp.expect('the anon insert policy on inquiries is gone',
        (SELECT count(*)::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'inquiries'), '0');
    PERFORM pg_temp.expect('no client executes the taxonomy functions',
        (SELECT count(*)::text FROM pg_proc p CROSS JOIN (VALUES ('anon'), ('authenticated')) r(role)
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('replace_household_category', 'seed_household_default_taxonomy')
           AND has_function_privilege(r.role, p.oid, 'EXECUTE')), '0');
    RAISE NOTICE 'PASSED: what 20261026120000 opens is closed again.';
END $$;

ROLLBACK;
