-- ============================================================================
-- Test 33: Manual prior-spend transaction rows & cycle key derivation (CRITICAL-03)
--
-- Verifies:
--   1. An insert with source = 'prior_adjustment' raises SQLSTATE 23514 (check_violation)
--      due to transactions_source_check (source IN ('chat', 'receipt_scan', 'manual')).
--   2. An insert with source = 'manual' and account_id = NULL succeeds.
--   3. All accounts.balance in the household remain unchanged when account_id is NULL.
--   4. The cycle_key is correctly derived from timestamp by populate_transaction_cycle_key().
--   5. A client-supplied wrong cycle_key is overwritten by the trigger with the true cycle_key.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

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

DO $$
DECLARE
    v_household_id uuid := 'e3300000-0000-0000-0000-000000000001';
    v_user uuid := 'e3300000-0000-0000-0000-00000000000a';
    v_acc uuid := 'e3300000-0000-0000-0000-000000000002';
    v_tx_id uuid;
    v_failed boolean;
    v_balance numeric;
    v_derived_key text;
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        (v_user, 'test-u33@test.local')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.households (id, name, invite_code, owner_user_id, payday_day) VALUES
        (v_household_id, 'Test 33 Household', 'TEST33HOUSEHOLD', v_user, 27)
    ON CONFLICT (id) DO UPDATE SET owner_user_id = v_user, payday_day = 27;

    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role) VALUES
        (v_household_id, v_user, 'admin', 'provider')
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = EXCLUDED.role, financial_role = EXCLUDED.financial_role;

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, currency, is_shared_pool)
    VALUES (v_acc, v_household_id, v_user, 'Main Bank', 'bank', 5000.00, 'SAR', true)
    ON CONFLICT (id) DO NOTHING;

    -- 1. source = 'prior_adjustment' fails with check_violation (SQLSTATE 23514)
    v_failed := false;
    BEGIN
        INSERT INTO public.transactions (
            household_id, user_id, amount, currency, merchant, category_code,
            timestamp, notes, source, account_id
        ) VALUES (
            v_household_id, v_user, 150.00, 'SAR', 'Prior Spend Grocery', 'OPEX-GROCERIES',
            '2026-11-01 12:00:00+03', 'Prior spend', 'prior_adjustment', NULL
        );
    EXCEPTION
        WHEN check_violation THEN
            v_failed := true;
    END;
    PERFORM pg_temp.expect('source=prior_adjustment raises check_violation', v_failed::text, 'true');

    -- 2. source = 'manual' and account_id = NULL succeeds
    INSERT INTO public.transactions (
        id, household_id, user_id, amount, currency, merchant, category_code,
        timestamp, notes, source, account_id
    ) VALUES (
        gen_random_uuid(), v_household_id, v_user, 150.00, 'SAR', 'Prior Spend Grocery', 'OPEX-GROCERIES',
        '2026-11-01 12:00:00+03', 'Prior spend adjustment', 'manual', NULL
    ) RETURNING id, cycle_key INTO v_tx_id, v_derived_key;

    PERFORM pg_temp.expect('derived cycle_key for 2026-11-01 payday 27', v_derived_key, '2026-11');

    -- 3. accounts.balance is untouched when account_id is NULL
    SELECT balance INTO v_balance FROM public.accounts WHERE id = v_acc;
    PERFORM pg_temp.expect('account balance unchanged on null account_id insert', v_balance::text, '5000.00');

    -- 4. Client-supplied wrong cycle_key is overwritten by trigger
    INSERT INTO public.transactions (
        id, household_id, user_id, amount, currency, merchant, category_code,
        timestamp, notes, source, account_id, cycle_key
    ) VALUES (
        gen_random_uuid(), v_household_id, v_user, 50.00, 'SAR', 'Coffee', 'OPEX-DINING',
        '2026-11-02 10:00:00+03', 'Coffee', 'manual', NULL, '1999-01'
    ) RETURNING cycle_key INTO v_derived_key;

    PERFORM pg_temp.expect('wrong cycle_key overwritten by trigger', v_derived_key, '2026-11');
END $$;

ROLLBACK;
