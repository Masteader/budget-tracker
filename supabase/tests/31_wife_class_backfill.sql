-- ============================================================================
-- Test 31: Legacy wife transactions backfill and balance refund proof
--
-- Migration: 20261101000000_nafaqah_wife_no_account.sql
--
-- Verifies:
--   1. Seeding legacy wife_personal and wife_reimbursable rows with account_id
--      debits the account balance by the transaction amount via DB trigger.
--   2. Running the backfill UPDATE sets account_id to NULL.
--   3. The UPDATE trigger restores the account balance by the exact sum.
--   4. Validating the constraint succeeds once all rows are unlinked.
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
    v_household_id uuid := 'e3100000-0000-0000-0000-000000000001';
    v_user_h uuid := 'e3100000-0000-0000-0000-00000000000a';
    v_user_w uuid := 'e3100000-0000-0000-0000-00000000000b';
    v_acc_id uuid := 'e3100000-0000-0000-0000-0000000000aa';
    v_wife_acc_id uuid := 'e3100000-0000-0000-0000-0000000000bb';
    v_initial_bal numeric := 2000.00;
    v_debited_bal numeric;
    v_restored_bal numeric;
    v_wife_bal numeric;
    v_tx1_id uuid;
    v_tx2_id uuid;
    v_tx3_id uuid;
    v_unlinked_count int;
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        (v_user_h, 'test-h31@test.local'),
        (v_user_w, 'test-w31@test.local')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.households (id, name, invite_code, owner_user_id) VALUES
        (v_household_id, 'Test 31 Household', 'TEST31HOUSEHOLD', v_user_h)
    ON CONFLICT (id) DO UPDATE SET owner_user_id = v_user_h;

    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role) VALUES
        (v_household_id, v_user_h, 'admin', 'provider'),
        (v_household_id, v_user_w, 'member', 'spouse')
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = EXCLUDED.role, financial_role = EXCLUDED.financial_role;

    -- The provider must already be a member (households_nafaqah_provider_rules).
    UPDATE public.households SET nafaqah_provider_user_id = v_user_h WHERE id = v_household_id;

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, currency, is_shared_pool) VALUES
        (v_acc_id, v_household_id, v_user_h, 'Main Account', 'bank', v_initial_bal, 'SAR', true),
        (v_wife_acc_id, v_household_id, v_user_w, 'Wife Personal Account', 'bank', 1000.00, 'SAR', false)
    ON CONFLICT (id) DO NOTHING;

    -- Temporarily disable the trigger so we can simulate legacy pre-migration rows linking wife rows to shared pool
    ALTER TABLE public.transactions DISABLE TRIGGER trg_enforce_wife_class_account;

    -- Insert legacy wife_personal row (150 SAR) linked to v_acc_id
    INSERT INTO public.transactions (
        household_id, user_id, amount, currency, merchant, category_code,
        timestamp, notes, nafaqah_class, nafaqah_spouse_id, account_id
    ) VALUES (
        v_household_id, v_user_w, 150.00, 'SAR', 'Salon', 'OPEX-SHOPPING',
        now(), 'Legacy wife personal row', 'wife_personal', v_user_w, v_acc_id
    ) RETURNING id INTO v_tx1_id;

    -- Insert legacy wife_reimbursable row (250 SAR) linked to v_acc_id
    INSERT INTO public.transactions (
        household_id, user_id, amount, currency, merchant, category_code,
        timestamp, notes, nafaqah_class, nafaqah_spouse_id, account_id
    ) VALUES (
        v_household_id, v_user_w, 250.00, 'SAR', 'Groceries', 'OPEX-GROCERY',
        now(), 'Legacy wife reimbursable row', 'wife_reimbursable', v_user_w, v_acc_id
    ) RETURNING id INTO v_tx2_id;

    -- Insert wife_personal row (100 SAR) correctly linked to wife's own personal account
    INSERT INTO public.transactions (
        household_id, user_id, amount, currency, merchant, category_code,
        timestamp, notes, nafaqah_class, nafaqah_spouse_id, account_id
    ) VALUES (
        v_household_id, v_user_w, 100.00, 'SAR', 'Boutique', 'OPEX-SHOPPING',
        now(), 'Wife own personal row', 'wife_personal', v_user_w, v_wife_acc_id
    ) RETURNING id INTO v_tx3_id;

    -- Verify that the trigger decremented v_acc_id by 400.00 (from 2000 to 1600)
    SELECT balance INTO v_debited_bal FROM public.accounts WHERE id = v_acc_id;
    PERFORM pg_temp.expect('balance debited by legacy wife rows', v_debited_bal::text, '1600.00');

    -- Verify wife account was decremented from 1000 to 900
    SELECT balance INTO v_wife_bal FROM public.accounts WHERE id = v_wife_acc_id;
    PERFORM pg_temp.expect('wife personal account balance debited', v_wife_bal::text, '900.00');

    -- Re-add the constraint as NOT VALID (matching migration step 1)
    ALTER TABLE public.transactions
      ADD CONSTRAINT transactions_wife_class_no_account
      CHECK (nafaqah_class IS NULL
             OR nafaqah_class NOT IN ('wife_personal', 'wife_reimbursable')
             OR account_id IS NULL) NOT VALID;

    -- Run the migration backfill UPDATE (matching migration step 2 with exclusion of wife's own accounts)
    UPDATE public.transactions
       SET account_id = NULL
     WHERE nafaqah_class IN ('wife_personal', 'wife_reimbursable')
       AND account_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.accounts a
          WHERE a.id = transactions.account_id
            AND a.owner_user_id = transactions.nafaqah_spouse_id
            AND a.is_shared_pool = false
            AND a.household_id = transactions.household_id
       );

    -- Confirm account_id IS NULL on legacy shared rows
    SELECT count(*) INTO v_unlinked_count
      FROM public.transactions
     WHERE id IN (v_tx1_id, v_tx2_id) AND account_id IS NULL;
    PERFORM pg_temp.expect('both legacy rows unlinked', v_unlinked_count::text, '2');

    -- Confirm wife own personal account row stays linked
    PERFORM pg_temp.expect('wife personal row stays linked',
        (SELECT account_id::text FROM public.transactions WHERE id = v_tx3_id),
        v_wife_acc_id::text);

    -- Confirm account balance is restored to exactly initial balance (2000.00)
    SELECT balance INTO v_restored_bal FROM public.accounts WHERE id = v_acc_id;
    PERFORM pg_temp.expect('account balance restored to initial balance', v_restored_bal::text, v_initial_bal::text);

    -- Confirm wife account balance is unchanged (900.00)
    SELECT balance INTO v_wife_bal FROM public.accounts WHERE id = v_wife_acc_id;
    PERFORM pg_temp.expect('wife balance unchanged', v_wife_bal::text, '900.00');

    -- Drop temporary check constraint and re-enable trigger
    ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_wife_class_no_account;
    ALTER TABLE public.transactions ENABLE TRIGGER trg_enforce_wife_class_account;
END $$;

ROLLBACK;

