-- ============================================================================
-- Test 12 (audit DB-06, DB-07): ledger amount precision and income_records
-- append-only enforcement
--
-- DB-06: transfer_between_accounts / record_income take unconstrained NUMERIC
--        and write NUMERIC(14,2) columns. Amounts with a third decimal are
--        rounded independently on each side, so 1.005 debits 1.00 and credits
--        1.01: repeated transfers mint money. record_income also accepted
--        negative components and malformed cycle keys.
-- DB-07: income_insert_household still allowed direct client INSERTs into the
--        income ledger, bypassing record_income (no balance update, any account
--        in the household, any sign).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('d6000000-0000-0000-0000-000000000001', 'db06-owner@test.local'),
        ('d6000000-0000-0000-0000-000000000002', 'db06-member@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('d6aa0000-0000-0000-0000-000000000001', 'DB06 Home', 'DB06HOMECODE0001');

    UPDATE public.users SET household_id = 'd6aa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd6000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'd6aa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'd6000000-0000-0000-0000-000000000002';

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('d6ac0000-0000-0000-0000-000000000001', 'd6aa0000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001', 'Owner A', 'bank', 100.00, false),
        ('d6ac0000-0000-0000-0000-000000000002', 'd6aa0000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001', 'Owner B', 'bank', 0.00, false);
END $$;

CREATE FUNCTION pg_temp.as_user(p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows int;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    RETURN 'ok';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(text, text) TO authenticated;

DO $$
DECLARE
    v_res text;
    v_a numeric;
    v_b numeric;
    v_owner text := 'd6000000-0000-0000-0000-000000000001';
BEGIN
    -- 1. Sub-halala transfer amounts must be rejected (no rounding mint)
    v_res := pg_temp.as_user(v_owner, $q$SELECT public.transfer_between_accounts(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        'd6ac0000-0000-0000-0000-000000000002', 1.005, 0)$q$);
    v_res := v_res || '/' || pg_temp.as_user(v_owner, $q$SELECT public.transfer_between_accounts(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000002',
        'd6ac0000-0000-0000-0000-000000000001', 1.005, 0)$q$);

    SELECT balance INTO v_a FROM public.accounts WHERE id = 'd6ac0000-0000-0000-0000-000000000001';
    SELECT balance INTO v_b FROM public.accounts WHERE id = 'd6ac0000-0000-0000-0000-000000000002';
    IF v_a + v_b <> 100.00 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-06): transfers with 3-decimal amounts changed total money from 100.00 to % (A=%, B=%, results %)',
            v_a + v_b, v_a, v_b, v_res;
    END IF;
    IF v_res <> '22023/22023' THEN
        RAISE EXCEPTION 'BUG (DB-06): sub-halala transfer not rejected with 22023 (got %)', v_res;
    END IF;

    v_res := pg_temp.as_user(v_owner, $q$SELECT public.transfer_between_accounts(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        'd6ac0000-0000-0000-0000-000000000002', 10.00, 0.001)$q$);
    IF v_res <> '22023' THEN
        RAISE EXCEPTION 'BUG (DB-06): sub-halala transfer fee not rejected (got %)', v_res;
    END IF;
    RAISE NOTICE 'PASSED: transfers reject amounts/fees with more than 2 decimals.';

    -- 2. Valid 2-decimal transfer still conserves money exactly
    v_res := pg_temp.as_user(v_owner, $q$SELECT public.transfer_between_accounts(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        'd6ac0000-0000-0000-0000-000000000002', 10.25, 0.50)$q$);
    IF v_res <> 'ok' THEN
        RAISE EXCEPTION 'Valid transfer failed: %', v_res;
    END IF;
    SELECT balance INTO v_a FROM public.accounts WHERE id = 'd6ac0000-0000-0000-0000-000000000001';
    SELECT balance INTO v_b FROM public.accounts WHERE id = 'd6ac0000-0000-0000-0000-000000000002';
    IF v_a <> 89.25 OR v_b <> 10.25 THEN
        RAISE EXCEPTION 'Valid transfer produced wrong balances (A=%, B=%)', v_a, v_b;
    END IF;
    RAISE NOTICE 'PASSED: valid transfer debits amount+fee and credits amount exactly.';

    -- 3. record_income validation
    v_res := pg_temp.as_user(v_owner, $q$SELECT public.record_income(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        '2026-11', 'salary', 'Salary', 1000.005)$q$);
    IF v_res <> '22023' THEN
        RAISE EXCEPTION 'BUG (DB-06): record_income accepted a 3-decimal amount (got %)', v_res;
    END IF;

    v_res := pg_temp.as_user(v_owner, $q$SELECT public.record_income(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        '2026-11', 'salary', 'Salary', 1000, -200, 0, 0)$q$);
    IF v_res <> '22023' THEN
        RAISE EXCEPTION 'BUG (DB-06): record_income accepted a negative overtime component (got %)', v_res;
    END IF;

    v_res := pg_temp.as_user(v_owner, $q$SELECT public.record_income(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        '2026-11', 'salary', 'Salary', 1000, 0, 0, -300)$q$);
    IF v_res <> '22023' THEN
        RAISE EXCEPTION 'BUG (DB-06): record_income accepted negative deductions (net inflated) (got %)', v_res;
    END IF;

    v_res := pg_temp.as_user(v_owner, $q$SELECT public.record_income(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        '2026-13', 'salary', 'Salary', 1000)$q$);
    IF v_res <> '22023' THEN
        RAISE EXCEPTION 'BUG (DB-06): record_income accepted malformed cycle_key 2026-13 (got %)', v_res;
    END IF;

    SELECT balance INTO v_a FROM public.accounts WHERE id = 'd6ac0000-0000-0000-0000-000000000001';
    IF v_a <> 89.25 THEN
        RAISE EXCEPTION 'BUG (DB-06): rejected record_income calls changed the balance to %', v_a;
    END IF;

    -- NULL cycle_key is derived from received_at and the household payday
    v_res := pg_temp.as_user(v_owner, $q$SELECT public.record_income(
        'd6aa0000-0000-0000-0000-000000000001', 'd6ac0000-0000-0000-0000-000000000001',
        NULL, 'salary', 'Salary', 1000, 0, 0, 0, '2026-10-27 09:00:00+03')$q$);
    IF v_res <> 'ok' THEN
        RAISE EXCEPTION 'record_income with derived cycle_key failed: %', v_res;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.income_records
                   WHERE account_id = 'd6ac0000-0000-0000-0000-000000000001' AND cycle_key = '2026-11') THEN
        RAISE EXCEPTION 'BUG (DB-06): cycle_key not derived from received_at (expected 2026-11)';
    END IF;
    RAISE NOTICE 'PASSED: record_income validates precision, component signs and cycle_key.';

    -- 4. Direct client INSERT into the income ledger must be blocked (DB-07)
    v_res := pg_temp.as_user('d6000000-0000-0000-0000-000000000002', $q$INSERT INTO public.income_records (
        household_id, user_id, account_id, cycle_key, source_type, title, net_amount)
        VALUES ('d6aa0000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000002',
                'd6ac0000-0000-0000-0000-000000000001', '2026-11', 'salary', 'forged', -5000)$q$);
    IF v_res = 'ok' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-07): client inserted a forged income record directly';
    END IF;
    RAISE NOTICE 'PASSED: income_records accepts writes only through record_income.';
END $$;

ROLLBACK;
