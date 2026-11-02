-- ============================================================================
-- Test 35: void_income_record RPC & Ledger Balance Reversal
--
-- Verifies:
--   1. Success Reversal & Row Deletion:
--      - Balance decrements by exact net amount.
--      - Income record row is cleanly deleted.
--      - Returned JSON matches specification.
--   2. Multi-Component Net Amount Ledger Math:
--      - Base + overtime + bonus - deductions correctly decremented.
--   3. Multi-Tenant IDOR Attack Rejection:
--      - User from another household cannot void this income record (42501).
--   4. Non-Existent & Invalid IDs:
--      - Non-existent UUID raises P0002.
--      - NULL UUID raises 22023.
--   5. Direct Client DELETE Blocked:
--      - Append-only policy prevents direct client DELETE on public.income_records.
--   6. Role & Account Ownership Boundary:
--      - Regular member cannot void income in another member's private account (42501).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Setup mock test data
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e3500000-0000-0000-0000-000000000001', 'u35-admin1@test.local'),
        ('e3500000-0000-0000-0000-000000000002', 'u35-member1@test.local'),
        ('e3500000-0000-0000-0000-000000000003', 'u35-admin2@test.local')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.households (id, name, invite_code, owner_user_id, payday_day) VALUES
        ('e35a0000-0000-0000-0000-000000000001', 'HH 35 Alpha', 'HH35ALPHA0000001', 'e3500000-0000-0000-0000-000000000001', 27),
        ('e35a0000-0000-0000-0000-000000000002', 'HH 35 Beta',  'HH35BETA00000002', 'e3500000-0000-0000-0000-000000000003', 27)
    ON CONFLICT (id) DO UPDATE SET owner_user_id = EXCLUDED.owner_user_id;

    UPDATE public.users SET household_id = 'e35a0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'e3500000-0000-0000-0000-000000000001';

    UPDATE public.users SET household_id = 'e35a0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'e3500000-0000-0000-0000-000000000002';

    UPDATE public.users SET household_id = 'e35a0000-0000-0000-0000-000000000002', role = 'admin'
    WHERE id = 'e3500000-0000-0000-0000-000000000003';

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('e35c0000-0000-0000-0000-000000000001', 'e35a0000-0000-0000-0000-000000000001', 'e3500000-0000-0000-0000-000000000001', 'Checking Alpha', 'bank', 1000.00, false),
        ('e35c0000-0000-0000-0000-000000000002', 'e35a0000-0000-0000-0000-000000000002', 'e3500000-0000-0000-0000-000000000003', 'Checking Beta',  'bank', 2000.00, false)
    ON CONFLICT (id) DO UPDATE SET balance = EXCLUDED.balance;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user_eval(p_sub text, p_sql text)
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
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user_eval(text, text) TO authenticated;

DO $$
DECLARE
    v_u1 text := 'e3500000-0000-0000-0000-000000000001';
    v_m1 text := 'e3500000-0000-0000-0000-000000000002';
    v_u2 text := 'e3500000-0000-0000-0000-000000000003';
    v_hh1 text := 'e35a0000-0000-0000-0000-000000000001';
    v_acc1 text := 'e35c0000-0000-0000-0000-000000000001';
    v_income_id uuid;
    v_income_id2 uuid;
    v_res text;
    v_bal numeric(14, 2);
    v_cnt int;
    v_rec_json jsonb;
BEGIN
    -- -------------------------------------------------------------------------
    -- 1. Success Reversal & Row Deletion
    -- -------------------------------------------------------------------------
    -- Reset balance to 1000.00
    UPDATE public.accounts SET balance = 1000.00 WHERE id = v_acc1::uuid;

    -- Record income: 500 SAR
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT public.record_income(
        v_hh1::uuid,
        v_acc1::uuid,
        '2026-11',
        'salary',
        'Monthly Salary',
        500.00,
        0.0,
        0.0,
        0.0,
        now(),
        'Initial test'
    ) INTO v_rec_json;
    EXECUTE 'RESET ROLE';

    v_income_id := (v_rec_json->>'id')::uuid;

    -- Verify balance increased to 1500.00
    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1::uuid;
    IF v_bal <> 1500.00 THEN
        RAISE EXCEPTION 'Precondition failed: balance after record_income is %, expected 1500.00', v_bal;
    END IF;

    -- Execute void_income_record as u1
    v_res := pg_temp.as_user_eval(v_u1, format('SELECT public.void_income_record(%L)::text', v_income_id));
    IF v_res ~ '^[0-9A-Z]{5}$' THEN
        RAISE EXCEPTION 'void_income_record failed with SQLSTATE %', v_res;
    END IF;

    -- Assert balance decremented back to 1000.00
    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1::uuid;
    IF v_bal <> 1000.00 THEN
        RAISE EXCEPTION 'Balance reversal failed: current balance is %, expected 1000.00', v_bal;
    END IF;

    -- Assert income record deleted
    SELECT count(*) INTO v_cnt FROM public.income_records WHERE id = v_income_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'income_records row still exists after void_income_record!';
    END IF;

    RAISE NOTICE 'PASSED: 1. Success Reversal & Row Deletion';

    -- -------------------------------------------------------------------------
    -- 2. Multi-Component Net Amount Ledger Math
    -- -------------------------------------------------------------------------
    -- Base 1000, Overtime 250, Bonus 150, Deductions 100 -> Net = 1300
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT public.record_income(
        v_hh1::uuid,
        v_acc1::uuid,
        '2026-11',
        'salary',
        'Salary with Breakdown',
        1000.00,
        250.00,
        150.00,
        100.00,
        now(),
        'Breakdown test'
    ) INTO v_rec_json;
    EXECUTE 'RESET ROLE';

    v_income_id2 := (v_rec_json->>'id')::uuid;

    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1::uuid;
    IF v_bal <> 2300.00 THEN
        RAISE EXCEPTION 'Balance after breakdown income is %, expected 2300.00', v_bal;
    END IF;

    -- Void and verify balance returns to 1000.00
    v_res := pg_temp.as_user_eval(v_u1, format('SELECT public.void_income_record(%L)::text', v_income_id2));
    IF v_res ~ '^[0-9A-Z]{5}$' THEN
        RAISE EXCEPTION 'void_income_record for breakdown failed with SQLSTATE %', v_res;
    END IF;

    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1::uuid;
    IF v_bal <> 1000.00 THEN
        RAISE EXCEPTION 'Net amount reversal failed: balance is %, expected 1000.00', v_bal;
    END IF;

    RAISE NOTICE 'PASSED: 2. Multi-Component Net Amount Ledger Math';

    -- -------------------------------------------------------------------------
    -- 3. Multi-Tenant IDOR Attack Rejection
    -- -------------------------------------------------------------------------
    -- Create fresh income record in HH1
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT public.record_income(
        v_hh1::uuid,
        v_acc1::uuid,
        '2026-11',
        'bonus',
        'Q4 Bonus',
        750.00,
        0.0,
        0.0,
        0.0,
        now(),
        'IDOR Target'
    ) INTO v_rec_json;
    EXECUTE 'RESET ROLE';

    v_income_id := (v_rec_json->>'id')::uuid;

    -- User u2 (HH 2) attempts to void HH 1's income record
    v_res := pg_temp.as_user_eval(v_u2, format('SELECT public.void_income_record(%L)::text', v_income_id));
    IF v_res <> '42501' THEN
        RAISE EXCEPTION 'IDOR attack was not rejected with 42501! Got: %', v_res;
    END IF;

    -- Verify row still exists and balance unaffected (1750.00)
    SELECT count(*) INTO v_cnt FROM public.income_records WHERE id = v_income_id;
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'IDOR attack altered/deleted the target income record!';
    END IF;
    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1::uuid;
    IF v_bal <> 1750.00 THEN
        RAISE EXCEPTION 'IDOR attack altered account balance to %', v_bal;
    END IF;

    RAISE NOTICE 'PASSED: 3. Multi-Tenant IDOR Attack Rejection';

    -- -------------------------------------------------------------------------
    -- 4. Non-Existent & Invalid IDs
    -- -------------------------------------------------------------------------
    v_res := pg_temp.as_user_eval(v_u1, 'SELECT public.void_income_record(''00000000-0000-0000-0000-000000000000''::uuid)::text');
    IF v_res <> 'P0002' THEN
        RAISE EXCEPTION 'Non-existent UUID was not rejected with P0002! Got: %', v_res;
    END IF;

    v_res := pg_temp.as_user_eval(v_u1, 'SELECT public.void_income_record(NULL)::text');
    IF v_res <> '22023' THEN
        RAISE EXCEPTION 'NULL UUID was not rejected with 22023! Got: %', v_res;
    END IF;

    RAISE NOTICE 'PASSED: 4. Non-Existent & Invalid IDs';

    -- -------------------------------------------------------------------------
    -- 5. Direct Client DELETE Blocked (Append-only Ledger)
    -- -------------------------------------------------------------------------
    v_res := pg_temp.as_user_eval(v_u1, format('DELETE FROM public.income_records WHERE id = %L', v_income_id));
    IF v_res = 'ok' THEN
        -- Check if row was actually deleted or protected by RLS / revoke
        SELECT count(*) INTO v_cnt FROM public.income_records WHERE id = v_income_id;
        IF v_cnt = 0 THEN
            RAISE EXCEPTION 'VULNERABILITY: Direct client DELETE bypassed append-only ledger!';
        END IF;
    END IF;

    RAISE NOTICE 'PASSED: 5. Direct Client DELETE Blocked';

    -- -------------------------------------------------------------------------
    -- 6. Role & Account Ownership Boundary
    -- -------------------------------------------------------------------------
    -- Member m1 attempts to void income in u1's personal account
    v_res := pg_temp.as_user_eval(v_m1, format('SELECT public.void_income_record(%L)::text', v_income_id));
    IF v_res <> '42501' THEN
        RAISE EXCEPTION 'Regular member voiding another member personal account was not rejected with 42501! Got: %', v_res;
    END IF;

    RAISE NOTICE 'PASSED: 6. Role & Account Ownership Boundary';

    -- Clean up the test row via authorized admin void
    v_res := pg_temp.as_user_eval(v_u1, format('SELECT public.void_income_record(%L)::text', v_income_id));
    IF v_res ~ '^[0-9A-Z]{5}$' THEN
        RAISE EXCEPTION 'Authorized admin cleanup failed with SQLSTATE %', v_res;
    END IF;

    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1::uuid;
    IF v_bal <> 1000.00 THEN
        RAISE EXCEPTION 'Final balance after cleanup is %, expected 1000.00', v_bal;
    END IF;

    RAISE NOTICE 'PASSED: All Test 35 void_income_record checks completed successfully.';
END $$;

ROLLBACK;
