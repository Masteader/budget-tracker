-- ============================================================================
-- Test 32: Trigger trg_enforce_wife_class_account
--
-- Migration: 20261101000100_nafaqah_wife_account_owner_guard.sql
--
-- Verifies:
--   1. (a) A wife_personal row with the wife's own personal account succeeds and debits that account.
--   2. (b) A wife_personal row with a shared pool fails with transactions_wife_class_no_account.
--   3. (c) A wife_reimbursable row with the husband's personal account fails.
--   4. (d) An UPDATE that switches a wife row to the shared pool fails.
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
    v_household_id uuid := 'e3200000-0000-0000-0000-000000000001';
    v_user_h uuid := 'e3200000-0000-0000-0000-00000000000a';
    v_user_w uuid := 'e3200000-0000-0000-0000-00000000000b';

    v_shared_acc uuid := 'e3200000-0000-0000-0000-000000000001';
    v_wife_personal_acc uuid := 'e3200000-0000-0000-0000-000000000002';
    v_husband_personal_acc uuid := 'e3200000-0000-0000-0000-000000000003';

    v_tx_id uuid;
    v_failed boolean;
    v_constraint text;
    v_balance numeric;
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        (v_user_h, 'test-h32@test.local'),
        (v_user_w, 'test-w32@test.local')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.households (id, name, invite_code, owner_user_id, nafaqah_provider_user_id) VALUES
        (v_household_id, 'Test 32 Household', 'TEST32HOUSEHOLD', v_user_h, v_user_h)
    ON CONFLICT (id) DO UPDATE SET owner_user_id = v_user_h, nafaqah_provider_user_id = v_user_h;

    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role) VALUES
        (v_household_id, v_user_h, 'admin', 'husband'),
        (v_household_id, v_user_w, 'member', 'wife')
    ON CONFLICT (household_id, user_id) DO NOTHING;

    -- Shared account (household pool)
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, currency, is_shared_pool)
    VALUES (v_shared_acc, v_household_id, v_user_h, 'Family Bank', 'bank', 5000.00, 'SAR', true)
    ON CONFLICT (id) DO NOTHING;

    -- Wife's own personal account
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, currency, is_shared_pool)
    VALUES (v_wife_personal_acc, v_household_id, v_user_w, 'Wife Personal Bank', 'bank', 2000.00, 'SAR', false)
    ON CONFLICT (id) DO NOTHING;

    -- Husband's own personal account
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, currency, is_shared_pool)
    VALUES (v_husband_personal_acc, v_household_id, v_user_h, 'Husband Personal Bank', 'bank', 3000.00, 'SAR', false)
    ON CONFLICT (id) DO NOTHING;

    -- (a) A wife_personal row with the wife's own personal account succeeds and debits that account
    INSERT INTO public.transactions (
        id, household_id, user_id, amount, currency, merchant, category_code,
        timestamp, raw_sms, nafaqah_class, nafaqah_spouse_id, account_id
    ) VALUES (
        gen_random_uuid(), v_household_id, v_user_w, 250.00, 'SAR', 'Sephora', 'OPEX-PERSONAL',
        now(), 'Wife salon/beauty', 'wife_personal', v_user_w, v_wife_personal_acc
    ) RETURNING id INTO v_tx_id;

    SELECT balance INTO v_balance FROM public.accounts WHERE id = v_wife_personal_acc;
    PERFORM pg_temp.expect('wife personal account debited', v_balance::text, '1750.00');

    -- (b) A wife_personal row with a shared pool fails with transactions_wife_class_no_account
    v_failed := false;
    BEGIN
        INSERT INTO public.transactions (
            household_id, user_id, amount, currency, merchant, category_code,
            timestamp, raw_sms, nafaqah_class, nafaqah_spouse_id, account_id
        ) VALUES (
            v_household_id, v_user_w, 100.00, 'SAR', 'Cosmetics', 'OPEX-PERSONAL',
            now(), 'Cosmetics on shared', 'wife_personal', v_user_w, v_shared_acc
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
        RAISE EXCEPTION 'Expected check_violation for wife_personal on shared pool, but succeeded';
    END IF;

    -- (c) A wife_reimbursable row with the husband personal account fails
    v_failed := false;
    BEGIN
        INSERT INTO public.transactions (
            household_id, user_id, amount, currency, merchant, category_code,
            timestamp, raw_sms, nafaqah_class, nafaqah_spouse_id, account_id
        ) VALUES (
            v_household_id, v_user_w, 400.00, 'SAR', 'Groceries', 'OPEX-GROCERY',
            now(), 'Reimbursable groceries on husband account', 'wife_reimbursable', v_user_w, v_husband_personal_acc
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
        RAISE EXCEPTION 'Expected check_violation for wife_reimbursable on husband personal account, but succeeded';
    END IF;

    -- (d) An UPDATE that switches a wife row to the shared pool fails
    v_failed := false;
    BEGIN
        UPDATE public.transactions
           SET account_id = v_shared_acc
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
        RAISE EXCEPTION 'Expected check_violation when switching wife transaction to shared pool, but succeeded';
    END IF;

END $$;

ROLLBACK;

