-- ----------------------------------------------------------------------------
-- Migration: 20261020050000_audit_ledger_precision_and_income_append_only.sql
-- Audit DB-06 (Medium): transfer_between_accounts / record_income accept
--   unconstrained NUMERIC while the ledger columns are NUMERIC(14,2)/(10,2).
--   A 3-decimal amount is rounded independently on each side (1.005 debits 1.00
--   from the source, credits 1.01 to the destination and logs 1.01), so a user
--   can mint 0.01 SAR per call between two own accounts. record_income also
--   accepted negative components (negative deductions inflate net income) and
--   any cycle_key string.
-- Audit DB-07 (Medium): income_insert_household (20261019090000) still lets a
--   client INSERT income_records directly - bypassing record_income's account
--   ownership check and balance update - with any sign and any account of the
--   household, forging the income ledger the budgets/rollover read.
-- Fix: precision/sign/format validation inside both RPCs (cycle_key derived
--   from received_at + household payday when NULL); income_records and
--   account_transfers become client read-only (RPCs are SECURITY DEFINER).
-- Proof test: supabase/tests/12_audit_ledger_integrity.sql
-- ----------------------------------------------------------------------------

BEGIN;

-- 1. transfer_between_accounts: reject amounts/fees with more than 2 decimals
CREATE OR REPLACE FUNCTION public.transfer_between_accounts(
    p_household_id UUID,
    p_from_account_id UUID,
    p_to_account_id UUID,
    p_amount NUMERIC,
    p_fee NUMERIC DEFAULT 0.0,
    p_notes TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid UUID;
    v_from_acc RECORD;
    v_to_acc RECORD;
    v_total_deduction NUMERIC;
    v_transfer_id UUID;
    v_created_at TIMESTAMPTZ := now();
    v_result jsonb;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive' USING ERRCODE = '22023';
    END IF;

    IF p_fee IS NULL OR p_fee < 0 THEN
        RAISE EXCEPTION 'Transfer fee cannot be negative' USING ERRCODE = '22023';
    END IF;

    -- Columns are NUMERIC(14,2)/(10,2): a third decimal would be rounded
    -- independently on each side of the transfer and mint or burn money.
    IF p_amount <> round(p_amount, 2) OR p_fee <> round(p_fee, 2) THEN
        RAISE EXCEPTION 'Transfer amount and fee must have at most 2 decimal places' USING ERRCODE = '22023';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'Cannot transfer between the same account' USING ERRCODE = '22023';
    END IF;

    -- Strict NULL-safe membership check
    IF p_household_id IS NULL OR public.get_auth_user_household_id() IS NULL OR p_household_id IS DISTINCT FROM public.get_auth_user_household_id() THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to specified household' USING ERRCODE = '42501';
    END IF;

    -- Lock accounts in deterministic UUID order to prevent deadlocks
    IF p_from_account_id < p_to_account_id THEN
        SELECT * INTO v_from_acc FROM public.accounts WHERE id = p_from_account_id FOR UPDATE;
        SELECT * INTO v_to_acc FROM public.accounts WHERE id = p_to_account_id FOR UPDATE;
    ELSE
        SELECT * INTO v_to_acc FROM public.accounts WHERE id = p_to_account_id FOR UPDATE;
        SELECT * INTO v_from_acc FROM public.accounts WHERE id = p_from_account_id FOR UPDATE;
    END IF;

    IF v_from_acc.id IS NULL THEN
        RAISE EXCEPTION 'Source account not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_to_acc.id IS NULL THEN
        RAISE EXCEPTION 'Destination account not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_from_acc.household_id <> p_household_id OR v_to_acc.household_id <> p_household_id THEN
        RAISE EXCEPTION 'Both accounts must belong to the household' USING ERRCODE = '42501';
    END IF;

    -- Caller must own source account OR source account is shared pool
    IF v_from_acc.is_shared_pool = false AND v_from_acc.owner_user_id <> v_caller_uid THEN
        RAISE EXCEPTION 'Access denied: cannot transfer from an account owned by another user' USING ERRCODE = '42501';
    END IF;

    v_total_deduction := p_amount + p_fee;
    IF v_from_acc.balance < v_total_deduction THEN
        RAISE EXCEPTION 'Insufficient funds: balance (%) is less than transfer plus fee (%)', v_from_acc.balance, v_total_deduction USING ERRCODE = '22000';
    END IF;

    UPDATE public.accounts
    SET balance = balance - v_total_deduction,
        updated_at = v_created_at
    WHERE id = p_from_account_id;

    UPDATE public.accounts
    SET balance = balance + p_amount,
        updated_at = v_created_at
    WHERE id = p_to_account_id;

    INSERT INTO public.account_transfers (
        household_id,
        user_id,
        from_account_id,
        to_account_id,
        amount,
        fee,
        timestamp,
        notes,
        created_at
    ) VALUES (
        p_household_id,
        v_caller_uid,
        p_from_account_id,
        p_to_account_id,
        p_amount,
        p_fee,
        v_created_at,
        p_notes,
        v_created_at
    ) RETURNING id INTO v_transfer_id;

    SELECT jsonb_build_object(
        'id', v_transfer_id,
        'household_id', p_household_id,
        'user_id', v_caller_uid,
        'from_account_id', p_from_account_id,
        'to_account_id', p_to_account_id,
        'amount', p_amount,
        'fee', p_fee,
        'timestamp', v_created_at,
        'notes', p_notes,
        'created_at', v_created_at
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- 2. record_income: precision, non-negative components, cycle_key format/derivation
CREATE OR REPLACE FUNCTION public.record_income(
    p_household_id UUID,
    p_account_id UUID,
    p_cycle_key TEXT,
    p_source_type TEXT,
    p_title TEXT,
    p_base_amount NUMERIC,
    p_overtime NUMERIC DEFAULT 0.0,
    p_bonus NUMERIC DEFAULT 0.0,
    p_deductions NUMERIC DEFAULT 0.0,
    p_received_at TIMESTAMPTZ DEFAULT now(),
    p_notes TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid UUID;
    v_acc RECORD;
    v_net_amount NUMERIC;
    v_income_id UUID;
    v_received_at TIMESTAMPTZ := COALESCE(p_received_at, now());
    v_cycle_key TEXT;
    v_result jsonb;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    -- Strict NULL-safe membership check
    IF p_household_id IS NULL OR public.get_auth_user_household_id() IS NULL OR p_household_id IS DISTINCT FROM public.get_auth_user_household_id() THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to specified household' USING ERRCODE = '42501';
    END IF;

    IF COALESCE(p_base_amount, 0.0) < 0 OR COALESCE(p_overtime, 0.0) < 0
       OR COALESCE(p_bonus, 0.0) < 0 OR COALESCE(p_deductions, 0.0) < 0 THEN
        RAISE EXCEPTION 'Income components cannot be negative' USING ERRCODE = '22023';
    END IF;

    IF COALESCE(p_base_amount, 0.0) <> round(COALESCE(p_base_amount, 0.0), 2)
       OR COALESCE(p_overtime, 0.0) <> round(COALESCE(p_overtime, 0.0), 2)
       OR COALESCE(p_bonus, 0.0) <> round(COALESCE(p_bonus, 0.0), 2)
       OR COALESCE(p_deductions, 0.0) <> round(COALESCE(p_deductions, 0.0), 2) THEN
        RAISE EXCEPTION 'Income amounts must have at most 2 decimal places' USING ERRCODE = '22023';
    END IF;

    IF p_title IS NULL OR btrim(p_title) = '' THEN
        RAISE EXCEPTION 'Income title is required' USING ERRCODE = '22023';
    END IF;

    IF p_cycle_key IS NULL THEN
        SELECT c.cycle_key INTO v_cycle_key
        FROM public.get_saudi_cycle_for_timestamp(
            v_received_at,
            COALESCE((SELECT h.payday_day FROM public.households h WHERE h.id = p_household_id), 27)
        ) c;
    ELSIF p_cycle_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
        v_cycle_key := p_cycle_key;
    ELSE
        RAISE EXCEPTION 'cycle_key must be formatted YYYY-MM' USING ERRCODE = '22023';
    END IF;

    v_net_amount := COALESCE(p_base_amount, 0.0) + COALESCE(p_overtime, 0.0) + COALESCE(p_bonus, 0.0) - COALESCE(p_deductions, 0.0);
    IF v_net_amount <= 0 THEN
        RAISE EXCEPTION 'Net income amount must be positive' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_acc FROM public.accounts WHERE id = p_account_id FOR UPDATE;
    IF v_acc.id IS NULL THEN
        RAISE EXCEPTION 'Target account not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_acc.household_id <> p_household_id THEN
        RAISE EXCEPTION 'Target account belongs to another household' USING ERRCODE = '42501';
    END IF;

    IF v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid THEN
        RAISE EXCEPTION 'Access denied: cannot record income into an account owned by another user' USING ERRCODE = '42501';
    END IF;

    UPDATE public.accounts
    SET balance = balance + v_net_amount,
        updated_at = now()
    WHERE id = p_account_id;

    INSERT INTO public.income_records (
        household_id,
        user_id,
        account_id,
        cycle_key,
        source_type,
        title,
        base_amount,
        overtime,
        bonus,
        deductions,
        net_amount,
        received_at,
        notes,
        created_at
    ) VALUES (
        p_household_id,
        v_caller_uid,
        p_account_id,
        v_cycle_key,
        p_source_type,
        p_title,
        COALESCE(p_base_amount, 0.0),
        COALESCE(p_overtime, 0.0),
        COALESCE(p_bonus, 0.0),
        COALESCE(p_deductions, 0.0),
        v_net_amount,
        v_received_at,
        p_notes,
        now()
    ) RETURNING id INTO v_income_id;

    SELECT jsonb_build_object(
        'id', v_income_id,
        'household_id', p_household_id,
        'user_id', v_caller_uid,
        'account_id', p_account_id,
        'cycle_key', v_cycle_key,
        'source_type', p_source_type,
        'title', p_title,
        'base_amount', p_base_amount,
        'overtime', p_overtime,
        'bonus', p_bonus,
        'deductions', p_deductions,
        'net_amount', v_net_amount,
        'received_at', v_received_at,
        'notes', p_notes,
        'created_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- 3. Append-only ledgers: clients read, RPCs write
DROP POLICY IF EXISTS income_insert_household ON public.income_records;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.income_records FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.account_transfers FROM anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.transfer_between_accounts(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_between_accounts(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.record_income(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_income(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT) TO authenticated, service_role;

COMMIT;
