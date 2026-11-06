-- ============================================================================
-- Test 61: Round 2 review fixes of tracked repayments, under concurrency
--
-- Migrations: 20261105001200_account_deletion_former_member_debt.sql,
--             20261105001300_wife_repayment_debit.sql
--
-- Like tests 51, 55 and 57 this one commits: the races need other sessions, which only see
-- committed rows. They are dblink connections back into this database. dblink goes in its own
-- schema and is dropped at the end, with every fixture row (all ids start with e61).
--
-- Each race is made deterministic with a lock or an open transaction held by another session,
-- never with sleeps:
--   R2-05  Her request while her purge holds the household: it waits, then is refused (she is no
--          longer a member); no pending request of a non-member is left.
--   R2-08  A reversal while the payer's purge holds the household: it waits, then is refused as
--          reversal_account_unavailable (his account went with him); nothing moves.
--   R2-07  The same key for two co-wives at once, from two accounts: one is recorded, the other is
--          request_key_reused (never a raw unique violation); one debit.
--   R2-01  The same key on two paths at once: a repayment not yet committed holds it, a former
--          member's payment and her request with that key wait, then are request_key_reused; when
--          the holder rolls back instead, the waiting call goes through.
-- ============================================================================
\set ON_ERROR_STOP on

DROP EXTENSION IF EXISTS dblink;
DROP SCHEMA IF EXISTS t61_dblink CASCADE;
CREATE SCHEMA t61_dblink;
CREATE EXTENSION dblink SCHEMA t61_dblink;

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
AS $$ SELECT ('e6100000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e61a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e61c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.d(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e61d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e61e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.r(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e61f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.b(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e61b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;

CREATE FUNCTION pg_temp.cleanup() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_hhs uuid[] := ARRAY(SELECT id FROM public.households WHERE id::text LIKE 'e61a%');
    v_users uuid[] := ARRAY(SELECT id FROM auth.users WHERE id::text LIKE 'e6100000%');
BEGIN
    DELETE FROM public.former_member_debts WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_deletion_storage_queue WHERE request_id::text LIKE 'e61f%';
    DELETE FROM public.account_deletion_requests WHERE id::text LIKE 'e61f%' OR user_id = ANY (v_users);
    -- Requests first: an outcome points at the repayment that approved it.
    DELETE FROM public.spouse_reimbursement_requests WHERE household_id = ANY (v_hhs);
    DELETE FROM public.spouse_reimbursements WHERE household_id = ANY (v_hhs);
    DELETE FROM public.nafaqah_request_keys WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_transfers WHERE household_id = ANY (v_hhs);
    DELETE FROM public.transactions WHERE household_id = ANY (v_hhs);
    DELETE FROM public.budgets WHERE household_id = ANY (v_hhs);
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
    PERFORM t61_dblink.dblink_connect(p_name, format('dbname=%s user=%s', current_database(), current_user));
    SELECT pid INTO v_pid FROM t61_dblink.dblink(p_name, 'SELECT pg_backend_pid()') AS t(pid int);
    RETURN v_pid;
END;
$$;

CREATE FUNCTION pg_temp.as_user(p_name text, p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM * FROM t61_dblink.dblink(p_name, format('SELECT set_config(%L, %L, false)', 'request.jwt.claims',
        jsonb_build_object('sub', p_user, 'role', 'authenticated')::text)) AS t(x text);
    PERFORM t61_dblink.dblink_exec(p_name, 'SET ROLE authenticated');
END;
$$;

CREATE FUNCTION pg_temp.wait(p_name text, p_pid int) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    FOR i IN 1..400 LOOP
        IF t61_dblink.dblink_is_busy(p_name) = 0 THEN
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
        SELECT r INTO v_res FROM t61_dblink.dblink_get_result(p_name) AS t(r text);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        v_res := 'ERR:' || v_state || ':' || COALESCE(v_hint, '');
    END;
    PERFORM * FROM t61_dblink.dblink_get_result(p_name, false) AS t(r text);
    RETURN COALESCE(v_res, 'ok');
END;
$$;

CREATE FUNCTION pg_temp.disconnect_all() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY COALESCE(t61_dblink.dblink_get_connections(), '{}') LOOP
        PERFORM t61_dblink.dblink_disconnect(v_name);
    END LOOP;
END;
$$;

-- Session 'blk' holds a budget row of the household, so a purge stops right after it has locked
-- the household FOR UPDATE (it locks pools, households, then budgets).
CREATE FUNCTION pg_temp.hold_budget(p_budget uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.connect('blk');
    PERFORM t61_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t61_dblink.dblink('blk', format('SELECT 1 FROM public.budgets WHERE id = %L FOR UPDATE', p_budget)) AS t(x int);
END;
$$;

CREATE FUNCTION pg_temp.repay_sql(p_hh int, p_wife int, p_amount numeric, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid)::text',
                  pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'cash', pg_temp.a(p_account), pg_temp.k(p_key));
$$;
CREATE FUNCTION pg_temp.fpay_sql(p_amount numeric, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
                  pg_temp.h(1), pg_temp.d(1), p_amount, 'cash', pg_temp.k(p_key), pg_temp.a(p_account));
$$;
CREATE FUNCTION pg_temp.req_sql(p_hh int, p_amount numeric, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.request_spouse_reimbursement(%L, %s, %L, %L::uuid, NULL)::text',
                  pg_temp.h(p_hh), p_amount, 'cash', pg_temp.k(p_key));
$$;
CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;
CREATE FUNCTION pg_temp.paid(p_debt int) RETURNS text LANGUAGE sql
AS $$ SELECT paid_amount::text FROM public.former_member_debts WHERE id = pg_temp.d(p_debt) $$;
CREATE FUNCTION pg_temp.verdict(p_res text) RETURNS text LANGUAGE sql
AS $$ SELECT CASE WHEN p_res LIKE 'ERR:%' THEN p_res ELSE 'recorded' END $$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();

-- ── Fixtures (committed) ────────────────────────────────────────────────────
-- H1: husband H(1) primary admin and provider, wives W(2) and W2(3), co-admin C(4).
--     Accounts: pool A1 5000 (H), H bank A2 1000, C bank A5 1000. W advanced 600, W2 100.
--     A former member's record D1 of 300. A budget B1. C is due for deletion (R4).
-- H3: primary admin O(11), husband P(12) the provider (a member), wife Q(13) who advanced 300.
--     A budget B3. Q is due for deletion (R13).
DO $$
DECLARE
    v_month date := date_trunc('month', now())::date;
BEGIN
    INSERT INTO auth.users (id, email) SELECT pg_temp.u(n), 't61-' || n || '@test.local' FROM unnest(ARRAY[1, 2, 3, 4, 11, 12, 13]) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T61 H1', 'T61CODE000000001', 'family'),
        (pg_temp.h(3), 'T61 H3', 'T61CODE000000003', 'family');
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'provider', true),
        (pg_temp.h(1), pg_temp.u(2), 'member', 'spouse', true),
        (pg_temp.h(1), pg_temp.u(3), 'member', 'spouse', true),
        (pg_temp.h(1), pg_temp.u(4), 'admin', 'family_member', true),
        (pg_temp.h(3), pg_temp.u(11), 'admin', 'family_member', true),
        (pg_temp.h(3), pg_temp.u(12), 'member', 'provider', true),
        (pg_temp.h(3), pg_temp.u(13), 'member', 'spouse', true);
    UPDATE public.users u SET household_id = m.household_id, role = m.role, financial_role = m.financial_role
    FROM public.household_memberships m WHERE m.user_id = u.id AND m.household_id::text LIKE 'e61a%';
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(11), nafaqah_provider_user_id = pg_temp.u(12) WHERE id = pg_temp.h(3);
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T61 pool', 'shared_pool', 5000, true),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(1), 'T61 his bank', 'bank', 1000, false),
        (pg_temp.a(5), pg_temp.h(1), pg_temp.u(4), 'T61 C bank', 'bank', 1000, false);
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(1), pg_temp.u(2), 600, 'T61 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(2)),
           (pg_temp.h(1), pg_temp.u(3), 100, 'T61 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(3)),
           (pg_temp.h(3), pg_temp.u(13), 300, 'T61 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(13));
    INSERT INTO public.former_member_debts (id, household_id, original_amount) VALUES (pg_temp.d(1), pg_temp.h(1), 300);
    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key, account_id) VALUES
        (pg_temp.b(1), pg_temp.h(1), v_month, 'OPEX-GROCERY', 900, public.nafaqah_current_cycle_key(pg_temp.h(1)), NULL),
        (pg_temp.b(3), pg_temp.h(3), v_month, 'OPEX-GROCERY', 900, public.nafaqah_current_cycle_key(pg_temp.h(3)), NULL);
    INSERT INTO public.account_deletion_requests (id, user_id, status, scheduled_for, attempts, lease_expires_at) VALUES
        (pg_temp.r(4), pg_temp.u(4), 'processing', now() - interval '1 minute', 1, now() + interval '30 minutes'),
        (pg_temp.r(13), pg_temp.u(13), 'processing', now() - interval '1 minute', 1, now() + interval '30 minutes');
END $$;

-- ── R2-05: her request while her purge holds the household ────────────────────────────────────
DO $$
DECLARE
    v_pg_pid int;
    v_w_pid int;
    v_purge text;
    v_req text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.hold_budget(pg_temp.b(3));
    v_pg_pid := pg_temp.connect('pg');
    PERFORM t61_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(13)));
    PERFORM pg_temp.expect('R2-05 the purge waits, holding the household', pg_temp.wait('pg', v_pg_pid), 'blocked');
    v_w_pid := pg_temp.connect('w');
    PERFORM pg_temp.as_user('w', pg_temp.u(13));
    PERFORM t61_dblink.dblink_send_query('w', pg_temp.req_sql(3, 50, 501));
    PERFORM pg_temp.expect('R2-05 her request waits for the household', pg_temp.wait('w', v_w_pid), 'blocked');
    PERFORM t61_dblink.dblink_exec('blk', 'COMMIT');
    v_purge := pg_temp.result('pg');
    v_req := pg_temp.result('w');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('R2-05 the purge prepared',
        CASE WHEN v_purge LIKE 'ERR:%' THEN v_purge ELSE v_purge::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('R2-05 her request is refused: she is no longer a member', v_req, 'ERR:42501:');
    PERFORM pg_temp.expect('R2-05 no request of hers is left',
        (SELECT count(*)::text FROM public.spouse_reimbursement_requests WHERE wife_user_id = pg_temp.u(13)), '0');
    PERFORM pg_temp.expect('R2-05 nor her key',
        (SELECT count(*)::text FROM public.nafaqah_request_keys WHERE household_id = pg_temp.h(3)), '0');
    PERFORM pg_temp.expect('R2-05 the household keeps what she was owed',
        (SELECT string_agg(original_amount::text || ':' || status, ',') FROM public.former_member_debts WHERE household_id = pg_temp.h(3)),
        '300.00:open');
    RAISE NOTICE 'PASSED: R2-05 her request racing her purge is refused, and no pending request of a non-member is left.';
END $$;

-- The husband is gone for this race (the provider cleared, committed: the other sessions read it),
-- so C, an admin who is not a wife, may pay her (review R3-01). He reverses his own account's
-- repayment as its owner, whatever the husband (review R1-07). The provider is back after it.
UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(1);

-- ── R2-08: a reversal while the payer's purge holds the household ─────────────────────────────
DO $$
DECLARE
    v_row uuid;
    v_pg_pid int;
    v_c_pid int;
    v_purge text;
    v_rev text;
    v_owed numeric;
BEGIN
    -- C paid W 40 from his own account (committed).
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('c0');
    PERFORM pg_temp.as_user('c0', pg_temp.u(4));
    v_row := ((SELECT r FROM t61_dblink.dblink('c0', pg_temp.repay_sql(1, 2, 40, 5, 801)) AS t(r text))::jsonb ->> 'reimbursement_id')::uuid;
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.expect('R2-08 C paid from his account', pg_temp.bal(5), '960.00');
    v_owed := public.nafaqah_outstanding(pg_temp.h(1), pg_temp.u(2));

    PERFORM pg_temp.hold_budget(pg_temp.b(1));
    v_pg_pid := pg_temp.connect('pg');
    PERFORM t61_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(4)));
    PERFORM pg_temp.expect('R2-08 his purge waits, holding the household', pg_temp.wait('pg', v_pg_pid), 'blocked');
    v_c_pid := pg_temp.connect('c');
    PERFORM pg_temp.as_user('c', pg_temp.u(4));
    PERFORM t61_dblink.dblink_send_query('c', format('SELECT public.reverse_spouse_reimbursement(%L, %L, %L::uuid, NULL)::text',
                                                     pg_temp.h(1), v_row, pg_temp.k(802)));
    PERFORM pg_temp.expect('R2-08 his reversal waits', pg_temp.wait('c', v_c_pid), 'blocked');
    PERFORM t61_dblink.dblink_exec('blk', 'COMMIT');
    v_purge := pg_temp.result('pg');
    v_rev := pg_temp.result('c');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('R2-08 the purge prepared',
        CASE WHEN v_purge LIKE 'ERR:%' THEN v_purge ELSE v_purge::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('R2-08 the reversal is refused as its account gone', v_rev, 'ERR:22023:reversal_account_unavailable');
    PERFORM pg_temp.expect('R2-08 the repayment stays', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE id = v_row), '1');
    PERFORM pg_temp.expect('R2-08 and is not reversed', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE reverses_id = v_row), '0');
    PERFORM pg_temp.expect('R2-08 what is owed did not move', public.nafaqah_outstanding(pg_temp.h(1), pg_temp.u(2))::text, v_owed::text);
    RAISE NOTICE 'PASSED: R2-08 a reversal racing its payer''s purge is refused as reversal_account_unavailable.';
END $$;

UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);

-- ── R2-07: the same key for two co-wives at once ──────────────────────────────────────────────
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_a text;
    v_b text;
    v_total numeric := (SELECT sum(balance) FROM public.accounts WHERE id IN (pg_temp.a(1), pg_temp.a(2)));
BEGIN
    -- Both wives' advisory locks held, so both calls pass their own replay checks before either
    -- records; then they pay from two accounts and meet only at the key.
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    PERFORM t61_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t61_dblink.dblink('blk', format('SELECT pg_advisory_xact_lock(hashtextextended(%L, 0))::text',
        'spouse_reimbursement:' || pg_temp.h(1)::text || ':' || pg_temp.u(2)::text)) AS t(x text);
    PERFORM * FROM t61_dblink.dblink('blk', format('SELECT pg_advisory_xact_lock(hashtextextended(%L, 0))::text',
        'spouse_reimbursement:' || pg_temp.h(1)::text || ':' || pg_temp.u(3)::text)) AS t(x text);
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(1));
    PERFORM t61_dblink.dblink_send_query('t1', pg_temp.repay_sql(1, 2, 10, 2, 701));
    PERFORM pg_temp.expect('R2-07 the first waits', pg_temp.wait('t1', v_p1), 'blocked');
    PERFORM t61_dblink.dblink_send_query('t2', pg_temp.repay_sql(1, 3, 10, 1, 701));
    PERFORM pg_temp.expect('R2-07 the second waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t61_dblink.dblink_exec('blk', 'ROLLBACK');
    v_a := pg_temp.result('t1');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('R2-07 one recorded, the other request_key_reused',
        (SELECT string_agg(x, ',' ORDER BY x COLLATE "C") FROM unnest(ARRAY[pg_temp.verdict(v_a), pg_temp.verdict(v_b)]) AS x),
        'ERR:22023:request_key_reused,recorded');
    PERFORM pg_temp.expect('R2-07 one debit',
        (v_total - (SELECT sum(balance) FROM public.accounts WHERE id IN (pg_temp.a(1), pg_temp.a(2))))::text, '10.00');
    PERFORM pg_temp.expect('R2-07 one row under the key',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE household_id = pg_temp.h(1) AND request_key = pg_temp.k(701)), '1');
    RAISE NOTICE 'PASSED: R2-07 the same key for two co-wives at once records one and names the other request_key_reused.';
END $$;

-- ── R2-01: the same key on two paths at once ──────────────────────────────────────────────────
DO $$
DECLARE
    v_p1 int;
    v_p2 int;
    v_hold text;
    v_b text;
    v_pool numeric := (SELECT balance FROM public.accounts WHERE id = pg_temp.a(1));
    v_bank numeric := (SELECT balance FROM public.accounts WHERE id = pg_temp.a(2));
BEGIN
    -- A repayment with key 901, not committed yet; a former member's payment with key 901 from the pool.
    PERFORM pg_temp.disconnect_all();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(1));
    PERFORM t61_dblink.dblink_exec('t1', 'BEGIN');
    v_hold := (SELECT r FROM t61_dblink.dblink('t1', pg_temp.repay_sql(1, 2, 10, 2, 901)) AS t(r text));
    PERFORM pg_temp.expect('R2-01 the repayment, not committed', v_hold::jsonb ->> 'success', 'true');
    PERFORM t61_dblink.dblink_send_query('t2', pg_temp.fpay_sql(10, 1, 901));
    PERFORM pg_temp.expect('R2-01 the payment with its key waits for it', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t61_dblink.dblink_exec('t1', 'COMMIT');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.expect('R2-01 then is request_key_reused', v_b, 'ERR:22023:request_key_reused');
    PERFORM pg_temp.expect('R2-01 the pool did not move', (SELECT balance FROM public.accounts WHERE id = pg_temp.a(1))::text, v_pool::text);
    PERFORM pg_temp.expect('R2-01 the record did not move', pg_temp.paid(1), '0.00');
    PERFORM pg_temp.expect('R2-01 his bank moved once', (v_bank - (SELECT balance FROM public.accounts WHERE id = pg_temp.a(2)))::text, '10.00');

    -- A former member's payment with key 903, not committed; her request with key 903 waits, then is refused.
    PERFORM pg_temp.disconnect_all();
    v_p1 := pg_temp.connect('t1');
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM pg_temp.as_user('t2', pg_temp.u(2));
    PERFORM t61_dblink.dblink_exec('t1', 'BEGIN');
    v_hold := (SELECT r FROM t61_dblink.dblink('t1', pg_temp.fpay_sql(15, 1, 903)) AS t(r text));
    PERFORM t61_dblink.dblink_send_query('t2', pg_temp.req_sql(1, 5, 903));
    PERFORM pg_temp.expect('R2-01 her request with its key waits for it', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t61_dblink.dblink_exec('t1', 'COMMIT');
    PERFORM pg_temp.expect('R2-01 then is request_key_reused', pg_temp.result('t2'), 'ERR:22023:request_key_reused');
    PERFORM pg_temp.expect('R2-01 the payment went through', pg_temp.paid(1), '15.00');
    PERFORM pg_temp.expect('R2-01 no request of hers under it',
        (SELECT count(*)::text FROM public.spouse_reimbursement_requests WHERE request_key = pg_temp.k(903)), '0');

    -- The holder rolls back instead: the key is free again, and the waiting call goes through.
    PERFORM t61_dblink.dblink_exec('t1', 'BEGIN');
    v_hold := (SELECT r FROM t61_dblink.dblink('t1', pg_temp.repay_sql(1, 3, 10, 2, 904)) AS t(r text));
    PERFORM t61_dblink.dblink_send_query('t2', pg_temp.req_sql(1, 5, 904));
    PERFORM pg_temp.expect('R2-01 her request waits for the uncommitted key', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t61_dblink.dblink_exec('t1', 'ROLLBACK');
    PERFORM pg_temp.expect('R2-01 then goes through', (pg_temp.result('t2'))::jsonb ->> 'status', 'pending');
    PERFORM pg_temp.disconnect_all();
    RAISE NOTICE 'PASSED: R2-01 the same key on two paths at once moves money once; the other call is request_key_reused.';
END $$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();
DROP EXTENSION dblink;
DROP SCHEMA t61_dblink;
