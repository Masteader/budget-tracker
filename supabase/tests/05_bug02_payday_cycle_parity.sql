-- ====================================================================
-- Test: 05_bug02_payday_cycle_parity.sql
-- Proof test for BUG-02: Payday Cycle Parity and Budget Trigger Sync
-- ====================================================================

DO $$
DECLARE
    v_rec RECORD;
    v_hh_id UUID := '88888888-8888-8888-8888-888888888888'::UUID;
    v_user_id UUID := '99999999-9999-9999-9999-999999999999'::UUID;
    v_tx_id UUID;
    v_spent NUMERIC;
    v_cycle_key TEXT;
BEGIN
    -- 1. Test get_saudi_cycle_for_timestamp directly
    -- Oct 28th, 2026: After 27th payday -> belongs to November cycle (2026-11)
    SELECT * INTO v_rec FROM public.get_saudi_cycle_for_timestamp('2026-10-28 10:00:00+03'::TIMESTAMPTZ, 27);
    IF v_rec.cycle_key <> '2026-11' THEN
        RAISE EXCEPTION 'TEST FAILED: Expected 2026-11 for Oct 28 with payday 27, got %', v_rec.cycle_key;
    END IF;
    IF v_rec.cycle_start <> '2026-10-27'::DATE OR v_rec.cycle_end <> '2026-11-26'::DATE THEN
        RAISE EXCEPTION 'TEST FAILED: Incorrect cycle window % to %', v_rec.cycle_start, v_rec.cycle_end;
    END IF;
    RAISE NOTICE 'PASSED: Oct 28 maps to 2026-11 cycle.';

    -- Oct 26th, 2026: Before 27th payday -> belongs to October cycle (2026-10)
    SELECT * INTO v_rec FROM public.get_saudi_cycle_for_timestamp('2026-10-26 10:00:00+03'::TIMESTAMPTZ, 27);
    IF v_rec.cycle_key <> '2026-10' THEN
        RAISE EXCEPTION 'TEST FAILED: Expected 2026-10 for Oct 26 with payday 27, got %', v_rec.cycle_key;
    END IF;
    RAISE NOTICE 'PASSED: Oct 26 maps to 2026-10 cycle.';

    -- Payday 1st: Standard calendar month
    SELECT * INTO v_rec FROM public.get_saudi_cycle_for_timestamp('2026-10-15 12:00:00+03'::TIMESTAMPTZ, 1);
    IF v_rec.cycle_key <> '2026-10' OR v_rec.cycle_start <> '2026-10-01'::DATE OR v_rec.cycle_end <> '2026-10-31'::DATE THEN
        RAISE EXCEPTION 'TEST FAILED: 1st payday calendar month mapping failed';
    END IF;
    RAISE NOTICE 'PASSED: Payday 1st matches calendar month.';

    -- Feb 28 in Leap Year 2028 with payday 30
    SELECT * INTO v_rec FROM public.get_saudi_cycle_for_timestamp('2028-02-28 12:00:00+03'::TIMESTAMPTZ, 30);
    IF v_rec.cycle_key <> '2028-02' THEN
        RAISE EXCEPTION 'TEST FAILED: Leap year clamping failed, got %', v_rec.cycle_key;
    END IF;
    RAISE NOTICE 'PASSED: Leap year clamping parity confirmed.';

    -- 2. Test Transaction Trigger: Automatic cycle_key & Budget Sync
    INSERT INTO auth.users (id, email) VALUES (v_user_id, 'cycle_test@example.com') ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.households (id, name, payday_day) VALUES (v_hh_id, 'Cycle Parity Household', 27) ON CONFLICT (id) DO NOTHING;

    -- Create budget for cycle 2026-11
    INSERT INTO public.budgets (household_id, category_code, allocated_amount, spent_amount, month, cycle_key)
    VALUES (v_hh_id, 'OPEX-DINING', 1000.00, 0.00, '2026-11-01', '2026-11')
    ON CONFLICT DO NOTHING;

    -- Create budget for cycle 2026-10 (calendar month of Oct 28)
    INSERT INTO public.budgets (household_id, category_code, allocated_amount, spent_amount, month, cycle_key)
    VALUES (v_hh_id, 'OPEX-DINING', 1000.00, 0.00, '2026-10-01', '2026-10')
    ON CONFLICT DO NOTHING;

    -- Insert a transaction on Oct 28th (WITHOUT cycle_key)
    INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp)
    VALUES (v_hh_id, 125.00, 'Tamimi Diner', 'OPEX-DINING', '2026-10-28 14:00:00+03')
    RETURNING id, cycle_key INTO v_tx_id, v_cycle_key;

    -- Verify automatic cycle_key populated on transaction
    IF v_cycle_key <> '2026-11' THEN
        RAISE EXCEPTION 'TEST FAILED: Transaction cycle_key was not automatically set to 2026-11, got: %', v_cycle_key;
    END IF;
    RAISE NOTICE 'PASSED: Transaction cycle_key automatically populated as 2026-11.';

    -- Verify that budget 2026-11 was updated, NOT budget 2026-10!
    SELECT spent_amount INTO v_spent FROM public.budgets WHERE household_id = v_hh_id AND cycle_key = '2026-11';
    IF v_spent <> 125.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Budget 2026-11 spent_amount should be 125.00, got: %', v_spent;
    END IF;

    SELECT spent_amount INTO v_spent FROM public.budgets WHERE household_id = v_hh_id AND cycle_key = '2026-10';
    IF v_spent <> 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Budget 2026-10 should NOT have received spent_amount, got: %', v_spent;
    END IF;
    RAISE NOTICE 'PASSED: Budget for November cycle updated correctly; October cycle unaffected.';

    -- Clean up fixtures
    DELETE FROM public.transactions WHERE household_id = v_hh_id;
    DELETE FROM public.budgets WHERE household_id = v_hh_id;
    DELETE FROM public.households WHERE id = v_hh_id;
    DELETE FROM auth.users WHERE id = v_user_id;
    RAISE NOTICE 'PASSED: Cleaned up test fixtures.';
END $$;
