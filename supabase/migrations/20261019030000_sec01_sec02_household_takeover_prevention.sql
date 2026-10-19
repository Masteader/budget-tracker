-- Migration: 20261019030000_sec01_sec02_household_takeover_prevention.sql
-- Description: SEC-01 & SEC-02 hardening:
-- 1. Tighten public.users RLS policies and revoke column-level UPDATE on role/household_id.
-- 2. Restrict household_invites RLS policies and invite creation to admins.
-- 3. Provide secure SECURITY DEFINER RPCs for household mutations (leave, set_role, remove_member, revoke_invite).
-- 4. Harden invite codes (single-use, expiry, failed-attempt lockout window).
-- 5. Backstop trigger on household_memberships for last-admin protection (BUG-03).
-- 6. Switch {public} role policies to TO authenticated and add explicit WITH CHECK clauses.
-- 7. Revoke EXECUTE grants from anon/PUBLIC on helper RPCs and trigger functions.
-- 8. Fix cost_control_codes leak policy and unique constraint.
-- 9. Prune documented zero-member zero-data orphan households.

BEGIN;

-- ============================================================================
-- 1. USERS TABLE SECURITY & PRIVILEGES
-- ============================================================================

-- Drop insecure update policy
DROP POLICY IF EXISTS users_update_own_or_admin ON public.users;
DROP POLICY IF EXISTS users_update_own_profile ON public.users;

-- Create restricted profile update policy (own row only)
CREATE POLICY users_update_own_profile ON public.users
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Tighten column-level privileges: authenticated clients can only update display_name, payday_day, financial_role
REVOKE UPDATE ON public.users FROM authenticated, anon, public;
GRANT UPDATE (display_name, payday_day, financial_role) ON public.users TO authenticated;

-- Tighten insert policy: client cannot insert with an admin role or foreign household
DROP POLICY IF EXISTS users_insert_own ON public.users;
CREATE POLICY users_insert_own ON public.users
    FOR INSERT
    TO authenticated
    WITH CHECK (id = auth.uid() AND household_id IS NULL AND role = 'member');

-- Tighten users select policy to authenticated only
DROP POLICY IF EXISTS users_select_household ON public.users;
CREATE POLICY users_select_household ON public.users
    FOR SELECT
    TO authenticated
    USING ((id = auth.uid()) OR ((household_id IS NOT NULL) AND (household_id = get_auth_user_household_id())));

-- Enforce financial_role CHECK constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_financial_role_check'
    ) THEN
        ALTER TABLE public.users
        ADD CONSTRAINT users_financial_role_check
        CHECK (financial_role IS NULL OR financial_role = ANY (ARRAY['provider'::text, 'spouse'::text, 'peer'::text, 'family_member'::text, 'dependent'::text]));
    END IF;
END $$;


-- ============================================================================
-- 2. HOUSEHOLD INVITES TABLE SECURITY & RATE LIMITING
-- ============================================================================

-- Ensure columns exist and have sufficient capacity
ALTER TABLE public.household_invites ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.household_invites ADD COLUMN IF NOT EXISTS used_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.household_invites ALTER COLUMN invite_code TYPE text;
ALTER TABLE public.households ALTER COLUMN invite_code TYPE text;

-- Replace open invite select policy with membership-restricted authenticated policy
DROP POLICY IF EXISTS invites_select_household ON public.household_invites;
CREATE POLICY invites_select_household ON public.household_invites
    FOR SELECT
    TO authenticated
    USING (household_id = get_auth_user_household_id());

-- Restrict invite creation to household admins
DROP POLICY IF EXISTS invites_insert_household ON public.household_invites;
CREATE POLICY invites_insert_household ON public.household_invites
    FOR INSERT
    TO authenticated
    WITH CHECK (
        household_id = get_auth_user_household_id()
        AND get_auth_user_role() = 'admin'::text
    );

DROP POLICY IF EXISTS invites_delete_admin ON public.household_invites;
CREATE POLICY invites_delete_admin ON public.household_invites
    FOR DELETE
    TO authenticated
    USING (
        household_id = get_auth_user_household_id()
        AND get_auth_user_role() = 'admin'::text
    );

-- Table for tracking failed invite code join attempts (rate limiting)
CREATE TABLE IF NOT EXISTS public.invite_attempt_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    attempted_at timestamptz NOT NULL DEFAULT now(),
    success boolean NOT NULL DEFAULT false
);

ALTER TABLE public.invite_attempt_log ENABLE ROW LEVEL SECURITY;
-- No client policies on invite_attempt_log


-- ============================================================================
-- 3. SECURITY DEFINER RPCS FOR SAFE HOUSEHOLD MUTATIONS
-- ============================================================================

-- Helper: generate cryptographically secure 16-hex character invite code
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.generate_secure_invite_code()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
    SELECT upper(encode(extensions.gen_random_bytes(8), 'hex'));
$$;

-- Leave household RPC (BUG-01)
CREATE OR REPLACE FUNCTION public.leave_household()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_hh_id uuid;
    v_role text;
    v_other_admins int;
    v_other_members int;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT household_id, role INTO v_hh_id, v_role
    FROM public.users
    WHERE id = v_uid;

    IF v_hh_id IS NULL THEN
        SELECT household_id, role INTO v_hh_id, v_role
        FROM public.household_memberships
        WHERE user_id = v_uid
        LIMIT 1;
    END IF;

    IF v_hh_id IS NULL THEN
        RETURN jsonb_build_object('success', true, 'message', 'User is not in any household');
    END IF;

    -- Last admin check: sole admin cannot leave if other members remain
    SELECT count(*) INTO v_other_admins
    FROM public.household_memberships
    WHERE household_id = v_hh_id AND role = 'admin' AND user_id <> v_uid;

    SELECT count(*) INTO v_other_members
    FROM public.household_memberships
    WHERE household_id = v_hh_id AND user_id <> v_uid;

    IF v_role = 'admin' AND v_other_admins = 0 AND v_other_members > 0 THEN
        RAISE EXCEPTION 'Sole admin cannot leave while other members remain. Promote another member to admin first.';
    END IF;

    -- Delete membership
    DELETE FROM public.household_memberships
    WHERE household_id = v_hh_id AND user_id = v_uid;

    -- Reset active household
    UPDATE public.users
    SET household_id = NULL,
        role = 'member'
    WHERE id = v_uid;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', v_hh_id,
        'message', 'Successfully left household'
    );
END;
$$;

-- Set member role RPC (Admin only)
CREATE OR REPLACE FUNCTION public.set_member_role(p_user_id uuid, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
$$;

-- Remove member RPC (Admin only)
CREATE OR REPLACE FUNCTION public.remove_member(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
$$;

-- Revoke invite RPC (Admin only)
CREATE OR REPLACE FUNCTION public.revoke_invite(p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid uuid := auth.uid();
    v_caller_hh_id uuid;
    v_caller_role text;
    v_invite_id uuid;
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

    DELETE FROM public.household_invites
    WHERE household_id = v_caller_hh_id 
      AND upper(trim(invite_code)) = upper(trim(p_invite_code))
    RETURNING id INTO v_invite_id;

    IF v_invite_id IS NULL THEN
        RAISE EXCEPTION 'Invite code not found in active household';
    END IF;

    RETURN jsonb_build_object('success', true, 'revoked_invite_code', p_invite_code);
END;
$$;

-- Create household and claim RPC (with quota limit of 5 households per user)
CREATE OR REPLACE FUNCTION public.create_household_and_claim(p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_hh public.households%ROWTYPE;
    v_count int;
    v_invite_code text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.household_memberships
    WHERE user_id = v_uid AND role = 'admin';

    IF v_count >= 5 THEN
        RAISE EXCEPTION 'Household creation limit reached (maximum 5 households per user)';
    END IF;

    v_invite_code := upper(encode(extensions.gen_random_bytes(8), 'hex'));

    INSERT INTO public.households (name, invite_code)
    VALUES (trim(p_name), v_invite_code)
    RETURNING * INTO v_hh;

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'admin'
    WHERE id = v_uid;

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_hh.id, v_uid, 'admin', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    RETURN to_jsonb(v_hh);
END;
$$;

-- Join household by code RPC (with single-use, expiry, and rate limiting)
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

        IF v_invite.used_by IS NOT NULL THEN
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has already been used');
        END IF;

        SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

        UPDATE public.household_invites
        SET used_by = v_uid
        WHERE id = v_invite.id AND used_by IS NULL;

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
        ON CONFLICT (household_id, user_id) DO NOTHING;

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    -- 2. Fallback to households.invite_code (legacy static household code)
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


-- ============================================================================
-- 4. BUG-03: LAST-ADMIN PROTECTION BACKSTOP TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_last_admin_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_other_admins int;
    v_other_members int;
BEGIN
    IF OLD.role = 'admin' AND (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW.role <> 'admin')) THEN
        SELECT count(*) INTO v_other_admins
        FROM public.household_memberships
        WHERE household_id = OLD.household_id AND role = 'admin' AND user_id <> OLD.user_id;

        IF v_other_admins = 0 THEN
            IF TG_OP = 'DELETE' THEN
                SELECT count(*) INTO v_other_members
                FROM public.household_memberships
                WHERE household_id = OLD.household_id AND user_id <> OLD.user_id;

                IF v_other_members > 0 THEN
                    RAISE EXCEPTION 'Cannot remove the sole admin while other household members remain';
                END IF;
            ELSE
                RAISE EXCEPTION 'Cannot demote the sole admin of a household';
            END IF;
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_last_admin_demotion ON public.household_memberships;
CREATE TRIGGER trg_prevent_last_admin_demotion
BEFORE UPDATE OF role OR DELETE ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.check_last_admin_membership();


-- ============================================================================
-- 5. COST CONTROL CODES LEAK FIX & UNIQUE CONSTRAINT
-- ============================================================================

-- Drop cross-household category leak policy
DROP POLICY IF EXISTS cost_control_codes_select_authenticated ON public.cost_control_codes;

-- Update cost_control_codes_select policy to authenticated
DROP POLICY IF EXISTS cost_control_codes_select ON public.cost_control_codes;
CREATE POLICY cost_control_codes_select ON public.cost_control_codes
    FOR SELECT
    TO authenticated
    USING ((household_id IS NULL) OR (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid())));

-- Allow households to create custom categories with the same code as other households
ALTER TABLE public.budgets DROP CONSTRAINT IF EXISTS budgets_category_code_fkey;
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_category_code_fkey;
ALTER TABLE public.cost_control_sub_categories DROP CONSTRAINT IF EXISTS cost_control_sub_categories_parent_code_fkey;
ALTER TABLE public.cost_control_sub_categories DROP CONSTRAINT IF EXISTS cost_control_sub_categories_category_code_fkey;
ALTER TABLE public.household_category_settings DROP CONSTRAINT IF EXISTS household_category_settings_category_code_fkey;

ALTER TABLE public.cost_control_codes DROP CONSTRAINT IF EXISTS cost_control_codes_code_key;
DROP INDEX IF EXISTS cost_control_codes_global_code_idx;
DROP INDEX IF EXISTS cost_control_codes_household_code_idx;

CREATE UNIQUE INDEX cost_control_codes_global_code_idx ON public.cost_control_codes (code) WHERE household_id IS NULL;
CREATE UNIQUE INDEX cost_control_codes_household_code_idx ON public.cost_control_codes (household_id, code) WHERE household_id IS NOT NULL;


-- ============================================================================
-- 6. SWITCH POLICIES WITH ROLE {PUBLIC} TO TO AUTHENTICATED & EXPLICIT WITH CHECK
-- ============================================================================

-- budgets
DROP POLICY IF EXISTS budgets_insert_admin ON public.budgets;
CREATE POLICY budgets_insert_admin ON public.budgets
    FOR INSERT
    TO authenticated
    WITH CHECK ((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text));

DROP POLICY IF EXISTS budgets_select_household ON public.budgets;
CREATE POLICY budgets_select_household ON public.budgets
    FOR SELECT
    TO authenticated
    USING (household_id = get_auth_user_household_id());

DROP POLICY IF EXISTS budgets_update_admin ON public.budgets;
CREATE POLICY budgets_update_admin ON public.budgets
    FOR UPDATE
    TO authenticated
    USING ((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text))
    WITH CHECK ((household_id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text));

-- cost_control_sub_categories
DROP POLICY IF EXISTS cost_control_sub_categories_select_all ON public.cost_control_sub_categories;
CREATE POLICY cost_control_sub_categories_select_all ON public.cost_control_sub_categories
    FOR SELECT
    TO authenticated
    USING (true);

-- household_category_settings
DROP POLICY IF EXISTS household_category_settings_all ON public.household_category_settings;
CREATE POLICY household_category_settings_all ON public.household_category_settings
    FOR ALL
    TO authenticated
    USING (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()))
    WITH CHECK (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

-- household_dependents
DROP POLICY IF EXISTS dependents_delete_household ON public.household_dependents;
CREATE POLICY dependents_delete_household ON public.household_dependents
    FOR DELETE
    TO authenticated
    USING (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

DROP POLICY IF EXISTS dependents_insert_household ON public.household_dependents;
CREATE POLICY dependents_insert_household ON public.household_dependents
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

DROP POLICY IF EXISTS dependents_select_household ON public.household_dependents;
CREATE POLICY dependents_select_household ON public.household_dependents
    FOR SELECT
    TO authenticated
    USING (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

DROP POLICY IF EXISTS dependents_update_household ON public.household_dependents;
CREATE POLICY dependents_update_household ON public.household_dependents
    FOR UPDATE
    TO authenticated
    USING (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()))
    WITH CHECK (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

-- household_memberships
DROP POLICY IF EXISTS memberships_view_own ON public.household_memberships;
CREATE POLICY memberships_view_own ON public.household_memberships
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- households
DROP POLICY IF EXISTS households_insert_authenticated ON public.households;
CREATE POLICY households_insert_authenticated ON public.households
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS households_select_own ON public.households;
CREATE POLICY households_select_own ON public.households
    FOR SELECT
    TO authenticated
    USING (id = get_auth_user_household_id());

DROP POLICY IF EXISTS households_update_admin ON public.households;
CREATE POLICY households_update_admin ON public.households
    FOR UPDATE
    TO authenticated
    USING ((id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text))
    WITH CHECK ((id = get_auth_user_household_id()) AND (get_auth_user_role() = 'admin'::text));

-- transactions
DROP POLICY IF EXISTS transactions_delete_household ON public.transactions;
CREATE POLICY transactions_delete_household ON public.transactions
    FOR DELETE
    TO authenticated
    USING (household_id = get_auth_user_household_id());

DROP POLICY IF EXISTS transactions_insert_household ON public.transactions;
CREATE POLICY transactions_insert_household ON public.transactions
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id = get_auth_user_household_id());

DROP POLICY IF EXISTS transactions_update_household ON public.transactions;
CREATE POLICY transactions_update_household ON public.transactions
    FOR UPDATE
    TO authenticated
    USING (household_id = get_auth_user_household_id())
    WITH CHECK (household_id = get_auth_user_household_id());


-- ============================================================================
-- 7. FUNCTION EXECUTION GRANTS CLEANUP
-- ============================================================================

-- Get user households function
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
        h.name AS household_name,
        h.invite_code,
        m.role,
        (h.id = u.household_id) AS is_active
    FROM public.household_memberships m
    JOIN public.households h ON h.id = m.household_id
    JOIN public.users u ON u.id = m.user_id
    WHERE m.user_id = auth.uid()
    ORDER BY is_active DESC, m.created_at ASC;
END;
$$;

-- Switch active household function (harden search_path)
CREATE OR REPLACE FUNCTION public.switch_active_household(p_household_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role TEXT;
    v_name TEXT;
BEGIN
    SELECT role INTO v_role
    FROM public.household_memberships
    WHERE household_id = p_household_id AND user_id = auth.uid();

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: Not a member of household %', p_household_id;
    END IF;

    SELECT name INTO v_name
    FROM public.households
    WHERE id = p_household_id;

    UPDATE public.users
    SET household_id = p_household_id,
        role = v_role
    WHERE id = auth.uid();

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'household_name', v_name,
        'role', v_role
    );
END;
$$;

-- Revoke execute from PUBLIC & anon on RPC helper functions
REVOKE EXECUTE ON FUNCTION public.create_household_and_claim(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.join_household_by_code(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.switch_active_household(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_households() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_household_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_role() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.leave_household() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_member_role(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.remove_member(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.revoke_invite(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.generate_secure_invite_code() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_household_and_claim(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_household_by_code(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.switch_active_household(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_households() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_household_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_household() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_member_role(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_invite(text) TO authenticated;

-- Ensure handle_new_auth_user exists with secure search_path
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.users (id, display_name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
    );
    RETURN NEW;
END;
$$;

-- Revoke execute from all client roles on trigger functions
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_user_household_membership() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_delete() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_budget_on_transaction_update() FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 8. ORPHAN HOUSEHOLDS CLEANUP (0 members, 0 data verified)
-- ============================================================================

DELETE FROM public.households
WHERE id IN (
    '77cf3324-93c7-46d1-8cf1-4b2c6b01c616',
    'f34d3f86-846a-49e6-ac42-49620f1c6dda'
)
AND NOT EXISTS (SELECT 1 FROM public.household_memberships m WHERE m.household_id = households.id)
AND NOT EXISTS (SELECT 1 FROM public.transactions t WHERE t.household_id = households.id)
AND NOT EXISTS (SELECT 1 FROM public.budgets b WHERE b.household_id = households.id)
AND NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.household_id = households.id);

COMMIT;
