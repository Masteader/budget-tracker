-- ============================================================================
-- Test 46: void_income_record stays fixed in the order production runs the files
--
-- Migrations: 20261105000000_account_deletion_ledger_fks.sql, 20261105000500_void_income_single_subtraction.sql
--
-- Production has no migration history. 000500 goes out early as a hotfix, then the chain
-- runs around it. If 000000 redefined the function it would bring back the double
-- subtraction until 000500 ran again. run_tests.py runs this file on a filename-order
-- rebuild and, through rollout_order_check, on a database where 000500 ran first, and
-- again after 000500 runs a second time. Whichever order, this must hold:
--   1. A void takes the income off the balance exactly once.
--   2. The function has one writer of the balance, the trigger, and refuses on a mismatch.
--   3. On a row with no creator a regular member is refused and an admin is allowed,
--      with the balance exact. That needs both 000000 (a nullable creator) and 000500
--      (IS DISTINCT FROM), which is the case test 36 covers.
--   4. 000000 does not define the function at all, so no later replay can undo the fix.
--      Checked by the catalog in (2): the body in place is 000500's.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.as_user(p_sub uuid, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
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
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated;

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

CREATE FUNCTION pg_temp.income(p_amount numeric)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.as_user('e4600000-0000-0000-0000-00000000000a', format(
        $q$SELECT public.record_income('e46a0000-0000-0000-0000-000000000001', 'e46c0000-0000-0000-0000-000000000001', '2026-11', 'salary', 'T46 income', %s, 0, 0, 0, now(), NULL)::text$q$,
        p_amount));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: record_income: %', v_res; END IF;
    RETURN (v_res::jsonb ->> 'id')::uuid;
END;
$$;

CREATE FUNCTION pg_temp.balance()
RETURNS text
LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = 'e46c0000-0000-0000-0000-000000000001' $$;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e4600000-0000-0000-0000-00000000000a', 't46-admin@test.local'),
        ('e4600000-0000-0000-0000-00000000000b', 't46-member@test.local');
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        ('e46a0000-0000-0000-0000-000000000001', 'T46', 'T46CODE000000001', 'roommates');
    UPDATE public.users SET household_id = 'e46a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'e4600000-0000-0000-0000-00000000000a';
    UPDATE public.users SET household_id = 'e46a0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'peer'
    WHERE id = 'e4600000-0000-0000-0000-00000000000b';
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('e46c0000-0000-0000-0000-000000000001', 'e46a0000-0000-0000-0000-000000000001', 'e4600000-0000-0000-0000-00000000000a', 'Pool', 'shared_pool', 1000, true);
END $$;

-- 1. Once, and exact --------------------------------------------------------------------
DO $$
DECLARE
    v_id uuid := pg_temp.income(250.75);
    v_res jsonb;
BEGIN
    PERFORM pg_temp.expect('after the income', pg_temp.balance(), '1250.75');
    v_res := pg_temp.as_user('e4600000-0000-0000-0000-00000000000a', format('SELECT public.void_income_record(%L)::text', v_id))::jsonb;
    PERFORM pg_temp.expect('a void subtracts once', pg_temp.balance(), '1000.00');
    PERFORM pg_temp.expect('new_balance is the stored balance', (v_res ->> 'new_balance')::numeric::text, '1000.00');
    RAISE NOTICE 'PASSED: a void subtracts once, whatever order the files ran in.';
END $$;

-- 2. The body in place is the fixed one -------------------------------------------------
DO $$
DECLARE
    v_src text := pg_get_functiondef('public.void_income_record(uuid)'::regprocedure);
BEGIN
    IF v_src ~* 'UPDATE public\.accounts' THEN
        RAISE EXCEPTION 'void_income_record writes the balance itself: the double subtraction is back';
    END IF;
    IF v_src !~ 'void_balance_mismatch' THEN
        RAISE EXCEPTION 'void_income_record lost its balance check';
    END IF;
    IF v_src !~* 'user_id IS DISTINCT FROM v_caller_uid' THEN
        RAISE EXCEPTION 'void_income_record can treat a NULL creator as allowed';
    END IF;
    RAISE NOTICE 'PASSED: the body in place is the fixed one.';
END $$;

-- 3. A row with no creator --------------------------------------------------------------
DO $$
DECLARE
    v_id uuid := pg_temp.income(60);
BEGIN
    UPDATE public.income_records SET user_id = NULL WHERE id = v_id;
    PERFORM pg_temp.expect('a regular member is refused',
        pg_temp.as_user('e4600000-0000-0000-0000-00000000000b', format('SELECT public.void_income_record(%L)::text', v_id)),
        'ERR:42501');
    PERFORM pg_temp.expect('balance untouched', pg_temp.balance(), '1060.00');
    PERFORM pg_temp.as_user('e4600000-0000-0000-0000-00000000000a', format('SELECT public.void_income_record(%L)::text', v_id));
    PERFORM pg_temp.expect('an admin voids it, once', pg_temp.balance(), '1000.00');
    PERFORM pg_temp.expect('row gone', (SELECT count(*)::text FROM public.income_records WHERE id = v_id), '0');
    RAISE NOTICE 'PASSED: a row with no creator is safe and the balance exact.';
END $$;

-- 4. REVOKE TRUNCATE on live, then 000600: clients still hold nothing --------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('anon on inquiries',
        has_table_privilege('anon', 'public.inquiries', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')::text, 'false');
    PERFORM pg_temp.expect('authenticated on inquiries',
        has_table_privilege('authenticated', 'public.inquiries', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')::text, 'false');
    PERFORM pg_temp.expect('anon on the catalog',
        has_table_privilege('anon', 'public.cost_control_templates', 'SELECT,TRUNCATE')::text, 'false');
    PERFORM pg_temp.expect('signed in reads the catalog',
        has_table_privilege('authenticated', 'public.cost_control_templates', 'SELECT')::text, 'true');
    PERFORM pg_temp.expect('signed in cannot truncate it',
        has_table_privilege('authenticated', 'public.cost_control_templates', 'TRUNCATE')::text, 'false');
    RAISE NOTICE 'PASSED: 000600 leaves the same privileges, TRUNCATE revoked already or not.';
END $$;

ROLLBACK;
