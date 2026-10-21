-- ============================================================================
-- Rollback snapshot for the 20261020 audit batch
--   20261020005000_preflight_live_alignment.sql ... 20261020400000_admin_permissions_and_co_admins.sql
-- Snapshot date: 2026-10-20. Generated from a read-only catalog inventory of the
-- live project, taken before the batch (definitions and privileges only, no row
-- data). See docs/review/audit/live_db_preflight.md.
--
-- Run ONLY to undo the whole batch, in the SQL editor as `postgres`, after review.
-- It returns the schema, policies, functions, triggers, grants and bucket settings
-- to the pre-batch live state. It was verified on the local replica: batch ->
-- this script -> catalog identical to live -> batch re-applied -> 20/20 DB tests.
--
-- What it cannot undo:
--   * it drops member_allowances, spouse_reimbursements, households.owner_user_id
--     and transactions.nafaqah_class / nafaqah_spouse_id, so allowances,
--     reimbursements and Nafaqah classes recorded after the batch are lost
--     (export them first if any exist);
--   * the 'sms' -> chat / receipt_scan / manual relabel of transactions.source
--     stays (label only; the app already displayed those rows that way);
--   * membership rows backfilled by 20261020020000 stay (0 on live at snapshot time).
-- To roll back a single later migration instead, re-run the matching sections
-- by hand (function definitions are grouped in section 5).
-- ============================================================================

BEGIN;

-- 1. Triggers added or changed by the batch
DROP TRIGGER IF EXISTS "trg_validate_invite_target_member" ON public.household_invites;
DROP TRIGGER IF EXISTS "trg_maintain_primary_admin" ON public.household_memberships;
DROP TRIGGER IF EXISTS "trg_protect_primary_admin" ON public.household_memberships;
DROP TRIGGER IF EXISTS "trg_bind_transaction_creator" ON public.transactions;
DROP TRIGGER IF EXISTS "trg_enforce_transaction_write_permission" ON public.transactions;
DROP TRIGGER IF EXISTS "trg_populate_transaction_cycle_key" ON public.transactions;
DROP TRIGGER IF EXISTS "trg_validate_transaction_nafaqah_class" ON public.transactions;
DROP TRIGGER IF EXISTS "trg_handover_households_on_user_delete" ON public.users;

-- 2. Policies added or changed by the batch
DROP POLICY IF EXISTS "transfers_select_household" ON public."account_transfers";
DROP POLICY IF EXISTS "accounts_delete_admin_or_owner" ON public."accounts";
DROP POLICY IF EXISTS "accounts_insert_personal" ON public."accounts";
DROP POLICY IF EXISTS "accounts_insert_shared" ON public."accounts";
DROP POLICY IF EXISTS "accounts_select" ON public."accounts";
DROP POLICY IF EXISTS "accounts_update_personal" ON public."accounts";
DROP POLICY IF EXISTS "accounts_update_shared" ON public."accounts";
DROP POLICY IF EXISTS "budgets_insert_admin" ON public."budgets";
DROP POLICY IF EXISTS "budgets_select_household" ON public."budgets";
DROP POLICY IF EXISTS "budgets_update_admin" ON public."budgets";
DROP POLICY IF EXISTS "cost_control_codes_insert" ON public."cost_control_codes";
DROP POLICY IF EXISTS "cost_control_codes_select" ON public."cost_control_codes";
DROP POLICY IF EXISTS "cost_control_codes_update" ON public."cost_control_codes";
DROP POLICY IF EXISTS "household_category_settings_all" ON public."household_category_settings";
DROP POLICY IF EXISTS "dependents_delete_household" ON public."household_dependents";
DROP POLICY IF EXISTS "dependents_insert_household" ON public."household_dependents";
DROP POLICY IF EXISTS "dependents_select_household" ON public."household_dependents";
DROP POLICY IF EXISTS "dependents_update_household" ON public."household_dependents";
DROP POLICY IF EXISTS "invites_delete_admin" ON public."household_invites";
DROP POLICY IF EXISTS "invites_insert_household" ON public."household_invites";
DROP POLICY IF EXISTS "invites_select_household" ON public."household_invites";
DROP POLICY IF EXISTS "memberships_select_own_or_admin" ON public."household_memberships";
DROP POLICY IF EXISTS "households_select_own" ON public."households";
DROP POLICY IF EXISTS "households_update_admin" ON public."households";
DROP POLICY IF EXISTS "income_select_household" ON public."income_records";
DROP POLICY IF EXISTS "Allow household members full access to installment_plans" ON public."installment_plans";
DROP POLICY IF EXISTS "member_allowances_select_household" ON public."member_allowances";
DROP POLICY IF EXISTS "spouse_reimbursements_select_household" ON public."spouse_reimbursements";
DROP POLICY IF EXISTS "transactions_delete_household" ON public."transactions";
DROP POLICY IF EXISTS "transactions_insert_household" ON public."transactions";
DROP POLICY IF EXISTS "transactions_select_household" ON public."transactions";
DROP POLICY IF EXISTS "transactions_update_household" ON public."transactions";
DROP POLICY IF EXISTS "users_insert_own" ON public."users";
DROP POLICY IF EXISTS "users_select_household" ON public."users";
DROP POLICY IF EXISTS "users_update_own_profile" ON public."users";
DROP POLICY IF EXISTS "receipts_delete_household" ON storage."objects";
DROP POLICY IF EXISTS "receipts_insert_household" ON storage."objects";
DROP POLICY IF EXISTS "receipts_select_household" ON storage."objects";

-- 3. Constraints and indexes added by the batch
ALTER TABLE public."households" DROP CONSTRAINT IF EXISTS "households_owner_user_id_fkey";
ALTER TABLE public."transactions" DROP CONSTRAINT IF EXISTS "transactions_nafaqah_class_check";
ALTER TABLE public."transactions" DROP CONSTRAINT IF EXISTS "transactions_nafaqah_spouse_id_fkey";
ALTER TABLE public."transactions" DROP CONSTRAINT IF EXISTS "transactions_source_check";
DROP INDEX IF EXISTS public."idx_account_transfers_user";
DROP INDEX IF EXISTS public."idx_household_invites_created_by";
DROP INDEX IF EXISTS public."idx_household_invites_household";
DROP INDEX IF EXISTS public."idx_household_invites_used_by";
DROP INDEX IF EXISTS public."idx_households_owner_user_id";
DROP INDEX IF EXISTS public."idx_income_records_user";
DROP INDEX IF EXISTS public."idx_invite_attempt_log_user_time";
DROP INDEX IF EXISTS public."idx_transactions_nafaqah_spouse";
DROP INDEX IF EXISTS public."idx_transactions_reallocated_from_budget";

-- 4. Tables and columns added by the batch (drops only data created after the batch)
DROP TABLE IF EXISTS public."member_allowances";
DROP TABLE IF EXISTS public."spouse_reimbursements";
ALTER TABLE public."households" DROP COLUMN IF EXISTS "owner_user_id";
ALTER TABLE public."transactions" DROP COLUMN IF EXISTS "nafaqah_class";
ALTER TABLE public."transactions" DROP COLUMN IF EXISTS "nafaqah_spouse_id";

-- 5. Functions: drop the ones the batch added, restore the pre-batch definitions
DROP FUNCTION IF EXISTS public."bind_transaction_creator"();
DROP FUNCTION IF EXISTS public."enforce_transaction_write_permission"();
DROP FUNCTION IF EXISTS public."get_household_members"(p_household_id uuid, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."get_member_allowance_status"(p_household_id uuid, p_member_user_id uuid, p_cycle_key text, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."get_spouse_reimbursement_balance"(p_household_id uuid, p_wife_user_id uuid, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."handover_households_on_user_delete"();
DROP FUNCTION IF EXISTS public."household_apply_role"(p_household_id uuid, p_user_id uuid, p_role text);
DROP FUNCTION IF EXISTS public."household_member_role"(p_household_id uuid, p_user_id uuid);
DROP FUNCTION IF EXISTS public."household_primary_admin_id"(p_household_id uuid);
DROP FUNCTION IF EXISTS public."household_require_admin"(p_household_id uuid, p_actor uuid);
DROP FUNCTION IF EXISTS public."household_resolve_actor"(p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."is_household_admin"(p_household_id uuid);
DROP FUNCTION IF EXISTS public."maintain_household_primary_admin"();
DROP FUNCTION IF EXISTS public."nafaqah_current_cycle_key"(p_household_id uuid);
DROP FUNCTION IF EXISTS public."nafaqah_husband_id"(p_household_id uuid);
DROP FUNCTION IF EXISTS public."nafaqah_is_spouse_member"(p_household_id uuid, p_user_id uuid);
DROP FUNCTION IF EXISTS public."nafaqah_require_member"(p_household_id uuid, p_user_id uuid);
DROP FUNCTION IF EXISTS public."nafaqah_resolve_actor"(p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."promote_member_to_admin"(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."protect_primary_admin_membership"();
DROP FUNCTION IF EXISTS public."reallocate_budget"(p_from_id uuid, p_to_id uuid, p_amount numeric);
DROP FUNCTION IF EXISTS public."record_spouse_reimbursement"(p_household_id uuid, p_wife_user_id uuid, p_amount numeric, p_payment_method text, p_notes text, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."revoke_admin"(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."set_member_allowance"(p_household_id uuid, p_member_user_id uuid, p_amount numeric, p_cycle_key text, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."transaction_account_matches"(p_account_id uuid, p_household_id uuid, p_creator_user_id uuid);
DROP FUNCTION IF EXISTS public."transaction_personal_account_writable"(p_account accounts, p_creator_user_id uuid, p_caller_uid uuid);
DROP FUNCTION IF EXISTS public."transfer_primary_admin"(p_household_id uuid, p_new_primary_user_id uuid, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."validate_invite_target_member"();
DROP FUNCTION IF EXISTS public."validate_transaction_nafaqah_class"();
CREATE OR REPLACE FUNCTION public.claim_household_role_invite(p_invite_code text, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_uid uuid;
    v_clean_code text := upper(trim(p_invite_code));
    v_invite public.household_invites%ROWTYPE;
    v_hh public.households%ROWTYPE;
BEGIN
    IF auth.uid() IS NOT NULL AND p_user_id IS NOT NULL AND p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot claim an invite on behalf of another user' USING ERRCODE = '42501';
    END IF;

    v_uid := COALESCE(auth.uid(), p_user_id);

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
$function$;

CREATE OR REPLACE FUNCTION public.get_auth_user_household_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT household_id FROM public.users WHERE id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.get_auth_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT role FROM public.users WHERE id = auth.uid();
$function$;

DROP FUNCTION IF EXISTS public."get_user_households"();
CREATE OR REPLACE FUNCTION public.get_user_households()
 RETURNS TABLE(household_id uuid, household_name text, invite_code text, role text, is_active boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.join_household_by_code(p_invite_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        IF v_invite.used_by = v_uid THEN
            -- Already claimed by the same authenticated caller (idempotent / targeted claim flow)
            v_claimed_id := v_invite.id;
        ELSIF v_invite.used_by IS NULL THEN
            UPDATE public.household_invites
            SET used_by = v_uid
            WHERE id = v_invite.id AND used_by IS NULL
            RETURNING id INTO v_claimed_id;

            IF v_claimed_id IS NULL THEN
                INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
                RETURN jsonb_build_object('success', false, 'error', 'Invite code has already been used');
            END IF;
        ELSE
            -- Used by another user
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
$function$;

CREATE OR REPLACE FUNCTION public.record_income(p_household_id uuid, p_account_id uuid, p_cycle_key text, p_source_type text, p_title text, p_base_amount numeric, p_overtime numeric DEFAULT 0.0, p_bonus numeric DEFAULT 0.0, p_deductions numeric DEFAULT 0.0, p_received_at timestamp with time zone DEFAULT now(), p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.remove_member(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_caller_uid uuid := auth.uid();
    v_caller_hh_id uuid;
    v_caller_role text;
    v_target_role text;
    v_other_admins int;
    v_other_members int;
BEGIN
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT household_id, role INTO v_caller_hh_id, v_caller_role
    FROM public.users
    WHERE id = v_caller_uid;

    IF v_caller_hh_id IS NULL OR v_caller_role <> 'admin' THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT role INTO v_target_role
    FROM public.household_memberships
    WHERE household_id = v_caller_hh_id AND user_id = p_user_id;

    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household';
    END IF;

    IF p_user_id = v_caller_uid THEN
        SELECT count(*) INTO v_other_admins
        FROM public.household_memberships
        WHERE household_id = v_caller_hh_id AND role = 'admin' AND user_id <> p_user_id;

        SELECT count(*) INTO v_other_members
        FROM public.household_memberships
        WHERE household_id = v_caller_hh_id AND user_id <> p_user_id;

        IF v_other_admins = 0 AND v_other_members > 0 THEN
            RAISE EXCEPTION 'Sole admin cannot be removed while other members remain. Promote another member first.';
        END IF;
    END IF;

    DELETE FROM public.household_memberships
    WHERE household_id = v_caller_hh_id AND user_id = p_user_id;

    UPDATE public.users
    SET household_id = NULL,
        role = 'member'
    WHERE id = p_user_id AND household_id = v_caller_hh_id;

    RETURN jsonb_build_object(
        'success', true,
        'removed_user_id', p_user_id
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_member_role(p_user_id uuid, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_caller_uid uuid := auth.uid();
    v_caller_hh_id uuid;
    v_caller_role text;
    v_target_role text;
    v_other_admins int;
BEGIN
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT household_id, role INTO v_caller_hh_id, v_caller_role
    FROM public.users
    WHERE id = v_caller_uid;

    IF v_caller_hh_id IS NULL OR v_caller_role <> 'admin' THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    IF p_role NOT IN ('admin', 'member') THEN
        RAISE EXCEPTION 'Invalid role: must be admin or member';
    END IF;

    SELECT role INTO v_target_role
    FROM public.household_memberships
    WHERE household_id = v_caller_hh_id AND user_id = p_user_id;

    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household';
    END IF;

    -- Sole admin demotion protection
    IF v_target_role = 'admin' AND p_role = 'member' THEN
        SELECT count(*) INTO v_other_admins
        FROM public.household_memberships
        WHERE household_id = v_caller_hh_id AND role = 'admin' AND user_id <> p_user_id;

        IF v_other_admins = 0 THEN
            RAISE EXCEPTION 'Cannot demote the sole administrator of the household';
        END IF;
    END IF;

    UPDATE public.household_memberships
    SET role = p_role
    WHERE household_id = v_caller_hh_id AND user_id = p_user_id;

    UPDATE public.users
    SET role = p_role
    WHERE id = p_user_id AND household_id = v_caller_hh_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'new_role', p_role
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_user_household_membership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    IF NEW.household_id IS NOT NULL THEN
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
        VALUES (
            NEW.household_id, 
            NEW.id, 
            COALESCE(NEW.role, 'member'), 
            NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = NEW.id)
        )
        ON CONFLICT (household_id, user_id) 
        DO UPDATE SET role = COALESCE(EXCLUDED.role, public.household_memberships.role);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.transfer_between_accounts(p_household_id uuid, p_from_account_id uuid, p_to_account_id uuid, p_amount numeric, p_fee numeric DEFAULT 0.0, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.update_account_balance_on_transaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_acc RECORD;
    v_caller_uid UUID;
BEGIN
    BEGIN
        v_caller_uid := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_caller_uid := NULL;
    END;
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
$function$;

REVOKE ALL ON FUNCTION public."claim_household_role_invite"(p_invite_code text, p_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."claim_household_role_invite"(p_invite_code text, p_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."claim_household_role_invite"(p_invite_code text, p_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."get_auth_user_household_id"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."get_auth_user_household_id"() TO authenticated;
GRANT EXECUTE ON FUNCTION public."get_auth_user_household_id"() TO service_role;
REVOKE ALL ON FUNCTION public."get_auth_user_role"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."get_auth_user_role"() TO authenticated;
GRANT EXECUTE ON FUNCTION public."get_auth_user_role"() TO service_role;
REVOKE ALL ON FUNCTION public."get_user_households"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."get_user_households"() TO authenticated;
GRANT EXECUTE ON FUNCTION public."get_user_households"() TO service_role;
REVOKE ALL ON FUNCTION public."join_household_by_code"(p_invite_code text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."join_household_by_code"(p_invite_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."join_household_by_code"(p_invite_code text) TO service_role;
REVOKE ALL ON FUNCTION public."record_income"(p_household_id uuid, p_account_id uuid, p_cycle_key text, p_source_type text, p_title text, p_base_amount numeric, p_overtime numeric, p_bonus numeric, p_deductions numeric, p_received_at timestamp with time zone, p_notes text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."record_income"(p_household_id uuid, p_account_id uuid, p_cycle_key text, p_source_type text, p_title text, p_base_amount numeric, p_overtime numeric, p_bonus numeric, p_deductions numeric, p_received_at timestamp with time zone, p_notes text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."record_income"(p_household_id uuid, p_account_id uuid, p_cycle_key text, p_source_type text, p_title text, p_base_amount numeric, p_overtime numeric, p_bonus numeric, p_deductions numeric, p_received_at timestamp with time zone, p_notes text) TO service_role;
REVOKE ALL ON FUNCTION public."remove_member"(p_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."remove_member"(p_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."remove_member"(p_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."rls_auto_enable"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."rls_auto_enable"() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public."rls_auto_enable"() TO anon;
GRANT EXECUTE ON FUNCTION public."rls_auto_enable"() TO authenticated;
GRANT EXECUTE ON FUNCTION public."rls_auto_enable"() TO service_role;
REVOKE ALL ON FUNCTION public."set_member_role"(p_user_id uuid, p_role text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."set_member_role"(p_user_id uuid, p_role text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."set_member_role"(p_user_id uuid, p_role text) TO service_role;
REVOKE ALL ON FUNCTION public."sync_user_household_membership"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."sync_user_household_membership"() TO service_role;
ALTER FUNCTION public."sync_user_household_membership"() RESET ALL;
REVOKE ALL ON FUNCTION public."transfer_between_accounts"(p_household_id uuid, p_from_account_id uuid, p_to_account_id uuid, p_amount numeric, p_fee numeric, p_notes text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."transfer_between_accounts"(p_household_id uuid, p_from_account_id uuid, p_to_account_id uuid, p_amount numeric, p_fee numeric, p_notes text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."transfer_between_accounts"(p_household_id uuid, p_from_account_id uuid, p_to_account_id uuid, p_amount numeric, p_fee numeric, p_notes text) TO service_role;
REVOKE ALL ON FUNCTION public."update_account_balance_on_transaction"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."update_account_balance_on_transaction"() TO service_role;

-- 6. Column defaults, comments, RLS flags
COMMENT ON COLUMN public."transactions"."raw_sms" IS 'Original SMS text for audit trail.';
ALTER TABLE public."transactions" ALTER COLUMN "source" SET DEFAULT 'sms'::text;
COMMENT ON COLUMN public."transactions"."source" IS 'Ingestion channel: sms, chat, receipt_scan, or manual.';
COMMENT ON TABLE public."cost_control_codes" IS 'Category taxonomy + keyword mapping for SMS merchant matching.';
COMMENT ON TABLE public."transactions" IS 'Every SMS-derived expense transaction.';

-- 7. Pre-batch policies and triggers
CREATE POLICY "transfers_select_household" ON public."account_transfers" AS PERMISSIVE FOR SELECT TO authenticated USING ((household_id = get_auth_user_household_id()));
CREATE POLICY "accounts_delete_admin_or_owner" ON public."accounts" AS PERMISSIVE FOR DELETE TO authenticated USING ((((owner_user_id = auth.uid()) AND (is_shared_pool = false)) OR ((is_shared_pool = true) AND (household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text))));
CREATE POLICY "accounts_insert_personal" ON public."accounts" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((owner_user_id = auth.uid()) AND (household_id = get_auth_user_household_id()) AND (is_shared_pool = false)));
CREATE POLICY "accounts_insert_shared" ON public."accounts" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((household_id = get_auth_user_household_id()) AND (is_shared_pool = true) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "accounts_select" ON public."accounts" AS PERMISSIVE FOR SELECT TO authenticated USING (((owner_user_id = auth.uid()) OR ((is_shared_pool = true) AND (household_id = get_auth_user_household_id()))));
CREATE POLICY "accounts_update_personal" ON public."accounts" AS PERMISSIVE FOR UPDATE TO authenticated USING (((owner_user_id = auth.uid()) AND (household_id = get_auth_user_household_id()))) WITH CHECK (((owner_user_id = auth.uid()) AND (household_id = get_auth_user_household_id()) AND (is_shared_pool = false)));
CREATE POLICY "accounts_update_shared" ON public."accounts" AS PERMISSIVE FOR UPDATE TO authenticated USING (((is_shared_pool = true) AND (household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text))) WITH CHECK (((is_shared_pool = true) AND (household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "budgets_insert_admin" ON public."budgets" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "budgets_select_household" ON public."budgets" AS PERMISSIVE FOR SELECT TO authenticated USING ((household_id = get_auth_user_household_id()));
CREATE POLICY "budgets_update_admin" ON public."budgets" AS PERMISSIVE FOR UPDATE TO authenticated USING (((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text))) WITH CHECK (((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "cost_control_codes_select" ON public."cost_control_codes" AS PERMISSIVE FOR SELECT TO authenticated USING (((household_id IS NULL) OR (household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid())))));
CREATE POLICY "household_category_settings_all" ON public."household_category_settings" AS PERMISSIVE FOR ALL TO authenticated USING ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid())))) WITH CHECK ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid()))));
CREATE POLICY "dependents_delete_household" ON public."household_dependents" AS PERMISSIVE FOR DELETE TO authenticated USING ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid()))));
CREATE POLICY "dependents_insert_household" ON public."household_dependents" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid()))));
CREATE POLICY "dependents_select_household" ON public."household_dependents" AS PERMISSIVE FOR SELECT TO authenticated USING ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid()))));
CREATE POLICY "dependents_update_household" ON public."household_dependents" AS PERMISSIVE FOR UPDATE TO authenticated USING ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid())))) WITH CHECK ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid()))));
CREATE POLICY "invites_delete_admin" ON public."household_invites" AS PERMISSIVE FOR DELETE TO authenticated USING (((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "invites_insert_household" ON public."household_invites" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "invites_select_household" ON public."household_invites" AS PERMISSIVE FOR SELECT TO authenticated USING ((household_id = get_auth_user_household_id()));
CREATE POLICY "memberships_view_own" ON public."household_memberships" AS PERMISSIVE FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY "households_insert_authenticated" ON public."households" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((auth.uid() IS NOT NULL));
CREATE POLICY "households_select_own" ON public."households" AS PERMISSIVE FOR SELECT TO authenticated USING ((id = get_auth_user_household_id()));
CREATE POLICY "households_update_admin" ON public."households" AS PERMISSIVE FOR UPDATE TO authenticated USING (((id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text))) WITH CHECK (((id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text)));
CREATE POLICY "income_insert_household" ON public."income_records" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((household_id = get_auth_user_household_id()) AND (user_id = auth.uid())));
CREATE POLICY "income_select_household" ON public."income_records" AS PERMISSIVE FOR SELECT TO authenticated USING ((household_id = get_auth_user_household_id()));
CREATE POLICY "Allow household members full access to installment_plans" ON public."installment_plans" AS PERMISSIVE FOR ALL TO authenticated USING ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid())))) WITH CHECK ((household_id IN ( SELECT users.household_id
   FROM users
  WHERE (users.id = auth.uid()))));
CREATE POLICY "transactions_delete_household" ON public."transactions" AS PERMISSIVE FOR DELETE TO authenticated USING ((household_id = get_auth_user_household_id()));
CREATE POLICY "transactions_insert_household" ON public."transactions" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((household_id = get_auth_user_household_id()) AND ((account_id IS NULL) OR (EXISTS ( SELECT 1
   FROM accounts a
  WHERE ((a.id = transactions.account_id) AND (a.household_id = transactions.household_id) AND ((a.is_shared_pool = true) OR (a.owner_user_id = auth.uid()))))))));
CREATE POLICY "transactions_select_household" ON public."transactions" AS PERMISSIVE FOR SELECT TO authenticated USING (((auth.uid() IS NOT NULL) AND (household_id = get_auth_user_household_id())));
CREATE POLICY "transactions_update_household" ON public."transactions" AS PERMISSIVE FOR UPDATE TO authenticated USING ((household_id = get_auth_user_household_id())) WITH CHECK (((household_id = get_auth_user_household_id()) AND ((account_id IS NULL) OR (EXISTS ( SELECT 1
   FROM accounts a
  WHERE ((a.id = transactions.account_id) AND (a.household_id = transactions.household_id) AND ((a.is_shared_pool = true) OR (a.owner_user_id = auth.uid()))))))));
CREATE POLICY "users_insert_own" ON public."users" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((id = auth.uid()) AND (household_id IS NULL) AND (role = 'member'::text)));
CREATE POLICY "users_select_household" ON public."users" AS PERMISSIVE FOR SELECT TO authenticated USING (((id = auth.uid()) OR ((household_id IS NOT NULL) AND (household_id = get_auth_user_household_id()))));
CREATE POLICY "users_update_own_profile" ON public."users" AS PERMISSIVE FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));
CREATE POLICY "receipts_delete_household" ON storage."objects" AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'receipts'::text) AND (auth.uid() IS NOT NULL) AND ((storage.foldername(name))[1] IN ( SELECT (household_memberships.household_id)::text AS household_id
   FROM household_memberships
  WHERE (household_memberships.user_id = auth.uid())
UNION
 SELECT (users.household_id)::text AS household_id
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.household_id IS NOT NULL))))));
CREATE POLICY "receipts_insert_household" ON storage."objects" AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'receipts'::text) AND (auth.uid() IS NOT NULL) AND ((storage.foldername(name))[1] IN ( SELECT (household_memberships.household_id)::text AS household_id
   FROM household_memberships
  WHERE (household_memberships.user_id = auth.uid())
UNION
 SELECT (users.household_id)::text AS household_id
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.household_id IS NOT NULL)))) AND (lower(storage.extension(name)) = ANY (ARRAY['jpg'::text, 'jpeg'::text, 'png'::text, 'webp'::text])) AND (name !~ '\.\.'::text)));
CREATE POLICY "receipts_select_household" ON storage."objects" AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'receipts'::text) AND (auth.uid() IS NOT NULL) AND ((storage.foldername(name))[1] IN ( SELECT (household_memberships.household_id)::text AS household_id
   FROM household_memberships
  WHERE (household_memberships.user_id = auth.uid())
UNION
 SELECT (users.household_id)::text AS household_id
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.household_id IS NOT NULL))))));
CREATE TRIGGER trg_populate_transaction_cycle_key BEFORE INSERT OR UPDATE OF "timestamp", household_id ON public.transactions FOR EACH ROW EXECUTE FUNCTION populate_transaction_cycle_key();

-- 8. Table and column privileges
REVOKE UPDATE ("accumulated_savings") ON public."households" FROM authenticated;
REVOKE UPDATE ("created_at") ON public."households" FROM authenticated;
REVOKE UPDATE ("id") ON public."households" FROM authenticated;
REVOKE UPDATE ("invite_code") ON public."households" FROM authenticated;
REVOKE UPDATE ("last_rollover_cycle") ON public."households" FROM authenticated;
REVOKE UPDATE ("last_rollover_surplus") ON public."households" FROM authenticated;
REVOKE UPDATE ("monthly_income") ON public."households" FROM authenticated;
REVOKE UPDATE ("name") ON public."households" FROM authenticated;
REVOKE UPDATE ("payday_day") ON public."households" FROM authenticated;
REVOKE UPDATE ("rollover_rule") ON public."households" FROM authenticated;
REVOKE ALL ON public."account_transfers" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."account_transfers" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."account_transfers" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."account_transfers" TO service_role;
REVOKE ALL ON public."cost_control_codes" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."cost_control_codes" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."cost_control_codes" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."cost_control_codes" TO service_role;
REVOKE ALL ON public."household_invites" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_invites" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_invites" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_invites" TO service_role;
REVOKE ALL ON public."household_memberships" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_memberships" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_memberships" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_memberships" TO service_role;
REVOKE ALL ON public."households" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."households" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."households" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."households" TO service_role;
REVOKE ALL ON public."income_records" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."income_records" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."income_records" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."income_records" TO service_role;

-- 9. Storage bucket settings
UPDATE storage.buckets SET public = false, file_size_limit = NULL, allowed_mime_types = NULL WHERE id = 'receipts';

COMMIT;
