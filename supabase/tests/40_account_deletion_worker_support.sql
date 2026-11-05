-- ============================================================================
-- Test 40: read-only queue summary, operator alerts and inquiry retention
--
-- Migration: 20261105000400_account_deletion_worker_support.sql
--
-- Verifies:
--   1. get_account_deletion_queue_summary counts due, in-progress, failed and overdue
--      jobs and changes nothing, so the worker can report while disabled.
--   2. list_account_deletion_alerts_due lists a failed and an overdue job once each,
--      and carries no user id.
--   3. purge_expired_account_deletion_inquiries removes only account_deletion rows
--      older than the retention period.
--   4. All three are service-only and refuse a caller with a JWT subject.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.call(p_role text, p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
BEGIN
    PERFORM set_config('request.jwt.claims',
        CASE WHEN p_sub IS NULL THEN json_build_object('role', p_role)::text
             ELSE json_build_object('sub', p_sub, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(text, text, text) TO PUBLIC;

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

-- 1. Summary -------------------------------------------------------------------------
DO $$
DECLARE
    v_before text;
    v_sum jsonb;
BEGIN
    DELETE FROM public.account_deletion_requests;
    INSERT INTO public.account_deletion_requests (id, user_id, status, stage, scheduled_for, lease_expires_at) VALUES
        ('e4000000-0000-0000-0000-000000000001', gen_random_uuid(), 'scheduled', 'none', now() + interval '10 days', NULL),
        ('e4000000-0000-0000-0000-000000000002', gen_random_uuid(), 'scheduled', 'none', now() - interval '1 hour', NULL),
        ('e4000000-0000-0000-0000-000000000003', gen_random_uuid(), 'scheduled', 'none', now() - interval '3 days', NULL),
        ('e4000000-0000-0000-0000-000000000004', gen_random_uuid(), 'processing', 'db_prepared', now() - interval '1 hour', now() + interval '1 hour'),
        ('e4000000-0000-0000-0000-000000000005', gen_random_uuid(), 'processing', 'none', now() - interval '5 days', now() + interval '1 hour'),
        ('e4000000-0000-0000-0000-000000000006', gen_random_uuid(), 'failed', 'db_prepared', now() - interval '5 days', NULL),
        ('e4000000-0000-0000-0000-000000000007', gen_random_uuid(), 'cancelled', 'none', now() - interval '9 days', NULL),
        ('e4000000-0000-0000-0000-000000000008', NULL, 'completed', 'storage_done', now() - interval '9 days', NULL);

    SELECT string_agg(row_to_json(r)::text, ',' ORDER BY r.id) INTO v_before FROM public.account_deletion_requests r;
    v_sum := pg_temp.call('service_role', NULL, 'SELECT public.get_account_deletion_queue_summary()::text')::jsonb;
    PERFORM pg_temp.expect('due', v_sum->>'due', '2');
    PERFORM pg_temp.expect('in progress', v_sum->>'in_progress', '2');
    PERFORM pg_temp.expect('failed', v_sum->>'failed', '1');
    PERFORM pg_temp.expect('overdue past 48 hours, failed excluded', v_sum->>'overdue', '2');
    PERFORM pg_temp.expect('summary changes nothing',
        (SELECT string_agg(row_to_json(r)::text, ',' ORDER BY r.id) FROM public.account_deletion_requests r), v_before);
    RAISE NOTICE 'PASSED: the queue summary counts jobs and changes nothing.';
END $$;

-- 2. Alerts --------------------------------------------------------------------------
DO $$
DECLARE
    v_got text;
BEGIN
    v_got := pg_temp.call('service_role', NULL,
        $q$SELECT string_agg(request_id::text || ':' || alert, ',' ORDER BY request_id) FROM public.list_account_deletion_alerts_due()$q$);
    PERFORM pg_temp.expect('failed and overdue alerts', v_got,
        'e4000000-0000-0000-0000-000000000003:ops_overdue,e4000000-0000-0000-0000-000000000005:ops_overdue,e4000000-0000-0000-0000-000000000006:ops_failed');

    IF EXISTS (SELECT 1 FROM pg_proc p
               JOIN unnest(p.proargnames) AS a(name) ON a.name = 'user_id'
               WHERE p.oid = 'public.list_account_deletion_alerts_due()'::regprocedure) THEN
        RAISE EXCEPTION 'alerts carry a user id';
    END IF;

    PERFORM pg_temp.call('service_role', NULL,
        $q$SELECT public.mark_account_deletion_notice_sent('e4000000-0000-0000-0000-000000000006', 'ops_failed')::text$q$);
    PERFORM pg_temp.call('service_role', NULL,
        $q$SELECT public.mark_account_deletion_notice_sent('e4000000-0000-0000-0000-000000000003', 'ops_overdue')::text$q$);
    v_got := pg_temp.call('service_role', NULL,
        $q$SELECT string_agg(request_id::text || ':' || alert, ',' ORDER BY request_id) FROM public.list_account_deletion_alerts_due()$q$);
    PERFORM pg_temp.expect('each alert once', v_got, 'e4000000-0000-0000-0000-000000000005:ops_overdue');

    -- A job that goes from overdue to failed still alerts about the failure.
    UPDATE public.account_deletion_requests SET status = 'failed' WHERE id = 'e4000000-0000-0000-0000-000000000003';
    v_got := pg_temp.call('service_role', NULL,
        $q$SELECT string_agg(request_id::text || ':' || alert, ',' ORDER BY request_id) FROM public.list_account_deletion_alerts_due()$q$);
    PERFORM pg_temp.expect('overdue then failed', v_got,
        'e4000000-0000-0000-0000-000000000003:ops_failed,e4000000-0000-0000-0000-000000000005:ops_overdue');
    RAISE NOTICE 'PASSED: failed and overdue jobs alert once each, with no user id.';
END $$;

-- 2b. A date already past gets no "will be deleted" reminder; the job is about to run ------
DO $$
DECLARE
    v_user uuid := 'e4000000-0000-0000-0000-0000000000b1';
    v_member uuid := 'e4000000-0000-0000-0000-0000000000b2';
    v_hh uuid := 'e40a0000-0000-0000-0000-000000000001';
    v_got text;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user, 't40-a@test.local'), (v_member, 't40-b@test.local');
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES (v_hh, 'T40', 'T40CODE000000001', 'roommates');
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role) VALUES
        (v_hh, v_user, 'admin', 'peer'), (v_hh, v_member, 'member', 'peer');
    INSERT INTO public.account_deletion_requests (id, user_id, status, stage, scheduled_for)
    VALUES ('e4000000-0000-0000-0000-000000000009', v_user, 'scheduled', 'none', now() - interval '1 hour');
    UPDATE public.households
    SET deletion_requested_by = v_user, deletion_requested_at = now(), deletion_scheduled_for = now() - interval '1 hour'
    WHERE id = v_hh;

    v_got := pg_temp.call('service_role', NULL,
        $q$SELECT count(*)::text FROM public.list_account_deletion_notices_due() WHERE request_id = 'e4000000-0000-0000-0000-000000000009'$q$);
    PERFORM pg_temp.expect('no reminder for a date already past', v_got, '0');

    UPDATE public.account_deletion_requests SET scheduled_for = now() + interval '1 hour' WHERE id = 'e4000000-0000-0000-0000-000000000009';
    UPDATE public.households SET deletion_scheduled_for = now() + interval '1 hour' WHERE id = v_hh;
    v_got := pg_temp.call('service_role', NULL,
        $q$SELECT string_agg(notice, ',' ORDER BY notice) FROM public.list_account_deletion_notices_due() WHERE request_id = 'e4000000-0000-0000-0000-000000000009'$q$);
    PERFORM pg_temp.expect('reminders while the date is ahead', v_got, 'holder_t1,member_marked');
    RAISE NOTICE 'PASSED: reminders stop once the date has passed.';
END $$;

-- 3. Inquiry retention ---------------------------------------------------------------
DO $$
DECLARE
    v_got text;
BEGIN
    INSERT INTO public.inquiries (type, email, reference, created_at) VALUES
        ('account_deletion', 't40-old@test.local', 'T40-OLD', now() - interval '91 days'),
        ('account_deletion', 't40-new@test.local', 'T40-NEW', now() - interval '89 days'),
        ('support', 't40-sup@test.local', 'T40-SUP', now() - interval '400 days');
    v_got := pg_temp.call('service_role', NULL, 'SELECT public.purge_expired_account_deletion_inquiries(90)::text');
    PERFORM pg_temp.expect('one row removed', v_got, '1');
    PERFORM pg_temp.expect('only the expired deletion inquiry went',
        (SELECT string_agg(reference, ',' ORDER BY reference) FROM public.inquiries WHERE reference LIKE 'T40-%'), 'T40-NEW,T40-SUP');
    -- A bad argument cannot empty the table.
    v_got := pg_temp.call('service_role', NULL, 'SELECT public.purge_expired_account_deletion_inquiries(0)::text');
    PERFORM pg_temp.expect('a retention of zero removes nothing recent', v_got, '0');
    RAISE NOTICE 'PASSED: only expired account_deletion inquiries are removed.';
END $$;

-- 4. Privileges ----------------------------------------------------------------------
DO $$
DECLARE
    v_call record;
BEGIN
    FOR v_call IN
        SELECT * FROM (VALUES
            ('get_account_deletion_queue_summary()', 'SELECT public.get_account_deletion_queue_summary()::text'),
            ('list_account_deletion_alerts_due()', 'SELECT count(*)::text FROM public.list_account_deletion_alerts_due()'),
            ('purge_expired_account_deletion_inquiries(integer)', 'SELECT public.purge_expired_account_deletion_inquiries(90)::text')
        ) AS t(sig, sql)
    LOOP
        IF has_function_privilege('anon', 'public.' || v_call.sig, 'EXECUTE')
           OR has_function_privilege('authenticated', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client role can execute %', v_call.sig;
        END IF;
        PERFORM pg_temp.expect('authenticated on ' || v_call.sig,
            pg_temp.call('authenticated', 'e4000000-0000-0000-0000-0000000000aa', v_call.sql), 'ERR:42501');
        PERFORM pg_temp.expect('anon on ' || v_call.sig, pg_temp.call('anon', NULL, v_call.sql), 'ERR:42501');
        PERFORM pg_temp.expect('a subject under service_role on ' || v_call.sig,
            pg_temp.call('service_role', 'e4000000-0000-0000-0000-0000000000aa', v_call.sql), 'ERR:42501');
    END LOOP;
    RAISE NOTICE 'PASSED: the worker support functions are service-only.';
END $$;

ROLLBACK;
