-- ============================================================================
-- Migration: 20261105000300_account_deletion_purge.sql
-- Plan: docs/superpowers/plans/2026-11-05-account-deletion-corrected.md, Task 4
--
-- Service-only functions behind the account deletion worker. No client can execute
-- any of them, and each refuses a caller with a JWT subject. Nothing here runs by
-- itself: the worker (Task 5) calls them, then the Auth Admin API deletes the user.
--
-- One job:
--   claim_due_account_deletions       lease with FOR UPDATE SKIP LOCKED
--   prepare_account_purge             all database work, one transaction, no-op if done
--   list_account_purge_storage        the worker removes these through the Storage API
--   mark_account_purge_storage_done
--   (Auth Admin API deletes the user; the FKs NULL the remaining creator columns)
--   complete_account_purge            verifies auth.users is gone, leaves a tombstone
--                                     with no identifiers
-- record_account_purge_failure backs off exponentially, capped at 24h, and ends in
-- 'failed' after 5 attempts. While backing off a job stays 'processing', so it can no
-- longer be cancelled: its data may already be gone.
--
-- prepare_account_purge, for each household of the user:
--   no other members, or marked by this user   household deleted
--   primary or sole admin, others, not marked  late-surfaced: mark it, give 7 days'
--                                              notice, extend the request, return
--                                              {deferred: true}. Nothing is purged.
--   anything else                              leaves, household kept
--
-- Household delete order is fixed: income and transfers (RESTRICT races), non-admin
-- memberships then admin ones (check_last_admin_membership), the household, then each
-- former member's active household is repointed.
--
-- D5: her wife_personal rows go before her membership. Otherwise
-- remove_nafaqah_ledger_on_membership_end would declassify them and the budget
-- triggers would move them into category budgets.
--
-- Ledger invariant, checked inside the transaction: every surviving pool balance and
-- every surviving budget's spent_amount must equal what it was at the start, or the
-- purge aborts with nothing changed (HINT purge_ledger_invariant). The one known way
-- to hit it is old data: a wife_personal row debiting a pool, written before
-- trg_enforce_wife_class_account. The job then ends in 'failed', which alerts, rather
-- than quietly crediting the pool. The snapshot covers only the households the purge can
-- reach (theirs, those of pools they own, those of their wife_personal rows), and those
-- pools, households and budgets are locked first, in that order and by id, so another
-- household's expense, or one waiting on these, never trips it.
--
-- Locks: the user's advisory lock, then the request row, as account_deletion_cancel.
--
-- Identifiers: their id goes from other members' rows in any household. Their address,
-- matched whole and in any case, goes from every text and JSON column in public. Their
-- display name goes from their own kept rows' merchant and item names and from the names
-- of pools handed to another admin; other members' free text keeps it.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.account_deletion_require_service()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Forbidden: this function is not for user sessions' USING ERRCODE = '42501';
    END IF;
END;
$$;

-- Moves a user whose active household is gone to their next membership.
-- leave_household and remove_member lack this; they are deliberately left as they are.
CREATE OR REPLACE FUNCTION public.account_deletion_repoint_active_household(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_current uuid;
    v_next public.household_memberships%ROWTYPE;
BEGIN
    SELECT household_id INTO v_current FROM public.users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    IF v_current IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.household_memberships m
                   WHERE m.user_id = p_user_id AND m.household_id = v_current) THEN
        RETURN;
    END IF;

    SELECT * INTO v_next
    FROM public.household_memberships m
    WHERE m.user_id = p_user_id
    ORDER BY m.is_default DESC, m.created_at ASC, m.household_id ASC
    LIMIT 1;

    IF v_next.id IS NULL THEN
        UPDATE public.users SET household_id = NULL, role = 'member' WHERE id = p_user_id;
        RETURN;
    END IF;

    UPDATE public.household_memberships m
    SET is_default = (m.household_id = v_next.household_id)
    WHERE m.user_id = p_user_id;

    UPDATE public.users
    SET household_id = v_next.household_id,
        role = v_next.role,
        financial_role = v_next.financial_role
    WHERE id = p_user_id;
END;
$$;

-- A note value we may keep: a known token, or another member's id.
CREATE OR REPLACE FUNCTION public.account_deletion_note_token(p_value text, p_refs text[])
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN v IN ('me', 'partner', 'both', 'shared', 'household', 'all', 'all_peers', 'family', 'everyone',
                   'wife', 'spouse', 'husband', 'provider', 'children') THEN v
        WHEN v = ANY (p_refs) THEN 'deleted_member'
        WHEN v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v
        ELSE 'deleted_member'
    END
    FROM (SELECT lower(trim(COALESCE(p_value, ''))) AS v) q;
$$;

-- The deleted member's own note: keep only the machine-readable part that
-- settlement_engine.py reads, drop all free text. Same patterns as _SETTLEMENT_HEAD_RE,
-- _MANUAL_TAIL_RE and _legacy_tags.
CREATE OR REPLACE FUNCTION public.account_deletion_scrub_own_note(p_notes text, p_refs text[])
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_m text[];
    v_text text;
    v_part text;
    v_low text;
    v_paid text;
    v_ben text;
    v_spent text;
    v_method text;
    v_out text[] := '{}';
BEGIN
    IF p_notes IS NULL THEN
        RETURN NULL;
    END IF;

    v_m := regexp_match(p_notes, '^\s*Settlement\s*\|\s*PaidBy:\s*([^|]+?)\s*(?:\||$)', 'i');
    IF v_m IS NOT NULL THEN
        v_paid := public.account_deletion_note_token(v_m[1], p_refs);
        v_out := v_out || ('PaidBy: ' || v_paid);
        v_m := regexp_match(p_notes, '\|\s*Recipient:\s*([^|]*?)\s*(?:\||$)', 'i');
        IF v_m IS NOT NULL THEN
            v_out := v_out || ('Recipient: ' || public.account_deletion_note_token(v_m[1], p_refs));
        END IF;
        v_m := regexp_match(p_notes, '\|\s*Method:\s*([a-z_]{1,20})\s*(?:\||$)', 'i');
        IF v_m IS NOT NULL THEN
            v_method := lower(v_m[1]);
            v_out := v_out || ('Method: ' || v_method);
        END IF;
        RETURN 'Settlement | ' || array_to_string(v_out, ' | ');
    END IF;

    v_m := regexp_match(p_notes,
        '\|\s*PaidBy:\s*([^|]*?)\s*\|\s*Beneficiary:\s*([^|]*?)\s*(?:\|\s*SubCategory:\s*[^|]*?\s*)?\|\s*SpentBy:\s*([^|]*?)\s*$', 'i');
    IF v_m IS NOT NULL THEN
        RETURN '| PaidBy: ' || public.account_deletion_note_token(v_m[1], p_refs)
            || ' | Beneficiary: ' || public.account_deletion_note_token(v_m[2], p_refs)
            || ' | SpentBy: ' || public.account_deletion_note_token(v_m[3], p_refs);
    END IF;

    v_text := p_notes;
    IF position(' | Items: [' IN v_text) > 0 THEN
        v_text := left(v_text, length(v_text) - position(reverse(' | Items: [') IN reverse(v_text)) - length(' | Items: [') + 1);
    END IF;
    FOREACH v_part IN ARRAY string_to_array(v_text, '|') LOOP
        v_low := lower(trim(v_part));
        IF v_low LIKE 'paidby:%' THEN
            v_paid := substr(v_low, 8);
        ELSIF v_low LIKE 'beneficiary:%' THEN
            v_ben := substr(v_low, 13);
        ELSIF v_low LIKE 'spentby:%' THEN
            v_spent := substr(v_low, 9);
        END IF;
    END LOOP;
    IF v_paid IS NOT NULL THEN
        v_out := v_out || ('PaidBy: ' || public.account_deletion_note_token(v_paid, p_refs));
    END IF;
    IF v_ben IS NOT NULL THEN
        v_out := v_out || ('Beneficiary: ' || public.account_deletion_note_token(v_ben, p_refs));
    END IF;
    IF v_spent IS NOT NULL THEN
        v_out := v_out || ('SpentBy: ' || public.account_deletion_note_token(v_spent, p_refs));
    END IF;
    IF array_length(v_out, 1) IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN array_to_string(v_out, ' | ');
END;
$$;

-- Someone else's note: their words stay, only references to the deleted member go.
CREATE OR REPLACE FUNCTION public.account_deletion_scrub_other_note(p_notes text, p_refs text[])
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ref text;
    v_esc text;
    v_out text := p_notes;
BEGIN
    IF p_notes IS NULL THEN
        RETURN NULL;
    END IF;
    FOREACH v_ref IN ARRAY p_refs LOOP
        v_esc := regexp_replace(v_ref, '([^[:alnum:][:space:]])', '\\\1', 'g');
        IF v_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            v_out := regexp_replace(v_out, v_esc, 'deleted_member', 'gi');
        ELSE
            -- A name only as a tag value, never as a word inside someone's sentence.
            v_out := regexp_replace(v_out, '(Beneficiary:\s*)' || v_esc || '(\s*(\||$))', '\1deleted_member\2', 'gi');
        END IF;
    END LOOP;
    RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.account_deletion_scrub_items(p_items jsonb, p_refs text[])
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN p_items
        ELSE (
            SELECT COALESCE(jsonb_agg(
                CASE
                    WHEN jsonb_typeof(e.item) = 'object' THEN
                        e.item
                        || CASE WHEN lower(trim(e.item ->> 'beneficiary')) = ANY (p_refs)
                                THEN '{"beneficiary": "deleted_member"}'::jsonb ELSE '{}'::jsonb END
                        || CASE WHEN lower(trim(e.item ->> 'beneficiary_id')) = ANY (p_refs)
                                THEN '{"beneficiary_id": "deleted_member"}'::jsonb ELSE '{}'::jsonb END
                    ELSE e.item
                END
                ORDER BY e.ord), '[]'::jsonb)
            FROM jsonb_array_elements(p_items) WITH ORDINALITY AS e(item, ord)
        )
    END;
$$;

-- Each pattern's matches, case-insensitive, become deleted_member. NULL patterns are skipped.
CREATE OR REPLACE FUNCTION public.account_deletion_scrub_text(p_text text, p_patterns text[])
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pattern text;
    v_out text := p_text;
BEGIN
    IF p_text IS NULL OR p_patterns IS NULL THEN
        RETURN p_text;
    END IF;
    FOREACH v_pattern IN ARRAY p_patterns LOOP
        IF v_pattern IS NOT NULL THEN
            v_out := regexp_replace(v_out, v_pattern, 'deleted_member', 'gi');
        END IF;
    END LOOP;
    RETURN v_out;
END;
$$;

-- The "name" of each item, through account_deletion_scrub_text. Nothing else in an item changes.
CREATE OR REPLACE FUNCTION public.account_deletion_scrub_item_names(p_items jsonb, p_patterns text[])
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN p_items
        ELSE (
            SELECT COALESCE(jsonb_agg(
                CASE
                    WHEN jsonb_typeof(e.item) = 'object' AND jsonb_typeof(e.item -> 'name') = 'string' THEN
                        jsonb_set(e.item, '{name}', to_jsonb(public.account_deletion_scrub_text(e.item ->> 'name', p_patterns)))
                    ELSE e.item
                END
                ORDER BY e.ord), '[]'::jsonb)
            FROM jsonb_array_elements(p_items) WITH ORDINALITY AS e(item, ord)
        )
    END;
$$;

-- Every text and JSON column of every table in public: matches of p_pattern become
-- deleted_member. p_needle (lowercase) is a cheap pre-filter that every match contains. A
-- length-limited column keeps a value the sentinel would not fit in, rather than fail the purge.
CREATE OR REPLACE FUNCTION public.account_deletion_replace_everywhere(p_needle text, p_pattern text)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_col record;
BEGIN
    IF COALESCE(p_needle, '') = '' OR p_pattern IS NULL THEN
        RETURN;
    END IF;
    FOR v_col IN
        SELECT c.oid::regclass AS tbl,
               a.attname AS col,
               format_type(a.atttypid, NULL) AS typ,
               a.atttypid IN ('json'::regtype, 'jsonb'::regtype) AS is_json,
               CASE WHEN a.atttypid = 'varchar'::regtype AND a.atttypmod > 4 THEN a.atttypmod - 4 END AS max_len
        FROM pg_class c
        JOIN pg_attribute a ON a.attrelid = c.oid
        WHERE c.relnamespace = 'public'::regnamespace
          AND c.relkind = 'r'
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND a.attgenerated = ''
          AND a.atttypid IN ('text'::regtype, 'varchar'::regtype, 'json'::regtype, 'jsonb'::regtype)
          AND has_column_privilege(c.oid, a.attnum, 'UPDATE')
        ORDER BY c.oid, a.attnum
    LOOP
        IF v_col.is_json THEN
            EXECUTE format(
                'UPDATE %s SET %I = regexp_replace(%I::text, $1, %L, %L)::%s WHERE strpos(lower(%I::text), $2) > 0 AND %I::text ~* $1',
                v_col.tbl, v_col.col, v_col.col, 'deleted_member', 'gi', v_col.typ, v_col.col, v_col.col)
            USING p_pattern, lower(p_needle);
        ELSE
            EXECUTE format(
                'UPDATE %s SET %I = regexp_replace(%I, $1, %L, %L) WHERE strpos(lower(%I), $2) > 0 AND %I ~* $1'
                || CASE WHEN v_col.max_len IS NOT NULL
                        THEN format(' AND char_length(regexp_replace(%I, $1, %L, %L)) <= %s', v_col.col, 'deleted_member', 'gi', v_col.max_len)
                        ELSE '' END,
                v_col.tbl, v_col.col, v_col.col, 'deleted_member', 'gi', v_col.col, v_col.col)
            USING p_pattern, lower(p_needle);
        END IF;
    END LOOP;
END;
$$;

-- ── Service functions ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.claim_due_account_deletions(p_limit integer DEFAULT 20, p_lease_minutes integer DEFAULT 30)
RETURNS TABLE(request_id uuid, user_id uuid, stage text, attempts integer, locale text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();

    -- A job that keeps killing the worker never reaches record_account_purge_failure.
    UPDATE public.account_deletion_requests r
    SET status = 'failed',
        lease_expires_at = NULL,
        last_error_code = COALESCE(r.last_error_code, 'lease_expired')
    WHERE r.status = 'processing'
      AND r.lease_expires_at <= now()
      AND r.attempts >= 5;

    RETURN QUERY
    WITH due AS (
        SELECT r.id
        FROM public.account_deletion_requests r
        WHERE (r.status = 'scheduled' AND r.scheduled_for <= now())
           OR (r.status = 'processing' AND r.lease_expires_at <= now())
        ORDER BY r.scheduled_for ASC, r.id ASC
        LIMIT GREATEST(COALESCE(p_limit, 20), 0)
        FOR UPDATE OF r SKIP LOCKED
    )
    UPDATE public.account_deletion_requests t
    SET status = 'processing',
        attempts = t.attempts + 1,
        lease_expires_at = now() + make_interval(mins => GREATEST(COALESCE(p_lease_minutes, 30), 1))
    FROM due
    WHERE t.id = due.id
    RETURNING t.id, t.user_id, t.stage, t.attempts, t.locale;
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_account_purge(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req public.account_deletion_requests%ROWTYPE;
    v_uid uuid;
    v_email text;
    v_pos record;
    v_delete uuid[] := '{}';
    v_late uuid[] := '{}';
    v_former uuid[];
    v_hh uuid;
    v_member uuid;
    v_notice timestamptz;
    v_refs text[];
    v_id_refs text[];
    v_scope uuid[];
    v_lock_hhs uuid[];
    v_ledger_hhs uuid[];
    v_keep_pools uuid[];
    v_reowned uuid[];
    v_name text;
    v_name_re text;
    v_email_re text;
    v_ledger_before text;
    v_ledger_after text;
BEGIN
    PERFORM public.account_deletion_require_service();

    -- The user's lock, then the request row: the order account_deletion_cancel takes them in.
    SELECT * INTO v_req FROM public.account_deletion_requests WHERE id = p_request_id;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'Account deletion request not found' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_req.user_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('account_deletion:' || v_req.user_id::text, 0));
    END IF;
    SELECT * INTO v_req FROM public.account_deletion_requests WHERE id = p_request_id FOR UPDATE;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'Account deletion request not found' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;

    IF v_req.stage <> 'none' OR v_req.status = 'completed' THEN
        RETURN jsonb_build_object('prepared', true, 'deferred', false, 'already_prepared', true, 'stage', v_req.stage);
    END IF;

    -- Only a claimed, due job. A cancelled or unclaimed request never reaches the data.
    IF v_req.status <> 'processing' OR v_req.scheduled_for > now() THEN
        RAISE EXCEPTION 'This request is not due for purging' USING ERRCODE = '22023', HINT = 'purge_not_allowed';
    END IF;

    v_uid := v_req.user_id;

    -- Deleted out of band during grace: the FKs did the work.
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid) THEN
        UPDATE public.account_deletion_requests
        SET stage = 'db_prepared', last_error_code = NULL
        WHERE id = p_request_id;
        RETURN jsonb_build_object('prepared', true, 'deferred', false, 'user_missing', true, 'deleted_households', 0);
    END IF;

    -- Every household whose ledger the purge can reach: theirs, those of the pools they own
    -- (re-owned below), and those of the wife_personal rows deleted below. Pools, then
    -- households, then budgets, each by id: an expense locks its account (a BEFORE trigger),
    -- then its household (the foreign key), then its budget, so this order cannot deadlock with it.
    SELECT COALESCE(array_agg(DISTINCT s.household_id), '{}') INTO v_lock_hhs
    FROM (
        SELECT m.household_id FROM public.household_memberships m WHERE m.user_id = v_uid
        UNION ALL
        SELECT a.household_id FROM public.accounts a WHERE a.owner_user_id = v_uid AND a.is_shared_pool
        UNION ALL
        SELECT t.household_id FROM public.transactions t WHERE t.nafaqah_spouse_id = v_uid AND t.nafaqah_class = 'wife_personal'
    ) s;

    PERFORM 1 FROM public.accounts a WHERE a.is_shared_pool AND a.household_id = ANY (v_lock_hhs) ORDER BY a.id FOR UPDATE;

    PERFORM 1
    FROM public.households h
    WHERE h.id = ANY (v_lock_hhs)
    ORDER BY h.id
    FOR UPDATE;

    FOR v_pos IN
        SELECT p.household_id, p.member_position,
               (h.deletion_requested_by = v_uid AND h.deletion_scheduled_for IS NOT NULL) AS marked
        FROM public.account_deletion_household_positions(v_uid) p
        JOIN public.households h ON h.id = p.household_id
    LOOP
        IF v_pos.member_position = 'sole_member' OR COALESCE(v_pos.marked, false) THEN
            v_delete := v_delete || v_pos.household_id;
        ELSIF v_pos.member_position = 'primary_admin' THEN
            v_late := v_late || v_pos.household_id;
        END IF;
    END LOOP;

    -- Late-surfaced: never delete a household its members were not warned about.
    IF array_length(v_late, 1) IS NOT NULL THEN
        v_notice := now() + interval '7 days';
        UPDATE public.households h
        SET deletion_requested_at = COALESCE(h.deletion_requested_at, now()),
            deletion_scheduled_for = v_notice,
            deletion_requested_by = v_uid
        WHERE h.id = ANY (v_late)
           OR h.deletion_requested_by = v_uid;
        UPDATE public.account_deletion_requests
        SET status = 'scheduled',
            scheduled_for = v_notice,
            lease_expires_at = NULL,
            attempts = 0,
            last_error_code = NULL,
            notices_sent = '{}'
        WHERE id = p_request_id;
        RETURN jsonb_build_object('prepared', false, 'deferred', true,
                                  'scheduled_for', v_notice, 'households', to_jsonb(v_late));
    END IF;

    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;
    SELECT NULLIF(btrim(display_name), '') INTO v_name FROM public.users WHERE id = v_uid;
    -- The whole address or name, any case, never part of a longer one.
    IF v_email IS NOT NULL AND v_email <> '' THEN
        v_email_re := '(?<![[:alnum:]._%+-])' || regexp_replace(v_email, '([^[:alnum:][:space:]])', '\\\1', 'g')
                      || '(?![[:alnum:]_-]|\.[[:alnum:]])';
    END IF;
    IF v_name IS NOT NULL THEN
        v_name_re := '(?<![[:alnum:]_])' || regexp_replace(v_name, '([^[:alnum:][:space:]])', '\\\1', 'g') || '(?![[:alnum:]_])';
    END IF;

    -- What must not move: the surviving households the purge can reach, and nothing else, so
    -- another household's expense in the meantime is not mistaken for one. Locked above (pools
    -- and households); a pool made since is locked now, then the budgets, before the snapshot.
    SELECT COALESCE(array_agg(x), '{}') INTO v_ledger_hhs
    FROM unnest(v_lock_hhs) AS x
    WHERE NOT (x = ANY (v_delete));
    PERFORM 1 FROM public.accounts a WHERE a.is_shared_pool AND a.household_id = ANY (v_ledger_hhs) ORDER BY a.id FOR UPDATE;
    PERFORM 1 FROM public.budgets b WHERE b.household_id = ANY (v_ledger_hhs) ORDER BY b.id FOR UPDATE;

    -- A pool in a household with no other admin has nobody to go to.
    SELECT COALESCE(array_agg(a.id), '{}') INTO v_keep_pools
    FROM public.accounts a
    WHERE a.is_shared_pool
      AND a.household_id = ANY (v_ledger_hhs)
      AND (a.owner_user_id <> v_uid
           OR EXISTS (SELECT 1 FROM public.household_memberships o
                      WHERE o.household_id = a.household_id AND o.user_id <> v_uid AND o.role = 'admin'));
    SELECT COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.id = ANY (v_keep_pools)), '')
        || '|'
        || COALESCE((SELECT string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id)
                     FROM public.budgets b WHERE b.household_id = ANY (v_ledger_hhs)), '')
    INTO v_ledger_before;

    -- ── Storage queue, while the paths still exist ──────────────────────────
    INSERT INTO public.account_deletion_storage_queue (request_id, bucket, path, is_prefix)
    SELECT p_request_id, 'receipts', d || '/', true
    FROM unnest(v_delete) AS d
    ON CONFLICT (request_id, bucket, path) DO NOTHING;

    -- Their receipts in households that survive. Only inside the row's own household
    -- folder: receipt_url is client-influenced and must never reach another household.
    INSERT INTO public.account_deletion_storage_queue (request_id, bucket, path, is_prefix)
    SELECT DISTINCT p_request_id, 'receipts', q.path, false
    FROM (
        SELECT t.household_id,
               split_part(regexp_replace(t.receipt_url, '^.*/receipts/', ''), '?', 1) AS path
        FROM public.transactions t
        WHERE t.user_id = v_uid
          AND t.receipt_url IS NOT NULL
          AND NOT (t.household_id = ANY (v_delete))
    ) q
    WHERE q.path LIKE q.household_id::text || '/%'
      AND q.path NOT LIKE '%..%'
    ON CONFLICT (request_id, bucket, path) DO NOTHING;

    -- ── Households being deleted, in the fixed order ────────────────────────
    SELECT COALESCE(array_agg(DISTINCT m.user_id), '{}') INTO v_former
    FROM public.household_memberships m
    WHERE m.household_id = ANY (v_delete) AND m.user_id <> v_uid;

    FOREACH v_hh IN ARRAY v_delete LOOP
        DELETE FROM public.income_records WHERE household_id = v_hh;
        DELETE FROM public.account_transfers WHERE household_id = v_hh;
        DELETE FROM public.household_memberships WHERE household_id = v_hh AND role <> 'admin';
        DELETE FROM public.household_memberships WHERE household_id = v_hh;
        DELETE FROM public.households WHERE id = v_hh;
    END LOOP;

    FOREACH v_member IN ARRAY v_former LOOP
        PERFORM public.account_deletion_repoint_active_household(v_member);
    END LOOP;

    -- ── Households that survive ─────────────────────────────────────────────
    -- D5: before the membership trigger can declassify them into the budgets.
    DELETE FROM public.transactions
    WHERE nafaqah_spouse_id = v_uid AND nafaqah_class = 'wife_personal';

    -- Every pool they own, including in a household they already left.
    WITH reowned AS (
        UPDATE public.accounts a
        SET owner_user_id = n.user_id,
            updated_at = now()
        FROM (
            SELECT DISTINCT ON (o.household_id) o.household_id, o.user_id
            FROM public.household_memberships o
            WHERE o.user_id <> v_uid AND o.role = 'admin'
            ORDER BY o.household_id, public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
        ) n
        WHERE a.household_id = n.household_id
          AND a.owner_user_id = v_uid
          AND a.is_shared_pool
        RETURNING a.id
    )
    SELECT COALESCE(array_agg(id), '{}') INTO v_reowned FROM reowned;

    -- Its name now belongs to someone else's pool: their name goes from it.
    IF v_name_re IS NOT NULL THEN
        UPDATE public.accounts a
        SET name = regexp_replace(a.name, v_name_re, 'deleted_member', 'gi')
        WHERE a.id = ANY (v_reowned)
          AND a.name ~* v_name_re;
    END IF;

    -- What other rows may call them: their id, and any dependent claimed by them.
    SELECT array_agg(DISTINCT r) INTO v_refs
    FROM (
        SELECT v_uid::text AS r
        UNION ALL
        SELECT d.id::text FROM public.household_dependents d WHERE d.linked_user_id = v_uid
        UNION ALL
        SELECT lower(trim(d.name)) FROM public.household_dependents d WHERE d.linked_user_id = v_uid
    ) q;
    -- Ids mean them in any household. A dependent's name only means them in its own.
    SELECT array_agg(r) INTO v_id_refs
    FROM unnest(v_refs) AS r
    WHERE r ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    SELECT COALESCE(array_agg(DISTINCT s.household_id), '{}') INTO v_scope
    FROM (
        SELECT m.household_id FROM public.household_memberships m WHERE m.user_id = v_uid
        UNION ALL
        SELECT t.household_id FROM public.transactions t WHERE t.user_id = v_uid
        UNION ALL
        SELECT i.household_id FROM public.income_records i WHERE i.user_id = v_uid
        UNION ALL
        SELECT a.household_id FROM public.accounts a WHERE a.owner_user_id = v_uid
    ) s;

    -- Their own rows. Their name and address go from the merchant and the item names too.
    UPDATE public.transactions t
    SET notes = public.account_deletion_scrub_own_note(t.notes, v_refs),
        receipt_url = NULL,
        beneficiary_id = CASE WHEN lower(trim(t.beneficiary_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.beneficiary_id END,
        settlement_target_id = CASE WHEN lower(trim(t.settlement_target_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.settlement_target_id END,
        merchant = public.account_deletion_scrub_text(t.merchant, ARRAY[v_name_re, v_email_re]),
        items = public.account_deletion_scrub_item_names(public.account_deletion_scrub_items(t.items, v_refs), ARRAY[v_name_re, v_email_re]),
        line_items = public.account_deletion_scrub_item_names(public.account_deletion_scrub_items(t.line_items, v_refs), ARRAY[v_name_re, v_email_re])
    WHERE t.user_id = v_uid;

    -- Other members' rows anywhere that name them by id, including in a household they left
    -- where only others' rows mention them (v_scope below would not reach it).
    UPDATE public.transactions t
    SET notes = public.account_deletion_scrub_other_note(t.notes, v_id_refs),
        beneficiary_id = CASE WHEN lower(trim(t.beneficiary_id)) = ANY (v_id_refs) THEN 'deleted_member' ELSE t.beneficiary_id END,
        settlement_target_id = CASE WHEN lower(trim(t.settlement_target_id)) = ANY (v_id_refs) THEN 'deleted_member' ELSE t.settlement_target_id END,
        items = public.account_deletion_scrub_items(t.items, v_id_refs),
        line_items = public.account_deletion_scrub_items(t.line_items, v_id_refs)
    WHERE t.user_id IS DISTINCT FROM v_uid
      AND (lower(trim(t.beneficiary_id)) = ANY (v_id_refs)
           OR lower(trim(t.settlement_target_id)) = ANY (v_id_refs)
           OR public.account_deletion_scrub_other_note(t.notes, v_id_refs) IS DISTINCT FROM t.notes
           OR public.account_deletion_scrub_items(t.items, v_id_refs) IS DISTINCT FROM t.items
           OR public.account_deletion_scrub_items(t.line_items, v_id_refs) IS DISTINCT FROM t.line_items);

    -- Other members' rows in those households that name them, by id or by a claimed dependent's name.
    UPDATE public.transactions t
    SET notes = public.account_deletion_scrub_other_note(t.notes, v_refs),
        beneficiary_id = CASE WHEN lower(trim(t.beneficiary_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.beneficiary_id END,
        settlement_target_id = CASE WHEN lower(trim(t.settlement_target_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.settlement_target_id END,
        items = public.account_deletion_scrub_items(t.items, v_refs),
        line_items = public.account_deletion_scrub_items(t.line_items, v_refs)
    WHERE t.household_id = ANY (v_scope)
      AND t.user_id IS DISTINCT FROM v_uid
      AND (lower(trim(t.beneficiary_id)) = ANY (v_refs)
           OR lower(trim(t.settlement_target_id)) = ANY (v_refs)
           OR public.account_deletion_scrub_other_note(t.notes, v_refs) IS DISTINCT FROM t.notes
           OR public.account_deletion_scrub_items(t.items, v_refs) IS DISTINCT FROM t.items
           OR public.account_deletion_scrub_items(t.line_items, v_refs) IS DISTINCT FROM t.line_items);

    UPDATE public.installment_plans p
    SET notes = NULL
    FROM public.transactions t
    WHERE p.original_transaction_id = t.id AND t.user_id = v_uid AND p.notes IS NOT NULL;

    -- Income they recorded stays where it landed; its free text goes. title is free text too.
    UPDATE public.income_records
    SET notes = NULL,
        title = source_type
    WHERE user_id = v_uid;

    -- Whatever they still own after the re-own above goes, with its income.
    DELETE FROM public.income_records i
    USING public.accounts a
    WHERE i.account_id = a.id AND a.owner_user_id = v_uid;

    UPDATE public.account_transfers t
    SET notes = NULL
    WHERE t.user_id = v_uid
       OR t.from_account_id IN (SELECT a.id FROM public.accounts a WHERE a.owner_user_id = v_uid)
       OR t.to_account_id IN (SELECT a.id FROM public.accounts a WHERE a.owner_user_id = v_uid);

    DELETE FROM public.account_transfers t
    USING public.accounts f, public.accounts d
    WHERE t.from_account_id = f.id AND t.to_account_id = d.id
      AND f.owner_user_id = v_uid AND d.owner_user_id = v_uid;

    DELETE FROM public.accounts WHERE owner_user_id = v_uid;

    UPDATE public.spouse_reimbursements
    SET notes = NULL
    WHERE (paid_by_user_id = v_uid OR recorded_by = v_uid) AND notes IS NOT NULL;

    -- The real name stays on a linked dependent row, and its targeted invites cascade.
    DELETE FROM public.household_dependents WHERE linked_user_id = v_uid;

    -- The leave itself. Fires the Nafaqah, provider, primary admin and mark triggers.
    DELETE FROM public.household_memberships WHERE user_id = v_uid;

    DELETE FROM public.invite_attempt_log WHERE user_id = v_uid;

    DELETE FROM public.inquiries i
    WHERE i.name = 'User ' || v_uid::text
       OR i.email = v_uid::text || '@auth.internal'
       OR (v_email IS NOT NULL AND lower(i.email) = v_email);

    -- Their address, wherever it still is in public, other members' text included. Their
    -- display name stays in others' text: a common name could be anyone's.
    PERFORM public.account_deletion_replace_everywhere(v_email, v_email_re);

    -- The shell the Auth Admin delete will cascade from.
    UPDATE public.users
    SET display_name = 'deleted_member',
        household_id = NULL,
        role = 'member',
        financial_role = NULL
    WHERE id = v_uid;

    -- ── The invariant ───────────────────────────────────────────────────────
    SELECT COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.id = ANY (v_keep_pools)), '')
        || '|'
        || COALESCE((SELECT string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id)
                     FROM public.budgets b WHERE b.household_id = ANY (v_ledger_hhs)), '')
    INTO v_ledger_after;
    IF v_ledger_after IS DISTINCT FROM v_ledger_before THEN
        RAISE EXCEPTION 'A surviving pool balance or budget would have moved; nothing was purged'
            USING ERRCODE = '23514', HINT = 'purge_ledger_invariant';
    END IF;

    UPDATE public.account_deletion_requests
    SET stage = 'db_prepared', last_error_code = NULL
    WHERE id = p_request_id;

    RETURN jsonb_build_object('prepared', true, 'deferred', false,
                              'deleted_households', COALESCE(array_length(v_delete, 1), 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.list_account_purge_storage(p_request_id uuid)
RETURNS TABLE(bucket text, path text, is_prefix boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    RETURN QUERY
    SELECT q.bucket, q.path, q.is_prefix
    FROM public.account_deletion_storage_queue q
    WHERE q.request_id = p_request_id
    ORDER BY q.bucket, q.path;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_account_purge_storage_done(p_request_id uuid)
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
    IF v_req.stage = 'none' THEN
        RAISE EXCEPTION 'Storage cannot be marked done before the database is prepared'
            USING ERRCODE = '22023', HINT = 'purge_stage_invalid';
    END IF;

    DELETE FROM public.account_deletion_storage_queue WHERE request_id = p_request_id;
    IF v_req.stage = 'db_prepared' THEN
        UPDATE public.account_deletion_requests SET stage = 'storage_done' WHERE id = p_request_id;
    END IF;
END;
$$;

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

    UPDATE public.account_deletion_requests
    SET status = 'completed',
        completed_at = now(),
        user_id = NULL,
        reason = NULL,
        lease_expires_at = NULL,
        last_error_code = NULL
    WHERE id = p_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_account_purge_failure(p_request_id uuid, p_error_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req public.account_deletion_requests%ROWTYPE;
    v_code text := CASE WHEN p_error_code ~ '^[a-z0-9_]{1,64}$' THEN p_error_code ELSE 'unknown_error' END;
    v_next timestamptz;
BEGIN
    PERFORM public.account_deletion_require_service();

    SELECT * INTO v_req FROM public.account_deletion_requests WHERE id = p_request_id FOR UPDATE;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'Account deletion request not found' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_req.status <> 'processing' THEN
        RETURN jsonb_build_object('status', v_req.status, 'attempts', v_req.attempts);
    END IF;

    IF v_req.attempts >= 5 THEN
        UPDATE public.account_deletion_requests
        SET status = 'failed', lease_expires_at = NULL, last_error_code = v_code
        WHERE id = p_request_id;
        RETURN jsonb_build_object('status', 'failed', 'attempts', v_req.attempts);
    END IF;

    v_next := now() + LEAST(interval '1 hour' * power(2, GREATEST(v_req.attempts - 1, 0)), interval '24 hours');
    UPDATE public.account_deletion_requests
    SET lease_expires_at = v_next, last_error_code = v_code
    WHERE id = p_request_id;
    RETURN jsonb_build_object('status', 'processing', 'attempts', v_req.attempts, 'next_attempt_at', v_next);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_account_deletion_notices_due()
RETURNS TABLE(request_id uuid, user_id uuid, notice text, locale text, scheduled_for timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    RETURN QUERY
    -- The account holder at T-7 and T-1.
    SELECT r.id, r.user_id,
           CASE WHEN r.scheduled_for <= now() + interval '1 day' THEN 'holder_t1' ELSE 'holder_t7' END,
           r.locale, r.scheduled_for
    FROM public.account_deletion_requests r
    WHERE r.status = 'scheduled'
      AND r.scheduled_for <= now() + interval '7 days'
      AND NOT ((CASE WHEN r.scheduled_for <= now() + interval '1 day' THEN 'holder_t1' ELSE 'holder_t7' END) = ANY (r.notices_sent))
    UNION ALL
    -- Sent before the Auth delete takes the address away, once the database work is done.
    SELECT r.id, r.user_id, 'holder_completion', r.locale, r.scheduled_for
    FROM public.account_deletion_requests r
    WHERE r.stage <> 'none'
      AND r.status = 'processing'
      AND NOT ('holder_completion' = ANY (r.notices_sent))
      AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = r.user_id)
    UNION ALL
    -- Other members of a marked household: when marked, and at T-7.
    SELECT r.id, m.user_id, n.notice, r.locale, h.deletion_scheduled_for
    FROM public.account_deletion_requests r
    JOIN public.households h ON h.deletion_requested_by = r.user_id AND h.deletion_scheduled_for IS NOT NULL
    JOIN public.household_memberships m ON m.household_id = h.id AND m.user_id <> r.user_id
    CROSS JOIN LATERAL (
        SELECT CASE WHEN h.deletion_scheduled_for <= now() + interval '7 days' AND 'member_marked' = ANY (r.notices_sent)
                    THEN 'member_t7' ELSE 'member_marked' END AS notice
    ) n
    WHERE r.status = 'scheduled'
      AND NOT (n.notice = ANY (r.notices_sent))
      AND (n.notice <> 'member_t7' OR h.deletion_scheduled_for > now() + interval '1 day');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_account_deletion_notice_sent(p_request_id uuid, p_notice text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();

    IF p_notice IS NULL OR p_notice NOT IN ('holder_t7', 'holder_t1', 'holder_completion', 'member_marked', 'member_t7') THEN
        RAISE EXCEPTION 'Unknown notice' USING ERRCODE = '22023';
    END IF;

    UPDATE public.account_deletion_requests
    SET notices_sent = array_append(notices_sent, p_notice)
    WHERE id = p_request_id
      AND NOT (p_notice = ANY (notices_sent));

    -- A first notice sent inside the last 7 days already says the date.
    IF p_notice = 'member_marked' THEN
        UPDATE public.account_deletion_requests
        SET notices_sent = array_append(notices_sent, 'member_t7')
        WHERE id = p_request_id
          AND scheduled_for <= now() + interval '7 days'
          AND NOT ('member_t7' = ANY (notices_sent));
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_account_deletion_worker_run(
    p_started_at timestamptz,
    p_claimed integer,
    p_completed integer,
    p_failed integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    INSERT INTO public.account_deletion_worker_runs (started_at, claimed, completed, failed)
    VALUES (COALESCE(p_started_at, now()), COALESCE(p_claimed, 0), COALESCE(p_completed, 0), COALESCE(p_failed, 0));
END;
$$;

-- ── Privileges ───────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.account_deletion_require_service() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_repoint_active_household(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_note_token(text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_scrub_own_note(text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_scrub_other_note(text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_scrub_items(jsonb, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_scrub_text(text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_scrub_item_names(jsonb, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_replace_everywhere(text, text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.claim_due_account_deletions(integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prepare_account_purge(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_account_purge_storage(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_account_purge_storage_done(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_account_purge(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_account_purge_failure(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_account_deletion_notices_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_account_deletion_notice_sent(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_account_deletion_worker_run(timestamptz, integer, integer, integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_due_account_deletions(integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.prepare_account_purge(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_account_purge_storage(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_account_purge_storage_done(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_purge(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_account_purge_failure(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_account_deletion_notices_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_account_deletion_notice_sent(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_account_deletion_worker_run(timestamptz, integer, integer, integer) TO service_role;

COMMIT;
