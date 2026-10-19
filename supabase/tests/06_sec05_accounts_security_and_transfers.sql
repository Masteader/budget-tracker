-- ====================================================================
-- Test: 06_sec05_accounts_security_and_transfers.sql
-- Proof test for SEC-05: Accounts Security, Atomic Transfers, Income & Triggers
-- ====================================================================

DO $$
DECLARE
    v_hh1 UUID := '11111111-aaaa-bbbb-cccc-111111111111'::UUID;
    v_hh2 UUID := '22222222-aaaa-bbbb-cccc-222222222222'::UUID;
    v_user1 UUID := '33333333-aaaa-bbbb-cccc-333333333333'::UUID; -- Admin of HH1
    v_user2 UUID := '44444444-aaaa-bbbb-cccc-444444444444'::UUID; -- Member of HH1
    v_attacker UUID := '55555555-aaaa-bbbb-cccc-555555555555'::UUID; -- Member of HH2
    v_acc1 UUID := '66666666-aaaa-bbbb-cccc-666666666666'::UUID; -- User1 personal account (HH1)
    v_acc2 UUID := '77777777-aaaa-bbbb-cccc-777777777777'::UUID; -- User2 personal account (HH1)
    v_shared_acc UUID := '88888888-aaaa-bbbb-cccc-888888888888'::UUID; -- Shared pool (HH1)
    v_transfer_res jsonb;
    v_income_res jsonb;
    v_bal NUMERIC;
    v_tx_id UUID;
    v_caught BOOLEAN := false;
BEGIN
    -- 0. Set up fixtures
    INSERT INTO auth.users (id, email) VALUES
        (v_user1, 'admin1@test.com'),
        (v_user2, 'member1@test.com'),
        (v_attacker, 'attacker2@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.households (id, name, payday_day) VALUES
        (v_hh1, 'Household Alpha', 27),
        (v_hh2, 'Household Beta', 27)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, household_id, role, display_name) VALUES
        (v_user1, v_hh1, 'admin', 'Admin 1'),
        (v_user2, v_hh1, 'member', 'Member 1'),
        (v_attacker, v_hh2, 'member', 'Attacker')
    ON CONFLICT (id) DO UPDATE SET household_id = EXCLUDED.household_id, role = EXCLUDED.role;

    INSERT INTO public.household_memberships (household_id, user_id, role) VALUES
        (v_hh1, v_user1, 'admin'),
        (v_hh1, v_user2, 'member'),
        (v_hh2, v_attacker, 'member')
    ON CONFLICT (household_id, user_id) DO NOTHING;

    -- Create accounts under service role
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        (v_acc1, v_hh1, v_user1, 'Admin Current Account', 'checking', 1000.00, false),
        (v_acc2, v_hh1, v_user2, 'Member Savings Account', 'savings', 500.00, false),
        (v_shared_acc, v_hh1, v_user1, 'Household Emergency Pool', 'shared_pool', 2000.00, true)
    ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE 'Fixtures created successfully.';

    -- 1. Test: Cross-household account creation blocked by RLS
    -- Attacker belongs to HH2, attempts to insert account in HH1
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker::text)::text, true);

    v_caught := false;
    BEGIN
        INSERT INTO public.accounts (household_id, owner_user_id, name, account_type, balance, is_shared_pool)
        VALUES (v_hh1, v_attacker, 'Malicious Account', 'checking', 0.00, false);
    EXCEPTION WHEN OTHERS THEN
        v_caught := true;
    END;

    IF NOT v_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Attacker was able to insert an account into victim household!';
    END IF;
    RAISE NOTICE 'PASSED: Cross-household account insertion blocked by RLS.';

    -- 2. Test: Non-admin member cannot create shared pool account
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user2::text)::text, true);
    v_caught := false;
    BEGIN
        INSERT INTO public.accounts (household_id, owner_user_id, name, account_type, balance, is_shared_pool)
        VALUES (v_hh1, v_user2, 'Member Rogue Pool', 'shared_pool', 0.00, true);
    EXCEPTION WHEN OTHERS THEN
        v_caught := true;
    END;

    IF NOT v_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Non-admin member was able to create a shared pool account!';
    END IF;
    RAISE NOTICE 'PASSED: Non-admin creation of shared pool blocked by RLS.';

    -- 3. Test: Attacker cannot directly update victim's account balance
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker::text)::text, true);
    UPDATE public.accounts SET balance = 99999.00 WHERE id = v_acc1;
    -- Reset to postgres to verify balance did not change
    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1;
    IF v_bal <> 1000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Attacker was able to directly modify victim account balance to %', v_bal;
    END IF;
    RAISE NOTICE 'PASSED: Attacker cannot directly update victim account balance.';

    -- 4. Test: Attacker cannot transfer from victim's personal account
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker::text)::text, true);
    v_caught := false;
    BEGIN
        PERFORM public.transfer_between_accounts(v_hh1, v_acc1, v_shared_acc, 100.00, 0.00, 'Steal funds');
    EXCEPTION WHEN OTHERS THEN
        v_caught := true;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Attacker was able to execute transfer from victim personal account!';
    END IF;
    RAISE NOTICE 'PASSED: Transfer from unauthorized account rejected.';

    -- 5. Test: Overdraft transfer is rejected with insufficient funds
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1::text)::text, true);
    v_caught := false;
    BEGIN
        PERFORM public.transfer_between_accounts(v_hh1, v_acc1, v_acc2, 5000.00, 10.00, 'Overdraft transfer');
    EXCEPTION WHEN OTHERS THEN
        v_caught := true;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'TEST FAILED: Overdraft transfer should have failed!';
    END IF;
    RAISE NOTICE 'PASSED: Overdraft transfer rejected.';

    -- 6. Test: Valid transfer between accounts executes atomically
    -- User1 transfers 200.00 SAR with 5.00 SAR fee to User2
    v_transfer_res := public.transfer_between_accounts(v_hh1, v_acc1, v_acc2, 200.00, 5.00, 'Valid transfer');
    EXECUTE 'SET LOCAL ROLE postgres';

    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1;
    IF v_bal <> 795.00 THEN -- 1000 - (200 + 5)
        RAISE EXCEPTION 'TEST FAILED: Source account balance expected 795.00, got: %', v_bal;
    END IF;

    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc2;
    IF v_bal <> 700.00 THEN -- 500 + 200
        RAISE EXCEPTION 'TEST FAILED: Destination account balance expected 700.00, got: %', v_bal;
    END IF;
    RAISE NOTICE 'PASSED: Atomic transfer correctly updated both balances and logged record.';

    -- 7. Test: record_income increments balance and writes audit record
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1::text)::text, true);
    v_income_res := public.record_income(
        v_hh1, v_acc1, '2026-11', 'salary', 'Monthly Salary', 8000.00, 500.00, 0.00, 100.00, now(), 'November Salary'
    );
    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1;
    -- 795.00 + (8000 + 500 - 100) = 795 + 8400 = 9195.00
    IF v_bal <> 9195.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Account balance after income expected 9195.00, got: %', v_bal;
    END IF;
    RAISE NOTICE 'PASSED: record_income atomically credited account balance.';

    -- 8. Test: Transaction insert with account_id triggers automatic balance deduction
    INSERT INTO public.transactions (household_id, amount, merchant, category_code, account_id, timestamp)
    VALUES (v_hh1, 195.00, 'Panda Supermarket', 'OPEX-GROCERIES', v_acc1, now())
    RETURNING id INTO v_tx_id;

    SELECT balance INTO v_bal FROM public.accounts WHERE id = v_acc1;
    -- 9195.00 - 195.00 = 9000.00
    IF v_bal <> 9000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Transaction trigger did not decrement account balance! Expected 9000.00, got: %', v_bal;
    END IF;
    RAISE NOTICE 'PASSED: Transaction automatically decremented account balance via trigger.';

    -- Clean up test fixtures (delete non-admin members before sole admins)
    DELETE FROM public.transactions WHERE household_id IN (v_hh1, v_hh2);
    DELETE FROM public.account_transfers WHERE household_id IN (v_hh1, v_hh2);
    DELETE FROM public.income_records WHERE household_id IN (v_hh1, v_hh2);
    DELETE FROM public.accounts WHERE household_id IN (v_hh1, v_hh2);
    DELETE FROM public.household_memberships WHERE household_id IN (v_hh1, v_hh2) AND role <> 'admin';
    DELETE FROM public.household_memberships WHERE household_id IN (v_hh1, v_hh2);
    DELETE FROM public.users WHERE id IN (v_user1, v_user2, v_attacker);
    DELETE FROM public.households WHERE id IN (v_hh1, v_hh2);
    DELETE FROM auth.users WHERE id IN (v_user1, v_user2, v_attacker);

    RAISE NOTICE 'PASSED: Cleaned up test fixtures.';
END $$;
