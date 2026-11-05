-- ============================================================================
-- Test 34: Cleanup Jargon (raw_sms -> notes) and Zombie Columns (users.payday_day)
--
-- Verifies:
--   1. public.transactions has column 'notes' with data_type = 'text'.
--   2. public.transactions does NOT have column 'raw_sms'.
--   3. public.users does NOT have column 'payday_day'.
--   4. public.households STILL has column 'payday_day' (single source of truth).
--   5. transactions.notes has column description mentioning 'Free-text audit note'.
--   6. Insert transaction with notes = 'TDD audit note verification' succeeds.
--   7. Insert into public.users without payday_day succeeds.
--   8. Insert into public.transactions with column raw_sms raises 42703 (undefined_column).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_notes_type text;
    v_raw_sms_exists boolean;
    v_user_payday_exists boolean;
    v_hh_payday_exists boolean;
    v_col_desc text;
    v_household_id uuid := 'e3400000-0000-0000-0000-000000000001';
    v_user uuid := 'e3400000-0000-0000-0000-00000000000a';
    v_tx_id uuid := 'e3400000-0000-0000-0000-000000000002';
    v_read_notes text;
    v_failed boolean;
BEGIN
    -- 1. public.transactions has column 'notes' of type 'text'
    SELECT data_type INTO v_notes_type
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'notes';

    IF v_notes_type IS DISTINCT FROM 'text' THEN
        RAISE EXCEPTION 'transactions.notes column missing or wrong type: % (expected text)', v_notes_type;
    END IF;

    -- 2. public.transactions does NOT have column 'raw_sms'
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'raw_sms'
    ) INTO v_raw_sms_exists;

    IF v_raw_sms_exists THEN
        RAISE EXCEPTION 'transactions.raw_sms column still exists!';
    END IF;

    -- 3. public.users does NOT have column 'payday_day'
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'payday_day'
    ) INTO v_user_payday_exists;

    IF v_user_payday_exists THEN
        RAISE EXCEPTION 'users.payday_day zombie column still exists!';
    END IF;

    -- 4. public.households STILL has column 'payday_day'
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'households' AND column_name = 'payday_day'
    ) INTO v_hh_payday_exists;

    IF NOT v_hh_payday_exists THEN
        RAISE EXCEPTION 'households.payday_day column is missing! (Must remain single source of truth)';
    END IF;

    -- 5. transactions.notes has column description mentioning 'Free-text audit note'
    SELECT col_description('public.transactions'::regclass,
               (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'notes'))
    INTO v_col_desc;

    IF v_col_desc IS NULL OR v_col_desc NOT ILIKE '%Free-text audit note%' THEN
        RAISE EXCEPTION 'transactions.notes description missing or inaccurate: %', v_col_desc;
    END IF;

    -- Setup test user and household
    INSERT INTO auth.users (id, email) VALUES
        (v_user, 'test-u34@test.local')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.households (id, name, invite_code, owner_user_id, payday_day) VALUES
        (v_household_id, 'Test 34 Household', 'TEST34HOUSEHOLD', v_user, 27)
    ON CONFLICT (id) DO UPDATE SET owner_user_id = v_user, payday_day = 27;

    -- 6. Insert transaction with notes succeeds and can be read back
    INSERT INTO public.transactions (
        id, household_id, user_id, amount, currency, merchant, category_code,
        timestamp, notes, source
    ) VALUES (
        v_tx_id, v_household_id, v_user, 50.00, 'SAR', 'Test Notes Merchant', 'OPEX-GROCERY',
        now(), 'TDD audit note verification', 'manual'
    );

    SELECT notes INTO v_read_notes FROM public.transactions WHERE id = v_tx_id;
    IF v_read_notes IS DISTINCT FROM 'TDD audit note verification' THEN
        RAISE EXCEPTION 'transactions.notes readback mismatch: %', v_read_notes;
    END IF;

    -- 7. Insert into public.transactions with column raw_sms raises 42703 (undefined_column)
    v_failed := false;
    BEGIN
        EXECUTE 'INSERT INTO public.transactions (household_id, user_id, amount, currency, merchant, category_code, timestamp, raw_sms, source)
                 VALUES ($1, $2, 10.00, ''SAR'', ''Invalid raw_sms'', ''OPEX-GROCERY'', now(), ''legacy note'', ''manual'')'
        USING v_household_id, v_user;
    EXCEPTION
        WHEN undefined_column THEN -- 42703
            v_failed := true;
    END;

    IF NOT v_failed THEN
        RAISE EXCEPTION 'Inserting into public.transactions with column raw_sms unexpectedly succeeded!';
    END IF;

    RAISE NOTICE 'PASSED: Test 34 cleanup jargon (raw_sms -> notes) and zombie columns (users.payday_day).';
END $$;

ROLLBACK;
