-- ----------------------------------------------------------------------------
-- Migration: 20261020010000_audit_invites_rls_and_targeted_claims.sql
-- Audit DB-01 (Critical): household_invites had policies but RLS was never
--   enabled, so with Supabase's default table grants anon could list every
--   invite code and any authenticated user could insert an invite for any
--   household (then join it), or re-open used/expired invites via UPDATE.
-- Audit DB-05 (High): join_household_by_code / claim_household_role_invite
--   updated household_dependents.claimed_user_id, a column that does not exist
--   (the schema column is linked_user_id), so every targeted invite failed; the
--   target member was also never checked against the invite's household.
--   claim_household_role_invite additionally had no failed-attempt lockout.
-- Proof test: supabase/tests/08_audit_invites_rls_and_targeted_claims.sql
-- ----------------------------------------------------------------------------

BEGIN;

-- 1. Enforce RLS on household_invites (policies from 20261019030000 become live)
ALTER TABLE public.household_invites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.household_invites FROM anon;

-- 2. target_member_id must reference a manual member of the same household.
--    Enforced by trigger so it also binds service-role inserts (ai_service).
CREATE OR REPLACE FUNCTION public.validate_invite_target_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.target_member_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.household_dependents d
        WHERE d.id = NEW.target_member_id
          AND d.household_id = NEW.household_id
    ) THEN
        RAISE EXCEPTION 'Invite target member % does not belong to household %', NEW.target_member_id, NEW.household_id
            USING ERRCODE = '23503';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_invite_target_member() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_validate_invite_target_member ON public.household_invites;
CREATE TRIGGER trg_validate_invite_target_member
BEFORE INSERT OR UPDATE OF target_member_id, household_id ON public.household_invites
FOR EACH ROW EXECUTE FUNCTION public.validate_invite_target_member();

-- 3. join_household_by_code: link manual member via linked_user_id (household-scoped)
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
$$;

REVOKE EXECUTE ON FUNCTION public.join_household_by_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_household_by_code(text) TO authenticated;

-- 4. claim_household_role_invite: linked_user_id, household-scoped link, lockout
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
$$;

REVOKE EXECUTE ON FUNCTION public.claim_household_role_invite(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_household_role_invite(text, uuid) TO authenticated, service_role;

COMMIT;
