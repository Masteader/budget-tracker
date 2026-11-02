-- Migration: 20261102010000_void_income_record_rpc.sql
-- Description: Void / Delete Income Record RPC with atomic balance reversal and strict multi-tenant authorization

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
    v_caller_role := public.get_auth_user_role();
    IF v_income.user_id <> v_caller_uid
       AND v_acc.owner_user_id <> v_caller_uid
       AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Access denied: insufficient permissions to void this income record' USING ERRCODE = '42501';
    END IF;

    -- Non-shared account protection: non-admin cannot debit another user's personal account
    IF v_acc.is_shared_pool = false
       AND v_acc.owner_user_id <> v_caller_uid
       AND (v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'co_admin')) THEN
        RAISE EXCEPTION 'Access denied: cannot void income from a personal account owned by another member' USING ERRCODE = '42501';
    END IF;

    -- 7. Atomically decrement account balance
    UPDATE public.accounts
    SET balance = balance - v_income.net_amount,
        updated_at = now()
    WHERE id = v_acc.id
    RETURNING balance INTO v_new_balance;

    -- 8. Delete the income record
    DELETE FROM public.income_records
    WHERE id = p_income_id;

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

-- Security grant restrictions
REVOKE ALL ON FUNCTION public.void_income_record(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_income_record(UUID) TO authenticated, service_role;
