-- ============================================================================
-- Migration: 20261105000800_account_deletion_operator_request.sql
-- Runbook: docs/runbooks/account-deletion-purge.md
--
-- Someone who cannot sign in asks through the public form, and the developer, after
-- verifying them, schedules the same 30-day deletion from ai_service/scripts/
-- account_deletion_operator.py. There is no HTTP route to any of this.
--
-- request_account_deletion and the operator path share one scheduler, so the household
-- rules cannot drift apart: a primary or sole admin with other members is refused with
-- household_choice_missing, never guessed for. Everything else about the request (status,
-- cancel, marks, purge) is the ordinary path.
--
-- The request records that an operator started it: the inquiry's reference and the
-- operator's handle, which must not be an address. No other personal data, and not the
-- form's message.
--
-- The preview says 'ambiguous', and offers no user id, when two accounts' addresses differ
-- only in letter case. One inquiry schedules one person (inquiry_reused otherwise), and an
-- operator cancel names a reference that exists.
--
-- Cancel, by the user or the operator, works whatever the status until the purge has deleted
-- anything (stage none). The typed word is folded on the server: see
-- account_deletion_fold_confirmation.
--
-- The reference is plain text with no foreign key, because the worker removes
-- account_deletion inquiries after 90 days, as the public page promises, and a job can
-- be open longer than that. Nothing in a job reads the inquiry after it is scheduled.
-- complete_account_purge removes the inquiry and the reference, because an inquiry can
-- carry a typed address that differs from the account's, which the purge's own match
-- by address would miss.
-- ============================================================================

BEGIN;

ALTER TABLE public.account_deletion_requests
    ADD COLUMN initiated_by text NOT NULL DEFAULT 'user' CHECK (initiated_by IN ('user', 'operator')),
    ADD COLUMN operator_inquiry_reference text CHECK (char_length(operator_inquiry_reference) <= 64),
    ADD COLUMN operator_verified_by text CHECK (operator_verified_by ~ '^[A-Za-z0-9_.-]{1,64}$'),
    ADD COLUMN operator_cancelled_by text CHECK (operator_cancelled_by ~ '^[A-Za-z0-9_.-]{1,64}$'),
    ADD COLUMN operator_cancel_reference text CHECK (char_length(operator_cancel_reference) <= 64),
    ADD CONSTRAINT account_deletion_requests_operator_recorded
        CHECK (initiated_by = 'user' OR operator_verified_by IS NOT NULL),
    ADD CONSTRAINT account_deletion_requests_user_has_no_operator
        CHECK (initiated_by = 'operator' OR (operator_inquiry_reference IS NULL AND operator_verified_by IS NULL));

-- ── The shared scheduler ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.account_deletion_schedule(
    p_uid uuid,
    p_choices jsonb,
    p_reason text,
    p_locale text,
    p_initiated_by text,
    p_inquiry_reference text,
    p_verified_by text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_locale text := COALESCE(lower(trim(p_locale)), 'ar');
    v_reason text := NULLIF(left(trim(p_reason), 500), '');
    v_choices jsonb := COALESCE(p_choices, '[]'::jsonb);
    v_choice jsonb;
    v_hh uuid;
    v_action text;
    v_succ_raw text;
    v_succ uuid;
    v_scheduled timestamptz := now() + interval '30 days';
    v_seen uuid[] := '{}';
    v_needed uuid[];
    v_uuid_re constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
    IF v_locale NOT IN ('ar', 'en', 'ur') THEN
        v_locale := 'ar';
    END IF;

    -- A double request finds the existing one.
    PERFORM pg_advisory_xact_lock(hashtextextended('account_deletion:' || p_uid::text, 0));
    IF public.account_deletion_user_pending(p_uid) THEN
        RETURN public.account_deletion_status_json(p_uid)
            || jsonb_build_object('success', true, 'already_requested', true);
    END IF;

    -- Hold every household of the user, so roles cannot change under the validation.
    PERFORM 1
    FROM public.households h
    WHERE h.id IN (SELECT m.household_id FROM public.household_memberships m WHERE m.user_id = p_uid)
    ORDER BY h.id
    FOR UPDATE;

    IF jsonb_typeof(v_choices) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Household choices must be a list'
            USING ERRCODE = '22023', HINT = 'household_choice_invalid';
    END IF;

    SELECT COALESCE(array_agg(p.household_id), '{}') INTO v_needed
    FROM public.account_deletion_household_positions(p_uid) p
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
            IF v_succ = p_uid OR public.household_member_role(v_hh, v_succ) IS NULL THEN
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
    INSERT INTO public.account_deletion_requests
        (user_id, scheduled_for, locale, reason, initiated_by, operator_inquiry_reference, operator_verified_by)
    VALUES (p_uid, v_scheduled, v_locale, v_reason, p_initiated_by, p_inquiry_reference, p_verified_by);

    -- Sole-member households, read before any transfer below can change a position.
    UPDATE public.households h
    SET deletion_requested_at = now(),
        deletion_scheduled_for = v_scheduled,
        deletion_requested_by = p_uid
    WHERE h.id IN (SELECT p.household_id
                   FROM public.account_deletion_household_positions(p_uid) p
                   WHERE p.member_position = 'sole_member');

    FOR v_choice IN SELECT * FROM jsonb_array_elements(v_choices) LOOP
        v_hh := (v_choice ->> 'household_id')::uuid;
        IF v_choice ->> 'action' = 'delete' THEN
            UPDATE public.households h
            SET deletion_requested_at = now(),
                deletion_scheduled_for = v_scheduled,
                deletion_requested_by = p_uid
            WHERE h.id = v_hh;
        ELSE
            -- A sole admin who is not the recorded primary (old data): record them first,
            -- as transfer_primary_admin only accepts the primary admin.
            UPDATE public.households h
            SET owner_user_id = p_uid
            WHERE h.id = v_hh AND h.owner_user_id IS DISTINCT FROM p_uid;
            PERFORM public.transfer_primary_admin(v_hh, (v_choice ->> 'successor_user_id')::uuid, p_uid);
        END IF;
    END LOOP;

    RETURN public.account_deletion_status_json(p_uid)
        || jsonb_build_object('success', true, 'already_requested', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.account_deletion_cancel(
    p_uid uuid,
    p_cancelled_by text DEFAULT NULL,
    p_cancel_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req public.account_deletion_requests%ROWTYPE;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('account_deletion:' || p_uid::text, 0));

    -- Serializes with the purge on the request row.
    SELECT * INTO v_req
    FROM public.account_deletion_requests r
    WHERE r.user_id = p_uid
      AND r.status IN ('scheduled', 'processing', 'failed')
    FOR UPDATE;

    IF v_req.id IS NULL THEN
        RETURN jsonb_build_object('success', true, 'cancelled', false, 'status', 'none', 'can_cancel', false);
    END IF;

    -- Whatever the status (scheduled, processing or failed), until the purge has deleted
    -- anything. prepare_account_purge takes the same two locks in the same order, and moves the
    -- stage past none in the transaction that deletes, so this read cannot be stale.
    IF v_req.stage <> 'none' THEN
        RAISE EXCEPTION 'This deletion is already in progress'
            USING ERRCODE = '22023', HINT = 'deletion_in_progress';
    END IF;

    UPDATE public.account_deletion_requests
    SET status = 'cancelled',
        cancelled_at = now(),
        lease_expires_at = NULL,
        reason = NULL,
        operator_cancelled_by = p_cancelled_by,
        operator_cancel_reference = p_cancel_reference
    WHERE id = v_req.id;

    UPDATE public.households
    SET deletion_requested_at = NULL,
        deletion_scheduled_for = NULL,
        deletion_requested_by = NULL
    WHERE deletion_requested_by = p_uid;

    RETURN jsonb_build_object('success', true, 'cancelled', true, 'status', 'none', 'can_cancel', false);
END;
$$;

-- ── The user's path, on the shared functions ────────────────────────────────

-- The typed confirmation word, folded before it is compared. In this order:
--   1. NFC.
--   2. Removed: U+200B-U+200D (zero-width space, non-joiner, joiner), U+202A-U+202E and
--      U+2066-U+2069 (bidi embeddings and isolates), U+FEFF.
--   3. A space: any \s, U+0085, U+00A0, U+1680, U+2000-U+200A, U+200E, U+200F, U+2028,
--      U+2029, U+202F, U+205F, U+3000.
--   4. Urdu letters as an Arabic keyboard types them: U+06A9 to U+0643, U+06CC to U+064A,
--      U+06BA to U+0646, and U+0649 to U+064A.
--   5. Runs of spaces become one, the ends are trimmed, and the text is lowercased.
CREATE OR REPLACE FUNCTION public.account_deletion_fold_confirmation(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT lower(btrim(regexp_replace(
        translate(
            regexp_replace(
                regexp_replace(normalize(COALESCE(p_text, ''), NFC),
                    '[\u200B-\u200D\u202A-\u202E\u2066-\u2069\uFEFF]', '', 'g'),
                '[\s\u0085\u00A0\u1680\u2000-\u200A\u200E\u200F\u2028\u2029\u202F\u205F\u3000]', ' ', 'g'),
            U&'\06A9\06CC\06BA\0649', U&'\0643\064A\0646\064A'),
        ' {2,}', ' ', 'g'), ' '));
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
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    IF NOT public.account_deletion_recent_login_ok() THEN
        RAISE EXCEPTION 'Sign in again to confirm this request'
            USING ERRCODE = '42501', HINT = 'reauthentication_required';
    END IF;

    -- Both sides folded the same way, so the accepted words match however they were typed.
    v_phrase := public.account_deletion_fold_confirmation(p_confirmation);
    IF v_phrase = '' OR v_phrase NOT IN (
        SELECT public.account_deletion_fold_confirmation(w) FROM unnest(ARRAY['delete', 'حذف', 'حذف کریں']) AS w
    ) THEN
        RAISE EXCEPTION 'The confirmation word does not match'
            USING ERRCODE = '22023', HINT = 'confirmation_mismatch';
    END IF;

    RETURN public.account_deletion_schedule(v_uid, p_household_choices, p_reason, p_locale, 'user', NULL, NULL);
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
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    RETURN public.account_deletion_cancel(v_uid);
END;
$$;

-- ── The operator's path ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.account_deletion_require_operator_handle(p_handle text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_handle IS NULL OR p_handle !~ '^[A-Za-z0-9_.-]{1,64}$' THEN
        RAISE EXCEPTION 'The operator handle is short text, not an address'
            USING ERRCODE = '22023', HINT = 'operator_handle_invalid';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_account_deletion_operator_preview(p_email text, p_inquiry_reference text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid;
    v_matches integer;
    v_address text := lower(trim(COALESCE(p_email, '')));
    v_inquiry public.inquiries%ROWTYPE;
BEGIN
    PERFORM public.account_deletion_require_service();

    -- Auth compares addresses exactly, so two accounts can differ only in letter case. Then
    -- the address does not say which one is meant, and no user id is offered.
    SELECT count(*), min(u.id::text)::uuid INTO v_matches, v_uid FROM auth.users u WHERE lower(u.email) = v_address;
    IF v_matches > 1 THEN
        v_uid := NULL;
    END IF;

    SELECT * INTO v_inquiry
    FROM public.inquiries i
    WHERE i.type = 'account_deletion'
      AND (i.reference = p_inquiry_reference OR i.id::text = p_inquiry_reference);

    RETURN jsonb_build_object(
        'inquiry_valid', v_inquiry.id IS NOT NULL,
        'inquiry_email_matches', v_inquiry.id IS NOT NULL AND lower(v_inquiry.email) = v_address,
        'ambiguous', v_matches > 1,
        'account_found', v_matches > 0,
        'user_id', v_uid,
        'deletion', CASE WHEN v_uid IS NULL THEN NULL ELSE (
            SELECT jsonb_build_object('status', s ->> 'status', 'scheduled_for', s ->> 'scheduled_for',
                                      'can_cancel', (s ->> 'can_cancel')::boolean)
            FROM public.account_deletion_status_json(v_uid) AS s
        ) END,
        -- Their own position in each household. No names, and nobody else's id.
        'households', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'household_id', p.household_id,
                'position', p.member_position,
                'needs_choice', p.needs_choice,
                'other_members', (SELECT count(*) FROM public.household_memberships o
                                  WHERE o.household_id = p.household_id AND o.user_id <> v_uid)))
            FROM public.account_deletion_household_positions(v_uid) p
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_account_deletion_by_operator(
    p_user_id uuid,
    p_inquiry_reference text,
    p_verified_by text,
    p_household_choices jsonb DEFAULT '[]'::jsonb,
    p_locale text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_inquiry public.inquiries%ROWTYPE;
BEGIN
    PERFORM public.account_deletion_require_service();
    PERFORM public.account_deletion_require_operator_handle(p_verified_by);

    -- Locked, so two operators cannot use one inquiry for two people at once.
    SELECT * INTO v_inquiry
    FROM public.inquiries i
    WHERE i.type = 'account_deletion'
      AND (i.reference = p_inquiry_reference OR i.id::text = p_inquiry_reference)
    FOR UPDATE;
    IF v_inquiry.id IS NULL THEN
        RAISE EXCEPTION 'No account deletion inquiry with that reference'
            USING ERRCODE = '22023', HINT = 'inquiry_invalid';
    END IF;

    -- One inquiry is one person's request.
    IF EXISTS (SELECT 1 FROM public.account_deletion_requests r
               WHERE r.operator_inquiry_reference = v_inquiry.reference
                 AND r.user_id IS DISTINCT FROM p_user_id) THEN
        RAISE EXCEPTION 'That inquiry already scheduled the deletion of another account'
            USING ERRCODE = '22023', HINT = 'inquiry_reused';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id)
       OR NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'No such account' USING ERRCODE = 'P0002', HINT = 'account_not_found';
    END IF;

    RETURN public.account_deletion_schedule(
        p_user_id, p_household_choices, NULL,
        COALESCE(NULLIF(trim(p_locale), ''), v_inquiry.locale),
        'operator', v_inquiry.reference, p_verified_by);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_account_deletion_by_operator(
    p_user_id uuid,
    p_inquiry_reference text,
    p_verified_by text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reference text;
BEGIN
    PERFORM public.account_deletion_require_service();
    PERFORM public.account_deletion_require_operator_handle(p_verified_by);

    -- The reference must exist: an account_deletion inquiry (by reference or id), or the one
    -- this user's open request was scheduled from, whose inquiry may be past its 90 days.
    SELECT i.reference INTO v_reference
    FROM public.inquiries i
    WHERE i.type = 'account_deletion'
      AND (i.reference = p_inquiry_reference OR i.id::text = p_inquiry_reference);
    IF v_reference IS NULL THEN
        SELECT r.operator_inquiry_reference INTO v_reference
        FROM public.account_deletion_requests r
        WHERE r.user_id = p_user_id
          AND r.status IN ('scheduled', 'processing', 'failed')
          AND r.operator_inquiry_reference = p_inquiry_reference;
    END IF;
    IF v_reference IS NULL THEN
        RAISE EXCEPTION 'No account deletion inquiry with that reference'
            USING ERRCODE = '22023', HINT = 'inquiry_invalid';
    END IF;

    RETURN public.account_deletion_cancel(p_user_id, p_verified_by, v_reference);
END;
$$;

-- ── Completion removes the reference and what it points to ──────────────────

CREATE OR REPLACE FUNCTION public.complete_account_purge(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req public.account_deletion_requests%ROWTYPE;
BEGIN
    PERFORM public.account_deletion_require_service();

    SELECT * INTO v_req FROM public.account_deletion_requests WHERE id = p_request_id FOR UPDATE;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'Account deletion request not found' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_req.status = 'completed' THEN
        RETURN;
    END IF;
    IF v_req.stage <> 'storage_done' THEN
        RAISE EXCEPTION 'The purge has not reached this stage' USING ERRCODE = '22023', HINT = 'purge_stage_invalid';
    END IF;
    IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_req.user_id)
       OR EXISTS (SELECT 1 FROM public.users WHERE id = v_req.user_id) THEN
        RAISE EXCEPTION 'The auth user still exists' USING ERRCODE = '22023', HINT = 'auth_user_still_exists';
    END IF;

    -- Older cancelled requests of this user would keep the id alive.
    DELETE FROM public.account_deletion_requests
    WHERE user_id = v_req.user_id AND id <> p_request_id;

    -- Its typed address can differ from the account's, so the purge's own match misses it.
    IF v_req.operator_inquiry_reference IS NOT NULL THEN
        DELETE FROM public.inquiries
        WHERE reference = v_req.operator_inquiry_reference AND type = 'account_deletion';
    END IF;

    UPDATE public.account_deletion_requests
    SET status = 'completed',
        completed_at = now(),
        user_id = NULL,
        reason = NULL,
        lease_expires_at = NULL,
        last_error_code = NULL,
        operator_inquiry_reference = NULL
    WHERE id = p_request_id;
END;
$$;

-- ── Privileges ──────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.account_deletion_schedule(uuid, jsonb, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_cancel(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_require_operator_handle(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_fold_confirmation(text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.get_account_deletion_operator_preview(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.schedule_account_deletion_by_operator(uuid, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cancel_account_deletion_by_operator(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_operator_preview(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.schedule_account_deletion_by_operator(uuid, text, text, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_account_deletion_by_operator(uuid, text, text) TO service_role;

COMMIT;
