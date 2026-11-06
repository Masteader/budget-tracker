-- ============================================================================
-- Migration: 20261105001200_account_deletion_former_member_debt.sql
-- Proof test: supabase/tests/54_former_member_debt.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- When a wife deletes her account, her Nafaqah ledger goes (remove_nafaqah_ledger_on_membership_end,
-- through the purge's leave). What the husband still owed her for shared things she paid is a debt
-- that does not end with her account (owner decision 2026-11-06):
--
--   1. While her request is scheduled, the creditor is told the amount: by email through the
--      deletion notice path (list_former_member_debt_notices_due, notice 'creditor_owed', marked
--      with mark_account_deletion_notice_sent, both email switches as for every other notice), and
--      in the app (get_former_member_debt_deletion_notices). The creditor is the household's Nafaqah
--      provider (nafaqah_husband_id), or its admins when there is none.
--   2. At the purge, before her membership ends, each surviving household where the outstanding
--      amount (her wife_reimbursable advances there less the repayments) is above zero keeps ONE
--      record: former_member_debts. No name, id, email or free text of hers.
--   3. The provider or any admin (co-admins included) closes it: record_former_member_debt_payment
--      (amount up to what remains, plus a payment method, exactly as record_spouse_reimbursement
--      takes them) or waive_former_member_debt (her release, إبراء). Like an ordinary reimbursement,
--      neither touches an account, a budget or a transaction: only these two tables change.
--      Both lock the record row and take a client request key, so a double tap records once.
--   4. Members read both tables under the reimbursement ledger's rule (their active household). No
--      client writes them.
--
-- The husband deleting his account later: a surviving household keeps the record and his id leaves
-- it (recorded_by ON DELETE SET NULL); a household deleted with him takes it along (CASCADE).
--
-- Replaces two existing functions, with the same signatures:
--   prepare_account_purge             (000300) + the snapshot, before the leave
--   mark_account_deletion_notice_sent (000400) + 'creditor_owed'
-- So re-running 000300 or 000400 after this file puts their versions back: run this file again.
-- It is safe to run again (IF NOT EXISTS, CREATE OR REPLACE, DROP POLICY IF EXISTS).
--
-- Lock order. prepare_account_purge holds the household rows FOR UPDATE when it takes the snapshot,
-- and every write to spouse_reimbursements or transactions of that household needs a KEY SHARE lock
-- on that row, so the amount cannot change under it. It does not take the spouse_reimbursement
-- advisory lock: record_spouse_reimbursement takes that lock before the household's, and taking
-- them in the other order here could deadlock. The payment and waiver RPCs lock only the record
-- row; the events table has no household column, so they never wait on the household while holding
-- it, and a purge deleting the household waits for them.
--
-- Rollback (one transaction), after rolling back the app and the API:
--   1. Run prepare_account_purge's CREATE OR REPLACE statement from 000300 and
--      mark_account_deletion_notice_sent's from 000400.
--   2. DROP FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid),
--        public.waive_former_member_debt(uuid, uuid, uuid, uuid),
--        public.get_former_member_debt_deletion_notices(uuid, uuid),
--        public.list_former_member_debt_notices_due(),
--        public.account_deletion_snapshot_former_member_debts(uuid),
--        public.former_member_debt_require_manager(uuid, uuid),
--        public.former_member_debt_creditors(uuid, uuid),
--        public.former_member_debt_outstanding(uuid, uuid);
--      DROP TABLE public.former_member_debt_events, public.former_member_debts;
--   Data lost: every kept record and its history.
-- ============================================================================

BEGIN;

-- 1. Tables ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.former_member_debts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    original_amount numeric(14, 2) NOT NULL CHECK (original_amount > 0),
    paid_amount numeric(14, 2) NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'settled', 'waived')),
    created_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    CONSTRAINT former_member_debts_paid_range CHECK (paid_amount >= 0 AND paid_amount <= original_amount),
    CONSTRAINT former_member_debts_closed_at CHECK ((status = 'open') = (closed_at IS NULL)),
    CONSTRAINT former_member_debts_open_owes CHECK (status <> 'open' OR paid_amount < original_amount),
    CONSTRAINT former_member_debts_settled_paid CHECK (status <> 'settled' OR paid_amount = original_amount),
    CONSTRAINT former_member_debts_waived_owed CHECK (status <> 'waived' OR paid_amount < original_amount)
);

CREATE INDEX IF NOT EXISTS idx_former_member_debts_household
    ON public.former_member_debts (household_id, created_at DESC);

COMMENT ON TABLE public.former_member_debts IS
    'What the husband still owed a wife when her account was deleted: one anonymised record per household, '
    'kept by prepare_account_purge. Closed only through record_former_member_debt_payment or waive_former_member_debt.';

CREATE TABLE IF NOT EXISTS public.former_member_debt_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id uuid NOT NULL REFERENCES public.former_member_debts(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('payment', 'waiver')),
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    payment_method text CHECK (payment_method IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other')),
    remaining_after numeric(14, 2) NOT NULL CHECK (remaining_after >= 0),
    recorded_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    request_key uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT former_member_debt_events_method CHECK ((kind = 'payment') = (payment_method IS NOT NULL)),
    CONSTRAINT former_member_debt_events_waiver_closes CHECK (kind <> 'waiver' OR remaining_after = 0),
    CONSTRAINT uq_former_member_debt_events_request UNIQUE (debt_id, request_key)
);

CREATE INDEX IF NOT EXISTS idx_former_member_debt_events_debt
    ON public.former_member_debt_events (debt_id, created_at);
CREATE INDEX IF NOT EXISTS idx_former_member_debt_events_recorded_by
    ON public.former_member_debt_events (recorded_by);

COMMENT ON TABLE public.former_member_debt_events IS
    'Payments and the waiver of a former_member_debts record. Append-only, through the two RPCs. '
    'request_key is the client''s idempotency key.';

ALTER TABLE public.former_member_debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.former_member_debt_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.former_member_debts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.former_member_debt_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.former_member_debts TO authenticated;
GRANT SELECT ON public.former_member_debt_events TO authenticated;
GRANT ALL ON public.former_member_debts TO service_role;
GRANT ALL ON public.former_member_debt_events TO service_role;

-- The reimbursement ledger's read rule (spouse_reimbursements_select_household).
DROP POLICY IF EXISTS former_member_debts_select_household ON public.former_member_debts;
CREATE POLICY former_member_debts_select_household ON public.former_member_debts
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS former_member_debt_events_select_household ON public.former_member_debt_events;
CREATE POLICY former_member_debt_events_select_household ON public.former_member_debt_events
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.former_member_debts d
        WHERE d.id = former_member_debt_events.debt_id
          AND d.household_id = (SELECT public.get_auth_user_household_id())
    ));

-- 2. Helpers (no client executes them) ---------------------------------------------

-- What the husband owes this wife in this household now: her advances less the repayments.
CREATE OR REPLACE FUNCTION public.former_member_debt_outstanding(p_household_id uuid, p_wife_user_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT GREATEST(
        (SELECT COALESCE(sum(t.amount), 0) FROM public.transactions t
         WHERE t.household_id = p_household_id
           AND t.nafaqah_spouse_id = p_wife_user_id
           AND t.nafaqah_class = 'wife_reimbursable')
      - (SELECT COALESCE(sum(r.amount), 0) FROM public.spouse_reimbursements r
         WHERE r.household_id = p_household_id AND r.wife_user_id = p_wife_user_id),
        0)::numeric(14, 2);
$$;

-- Who is told what a leaving wife is owed: the husband, or the admins when the household has none.
-- Never the wife herself.
CREATE OR REPLACE FUNCTION public.former_member_debt_creditors(p_household_id uuid, p_wife_user_id uuid)
RETURNS SETOF uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_husband uuid := public.nafaqah_husband_id(p_household_id);
BEGIN
    IF v_husband IS NOT NULL AND v_husband IS DISTINCT FROM p_wife_user_id THEN
        RETURN NEXT v_husband;
        RETURN;
    END IF;
    RETURN QUERY
    SELECT m.user_id FROM public.household_memberships m
    WHERE m.household_id = p_household_id AND m.role = 'admin' AND m.user_id <> p_wife_user_id
    ORDER BY m.user_id;
END;
$$;

-- The husband (the household's provider) or an admin of the household; anyone else is refused.
CREATE OR REPLACE FUNCTION public.former_member_debt_require_manager(p_household_id uuid, p_actor uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        JOIN public.households h ON h.id = m.household_id
        WHERE m.household_id = p_household_id
          AND m.user_id = p_actor
          AND (m.role = 'admin' OR h.nafaqah_provider_user_id = p_actor)
    ) THEN
        RAISE EXCEPTION 'Forbidden: only the husband or a household admin can close this record'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
END;
$$;

-- Called by prepare_account_purge before her memberships end. One record per household she is
-- still in where something is owed. Returns how many were kept.
CREATE OR REPLACE FUNCTION public.account_deletion_snapshot_former_member_debts(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_kept integer;
BEGIN
    PERFORM public.account_deletion_require_service();
    INSERT INTO public.former_member_debts (household_id, original_amount)
    SELECT o.household_id, o.outstanding
    FROM (
        SELECT m.household_id, public.former_member_debt_outstanding(m.household_id, p_user_id) AS outstanding
        FROM public.household_memberships m
        WHERE m.user_id = p_user_id
    ) o
    WHERE o.outstanding > 0
    ORDER BY o.household_id;
    GET DIAGNOSTICS v_kept = ROW_COUNT;
    RETURN v_kept;
END;
$$;

-- 3. Before the deletion ----------------------------------------------------------

-- The worker's 'creditor_owed' emails: one per scheduled request, to each creditor, with the
-- amount owed across the households they share with her. Sent while more than an hour remains,
-- marked once with mark_account_deletion_notice_sent. Not for a household she is deleting herself.
-- locale is NULL: the creditor has no stored language, and the email is in all three.
CREATE OR REPLACE FUNCTION public.list_former_member_debt_notices_due()
RETURNS TABLE(request_id uuid, user_id uuid, notice text, locale text, scheduled_for timestamptz, amount numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    RETURN QUERY
    SELECT o.request_id, c.creditor, 'creditor_owed'::text, NULL::text, o.scheduled_for, sum(o.outstanding)::numeric(14, 2)
    FROM (
        SELECT r.id AS request_id, r.user_id AS wife, r.scheduled_for, m.household_id,
               public.former_member_debt_outstanding(m.household_id, r.user_id) AS outstanding
        FROM public.account_deletion_requests r
        JOIN public.household_memberships m ON m.user_id = r.user_id
        JOIN public.households h ON h.id = m.household_id
        WHERE r.status = 'scheduled'
          AND r.scheduled_for >= now() + interval '1 hour'
          AND NOT ('creditor_owed' = ANY (r.notices_sent))
          AND h.deletion_requested_by IS DISTINCT FROM r.user_id
    ) o
    CROSS JOIN LATERAL public.former_member_debt_creditors(o.household_id, o.wife) AS c(creditor)
    WHERE o.outstanding > 0
    GROUP BY o.request_id, c.creditor, o.scheduled_for;
END;
$$;

-- The in-app notice: wives of this household whose deletion is pending, with what is owed to each.
-- Rows only for a creditor of the household; other members get none. Acts as auth.uid(), or the
-- verified caller the API passes under the service role.
CREATE OR REPLACE FUNCTION public.get_former_member_debt_deletion_notices(
    p_household_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS TABLE(wife_user_id uuid, scheduled_for timestamptz, outstanding numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    RETURN QUERY
    SELECT o.wife, o.scheduled_for, o.outstanding
    FROM (
        SELECT m.user_id AS wife, r.scheduled_for,
               public.former_member_debt_outstanding(p_household_id, m.user_id) AS outstanding
        FROM public.household_memberships m
        JOIN public.account_deletion_requests r ON r.user_id = m.user_id AND r.status IN ('scheduled', 'processing')
        JOIN public.households h ON h.id = m.household_id
        WHERE m.household_id = p_household_id
          AND m.user_id <> v_actor
          AND h.deletion_requested_by IS DISTINCT FROM m.user_id
    ) o
    WHERE o.outstanding > 0
      AND v_actor IN (SELECT c FROM public.former_member_debt_creditors(p_household_id, o.wife) AS c)
    ORDER BY o.scheduled_for, o.wife;
END;
$$;

-- Same function as 000400, with 'creditor_owed' added to the accepted names.
CREATE OR REPLACE FUNCTION public.mark_account_deletion_notice_sent(p_request_id uuid, p_notice text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();

    IF p_notice IS NULL OR p_notice NOT IN ('holder_t7', 'holder_t1', 'holder_completion', 'member_marked', 'member_t7',
                                            'ops_failed', 'ops_overdue', 'creditor_owed') THEN
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

-- 4. Closing a record ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_former_member_debt_payment(
    p_household_id uuid,
    p_debt_id uuid,
    p_amount numeric,
    p_payment_method text DEFAULT 'cash',
    p_request_key uuid DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_debt public.former_member_debts%ROWTYPE;
    v_event public.former_member_debt_events%ROWTYPE;
    v_method text := lower(COALESCE(NULLIF(trim(p_payment_method), ''), 'cash'));
    v_remaining numeric(14, 2);
BEGIN
    PERFORM public.former_member_debt_require_manager(p_household_id, v_actor);
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    SELECT * INTO v_debt FROM public.former_member_debts
    WHERE id = p_debt_id AND household_id = p_household_id
    FOR UPDATE;
    IF v_debt.id IS NULL THEN
        RAISE EXCEPTION 'No such record in this household' USING ERRCODE = 'P0002', HINT = 'debt_not_found';
    END IF;

    -- The same tap again: answer as the first time, change nothing.
    SELECT * INTO v_event FROM public.former_member_debt_events
    WHERE debt_id = p_debt_id AND request_key = p_request_key;
    IF v_event.id IS NOT NULL THEN
        IF v_event.kind <> 'payment' THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'replayed', true, 'event_id', v_event.id, 'debt_id', v_debt.id,
            'amount', v_event.amount, 'payment_method', v_event.payment_method,
            'remaining', v_event.remaining_after, 'status', v_debt.status);
    END IF;

    IF v_debt.status <> 'open' THEN
        RAISE EXCEPTION 'This record is already closed' USING ERRCODE = '22023', HINT = 'debt_closed';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'A payment is a positive SAR amount with at most 2 decimals' USING ERRCODE = '22023', HINT = 'invalid_amount';
    END IF;
    IF v_method NOT IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method %', v_method USING ERRCODE = '22023', HINT = 'invalid_payment_method';
    END IF;

    v_remaining := v_debt.original_amount - v_debt.paid_amount;
    IF p_amount > v_remaining THEN
        RAISE EXCEPTION 'Payment of % exceeds the remaining % SAR', p_amount, v_remaining
            USING ERRCODE = '22023', HINT = 'overpayment';
    END IF;

    UPDATE public.former_member_debts
    SET paid_amount = paid_amount + p_amount,
        status = CASE WHEN p_amount = v_remaining THEN 'settled' ELSE 'open' END,
        closed_at = CASE WHEN p_amount = v_remaining THEN now() END
    WHERE id = p_debt_id
    RETURNING * INTO v_debt;

    INSERT INTO public.former_member_debt_events (debt_id, kind, amount, payment_method, remaining_after, recorded_by, request_key)
    VALUES (p_debt_id, 'payment', p_amount, v_method, v_remaining - p_amount, v_actor, p_request_key)
    RETURNING * INTO v_event;

    RETURN jsonb_build_object(
        'success', true, 'replayed', false, 'event_id', v_event.id, 'debt_id', v_debt.id,
        'amount', v_event.amount, 'payment_method', v_event.payment_method,
        'remaining', v_event.remaining_after, 'status', v_debt.status);
END;
$$;

CREATE OR REPLACE FUNCTION public.waive_former_member_debt(
    p_household_id uuid,
    p_debt_id uuid,
    p_request_key uuid DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_debt public.former_member_debts%ROWTYPE;
    v_event public.former_member_debt_events%ROWTYPE;
    v_remaining numeric(14, 2);
BEGIN
    PERFORM public.former_member_debt_require_manager(p_household_id, v_actor);
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    SELECT * INTO v_debt FROM public.former_member_debts
    WHERE id = p_debt_id AND household_id = p_household_id
    FOR UPDATE;
    IF v_debt.id IS NULL THEN
        RAISE EXCEPTION 'No such record in this household' USING ERRCODE = 'P0002', HINT = 'debt_not_found';
    END IF;

    SELECT * INTO v_event FROM public.former_member_debt_events
    WHERE debt_id = p_debt_id AND request_key = p_request_key;
    IF v_event.id IS NOT NULL THEN
        IF v_event.kind <> 'waiver' THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'replayed', true, 'event_id', v_event.id, 'debt_id', v_debt.id,
            'waived_amount', v_event.amount, 'remaining', v_event.remaining_after, 'status', v_debt.status);
    END IF;

    IF v_debt.status <> 'open' THEN
        RAISE EXCEPTION 'This record is already closed' USING ERRCODE = '22023', HINT = 'debt_closed';
    END IF;

    v_remaining := v_debt.original_amount - v_debt.paid_amount;
    UPDATE public.former_member_debts
    SET status = 'waived', closed_at = now()
    WHERE id = p_debt_id
    RETURNING * INTO v_debt;

    INSERT INTO public.former_member_debt_events (debt_id, kind, amount, payment_method, remaining_after, recorded_by, request_key)
    VALUES (p_debt_id, 'waiver', v_remaining, NULL, 0, v_actor, p_request_key)
    RETURNING * INTO v_event;

    RETURN jsonb_build_object(
        'success', true, 'replayed', false, 'event_id', v_event.id, 'debt_id', v_debt.id,
        'waived_amount', v_event.amount, 'remaining', 0::numeric(14, 2), 'status', v_debt.status);
END;
$$;

-- 5. The purge: same function as 000300, with the snapshot before the leave ----------
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

    -- What the husband still owes her stays with each surviving household (one anonymised record
    -- each), taken before anything below touches her rows and before the leave removes her ledger.
    -- The households are locked above, so the amount cannot change under it.
    PERFORM public.account_deletion_snapshot_former_member_debts(v_uid);

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

-- 6. Privileges --------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.former_member_debt_outstanding(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.former_member_debt_creditors(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.former_member_debt_require_manager(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_snapshot_former_member_debts(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_former_member_debt_notices_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_former_member_debt_deletion_notices(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.waive_former_member_debt(uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
-- As 000300 and 000400 left them.
REVOKE ALL ON FUNCTION public.prepare_account_purge(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_account_deletion_notice_sent(uuid, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.list_former_member_debt_notices_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_former_member_debt_deletion_notices(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.waive_former_member_debt(uuid, uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_account_purge(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_account_deletion_notice_sent(uuid, text) TO service_role;

COMMIT;
