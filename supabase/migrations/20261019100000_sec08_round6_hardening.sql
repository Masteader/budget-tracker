-- ----------------------------------------------------------------------
-- Migration: 20261019100000_sec08_round6_hardening.sql
-- SEC-08: Round 6 Hardening (Merged Argon + Claude Audit)
-- ----------------------------------------------------------------------

-- ============================================================================
-- A. ACCOUNTS & BALANCE INTEGRITY (SEC-05)
-- ============================================================================

-- Ensure all metadata columns exist on public.accounts
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS color_hex TEXT DEFAULT '#00E5BF';
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS icon_name TEXT DEFAULT 'account_balance_rounded';
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT false;
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'SAR';

-- 1. Column-Level Privilege Lock on public.accounts
-- Revoke broad table UPDATE from client roles
REVOKE UPDATE ON public.accounts FROM PUBLIC, anon, authenticated;

-- Grant column-level UPDATE ONLY on safe metadata columns to authenticated
GRANT UPDATE (name, account_type, type, currency, color_hex, icon_name, is_archived, updated_at)
    ON public.accounts TO authenticated;

-- Ensure RLS policies restrict row visibility and metadata editing
DROP POLICY IF EXISTS "accounts_update_personal" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_shared" ON public.accounts;

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

-- 2. Tighten transactions RLS policies
DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
DROP POLICY IF EXISTS "transactions_update_household" ON public.transactions;

CREATE POLICY "transactions_insert_household" ON public.transactions
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
        AND (
            account_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.accounts a
                WHERE a.id = transactions.account_id
                  AND a.household_id = transactions.household_id
                  AND (a.is_shared_pool = true OR a.owner_user_id = auth.uid())
            )
        )
    );

CREATE POLICY "transactions_update_household" ON public.transactions
    FOR UPDATE TO authenticated
    USING (household_id = public.get_auth_user_household_id())
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
        AND (
            account_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.accounts a
                WHERE a.id = transactions.account_id
                  AND a.household_id = transactions.household_id
                  AND (a.is_shared_pool = true OR a.owner_user_id = auth.uid())
            )
        )
    );

-- 3. Automate Account Balance Maintenance Trigger with Strict Cross-Account Authorization
CREATE OR REPLACE FUNCTION public.update_account_balance_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_acc RECORD;
    v_caller_uid UUID := auth.uid();
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.account_id IS NOT NULL THEN
            SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id FOR UPDATE;
            IF v_acc.id IS NULL THEN
                RAISE EXCEPTION 'Target account % not found', NEW.account_id USING ERRCODE = 'P0002';
            END IF;
            IF v_acc.household_id <> NEW.household_id THEN
                RAISE EXCEPTION 'Account % does not belong to transaction household %', NEW.account_id, NEW.household_id USING ERRCODE = '42501';
            END IF;
            IF v_caller_uid IS NOT NULL AND v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid THEN
                RAISE EXCEPTION 'Access denied: cannot debit personal account owned by another user' USING ERRCODE = '42501';
            END IF;

            UPDATE public.accounts
            SET balance = balance - NEW.amount,
                updated_at = now()
            WHERE id = NEW.account_id;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.account_id IS NOT NULL THEN
            SELECT * INTO v_acc FROM public.accounts WHERE id = OLD.account_id FOR UPDATE;
            IF v_acc.id IS NOT NULL THEN
                IF v_acc.household_id <> OLD.household_id THEN
                    RAISE EXCEPTION 'Account % does not belong to transaction household %', OLD.account_id, OLD.household_id USING ERRCODE = '42501';
                END IF;
                IF v_caller_uid IS NOT NULL AND v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid THEN
                    RAISE EXCEPTION 'Access denied: cannot credit personal account owned by another user' USING ERRCODE = '42501';
                END IF;

                UPDATE public.accounts
                SET balance = balance + OLD.amount,
                    updated_at = now()
                WHERE id = OLD.account_id;
            END IF;
        END IF;
        RETURN OLD;

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.account_id IS DISTINCT FROM NEW.account_id OR OLD.amount <> NEW.amount THEN
            -- Revert old account debit
            IF OLD.account_id IS NOT NULL THEN
                SELECT * INTO v_acc FROM public.accounts WHERE id = OLD.account_id FOR UPDATE;
                IF v_acc.id IS NOT NULL THEN
                    IF v_acc.household_id <> OLD.household_id THEN
                        RAISE EXCEPTION 'Account % does not belong to transaction household %', OLD.account_id, OLD.household_id USING ERRCODE = '42501';
                    END IF;
                    IF v_caller_uid IS NOT NULL AND v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid THEN
                        RAISE EXCEPTION 'Access denied: cannot credit personal account owned by another user' USING ERRCODE = '42501';
                    END IF;

                    UPDATE public.accounts
                    SET balance = balance + OLD.amount,
                        updated_at = now()
                    WHERE id = OLD.account_id;
                END IF;
            END IF;

            -- Apply new account debit
            IF NEW.account_id IS NOT NULL THEN
                SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id FOR UPDATE;
                IF v_acc.id IS NULL THEN
                    RAISE EXCEPTION 'Target account % not found', NEW.account_id USING ERRCODE = 'P0002';
                END IF;
                IF v_acc.household_id <> NEW.household_id THEN
                    RAISE EXCEPTION 'Account % does not belong to transaction household %', NEW.account_id, NEW.household_id USING ERRCODE = '42501';
                END IF;
                IF v_caller_uid IS NOT NULL AND v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid THEN
                    RAISE EXCEPTION 'Access denied: cannot debit personal account owned by another user' USING ERRCODE = '42501';
                END IF;

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

-- 4. Ledger Immutability: Drop direct client INSERT on account_transfers
DROP POLICY IF EXISTS "transfers_insert_household" ON public.account_transfers;

-- 5. Ledger Immutability: Drop direct client UPDATE and DELETE on income_records
DROP POLICY IF EXISTS "income_update_household" ON public.income_records;
DROP POLICY IF EXISTS "income_delete_household" ON public.income_records;

-- Trigger to maintain accounts balance consistency if income records are edited or deleted administratively
CREATE OR REPLACE FUNCTION public.adjust_account_balance_on_income_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.account_id IS NOT NULL AND OLD.net_amount IS NOT NULL THEN
            UPDATE public.accounts
            SET balance = balance - OLD.net_amount,
                updated_at = now()
            WHERE id = OLD.account_id;
        END IF;
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.account_id IS DISTINCT FROM NEW.account_id OR OLD.net_amount IS DISTINCT FROM NEW.net_amount THEN
            IF OLD.account_id IS NOT NULL AND OLD.net_amount IS NOT NULL THEN
                UPDATE public.accounts
                SET balance = balance - OLD.net_amount,
                    updated_at = now()
                WHERE id = OLD.account_id;
            END IF;
            IF NEW.account_id IS NOT NULL AND NEW.net_amount IS NOT NULL THEN
                UPDATE public.accounts
                SET balance = balance + NEW.net_amount,
                    updated_at = now()
                WHERE id = NEW.account_id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_adjust_account_balance_on_income_change ON public.income_records;
CREATE TRIGGER trg_adjust_account_balance_on_income_change
AFTER UPDATE OR DELETE ON public.income_records
FOR EACH ROW
EXECUTE FUNCTION public.adjust_account_balance_on_income_change();


-- ============================================================================
-- B. FIX NULL COMPARISON BUG IN FINANCIAL RPCS
-- ============================================================================

-- Fix transfer_between_accounts
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

-- Fix record_income
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

    -- Strict NULL-safe membership check
    IF p_household_id IS NULL OR public.get_auth_user_household_id() IS NULL OR p_household_id IS DISTINCT FROM public.get_auth_user_household_id() THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to specified household' USING ERRCODE = '42501';
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


-- ============================================================================
-- C. FUNCTION GRANTS & QUOTA RPC HARDENING
-- ============================================================================

-- 1. Quota RPCs: restrict execution exclusively to service_role
REVOKE ALL ON FUNCTION public.consume_quota(UUID, TEXT, INT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_quota(UUID, TEXT, INT, INT) TO service_role;

REVOKE ALL ON FUNCTION public.check_quota_status(UUID, TEXT, INT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_quota_status(UUID, TEXT, INT, INT) TO service_role;

-- 2. Trigger functions: revoke execution from client roles
REVOKE EXECUTE ON FUNCTION public.check_last_admin_membership() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.populate_transaction_cycle_key() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_account_balance_on_transaction() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_update() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_delete() FROM PUBLIC, anon, authenticated;

-- 3. Financial RPCs: grant to authenticated and service_role, revoke from anon/PUBLIC
REVOKE EXECUTE ON FUNCTION public.transfer_between_accounts(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_between_accounts(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.record_income(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_income(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_saudi_cycle_for_timestamp(TIMESTAMPTZ, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_saudi_cycle_for_timestamp(TIMESTAMPTZ, INT) TO authenticated, service_role;


-- ============================================================================
-- F. INVITE CODE LENGTH, ATOMIC CLAIM RPC & RETURNING FOUND
-- ============================================================================

-- Expand invite_code column lengths to support 16-hex characters
ALTER TABLE public.households ALTER COLUMN invite_code TYPE VARCHAR(16);
ALTER TABLE public.household_invites ALTER COLUMN invite_code TYPE VARCHAR(16);

-- Rotate legacy 8-character codes to 16-character hex
UPDATE public.households
SET invite_code = upper(encode(extensions.gen_random_bytes(8), 'hex'))
WHERE length(invite_code) < 16;

-- Fix race condition in join_household_by_code
CREATE OR REPLACE FUNCTION public.join_household_by_code(p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_clean_code text := upper(trim(p_invite_code));
    v_fail_count int;
    v_invite public.household_invites%ROWTYPE;
    v_hh public.households%ROWTYPE;
    v_claimed_id uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Rate limiting check
    SELECT count(*) INTO v_fail_count
    FROM public.invite_attempt_log
    WHERE user_id = v_uid 
      AND success = false 
      AND attempted_at > (now() - interval '15 minutes');

    IF v_fail_count >= 5 THEN
        RAISE EXCEPTION 'Too many failed join attempts. Please try again in 15 minutes.';
    END IF;

    -- 1. Check household_invites table
    SELECT * INTO v_invite
    FROM public.household_invites
    WHERE upper(trim(invite_code)) = v_clean_code;

    IF v_invite.id IS NOT NULL THEN
        IF v_invite.expires_at < now() THEN
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has expired');
        END IF;

        -- Atomic update with RETURNING to prevent race conditions
        UPDATE public.household_invites
        SET used_by = v_uid
        WHERE id = v_invite.id AND used_by IS NULL
        RETURNING id INTO v_claimed_id;

        IF v_claimed_id IS NULL THEN
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has already been used');
        END IF;

        SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

        -- Link target member if present
        IF v_invite.target_member_id IS NOT NULL THEN
            UPDATE public.household_dependents
            SET claimed_user_id = v_uid
            WHERE id = v_invite.target_member_id;
        END IF;

        UPDATE public.users
        SET household_id = v_hh.id,
            role = 'member',
            financial_role = CASE
                WHEN v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent') THEN v_invite.role
                ELSE financial_role
            END
        WHERE id = v_uid;

        INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
        VALUES (v_hh.id, v_uid, 'member', false)
        ON CONFLICT (household_id, user_id) DO UPDATE SET role = COALESCE(public.household_memberships.role, 'member');

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    -- 2. Fallback to households.invite_code (static master code)
    SELECT * INTO v_hh
    FROM public.households
    WHERE upper(trim(invite_code)) = v_clean_code;

    IF v_hh.id IS NOT NULL THEN
        UPDATE public.users
        SET household_id = v_hh.id,
            role = 'member'
        WHERE id = v_uid;

        INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
        VALUES (v_hh.id, v_uid, 'member', false)
        ON CONFLICT (household_id, user_id) DO NOTHING;

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
    RETURN jsonb_build_object('success', false, 'error', 'Invalid invite code');
END;
$$;

-- Atomic role invite claim RPC
CREATE OR REPLACE FUNCTION public.claim_household_role_invite(
    p_invite_code text,
    p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := COALESCE(p_user_id, auth.uid());
    v_clean_code text := upper(trim(p_invite_code));
    v_invite public.household_invites%ROWTYPE;
    v_hh public.households%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    UPDATE public.household_invites
    SET used_by = v_uid
    WHERE upper(trim(invite_code)) = v_clean_code
      AND used_by IS NULL
      AND expires_at > now()
    RETURNING * INTO v_invite;

    IF v_invite.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
    END IF;

    SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

    IF v_invite.target_member_id IS NOT NULL THEN
        UPDATE public.household_dependents
        SET claimed_user_id = v_uid
        WHERE id = v_invite.target_member_id;
    END IF;

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'member',
        financial_role = CASE
            WHEN v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent') THEN v_invite.role
            ELSE financial_role
        END
    WHERE id = v_uid;

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_hh.id, v_uid, 'member', false)
    ON CONFLICT (household_id, user_id) 
    DO UPDATE SET role = COALESCE(public.household_memberships.role, 'member');

    RETURN jsonb_build_object(
        'success', true,
        'household_id', v_hh.id,
        'household_name', v_hh.name,
        'role', v_invite.role,
        'target_member_id', v_invite.target_member_id
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_household_role_invite(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_household_role_invite(text, uuid) TO authenticated, service_role;

-- Stop returning households.invite_code to non-admins in get_user_households()
CREATE OR REPLACE FUNCTION public.get_user_households()
RETURNS TABLE(household_id uuid, household_name text, invite_code text, role text, is_active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        h.id AS household_id,
        h.name::text AS household_name,
        CASE WHEN m.role = 'admin' THEN h.invite_code::text ELSE NULL END AS invite_code,
        m.role::text,
        (h.id = u.household_id) AS is_active
    FROM public.household_memberships m
    JOIN public.households h ON h.id = m.household_id
    JOIN public.users u ON u.id = m.user_id
    WHERE m.user_id = auth.uid()
    ORDER BY is_active DESC, m.created_at ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_user_households() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_households() TO authenticated, service_role;


-- ============================================================================
-- G. CATEGORY CODE INTEGRITY TRIGGER & BUDGET UPDATE FIX
-- ============================================================================

-- 1. Category code validation trigger
CREATE OR REPLACE FUNCTION public.validate_category_code_exists()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.category_code IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.cost_control_codes
            WHERE code = NEW.category_code
              AND (household_id IS NULL OR household_id = NEW.household_id)
        ) THEN
            RAISE EXCEPTION 'Category code % does not exist in global or household taxonomy', NEW.category_code
                USING ERRCODE = '23503';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_category_budgets ON public.budgets;
CREATE TRIGGER trg_validate_category_budgets
BEFORE INSERT OR UPDATE OF category_code, household_id ON public.budgets
FOR EACH ROW EXECUTE FUNCTION public.validate_category_code_exists();

DROP TRIGGER IF EXISTS trg_validate_category_transactions ON public.transactions;
CREATE TRIGGER trg_validate_category_transactions
BEFORE INSERT OR UPDATE OF category_code, household_id ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.validate_category_code_exists();

DROP TRIGGER IF EXISTS trg_validate_category_settings ON public.household_category_settings;
CREATE TRIGGER trg_validate_category_settings
BEFORE INSERT OR UPDATE OF category_code, household_id ON public.household_category_settings
FOR EACH ROW EXECUTE FUNCTION public.validate_category_code_exists();

-- 2. Fix OLD.category_code IS DISTINCT FROM NEW.category_code in update_budget_on_transaction_update
CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.amount <> NEW.amount 
       OR OLD.category_code IS DISTINCT FROM NEW.category_code 
       OR OLD.cycle_key IS DISTINCT FROM NEW.cycle_key
       OR date_trunc('month', OLD.timestamp) IS DISTINCT FROM date_trunc('month', NEW.timestamp) THEN

        UPDATE public.budgets
        SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
        WHERE household_id  = OLD.household_id
          AND category_code = OLD.category_code
          AND (
              (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
              OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
          );

        UPDATE public.budgets
        SET spent_amount = spent_amount + NEW.amount
        WHERE household_id  = NEW.household_id
          AND category_code = NEW.category_code
          AND (
              (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
              OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
          );
    END IF;
    RETURN NEW;
END;
$$;
