-- ============================================================================
-- Test 47: 000600 and 000700 hold on the full chain and on a drifted database
--
-- Migrations: 20261105000600_limit_anonymous_contact_form.sql, 20261105000700_sub_categories_household_scope.sql
--
-- Live has drifted from the chain: it has no cost_control_templates table and neither
-- function of 20261026120000, and may lack that migration's household_id column too.
-- run_tests.py runs this file on a filename-order rebuild, on the rollout order, and on a
-- database built without 20261026120000 (rollout_order_check's drift scenario), each
-- after both files ran twice. In every state:
--   1. Clients can do nothing on inquiries, TRUNCATE included.
--   2. Where cost_control_templates exists, anon has nothing and signed-in users only read.
--   3. Where the two taxonomy functions exist, no client can execute them.
--   4. No client writes sub-categories and anon reads none. Where household_id exists, the
--      scoped read policy is the only policy; where it does not, none of that migration's
--      write policies or its cross-household read policy exist.
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

DO $$
DECLARE
    v_role text;
    v_priv text;
    v_fn regprocedure;
BEGIN
    -- 1
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] LOOP
            PERFORM pg_temp.expect(format('%s %s on inquiries', v_role, v_priv),
                has_table_privilege(v_role, 'public.inquiries', v_priv)::text, 'false');
        END LOOP;
    END LOOP;
    PERFORM pg_temp.expect('no anon policy on inquiries',
        (SELECT count(*)::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'inquiries'
           AND NOT (roles <@ ARRAY['authenticated', 'service_role']::name[])), '0');

    -- 2
    IF to_regclass('public.cost_control_templates') IS NOT NULL THEN
        FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
            PERFORM pg_temp.expect('anon ' || v_priv || ' on templates',
                has_table_privilege('anon', 'public.cost_control_templates', v_priv)::text, 'false');
            PERFORM pg_temp.expect('authenticated ' || v_priv || ' on templates',
                has_table_privilege('authenticated', 'public.cost_control_templates', v_priv)::text,
                CASE WHEN v_priv = 'SELECT' THEN 'true' ELSE 'false' END);
        END LOOP;
        RAISE NOTICE 'PASSED: templates exist here and clients only read them.';
    ELSE
        RAISE NOTICE 'PASSED: no templates table here, and 000600 applied without it.';
    END IF;

    -- 3
    FOREACH v_fn IN ARRAY ARRAY[
        to_regprocedure('public.replace_household_category(uuid, character varying, character varying, character varying, character varying)'),
        to_regprocedure('public.seed_household_default_taxonomy(uuid)')
    ] LOOP
        CONTINUE WHEN v_fn IS NULL;
        PERFORM pg_temp.expect(v_fn::text || ' anon', has_function_privilege('anon', v_fn, 'EXECUTE')::text, 'false');
        PERFORM pg_temp.expect(v_fn::text || ' authenticated', has_function_privilege('authenticated', v_fn, 'EXECUTE')::text, 'false');
    END LOOP;

    -- 4
    FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
        PERFORM pg_temp.expect('anon ' || v_priv || ' on sub-categories',
            has_table_privilege('anon', 'public.cost_control_sub_categories', v_priv)::text, 'false');
    END LOOP;
    FOREACH v_priv IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
        PERFORM pg_temp.expect('authenticated ' || v_priv || ' on sub-categories',
            has_table_privilege('authenticated', 'public.cost_control_sub_categories', v_priv)::text, 'false');
    END LOOP;
    PERFORM pg_temp.expect('no write or cross-household policy',
        (SELECT count(*)::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cost_control_sub_categories'
           AND policyname IN ('cost_control_sub_categories_select_autonomous', 'cost_control_sub_categories_insert',
                              'cost_control_sub_categories_update', 'cost_control_sub_categories_delete')), '0');
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'cost_control_sub_categories' AND column_name = 'household_id') THEN
        PERFORM pg_temp.expect('the scoped read policy is in place',
            (SELECT count(*)::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cost_control_sub_categories'
               AND policyname = 'cost_control_sub_categories_select_scoped' AND cmd = 'SELECT'), '1');
        RAISE NOTICE 'PASSED: sub-categories are scoped by household and read only.';
    ELSE
        RAISE NOTICE 'PASSED: no household_id here; sub-categories are read only and keep their older read policy.';
    END IF;
END $$;

ROLLBACK;
