-- ============================================================================
-- Test 71: The wife account, verification review CHK (owner decisions 2026-11-07)
--
-- Migration: 20261105001300_wife_repayment_debit.sql, sections 10d and 12
-- Rules: .agents/rules/04-security-and-privacy.md, Family Nafaqah ("do not even learn it exists")
--
--   CHK-01  The write policies of transactions asked a helper for the list of the wife accounts
--           hidden from the caller (nafaqah_caller_hidden_wife_accounts(): SECURITY DEFINER,
--           executable by every member, so callable through /rpc/). It answered any member, a
--           co-wife included, with the ids of every wife account of the household they may not
--           see, one with no row on it too. Now the policies ask about the row's own account
--           (nafaqah_wife_account_hidden(account_id)), which answers an id of nothing exactly as it
--           answers a wife account the caller does not see, so it tells nobody that one exists.
--           No callable function without arguments names a wife account its caller does not read.
-- Every client call is as the client makes it (RLS, as PostgREST applies it). Rolled back.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e7100000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e71a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e71b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e71c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.t(int) TO PUBLIC;

CREATE TABLE pg_temp.fails (n serial PRIMARY KEY, label text, got text, want text);
CREATE FUNCTION pg_temp.check(p_label text, p_got text, p_want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 600), p_want);
    END IF;
END;
$$;

CREATE TABLE pg_temp.snap (label text PRIMARY KEY, val text);
GRANT ALL ON pg_temp.snap TO PUBLIC;
CREATE FUNCTION pg_temp.keep(p_label text, p_val text) RETURNS void LANGUAGE sql
AS $$ INSERT INTO pg_temp.snap VALUES (p_label, p_val) ON CONFLICT (label) DO UPDATE SET val = EXCLUDED.val $$;
CREATE FUNCTION pg_temp.id(p_label text) RETURNS uuid LANGUAGE sql
AS $$ SELECT CASE WHEN val ~ '^[0-9a-f-]{36}$' THEN val::uuid END FROM pg_temp.snap WHERE label = p_label $$;
GRANT EXECUTE ON FUNCTION pg_temp.id(text) TO PUBLIC;

-- One call as user p_sub (the client, through RLS): the value, or ERR:<hint or SQLSTATE>.
CREATE FUNCTION pg_temp.call(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_val text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
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
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text), pg_temp.write(uuid, text) TO PUBLIC;

CREATE FUNCTION pg_temp.j(p_res text, p_field text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    IF p_res IS NULL OR p_res LIKE 'ERR:%' THEN RETURN p_res; END IF;
    RETURN p_res::jsonb ->> p_field;
END;
$$;
CREATE FUNCTION pg_temp.provider(p_user int) RETURNS void LANGUAGE sql AS $$
    UPDATE public.households SET nafaqah_provider_user_id = CASE WHEN p_user = 0 THEN NULL ELSE pg_temp.u(p_user) END
    WHERE id = pg_temp.h(1);
$$;
-- What the per-account helper answers user p_n, for each of: WA1, WC, an id of nothing, H's bank,
-- K's bank, the other household's bank, NULL.
CREATE FUNCTION pg_temp.hidden_row(p_n int) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(pg_temp.call(pg_temp.u(p_n), CASE WHEN x.acc IS NULL
                                                         THEN 'SELECT public.nafaqah_wife_account_hidden(NULL)::text'
                                                         ELSE format('SELECT public.nafaqah_wife_account_hidden(%L)::text', x.acc) END),
                      ',' ORDER BY x.n)
    FROM (VALUES (1, pg_temp.id('WA1')), (2, pg_temp.id('WC')), (3, 'e71f0000-0000-0000-0000-000000000099'::uuid),
                 (4, pg_temp.a(1)), (5, pg_temp.a(4)), (6, pg_temp.a(9)), (7, NULL::uuid)) AS x(n, acc);
$$;
-- Every function of the public schema a client may call with no argument and that only reads
-- (stable or immutable; triggers aside), called as user p_n: '<name>=<answer>' joined by ' ; '.
CREATE FUNCTION pg_temp.zero_arg_answers(p_n int) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(p.proname || '=' || pg_temp.call(pg_temp.u(p_n),
                      format('SELECT string_agg(r::text, %L) FROM public.%I() AS r', ',', p.proname)), ' ; ' ORDER BY p.proname)
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.pronargs = 0 AND p.prokind = 'f'
      AND p.provolatile IN ('s', 'i')
      AND p.prorettype NOT IN ('trigger'::regtype, 'event_trigger'::regtype)
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin, provider and primary admin; wife W(2); co-wife W2(3); member K(4);
--        admin C(5) who is not a wife; wife WA(6) who is an admin. F2(2): its only member X(7).
-- Accounts: H's bank a(1) 10000; W's bank a(2) 1000; C's bank a(3) 1000; K's bank a(4) 500;
-- X's bank a(9) in F2.
-- WA1: W's wife account, made by H, funded 620 by H; on it her advance t(11) 70. WC: W2's wife
-- account, made by H, with nothing on it at all (no row, no transfer). K's own expense t(16) 15 on
-- his bank; C's own expense t(15) 25 on his.
DO $$
DECLARE
    v_res text;
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't71-' || n || '@test.local', jsonb_build_object('display_name', 'T71 User ' || n)
    FROM generate_series(1, 7) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T71 H1', 'T71CODE000000001', 'family', 27),
        (pg_temp.h(2), 'T71 H2', 'T71CODE000000002', 'family', 27);
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'provider', true),
        (pg_temp.h(1), pg_temp.u(2), 'member', 'spouse', true),
        (pg_temp.h(1), pg_temp.u(3), 'member', 'spouse', true),
        (pg_temp.h(1), pg_temp.u(4), 'member', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(5), 'admin', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(6), 'admin', 'spouse', true),
        (pg_temp.h(2), pg_temp.u(7), 'admin', 'provider', true);
    UPDATE public.users u SET household_id = m.household_id, role = m.role, financial_role = m.financial_role
    FROM public.household_memberships m WHERE m.user_id = u.id AND m.household_id IN (pg_temp.h(1), pg_temp.h(2));
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(7), nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T71 H bank', 'bank', 10000, false, false, 'SAR'),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(2), 'T71 W bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(3), pg_temp.h(1), pg_temp.u(5), 'T71 C bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(4), pg_temp.h(1), pg_temp.u(4), 'T71 K bank', 'bank', 500, false, false, 'SAR'),
        (pg_temp.a(9), pg_temp.h(2), pg_temp.u(7), 'T71 X bank', 'bank', 500, false, false, 'SAR');

    v_res := pg_temp.call(pg_temp.u(1), format('SELECT public.create_wife_account(%L, %L, %L, NULL)::text', pg_temp.h(1), pg_temp.u(2), 'T71 her card'));
    PERFORM pg_temp.keep('WA1', pg_temp.j(v_res, 'id'));
    v_res := pg_temp.call(pg_temp.u(1), format('SELECT public.create_wife_account(%L, %L, %L, NULL)::text', pg_temp.h(1), pg_temp.u(3), 'T71 her card 2'));
    PERFORM pg_temp.keep('WC', pg_temp.j(v_res, 'id'));
    PERFORM pg_temp.check('fixture: both wife accounts made', (pg_temp.id('WA1') IS NOT NULL AND pg_temp.id('WC') IS NOT NULL)::text, 'true');
    PERFORM pg_temp.check('fixture: H funds WA1', pg_temp.call(pg_temp.u(1), format(
        'SELECT (public.transfer_between_accounts(%L, %L, %L, 620, 0, %L) ->> %L)', pg_temp.h(1), pg_temp.a(1), pg_temp.id('WA1'), 'fund', 'notes')), 'fund');
    PERFORM pg_temp.check('fixture: her advance on WA1', pg_temp.write(pg_temp.u(2), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, '
        'nafaqah_class, nafaqah_spouse_id, account_id) VALUES (%L, %L, %L, 70, %L, %L, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(11), pg_temp.h(1), pg_temp.u(2), 'T71 advance', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me',
        'wife_reimbursable', pg_temp.u(2), pg_temp.id('WA1'))), '1');
    PERFORM pg_temp.check('fixture: K''s expense', pg_temp.write(pg_temp.u(4), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, account_id) '
        'VALUES (%L, %L, %L, 15, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(16), pg_temp.h(1), pg_temp.u(4), 'T71 K', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', pg_temp.a(4))), '1');
    PERFORM pg_temp.check('fixture: C''s expense', pg_temp.write(pg_temp.u(5), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, account_id) '
        'VALUES (%L, %L, %L, 25, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(15), pg_temp.h(1), pg_temp.u(5), 'T71 C', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', pg_temp.a(3))), '1');
    PERFORM pg_temp.check('fixture: WC has nothing on it',
        ((SELECT count(*) FROM public.transactions WHERE account_id = pg_temp.id('WC'))
         + (SELECT count(*) FROM public.account_transfers WHERE pg_temp.id('WC') IN (from_account_id, to_account_id)))::text, '0');
    -- Who reads which (accounts_select): WA1 by H and W; WC by H and W2.
    PERFORM pg_temp.check('fixture: WA1 is read by H and W only', (
        SELECT string_agg(pg_temp.call(pg_temp.u(n), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('WA1'))), ',' ORDER BY n)
        FROM generate_series(1, 6) AS n), '1,1,0,0,0,0');
    PERFORM pg_temp.check('fixture: WC is read by H and W2 only', (
        SELECT string_agg(pg_temp.call(pg_temp.u(n), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('WC'))), ',' ORDER BY n)
        FROM generate_series(1, 6) AS n), '1,0,1,0,0,0');
END $$;

-- ── CHK-01: no callable function lists the wife accounts hidden from its caller ───────────────
-- The auditor's table: K, C, WA got both ids (WA1 and WC), W got WC, W2 got WA1, from
-- /rpc/nafaqah_caller_hidden_wife_accounts. Now no function a client calls without an argument
-- names a wife account its caller does not read: not that one (gone), and none other.
DO $$
DECLARE
    v_n int;
    v_answers text;
    v_leaks text := '';
BEGIN
    FOR v_n IN 1..6 LOOP
        v_answers := pg_temp.zero_arg_answers(v_n);
        IF position(pg_temp.id('WA1')::text IN v_answers) > 0
           AND pg_temp.call(pg_temp.u(v_n), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('WA1'))) = '0' THEN
            v_leaks := v_leaks || ' user ' || v_n || ' learns WA1;';
        END IF;
        IF position(pg_temp.id('WC')::text IN v_answers) > 0
           AND pg_temp.call(pg_temp.u(v_n), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('WC'))) = '0' THEN
            v_leaks := v_leaks || ' user ' || v_n || ' learns WC;';
        END IF;
    END LOOP;
    PERFORM pg_temp.check('CHK-01 no argument-less callable function names a wife account its caller does not read', v_leaks, '');
    -- The functions it called (so that a rename cannot make the check above vacuous): the two
    -- caller helpers of 001200 and 001300 among them.
    PERFORM pg_temp.check('CHK-01 the helpers above were called',
        (position('nafaqah_caller_hidden_wives=' IN pg_temp.zero_arg_answers(4)) > 0
         AND position('nafaqah_caller_manages_ledgers=' IN pg_temp.zero_arg_answers(4)) > 0
         AND position('nafaqah_caller_sees_allowances=' IN pg_temp.zero_arg_answers(4)) > 0)::text, 'true');
    PERFORM pg_temp.check('CHK-01 the list helper is gone', (to_regprocedure('public.nafaqah_caller_hidden_wife_accounts()') IS NULL)::text, 'true');

    -- Of the SECURITY DEFINER functions a client may call without an argument, only one answers
    -- with ids: the wives of the caller's household whose purchases they do not read (each of them
    -- a member every member reads in users, below). Every other answers about the caller alone.
    PERFORM pg_temp.check('CHK-01 no other argument-less definer function a client calls answers with ids',
        (SELECT COALESCE(string_agg(p.oid::regprocedure::text, ',' ORDER BY p.proname), '')
         FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.pronargs = 0 AND p.prosecdef AND p.prokind = 'f'
           AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
           AND (p.prorettype IN ('uuid[]'::regtype, 'text[]'::regtype) OR (p.proretset AND p.prorettype = 'uuid'::regtype))),
        'nafaqah_caller_hidden_wives()');
    FOR v_n IN 1..6 LOOP
        PERFORM pg_temp.check('CHK-01 nafaqah_caller_hidden_wives names only wives user ' || v_n || ' reads anyway',
            pg_temp.call(pg_temp.u(v_n), 'SELECT (NOT EXISTS (SELECT unnest(public.nafaqah_caller_hidden_wives()) '
                                          'EXCEPT SELECT u.id FROM public.users u WHERE u.financial_role = ''spouse''))::text'), 'true');
    END LOOP;
END $$;

-- The per-account helper the write policies use instead. For each caller, in order: WA1, WC, an
-- id of nothing, H's bank, K's bank, F2's bank, NULL. True for a wife account of the caller's
-- household they may not see, and for anything that is no account of their household: an id of
-- nothing gets the answer of a hidden wife account, so it tells nobody that one exists (the rule
-- of nafaqah_receipt_hidden, review R3B-04). False for every other account of their household.
DO $$
BEGIN
    PERFORM pg_temp.check('CHK-01 helper as H (owner of both)', pg_temp.hidden_row(1), 'false,false,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 helper as W (WA1 is hers)', pg_temp.hidden_row(2), 'false,true,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 helper as W2 (WC is hers)', pg_temp.hidden_row(3), 'true,false,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 helper as K', pg_temp.hidden_row(4), 'true,true,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 helper as C (husband there)', pg_temp.hidden_row(5), 'true,true,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 helper as WA (co-wife admin)', pg_temp.hidden_row(6), 'true,true,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 helper as X (another household)', pg_temp.hidden_row(7), 'true,true,true,true,true,false,true');
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('CHK-01 husband gone: helper as C', pg_temp.hidden_row(5), 'false,false,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 husband gone: helper as WA', pg_temp.hidden_row(6), 'true,true,true,false,false,true,true');
    PERFORM pg_temp.check('CHK-01 husband gone: helper as K', pg_temp.hidden_row(4), 'true,true,true,false,false,true,true');
    PERFORM pg_temp.provider(1);
    -- Its shape and privileges: a definer function with a pinned search_path, stable, called by
    -- the policies as the caller (so authenticated executes it), never by anon.
    PERFORM pg_temp.check('CHK-01 helper shape and privileges',
        COALESCE((SELECT concat_ws(',', p.prosecdef, p.provolatile, pg_get_function_result(p.oid),
                                   p.proconfig::text LIKE '%search_path=public, pg_temp%',
                                   has_function_privilege('authenticated', p.oid, 'EXECUTE'),
                                   has_function_privilege('anon', p.oid, 'EXECUTE'))
                  FROM pg_proc p WHERE p.oid = to_regprocedure('public.nafaqah_wife_account_hidden(uuid)')), 'missing'),
        'true,s,boolean,true,true,false');
    -- The three policy clauses that used the list ask about the row's own account now.
    PERFORM pg_temp.check('CHK-01 the write policies use the per-account helper',
        (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transactions' AND cmd IN ('UPDATE', 'DELETE')
           AND qual LIKE '%NOT nafaqah_wife_account_hidden(account_id)%')::text || '|'
        || (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transactions' AND cmd = 'UPDATE'
              AND with_check LIKE '%NOT nafaqah_wife_account_hidden(account_id)%')::text || '|'
        || (SELECT count(*) FROM pg_policies WHERE qual LIKE '%nafaqah_caller_hidden_wife_accounts%'
              OR with_check LIKE '%nafaqah_caller_hidden_wife_accounts%')::text,
        '2|1|0');
END $$;

-- The rule the helper serves is unchanged (test 70 has every case): who sees WA1 edits and
-- deletes its rows; anyone else reaches none of them, also by a statement that names no row;
-- every other row keeps the creator-or-admin rule.
DO $$
BEGIN
    PERFORM pg_temp.check('CHK-01 K edits her advance on WA1', pg_temp.write(pg_temp.u(4), format(
        'UPDATE public.transactions SET amount = 1 WHERE id = %L', pg_temp.t(11))), '0');
    PERFORM pg_temp.check('CHK-01 W2 deletes her advance on WA1', pg_temp.write(pg_temp.u(3), format(
        'DELETE FROM public.transactions WHERE id = %L', pg_temp.t(11))), '0');
    PERFORM pg_temp.check('CHK-01 WA (co-wife admin) edits her advance on WA1', pg_temp.write(pg_temp.u(6), format(
        'UPDATE public.transactions SET amount = 1 WHERE id = %L', pg_temp.t(11))), '0');
    PERFORM pg_temp.check('CHK-01 C (husband there) blind update reaches his and K''s rows, not hers on WA1',
        pg_temp.write(pg_temp.u(5), 'UPDATE public.transactions SET notes = ''blind'''), '2');
    PERFORM pg_temp.check('CHK-01 her row on WA1 untouched',
        (SELECT amount::text || '|' || COALESCE(notes, '-') FROM public.transactions WHERE id = pg_temp.t(11)), '70.00|-');
    PERFORM pg_temp.check('CHK-01 C still edits K''s expense on K''s bank (rule 04)', pg_temp.write(pg_temp.u(5), format(
        'UPDATE public.transactions SET amount = 16 WHERE id = %L', pg_temp.t(16))), '1');
    PERFORM pg_temp.check('CHK-01 W edits her advance on WA1', pg_temp.write(pg_temp.u(2), format(
        'UPDATE public.transactions SET amount = 75 WHERE id = %L', pg_temp.t(11))), '1');
    PERFORM pg_temp.check('CHK-01 W cannot move her advance onto W2''s WC', (pg_temp.write(pg_temp.u(2), format(
        'UPDATE public.transactions SET account_id = %L WHERE id = %L', pg_temp.id('WC'), pg_temp.t(11))) LIKE 'ERR:%')::text, 'true');
    PERFORM pg_temp.check('CHK-01 H deletes her advance on WA1', pg_temp.write(pg_temp.u(1), format(
        'DELETE FROM public.transactions WHERE id = %L', pg_temp.t(11))), '1');
    PERFORM pg_temp.check('CHK-01 WA1 back to what H funded', (SELECT balance::text FROM public.accounts WHERE id = pg_temp.id('WA1')), '620.00');
END $$;

DO $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(label || ' => got ' || COALESCE(got, 'NULL') || ', expected ' || COALESCE(want, 'NULL'), E'\n' ORDER BY n)
    INTO v_list FROM pg_temp.fails;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION E'Test 71 failed:\n%', v_list;
    END IF;
    RAISE NOTICE 'PASSED: CHK-01: no callable function lists the wife accounts hidden from its caller.';
END $$;

ROLLBACK;
