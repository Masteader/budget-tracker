-- ============================================================================
-- Test 43: sub-category names stay inside their household
--
-- Migration: 20261105000700_sub_categories_household_scope.sql
--
-- Test 22 is the original proof for custom parents. This one covers what
-- 20261026120000 added: the household_id column.
--
-- Verifies:
--   1. A household-scoped row is read only by that household, under any parent.
--   2. Seeded rows under system categories stay readable by every signed-in user.
--   3. An API-created name from before household_id existed ('sub-' code, NULL household,
--      system parent) is not shown to anyone through RLS, and the service role keeps it.
--   4. A NULL-household row under a household's custom category is read only by it.
--   5. Clients cannot write, whatever household_id they name. anon reads nothing.
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

-- How many rows with this sub_code the user can read.
CREATE FUNCTION pg_temp.sees(p_user text, p_sub_code text)
RETURNS text
LANGUAGE sql
AS $$
    SELECT pg_temp.run_as('authenticated', p_user,
        format('SELECT count(*)::text FROM public.cost_control_sub_categories WHERE sub_code = %L', p_sub_code));
$$;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e4300000-0000-0000-0000-00000000000a', 't43-x@test.local'),
        ('e4300000-0000-0000-0000-00000000000b', 't43-y@test.local');
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        ('e43a0000-0000-0000-0000-000000000001', 'T43 X', 'T43CODEX00000001', 'roommates'),
        ('e43a0000-0000-0000-0000-000000000002', 'T43 Y', 'T43CODEY00000001', 'roommates');
    UPDATE public.users SET household_id = 'e43a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'e4300000-0000-0000-0000-00000000000a';
    UPDATE public.users SET household_id = 'e43a0000-0000-0000-0000-000000000002', role = 'admin', financial_role = 'peer'
    WHERE id = 'e4300000-0000-0000-0000-00000000000b';
    INSERT INTO public.cost_control_codes (code, category, keywords, is_system, household_id) VALUES
        ('CUSTOM-T43X', 'T43 X custom', '{}', false, 'e43a0000-0000-0000-0000-000000000001');
    INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar, household_id) VALUES
        ('OPEX-DINING', 'sub-t43-scoped', 'Private name of X', 'x', 'e43a0000-0000-0000-0000-000000000001'),
        ('OPEX-DINING', 't43_seeded', 'A seeded name', 'x', NULL),
        ('OPEX-DINING', 'sub-t43-legacy', 'Old private name', 'x', NULL),
        ('CUSTOM-T43X', 'sub-t43-custom', 'Under custom parent', 'x', NULL);
END $$;

DO $$
DECLARE
    v_x text := 'e4300000-0000-0000-0000-00000000000a';
    v_y text := 'e4300000-0000-0000-0000-00000000000b';
BEGIN
    PERFORM pg_temp.expect('owner reads its scoped row', pg_temp.sees(v_x, 'sub-t43-scoped'), '1');
    PERFORM pg_temp.expect('another household cannot', pg_temp.sees(v_y, 'sub-t43-scoped'), '0');

    PERFORM pg_temp.expect('seeded row, X', pg_temp.sees(v_x, 't43_seeded'), '1');
    PERFORM pg_temp.expect('seeded row, Y', pg_temp.sees(v_y, 't43_seeded'), '1');

    PERFORM pg_temp.expect('legacy name hidden from X', pg_temp.sees(v_x, 'sub-t43-legacy'), '0');
    PERFORM pg_temp.expect('legacy name hidden from Y', pg_temp.sees(v_y, 'sub-t43-legacy'), '0');
    PERFORM pg_temp.expect('service role keeps the legacy row',
        pg_temp.run_as('service_role', NULL, $q$SELECT count(*)::text FROM public.cost_control_sub_categories WHERE sub_code = 'sub-t43-legacy'$q$), '1');

    PERFORM pg_temp.expect('owner reads under its custom parent', pg_temp.sees(v_x, 'sub-t43-custom'), '1');
    PERFORM pg_temp.expect('another household cannot read under it', pg_temp.sees(v_y, 'sub-t43-custom'), '0');

    PERFORM pg_temp.expect('client insert naming its own household',
        pg_temp.run_as('authenticated', v_x, $q$INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar, household_id)
            VALUES ('OPEX-DINING', 'sub-t43-new', 'n', 'n', 'e43a0000-0000-0000-0000-000000000001')$q$), 'ERR:42501');
    PERFORM pg_temp.expect('client update of its own row',
        pg_temp.run_as('authenticated', v_x, $q$UPDATE public.cost_control_sub_categories SET name_en = 'n' WHERE sub_code = 'sub-t43-scoped'$q$), 'ERR:42501');
    PERFORM pg_temp.expect('client delete of its own row',
        pg_temp.run_as('authenticated', v_x, $q$DELETE FROM public.cost_control_sub_categories WHERE sub_code = 'sub-t43-scoped'$q$), 'ERR:42501');
    PERFORM pg_temp.expect('anon reads',
        pg_temp.run_as('anon', NULL, 'SELECT count(*)::text FROM public.cost_control_sub_categories'), 'ERR:42501');
    RAISE NOTICE 'PASSED: sub-category names stay in their household; clients only read.';
END $$;

ROLLBACK;
