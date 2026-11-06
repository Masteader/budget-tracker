-- ============================================================================
-- Test 63: Who sees and who sets a wife's personal allowance (owner decision 2026-11-06)
--
-- Migration: 20261105001300_wife_repayment_debit.sql (replaces the allowance policy and both
--            allowance RPCs of 20261020300000)
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 3;
--       .agents/rules/04-security-and-privacy.md, Family Nafaqah
--
-- Her allowance (member_allowances, get_member_allowance_status: allocated, spent, remaining) is
-- read by:
--   * the wife herself (her own only);
--   * her husband: the household's Nafaqah provider while he is a current member who is not a wife;
--   * a household admin who is not a wife.
-- Nobody else: a co-wife (even an admin) and an ordinary member read no row and get no figure.
-- It is set by whoever set it before (the husband, admin or not, and the household's admins), but
-- never by a wife: a wife who is an admin no longer sets a co-wife's.
--
-- The matrix: the wife (her own, a co-wife's), the husband (an admin, and not an admin), a co-wife,
-- a wife who is an admin, an ordinary member, an admin who is not a wife; with the husband a
-- member, and gone (he left the household, which clears the provider). Each read is checked
-- through the table (RLS, as the app's client reads it), through the read RPC as the client, and
-- through it as the API calls it (the service role naming the verified caller).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- One call as user p_sub (or the service role): the value, or ERR:<SQLSTATE>:<message>.
CREATE FUNCTION pg_temp.call(p_sub uuid, p_sql text, p_role text DEFAULT 'authenticated')
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
    v_claims jsonb := jsonb_build_object('role', p_role);
BEGIN
    IF p_sub IS NOT NULL THEN
        v_claims := v_claims || jsonb_build_object('sub', p_sub);
    END IF;
    PERFORM set_config('request.jwt.claims', v_claims::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE || ':' || SQLERRM;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text) TO PUBLIC;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e6300000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e63a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int) TO PUBLIC;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, true);
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
    WHERE id = pg_temp.u(p_user);
END;
$$;

CREATE TABLE pg_temp.fails (n serial PRIMARY KEY, label text, got text, want text);
CREATE FUNCTION pg_temp.check(p_label text, p_got text, p_want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 240), p_want);
    END IF;
END;
$$;

-- Her allowance rows the caller reads through the table (RLS): 1 or 0.
CREATE FUNCTION pg_temp.rows_of(p_actor int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT count(*)::text FROM public.member_allowances WHERE member_user_id = %L', pg_temp.u(p_wife)));
$$;
-- Every allowance row the caller reads, whoever it belongs to.
CREATE FUNCTION pg_temp.all_rows(p_actor int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), 'SELECT count(*)::text FROM public.member_allowances');
$$;
-- The read RPC as the client: her allocated figure, or the refusal.
CREATE FUNCTION pg_temp.status_as(p_actor int, p_hh int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT (public.get_member_allowance_status(%L, %L, %L, NULL) ->> %L)',
               pg_temp.h(p_hh), pg_temp.u(p_wife), '2026-11', 'allocated'));
$$;
-- The same, as the API calls it: the service role naming the verified caller.
CREATE FUNCTION pg_temp.status_api(p_actor int, p_hh int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(NULL,
        format('SELECT (public.get_member_allowance_status(%L, %L, %L, %L) ->> %L)',
               pg_temp.h(p_hh), pg_temp.u(p_wife), '2026-11', pg_temp.u(p_actor), 'allocated'), 'service_role');
$$;
-- The set RPC as the client, and as the API.
CREATE FUNCTION pg_temp.set_as(p_actor int, p_hh int, p_wife int, p_amount text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT (public.set_member_allowance(%L, %L, %s, %L, NULL) ->> %L)',
               pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, '2026-11', 'allocated'));
$$;
CREATE FUNCTION pg_temp.set_api(p_actor int, p_hh int, p_wife int, p_amount text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(NULL,
        format('SELECT (public.set_member_allowance(%L, %L, %s, %L, %L) ->> %L)',
               pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, '2026-11', pg_temp.u(p_actor), 'allocated'), 'service_role');
$$;
-- A refusal of the read (42501, naming who reads it) / of the set (42501, naming who sets it) /
-- any refusal; anything else as it came.
CREATE FUNCTION pg_temp.v(p_res text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_res LIKE 'ERR:42501:%reads%allowance%' THEN 'no-read'
        WHEN p_res LIKE 'ERR:42501:%allowance is set by%' THEN 'no-set'
        WHEN p_res LIKE 'ERR:42501:%' THEN 'refused'
        ELSE p_res
    END;
$$;
CREATE FUNCTION pg_temp.amount(p_hh int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT amount::text || '/' || COALESCE(set_by::text, '-') FROM public.member_allowances
    WHERE household_id = pg_temp.h(p_hh) AND member_user_id = pg_temp.u(p_wife) AND cycle_key = '2026-11';
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider; wife W(2); co-wife W2(3); member K(4); admin C(5) who is
--        not a wife; wife WA(6) who is an admin.
-- F2(2): husband H2(7) a member (not an admin) and provider; wife V(8); primary admin D(9) who is
--        not a wife; wife VA(10) who is an admin; member M(11).
-- Allowances for 2026-11: W 500, W2 600, WA 700; V 800, VA 900.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't63-' || n || '@test.local', jsonb_build_object('display_name', 'T63 User ' || n)
    FROM generate_series(1, 11) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T63 H1', 'T63CODE000000001', 'family'),
        (pg_temp.h(2), 'T63 H2', 'T63CODE000000002', 'family');
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'member', 'family_member');
    PERFORM pg_temp.join(6, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(9, 2, 'admin', 'family_member');
    PERFORM pg_temp.join(7, 2, 'member', 'provider');
    PERFORM pg_temp.join(8, 2, 'member', 'spouse');
    PERFORM pg_temp.join(10, 2, 'admin', 'spouse');
    PERFORM pg_temp.join(11, 2, 'member', 'family_member');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(9), nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);

    INSERT INTO public.member_allowances (household_id, member_user_id, cycle_key, amount, set_by) VALUES
        (pg_temp.h(1), pg_temp.u(2), '2026-11', 500, pg_temp.u(1)),
        (pg_temp.h(1), pg_temp.u(3), '2026-11', 600, pg_temp.u(1)),
        (pg_temp.h(1), pg_temp.u(6), '2026-11', 700, pg_temp.u(1)),
        (pg_temp.h(2), pg_temp.u(8), '2026-11', 800, pg_temp.u(7)),
        (pg_temp.h(2), pg_temp.u(10), '2026-11', 900, pg_temp.u(7));
END $$;

-- ── Husband present ─────────────────────────────────────────────────────────────────────────
-- The reads: (household, caller, wife, sees). The calls run as each caller, one after another.
CREATE TABLE pg_temp.reads (hh int, actor int, wife int, label text, sees boolean, allocated text);
INSERT INTO pg_temp.reads VALUES
    -- F1: the husband is an admin.
    (1, 2, 2, 'the wife, her own', true, '500.00'),
    (1, 2, 3, 'the wife, a co-wife''s', false, NULL),
    (1, 1, 2, 'the husband (an admin)', true, '500.00'),
    (1, 1, 6, 'the husband (an admin), the wife-admin''s', true, '700.00'),
    (1, 3, 2, 'a co-wife', false, NULL),
    (1, 3, 3, 'a co-wife, her own', true, '600.00'),
    (1, 6, 2, 'a wife who is an admin', false, NULL),
    (1, 6, 3, 'a wife who is an admin, another co-wife''s', false, NULL),
    (1, 6, 6, 'a wife who is an admin, her own', true, '700.00'),
    (1, 4, 2, 'an ordinary member', false, NULL),
    (1, 4, 6, 'an ordinary member, the wife-admin''s', false, NULL),
    (1, 5, 2, 'an admin who is not a wife', true, '500.00'),
    (1, 5, 3, 'an admin who is not a wife, the co-wife''s', true, '600.00'),
    -- F2: the husband is not an admin.
    (2, 7, 8, 'the husband (not an admin)', true, '800.00'),
    (2, 7, 10, 'the husband (not an admin), the wife-admin''s', true, '900.00'),
    (2, 8, 8, 'F2 wife, her own', true, '800.00'),
    (2, 8, 10, 'F2 wife, her co-wife''s', false, NULL),
    (2, 10, 8, 'F2 wife who is an admin', false, NULL),
    (2, 11, 8, 'F2 ordinary member', false, NULL),
    (2, 9, 8, 'F2 admin who is not a wife', true, '800.00'),
    (2, 9, 10, 'F2 admin who is not a wife, the wife-admin''s', true, '900.00');

CREATE FUNCTION pg_temp.check_reads(p_when text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v record;
BEGIN
    FOR v IN SELECT * FROM pg_temp.reads ORDER BY hh, actor, wife LOOP
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' reads her row',
            pg_temp.rows_of(v.actor, v.wife), CASE WHEN v.sees THEN '1' ELSE '0' END);
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' gets her figure (client)',
            pg_temp.v(pg_temp.status_as(v.actor, v.hh, v.wife)), CASE WHEN v.sees THEN v.allocated ELSE 'no-read' END);
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' gets her figure (API)',
            pg_temp.v(pg_temp.status_api(v.actor, v.hh, v.wife)), CASE WHEN v.sees THEN v.allocated ELSE 'no-read' END);
    END LOOP;
END;
$$;

DO $$
BEGIN
    PERFORM pg_temp.check_reads('present');
    -- How many rows each reads in all: no total is computed from rows a caller should not see.
    PERFORM pg_temp.check('present: the wife reads only her own row', pg_temp.all_rows(2), '1');
    PERFORM pg_temp.check('present: a wife-admin reads only her own row', pg_temp.all_rows(6), '1');
    PERFORM pg_temp.check('present: a member reads no row', pg_temp.all_rows(4), '0');
    PERFORM pg_temp.check('present: the husband reads his household''s rows', pg_temp.all_rows(1), '3');
    PERFORM pg_temp.check('present: an admin reads his household''s rows', pg_temp.all_rows(5), '3');
    PERFORM pg_temp.check('present: the husband who is not an admin reads his household''s rows', pg_temp.all_rows(7), '2');
    PERFORM pg_temp.check('present: F2 member reads no row', pg_temp.all_rows(11), '0');
    PERFORM pg_temp.check('present: F2 wife-admin reads only her own row', pg_temp.all_rows(10), '1');
END $$;

-- Who sets (husband present).
DO $$
BEGIN
    -- Allowed, as before: the husband (an admin, and not an admin), an admin who is not a wife.
    PERFORM pg_temp.check('present: the husband (an admin) sets hers', pg_temp.v(pg_temp.set_as(1, 1, 2, '510')), '510.00');
    PERFORM pg_temp.check('present: an admin who is not a wife sets the co-wife''s', pg_temp.v(pg_temp.set_as(5, 1, 3, '610')), '610.00');
    PERFORM pg_temp.check('present: the husband (not an admin) sets hers', pg_temp.v(pg_temp.set_as(7, 2, 8, '810')), '810.00');
    PERFORM pg_temp.check('present: F2 admin who is not a wife sets the wife-admin''s', pg_temp.v(pg_temp.set_api(9, 2, 10, '910')), '910.00');
    -- Never a wife: not her own, not a co-wife's, even as an admin; never an ordinary member.
    PERFORM pg_temp.check('present: the wife sets her own', pg_temp.v(pg_temp.set_as(2, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('present: the wife sets a co-wife''s', pg_temp.v(pg_temp.set_as(2, 1, 3, '9999')), 'no-set');
    PERFORM pg_temp.check('present: a co-wife sets hers', pg_temp.v(pg_temp.set_as(3, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('present: a wife-admin sets a co-wife''s (client)', pg_temp.v(pg_temp.set_as(6, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('present: a wife-admin sets a co-wife''s (API)', pg_temp.v(pg_temp.set_api(6, 1, 3, '9999')), 'no-set');
    PERFORM pg_temp.check('present: a wife-admin sets her own', pg_temp.v(pg_temp.set_as(6, 1, 6, '9999')), 'no-set');
    PERFORM pg_temp.check('present: F2 wife-admin sets her co-wife''s', pg_temp.v(pg_temp.set_as(10, 2, 8, '9999')), 'no-set');
    PERFORM pg_temp.check('present: an ordinary member sets hers', pg_temp.v(pg_temp.set_as(4, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('present: F2 ordinary member sets hers', pg_temp.v(pg_temp.set_api(11, 2, 8, '9999')), 'no-set');
    -- What stands after them.
    PERFORM pg_temp.check('present: hers', pg_temp.amount(1, 2), '510.00/' || pg_temp.u(1));
    PERFORM pg_temp.check('present: the co-wife''s', pg_temp.amount(1, 3), '610.00/' || pg_temp.u(5));
    PERFORM pg_temp.check('present: the wife-admin''s', pg_temp.amount(1, 6), '700.00/' || pg_temp.u(1));
    PERFORM pg_temp.check('present: F2 hers', pg_temp.amount(2, 8), '810.00/' || pg_temp.u(7));
    PERFORM pg_temp.check('present: F2 the wife-admin''s', pg_temp.amount(2, 10), '910.00/' || pg_temp.u(9));
    -- Put the figures back for the reads below.
    UPDATE public.member_allowances SET amount = CASE member_user_id
        WHEN pg_temp.u(2) THEN 500 WHEN pg_temp.u(3) THEN 600 WHEN pg_temp.u(8) THEN 800 WHEN pg_temp.u(10) THEN 900 ELSE amount END;
END $$;

-- ── Husband gone (he left the household, which clears the provider) ─────────────────────────
DO $$
BEGIN
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(1);
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(2) AND user_id = pg_temp.u(7);
    PERFORM pg_temp.check('gone: no provider',
        (SELECT string_agg((nafaqah_provider_user_id IS NULL)::text, ',' ORDER BY id) FROM public.households
         WHERE id IN (pg_temp.h(1), pg_temp.h(2))), 'true,true');
END $$;

DELETE FROM pg_temp.reads WHERE actor IN (1, 7);
DO $$
BEGIN
    PERFORM pg_temp.check_reads('gone');
    -- The husband who left reads nothing and sets nothing.
    PERFORM pg_temp.check('gone: the husband who left reads no row', pg_temp.all_rows(1), '0');
    PERFORM pg_temp.check('gone: the husband who left gets no figure', pg_temp.v(pg_temp.status_api(1, 1, 2)), 'refused');
    PERFORM pg_temp.check('gone: the husband who left sets nothing', pg_temp.v(pg_temp.set_api(1, 1, 2, '1')), 'refused');
    PERFORM pg_temp.check('gone: F2 husband who left sets nothing', pg_temp.v(pg_temp.set_api(7, 2, 8, '1')), 'refused');
    -- An admin who is not a wife sets; a wife-admin and a member never.
    PERFORM pg_temp.check('gone: an admin who is not a wife sets hers', pg_temp.v(pg_temp.set_as(5, 1, 2, '520')), '520.00');
    PERFORM pg_temp.check('gone: F2 admin who is not a wife sets hers', pg_temp.v(pg_temp.set_as(9, 2, 8, '820')), '820.00');
    PERFORM pg_temp.check('gone: a wife-admin sets a co-wife''s', pg_temp.v(pg_temp.set_as(6, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('gone: F2 wife-admin sets her co-wife''s', pg_temp.v(pg_temp.set_api(10, 2, 8, '9999')), 'no-set');
    PERFORM pg_temp.check('gone: an ordinary member sets hers', pg_temp.v(pg_temp.set_as(4, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('gone: a wife sets her own', pg_temp.v(pg_temp.set_as(2, 1, 2, '9999')), 'no-set');
    PERFORM pg_temp.check('gone: hers', pg_temp.amount(1, 2), '520.00/' || pg_temp.u(5));
    PERFORM pg_temp.check('gone: F2 hers', pg_temp.amount(2, 8), '820.00/' || pg_temp.u(9));
END $$;

-- ── The rules stated where they live ────────────────────────────────────────────────────────
DO $$
BEGIN
    -- The read policy names the rule itself (one policy, for SELECT, to authenticated).
    PERFORM pg_temp.check('the allowance policy',
        (SELECT string_agg(policyname || '/' || cmd || '/' || array_to_string(roles, ','), ';') FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'member_allowances'),
        'member_allowances_select_household/SELECT/authenticated');
    PERFORM pg_temp.check('the allowance policy reads her own row and the callers who see allowances',
        (SELECT (qual LIKE '%member_user_id = ( SELECT auth.uid()%' AND qual LIKE '%nafaqah_caller_sees_allowances%')::text
         FROM pg_policies WHERE schemaname = 'public' AND tablename = 'member_allowances'), 'true');
    -- No client writes the table, and no API role runs the internal helper.
    PERFORM pg_temp.check('clients write no allowance row',
        (has_table_privilege('authenticated', 'public.member_allowances', 'INSERT')
         OR has_table_privilege('authenticated', 'public.member_allowances', 'UPDATE')
         OR has_table_privilege('authenticated', 'public.member_allowances', 'DELETE'))::text, 'false');
    PERFORM pg_temp.check('the helper exists',
        (to_regprocedure('public.nafaqah_may_see_allowances(uuid, uuid)') IS NOT NULL)::text, 'true');
    IF to_regprocedure('public.nafaqah_may_see_allowances(uuid, uuid)') IS NOT NULL THEN
        PERFORM pg_temp.check('the helper is internal',
            (has_function_privilege('authenticated', 'public.nafaqah_may_see_allowances(uuid, uuid)', 'EXECUTE')
             OR has_function_privilege('anon', 'public.nafaqah_may_see_allowances(uuid, uuid)', 'EXECUTE'))::text, 'false');
    END IF;
    PERFORM pg_temp.check('anon reads no allowance',
        has_function_privilege('anon', 'public.get_member_allowance_status(uuid, uuid, text, uuid)', 'EXECUTE')::text, 'false');
END $$;

DO $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(label || ': got ' || COALESCE(got, 'NULL') || ', expected ' || COALESCE(want, 'NULL'), E'\n' ORDER BY n)
    INTO v_list FROM pg_temp.fails;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION E'% check(s) failed:\n%', (SELECT count(*) FROM pg_temp.fails), v_list;
    END IF;
    RAISE NOTICE 'PASSED: who sees and who sets a wife''s allowance.';
END $$;

ROLLBACK;
