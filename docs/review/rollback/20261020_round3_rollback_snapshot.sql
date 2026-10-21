-- ============================================================================
-- Rollback snapshot for 20261020900000_household_type_and_round2_fixes.sql
-- Snapshot date: 2026-10-21. Generated from catalog inventories of a local
-- database rebuilt from the repository up to 20261020800000 (the state live will
-- have once 20261020700000 / 750000 / 800000 are applied) and the same database
-- after 20261020900000; definitions and privileges only, no row data.
--
-- Run ONLY to undo 20261020900000, in the SQL editor as `postgres`, after review.
-- It drops the household_type column and the new functions/trigger, restores the
-- 20261020800000 definitions (claim / join / create RPCs, provider rules, ledger
-- guard, budget triggers, pay_installment_plan, ...), the households provider
-- trigger, the installment_plans UPDATE grant, and removes the paid_installments
-- CHECK. Verified locally: 900000 -> this script -> catalog identical to the
-- pre-900000 state -> 900000 re-applied -> DB suite green (also on a database
-- the test suite had already run on).
--
-- What it cannot undo / data impact:
--   * households.household_type is dropped: the chosen types are lost (export
--     them first if admins have used set_household_type);
--   * membership financial roles changed by set_household_type /
--     set_member_financial_role stay as they are (valid 800000 values);
--   * D3 removals are permanent: wife ledgers (spouse_reimbursements,
--     member_allowances) deleted when a wife's membership ended, and the
--     classification cleared on her expenses, are not recreated;
--   * a provider left NULL after owner succession stays NULL (an admin can set it).
-- To undo the round-2 files as well, run this first, then
-- 20261020_round2_rollback_snapshot.sql.
-- ============================================================================

BEGIN;

-- 0. Refuse to run unless 20261020900000 is applied
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'households'
                     AND column_name = 'household_type') THEN
        RAISE EXCEPTION 'rollback: 20261020900000 does not look applied (households.household_type missing); nothing to undo';
    END IF;
END $$;

-- 1. Triggers added or changed by the batch
DROP TRIGGER IF EXISTS "trg_remove_nafaqah_ledger_on_membership_end" ON public.household_memberships;
DROP TRIGGER IF EXISTS "trg_households_nafaqah_provider" ON public.households;

-- 2. Policies added or changed by the batch

-- 3. Constraints and indexes added by the batch
ALTER TABLE public."households" DROP CONSTRAINT IF EXISTS "households_household_type_check";
ALTER TABLE public."installment_plans" DROP CONSTRAINT IF EXISTS "installment_plans_paid_installments_range";

-- 4. Tables and columns added by the batch (drops only data created after the batch)
ALTER TABLE public."households" DROP COLUMN IF EXISTS "household_type";

-- 5. Functions: drop the ones the batch added, restore the pre-batch definitions
DROP FUNCTION IF EXISTS public."create_household_and_claim"(p_name text, p_household_type text);
DROP FUNCTION IF EXISTS public."household_financial_role_allowed"(p_household_type text, p_financial_role text);
DROP FUNCTION IF EXISTS public."remove_nafaqah_ledger_on_membership_end"();
DROP FUNCTION IF EXISTS public."set_household_type"(p_household_id uuid, p_household_type text, p_actor_user_id uuid);
DROP FUNCTION IF EXISTS public."set_member_financial_role"(p_household_id uuid, p_user_id uuid, p_financial_role text, p_actor_user_id uuid);
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
    v_role text;
    v_financial_role text;
    v_is_default boolean;
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

    SELECT * INTO v_invite
    FROM public.household_invites
    WHERE upper(trim(invite_code)) = v_clean_code
      AND expires_at > now()
    FOR UPDATE;

    IF v_invite.id IS NULL OR (v_invite.used_by IS NOT NULL AND v_invite.used_by IS DISTINCT FROM v_uid) THEN
        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
    END IF;

    SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;

    SELECT role, financial_role INTO v_role, v_financial_role
    FROM public.household_memberships
    WHERE household_id = v_invite.household_id AND user_id = v_uid;

    IF v_role IS NOT NULL THEN
        IF v_invite.used_by IS DISTINCT FROM v_uid THEN
            -- FABLE-DB-01: a member cannot take the spouse/provider invite meant for
            -- someone else; the invite stays open for the real invitee.
            RETURN jsonb_build_object('success', false, 'error', 'You are already a member of this household',
                                      'code', 'already_member');
        END IF;
        -- Idempotent retry by the claimer: nothing changes.
        RETURN jsonb_build_object(
            'success', true,
            'household_id', v_hh.id,
            'household_name', v_hh.name,
            'role', v_financial_role,
            'target_member_id', v_invite.target_member_id
        );
    END IF;

    IF v_invite.used_by IS NOT NULL THEN
        -- Used by this user, who has since left: same answer as any used invite.
        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
        RETURN jsonb_build_object('success', false, 'error', 'Invalid, expired, or already used invite code');
    END IF;

    UPDATE public.household_invites SET used_by = v_uid WHERE id = v_invite.id;

    IF v_invite.target_member_id IS NOT NULL THEN
        UPDATE public.household_dependents
        SET linked_user_id = v_uid
        WHERE id = v_invite.target_member_id
          AND household_id = v_invite.household_id;
    END IF;

    v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
    VALUES (
        v_hh.id, v_uid, 'member', v_is_default,
        CASE WHEN v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent')
             THEN v_invite.role
             ELSE public.household_default_financial_role(v_hh.id, v_uid) END
    )
    ON CONFLICT (household_id, user_id) DO NOTHING;

    SELECT role, financial_role INTO v_role, v_financial_role
    FROM public.household_memberships
    WHERE household_id = v_hh.id AND user_id = v_uid;

    UPDATE public.users
    SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
    WHERE id = v_uid;

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);

    RETURN jsonb_build_object(
        'success', true,
        'household_id', v_hh.id,
        'household_name', v_hh.name,
        'role', v_financial_role,
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

    -- Membership first: it makes the creator the primary admin, which makes
    -- them the default Nafaqah provider.
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
    VALUES (v_hh.id, v_uid, 'admin', true, 'provider')
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'admin',
        financial_role = 'provider'
    WHERE id = v_uid;

    SELECT * INTO v_hh FROM public.households WHERE id = v_hh.id;
    RETURN to_jsonb(v_hh);
END;
$function$;

CREATE OR REPLACE FUNCTION public.guard_wife_reimbursable_ledger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_kept numeric(14, 2) := 0;
    v_advanced numeric(14, 2);
    v_repaid numeric(14, 2);
    v_after numeric(14, 2);
BEGIN
    IF pg_trigger_depth() > 1 THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF OLD.nafaqah_class IS DISTINCT FROM 'wife_reimbursable' OR OLD.nafaqah_spouse_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_reimbursable'
       AND NEW.nafaqah_spouse_id IS NOT DISTINCT FROM OLD.nafaqah_spouse_id
       AND NEW.household_id IS NOT DISTINCT FROM OLD.household_id THEN
        v_kept := COALESCE(NEW.amount, 0);
    END IF;

    IF v_kept >= COALESCE(OLD.amount, 0) THEN
        RETURN COALESCE(NEW, OLD);  -- the advance does not shrink
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(
        'spouse_reimbursement:' || OLD.household_id::text || ':' || OLD.nafaqah_spouse_id::text, 0));

    SELECT COALESCE(sum(t.amount), 0) INTO v_advanced
    FROM public.transactions t
    WHERE t.household_id = OLD.household_id
      AND t.nafaqah_spouse_id = OLD.nafaqah_spouse_id
      AND t.nafaqah_class = 'wife_reimbursable';

    SELECT COALESCE(sum(r.amount), 0) INTO v_repaid
    FROM public.spouse_reimbursements r
    WHERE r.household_id = OLD.household_id AND r.wife_user_id = OLD.nafaqah_spouse_id;

    v_after := v_advanced - COALESCE(OLD.amount, 0) + v_kept;
    IF v_after < v_repaid THEN
        RAISE EXCEPTION 'This change would leave the wife''s reimbursement ledger overpaid: % SAR already repaid, only % SAR of advances would remain', v_repaid, v_after
            USING ERRCODE = '22023',
                  HINT = 'ledger_would_be_overpaid',
                  DETAIL = format('repaid=%s advances_after=%s', v_repaid, v_after);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.household_default_financial_role(p_household_id uuid, p_user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT CASE
        WHEN (SELECT h.owner_user_id FROM public.households h WHERE h.id = p_household_id) = p_user_id
             OR NOT EXISTS (SELECT 1 FROM public.household_memberships o
                            WHERE o.household_id = p_household_id AND o.user_id <> p_user_id)
            THEN 'provider'
        WHEN EXISTS (SELECT 1 FROM public.household_memberships o
                     WHERE o.household_id = p_household_id AND o.user_id <> p_user_id AND o.financial_role = 'spouse')
            THEN 'family_member'
        WHEN EXISTS (SELECT 1 FROM public.household_memberships o
                     WHERE o.household_id = p_household_id AND o.user_id <> p_user_id AND o.financial_role = 'peer')
            THEN 'peer'
        ELSE 'family_member'
    END;
$function$;

CREATE OR REPLACE FUNCTION public.households_nafaqah_provider_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_role text;
BEGIN
    IF NEW.nafaqah_provider_user_id IS NULL
       AND NEW.owner_user_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR OLD.owner_user_id IS NULL) THEN
        v_role := public.household_member_financial_role(NEW.id, NEW.owner_user_id);
        IF v_role IS NOT NULL AND v_role <> 'spouse' THEN
            NEW.nafaqah_provider_user_id := NEW.owner_user_id;
        END IF;
    END IF;

    IF NEW.nafaqah_provider_user_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.nafaqah_provider_user_id IS DISTINCT FROM OLD.nafaqah_provider_user_id) THEN
        v_role := public.household_member_financial_role(NEW.id, NEW.nafaqah_provider_user_id);
        IF v_role IS NULL THEN
            RAISE EXCEPTION 'The Nafaqah provider must be a member of the household'
                USING ERRCODE = '23514', HINT = 'provider_not_member';
        END IF;
        IF v_role = 'spouse' THEN
            RAISE EXCEPTION 'A spouse member cannot be the Nafaqah provider'
                USING ERRCODE = '23514', HINT = 'provider_is_spouse';
        END IF;
    END IF;
    RETURN NEW;
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
    v_role text;
    v_financial_role text;
    v_is_default boolean;
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
    WHERE upper(trim(invite_code)) = v_clean_code
    FOR UPDATE;

    IF v_invite.id IS NOT NULL THEN
        IF v_invite.expires_at < now() THEN
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
            RETURN jsonb_build_object('success', false, 'error', 'Invite code has expired');
        END IF;

        SELECT role, financial_role INTO v_role, v_financial_role
        FROM public.household_memberships
        WHERE household_id = v_invite.household_id AND user_id = v_uid;

        IF v_role IS NOT NULL THEN
            IF v_invite.used_by IS DISTINCT FROM v_uid THEN
                -- An existing member never consumes an invite meant for someone else
                -- (and never re-roles themselves through it).
                RETURN jsonb_build_object('success', false, 'error', 'You are already a member of this household',
                                          'code', 'already_member');
            END IF;
            -- Retry by the claimer: switch to the household, nothing else changes.
            SELECT * INTO v_hh FROM public.households WHERE id = v_invite.household_id;
            UPDATE public.users
            SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
            WHERE id = v_uid;
            INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
            RETURN to_jsonb(v_hh);
        END IF;

        IF v_invite.used_by = v_uid THEN
            v_claimed_id := v_invite.id;  -- re-joining with the invite this user claimed earlier
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

        v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
        VALUES (
            v_hh.id, v_uid, 'member', v_is_default,
            CASE WHEN v_invite.role IN ('provider', 'spouse', 'peer', 'family_member', 'dependent')
                 THEN v_invite.role
                 ELSE public.household_default_financial_role(v_hh.id, v_uid) END
        )
        ON CONFLICT (household_id, user_id) DO NOTHING;

        SELECT role, financial_role INTO v_role, v_financial_role
        FROM public.household_memberships
        WHERE household_id = v_hh.id AND user_id = v_uid;

        UPDATE public.users
        SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
        WHERE id = v_uid;

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    -- The household's permanent join code.
    SELECT * INTO v_hh
    FROM public.households
    WHERE upper(trim(invite_code)) = v_clean_code;

    IF v_hh.id IS NOT NULL THEN
        v_is_default := NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = v_uid);
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role)
        VALUES (v_hh.id, v_uid, 'member', v_is_default, public.household_default_financial_role(v_hh.id, v_uid))
        ON CONFLICT (household_id, user_id) DO NOTHING;

        -- Existing members keep their role and financial role (never demoted).
        SELECT role, financial_role INTO v_role, v_financial_role
        FROM public.household_memberships
        WHERE household_id = v_hh.id AND user_id = v_uid;

        UPDATE public.users
        SET household_id = v_hh.id, role = v_role, financial_role = v_financial_role
        WHERE id = v_uid;

        INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, true);
        RETURN to_jsonb(v_hh);
    END IF;

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (v_uid, false);
    RETURN jsonb_build_object('success', false, 'error', 'Invalid invite code');
END;
$function$;

CREATE OR REPLACE FUNCTION public.maintain_household_primary_admin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.households h
        SET owner_user_id = (
            SELECT m.user_id
            FROM public.household_memberships m
            WHERE m.household_id = OLD.household_id
              AND m.user_id <> OLD.user_id
              AND m.role = 'admin'
            ORDER BY m.created_at ASC, m.user_id ASC
            LIMIT 1
        )
        WHERE h.id = OLD.household_id
          AND (h.owner_user_id IS NULL OR h.owner_user_id = OLD.user_id);
        RETURN OLD;
    END IF;

    IF NEW.role = 'admin' THEN
        UPDATE public.households
        SET owner_user_id = NEW.user_id
        WHERE id = NEW.household_id AND owner_user_id IS NULL;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.membership_financial_role_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.financial_role IS NULL THEN
        NEW.financial_role := public.household_default_financial_role(NEW.household_id, NEW.user_id);
    END IF;
    IF NEW.financial_role = 'spouse'
       AND (TG_OP = 'INSERT' OR OLD.financial_role IS DISTINCT FROM 'spouse')
       AND EXISTS (SELECT 1 FROM public.households h
                   WHERE h.id = NEW.household_id AND h.nafaqah_provider_user_id = NEW.user_id) THEN
        RAISE EXCEPTION 'The Nafaqah provider of a household cannot be a spouse member'
            USING ERRCODE = '23514', HINT = 'provider_is_spouse';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nafaqah_husband_id(p_household_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT h.nafaqah_provider_user_id
    FROM public.households h
    WHERE h.id = p_household_id
      AND EXISTS (SELECT 1 FROM public.household_memberships sm
                  WHERE sm.household_id = h.id AND sm.financial_role = 'spouse')
      AND EXISTS (SELECT 1 FROM public.household_memberships pm
                  WHERE pm.household_id = h.id
                    AND pm.user_id = h.nafaqah_provider_user_id
                    AND pm.financial_role <> 'spouse');
$function$;

CREATE OR REPLACE FUNCTION public.pay_installment_plan(p_plan_id uuid, p_household_id uuid, p_actor_user_id uuid)
 RETURNS SETOF installment_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_row public.installment_plans;
BEGIN
    IF p_plan_id IS NULL OR p_household_id IS NULL OR p_actor_user_id IS NULL THEN
        RAISE EXCEPTION 'plan, household and actor are required' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        WHERE m.household_id = p_household_id
          AND m.user_id = p_actor_user_id
    ) THEN
        RAISE EXCEPTION 'Only a member of the household can record an installment payment'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.installment_plans AS p
       SET paid_installments = p.paid_installments + 1,
           status = CASE WHEN p.paid_installments + 1 >= p.installment_count THEN 'COMPLETED' ELSE p.status END
     WHERE p.id = p_plan_id
       AND p.household_id = p_household_id
       AND p.paid_installments < p.installment_count
    RETURNING p.* INTO v_row;

    IF FOUND THEN
        RETURN NEXT v_row;
        RETURN;
    END IF;

    -- Already paid up (or not in this household): the current row, unchanged, if any.
    RETURN QUERY
        SELECT p.*
        FROM public.installment_plans AS p
        WHERE p.id = p_plan_id
          AND p.household_id = p_household_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_nafaqah_provider(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_previous uuid;
    v_role text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT nafaqah_provider_user_id INTO v_previous
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'Choose a member of this household as the Nafaqah provider' USING ERRCODE = '22023';
    END IF;

    v_role := public.household_member_financial_role(p_household_id, p_user_id);
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;
    IF v_role = 'spouse' THEN
        RAISE EXCEPTION 'A spouse member cannot be the Nafaqah provider'
            USING ERRCODE = '22023', HINT = 'provider_is_spouse';
    END IF;

    IF v_previous IS DISTINCT FROM p_user_id THEN
        UPDATE public.households SET nafaqah_provider_user_id = p_user_id WHERE id = p_household_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'nafaqah_provider_user_id', p_user_id,
        'previous_provider_user_id', v_previous
    );
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
    v_provider uuid;
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
    SET owner_user_id = p_new_primary_user_id,
        nafaqah_provider_user_id = COALESCE(
            nafaqah_provider_user_id,
            CASE WHEN public.household_member_financial_role(p_household_id, p_new_primary_user_id) <> 'spouse'
                 THEN p_new_primary_user_id END
        )
    WHERE id = p_household_id
    RETURNING nafaqah_provider_user_id INTO v_provider;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'primary_admin_user_id', p_new_primary_user_id,
        'previous_primary_admin_user_id', v_actor,
        'nafaqah_provider_user_id', v_provider
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
    IF NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' THEN
        RETURN NEW;  -- charged to the wife's allowance only
    END IF;

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
    IF OLD.nafaqah_class IS NOT DISTINCT FROM 'wife_personal' THEN
        RETURN OLD;
    END IF;

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
DECLARE
    v_old_counted boolean := OLD.nafaqah_class IS DISTINCT FROM 'wife_personal';
    v_new_counted boolean := NEW.nafaqah_class IS DISTINCT FROM 'wife_personal';
BEGIN
    IF OLD.amount <> NEW.amount
       OR OLD.category_code IS DISTINCT FROM NEW.category_code
       OR OLD.cycle_key IS DISTINCT FROM NEW.cycle_key
       OR date_trunc('month', OLD.timestamp) IS DISTINCT FROM date_trunc('month', NEW.timestamp)
       OR v_old_counted IS DISTINCT FROM v_new_counted THEN

        IF v_old_counted THEN
            UPDATE public.budgets
            SET spent_amount = GREATEST(0, spent_amount - OLD.amount)
            WHERE household_id  = OLD.household_id
              AND category_code = OLD.category_code
              AND (
                  (OLD.cycle_key IS NOT NULL AND cycle_key = OLD.cycle_key)
                  OR (OLD.cycle_key IS NULL AND month = date_trunc('month', OLD.timestamp)::DATE)
              );
        END IF;

        IF v_new_counted THEN
            UPDATE public.budgets
            SET spent_amount = spent_amount + NEW.amount
            WHERE household_id  = NEW.household_id
              AND category_code = NEW.category_code
              AND (
                  (NEW.cycle_key IS NOT NULL AND cycle_key = NEW.cycle_key)
                  OR (NEW.cycle_key IS NULL AND month = date_trunc('month', NEW.timestamp)::DATE)
              );
        END IF;
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

    -- An unchanged classification stays editable (e.g. after the provider left).
    IF TG_OP = 'UPDATE'
       AND NEW.nafaqah_class IS NOT DISTINCT FROM OLD.nafaqah_class
       AND NEW.nafaqah_spouse_id IS NOT DISTINCT FROM OLD.nafaqah_spouse_id
       AND NEW.household_id IS NOT DISTINCT FROM OLD.household_id THEN
        RETURN NEW;
    END IF;

    IF NOT public.nafaqah_is_spouse_member(NEW.household_id, NEW.nafaqah_spouse_id) THEN
        RAISE EXCEPTION 'nafaqah_spouse_id % is not a spouse member of household %', NEW.nafaqah_spouse_id, NEW.household_id
            USING ERRCODE = '23503';
    END IF;

    IF public.nafaqah_husband_id(NEW.household_id) IS NULL THEN
        RAISE EXCEPTION 'Household % has no Nafaqah provider: a household admin must choose one before family expenses are classified', NEW.household_id
            USING ERRCODE = '23514', HINT = 'no_nafaqah_provider';
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
REVOKE ALL ON FUNCTION public."guard_wife_reimbursable_ledger"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."guard_wife_reimbursable_ledger"() TO service_role;
REVOKE ALL ON FUNCTION public."household_default_financial_role"(p_household_id uuid, p_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."household_default_financial_role"(p_household_id uuid, p_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."households_nafaqah_provider_rules"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."households_nafaqah_provider_rules"() TO service_role;
REVOKE ALL ON FUNCTION public."join_household_by_code"(p_invite_code text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."join_household_by_code"(p_invite_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public."join_household_by_code"(p_invite_code text) TO service_role;
REVOKE ALL ON FUNCTION public."maintain_household_primary_admin"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."maintain_household_primary_admin"() TO service_role;
REVOKE ALL ON FUNCTION public."membership_financial_role_rules"() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."membership_financial_role_rules"() TO service_role;
REVOKE ALL ON FUNCTION public."nafaqah_husband_id"(p_household_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."nafaqah_husband_id"(p_household_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."pay_installment_plan"(p_plan_id uuid, p_household_id uuid, p_actor_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."pay_installment_plan"(p_plan_id uuid, p_household_id uuid, p_actor_user_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public."set_nafaqah_provider"(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public."set_nafaqah_provider"(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public."set_nafaqah_provider"(p_household_id uuid, p_user_id uuid, p_actor_user_id uuid) TO service_role;
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

-- 7. Pre-batch policies and triggers
CREATE TRIGGER trg_households_nafaqah_provider BEFORE INSERT OR UPDATE OF owner_user_id, nafaqah_provider_user_id ON public.households FOR EACH ROW EXECUTE FUNCTION households_nafaqah_provider_rules();

-- 8. Table and column privileges (installment_plans: back to the table-level UPDATE grant;
--    only authenticated changed, so service_role / anon privileges, PG17 MAINTAIN included,
--    are left exactly as they are)
REVOKE UPDATE (category_code, day_of_month, installment_count, merchant, monthly_amount, notes,
               original_transaction_id, provider, start_date, total_amount)
    ON public."installment_plans" FROM authenticated;
GRANT UPDATE ON public."installment_plans" TO authenticated;

COMMIT;
