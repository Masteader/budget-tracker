-- ============================================================================
-- Migration: 20261105000500_void_income_single_subtraction.sql
--
-- void_income_record subtracted net_amount from the account, then deleted the income
-- row, and trg_adjust_account_balance_on_income_change subtracted net_amount again on
-- the delete. Voiding 500 SAR took 1000 SAR off the balance. Test 35 proves it.
--
-- The trigger stays the single source, because it also covers deletes that do not go
-- through this RPC. The RPC stops subtracting and reads the balance back while it
-- still holds the account row, so new_balance is the stored value. Its locks and the
-- shape of its response do not change.
--
-- If the trigger ever stops subtracting, the RPC refuses (HINT void_balance_mismatch)
-- instead of removing the row and reporting a reversal that did not happen. This
-- migration also aborts on a database where the trigger is missing or disabled:
-- without it this RPC could void nothing at all.
--
-- Past voids are not repaired here. The voided rows are deleted, so the amounts cannot
-- be reconstructed from the tables. Repair is a separate owner decision;
-- docs/review/audit/account_deletion_preflight_checks.sql has what can be checked.
-- ============================================================================

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid = 'public.income_records'::regclass
          AND t.tgname = 'trg_adjust_account_balance_on_income_change'
          AND t.tgenabled <> 'D'
    ) THEN
        RAISE EXCEPTION 'trg_adjust_account_balance_on_income_change is missing or disabled; void_income_record relies on it';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.void_income_record(
    p_income_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_hh UUID;
    v_caller_role TEXT;
    v_income RECORD;
    v_acc RECORD;
    v_new_balance NUMERIC(14, 2);
    v_result jsonb;
BEGIN
    -- 1. Input parameter validation
    IF p_income_id IS NULL THEN
        RAISE EXCEPTION 'Income record ID is required' USING ERRCODE = '22023';
    END IF;

    -- 2. Authentication check
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    -- 3. Row lock on income_records to prevent concurrent voiding
    SELECT * INTO v_income
    FROM public.income_records
    WHERE id = p_income_id
    FOR UPDATE;

    IF v_income.id IS NULL THEN
        RAISE EXCEPTION 'Income record not found' USING ERRCODE = 'P0002';
    END IF;

    -- 4. Multi-tenancy check: caller household must match income record household
    v_caller_hh := public.get_auth_user_household_id();
    IF v_caller_hh IS NULL OR v_caller_hh IS DISTINCT FROM v_income.household_id THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to the household of this income record' USING ERRCODE = '42501';
    END IF;

    -- 5. Row lock on target account
    SELECT * INTO v_acc
    FROM public.accounts
    WHERE id = v_income.account_id
    FOR UPDATE;

    IF v_acc.id IS NULL THEN
        RAISE EXCEPTION 'Target account not found' USING ERRCODE = 'P0002';
    END IF;

    -- Verify account belongs to same household
    IF v_acc.household_id <> v_income.household_id THEN
        RAISE EXCEPTION 'Corrupt ledger: target account belongs to a different household' USING ERRCODE = '42501';
    END IF;

    -- 6. Permission check:
    -- Caller must be:
    --   a) The user who logged the income, OR
    --   b) The account owner, OR
    --   c) A household admin/co-admin.
    -- A NULL creator (deleted member) matches nobody: IS DISTINCT FROM, never <>.
    v_caller_role := public.get_auth_user_role();
    IF v_income.user_id IS DISTINCT FROM v_caller_uid
       AND v_acc.owner_user_id IS DISTINCT FROM v_caller_uid
       AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Access denied: insufficient permissions to void this income record' USING ERRCODE = '42501';
    END IF;

    -- Non-shared account protection: non-admin cannot debit another user's personal account
    IF v_acc.is_shared_pool = false
       AND v_acc.owner_user_id IS DISTINCT FROM v_caller_uid
       AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Access denied: cannot void income from a personal account owned by another member' USING ERRCODE = '42501';
    END IF;

    -- 7. Delete the income record. trg_adjust_account_balance_on_income_change subtracts
    -- net_amount from the account; nothing else here may touch the balance.
    DELETE FROM public.income_records
    WHERE id = p_income_id;

    -- 8. Read the balance back. The account row has been held since step 5, so nobody
    -- else can have moved it: anything but the exact reversal means the trigger did not.
    SELECT balance INTO v_new_balance
    FROM public.accounts
    WHERE id = v_acc.id;

    IF v_new_balance IS DISTINCT FROM v_acc.balance - v_income.net_amount THEN
        RAISE EXCEPTION 'The income could not be reversed from the account balance'
            USING ERRCODE = '23514', HINT = 'void_balance_mismatch';
    END IF;

    -- 9. Construct and return receipt payload
    SELECT jsonb_build_object(
        'success', true,
        'id', v_income.id,
        'income_id', v_income.id,
        'household_id', v_income.household_id,
        'account_id', v_income.account_id,
        'user_id', v_income.user_id,
        'cycle_key', v_income.cycle_key,
        'title', v_income.title,
        'net_amount', v_income.net_amount,
        'reverted_amount', v_income.net_amount,
        'new_balance', v_new_balance,
        'voided_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.void_income_record(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_income_record(UUID) TO authenticated, service_role;

COMMIT;
