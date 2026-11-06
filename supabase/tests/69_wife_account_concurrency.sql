-- ============================================================================
-- Test 69: The wife account under concurrency (owner decisions 2026-11-06)
--
-- Migration: 20261105001300_wife_repayment_debit.sql, sections 5, 8 and 12
--
-- Like tests 57 and 61 this one commits: the races need other sessions, which only see committed
-- rows. They are dblink connections back into this database. dblink goes in its own schema and is
-- dropped at the end, with every fixture row (all ids start with e69).
--
-- Each race is made deterministic with an open transaction held by another session, never with
-- sleeps. Her wife account starts each race with a known balance:
--   C1  A repayment into her wife account not yet committed: her purchase from it waits, then goes
--       through; the account moved by exactly +repayment -purchase, his by exactly -repayment.
--   C2  Her purchase not yet committed: the repayment waits for the account, then goes through;
--       the same exact sums.
--   C3  Her purchase of most of it not yet committed: the reversal waits, then is refused as
--       wife_account_insufficient_funds; nothing of the reversal moved, its key is unused.
--   C4  A reversal not yet committed: her purchase waits, then goes through; the account moved by
--       exactly -reversal -purchase, his by exactly +reversal.
--   C5  The same repayment twice at once (one key): one is recorded, the other answers it again;
--       one credit, one debit.
-- ============================================================================
\set ON_ERROR_STOP on

DROP EXTENSION IF EXISTS dblink;
DROP SCHEMA IF EXISTS t69_dblink CASCADE;
CREATE SCHEMA t69_dblink;
CREATE EXTENSION dblink SCHEMA t69_dblink;

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
AS $$ SELECT ('e6900000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e69a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e69c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e69e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e69f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
-- Her wife account: the one assigned to W in the fixture household.
CREATE FUNCTION pg_temp.wa() RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.accounts WHERE household_id = pg_temp.h(1) AND account_type = 'wife' $$;

CREATE FUNCTION pg_temp.cleanup() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_hhs uuid[] := ARRAY(SELECT id FROM public.households WHERE id::text LIKE 'e69a%');
    v_users uuid[] := ARRAY(SELECT id FROM auth.users WHERE id::text LIKE 'e6900000%');
BEGIN
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
    DELETE FROM auth.users WHERE id = ANY (v_users);
END;
$$;

CREATE FUNCTION pg_temp.connect(p_name text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    v_pid int;
BEGIN
    PERFORM t69_dblink.dblink_connect(p_name, format('dbname=%s user=%s', current_database(), current_user));
    SELECT pid INTO v_pid FROM t69_dblink.dblink(p_name, 'SELECT pg_backend_pid()') AS t(pid int);
    RETURN v_pid;
END;
$$;

CREATE FUNCTION pg_temp.as_user(p_name text, p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM * FROM t69_dblink.dblink(p_name, format('SELECT set_config(%L, %L, false)', 'request.jwt.claims',
        jsonb_build_object('sub', p_user, 'role', 'authenticated')::text)) AS t(x text);
    PERFORM t69_dblink.dblink_exec(p_name, 'SET ROLE authenticated');
END;
$$;

CREATE FUNCTION pg_temp.wait(p_name text, p_pid int) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    FOR i IN 1..400 LOOP
        IF t69_dblink.dblink_is_busy(p_name) = 0 THEN
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
        SELECT r INTO v_res FROM t69_dblink.dblink_get_result(p_name) AS t(r text);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        v_res := 'ERR:' || v_state || ':' || COALESCE(v_hint, '');
    END;
    PERFORM * FROM t69_dblink.dblink_get_result(p_name, false) AS t(r text);
    RETURN COALESCE(v_res, 'ok');
END;
$$;

CREATE FUNCTION pg_temp.disconnect_all() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY COALESCE(t69_dblink.dblink_get_connections(), '{}') LOOP
        PERFORM t69_dblink.dblink_disconnect(v_name);
    END LOOP;
END;
$$;

-- The calls, as SQL text for a session that already is the user.
CREATE FUNCTION pg_temp.repay_sql(p_amount numeric, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid, %L::uuid)::text',
                  pg_temp.h(1), pg_temp.u(2), p_amount, 'cash', pg_temp.a(1), pg_temp.k(p_key), pg_temp.wa());
$$;
CREATE FUNCTION pg_temp.rev_sql(p_row uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT format('SELECT public.reverse_spouse_reimbursement(%L, %L, %L::uuid, NULL)::text', pg_temp.h(1), p_row, pg_temp.k(p_key));
$$;
-- Her purchase from her wife account, as the app inserts it.
CREATE FUNCTION pg_temp.spend_sql(p_id int, p_amount numeric) RETURNS text LANGUAGE sql AS $$
    SELECT format('INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, '
                  'nafaqah_class, nafaqah_spouse_id, account_id) VALUES (%L, %L, %L, %s, %L, %L, now(), %L, %L, %L, %L, %L) RETURNING id::text',
                  pg_temp.t(p_id), pg_temp.h(1), pg_temp.u(2), p_amount, 'T69 shop', 'OPEX-SHOPPING', 'manual', 'me',
                  'wife_personal', pg_temp.u(2), pg_temp.wa());
$$;
CREATE FUNCTION pg_temp.bal(p_id uuid) RETURNS numeric LANGUAGE sql
AS $$ SELECT balance FROM public.accounts WHERE id = p_id $$;
-- A committed repayment of p_amount (his bank into her wife account), by H in its own session.
CREATE FUNCTION pg_temp.repaid(p_amount numeric, p_key int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_res text;
BEGIN
    PERFORM pg_temp.connect('r0');
    PERFORM pg_temp.as_user('r0', pg_temp.u(1));
    SELECT r INTO v_res FROM t69_dblink.dblink('r0', pg_temp.repay_sql(p_amount, p_key)) AS t(r text);
    PERFORM t69_dblink.dblink_disconnect('r0');
    RETURN (v_res::jsonb ->> 'reimbursement_id')::uuid;
END;
$$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();

-- ── Fixtures (committed) ────────────────────────────────────────────────────
-- H1: husband H(1) primary admin and provider; wife W(2), who advanced 5000. H's bank A1 10000.
--     Her wife account, made by H through the RPC.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) SELECT pg_temp.u(n), 't69-' || n || '@test.local' FROM unnest(ARRAY[1, 2]) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES (pg_temp.h(1), 'T69 H1', 'T69CODE000000001', 'family');
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'provider', true),
        (pg_temp.h(1), pg_temp.u(2), 'member', 'spouse', true);
    UPDATE public.users u SET household_id = m.household_id, role = m.role, financial_role = m.financial_role
    FROM public.household_memberships m WHERE m.user_id = u.id AND m.household_id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T69 his bank', 'bank', 10000, false);
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(1), pg_temp.u(2), 5000, 'T69 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me', 'wife_reimbursable', pg_temp.u(2));
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.u(1))::text, true);
    SET LOCAL ROLE authenticated;
    PERFORM public.create_wife_account(pg_temp.h(1), pg_temp.u(2), 'T69 her account', NULL);
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- ── C1: a repayment not yet committed, her purchase waits ────────────────────────────────────
DO $$
DECLARE
    v_wa0 numeric := pg_temp.bal(pg_temp.wa());
    v_his0 numeric := pg_temp.bal(pg_temp.a(1));
    v_w_pid int;
    v_rep text;
    v_buy text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('h');
    PERFORM pg_temp.as_user('h', pg_temp.u(1));
    PERFORM t69_dblink.dblink_exec('h', 'BEGIN');
    SELECT r INTO v_rep FROM t69_dblink.dblink('h', pg_temp.repay_sql(100, 1)) AS t(r text);
    v_w_pid := pg_temp.connect('w');
    PERFORM pg_temp.as_user('w', pg_temp.u(2));
    PERFORM t69_dblink.dblink_send_query('w', pg_temp.spend_sql(1, 30));
    PERFORM pg_temp.expect('C1 her purchase waits for the repayment', pg_temp.wait('w', v_w_pid), 'blocked');
    PERFORM t69_dblink.dblink_exec('h', 'COMMIT');
    v_buy := pg_temp.result('w');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('C1 the repayment credited her account', v_rep::jsonb ->> 'wife_account_id', pg_temp.wa()::text);
    PERFORM pg_temp.expect('C1 her purchase went through', v_buy, pg_temp.t(1)::text);
    PERFORM pg_temp.expect('C1 her account: +100 -30 exactly', pg_temp.bal(pg_temp.wa())::text, (v_wa0 + 100 - 30)::numeric(14, 2)::text);
    PERFORM pg_temp.expect('C1 his account: -100 exactly', pg_temp.bal(pg_temp.a(1))::text, (v_his0 - 100)::numeric(14, 2)::text);
    PERFORM pg_temp.expect('C1 one transfer', (SELECT count(*)::text FROM public.account_transfers
                                               WHERE household_id = pg_temp.h(1) AND purpose = 'wife_repayment'), '1');
    RAISE NOTICE 'PASSED: C1 a repayment into her wife account, then her purchase from it: both, exactly once.';
END $$;

-- ── C2: her purchase not yet committed, the repayment waits ──────────────────────────────────
DO $$
DECLARE
    v_wa0 numeric := pg_temp.bal(pg_temp.wa());
    v_his0 numeric := pg_temp.bal(pg_temp.a(1));
    v_h_pid int;
    v_rep text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('w');
    PERFORM pg_temp.as_user('w', pg_temp.u(2));
    PERFORM t69_dblink.dblink_exec('w', 'BEGIN');
    PERFORM * FROM t69_dblink.dblink('w', pg_temp.spend_sql(2, 50)) AS t(r text);
    v_h_pid := pg_temp.connect('h');
    PERFORM pg_temp.as_user('h', pg_temp.u(1));
    PERFORM t69_dblink.dblink_send_query('h', pg_temp.repay_sql(200, 2));
    PERFORM pg_temp.expect('C2 the repayment waits for her purchase', pg_temp.wait('h', v_h_pid), 'blocked');
    PERFORM t69_dblink.dblink_exec('w', 'COMMIT');
    v_rep := pg_temp.result('h');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('C2 the repayment went through', v_rep::jsonb ->> 'amount', '200.00');
    PERFORM pg_temp.expect('C2 her account: -50 +200 exactly', pg_temp.bal(pg_temp.wa())::text, (v_wa0 - 50 + 200)::numeric(14, 2)::text);
    PERFORM pg_temp.expect('C2 his account: -200 exactly', pg_temp.bal(pg_temp.a(1))::text, (v_his0 - 200)::numeric(14, 2)::text);
    RAISE NOTICE 'PASSED: C2 her purchase from her wife account, then a repayment into it: both, exactly once.';
END $$;

-- ── C3: her purchase of most of it not yet committed, the reversal waits and is refused ───────
DO $$
DECLARE
    v_row uuid := pg_temp.repaid(300, 3);
    v_wa0 numeric;
    v_his0 numeric;
    v_spend numeric;
    v_h_pid int;
    v_rev text;
BEGIN
    v_wa0 := pg_temp.bal(pg_temp.wa());
    v_his0 := pg_temp.bal(pg_temp.a(1));
    v_spend := v_wa0 - 100;  -- leaves 100, less than the 300 to take back
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('w');
    PERFORM pg_temp.as_user('w', pg_temp.u(2));
    PERFORM t69_dblink.dblink_exec('w', 'BEGIN');
    PERFORM * FROM t69_dblink.dblink('w', pg_temp.spend_sql(3, v_spend)) AS t(r text);
    v_h_pid := pg_temp.connect('h');
    PERFORM pg_temp.as_user('h', pg_temp.u(1));
    PERFORM t69_dblink.dblink_send_query('h', pg_temp.rev_sql(v_row, 4));
    PERFORM pg_temp.expect('C3 the reversal waits for her purchase', pg_temp.wait('h', v_h_pid), 'blocked');
    PERFORM t69_dblink.dblink_exec('w', 'COMMIT');
    v_rev := pg_temp.result('h');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('C3 the reversal is refused', v_rev, 'ERR:22000:wife_account_insufficient_funds');
    PERFORM pg_temp.expect('C3 her account: only her purchase', pg_temp.bal(pg_temp.wa())::text, '100.00');
    PERFORM pg_temp.expect('C3 his account: unchanged', pg_temp.bal(pg_temp.a(1))::text, v_his0::text);
    PERFORM pg_temp.expect('C3 not reversed', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE reverses_id = v_row), '0');
    PERFORM pg_temp.expect('C3 its key unused', (SELECT count(*)::text FROM public.nafaqah_request_keys WHERE request_key = pg_temp.k(4)), '0');
    RAISE NOTICE 'PASSED: C3 a reversal racing her purchase that leaves too little is refused, and nothing of it moves.';
END $$;

-- ── C4: a reversal not yet committed, her purchase waits ─────────────────────────────────────
DO $$
DECLARE
    v_row uuid := pg_temp.repaid(400, 5);
    v_wa0 numeric;
    v_his0 numeric;
    v_w_pid int;
    v_rev text;
    v_buy text;
BEGIN
    v_wa0 := pg_temp.bal(pg_temp.wa());
    v_his0 := pg_temp.bal(pg_temp.a(1));
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('h');
    PERFORM pg_temp.as_user('h', pg_temp.u(1));
    PERFORM t69_dblink.dblink_exec('h', 'BEGIN');
    SELECT r INTO v_rev FROM t69_dblink.dblink('h', pg_temp.rev_sql(v_row, 6)) AS t(r text);
    v_w_pid := pg_temp.connect('w');
    PERFORM pg_temp.as_user('w', pg_temp.u(2));
    PERFORM t69_dblink.dblink_send_query('w', pg_temp.spend_sql(4, 60));
    PERFORM pg_temp.expect('C4 her purchase waits for the reversal', pg_temp.wait('w', v_w_pid), 'blocked');
    PERFORM t69_dblink.dblink_exec('h', 'COMMIT');
    v_buy := pg_temp.result('w');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('C4 reversed', v_rev::jsonb ->> 'kind', 'reversal');
    PERFORM pg_temp.expect('C4 her purchase went through', v_buy, pg_temp.t(4)::text);
    PERFORM pg_temp.expect('C4 her account: -400 -60 exactly', pg_temp.bal(pg_temp.wa())::text, (v_wa0 - 400 - 60)::numeric(14, 2)::text);
    PERFORM pg_temp.expect('C4 his account: +400 exactly', pg_temp.bal(pg_temp.a(1))::text, (v_his0 + 400)::numeric(14, 2)::text);
    RAISE NOTICE 'PASSED: C4 a reversal out of her wife account, then her purchase from it: both, exactly once.';
END $$;

-- ── C5: the same repayment twice at once ─────────────────────────────────────────────────────
DO $$
DECLARE
    v_wa0 numeric := pg_temp.bal(pg_temp.wa());
    v_his0 numeric := pg_temp.bal(pg_temp.a(1));
    v_p2 int;
    v_a text;
    v_b text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('t1');
    PERFORM pg_temp.as_user('t1', pg_temp.u(1));
    PERFORM t69_dblink.dblink_exec('t1', 'BEGIN');
    SELECT r INTO v_a FROM t69_dblink.dblink('t1', pg_temp.repay_sql(70, 7)) AS t(r text);
    v_p2 := pg_temp.connect('t2');
    PERFORM pg_temp.as_user('t2', pg_temp.u(1));
    PERFORM t69_dblink.dblink_send_query('t2', pg_temp.repay_sql(70, 7));
    PERFORM pg_temp.expect('C5 the second waits', pg_temp.wait('t2', v_p2), 'blocked');
    PERFORM t69_dblink.dblink_exec('t1', 'COMMIT');
    v_b := pg_temp.result('t2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('C5 the first recorded', v_a::jsonb ->> 'replayed', 'false');
    PERFORM pg_temp.expect('C5 the second answers it again', (v_b::jsonb ->> 'replayed') || '|' || (v_b::jsonb ->> 'reimbursement_id'),
                           'true|' || (v_a::jsonb ->> 'reimbursement_id'));
    PERFORM pg_temp.expect('C5 one credit', pg_temp.bal(pg_temp.wa())::text, (v_wa0 + 70)::numeric(14, 2)::text);
    PERFORM pg_temp.expect('C5 one debit', pg_temp.bal(pg_temp.a(1))::text, (v_his0 - 70)::numeric(14, 2)::text);
    RAISE NOTICE 'PASSED: C5 the same repayment twice at once credits her wife account once.';
END $$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();
DROP SCHEMA t69_dblink CASCADE;
