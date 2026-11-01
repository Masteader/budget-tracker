-- ============================================================================
-- Test 30: Constraint transactions_wife_class_no_account
--
-- Migration: 20261101000000_nafaqah_wife_no_account.sql
--
-- Verifies:
--   1. An insert with nafaqah_class in ('wife_personal', 'wife_reimbursable')
--      and a non-null account_id raises check_violation on transactions_wife_class_no_account.
--   2. An update setting account_id on a wife-class row raises check_violation.
--   3. Wife transactions with account_id IS NULL succeed.
--   4. Standard transactions with account_id succeed.
--   5. The constraint is marked VALIDATED.
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
    v_household_id uuid := 'e3000000-0000-0000-0000-000000000001';
    v_user_h uuid := 'e3000000-0000-0000-0000-00000000000a';
    v_user_w uuid := 'e3000000-0000-0000-0000-00000000000b';
    v_acc_id uuid := 'e3000000-0000-0000-0000-0000000000aa';
    v_tx_id uuid;
    v_failed boolean;
    v_constraint text;
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        (v_user_h, 'test-h30@test.local'),
        (v_user_w, 'test-w30@test.local')
    ON CONFLICT (id) DO NOTHING;

    -- Fully seed household with owner and nafaqah_provider_user_id
    INSERT INTO public.households (id, name, invite_code, owner_user_id, nafaqah_provider_user_id) VALUES
        (v_household_id, 'Test 30 Household', 'TEST30HOUSEHOLD', v_user_h, v_user_h)
    ON CONFLICT (id) DO UPDATE SET owner_user_id = v_user_h, nafaqah_provider_user_id = v_user_h;

    -- Seed memberships with explicit financial roles
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role) VALUES
        (v_household_id, v_user_h, 'admin', 'provider'),
        (v_household_id, v_user_w, 'member', 'spouse')
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = EXCLUDED.role, financial_role = EXCLUDED.financial_role;

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, currency, is_shared_pool) VALUES
        (v_acc_id, v_household_id, v_user_h, 'Main Account', 'checking', 1000.00, 'SAR', true)
    ON CONFLICT (id) DO NOTHING;

    -- 1. Insert wife_personal with non-null account_id MUST FAIL with transactions_wife_class_no_account
    v_failed := false;
    BEGIN
        INSERT INTO public.transactions (
            household_id, user_id, amount, currency, merchant, category_code,
            timestamp, raw_sms, nafaqah_class, nafaqah_spouse_id, account_id
        ) VALUES (
            v_household_id, v_user_w, 50.00, 'SAR', 'Test Merchant', 'OPEX-CLOTHING',
            now(), 'Test wife personal with account', 'wife_personal', v_user_w, v_acc_id
        );
    EXCEPTION
        WHEN check_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
            IF v_constraint IS DISTINCT FROM 'transactions_wife_class_no_account' THEN
                RAISE EXCEPTION 'wrong constraint fired: %', v_constraint;
            END IF;
            v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'Expected check_violation when inserting wife_personal with account_id, but succeeded';
    END IF;

    -- 2. Insert wife_reimbursable with non-null account_id MUST FAIL with transactions_wife_class_no_account
    v_failed := false;
    BEGIN
        INSERT INTO public.transactions (
            household_id, user_id, amount, currency, merchant, category_code,
            timestamp, raw_sms, nafaqah_class, nafaqah_spouse_id, account_id
        ) VALUES (
            v_household_id, v_user_w, 75.00, 'SAR', 'Groceries', 'OPEX-GROCERIES',
            now(), 'Test wife reimbursable with account', 'wife_reimbursable', v_user_w, v_acc_id
        );
    EXCEPTION
        WHEN check_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
            IF v_constraint IS DISTINCT FROM 'transactions_wife_class_no_account' THEN
                RAISE EXCEPTION 'wrong constraint fired: %', v_constraint;
            END IF;
            v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'Expected check_violation when inserting wife_reimbursable with account_id, but succeeded';
    END IF;

    -- 3. Insert wife_personal with NULL account_id MUST SUCCEED
    INSERT INTO public.transactions (
        household_id, user_id, amount, currency, merchant, category_code,
        timestamp, raw_sms, nafaqah_class, nafaqah_spouse_id, account_id
    ) VALUES (
        v_household_id, v_user_w, 50.00, 'SAR', 'Test Merchant', 'OPEX-CLOTHING',
        now(), 'Test wife personal no account', 'wife_personal', v_user_w, NULL
    ) RETURNING id INTO v_tx_id;

    -- 4. Update setting account_id on wife row MUST FAIL with transactions_wife_class_no_account
    v_failed := false;
    BEGIN
        UPDATE public.transactions
        SET account_id = v_acc_id
        WHERE id = v_tx_id;
    EXCEPTION
        WHEN check_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
            IF v_constraint IS DISTINCT FROM 'transactions_wife_class_no_account' THEN
                RAISE EXCEPTION 'wrong constraint fired: %', v_constraint;
            END IF;
            v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'Expected check_violation when updating wife row with account_id, but succeeded';
    END IF;

    -- 5. Standard transaction with account_id MUST SUCCEED
    INSERT INTO public.transactions (
        household_id, user_id, amount, currency, merchant, category_code,
        timestamp, raw_sms, nafaqah_class, account_id
    ) VALUES (
        v_household_id, v_user_h, 100.00, 'SAR', 'Car Fuel', 'OPEX-TRANSPORT',
        now(), 'Standard fuel', NULL, v_acc_id
    );

    -- 6. Verify the constraint exists and is validated
    PERFORM pg_temp.expect(
        'convalidated',
        (SELECT convalidated::text FROM pg_constraint WHERE conname = 'transactions_wife_class_no_account'),
        'true'
    );

END $$;

ROLLBACK;
