-- ============================================================================
-- Migration: 20261105000200_account_deletion_rpcs.sql
-- Plan: docs/superpowers/plans/2026-11-05-account-deletion-corrected.md, Task 3
--
-- Client RPCs for requesting, cancelling and reading an account deletion. They act
-- only on auth.uid(); no argument can name another user.
--
-- request_account_deletion needs a recent login, enforced here and not by the client:
-- the JWT's session_id must match an auth.sessions row of this user created within the
-- last 15 minutes. It does not read `amr`. Cancel needs no re-auth.
--
-- Household rules at request time:
--   regular member          nothing
--   sole member             no choice; household marked
--   primary or sole admin,  required choice: 'transfer' to a named member (runs now
--     others present          through transfer_primary_admin; the caller stays a
--                             co-admin until final deletion) or 'delete' (marked)
--   non-primary co-admin    no choice; leaves at final deletion, household kept
--
-- Everything validates before anything changes, and one transaction covers it all.
-- Error hints: reauthentication_required, confirmation_mismatch,
-- household_choice_missing, household_choice_invalid, successor_invalid,
-- successor_pending_deletion, deletion_in_progress.
-- ============================================================================

BEGIN;

-- ── Internal helpers ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.account_deletion_recent_login_ok()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session text := auth.jwt() ->> 'session_id';
BEGIN
    IF v_session IS NULL
       OR v_session !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN false;
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM auth.sessions s
        WHERE s.id = v_session::uuid
          AND s.user_id = auth.uid()
          AND s.created_at >= now() - interval '15 minutes'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.account_deletion_household_positions(p_user_id uuid)
RETURNS TABLE(household_id uuid, household_name text, member_role text, member_position text, needs_choice boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT q.household_id, q.name, q.role, q.pos, q.pos = 'primary_admin'
    FROM (
        SELECT m.household_id, h.name, m.role,
            CASE
                WHEN NOT EXISTS (SELECT 1 FROM public.household_memberships o
                                 WHERE o.household_id = m.household_id AND o.user_id <> m.user_id)
                    THEN 'sole_member'
                WHEN m.role = 'admin'
                     AND (h.owner_user_id IS NOT DISTINCT FROM m.user_id
                          OR NOT EXISTS (SELECT 1 FROM public.household_memberships o
                                         WHERE o.household_id = m.household_id
                                           AND o.user_id <> m.user_id AND o.role = 'admin'))
                    THEN 'primary_admin'
                WHEN m.role = 'admin' THEN 'co_admin'
                ELSE 'member'
            END AS pos,
            m.created_at
        FROM public.household_memberships m
        JOIN public.households h ON h.id = m.household_id
        WHERE m.user_id = p_user_id
    ) q
    ORDER BY q.created_at ASC, q.household_id ASC;
$$;

-- Never includes the reason.
CREATE OR REPLACE FUNCTION public.account_deletion_status_json(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req public.account_deletion_requests%ROWTYPE;
BEGIN
    SELECT * INTO v_req
    FROM public.account_deletion_requests r
    WHERE r.user_id = p_user_id
      AND r.status IN ('scheduled', 'processing', 'failed');

    IF v_req.id IS NULL THEN
        RETURN jsonb_build_object('status', 'none', 'can_cancel', false);
    END IF;

    RETURN jsonb_build_object(
        'request_id', v_req.id,
        'status', v_req.status,
        'requested_at', v_req.requested_at,
        'scheduled_for', v_req.scheduled_for,
        'locale', v_req.locale,
        -- Until the purge has deleted anything, whatever the status.
        'can_cancel', v_req.stage = 'none',
        'marked_households', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'household_id', h.id,
                       'household_name', h.name,
                       'scheduled_for', h.deletion_scheduled_for) ORDER BY h.name)
            FROM public.households h
            WHERE h.deletion_requested_by = p_user_id
              AND h.deletion_scheduled_for IS NOT NULL
        ), '[]'::jsonb)
    );
END;
$$;

-- ── Client RPCs ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_account_deletion_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    RETURN public.account_deletion_status_json(v_uid);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_account_deletion_preflight()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'deletion', public.account_deletion_status_json(v_uid),
        'households', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'household_id', p.household_id,
                'household_name', p.household_name,
                'position', p.member_position,
                'needs_choice', p.needs_choice,
                -- Only where the caller must name a successor. A pending member is listed
                -- but flagged, and the server refuses them either way.
                'candidates', CASE WHEN p.needs_choice THEN COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'user_id', o.user_id,
                        'display_name', u.display_name,
                        'pending_deletion', public.account_deletion_user_pending(o.user_id))
                        ORDER BY o.created_at ASC, o.user_id ASC)
                    FROM public.household_memberships o
                    JOIN public.users u ON u.id = o.user_id
                    WHERE o.household_id = p.household_id AND o.user_id <> v_uid
                ), '[]'::jsonb) ELSE '[]'::jsonb END
            ))
            FROM public.account_deletion_household_positions(v_uid) p
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_account_deletion(
    p_confirmation text,
    p_household_choices jsonb DEFAULT '[]'::jsonb,
    p_reason text DEFAULT NULL,
    p_locale text DEFAULT 'ar'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_phrase text;
    v_locale text := COALESCE(lower(trim(p_locale)), 'ar');
    v_reason text := NULLIF(left(trim(p_reason), 500), '');
    v_choices jsonb := COALESCE(p_household_choices, '[]'::jsonb);
    v_choice jsonb;
    v_position record;
    v_hh uuid;
    v_action text;
    v_succ_raw text;
    v_succ uuid;
    v_scheduled timestamptz := now() + interval '30 days';
    v_seen uuid[] := '{}';
    v_needed uuid[];
    v_uuid_re constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    IF NOT public.account_deletion_recent_login_ok() THEN
        RAISE EXCEPTION 'Sign in again to confirm this request'
            USING ERRCODE = '42501', HINT = 'reauthentication_required';
    END IF;

    -- Drop bidi and zero-width marks a mobile keyboard may add, collapse whitespace.
    v_phrase := lower(regexp_replace(regexp_replace(
        regexp_replace(normalize(COALESCE(p_confirmation, ''), NFC), '[​-‏‪-‮⁦-⁩﻿]', '', 'g'),
        '\s+', ' ', 'g'), '^ | $', '', 'g'));
    IF v_phrase NOT IN ('delete', 'حذف', 'حذف کریں') THEN
        RAISE EXCEPTION 'The confirmation word does not match'
            USING ERRCODE = '22023', HINT = 'confirmation_mismatch';
    END IF;

    IF v_locale NOT IN ('ar', 'en', 'ur') THEN
        v_locale := 'ar';
    END IF;

    -- A double request finds the existing one.
    PERFORM pg_advisory_xact_lock(hashtextextended('account_deletion:' || v_uid::text, 0));
    IF public.account_deletion_user_pending(v_uid) THEN
        RETURN public.account_deletion_status_json(v_uid)
            || jsonb_build_object('success', true, 'already_requested', true);
    END IF;

    -- Hold every household of the caller, so roles cannot change under the validation.
    PERFORM 1
    FROM public.households h
    WHERE h.id IN (SELECT m.household_id FROM public.household_memberships m WHERE m.user_id = v_uid)
    ORDER BY h.id
    FOR UPDATE;

    IF jsonb_typeof(v_choices) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Household choices must be a list'
            USING ERRCODE = '22023', HINT = 'household_choice_invalid';
    END IF;

    SELECT COALESCE(array_agg(p.household_id), '{}') INTO v_needed
    FROM public.account_deletion_household_positions(v_uid) p
    WHERE p.needs_choice;

    FOR v_choice IN SELECT * FROM jsonb_array_elements(v_choices) LOOP
        IF jsonb_typeof(v_choice) IS DISTINCT FROM 'object'
           OR COALESCE(v_choice ->> 'household_id', '') !~* v_uuid_re THEN
            RAISE EXCEPTION 'Household choice is not valid'
                USING ERRCODE = '22023', HINT = 'household_choice_invalid';
        END IF;
        v_hh := (v_choice ->> 'household_id')::uuid;
        v_action := v_choice ->> 'action';
        v_succ_raw := v_choice ->> 'successor_user_id';

        -- Unknown, foreign, repeated, or a household that takes no choice.
        IF v_hh = ANY (v_seen) OR NOT (v_hh = ANY (v_needed)) THEN
            RAISE EXCEPTION 'Household choice is not valid'
                USING ERRCODE = '22023', HINT = 'household_choice_invalid';
        END IF;
        v_seen := v_seen || v_hh;

        IF v_action = 'delete' THEN
            IF v_succ_raw IS NOT NULL THEN
                RAISE EXCEPTION 'A household being deleted has no successor'
                    USING ERRCODE = '22023', HINT = 'household_choice_invalid';
            END IF;
        ELSIF v_action = 'transfer' THEN
            IF COALESCE(v_succ_raw, '') !~* v_uuid_re THEN
                RAISE EXCEPTION 'Choose a member of this household'
                    USING ERRCODE = '22023', HINT = 'successor_invalid';
            END IF;
            v_succ := v_succ_raw::uuid;
            IF v_succ = v_uid OR public.household_member_role(v_hh, v_succ) IS NULL THEN
                RAISE EXCEPTION 'Choose another member of this household'
                    USING ERRCODE = '22023', HINT = 'successor_invalid';
            END IF;
            IF public.account_deletion_user_pending(v_succ) THEN
                RAISE EXCEPTION 'This member is scheduled for deletion'
                    USING ERRCODE = '22023', HINT = 'successor_pending_deletion';
            END IF;
        ELSE
            RAISE EXCEPTION 'Household choice is not valid'
                USING ERRCODE = '22023', HINT = 'household_choice_invalid';
        END IF;
    END LOOP;

    IF EXISTS (SELECT 1 FROM unnest(v_needed) n WHERE NOT (n = ANY (v_seen))) THEN
        RAISE EXCEPTION 'Choose what happens to each household you administer'
            USING ERRCODE = '22023', HINT = 'household_choice_missing';
    END IF;

    -- Validated; apply.
    INSERT INTO public.account_deletion_requests (user_id, scheduled_for, locale, reason)
    VALUES (v_uid, v_scheduled, v_locale, v_reason);

    -- Sole-member households, read before any transfer below can change a position.
    UPDATE public.households h
    SET deletion_requested_at = now(),
        deletion_scheduled_for = v_scheduled,
        deletion_requested_by = v_uid
    WHERE h.id IN (SELECT p.household_id
                   FROM public.account_deletion_household_positions(v_uid) p
                   WHERE p.member_position = 'sole_member');

    FOR v_choice IN SELECT * FROM jsonb_array_elements(v_choices) LOOP
        v_hh := (v_choice ->> 'household_id')::uuid;
        IF v_choice ->> 'action' = 'delete' THEN
            UPDATE public.households h
            SET deletion_requested_at = now(),
                deletion_scheduled_for = v_scheduled,
                deletion_requested_by = v_uid
            WHERE h.id = v_hh;
        ELSE
            -- A sole admin who is not the recorded primary (old data): record them first,
            -- as transfer_primary_admin only accepts the primary admin.
            UPDATE public.households h
            SET owner_user_id = v_uid
            WHERE h.id = v_hh AND h.owner_user_id IS DISTINCT FROM v_uid;
            PERFORM public.transfer_primary_admin(v_hh, (v_choice ->> 'successor_user_id')::uuid, NULL);
        END IF;
    END LOOP;

    RETURN public.account_deletion_status_json(v_uid)
        || jsonb_build_object('success', true, 'already_requested', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_account_deletion()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_req public.account_deletion_requests%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('account_deletion:' || v_uid::text, 0));

    -- Serializes with the purge on the request row.
    SELECT * INTO v_req
    FROM public.account_deletion_requests r
    WHERE r.user_id = v_uid
      AND r.status IN ('scheduled', 'processing', 'failed')
    FOR UPDATE;

    IF v_req.id IS NULL THEN
        RETURN jsonb_build_object('success', true, 'cancelled', false, 'status', 'none', 'can_cancel', false);
    END IF;

    -- Once the purge has deleted anything (stage past none), it can only finish.
    IF v_req.stage <> 'none' THEN
        RAISE EXCEPTION 'This deletion is already in progress'
            USING ERRCODE = '22023', HINT = 'deletion_in_progress';
    END IF;

    UPDATE public.account_deletion_requests
    SET status = 'cancelled',
        cancelled_at = now(),
        lease_expires_at = NULL,
        reason = NULL
    WHERE id = v_req.id;

    UPDATE public.households
    SET deletion_requested_at = NULL,
        deletion_scheduled_for = NULL,
        deletion_requested_by = NULL
    WHERE deletion_requested_by = v_uid;

    RETURN jsonb_build_object('success', true, 'cancelled', true, 'status', 'none', 'can_cancel', false);
END;
$$;

REVOKE ALL ON FUNCTION public.account_deletion_recent_login_ok() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_household_positions(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_status_json(uuid) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.get_account_deletion_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_account_deletion_preflight() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.request_account_deletion(text, jsonb, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_account_deletion() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_status() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_preflight() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_account_deletion(text, jsonb, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_account_deletion() TO authenticated, service_role;

COMMIT;
