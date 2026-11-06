-- ============================================================================
-- Test 55: former member debt under concurrency (several sessions)
--
-- Migration: 20261105001200_account_deletion_former_member_debt.sql
--
-- Like test 51 this one commits: the races need other sessions, which only see committed rows.
-- They are dblink connections back into this database (a local superuser without a password, the
-- Docker setup in run_tests.py). dblink goes in its own schema and is dropped at the end, with
-- every fixture row (all ids start with e55).
--
-- Each race is made deterministic with a lock held by another session, never with sleeps:
--   1. A double tap: the same request key sent twice at once records one payment.
--   2. Two different payments of the whole remainder at once: one settles, the other is refused,
--      and the record is never overpaid.
--   3. A payment and a waiver at once: one closes the record, the other is refused.
--   4. A purge while an ordinary repayment is in flight: the purge waits for it and keeps what is
--      owed after it, with no deadlock.
-- The household's husband is gone (review R3-01), so two admins who are not wives may each pay:
-- the races need two people allowed to act on the same record.
-- ============================================================================
\set ON_ERROR_STOP on

DROP EXTENSION IF EXISTS dblink;
DROP SCHEMA IF EXISTS t55_dblink CASCADE;
CREATE SCHEMA t55_dblink;
CREATE EXTENSION dblink SCHEMA t55_dblink;

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

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e5500000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e55a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.d(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e55d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e55e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.r(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e55f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;

CREATE FUNCTION pg_temp.cleanup() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_hhs uuid[] := ARRAY(SELECT id FROM public.households WHERE id::text LIKE 'e55a%');
    v_users uuid[] := ARRAY(SELECT id FROM auth.users WHERE id::text LIKE 'e5500000%');
BEGIN
    DELETE FROM public.former_member_debts WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_deletion_storage_queue WHERE request_id::text LIKE 'e55f%';
    DELETE FROM public.account_deletion_requests WHERE id::text LIKE 'e55f%' OR user_id = ANY (v_users);
    DELETE FROM public.spouse_reimbursements WHERE household_id = ANY (v_hhs);
    DELETE FROM public.transactions WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_transfers WHERE household_id = ANY (v_hhs);
    DELETE FROM public.accounts WHERE household_id = ANY (v_hhs);
    DELETE FROM public.household_memberships WHERE household_id = ANY (v_hhs) AND role <> 'admin';
    DELETE FROM public.household_memberships WHERE household_id = ANY (v_hhs);
    DELETE FROM public.households WHERE id = ANY (v_hhs);
    DELETE FROM auth.sessions WHERE user_id = ANY (v_users);
    DELETE FROM auth.users WHERE id = ANY (v_users);
END;
$$;

CREATE FUNCTION pg_temp.connect(p_name text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    v_pid int;
BEGIN
    PERFORM t55_dblink.dblink_connect(p_name, format('dbname=%s user=%s', current_database(), current_user));
    SELECT pid INTO v_pid FROM t55_dblink.dblink(p_name, 'SELECT pg_backend_pid()') AS t(pid int);
    RETURN v_pid;
END;
$$;

CREATE FUNCTION pg_temp.as_user(p_name text, p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM * FROM t55_dblink.dblink(p_name, format('SELECT set_config(%L, %L, false)', 'request.jwt.claims',
        jsonb_build_object('sub', p_user, 'role', 'authenticated')::text)) AS t(x text);
    PERFORM t55_dblink.dblink_exec(p_name, 'SET ROLE authenticated');
END;
$$;

CREATE FUNCTION pg_temp.wait(p_name text, p_pid int) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    FOR i IN 1..400 LOOP
        IF t55_dblink.dblink_is_busy(p_name) = 0 THEN
            RETURN 'done';
        END IF;
        PERFORM pg_stat_clear_snapshot();
        IF EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = p_pid AND wait_event_type = 'Lock') THEN
            RETURN 'blocked';
        END IF;
        PERFORM pg_sleep(0.025);
    END LOOP;
    RETURN 'timeout';
END;
$$;

CREATE FUNCTION pg_temp.result(p_name text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_res text;
    v_state text;
    v_hint text;
BEGIN
    BEGIN
        SELECT r INTO v_res FROM t55_dblink.dblink_get_result(p_name) AS t(r text);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        v_res := 'ERR:' || v_state || ':' || COALESCE(v_hint, '');
    END;
    PERFORM * FROM t55_dblink.dblink_get_result(p_name, false) AS t(r text);
    RETURN COALESCE(v_res, 'ok');
END;
$$;

CREATE FUNCTION pg_temp.disconnect_all() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY COALESCE(t55_dblink.dblink_get_connections(), '{}') LOOP
        PERFORM t55_dblink.dblink_disconnect(v_name);
    END LOOP;
END;
$$;

-- Holds the record row on 'blk' until released, so the two racers queue behind it together.
CREATE FUNCTION pg_temp.hold(p_debt uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM t55_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t55_dblink.dblink('blk', format('SELECT 1 FROM public.former_member_debts WHERE id = %L FOR UPDATE', p_debt)) AS t(x int);
END;
$$;

-- 20261105001300: a payment leaves an account; both admins pay from the shared pool here.
CREATE FUNCTION pg_temp.pool() RETURNS uuid LANGUAGE sql AS $$ SELECT 'e55c0000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.pay_sql(p_debt uuid, p_amount numeric, p_key uuid) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L, NULL, %L::uuid)::text',
                  pg_temp.h(1), p_debt, p_amount, 'cash', p_key, pg_temp.pool());
$$;

SELECT pg_temp.cleanup();

-- ── Fixtures (committed) ────────────────────────────────────────────────────
-- H1: the husband is gone (no provider); admins A(1) and C(2), neither a wife; wife W(3) still a
--     member for race 4.
-- Records D1 (100 owed), D2 (100), D3 (100), made as the purge would make them.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) SELECT pg_temp.u(n), 't55-' || n || '@test.local' FROM generate_series(1, 3) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES (pg_temp.h(1), 'T55 H1', 'T55CODE000000001', 'family');
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(2), 'admin', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(3), 'member', 'spouse', true);
    UPDATE public.users SET household_id = pg_temp.h(1) WHERE id IN (pg_temp.u(1), pg_temp.u(2), pg_temp.u(3));
    -- A provider while her advance is recorded; cleared below (the husband is gone).
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.users SET role = 'admin', financial_role = 'family_member' WHERE id = pg_temp.u(1);
    UPDATE public.users SET financial_role = 'spouse' WHERE id = pg_temp.u(3);
    INSERT INTO public.former_member_debts (id, household_id, original_amount)
    SELECT pg_temp.d(n), pg_temp.h(1), 100 FROM generate_series(1, 3) AS n;
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool)
    VALUES (pg_temp.pool(), pg_temp.h(1), pg_temp.u(1), 'T55 pool', 'shared_pool', 10000, true);
    -- W: 90 advanced, nothing repaid yet; her request is claimed and due.
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(1), pg_temp.u(3), 90, 'T55 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(3));
    -- No husband now (he left, say): the admins who are not wives act (review R3-01).
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(1);
    INSERT INTO public.account_deletion_requests (id, user_id, status, scheduled_for, attempts, lease_expires_at)
    VALUES (pg_temp.r(3), pg_temp.u(3), 'processing', now() - interval '1 minute', 1, now() + interval '30 minutes');
END $$;

-- 1. Double tap -----------------------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(1));
    PERFORM pg_temp.hold(pg_temp.d(1));
    PERFORM t55_dblink.dblink_send_query('t1', pg_temp.pay_sql(pg_temp.d(1), 30, pg_temp.k(1)));
    PERFORM pg_temp.expect('first tap waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t55_dblink.dblink_send_query('t2', pg_temp.pay_sql(pg_temp.d(1), 30, pg_temp.k(1)));
    PERFORM pg_temp.expect('second tap waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t55_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('both answered', (v_a LIKE '{%' AND v_b LIKE '{%')::text, 'true');
    PERFORM pg_temp.expect('one recorded, one replayed',
        (SELECT string_agg(x, ',' ORDER BY x) FROM unnest(ARRAY[v_a::jsonb ->> 'replayed', v_b::jsonb ->> 'replayed']) AS x), 'false,true');
    PERFORM pg_temp.expect('the same event', v_a::jsonb ->> 'event_id', v_b::jsonb ->> 'event_id');
    PERFORM pg_temp.expect('paid once', (SELECT paid_amount::text FROM public.former_member_debts WHERE id = pg_temp.d(1)), '30.00');
    PERFORM pg_temp.expect('one event', (SELECT count(*)::text FROM public.former_member_debt_events WHERE debt_id = pg_temp.d(1)), '1');
    RAISE NOTICE 'PASSED: a double tap records one payment.';
END $$;

-- 2. Two payments of the whole remainder ---------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(2));
    PERFORM pg_temp.hold(pg_temp.d(2));
    PERFORM t55_dblink.dblink_send_query('t1', pg_temp.pay_sql(pg_temp.d(2), 100, pg_temp.k(21)));
    PERFORM pg_temp.expect('first admin waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t55_dblink.dblink_send_query('t2', pg_temp.pay_sql(pg_temp.d(2), 100, pg_temp.k(22)));
    PERFORM pg_temp.expect('co-admin waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t55_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('one settles, the other is refused',
        (SELECT string_agg(x, ',' ORDER BY x) FROM unnest(ARRAY[
            CASE WHEN v_a LIKE 'ERR:%' THEN v_a ELSE v_a::jsonb ->> 'status' END,
            CASE WHEN v_b LIKE 'ERR:%' THEN v_b ELSE v_b::jsonb ->> 'status' END]) AS x),
        'ERR:22023:debt_closed,settled');
    PERFORM pg_temp.expect('never overpaid', (SELECT paid_amount::text || '/' || status FROM public.former_member_debts WHERE id = pg_temp.d(2)), '100.00/settled');
    PERFORM pg_temp.expect('one event', (SELECT count(*)::text FROM public.former_member_debt_events WHERE debt_id = pg_temp.d(2)), '1');
    RAISE NOTICE 'PASSED: two payments of the remainder at once settle it once.';
END $$;

-- 3. A payment and a waiver ----------------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(2));
    PERFORM pg_temp.hold(pg_temp.d(3));
    PERFORM t55_dblink.dblink_send_query('t1', format('SELECT public.waive_former_member_debt(%L, %L, %L)::text', pg_temp.h(1), pg_temp.d(3), pg_temp.k(31)));
    PERFORM pg_temp.expect('waiver waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t55_dblink.dblink_send_query('t2', pg_temp.pay_sql(pg_temp.d(3), 40, pg_temp.k(32)));
    PERFORM pg_temp.expect('payment waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t55_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    -- The waiver queued first: it closes the record, the payment then finds it closed.
    PERFORM pg_temp.expect('waived first', v_a::jsonb ->> 'status', 'waived');
    PERFORM pg_temp.expect('payment refused', v_b, 'ERR:22023:debt_closed');
    PERFORM pg_temp.expect('nothing paid', (SELECT paid_amount::text || '/' || status FROM public.former_member_debts WHERE id = pg_temp.d(3)), '0.00/waived');
    RAISE NOTICE 'PASSED: a payment and a waiver at once close the record once.';
END $$;

-- 4. The purge and an ordinary repayment in flight ---------------------------------------------
DO $$
DECLARE
    v_rp_pid int;
    v_pg_pid int;
    v_purge text;
    v_repay text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    v_rp_pid := pg_temp.connect('rp');
    v_pg_pid := pg_temp.connect('pg');
    PERFORM pg_temp.as_user('rp', pg_temp.u(1));
    -- An admin's repayment of 25 (the husband is gone), not yet committed.
    PERFORM t55_dblink.dblink_exec('rp', 'BEGIN');
    v_repay := (SELECT r FROM t55_dblink.dblink('rp', format('SELECT public.record_spouse_reimbursement(%L, %L, 25, %L, NULL, NULL, %L::uuid, %L::uuid)::text',
        pg_temp.h(1), pg_temp.u(3), 'cash', pg_temp.pool(), pg_temp.k(41))) AS t(r text));
    PERFORM t55_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(3)));
    PERFORM pg_temp.expect('the purge waits for the repayment', pg_temp.wait('pg', v_pg_pid), 'blocked');
    PERFORM t55_dblink.dblink_exec('rp', 'COMMIT');
    v_purge := pg_temp.result('pg');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('repayment recorded', v_repay::jsonb ->> 'outstanding_after', '65.00');
    PERFORM pg_temp.expect('no deadlock', CASE WHEN v_purge LIKE 'ERR:%' THEN v_purge ELSE v_purge::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('the record holds what is owed after the repayment',
        (SELECT string_agg(original_amount::text, ',') FROM public.former_member_debts
         WHERE household_id = pg_temp.h(1) AND id NOT IN (pg_temp.d(1), pg_temp.d(2), pg_temp.d(3))), '65.00');
    RAISE NOTICE 'PASSED: the purge waits for a repayment in flight and keeps what is owed after it.';
END $$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();
DROP EXTENSION dblink;
DROP SCHEMA t55_dblink;
