-- ----------------------------------------------------------------------
-- Migration: 20261019090000_sec05_accounts_security_and_transfers.sql
-- SEC-05: Accounts Security, Atomic Transfers, Income Records & Balance Triggers
-- ----------------------------------------------------------------------

-- 0. Ensure schema columns exist on households, transactions, transfers, and income records
ALTER TABLE public.households ADD COLUMN IF NOT EXISTS accumulated_savings NUMERIC(12, 2) DEFAULT 0.00;
ALTER TABLE public.households ADD COLUMN IF NOT EXISTS last_rollover_surplus NUMERIC(12, 2) DEFAULT 0.00;
ALTER TABLE public.households ADD COLUMN IF NOT EXISTS last_rollover_cycle VARCHAR(7);

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_account ON public.transactions(account_id);

ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS account_type TEXT DEFAULT 'checking';
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts' AND column_name = 'type') THEN
        ALTER TABLE public.accounts ALTER COLUMN type DROP NOT NULL;
    END IF;
END $$;

ALTER TABLE public.account_transfers ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE public.account_transfers ADD COLUMN IF NOT EXISTS fee NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.account_transfers ADD COLUMN IF NOT EXISTS timestamp TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id);
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS cycle_key TEXT;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS source_type TEXT;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS base_amount NUMERIC(14, 2) DEFAULT 0.00;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS overtime NUMERIC(14, 2) DEFAULT 0.00;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS bonus NUMERIC(14, 2) DEFAULT 0.00;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS deductions NUMERIC(14, 2) DEFAULT 0.00;
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS net_amount NUMERIC(14, 2);
ALTER TABLE public.income_records ADD COLUMN IF NOT EXISTS notes TEXT;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'income_records' AND column_name = 'amount') THEN
        ALTER TABLE public.income_records ALTER COLUMN amount DROP NOT NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'income_records' AND column_name = 'source') THEN
        ALTER TABLE public.income_records ALTER COLUMN source DROP NOT NULL;
    END IF;
END $$;



-- 1. Hardened RLS Policies on public.accounts
DROP POLICY IF EXISTS "Users can manage personal accounts" ON public.accounts;
DROP POLICY IF EXISTS "Household members can update shared pool accounts" ON public.accounts;
DROP POLICY IF EXISTS "Users view their accounts or shared pools" ON public.accounts;
DROP POLICY IF EXISTS "accounts_select" ON public.accounts;
DROP POLICY IF EXISTS "accounts_insert_personal" ON public.accounts;
DROP POLICY IF EXISTS "accounts_insert_shared" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_personal" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_shared" ON public.accounts;
DROP POLICY IF EXISTS "accounts_delete_admin_or_owner" ON public.accounts;

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "accounts_select" ON public.accounts
    FOR SELECT TO authenticated
    USING (
        owner_user_id = auth.uid()
        OR (is_shared_pool = true AND household_id = public.get_auth_user_household_id())
    );

CREATE POLICY "accounts_insert_personal" ON public.accounts
    FOR INSERT TO authenticated
    WITH CHECK (
        owner_user_id = auth.uid()
        AND household_id = public.get_auth_user_household_id()
        AND is_shared_pool = false
    );

CREATE POLICY "accounts_insert_shared" ON public.accounts
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
        AND is_shared_pool = true
        AND public.get_auth_user_role() = 'admin'
    );

CREATE POLICY "accounts_update_personal" ON public.accounts
    FOR UPDATE TO authenticated
    USING (
        owner_user_id = auth.uid()
        AND household_id = public.get_auth_user_household_id()
    )
    WITH CHECK (
        owner_user_id = auth.uid()
        AND household_id = public.get_auth_user_household_id()
        AND is_shared_pool = false
    );

CREATE POLICY "accounts_update_shared" ON public.accounts
    FOR UPDATE TO authenticated
    USING (
        is_shared_pool = true
        AND household_id = public.get_auth_user_household_id()
        AND public.get_auth_user_role() = 'admin'
    )
    WITH CHECK (
        is_shared_pool = true
        AND household_id = public.get_auth_user_household_id()
        AND public.get_auth_user_role() = 'admin'
    );

CREATE POLICY "accounts_delete_admin_or_owner" ON public.accounts
    FOR DELETE TO authenticated
    USING (
        (owner_user_id = auth.uid() AND is_shared_pool = false)
        OR (is_shared_pool = true AND household_id = public.get_auth_user_household_id() AND public.get_auth_user_role() = 'admin')
    );

-- 2. Hardened RLS Policies on public.account_transfers (Append-Only Ledger)
DROP POLICY IF EXISTS "Household members view and create transfers" ON public.account_transfers;
DROP POLICY IF EXISTS "transfers_select_household" ON public.account_transfers;
DROP POLICY IF EXISTS "transfers_insert_household" ON public.account_transfers;

ALTER TABLE public.account_transfers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "transfers_select_household" ON public.account_transfers
    FOR SELECT TO authenticated
    USING (household_id = public.get_auth_user_household_id());

CREATE POLICY "transfers_insert_household" ON public.account_transfers
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
        AND user_id = auth.uid()
    );

-- 3. Hardened RLS Policies on public.income_records
DROP POLICY IF EXISTS "Household members view and record income" ON public.income_records;
DROP POLICY IF EXISTS "income_select_household" ON public.income_records;
DROP POLICY IF EXISTS "income_insert_household" ON public.income_records;
DROP POLICY IF EXISTS "income_update_household" ON public.income_records;
DROP POLICY IF EXISTS "income_delete_household" ON public.income_records;

ALTER TABLE public.income_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "income_select_household" ON public.income_records
    FOR SELECT TO authenticated
    USING (household_id = public.get_auth_user_household_id());

CREATE POLICY "income_insert_household" ON public.income_records
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
        AND user_id = auth.uid()
    );

CREATE POLICY "income_update_household" ON public.income_records
    FOR UPDATE TO authenticated
    USING (
        household_id = public.get_auth_user_household_id()
        AND (user_id = auth.uid() OR public.get_auth_user_role() = 'admin')
    )
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
    );

CREATE POLICY "income_delete_household" ON public.income_records
    FOR DELETE TO authenticated
    USING (
        household_id = public.get_auth_user_household_id()
        AND (user_id = auth.uid() OR public.get_auth_user_role() = 'admin')
    );

-- 4. Atomic Inter-Account Transfer RPC Function
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

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'Cannot transfer between the same account' USING ERRCODE = '22023';
    END IF;

    -- Check caller membership in household
    IF p_household_id <> public.get_auth_user_household_id() THEN
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

    -- Check authorization on source account:
    -- Caller must own source account OR source account is shared pool
    IF v_from_acc.is_shared_pool = false AND v_from_acc.owner_user_id <> v_caller_uid THEN
        RAISE EXCEPTION 'Access denied: cannot transfer from an account owned by another user' USING ERRCODE = '42501';
    END IF;

    v_total_deduction := p_amount + p_fee;
    IF v_from_acc.balance < v_total_deduction THEN
        RAISE EXCEPTION 'Insufficient funds: balance (%) is less than transfer plus fee (%)', v_from_acc.balance, v_total_deduction USING ERRCODE = '22000';
    END IF;

    -- Perform atomic balance updates
    UPDATE public.accounts
    SET balance = balance - v_total_deduction,
        updated_at = v_created_at
    WHERE id = p_from_account_id;

    UPDATE public.accounts
    SET balance = balance + p_amount,
        updated_at = v_created_at
    WHERE id = p_to_account_id;

    -- Insert transfer log
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

-- 5. Atomic Income Recording RPC Function
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
    v_result jsonb;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_household_id <> public.get_auth_user_household_id() THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to specified household' USING ERRCODE = '42501';
    END IF;

    v_net_amount := COALESCE(p_base_amount, 0.0) + COALESCE(p_overtime, 0.0) + COALESCE(p_bonus, 0.0) - COALESCE(p_deductions, 0.0);
    IF v_net_amount <= 0 THEN
        RAISE EXCEPTION 'Net income amount must be positive' USING ERRCODE = '22023';
    END IF;

    -- Lock account row
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

    -- Atomic balance update
    UPDATE public.accounts
    SET balance = balance + v_net_amount,
        updated_at = now()
    WHERE id = p_account_id;

    -- Insert income record
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
        p_cycle_key,
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
        'cycle_key', p_cycle_key,
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

-- 6. Automated Transaction Account Balance Maintenance Trigger
CREATE OR REPLACE FUNCTION public.update_account_balance_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.account_id IS NOT NULL THEN
            UPDATE public.accounts
            SET balance = balance - NEW.amount,
                updated_at = now()
            WHERE id = NEW.account_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.account_id IS NOT NULL THEN
            UPDATE public.accounts
            SET balance = balance + OLD.amount,
                updated_at = now()
            WHERE id = OLD.account_id;
        END IF;
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.account_id IS DISTINCT FROM NEW.account_id OR OLD.amount <> NEW.amount THEN
            IF OLD.account_id IS NOT NULL THEN
                UPDATE public.accounts
                SET balance = balance + OLD.amount,
                    updated_at = now()
                WHERE id = OLD.account_id;
            END IF;
            IF NEW.account_id IS NOT NULL THEN
                UPDATE public.accounts
                SET balance = balance - NEW.amount,
                    updated_at = now()
                WHERE id = NEW.account_id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_account_balance_on_transaction ON public.transactions;
CREATE TRIGGER trg_update_account_balance_on_transaction
AFTER INSERT OR UPDATE OF amount, account_id OR DELETE ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.update_account_balance_on_transaction();
