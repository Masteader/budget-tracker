-- ============================================================================
-- Test 72: budgets and household_category_settings take only codes the household may use
--
-- Migration: 20261019100000_sec08_round6_hardening.sql (validate_category_code_exists,
--            trg_validate_category_budgets, trg_validate_category_settings)
-- Rules: .agents/rules/04-security-and-privacy.md (RLS multi-tenancy)
--
-- The app writes both tables directly (the Category Library switch, the sub-budget dialog), and
-- their RLS policies check only the household and the admin role. The category code is checked by
-- the validation trigger: a system code or the household's own custom code. Test 07 covers
-- transactions; this covers the two tables the API ownership check (POST /budgets/sub-allocations,
-- switching a category on) also guards, so a direct client write cannot get around it:
--   * another household's custom code and an unknown code are refused with the same SQLSTATE
--     (no oracle on other households' codes), on insert and on changing a row's code;
--   * a system code and the household's own custom code are accepted.
-- Every client call is as the client makes it (RLS, as PostgREST applies it). Rolled back.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e7200000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e72a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int) TO PUBLIC;

CREATE TABLE pg_temp.fails (n serial PRIMARY KEY, label text, got text, want text);
CREATE FUNCTION pg_temp.check(p_label text, p_got text, p_want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 600), p_want);
    END IF;
END;
$$;

-- A client write as user p_sub: the rows it changed, or ERR:<SQLSTATE>.
CREATE FUNCTION pg_temp.write(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_n bigint;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v_n::text;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.write(uuid, text) TO PUBLIC;

CREATE FUNCTION pg_temp.budget_sql(p_code text) RETURNS text LANGUAGE sql AS $$
    SELECT format(
        'INSERT INTO public.budgets (household_id, month, cycle_key, category_code, allocated_amount, spent_amount) '
        'VALUES (%L, %L, %L, %L, 100, 0)', pg_temp.h(1), '2026-11-01', '2026-11', p_code)
$$;
CREATE FUNCTION pg_temp.setting_sql(p_code text) RETURNS text LANGUAGE sql AS $$
    SELECT format(
        'INSERT INTO public.household_category_settings (household_id, category_code, is_active) VALUES (%L, %L, true)',
        pg_temp.h(1), p_code)
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- Household 1: admin A(1). Household 2: admin B(2), owner of CUSTOM-T72-SECRET.
-- CUSTOM-T72-OWN belongs to household 1; OPEX-GROCERY is a system code (seed.sql).
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't72-' || n || '@test.local', jsonb_build_object('display_name', 'T72 User ' || n)
    FROM generate_series(1, 2) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T72 H1', 'T72CODE000000001', 'roommates', 1),
        (pg_temp.h(2), 'T72 H2', 'T72CODE000000002', 'roommates', 1);
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'family_member', true),
        (pg_temp.h(2), pg_temp.u(2), 'admin', 'family_member', true);
    UPDATE public.users u SET household_id = m.household_id, role = m.role, financial_role = m.financial_role
    FROM public.household_memberships m WHERE m.user_id = u.id AND m.household_id IN (pg_temp.h(1), pg_temp.h(2));
    UPDATE public.households SET owner_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(2) WHERE id = pg_temp.h(2);
    IF NOT EXISTS (SELECT 1 FROM public.cost_control_codes WHERE code = 'OPEX-GROCERY' AND household_id IS NULL) THEN
        INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system)
        VALUES ('OPEX-GROCERY', 'Groceries', ARRAY['grocery'], NULL, true);
    END IF;
    INSERT INTO public.cost_control_codes (code, category, keywords, household_id, is_system) VALUES
        ('CUSTOM-T72-OWN', 'T72 Own', ARRAY['t72 own'], pg_temp.h(1), false),
        ('CUSTOM-T72-SECRET', 'T72 Secret', ARRAY['t72 secret'], pg_temp.h(2), false);
END $$;

DO $$
DECLARE
    v_foreign text;
    v_unknown text;
BEGIN
    -- budgets: insert
    v_foreign := pg_temp.write(pg_temp.u(1), pg_temp.budget_sql('CUSTOM-T72-SECRET'));
    v_unknown := pg_temp.write(pg_temp.u(1), pg_temp.budget_sql('CUSTOM-T72-NOWHERE'));
    PERFORM pg_temp.check('budgets: A cannot budget household 2''s custom code', v_foreign, 'ERR:23503');
    PERFORM pg_temp.check('budgets: A cannot budget an unknown code', v_unknown, 'ERR:23503');
    PERFORM pg_temp.check('budgets: foreign and unknown codes are refused alike', v_foreign, v_unknown);
    PERFORM pg_temp.check('budgets: A budgets a system code', pg_temp.write(pg_temp.u(1), pg_temp.budget_sql('OPEX-GROCERY')), '1');
    PERFORM pg_temp.check('budgets: A budgets its own custom code', pg_temp.write(pg_temp.u(1), pg_temp.budget_sql('CUSTOM-T72-OWN')), '1');

    -- budgets: changing an existing row's code
    PERFORM pg_temp.check('budgets: A cannot move its row onto household 2''s code', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.budgets SET category_code = %L WHERE household_id = %L AND category_code = %L',
        'CUSTOM-T72-SECRET', pg_temp.h(1), 'CUSTOM-T72-OWN')), 'ERR:23503');
    PERFORM pg_temp.check('budgets: A still edits its own row''s allocation', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.budgets SET allocated_amount = 150 WHERE household_id = %L AND category_code = %L',
        pg_temp.h(1), 'CUSTOM-T72-OWN')), '1');

    -- household_category_settings: insert
    v_foreign := pg_temp.write(pg_temp.u(1), pg_temp.setting_sql('CUSTOM-T72-SECRET'));
    v_unknown := pg_temp.write(pg_temp.u(1), pg_temp.setting_sql('CUSTOM-T72-NOWHERE'));
    PERFORM pg_temp.check('settings: A cannot switch on household 2''s custom code', v_foreign, 'ERR:23503');
    PERFORM pg_temp.check('settings: A cannot switch on an unknown code', v_unknown, 'ERR:23503');
    PERFORM pg_temp.check('settings: foreign and unknown codes are refused alike', v_foreign, v_unknown);
    PERFORM pg_temp.check('settings: A switches on its own custom code', pg_temp.write(pg_temp.u(1), pg_temp.setting_sql('CUSTOM-T72-OWN')), '1');

    -- household_category_settings: changing an existing row's code
    PERFORM pg_temp.check('settings: A cannot move its setting onto household 2''s code', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.household_category_settings SET category_code = %L WHERE household_id = %L AND category_code = %L',
        'CUSTOM-T72-SECRET', pg_temp.h(1), 'CUSTOM-T72-OWN')), 'ERR:23503');

    -- Nothing of household 1 sits under the refused codes.
    PERFORM pg_temp.check('no household 1 rows under refused codes', (
        (SELECT count(*) FROM public.budgets WHERE household_id = pg_temp.h(1)
             AND category_code IN ('CUSTOM-T72-SECRET', 'CUSTOM-T72-NOWHERE'))
      + (SELECT count(*) FROM public.household_category_settings WHERE household_id = pg_temp.h(1)
             AND category_code IN ('CUSTOM-T72-SECRET', 'CUSTOM-T72-NOWHERE')))::text, '0');
END $$;

DO $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(label || ' => got ' || COALESCE(got, 'NULL') || ', expected ' || COALESCE(want, 'NULL'), E'\n' ORDER BY n)
    INTO v_list FROM pg_temp.fails;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION E'Test 72 failed:\n%', v_list;
    END IF;
    RAISE NOTICE 'PASSED: budgets and category settings take only system or the household''s own codes, from any client.';
END $$;

ROLLBACK;
