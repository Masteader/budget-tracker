-- ============================================================================
-- Test 53: an account deleted out of band (the Auth dashboard, not the worker)
--
-- Migrations: 20261105000100_account_deletion_schema.sql (handover_households_on_user_delete)
--
-- `DELETE FROM auth.users` stands in for the dashboard, as tests 16 and 39 do.
--
-- Verifies:
--   1. The user's invite_attempt_log rows and cancelled account_deletion_requests rows go with
--      them, and then nothing in public names their id.
--   2. An open request stays, for the worker to close (prepare_account_purge finds the user gone).
--   3. Other users' rows of both tables are untouched.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e5300000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;

-- Tables in public holding p_needle in any column, as "table:rows " in name order.
CREATE FUNCTION pg_temp.scan(p_needle text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_t record;
    v_n bigint;
    v_found text := '';
BEGIN
    FOR v_t IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r' ORDER BY c.relname LOOP
        EXECUTE format('SELECT count(*) FROM public.%I x WHERE x::text ILIKE %L', v_t.relname, '%' || p_needle || '%') INTO v_n;
        IF v_n > 0 THEN
            v_found := v_found || v_t.relname || ':' || v_n || ' ';
        END IF;
    END LOOP;
    RETURN v_found;
END;
$$;

INSERT INTO auth.users (id, email)
SELECT pg_temp.u(n), 't53-' || n || '@test.local' FROM generate_series(1, 3) AS n;

-- 1 and 3: failed joins and a cancelled request each. 2: a cancelled request and an open one.
INSERT INTO public.invite_attempt_log (user_id, success)
SELECT pg_temp.u(n), s FROM generate_series(1, 3) AS n, (VALUES (false), (true)) AS v(s) WHERE n <> 2;
INSERT INTO public.account_deletion_requests (user_id, status, scheduled_for, cancelled_at)
SELECT pg_temp.u(n), 'cancelled', now() + interval '30 days', now() FROM generate_series(1, 3) AS n;
INSERT INTO public.account_deletion_requests (user_id, status, scheduled_for)
VALUES (pg_temp.u(2), 'scheduled', now() + interval '20 days');

DO $$
BEGIN
    DELETE FROM auth.users WHERE id IN (pg_temp.u(1), pg_temp.u(2));

    IF (SELECT count(*) FROM public.invite_attempt_log WHERE user_id = pg_temp.u(1)) <> 0 THEN
        RAISE EXCEPTION 'invite_attempt_log rows of a deleted user remain';
    END IF;
    IF (SELECT count(*) FROM public.account_deletion_requests WHERE user_id IN (pg_temp.u(1), pg_temp.u(2)) AND status = 'cancelled') <> 0 THEN
        RAISE EXCEPTION 'cancelled requests of a deleted user remain';
    END IF;
    IF pg_temp.scan(pg_temp.u(1)::text) <> '' THEN
        RAISE EXCEPTION 'public still names the deleted user: %', pg_temp.scan(pg_temp.u(1)::text);
    END IF;
    RAISE NOTICE 'PASSED: a user deleted out of band leaves no failed-join log, no cancelled request and no id in public.';

    IF (SELECT status FROM public.account_deletion_requests WHERE user_id = pg_temp.u(2)) IS DISTINCT FROM 'scheduled' THEN
        RAISE EXCEPTION 'the open request of a user deleted out of band must stay for the worker';
    END IF;
    RAISE NOTICE 'PASSED: an open request stays for the worker to close.';

    IF (SELECT count(*) FROM public.invite_attempt_log WHERE user_id = pg_temp.u(3)) <> 2
       OR (SELECT count(*) FROM public.account_deletion_requests WHERE user_id = pg_temp.u(3) AND status = 'cancelled') <> 1 THEN
        RAISE EXCEPTION 'another user''s rows were touched';
    END IF;
    RAISE NOTICE 'PASSED: other users keep their rows.';
END $$;

ROLLBACK;
