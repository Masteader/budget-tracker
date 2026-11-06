-- ============================================================================
-- Test 57: repayments, requests and reversals that move money, under concurrency
--
-- Migration: 20261105001300_wife_repayment_debit.sql
--
-- Like tests 51 and 55 this one commits: the races need other sessions, which only see committed
-- rows. They are dblink connections back into this database. dblink goes in its own schema and
-- is dropped at the end, with every fixture row (all ids start with e57).
--
-- Each race is made deterministic with a lock held by another session, never with sleeps:
--   1. A double tap with an account: one repayment, one debit; her account never moves.
--   2. Two repayments of the whole remainder from two accounts: one passes, the other is refused
--      as an overpayment, and only one account is debited.
--   3. The lock order. While the household is held (as the purge holds it), a repayment and an
--      approval wait without holding his account or the request; while a shared pool is held, a
--      repayment waits without holding the household. A former member payment waits for the
--      household without holding the record.
--   4. A double tap of a former member payment with an account: one debit.
--   5. A double approval of one request (two admins): one approves and debits once, the other is
--      refused as no longer pending.
--   6. Approve against cancel: exactly one outcome, and money moves only if it was approved.
--   7. Reverse against reverse: one reversal, one credit; the other is refused as already reversed.
--   8. The wife's purge while an approval from the pool is in flight, with a reversal in history and
--      another request pending: the purge waits for it, with no deadlock, its ledger invariant holds,
--      and the record keeps what remained after the approval.
-- The household's husband is gone (review R3-01), so two admins who are not wives may each act:
-- the races need two people allowed to settle the same ledger.
-- ============================================================================
\set ON_ERROR_STOP on

DROP EXTENSION IF EXISTS dblink;
DROP SCHEMA IF EXISTS t57_dblink CASCADE;
CREATE SCHEMA t57_dblink;
CREATE EXTENSION dblink SCHEMA t57_dblink;

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
AS $$ SELECT ('e5700000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e57a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e57c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.d(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e57d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e57e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.r(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e57f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;

CREATE FUNCTION pg_temp.cleanup() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_hhs uuid[] := ARRAY(SELECT id FROM public.households WHERE id::text LIKE 'e57a%');
    v_users uuid[] := ARRAY(SELECT id FROM auth.users WHERE id::text LIKE 'e5700000%');
BEGIN
    DELETE FROM public.former_member_debts WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_deletion_storage_queue WHERE request_id::text LIKE 'e57f%';
    DELETE FROM public.account_deletion_requests WHERE id::text LIKE 'e57f%' OR user_id = ANY (v_users);
    -- Requests first: an outcome points at the repayment that approved it.
    DELETE FROM public.spouse_reimbursement_requests WHERE household_id = ANY (v_hhs);
    DELETE FROM public.spouse_reimbursements WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_transfers WHERE household_id = ANY (v_hhs);
    DELETE FROM public.transactions WHERE household_id = ANY (v_hhs);
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
    PERFORM t57_dblink.dblink_connect(p_name, format('dbname=%s user=%s', current_database(), current_user));
    SELECT pid INTO v_pid FROM t57_dblink.dblink(p_name, 'SELECT pg_backend_pid()') AS t(pid int);
    RETURN v_pid;
END;
$$;

CREATE FUNCTION pg_temp.as_user(p_name text, p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM * FROM t57_dblink.dblink(p_name, format('SELECT set_config(%L, %L, false)', 'request.jwt.claims',
        jsonb_build_object('sub', p_user, 'role', 'authenticated')::text)) AS t(x text);
    PERFORM t57_dblink.dblink_exec(p_name, 'SET ROLE authenticated');
END;
$$;

CREATE FUNCTION pg_temp.wait(p_name text, p_pid int) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    FOR i IN 1..400 LOOP
        IF t57_dblink.dblink_is_busy(p_name) = 0 THEN
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
        SELECT r INTO v_res FROM t57_dblink.dblink_get_result(p_name) AS t(r text);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        v_res := 'ERR:' || v_state || ':' || COALESCE(v_hint, '');
    END;
    PERFORM * FROM t57_dblink.dblink_get_result(p_name, false) AS t(r text);
    RETURN COALESCE(v_res, 'ok');
END;
$$;

CREATE FUNCTION pg_temp.disconnect_all() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY COALESCE(t57_dblink.dblink_get_connections(), '{}') LOOP
        PERFORM t57_dblink.dblink_disconnect(v_name);
    END LOOP;
END;
$$;

-- Whether another session can take these rows at once ('free') or not ('locked').
CREATE FUNCTION pg_temp.probe(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_state text;
BEGIN
    PERFORM pg_temp.connect('probe');
    PERFORM t57_dblink.dblink_exec('probe', 'BEGIN');
    BEGIN
        PERFORM * FROM t57_dblink.dblink('probe', p_sql) AS t(x int);
        v_state := 'free';
    EXCEPTION WHEN OTHERS THEN
        v_state := 'locked';
    END;
    PERFORM t57_dblink.dblink_disconnect('probe');
    RETURN v_state;
END;
$$;

-- The spouse_reimbursement advisory lock held by session 'blk', so the calls queue behind it.
CREATE FUNCTION pg_temp.hold_ledger() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.connect('blk');
    PERFORM t57_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t57_dblink.dblink('blk', format('SELECT pg_advisory_xact_lock(hashtextextended(%L, 0))::text',
        'spouse_reimbursement:' || pg_temp.h(1)::text || ':' || pg_temp.u(3)::text)) AS t(x text);
END;
$$;

CREATE FUNCTION pg_temp.repay_sql(p_amount numeric, p_account uuid, p_key uuid) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid, %L::uuid)::text',
                  pg_temp.h(1), pg_temp.u(3), p_amount, 'bank_transfer', p_account, p_key, pg_temp.a(4));
$$;
CREATE FUNCTION pg_temp.fpay_sql(p_amount numeric, p_account uuid, p_key uuid) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
                  pg_temp.h(1), pg_temp.d(1), p_amount, 'cash', p_key, p_account);
$$;
CREATE FUNCTION pg_temp.approve_sql(p_request uuid, p_account uuid, p_key uuid) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.approve_spouse_reimbursement_request(%L, %L, %L::uuid, %L::uuid, NULL)::text',
                  pg_temp.h(1), p_request, p_account, p_key);
$$;
CREATE FUNCTION pg_temp.cancel_sql(p_request uuid) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.cancel_spouse_reimbursement_request(%L, %L, NULL)::text', pg_temp.h(1), p_request);
$$;
CREATE FUNCTION pg_temp.reverse_sql(p_row uuid, p_key uuid) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.reverse_spouse_reimbursement(%L, %L, %L::uuid, NULL)::text', pg_temp.h(1), p_row, p_key);
$$;

-- A pending request of hers, committed (as the wife, through the API's path).
CREATE FUNCTION pg_temp.ask(p_amount numeric, p_key uuid) RETURNS uuid LANGUAGE sql AS $$
    SELECT (public.request_spouse_reimbursement(pg_temp.h(1), p_amount, 'cash', p_key, pg_temp.u(3), pg_temp.a(4)) ->> 'request_id')::uuid;
$$;

CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;
CREATE FUNCTION pg_temp.both() RETURNS numeric LANGUAGE sql
AS $$ SELECT sum(balance) FROM public.accounts WHERE id IN (pg_temp.a(1), pg_temp.a(2)) $$;

-- What is owed, counted here independently of the functions under test: reversals add back.
CREATE FUNCTION pg_temp.outstanding() RETURNS text LANGUAGE sql AS $$
    SELECT (sum(t.amount) - COALESCE((SELECT sum(CASE WHEN r.kind = 'reversal' THEN -r.amount ELSE r.amount END)
                                      FROM public.spouse_reimbursements r
                                      WHERE r.household_id = pg_temp.h(1) AND r.wife_user_id = pg_temp.u(3)), 0))::text
    FROM public.transactions t
    WHERE t.household_id = pg_temp.h(1) AND t.nafaqah_spouse_id = pg_temp.u(3) AND t.nafaqah_class = 'wife_reimbursable';
$$;

CREATE FUNCTION pg_temp.outcome(p_request uuid) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE((SELECT outcome FROM public.spouse_reimbursement_request_outcomes WHERE request_id = p_request), 'pending');
$$;

SELECT pg_temp.cleanup();

-- ── Fixtures (committed) ────────────────────────────────────────────────────
-- H1: the husband is gone (no provider); admins A(1) and C(2), neither a wife; wife W(3) with a
--     bank account.
-- Accounts: pool A1 1000 (H), H bank A2 500, W bank A3 0. W advanced 300. Record D1 (100 owed).
DO $$
BEGIN
    INSERT INTO auth.users (id, email) SELECT pg_temp.u(n), 't57-' || n || '@test.local' FROM generate_series(1, 3) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES (pg_temp.h(1), 'T57 H1', 'T57CODE000000001', 'family');
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(2), 'admin', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(3), 'member', 'spouse', true);
    UPDATE public.users SET household_id = pg_temp.h(1) WHERE id IN (pg_temp.u(1), pg_temp.u(2), pg_temp.u(3));
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.users SET role = 'admin', financial_role = 'family_member' WHERE id = pg_temp.u(1);
    UPDATE public.users SET role = 'admin' WHERE id = pg_temp.u(2);
    UPDATE public.users SET financial_role = 'spouse' WHERE id = pg_temp.u(3);
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T57 pool', 'shared_pool', 1000, true),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(1), 'T57 his bank', 'bank', 500, false),
        (pg_temp.a(3), pg_temp.h(1), pg_temp.u(3), 'T57 her bank', 'bank', 0, false);
    -- Her wife account (20261105001300, section 12): every repayment to her credits it.
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, assigned_wife_id)
    VALUES (pg_temp.a(4), pg_temp.h(1), pg_temp.u(1), 'T57 her account', 'wife', 0, false, pg_temp.u(3));
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(1), pg_temp.u(3), 300, 'T57 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(3));
    -- No husband now (he left, say): the admins who are not wives act (review R3-01).
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(1);
    INSERT INTO public.former_member_debts (id, household_id, original_amount) VALUES (pg_temp.d(1), pg_temp.h(1), 100);
    INSERT INTO public.account_deletion_requests (id, user_id, status, scheduled_for, attempts, lease_expires_at)
    VALUES (pg_temp.r(3), pg_temp.u(3), 'processing', now() - interval '1 minute', 1, now() + interval '30 minutes');
END $$;

-- 1. Double tap with an account ------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.hold_ledger();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(1));
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.repay_sql(30, pg_temp.a(2), pg_temp.k(1)));
    PERFORM pg_temp.expect('first tap waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t57_dblink.dblink_send_query('t2', pg_temp.repay_sql(30, pg_temp.a(2), pg_temp.k(1)));
    PERFORM pg_temp.expect('second tap waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('both answered', (v_a LIKE '{%' AND v_b LIKE '{%')::text, 'true');
    PERFORM pg_temp.expect('one recorded, one replayed',
        (SELECT string_agg(x, ',' ORDER BY x COLLATE "C") FROM unnest(ARRAY[v_a::jsonb ->> 'replayed', v_b::jsonb ->> 'replayed']) AS x), 'false,true');
    PERFORM pg_temp.expect('the same repayment', v_a::jsonb ->> 'reimbursement_id', v_b::jsonb ->> 'reimbursement_id');
    PERFORM pg_temp.expect('debited once', pg_temp.bal(2), '470.00');
    PERFORM pg_temp.expect('her account never credited', pg_temp.bal(3), '0.00');
    PERFORM pg_temp.expect('one transfer', (SELECT count(*)::text FROM public.account_transfers WHERE household_id = pg_temp.h(1)), '1');
    RAISE NOTICE 'PASSED: a double tap with an account moves the money once.';
END $$;

-- 2. Two repayments of the whole remainder --------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.hold_ledger();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(2));
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.repay_sql(270, pg_temp.a(2), pg_temp.k(21)));
    PERFORM pg_temp.expect('husband waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t57_dblink.dblink_send_query('t2', pg_temp.repay_sql(270, pg_temp.a(1), pg_temp.k(22)));
    PERFORM pg_temp.expect('co-admin waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('one passes, the other is refused',
        (SELECT string_agg(x, ',' ORDER BY x COLLATE "C") FROM unnest(ARRAY[
            CASE WHEN v_a LIKE 'ERR:%' THEN v_a ELSE v_a::jsonb ->> 'outstanding_after' END,
            CASE WHEN v_b LIKE 'ERR:%' THEN v_b ELSE v_b::jsonb ->> 'outstanding_after' END]) AS x),
        '0.00,ERR:22023:overpayment');
    PERFORM pg_temp.expect('his bank paid it, the pool did not', pg_temp.bal(2) || '/' || pg_temp.bal(1), '200.00/1000.00');
    PERFORM pg_temp.expect('her bank never moved', pg_temp.bal(3), '0.00');
    PERFORM pg_temp.expect('never overpaid', pg_temp.outstanding(), '0.00');
    RAISE NOTICE 'PASSED: two repayments of the remainder at once move it once.';
END $$;

-- A new advance for what follows: 200 owed (classified while a provider is named, as before he
-- left). A pending request of 5 for the lock-order check.
UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id)
VALUES (pg_temp.h(1), pg_temp.u(3), 200, 'T57 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(3));
UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(1);
CREATE TABLE pg_temp.ids (label text PRIMARY KEY, id uuid);
INSERT INTO pg_temp.ids VALUES ('r0', pg_temp.ask(5, pg_temp.k(30)));

-- 3. The lock order ----------------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_res text;
    v_r0 uuid := (SELECT id FROM pg_temp.ids WHERE label = 'r0');
BEGIN
    -- The household held, as prepare_account_purge holds it.
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    v_p1 := pg_temp.connect('t1');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM t57_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t57_dblink.dblink('blk', format('SELECT 1 FROM public.households WHERE id = %L FOR UPDATE', pg_temp.h(1))) AS t(x int);
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.repay_sql(20, pg_temp.a(2), pg_temp.k(31)));
    PERFORM pg_temp.expect('the repayment waits for the household', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM pg_temp.expect('holding neither account while it waits',
        pg_temp.probe(format('SELECT 1 FROM public.accounts WHERE id IN (%L, %L) FOR UPDATE NOWAIT', pg_temp.a(2), pg_temp.a(3))), 'free');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_res := pg_temp.result('t1');
    PERFORM pg_temp.expect('then it completes', v_res::jsonb ->> 'outstanding_after', '180.00');

    -- A shared pool held: the repayment waits for it before it takes the household.
    PERFORM t57_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t57_dblink.dblink('blk', format('SELECT 1 FROM public.accounts WHERE id = %L FOR UPDATE', pg_temp.a(1))) AS t(x int);
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.repay_sql(10, pg_temp.a(1), pg_temp.k(32)));
    PERFORM pg_temp.expect('the repayment waits for the pool', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM pg_temp.expect('without holding the household',
        pg_temp.probe(format('SELECT 1 FROM public.households WHERE id = %L FOR UPDATE NOWAIT', pg_temp.h(1))), 'free');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_res := pg_temp.result('t1');
    PERFORM pg_temp.expect('then it completes from the pool', (v_res::jsonb ->> 'outstanding_after') || '/' || pg_temp.bal(1), '170.00/990.00');

    -- A former member payment: the household held, it waits without holding the record row.
    PERFORM t57_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t57_dblink.dblink('blk', format('SELECT 1 FROM public.households WHERE id = %L FOR UPDATE', pg_temp.h(1))) AS t(x int);
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.fpay_sql(15, pg_temp.a(2), pg_temp.k(33)));
    PERFORM pg_temp.expect('the payment waits for the household', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM pg_temp.expect('without holding the record',
        pg_temp.probe(format('SELECT 1 FROM public.former_member_debts WHERE id = %L FOR UPDATE NOWAIT', pg_temp.d(1))), 'free');
    PERFORM pg_temp.expect('nor his account',
        pg_temp.probe(format('SELECT 1 FROM public.accounts WHERE id = %L FOR UPDATE NOWAIT', pg_temp.a(2))), 'free');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_res := pg_temp.result('t1');
    PERFORM pg_temp.expect('then it completes (payment)', (v_res::jsonb ->> 'remaining') || '/' || pg_temp.bal(2), '85.00/165.00');

    -- An approval: the household held, it waits without holding the request or his account.
    PERFORM t57_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t57_dblink.dblink('blk', format('SELECT 1 FROM public.households WHERE id = %L FOR UPDATE', pg_temp.h(1))) AS t(x int);
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.approve_sql(v_r0, pg_temp.a(2), pg_temp.k(34)));
    PERFORM pg_temp.expect('the approval waits for the household', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM pg_temp.expect('without holding the request',
        pg_temp.probe(format('SELECT 1 FROM public.spouse_reimbursement_requests WHERE id = %L FOR UPDATE NOWAIT', v_r0)), 'free');
    PERFORM pg_temp.expect('nor his account (approval)',
        pg_temp.probe(format('SELECT 1 FROM public.accounts WHERE id = %L FOR UPDATE NOWAIT', pg_temp.a(2))), 'free');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_res := pg_temp.result('t1');
    PERFORM pg_temp.expect('then it is approved', (v_res::jsonb ->> 'outstanding_after') || '/' || pg_temp.bal(2) || '/' || pg_temp.outcome(v_r0),
        '165.00/160.00/approved');
    PERFORM pg_temp.disconnect_all();
    RAISE NOTICE 'PASSED: pools, then the household, then personal accounts, then the request or record: the purge''s order.';
END $$;

-- 4. A double tap of a former member payment with an account ---------------------------------
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
    PERFORM t57_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t57_dblink.dblink('blk', format('SELECT 1 FROM public.former_member_debts WHERE id = %L FOR UPDATE', pg_temp.d(1))) AS t(x int);
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.fpay_sql(25, pg_temp.a(2), pg_temp.k(41)));
    PERFORM pg_temp.expect('first tap waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t57_dblink.dblink_send_query('t2', pg_temp.fpay_sql(25, pg_temp.a(2), pg_temp.k(41)));
    PERFORM pg_temp.expect('second tap waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('one recorded, one replayed',
        (SELECT string_agg(x, ',' ORDER BY x COLLATE "C") FROM unnest(ARRAY[v_a::jsonb ->> 'replayed', v_b::jsonb ->> 'replayed']) AS x), 'false,true');
    PERFORM pg_temp.expect('debited once', pg_temp.bal(2), '135.00');
    PERFORM pg_temp.expect('paid once', (SELECT paid_amount::text FROM public.former_member_debts WHERE id = pg_temp.d(1)), '40.00');
    RAISE NOTICE 'PASSED: a double tap of a former member payment moves the money once.';
END $$;

INSERT INTO pg_temp.ids VALUES ('r1', pg_temp.ask(20, pg_temp.k(50)));

-- 5. A double approval ------------------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
    v_both numeric := pg_temp.both();
    v_r1 uuid := (SELECT id FROM pg_temp.ids WHERE label = 'r1');
BEGIN
    PERFORM pg_temp.expect('owed before', pg_temp.outstanding(), '165.00');
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.hold_ledger();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(2));
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.approve_sql(v_r1, pg_temp.a(2), pg_temp.k(51)));
    PERFORM pg_temp.expect('the husband waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t57_dblink.dblink_send_query('t2', pg_temp.approve_sql(v_r1, pg_temp.a(1), pg_temp.k(52)));
    PERFORM pg_temp.expect('the co-admin waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('one approves, the other is refused',
        (SELECT string_agg(x, ',' ORDER BY x COLLATE "C") FROM unnest(ARRAY[
            CASE WHEN v_a LIKE 'ERR:%' THEN v_a ELSE 'approved' END,
            CASE WHEN v_b LIKE 'ERR:%' THEN v_b ELSE 'approved' END]) AS x),
        'ERR:22023:request_not_pending,approved');
    PERFORM pg_temp.expect('debited once, by exactly the request', (v_both - pg_temp.both())::text, '20.00');
    PERFORM pg_temp.expect('one repayment for the request',
        (SELECT count(*)::text FROM public.spouse_reimbursement_request_outcomes WHERE request_id = v_r1 AND outcome = 'approved'), '1');
    PERFORM pg_temp.expect('owed after', pg_temp.outstanding(), '145.00');
    PERFORM pg_temp.expect('her bank never moved', pg_temp.bal(3), '0.00');
    RAISE NOTICE 'PASSED: two approvals of one request at once debit once.';
END $$;

INSERT INTO pg_temp.ids VALUES ('r2', pg_temp.ask(15, pg_temp.k(60)));

-- 6. Approve against cancel ---------------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
    v_both numeric := pg_temp.both();
    v_r2 uuid := (SELECT id FROM pg_temp.ids WHERE label = 'r2');
    v_outcome text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.hold_ledger();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(3));
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.approve_sql(v_r2, pg_temp.a(2), pg_temp.k(61)));
    PERFORM pg_temp.expect('the approval waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t57_dblink.dblink_send_query('t2', pg_temp.cancel_sql(v_r2));
    PERFORM pg_temp.expect('the cancel waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    v_outcome := pg_temp.outcome(v_r2);
    PERFORM pg_temp.expect('exactly one outcome',
        (SELECT count(*)::text FROM public.spouse_reimbursement_request_outcomes WHERE request_id = v_r2), '1');
    IF v_outcome = 'approved' THEN
        PERFORM pg_temp.expect('the cancel lost', v_b, 'ERR:22023:request_not_pending');
        PERFORM pg_temp.expect('approved: debited once', (v_both - pg_temp.both())::text, '15.00');
        PERFORM pg_temp.expect('approved: owed after', pg_temp.outstanding(), '130.00');
    ELSE
        PERFORM pg_temp.expect('cancelled', v_outcome, 'cancelled');
        PERFORM pg_temp.expect('the approval lost', v_a, 'ERR:22023:request_not_pending');
        PERFORM pg_temp.expect('cancelled: nothing moved', (v_both - pg_temp.both())::text, '0.00');
        PERFORM pg_temp.expect('cancelled: owed unchanged', pg_temp.outstanding(), '145.00');
    END IF;
    RAISE NOTICE 'PASSED: approve against cancel ends in exactly one outcome (%), and money moves only if approved.', v_outcome;
END $$;

-- A tracked repayment to reverse, committed (the API's path: the verified caller in p_actor_user_id).
INSERT INTO pg_temp.ids VALUES ('p7', (public.record_spouse_reimbursement(pg_temp.h(1), pg_temp.u(3), 10, 'cash', NULL, pg_temp.u(1),
    pg_temp.a(2), pg_temp.k(70), pg_temp.a(4)) ->> 'reimbursement_id')::uuid);

-- 7. Reverse against reverse ------------------------------------------------------------------
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
    v_bank numeric := (SELECT balance FROM public.accounts WHERE id = pg_temp.a(2));
    v_owed text := pg_temp.outstanding();
    v_p7 uuid := (SELECT id FROM pg_temp.ids WHERE label = 'p7');
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.hold_ledger();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(1));
    PERFORM t57_dblink.dblink_send_query('t1', pg_temp.reverse_sql(v_p7, pg_temp.k(71)));
    PERFORM pg_temp.expect('the first reversal waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t57_dblink.dblink_send_query('t2', pg_temp.reverse_sql(v_p7, pg_temp.k(72)));
    PERFORM pg_temp.expect('the second reversal waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t57_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('one reverses, the other is refused',
        (SELECT string_agg(x, ',' ORDER BY x COLLATE "C") FROM unnest(ARRAY[
            CASE WHEN v_a LIKE 'ERR:%' THEN v_a ELSE 'reversed' END,
            CASE WHEN v_b LIKE 'ERR:%' THEN v_b ELSE 'reversed' END]) AS x),
        'ERR:22023:already_reversed,reversed');
    PERFORM pg_temp.expect('credited back once', ((SELECT balance FROM public.accounts WHERE id = pg_temp.a(2)) - v_bank)::text, '10.00');
    PERFORM pg_temp.expect('one reversal', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE reverses_id = v_p7), '1');
    PERFORM pg_temp.expect('owed restored once', pg_temp.outstanding(), (v_owed::numeric + 10)::text);
    RAISE NOTICE 'PASSED: two reversals of one repayment at once credit it back once.';
END $$;

INSERT INTO pg_temp.ids VALUES ('r3', pg_temp.ask(25, pg_temp.k(80)));
INSERT INTO pg_temp.ids VALUES ('r4', pg_temp.ask(5, pg_temp.k(81)));

-- 8. Her purge while an approval from the pool is in flight -------------------------------------
DO $$
DECLARE
    v_rp_pid int;
    v_pg_pid int;
    v_purge text;
    v_approve text;
    v_pool numeric := (SELECT balance FROM public.accounts WHERE id = pg_temp.a(1));
    v_owed numeric := pg_temp.outstanding()::numeric;
    v_r3 uuid := (SELECT id FROM pg_temp.ids WHERE label = 'r3');
BEGIN
    PERFORM pg_temp.disconnect_all();
    v_rp_pid := pg_temp.connect('rp');
    v_pg_pid := pg_temp.connect('pg');
    PERFORM pg_temp.as_user('rp', pg_temp.u(1));
    PERFORM t57_dblink.dblink_exec('rp', 'BEGIN');
    v_approve := (SELECT r FROM t57_dblink.dblink('rp', pg_temp.approve_sql(v_r3, pg_temp.a(1), pg_temp.k(82))) AS t(r text));
    PERFORM t57_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(3)));
    PERFORM pg_temp.expect('the purge waits for the approval', pg_temp.wait('pg', v_pg_pid), 'blocked');
    PERFORM t57_dblink.dblink_exec('rp', 'COMMIT');
    v_purge := pg_temp.result('pg');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('approved', (v_approve::jsonb ->> 'outstanding_after')::numeric::text, (v_owed - 25)::text);
    PERFORM pg_temp.expect('no deadlock, and the ledger invariant holds',
        CASE WHEN v_purge LIKE 'ERR:%' THEN v_purge ELSE v_purge::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('the pool paid it', (v_pool - (SELECT balance FROM public.accounts WHERE id = pg_temp.a(1)))::text, '25.00');
    PERFORM pg_temp.expect('her account went with her', (SELECT count(*)::text FROM public.accounts WHERE id = pg_temp.a(3)), '0');
    PERFORM pg_temp.expect('her requests went with her ledger',
        (SELECT count(*)::text FROM public.spouse_reimbursement_requests WHERE household_id = pg_temp.h(1)), '0');
    PERFORM pg_temp.expect('the record holds what remained after the approval, reversal counted',
        (SELECT string_agg(original_amount::text, ',') FROM public.former_member_debts
         WHERE household_id = pg_temp.h(1) AND id <> pg_temp.d(1)), (v_owed - 25)::text);
    RAISE NOTICE 'PASSED: the purge waits for an approval in flight, with no deadlock, and keeps what remained.';
END $$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();
DROP EXTENSION dblink;
DROP SCHEMA t57_dblink;
