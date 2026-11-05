-- ============================================================================
-- Test 45: a notice is offered only while it still means something
--
-- Migration: 20261105000900_account_deletion_notice_windows.sql
--
-- ACCOUNT_DELETION_EMAILS_ENABLED can be off for weeks, and notices are not marked sent
-- while it is. Turning it on must not produce a burst of stale reminders. Verifies, at
-- each distance from the date, what the worker would be offered with nothing sent yet:
--   holder:  more than 7 days, nothing; 7 to 2 days, T-7; 2 to 1 days, nothing;
--            1 day to 1 hour, T-1; under an hour or past, nothing. Never both.
--   member:  the first notice until an hour before; T-7 only after it, and only while
--            more than 2 days remain.
--   A cancelled request is offered nothing. holder_completion is unchanged.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e4500000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION '%: got %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.req(p_user int, p_in interval, p_sent text[] DEFAULT '{}') RETURNS uuid LANGUAGE sql
AS $$
    INSERT INTO public.account_deletion_requests (user_id, scheduled_for, locale, notices_sent)
    VALUES (pg_temp.u(p_user), now() + p_in, 'en', p_sent)
    RETURNING id
$$;

CREATE FUNCTION pg_temp.due(p_id uuid) RETURNS text LANGUAGE sql
AS $$
    SELECT COALESCE(string_agg(notice, ',' ORDER BY notice), 'none')
    FROM public.list_account_deletion_notices_due() WHERE request_id = p_id
$$;

DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't45-' || n || '@test.local', jsonb_build_object('display_name', 'T45 User ' || n)
    FROM generate_series(1, 30) AS n;
END $$;

-- Holder ---------------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('25 days out', pg_temp.due(pg_temp.req(1, interval '25 days')), 'none');
    PERFORM pg_temp.expect('just over 7 days', pg_temp.due(pg_temp.req(2, interval '7 days 1 hour')), 'none');
    PERFORM pg_temp.expect('just under 7 days', pg_temp.due(pg_temp.req(3, interval '6 days 23 hours')), 'holder_t7');
    PERFORM pg_temp.expect('3 days out, T-7 was missed but still helps', pg_temp.due(pg_temp.req(4, interval '3 days')), 'holder_t7');
    PERFORM pg_temp.expect('2 days and an hour', pg_temp.due(pg_temp.req(5, interval '2 days 1 hour')), 'holder_t7');
    PERFORM pg_temp.expect('just under 2 days: T-7 is stale, T-1 is coming', pg_temp.due(pg_temp.req(6, interval '47 hours')), 'none');
    PERFORM pg_temp.expect('just over 1 day', pg_temp.due(pg_temp.req(7, interval '25 hours')), 'none');
    PERFORM pg_temp.expect('just under 1 day', pg_temp.due(pg_temp.req(8, interval '23 hours')), 'holder_t1');
    PERFORM pg_temp.expect('2 hours out', pg_temp.due(pg_temp.req(9, interval '2 hours')), 'holder_t1');
    PERFORM pg_temp.expect('30 minutes out: the purge is next', pg_temp.due(pg_temp.req(10, interval '30 minutes')), 'none');
    PERFORM pg_temp.expect('past', pg_temp.due(pg_temp.req(11, interval '-1 hour')), 'none');
    PERFORM pg_temp.expect('T-7 already sent', pg_temp.due(pg_temp.req(12, interval '3 days', '{holder_t7}')), 'none');
    PERFORM pg_temp.expect('T-1 already sent', pg_temp.due(pg_temp.req(13, interval '12 hours', '{holder_t7,holder_t1}')), 'none');
    PERFORM pg_temp.expect('T-7 never sent, T-1 alone', pg_temp.due(pg_temp.req(14, interval '12 hours', '{}')), 'holder_t1');

    UPDATE public.account_deletion_requests SET status = 'cancelled' WHERE user_id = pg_temp.u(3);
    PERFORM pg_temp.expect('cancelled is offered nothing',
        (SELECT count(*)::text FROM public.list_account_deletion_notices_due() WHERE user_id = pg_temp.u(3)), '0');
    RAISE NOTICE 'PASSED: an account holder is offered one meaningful reminder at a time.';
END $$;

-- Members --------------------------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    n int := 0;
    v_case record;
BEGIN
    FOR v_case IN
        SELECT * FROM (VALUES
            (interval '25 days',  '{}'::text[],        'none', 'member_marked'),
            (interval '6 days',   '{}'::text[],        'holder_t7', 'member_marked'),
            (interval '3 hours',  '{}'::text[],        'holder_t1', 'member_marked'),
            (interval '30 minutes', '{}'::text[],      'none', 'none'),
            (interval '-1 hour',  '{}'::text[],        'none', 'none'),
            (interval '6 days',   '{member_marked}'::text[], 'holder_t7', 'member_t7'),
            (interval '3 days',   '{member_marked}'::text[], 'holder_t7', 'member_t7'),
            (interval '36 hours', '{member_marked}'::text[], 'none', 'none'),
            (interval '12 hours', '{member_marked}'::text[], 'holder_t1', 'none'),
            (interval '6 days',   '{member_marked,member_t7}'::text[], 'holder_t7', 'none')
        ) AS t(away, sent, holder_wants, member_wants)
    LOOP
        n := n + 1;
        INSERT INTO public.households (id, name, invite_code, household_type)
        VALUES (('e45a0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'T45 H' || n, 'T45CODE' || lpad(n::text, 9, '0'), 'roommates');
        -- Member 30 is in every one of these households, from before the mark.
        INSERT INTO public.household_memberships (household_id, user_id, role, financial_role)
        VALUES (('e45a0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, pg_temp.u(30), 'member', 'peer');
        v_id := pg_temp.req(15 + n, v_case.away, v_case.sent);
        UPDATE public.households
        SET deletion_requested_at = now(), deletion_scheduled_for = now() + v_case.away, deletion_requested_by = pg_temp.u(15 + n)
        WHERE id = ('e45a0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;

        PERFORM pg_temp.expect(format('member, %s away, sent %s', v_case.away, v_case.sent),
            (SELECT COALESCE(string_agg(notice, ','), 'none') FROM public.list_account_deletion_notices_due()
             WHERE request_id = v_id AND user_id = pg_temp.u(30)),
            v_case.member_wants);
        PERFORM pg_temp.expect(format('holder, %s away, sent %s', v_case.away, v_case.sent),
            (SELECT COALESCE(string_agg(notice, ','), 'none') FROM public.list_account_deletion_notices_due()
             WHERE request_id = v_id AND user_id = pg_temp.u(15 + n)),
            v_case.holder_wants);
    END LOOP;
    RAISE NOTICE 'PASSED: a member is offered the first notice, then T-7 only while it helps.';
END $$;

-- The operator alerts and the completion row are untouched -------------------------------
DO $$
DECLARE
    v_id uuid;
BEGIN
    v_id := pg_temp.req(1 + 14, interval '-1 hour');
    UPDATE public.account_deletion_requests SET status = 'processing', stage = 'db_prepared' WHERE id = v_id;
    PERFORM pg_temp.expect('completion still offered', pg_temp.due(v_id), 'holder_completion');
    RAISE NOTICE 'PASSED: the completion row is unchanged.';
END $$;

ROLLBACK;
