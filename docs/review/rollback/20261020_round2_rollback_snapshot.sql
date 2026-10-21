-- ============================================================================
-- Rollback snapshot for the 20261020 round-2 pair
--   20261020700000_fable_db_hardening.sql
--   20261020800000_household_roles_and_nafaqah_integrity.sql
-- Snapshot date: 2026-10-21. Generated from a read-only catalog inventory of the
-- live project taken BEFORE the pair (live then had every migration up to
-- 20261020600000; definitions and privileges only, no row data).
-- See docs/review/audit/live_db_preflight_round2.md.
--
-- Run ONLY to undo BOTH files, in the SQL editor as `postgres`, after review.
-- It returns triggers, policies, constraints, columns, functions (bodies, EXECUTE
-- grants, comments) and table/column privileges to the pre-pair live state,
-- including the PostgreSQL 17 MAINTAIN privilege (granted only on PG17+).
-- Verified on the local live replica (owner = non-superuser BYPASSRLS role):
-- pair -> this script -> catalog identical to live -> pair re-applied -> suite green.
--
-- What it cannot undo / data impact:
--   * it drops household_memberships.financial_role and
--     households.nafaqah_provider_user_id, so per-membership financial roles and
--     Nafaqah providers chosen after the pair are lost (export them first if an
--     admin has used set_nafaqah_provider);
--   * users.financial_role keeps whatever value the new RPCs cached last (it is
--     the pre-pair source of truth again after the rollback);
--   * cycle keys / budgets re-keyed by a payday change made while the pair was
--     live stay re-keyed (the pair itself re-keys nothing at apply time);
--   * invite rows deleted by the new ON DELETE CASCADE (account deletion of a
--     claimer) are not recreated.
-- To undo only 20261020800000, use the commented rollback at the end of that
-- file instead; to undo only 20261020700000, take sections 3 (invite FKs),
-- 5 (reallocate_budget, nafaqah_current_cycle_key, generate_secure_invite_code)
-- and 8 (privileges) of this script.
-- ============================================================================

BEGIN;

-- 0. Refuse to run unless the pair is applied
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'households'
                     AND column_name = 'nafaqah_provider_user_id') THEN
        RAISE EXCEPTION 'rollback: 20261020800000 does not look applied (households.nafaqah_provider_user_id missing); nothing to undo';
    END IF;
END $$;

-- 1. Triggers added or changed by the batch
DROP TRIGGER IF EXISTS "trg_refuse_invite_claim_by_member" ON public.household_invites;
DROP TRIGGER IF EXISTS "trg_clear_nafaqah_provider" ON public.household_memberships;
DROP TRIGGER IF EXISTS "trg_membership_financial_role_cache" ON public.household_memberships;
DROP TRIGGER IF EXISTS "trg_membership_financial_role_rules" ON public.household_memberships;
DROP TRIGGER IF EXISTS "trg_households_nafaqah_provider" ON public.households;
DROP TRIGGER IF EXISTS "trg_rekey_cycles_on_payday_change" ON public.households;
DROP TRIGGER IF EXISTS "trg_wife_ledger_guard" ON public.transactions;

-- 2. Policies added or changed by the batch
DROP POLICY IF EXISTS "invites_select_admin" ON public."household_invites";

-- 3. Constraints and indexes added by the batch
ALTER TABLE public."household_invites" DROP CONSTRAINT IF EXISTS "household_invites_created_by_fkey";
ALTER TABLE public."household_invites" DROP CONSTRAINT IF EXISTS "household_invites_used_by_fkey";
ALTER TABLE public."household_memberships" DROP CONSTRAINT IF EXISTS "household_memberships_financial_role_check";
ALTER TABLE public."households" DROP CONSTRAINT IF EXISTS "households_nafaqah_provider_user_id_fkey";
DROP INDEX IF EXISTS public."idx_households_nafaqah_provider";

-- 4. Tables and columns added by the batch (drops only data created after the batch)
ALTER TABLE public."household_memberships" DROP COLUMN IF EXISTS "financial_role";
ALTER TABLE public."households" DROP COLUMN IF EXISTS "nafaqah_provider_user_id";

-- 5. Functions: drop the ones the batch added, restore the pre-batch definitions
DROP FUNCTION IF EXISTS public."clear_nafaqah_provider_on_membership_end"();
DROP FUNCTION IF EXISTS public."guard_wife_reimbursable_ledger"();
DROP FUNCTION IF EXISTS public."household_default_financial_role"(p_household_id uuid, p_user_id uuid);
DROP FUNCTION IF EXISTS public."household_member_financial_role"(p_household_id uuid, p_user_id uuid);
DROP FUNCTION IF EXISTS public."households_nafaqah_provider_rules"();
DROP FUNCTION IF EXISTS public."membership_financial_role_cache"();
DROP FUNCTION IF EXISTS public."membership_financial_role_rules"();
DROP FUNCTION IF EXISTS public."recompute_budget_spent"(p_household_id uuid, p_cycle_keys text[]);
DROP FUNCTION IF EXISTS public."refuse_invite_claim_by_member"();
DROP FUNCTION IF EXISTS public."rekey_cycles_on_payday_change"();
DROP FUNCTION IF EXISTS public."rekey_household_cycles"(p_household_id uuid, p_old_payday integer, p_new_payday integer, p_as_of timestamp with time zone);
DROP FUNCTION IF EXISTS public."set_nafaqah_provider"(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid);
CREATE OR REPLACE FUNCTION public.claim_household_role_invite(p_invite_code text, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_uid uuid;
    v_clean_code text := upper(trim(p_invite_code));
    v_fail_count int;
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

    SELECT count(*) INTO v_fail_count
    FROM public.invite_attempt_log
    WHERE user_id = v_uid
      AND success = false
      AND attempted_at > (now() - interval '15 minutes');

    IF v_fail_count >= 5 THEN
        RAISE EXCEPTION 'Too many failed join attempts. Please try again in 15 minutes.';
    END IF;

    UPDATE public.household_invites
    SET used_by = v_uid
    WHERE upper(trim(invite_code)) = v_clean_code
      AND used_by IS NULL
      AND expires_at > now()
    RETURNING * INTO v_invite;

    IF v_invite.id IS NULL THEN
        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
    END IF;

    SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

    IF v_invite.target_member_id IS NOT NULL THEN
        UPDATE public.household_dependents
        SET linked_user_id = v_uid
        WHERE id = v_invite.target_member_id
          AND household_id = v_invite.household_id;
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

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);

    RETURN jsonb_build_object(
        'success', true,
        'household_id', v_hh.id,
        'household_name', v_hh.name,
        'role', v_invite.role,
        'target_member_id', v_invite.target_member_id
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_household_and_claim(p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_household_members(p_household_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(user_id uuid, display_name text, role text, financial_role text, is_primary boolean, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
BEGIN
    IF p_household_id IS NULL OR public.household_member_role(p_household_id, v_actor) IS NULL THEN
        RAISE EXCEPTION 'Forbidden: not a member of this household' USING ERRCODE = '42501';
    END IF;
    v_owner := public.household_primary_admin_id(p_household_id);

    RETURN QUERY
    SELECT m.user_id,
           u.display_name,
           m.role,
           u.financial_role,
           (m.user_id = v_owner) AS is_primary,
           m.created_at AS joined_at
    FROM public.household_memberships m
    JOIN public.users u ON u.id = m.user_id
    WHERE m.household_id = p_household_id
    ORDER BY (m.user_id = v_owner) DESC, (m.role = 'admin') DESC, m.created_at ASC, m.user_id ASC;
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

    SELECT count(*) INTO v_fail_count
    FROM public.invite_attempt_log
    WHERE user_id = v_uid
      AND success = false
      AND attempted_at > (now() - interval '15 minutes');

    IF v_fail_count >= 5 THEN
        RAISE EXCEPTION 'Too many failed join attempts. Please try again in 15 minutes.';
    END IF;

    SELECT * INTO v_invite
    FROM public.household_invites
    WHERE upper(trim(invite_code)) = v_clean_code;

    IF v_invite.id IS NOT NULL THEN
        IF v_invite.expires_at < now() THEN
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has expired');
        END IF;

        IF v_invite.used_by = v_uid THEN
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
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has already been used');
        END IF;

        SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

        IF v_invite.target_member_id IS NOT NULL THEN
            UPDATE public.household_dependents
            SET linked_user_id = v_uid
            WHERE id = v_invite.target_member_id
              AND household_id = v_invite.household_id;
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

CREATE OR REPLACE FUNCTION public.nafaqah_husband_id(p_household_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT m.user_id
    FROM public.household_memberships m
    JOIN public.users u ON u.id = m.user_id
    JOIN public.households h ON h.id = m.household_id
    WHERE m.household_id = p_household_id
      AND COALESCE(u.financial_role, 'provider') = 'provider'
      AND EXISTS (
          SELECT 1
          FROM public.household_memberships sm
          JOIN public.users su ON su.id = sm.user_id
          WHERE sm.household_id = p_household_id AND su.financial_role = 'spouse'
      )
    ORDER BY (m.user_id = h.owner_user_id) DESC NULLS LAST, (m.role = 'admin') DESC, m.created_at, m.user_id
    LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.nafaqah_is_spouse_member(p_household_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        JOIN public.users u ON u.id = m.user_id
        WHERE m.household_id = p_household_id
          AND m.user_id = p_user_id
          AND u.financial_role = 'spouse'
    );
$function$;

CREATE OR REPLACE FUNCTION public.reallocate_budget(p_from_id uuid, p_to_id uuid, p_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_jwt_role text := auth.role();
    v_from public.budgets%ROWTYPE;
    v_to public.budgets%ROWTYPE;
BEGIN
    IF v_uid IS NULL AND v_jwt_role IS DISTINCT FROM 'service_role' AND v_jwt_role IS NOT NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_from_id IS NULL OR p_to_id IS NULL OR p_from_id = p_to_id THEN
        RAISE EXCEPTION 'Two distinct budget ids are required' USING ERRCODE = '22023';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Reallocation amount must be positive with at most 2 decimals' USING ERRCODE = '22023';
    END IF;

    IF p_from_id < p_to_id THEN
        SELECT * INTO v_from FROM public.budgets WHERE id = p_from_id FOR UPDATE;
        SELECT * INTO v_to FROM public.budgets WHERE id = p_to_id FOR UPDATE;
    ELSE
        SELECT * INTO v_to FROM public.budgets WHERE id = p_to_id FOR UPDATE;
        SELECT * INTO v_from FROM public.budgets WHERE id = p_from_id FOR UPDATE;
    END IF;

    IF v_from.id IS NULL OR v_to.id IS NULL THEN
        RAISE EXCEPTION 'Budget not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_from.household_id IS DISTINCT FROM v_to.household_id THEN
        RAISE EXCEPTION 'Budgets belong to different households' USING ERRCODE = '42501';
    END IF;

    IF v_uid IS NOT NULL THEN
        IF public.get_auth_user_household_id() IS DISTINCT FROM v_from.household_id
           OR public.get_auth_user_role() IS DISTINCT FROM 'admin' THEN
            RAISE EXCEPTION 'Access denied: household admin required' USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_from.allocated_amount < p_amount THEN
        RAISE EXCEPTION 'Insufficient allocation: % available, % requested', v_from.allocated_amount, p_amount
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount - p_amount
    WHERE id = v_from.id;

    UPDATE public.budgets
    SET allocated_amount = allocated_amount + p_amount
    WHERE id = v_to.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.switch_active_household(p_household_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.sync_user_household_membership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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

CREATE OR REPLACE FUNCTION public.transfer_primary_admin(p_household_id uuid, p_new_primary_user_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
    v_target_role text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT owner_user_id INTO v_owner
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF v_owner IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'Forbidden: only the primary admin can transfer primary admin' USING ERRCODE = '42501';
    END IF;

    IF p_new_primary_user_id IS NULL OR p_new_primary_user_id = v_actor THEN
        RAISE EXCEPTION 'Choose another member of this household' USING ERRCODE = '22023';
    END IF;

    v_target_role := public.household_member_role(p_household_id, p_new_primary_user_id);
    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;

    IF v_target_role <> 'admin' THEN
        PERFORM public.household_apply_role(p_household_id, p_new_primary_user_id, 'admin');
    END IF;

    UPDATE public.households
    SET owner_user_id = p_new_primary_user_id
    WHERE id = p_household_id;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'primary_admin_user_id', p_new_primary_user_id,
        'previous_primary_admin_user_id', v_actor
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    UPDATE public.budgets
    SET spent_amount = spent_amount + NEW.amount
    WHERE household_id  = NEW.household_id
      AND category_code = NEW.category_code
      AND (
          (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
          OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
      );

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    UPDATE public.budgets
    SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
    WHERE household_id  = OLD.household_id
      AND category_code = OLD.category_code
      AND (
          (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
          OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
      );

    RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_budget_on_transaction_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.validate_transaction_nafaqah_class()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    -- ON DELETE SET NULL of the spouse's account: keep the expense, drop the class.
    IF TG_OP = 'UPDATE' AND NEW.nafaqah_spouse_id IS NULL AND OLD.nafaqah_spouse_id IS NOT NULL
       AND NEW.nafaqah_class IS NOT DISTINCT FROM OLD.nafaqah_class THEN
        NEW.nafaqah_class := NULL;
        RETURN NEW;
    END IF;

    IF NEW.nafaqah_class IS NULL AND NEW.nafaqah_spouse_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.nafaqah_class IS NULL OR NEW.nafaqah_spouse_id IS NULL THEN
        RAISE EXCEPTION 'nafaqah_class and nafaqah_spouse_id must be set together'
            USING ERRCODE = '23514';
    END IF;

    IF NOT public.nafaqah_is_spouse_member(NEW.household_id, NEW.nafaqah_spouse_id) THEN
        RAISE EXCEPTION 'nafaqah_spouse_id % is not a spouse member of household %', NEW.nafaqah_spouse_id, NEW.household_id
            USING ERRCODE = '23503';
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public."claim_household_role_invite"(p_invite_code text, p_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."claim_household_role_invite"(p_invite_code text, p_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."claim_household_role_invite"(p_invite_code text, p_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."create_household_and_claim"(p_name text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."create_household_and_claim"(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."create_household_and_claim"(p_name text) TO service_role;
REVOKE ALL ON FUNCTION public."generate_secure_invite_code"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."generate_secure_invite_code"() TO authenticated;
GRANT EXECUTE ON FUNCTION public."generate_secure_invite_code"() TO service_role;
REVOKE ALL ON FUNCTION public."get_household_members"(p_household_id uuid, p_actor_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."get_household_members"(p_household_id uuid, p_actor_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."get_household_members"(p_household_id uuid, p_actor_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."join_household_by_code"(p_invite_code text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."join_household_by_code"(p_invite_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."join_household_by_code"(p_invite_code text) TO service_role;
REVOKE ALL ON FUNCTION public."nafaqah_current_cycle_key"(p_household_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."nafaqah_current_cycle_key"(p_household_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."nafaqah_current_cycle_key"(p_household_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."nafaqah_husband_id"(p_household_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."nafaqah_husband_id"(p_household_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."nafaqah_is_spouse_member"(p_household_id uuid, p_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."nafaqah_is_spouse_member"(p_household_id uuid, p_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."reallocate_budget"(p_from_id uuid, p_to_id uuid, p_amount numeric) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."reallocate_budget"(p_from_id uuid, p_to_id uuid, p_amount numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public."reallocate_budget"(p_from_id uuid, p_to_id uuid, p_amount numeric) TO service_role;
REVOKE ALL ON FUNCTION public."switch_active_household"(p_household_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."switch_active_household"(p_household_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."switch_active_household"(p_household_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."sync_user_household_membership"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."sync_user_household_membership"() TO service_role;
REVOKE ALL ON FUNCTION public."transfer_primary_admin"(p_household_id uuid, p_new_primary_user_id uuid, p_actor_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."transfer_primary_admin"(p_household_id uuid, p_new_primary_user_id uuid, p_actor_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."transfer_primary_admin"(p_household_id uuid, p_new_primary_user_id uuid, p_actor_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."update_budget_on_transaction"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."update_budget_on_transaction"() TO service_role;
REVOKE ALL ON FUNCTION public."update_budget_on_transaction_delete"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."update_budget_on_transaction_delete"() TO service_role;
REVOKE ALL ON FUNCTION public."update_budget_on_transaction_update"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."update_budget_on_transaction_update"() TO service_role;
REVOKE ALL ON FUNCTION public."validate_transaction_nafaqah_class"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."validate_transaction_nafaqah_class"() TO service_role;

-- 6. Column defaults, comments, RLS flags
ALTER TABLE public."household_invites" ADD CONSTRAINT "household_invites_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(id);
ALTER TABLE public."household_invites" ADD CONSTRAINT "household_invites_used_by_fkey" FOREIGN KEY (used_by) REFERENCES users(id);

-- 7. Pre-batch policies and triggers
CREATE POLICY "invites_select_household" ON public."household_invites" AS PERMISSIVE FOR SELECT TO authenticated USING ((household_id = ( SELECT get_auth_user_household_id() AS get_auth_user_household_id)));

-- 8. Table and column privileges
REVOKE INSERT,UPDATE ("avatar_icon") ON public."household_dependents" FROM authenticated;
REVOKE INSERT ("created_at") ON public."household_dependents" FROM authenticated;
REVOKE INSERT ("household_id") ON public."household_dependents" FROM authenticated;
REVOKE INSERT ("id") ON public."household_dependents" FROM authenticated;
REVOKE INSERT,UPDATE ("monthly_allowance") ON public."household_dependents" FROM authenticated;
REVOKE INSERT,UPDATE ("name") ON public."household_dependents" FROM authenticated;
REVOKE INSERT,UPDATE ("relationship") ON public."household_dependents" FROM authenticated;
REVOKE INSERT ("created_at") ON public."users" FROM authenticated;
REVOKE INSERT ("household_id") ON public."users" FROM authenticated;
REVOKE INSERT ("id") ON public."users" FROM authenticated;
REVOKE INSERT ("role") ON public."users" FROM authenticated;
REVOKE ALL ON public."account_transfers" FROM PUBLIC, anon, authenticated, service_role;
GRANT REFERENCES, SELECT, TRIGGER ON public."account_transfers" TO anon;
GRANT REFERENCES, SELECT, TRIGGER ON public."account_transfers" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."account_transfers" TO service_role;
REVOKE ALL ON public."accounts" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE ON public."accounts" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE ON public."accounts" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."accounts" TO service_role;
GRANT UPDATE ("account_type") ON public."accounts" TO authenticated;
GRANT UPDATE ("color_hex") ON public."accounts" TO authenticated;
GRANT UPDATE ("currency") ON public."accounts" TO authenticated;
GRANT UPDATE ("icon_name") ON public."accounts" TO authenticated;
GRANT UPDATE ("is_archived") ON public."accounts" TO authenticated;
GRANT UPDATE ("name") ON public."accounts" TO authenticated;
GRANT UPDATE ("updated_at") ON public."accounts" TO authenticated;
REVOKE ALL ON public."budgets" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."budgets" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."budgets" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."budgets" TO service_role;
REVOKE ALL ON public."budgets_spent_backup_20261019" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."budgets_spent_backup_20261019" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."budgets_spent_backup_20261019" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."budgets_spent_backup_20261019" TO service_role;
REVOKE ALL ON public."cost_control_codes" FROM PUBLIC, anon, authenticated, service_role;
GRANT INSERT, REFERENCES, SELECT, TRIGGER, UPDATE ON public."cost_control_codes" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."cost_control_codes" TO service_role;
REVOKE ALL ON public."household_category_settings" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_category_settings" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_category_settings" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_category_settings" TO service_role;
REVOKE ALL ON public."household_dependents" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_dependents" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_dependents" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_dependents" TO service_role;
REVOKE ALL ON public."household_invites" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_invites" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_invites" TO service_role;
REVOKE ALL ON public."household_memberships" FROM PUBLIC, anon, authenticated, service_role;
GRANT REFERENCES, SELECT, TRIGGER ON public."household_memberships" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."household_memberships" TO service_role;
REVOKE ALL ON public."households" FROM PUBLIC, anon, authenticated, service_role;
GRANT REFERENCES, SELECT, TRIGGER ON public."households" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."households" TO service_role;
GRANT UPDATE ("accumulated_savings") ON public."households" TO authenticated;
GRANT UPDATE ("created_at") ON public."households" TO authenticated;
GRANT UPDATE ("id") ON public."households" TO authenticated;
GRANT UPDATE ("invite_code") ON public."households" TO authenticated;
GRANT UPDATE ("last_rollover_cycle") ON public."households" TO authenticated;
GRANT UPDATE ("last_rollover_surplus") ON public."households" TO authenticated;
GRANT UPDATE ("monthly_income") ON public."households" TO authenticated;
GRANT UPDATE ("name") ON public."households" TO authenticated;
GRANT UPDATE ("payday_day") ON public."households" TO authenticated;
GRANT UPDATE ("rollover_rule") ON public."households" TO authenticated;
REVOKE ALL ON public."income_records" FROM PUBLIC, anon, authenticated, service_role;
GRANT REFERENCES, SELECT, TRIGGER ON public."income_records" TO anon;
GRANT REFERENCES, SELECT, TRIGGER ON public."income_records" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."income_records" TO service_role;
REVOKE ALL ON public."installment_plans" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."installment_plans" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."installment_plans" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."installment_plans" TO service_role;
REVOKE ALL ON public."invite_attempt_log" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."invite_attempt_log" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."invite_attempt_log" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."invite_attempt_log" TO service_role;
REVOKE ALL ON public."transactions" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."transactions" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."transactions" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."transactions" TO service_role;
REVOKE ALL ON public."users" FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE ON public."users" TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE ON public."users" TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public."users" TO service_role;
GRANT UPDATE ("display_name") ON public."users" TO authenticated;
GRANT UPDATE ("payday_day") ON public."users" TO authenticated;
DO $$
BEGIN
    IF current_setting('server_version_num')::int >= 170000 THEN
        EXECUTE 'GRANT MAINTAIN ON public."account_transfers" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."account_transfers" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."account_transfers" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."accounts" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."accounts" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."accounts" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."budgets" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."budgets" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."budgets" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."budgets_spent_backup_20261019" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."budgets_spent_backup_20261019" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."budgets_spent_backup_20261019" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."cost_control_codes" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."cost_control_codes" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."household_category_settings" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."household_category_settings" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."household_category_settings" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."household_dependents" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."household_dependents" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."household_dependents" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."household_invites" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."household_invites" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."household_memberships" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."household_memberships" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."households" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."households" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."income_records" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."income_records" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."income_records" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."installment_plans" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."installment_plans" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."installment_plans" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."invite_attempt_log" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."invite_attempt_log" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."invite_attempt_log" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."transactions" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."transactions" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."transactions" TO service_role';
        EXECUTE 'GRANT MAINTAIN ON public."users" TO anon';
        EXECUTE 'GRANT MAINTAIN ON public."users" TO authenticated';
        EXECUTE 'GRANT MAINTAIN ON public."users" TO service_role';
    END IF;
END $$;

-- 9. Storage bucket settings

-- 10. Function comment changed by 20261020800000
COMMENT ON FUNCTION public.nafaqah_husband_id(uuid) IS 'Internal: Nafaqah provider of a family household. Not client-callable (E2E-04); used by SECURITY DEFINER functions.';

COMMIT;
