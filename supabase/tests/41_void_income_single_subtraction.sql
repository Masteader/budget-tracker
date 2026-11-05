-- ============================================================================
-- Test 41: void_income_record subtracts income once
--
-- Migration: 20261105000500_void_income_single_subtraction.sql
--
-- The RPC subtracted net_amount and then trg_adjust_account_balance_on_income_change
-- subtracted it again on the delete. Test 35 is the original proof; this one adds:
--   1. new_balance in the response equals the stored balance, and the payload's shape
--      is unchanged.
--   2. Several voids on one account each take exactly their own amount.
--   3. Another account does not move.
--   4. If the delete trigger ever stops subtracting, the void refuses and changes
--      nothing, rather than reporting a reversal that did not happen.
--   5. The RPC holds the account row while it reads the balance back.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.as_user(p_sub uuid, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
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

CREATE FUNCTION pg_temp.income(p_amount numeric, p_account uuid DEFAULT 'e41c0000-0000-0000-0000-000000000001')
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.as_user('e4100000-0000-0000-0000-00000000000a', format(
        $q$SELECT public.record_income('e41a0000-0000-0000-0000-000000000001', %L, '2026-11', 'salary', 'T41 income', %s, 0, 0, 0, now(), NULL)::text$q$,
        p_account, p_amount));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: record_income: %', v_res; END IF;
    RETURN (v_res::jsonb ->> 'id')::uuid;
END;
$$;

CREATE FUNCTION pg_temp.balance(p_account uuid DEFAULT 'e41c0000-0000-0000-0000-000000000001')
RETURNS text
LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = p_account $$;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES ('e4100000-0000-0000-0000-00000000000a', 't41-a@test.local');
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        ('e41a0000-0000-0000-0000-000000000001', 'T41', 'T41CODE000000001', 'roommates');
    UPDATE public.users SET household_id = 'e41a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'e4100000-0000-0000-0000-00000000000a';
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('e41c0000-0000-0000-0000-000000000001', 'e41a0000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-00000000000a', 'Pool', 'shared_pool', 1000, true),
        ('e41c0000-0000-0000-0000-000000000002', 'e41a0000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-00000000000a', 'Other', 'bank', 70, false);
END $$;

-- 1, 2, 3 ------------------------------------------------------------------------------
DO $$
DECLARE
    v_a uuid;
    v_b uuid;
    v_res jsonb;
BEGIN
    v_a := pg_temp.income(500);
    v_b := pg_temp.income(120.50);
    PERFORM pg_temp.expect('after two incomes', pg_temp.balance(), '1620.50');

    v_res := pg_temp.as_user('e4100000-0000-0000-0000-00000000000a', format('SELECT public.void_income_record(%L)::text', v_a))::jsonb;
    PERFORM pg_temp.expect('first void takes its own amount once', pg_temp.balance(), '1120.50');
    PERFORM pg_temp.expect('returned new_balance is the stored balance', (v_res ->> 'new_balance')::numeric::text, pg_temp.balance());
    PERFORM pg_temp.expect('reverted amount', (v_res ->> 'reverted_amount')::numeric::text, '500.00');
    PERFORM pg_temp.expect('payload shape unchanged',
        (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(v_res) k),
        'account_id,cycle_key,household_id,id,income_id,net_amount,new_balance,reverted_amount,success,title,user_id,voided_at');

    v_res := pg_temp.as_user('e4100000-0000-0000-0000-00000000000a', format('SELECT public.void_income_record(%L)::text', v_b))::jsonb;
    PERFORM pg_temp.expect('second void takes its own amount once', pg_temp.balance(), '1000.00');
    PERFORM pg_temp.expect('second returned new_balance', (v_res ->> 'new_balance')::numeric::text, pg_temp.balance());
    PERFORM pg_temp.expect('the other account did not move', pg_temp.balance('e41c0000-0000-0000-0000-000000000002'), '70.00');
    RAISE NOTICE 'PASSED: each void subtracts once and new_balance is the stored balance.';
END $$;

-- 4. If the trigger stops subtracting, the void refuses ---------------------------------
DO $$
DECLARE
    v_id uuid;
    v_res text;
BEGIN
    v_id := pg_temp.income(40);
    PERFORM pg_temp.expect('before', pg_temp.balance(), '1040.00');
    ALTER TABLE public.income_records DISABLE TRIGGER trg_adjust_account_balance_on_income_change;
    v_res := pg_temp.as_user('e4100000-0000-0000-0000-00000000000a', format('SELECT public.void_income_record(%L)::text', v_id));
    ALTER TABLE public.income_records ENABLE TRIGGER trg_adjust_account_balance_on_income_change;
    PERFORM pg_temp.expect('refused', v_res, 'ERR:void_balance_mismatch');
    PERFORM pg_temp.expect('row kept', (SELECT count(*)::text FROM public.income_records WHERE id = v_id), '1');
    PERFORM pg_temp.expect('balance unchanged', pg_temp.balance(), '1040.00');
    RAISE NOTICE 'PASSED: a void that cannot reverse the balance refuses and changes nothing.';
END $$;

-- 5. The account row is held across the read-back ---------------------------------------
DO $$
DECLARE
    v_src text := pg_get_functiondef('public.void_income_record(uuid)'::regprocedure);
BEGIN
    IF v_src !~* 'FROM public\.accounts\s+WHERE id = v_income\.account_id\s+FOR UPDATE' THEN
        RAISE EXCEPTION 'void_income_record no longer locks the account row';
    END IF;
    IF v_src ~* 'UPDATE public\.accounts' THEN
        RAISE EXCEPTION 'void_income_record writes the balance itself again';
    END IF;
    RAISE NOTICE 'PASSED: the account row is locked and the trigger is the only writer.';
END $$;

ROLLBACK;
