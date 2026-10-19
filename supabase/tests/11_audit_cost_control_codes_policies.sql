-- ============================================================================
-- Test 11 (audit DB-04): cost_control_codes write policies
--
-- 20261011_hybrid_category_lifecycle.sql created cost_control_codes_insert /
-- _update for role PUBLIC with only "household_id IS NOT NULL AND
-- is_system = false". Any caller - including anon - could plant categories in
-- any household's taxonomy (and squat on its future codes), and move their own
-- custom codes into another household.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('d4000000-0000-0000-0000-000000000001', 'db04-admin@test.local'),
        ('d4000000-0000-0000-0000-000000000002', 'db04-member@test.local'),
        ('d4000000-0000-0000-0000-000000000003', 'db04-attacker@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('d4aa0000-0000-0000-0000-000000000001', 'DB04 Victim', 'DB04VICTIMCODE01'),
        ('d4bb0000-0000-0000-0000-000000000001', 'DB04 Attacker', 'DB04ATTACKCODE01');

    UPDATE public.users SET household_id = 'd4aa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd4000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'd4aa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'd4000000-0000-0000-0000-000000000002';
    UPDATE public.users SET household_id = 'd4bb0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd4000000-0000-0000-0000-000000000003';

    INSERT INTO public.cost_control_codes (id, code, category, keywords, household_id, is_system) VALUES
        ('d4cc0000-0000-0000-0000-000000000001', 'DB04-ATTACKER-OWN', 'Attacker own', '{}', 'd4bb0000-0000-0000-0000-000000000001', false);
END $$;

CREATE FUNCTION pg_temp.try_sql(p_role text, p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows int;
BEGIN
    IF p_sub IS NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
    ELSE
        PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_role)::text, true);
    END IF;
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    RETURN 'rows=' || v_rows;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.try_sql(text, text, text) TO anon, authenticated;

DO $$
DECLARE
    v_res text;
BEGIN
    -- 1. anon cannot plant a category in any household
    v_res := pg_temp.try_sql('anon', NULL,
        $q$INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system)
           VALUES ('DB04-ANON', 'anon planted', '{}', 'd4aa0000-0000-0000-0000-000000000001', false)$q$);
    IF v_res = 'rows=1' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-04): anon inserted a category into a household';
    END IF;

    -- 2. authenticated outsider cannot plant a category in the victim household
    v_res := pg_temp.try_sql('authenticated', 'd4000000-0000-0000-0000-000000000003',
        $q$INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system)
           VALUES ('DB04-PLANTED', 'planted', '{}', 'd4aa0000-0000-0000-0000-000000000001', false)$q$);
    IF v_res = 'rows=1' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-04): outsider inserted a category into the victim household';
    END IF;

    -- 3. outsider cannot move their own custom category into the victim household
    v_res := pg_temp.try_sql('authenticated', 'd4000000-0000-0000-0000-000000000003',
        $q$UPDATE public.cost_control_codes SET household_id = 'd4aa0000-0000-0000-0000-000000000001'
           WHERE id = 'd4cc0000-0000-0000-0000-000000000001'$q$);
    IF v_res = 'rows=1' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-04): category moved into a foreign household via UPDATE';
    END IF;

    -- 4. non-admin member cannot create household categories
    v_res := pg_temp.try_sql('authenticated', 'd4000000-0000-0000-0000-000000000002',
        $q$INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system)
           VALUES ('DB04-MEMBER', 'member cat', '{}', 'd4aa0000-0000-0000-0000-000000000001', false)$q$);
    IF v_res = 'rows=1' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-04): non-admin member created a household category';
    END IF;

    -- 5. nobody can create a system / global category from the client
    v_res := pg_temp.try_sql('authenticated', 'd4000000-0000-0000-0000-000000000001',
        $q$INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system)
           VALUES ('DB04-GLOBAL', 'global', '{}', NULL, true)$q$);
    IF v_res = 'rows=1' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-04): client created a global/system category';
    END IF;

    IF EXISTS (SELECT 1 FROM public.cost_control_codes
               WHERE code IN ('DB04-ANON', 'DB04-PLANTED', 'DB04-MEMBER', 'DB04-GLOBAL')
                  OR (id = 'd4cc0000-0000-0000-0000-000000000001' AND household_id <> 'd4bb0000-0000-0000-0000-000000000001')) THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-04): forbidden category rows were written';
    END IF;

    -- 6. household admin can still add and rename a custom category in their own household
    v_res := pg_temp.try_sql('authenticated', 'd4000000-0000-0000-0000-000000000001',
        $q$INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system)
           VALUES ('DB04-ADMIN-OWN', 'admin cat', '{}', 'd4aa0000-0000-0000-0000-000000000001', false)$q$);
    IF v_res <> 'rows=1' THEN
        RAISE EXCEPTION 'Admin could not create own household category: %', v_res;
    END IF;
    v_res := pg_temp.try_sql('authenticated', 'd4000000-0000-0000-0000-000000000001',
        $q$UPDATE public.cost_control_codes SET category = 'admin cat renamed'
           WHERE code = 'DB04-ADMIN-OWN' AND household_id = 'd4aa0000-0000-0000-0000-000000000001'$q$);
    IF v_res <> 'rows=1' THEN
        RAISE EXCEPTION 'Admin could not rename own household category: %', v_res;
    END IF;

    RAISE NOTICE 'PASSED: cost_control_codes writes are scoped to the caller''s household admins.';
END $$;

ROLLBACK;
