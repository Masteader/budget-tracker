-- ============================================================================
-- Test 42: anonymous and client access to the contact form and the template catalog
--
-- Migration: 20261105000600_limit_anonymous_contact_form.sql
--
-- The public form posts to POST /public/inquiries, and ai_service writes the row with
-- the service role. No client talks to public.inquiries. Tests 14 and 23 are the
-- guardrails that caught this; this one says what each role can still do.
--
-- Verifies:
--   1. anon can do nothing on inquiries or cost_control_templates.
--   2. authenticated can do nothing on inquiries and can only read the templates.
--   3. No client can execute replace_household_category or
--      seed_household_default_taxonomy; the service role can.
--   4. seed_household_default_taxonomy can no longer write into someone else's household.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.run_as(p_role text, p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
BEGIN
    PERFORM set_config('request.jwt.claims',
        CASE WHEN p_sub IS NULL THEN json_build_object('role', p_role)::text
             ELSE json_build_object('sub', p_sub, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.run_as(text, text, text) TO PUBLIC;

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

-- 1, 2. Tables --------------------------------------------------------------------------
DO $$
DECLARE
    v_user text := 'e4200000-0000-0000-0000-00000000000a';
    v_priv text;
BEGIN
    FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] LOOP
        IF has_table_privilege('anon', 'public.inquiries', v_priv)
           OR has_table_privilege('authenticated', 'public.inquiries', v_priv)
           OR has_table_privilege('anon', 'public.cost_control_templates', v_priv) THEN
            RAISE EXCEPTION 'VULNERABILITY: a client role holds % on inquiries or anon on templates', v_priv;
        END IF;
        IF v_priv <> 'SELECT' AND has_table_privilege('authenticated', 'public.cost_control_templates', v_priv) THEN
            RAISE EXCEPTION 'VULNERABILITY: authenticated holds % on cost_control_templates', v_priv;
        END IF;
    END LOOP;

    PERFORM pg_temp.expect('anon reads inquiries', pg_temp.run_as('anon', NULL, 'SELECT count(*)::text FROM public.inquiries'), 'ERR:42501');
    PERFORM pg_temp.expect('anon inserts an inquiry',
        pg_temp.run_as('anon', NULL, $q$INSERT INTO public.inquiries (type, email, reference) VALUES ('contact', 'a@test.local', 'T42-1')$q$), 'ERR:42501');
    PERFORM pg_temp.expect('authenticated inserts an inquiry',
        pg_temp.run_as('authenticated', v_user, $q$INSERT INTO public.inquiries (type, email, reference) VALUES ('contact', 'a@test.local', 'T42-2')$q$), 'ERR:42501');
    PERFORM pg_temp.expect('anon reads templates', pg_temp.run_as('anon', NULL, 'SELECT count(*)::text FROM public.cost_control_templates'), 'ERR:42501');
    IF pg_temp.run_as('authenticated', v_user, 'SELECT count(*)::text FROM public.cost_control_templates')::int < 7 THEN
        RAISE EXCEPTION 'REGRESSION: authenticated cannot read the template catalog';
    END IF;
    PERFORM pg_temp.expect('authenticated edits a template',
        pg_temp.run_as('authenticated', v_user, $q$UPDATE public.cost_control_templates SET default_name_en = 'x'$q$), 'ERR:42501');

    -- ai_service keeps working.
    PERFORM pg_temp.expect('service role stores an inquiry',
        pg_temp.run_as('service_role', NULL, $q$INSERT INTO public.inquiries (type, email, reference) VALUES ('contact', 'a@test.local', 'T42-3') RETURNING reference$q$), 'T42-3');
    PERFORM pg_temp.expect('service role reads it',
        pg_temp.run_as('service_role', NULL, $q$SELECT count(*)::text FROM public.inquiries WHERE reference = 'T42-3'$q$), '1');
    RAISE NOTICE 'PASSED: inquiries are service-only; templates are read-only for signed-in users.';
END $$;

-- 3. RPCs -------------------------------------------------------------------------------
DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'public.replace_household_category(uuid, character varying, character varying, character varying, character varying)',
        'public.seed_household_default_taxonomy(uuid)'
    ] LOOP
        IF has_function_privilege('anon', v_sig, 'EXECUTE') OR has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client role can execute %', v_sig;
        END IF;
        IF NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: the service role cannot execute %', v_sig;
        END IF;
        PERFORM pg_temp.expect('search_path of ' || v_sig,
            (SELECT cfg FROM pg_proc p, unnest(p.proconfig) cfg WHERE p.oid = v_sig::regprocedure AND cfg LIKE 'search_path=%'),
            'search_path=public, pg_temp');
    END LOOP;
    RAISE NOTICE 'PASSED: the two taxonomy RPCs are service-only with a safe search_path.';
END $$;

-- 4. The cross-household write this closes -----------------------------------------------
DO $$
DECLARE
    v_user text := 'e4200000-0000-0000-0000-00000000000a';
    v_hh uuid := 'e42a0000-0000-0000-0000-000000000001';
    v_res text;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user::uuid, 't42-a@test.local');
    INSERT INTO public.households (id, name, invite_code) VALUES (v_hh, 'T42 Someone else', 'T42CODE000000001');

    PERFORM pg_temp.expect('a stranger seeds someone else''s household',
        pg_temp.run_as('authenticated', v_user, format('SELECT public.seed_household_default_taxonomy(%L)::text', v_hh)), 'ERR:42501');
    PERFORM pg_temp.expect('nothing was written',
        (SELECT count(*)::text FROM public.household_category_settings WHERE household_id = v_hh), '0');

    v_res := pg_temp.run_as('service_role', NULL, format('SELECT public.seed_household_default_taxonomy(%L)::text', v_hh));
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'REGRESSION: the service role cannot seed: %', v_res;
    END IF;
    IF (SELECT count(*) FROM public.household_category_settings WHERE household_id = v_hh) < 7 THEN
        RAISE EXCEPTION 'REGRESSION: the seed wrote nothing';
    END IF;
    RAISE NOTICE 'PASSED: only the service role can seed a household''s taxonomy.';
END $$;

ROLLBACK;
