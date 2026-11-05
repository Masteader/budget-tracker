-- ============================================================================
-- Test 51: account deletion and budget activation under concurrency (several sessions)
--
-- Migrations: 20261105000300_account_deletion_purge.sql, 20261105000800_account_deletion_operator_request.sql,
--             20261105001000_inactive_category_budgets.sql, 20261105001100_last_admin_household_lock.sql
--
-- Unlike the other tests this one commits: the races need a second session, which only sees
-- committed rows. The sessions are dblink connections back into this database, so it runs only
-- against a local Postgres where the runner's user is a superuser that may connect without a
-- password (the Docker setup in run_tests.py). dblink goes in its own schema and is dropped at
-- the end, with every fixture row (all ids start with e51).
--
-- Each race is made deterministic with a lock held by a third session, never with sleeps:
--   1. Purge vs. an expense in an unrelated household: no false purge_ledger_invariant.
--      And a direct change to a budget or pool the purge covers waits for the purge.
--   2. Budget activation vs. an expense being saved in that inactive category: it counts.
--   3. Budget activation vs. an expense being deleted from it: it does not count.
--   4. A co-admin's purge vs. the primary admin leaving: the household keeps an admin. And
--      two admin removals on any path, one waiting for the other: the second is refused.
--   5. A primary's purge deleting a household vs. a co-admin leaving it: no deadlock.
--   6. Prepare vs. cancel on the same request: no deadlock.
-- ============================================================================
\set ON_ERROR_STOP on

DROP EXTENSION IF EXISTS dblink;
DROP SCHEMA IF EXISTS t51_dblink CASCADE;
CREATE SCHEMA t51_dblink;
CREATE EXTENSION dblink SCHEMA t51_dblink;

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
AS $$ SELECT ('e5100000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e51a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.b(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e51b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.r(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e51d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e51e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e51c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.i(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e51f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;

-- Every fixture row, in an order the guards accept. Safe to run when there is nothing.
CREATE FUNCTION pg_temp.cleanup() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_hhs uuid[] := ARRAY(SELECT id FROM public.households WHERE id::text LIKE 'e51a%');
    v_users uuid[] := ARRAY(SELECT id FROM auth.users WHERE id::text LIKE 'e5100000%');
BEGIN
    DELETE FROM public.account_deletion_storage_queue WHERE request_id::text LIKE 'e51d%';
    DELETE FROM public.account_deletion_requests WHERE id::text LIKE 'e51d%' OR user_id = ANY (v_users);
    DELETE FROM public.transactions WHERE household_id = ANY (v_hhs);
    DELETE FROM public.budgets WHERE household_id = ANY (v_hhs);
    DELETE FROM public.income_records WHERE household_id = ANY (v_hhs);
    DELETE FROM public.account_transfers WHERE household_id = ANY (v_hhs);
    DELETE FROM public.accounts WHERE household_id = ANY (v_hhs);
    UPDATE public.households SET deletion_requested_at = NULL, deletion_scheduled_for = NULL, deletion_requested_by = NULL
    WHERE id = ANY (v_hhs);
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
    PERFORM t51_dblink.dblink_connect(p_name, format('dbname=%s user=%s', current_database(), current_user));
    SELECT pid INTO v_pid FROM t51_dblink.dblink(p_name, 'SELECT pg_backend_pid()') AS t(pid int);
    RETURN v_pid;
END;
$$;

-- A connection that acts as a signed-in user.
CREATE FUNCTION pg_temp.as_user(p_name text, p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM * FROM t51_dblink.dblink(p_name, format('SELECT set_config(%L, %L, false)', 'request.jwt.claims',
        jsonb_build_object('sub', p_user, 'role', 'authenticated')::text)) AS t(x text);
    PERFORM t51_dblink.dblink_exec(p_name, 'SET ROLE authenticated');
END;
$$;

-- 'done' when the connection's query has finished, 'blocked' when its session waits on a lock.
CREATE FUNCTION pg_temp.wait(p_name text, p_pid int) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    FOR i IN 1..400 LOOP
        IF t51_dblink.dblink_is_busy(p_name) = 0 THEN
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

-- The text result of the query sent on p_name, or ERR:<sqlstate>:<hint>.
CREATE FUNCTION pg_temp.result(p_name text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_res text;
    v_state text;
    v_hint text;
BEGIN
    BEGIN
        SELECT r INTO v_res FROM t51_dblink.dblink_get_result(p_name) AS t(r text);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        v_res := 'ERR:' || v_state || ':' || COALESCE(v_hint, '');
    END;
    -- Drain, so the connection can be used again.
    PERFORM * FROM t51_dblink.dblink_get_result(p_name, false) AS t(r text);
    RETURN COALESCE(v_res, 'ok');
END;
$$;

-- 'locked' when another session holds a lock on the household row, else 'free'. Takes nothing.
CREATE FUNCTION pg_temp.row_lock_state(p_household uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        PERFORM 1 FROM public.households WHERE id = p_household FOR UPDATE NOWAIT;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'free';
    EXCEPTION
        WHEN lock_not_available THEN RETURN 'locked';
        WHEN raise_exception THEN RETURN 'free';
    END;
END;
$$;

CREATE FUNCTION pg_temp.disconnect_all() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY COALESCE(t51_dblink.dblink_get_connections(), '{}') LOOP
        PERFORM t51_dblink.dblink_disconnect(v_name);
    END LOOP;
END;
$$;

SELECT pg_temp.cleanup();

-- ── Fixtures (committed) ────────────────────────────────────────────────────
DO $$
DECLARE
    v_month date := date_trunc('month', now())::date;
BEGIN
    INSERT INTO auth.users (id, email) SELECT pg_temp.u(n), 't51-' || n || '@test.local' FROM generate_series(1, 70) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type)
    SELECT pg_temp.h(n), 'T51 H' || n, 'T51CODE' || lpad(n::text, 9, '0'), 'roommates'
    FROM unnest(ARRAY[1, 2, 9, 31, 32, 41, 42, 51, 61]) AS n;

    -- Admins first: the first admin of a household becomes its primary admin.
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    SELECT pg_temp.h(m.hh), pg_temp.u(m.usr), m.role, 'peer', true
    FROM (VALUES (1, 2, 'admin', 1), (1, 1, 'member', 2), (9, 3, 'admin', 3),
                 (2, 5, 'admin', 14), (2, 4, 'member', 15),
                 (31, 31, 'admin', 4), (32, 32, 'admin', 5),
                 (41, 41, 'admin', 6), (41, 42, 'admin', 7), (41, 43, 'member', 8),
                 (42, 44, 'admin', 16), (42, 45, 'admin', 17), (42, 46, 'member', 18),
                 (51, 51, 'admin', 9), (51, 52, 'admin', 10), (51, 53, 'member', 11),
                 (61, 62, 'admin', 12), (61, 61, 'member', 13)) AS m(hh, usr, role, ord)
    ORDER BY m.ord;
    UPDATE public.users u SET household_id = m.household_id, role = m.role
    FROM public.household_memberships m WHERE m.user_id = u.id AND u.id::text LIKE 'e5100000%';

    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key, is_active)
    SELECT pg_temp.b(n), pg_temp.h(n), v_month, 'OPEX-GROCERY', 1000, public.nafaqah_current_cycle_key(pg_temp.h(n)), n NOT IN (31, 32)
    FROM unnest(ARRAY[1, 2, 9, 31, 32]) AS n;
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool)
    VALUES (pg_temp.a(2), pg_temp.h(2), pg_temp.u(5), 'T51 pool', 'shared_pool', 500, true),
           (pg_temp.a(51), pg_temp.h(51), pg_temp.u(51), 'T51 pool 51', 'shared_pool', 100, true);
    -- Income in H51, which the household deletion removes first.
    INSERT INTO public.income_records (id, household_id, user_id, account_id, cycle_key, source_type, title, base_amount, net_amount)
    VALUES (pg_temp.i(51), pg_temp.h(51), pg_temp.u(53), pg_temp.a(51), public.nafaqah_current_cycle_key(pg_temp.h(51)), 'other', 'T51 income', 5, 5);

    -- An expense recorded while the category is inactive: it counts in no budget.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, cycle_key, source, spent_by)
    VALUES (pg_temp.t(32), pg_temp.h(32), pg_temp.u(32), 25, 'T51 old', 'OPEX-GROCERY', now(),
            public.nafaqah_current_cycle_key(pg_temp.h(32)), 'manual', 'me');

    -- Due, claimed requests (the RPCs that schedule them are tested elsewhere).
    INSERT INTO public.account_deletion_requests (id, user_id, status, scheduled_for, attempts, lease_expires_at)
    SELECT pg_temp.r(n), pg_temp.u(n), 'processing', now() - interval '1 minute', 1, now() + interval '30 minutes'
    FROM unnest(ARRAY[1, 4, 42, 51, 61]) AS n;
    -- X (51) chose to delete H51.
    UPDATE public.households
    SET deletion_requested_at = now(), deletion_scheduled_for = now() - interval '1 minute', deletion_requested_by = pg_temp.u(51)
    WHERE id = pg_temp.h(51);
END $$;

DO $$
BEGIN
    PERFORM pg_temp.expect('H32 inactive row holds nothing',
        (SELECT spent_amount::text || '/' || is_active::text FROM public.budgets WHERE id = pg_temp.b(32)), '0.00/false');
    PERFORM pg_temp.expect('P is the primary admin of H41', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(41)), pg_temp.u(41)::text);
    PERFORM pg_temp.expect('X is the primary admin of H51', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(51)), pg_temp.u(51)::text);
END $$;

-- 1. Purge vs. an expense in an unrelated household -------------------------------------------
DO $$
DECLARE
    v_pid int;
    v_res text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('lk');
    v_pid := pg_temp.connect('pg');
    PERFORM pg_temp.connect('ex');
    -- Holds X's membership, so the purge stops between its two ledger snapshots.
    PERFORM t51_dblink.dblink_exec('lk', 'BEGIN');
    PERFORM * FROM t51_dblink.dblink('lk', format('SELECT 1 FROM public.household_memberships WHERE user_id = %L FOR UPDATE', pg_temp.u(1))) AS t(x int);
    PERFORM t51_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(1)));
    PERFORM pg_temp.expect('the purge waits between its snapshots', pg_temp.wait('pg', v_pid), 'blocked');
    -- Meanwhile Z, in a household X never belonged to, records an expense.
    PERFORM t51_dblink.dblink_exec('ex', format(
        $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, cycle_key, source, spent_by)
           VALUES (%L, %L, 33, 'T51 Z', 'OPEX-GROCERY', now(), public.nafaqah_current_cycle_key(%L), 'manual', 'me')$q$,
        pg_temp.h(9), pg_temp.u(3), pg_temp.h(9)));
    PERFORM t51_dblink.dblink_exec('lk', 'ROLLBACK');
    v_res := pg_temp.result('pg');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('the purge is not refused', CASE WHEN v_res LIKE 'ERR:%' THEN v_res ELSE v_res::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('prepared', (SELECT stage FROM public.account_deletion_requests WHERE id = pg_temp.r(1)), 'db_prepared');
    PERFORM pg_temp.expect('Z''s expense counted in Z''s budget', (SELECT spent_amount::text FROM public.budgets WHERE id = pg_temp.b(9)), '33.00');
    RAISE NOTICE 'PASSED: an unrelated household''s expense does not abort a purge.';
END $$;

-- 1b. Purge vs. a direct change to a budget and a pool it covers --------------------------------
DO $$
DECLARE
    v_pid int;
    v_b_pid int;
    v_a_pid int;
    v_res text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('lk');
    v_pid := pg_temp.connect('pg');
    v_b_pid := pg_temp.connect('ub');
    v_a_pid := pg_temp.connect('ua');
    PERFORM t51_dblink.dblink_exec('lk', 'BEGIN');
    PERFORM * FROM t51_dblink.dblink('lk', format('SELECT 1 FROM public.household_memberships WHERE user_id = %L FOR UPDATE', pg_temp.u(4))) AS t(x int);
    PERFORM t51_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(4)));
    PERFORM pg_temp.expect('the purge waits between its snapshots', pg_temp.wait('pg', v_pid), 'blocked');
    -- The household's budget and pool, changed directly (a recompute, a balance correction).
    PERFORM t51_dblink.dblink_send_query('ub', format('UPDATE public.budgets SET spent_amount = spent_amount + 7 WHERE id = %L', pg_temp.b(2)));
    PERFORM pg_temp.expect('the budget change waits for the purge', pg_temp.wait('ub', v_b_pid), 'blocked');
    PERFORM t51_dblink.dblink_send_query('ua', format('UPDATE public.accounts SET balance = balance + 7 WHERE id = %L', pg_temp.a(2)));
    PERFORM pg_temp.expect('the pool change waits for the purge', pg_temp.wait('ua', v_a_pid), 'blocked');
    PERFORM t51_dblink.dblink_exec('lk', 'ROLLBACK');
    v_res := pg_temp.result('pg');
    PERFORM pg_temp.expect('then the budget change', pg_temp.result('ub'), 'UPDATE 1');
    PERFORM pg_temp.expect('then the pool change', pg_temp.result('ua'), 'UPDATE 1');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('the purge is not refused', CASE WHEN v_res LIKE 'ERR:%' THEN v_res ELSE v_res::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('both changes landed after it',
        (SELECT spent_amount::text FROM public.budgets WHERE id = pg_temp.b(2)) || '/' || (SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(2)),
        '7.00/507.00');
    RAISE NOTICE 'PASSED: a budget or pool the purge covers is locked before its first snapshot.';
END $$;

-- 2. Activation vs. an expense being saved --------------------------------------------------------
DO $$
DECLARE
    v_pid int;
    v_res text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('ex');
    v_pid := pg_temp.connect('ac');
    PERFORM t51_dblink.dblink_exec('ex', 'BEGIN');
    PERFORM t51_dblink.dblink_exec('ex', format(
        $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, cycle_key, source, spent_by)
           VALUES (%L, %L, 40, 'T51 new', 'OPEX-GROCERY', now(), public.nafaqah_current_cycle_key(%L), 'manual', 'me')$q$,
        pg_temp.h(31), pg_temp.u(31), pg_temp.h(31)));
    PERFORM t51_dblink.dblink_send_query('ac', format('UPDATE public.budgets SET is_active = true WHERE id = %L', pg_temp.b(31)));
    -- The activation must wait for the expense, whichever it does: count it or be counted by it.
    PERFORM pg_temp.wait('ac', v_pid);
    PERFORM t51_dblink.dblink_exec('ex', 'COMMIT');
    v_res := pg_temp.result('ac');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('activation ran', v_res, 'UPDATE 1');
    PERFORM pg_temp.expect('the expense saved during activation counts',
        (SELECT spent_amount::text || '/' || is_active::text FROM public.budgets WHERE id = pg_temp.b(31)), '40.00/true');
    RAISE NOTICE 'PASSED: an expense saved while its budget is activated is counted once.';
END $$;

-- 3. Activation vs. an expense being deleted --------------------------------------------------------
DO $$
DECLARE
    v_pid int;
    v_res text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('ex');
    v_pid := pg_temp.connect('ac');
    PERFORM t51_dblink.dblink_exec('ex', 'BEGIN');
    PERFORM t51_dblink.dblink_exec('ex', format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(32)));
    PERFORM t51_dblink.dblink_send_query('ac', format('UPDATE public.budgets SET is_active = true WHERE id = %L', pg_temp.b(32)));
    PERFORM pg_temp.wait('ac', v_pid);
    PERFORM t51_dblink.dblink_exec('ex', 'COMMIT');
    v_res := pg_temp.result('ac');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('activation ran', v_res, 'UPDATE 1');
    PERFORM pg_temp.expect('the expense deleted during activation does not count',
        (SELECT spent_amount::text || '/' || is_active::text FROM public.budgets WHERE id = pg_temp.b(32)), '0.00/true');
    RAISE NOTICE 'PASSED: an expense deleted while its budget is activated is not counted.';
END $$;

-- 4. A co-admin's purge vs. the primary admin leaving ------------------------------------------------
DO $$
DECLARE
    v_pid int;
    v_purge text;
    v_leave text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('pg');
    v_pid := pg_temp.connect('lv');
    PERFORM pg_temp.as_user('lv', pg_temp.u(41));
    -- A (42), a co-admin, is purged: the work is done but not committed yet.
    PERFORM t51_dblink.dblink_exec('pg', 'BEGIN');
    SELECT r INTO v_purge FROM t51_dblink.dblink('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(42))) AS t(r text);
    PERFORM pg_temp.expect('A''s purge prepared', v_purge::jsonb ->> 'prepared', 'true');
    -- P, the primary, leaves: there is another admin, as far as P can see.
    PERFORM t51_dblink.dblink_send_query('lv', 'SELECT public.leave_household()::text');
    PERFORM pg_temp.expect('the leave waits for the purge', pg_temp.wait('lv', v_pid), 'blocked');
    PERFORM t51_dblink.dblink_exec('pg', 'COMMIT');
    v_leave := pg_temp.result('lv');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('the leave is refused', left(v_leave, 4), 'ERR:');
    PERFORM pg_temp.expect('H41 keeps an admin while it has members',
        (SELECT string_agg(user_id::text || '=' || role, ',' ORDER BY user_id) FROM public.household_memberships WHERE household_id = pg_temp.h(41)),
        pg_temp.u(41) || '=admin,' || pg_temp.u(43) || '=member');
    RAISE NOTICE 'PASSED: a co-admin purge and the primary leaving never leave a household without an admin.';
END $$;

-- 4b. Two admin removals on a path that does not lock the household first ---------------------------
DO $$
DECLARE
    v_pid int;
    v_res text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('s1');
    v_pid := pg_temp.connect('s2');
    -- Any path: the trigger alone must make the second removal count what the first committed.
    PERFORM t51_dblink.dblink_exec('s1', 'BEGIN');
    PERFORM t51_dblink.dblink_exec('s1', format('DELETE FROM public.household_memberships WHERE household_id = %L AND user_id = %L',
        pg_temp.h(42), pg_temp.u(44)));
    PERFORM t51_dblink.dblink_send_query('s2', format('DELETE FROM public.household_memberships WHERE household_id = %L AND user_id = %L',
        pg_temp.h(42), pg_temp.u(45)));
    PERFORM pg_temp.expect('the second removal waits', pg_temp.wait('s2', v_pid), 'blocked');
    PERFORM t51_dblink.dblink_exec('s1', 'COMMIT');
    v_res := pg_temp.result('s2');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('the second removal is refused', left(v_res, 4), 'ERR:');
    PERFORM pg_temp.expect('H42 keeps an admin',
        (SELECT string_agg(user_id::text || '=' || role, ',' ORDER BY user_id) FROM public.household_memberships WHERE household_id = pg_temp.h(42)),
        pg_temp.u(45) || '=admin,' || pg_temp.u(46) || '=member');
    RAISE NOTICE 'PASSED: the last-admin trigger serializes admin removals in a household.';
END $$;

-- 5. A primary's purge deleting a household vs. a co-admin leaving it --------------------------------
DO $$
DECLARE
    v_pg_pid int;
    v_lv_pid int;
    v_purge text;
    v_leave text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    v_pg_pid := pg_temp.connect('pg');
    v_lv_pid := pg_temp.connect('lv');
    PERFORM pg_temp.as_user('lv', pg_temp.u(52));
    -- Holds H51's income row, which the household deletion removes first: the purge stops after
    -- locking the household, before deleting its memberships.
    PERFORM t51_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t51_dblink.dblink('blk', format('SELECT 1 FROM public.income_records WHERE id = %L FOR UPDATE', pg_temp.i(51))) AS t(x int);
    PERFORM t51_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(51)));
    PERFORM pg_temp.expect('the purge holds the household and waits', pg_temp.wait('pg', v_pg_pid), 'blocked');
    PERFORM pg_temp.expect('the purge already holds the household', pg_temp.row_lock_state(pg_temp.h(51)), 'locked');
    -- P leaves now. It must wait for the household before it holds its own membership row.
    PERFORM t51_dblink.dblink_send_query('lv', 'SELECT public.leave_household()::text');
    PERFORM pg_temp.expect('the leave waits for the purge', pg_temp.wait('lv', v_lv_pid), 'blocked');
    PERFORM t51_dblink.dblink_exec('blk', 'ROLLBACK');
    v_purge := pg_temp.result('pg');
    v_leave := pg_temp.result('lv');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('no deadlock in the purge', CASE WHEN v_purge LIKE 'ERR:%' THEN v_purge ELSE v_purge::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('no error in the leave', CASE WHEN v_leave LIKE 'ERR:%' THEN v_leave ELSE v_leave::jsonb ->> 'success' END, 'true');
    PERFORM pg_temp.expect('H51 deleted', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(51)), '0');
    PERFORM pg_temp.expect('P and M keep their logins',
        (SELECT count(*)::text FROM public.users WHERE id IN (pg_temp.u(52), pg_temp.u(53)) AND household_id IS NULL), '2');
    RAISE NOTICE 'PASSED: a household deletion and a co-admin leaving it do not deadlock.';
END $$;

-- 6. Prepare vs. cancel on the same request -------------------------------------------------------------
DO $$
DECLARE
    v_pg_pid int;
    v_cn_pid int;
    v_purge text;
    v_cancel text;
BEGIN
    PERFORM pg_temp.disconnect_all();
    PERFORM pg_temp.connect('blk');
    v_pg_pid := pg_temp.connect('pg');
    v_cn_pid := pg_temp.connect('cn');
    PERFORM pg_temp.as_user('cn', pg_temp.u(61));
    PERFORM t51_dblink.dblink_exec('blk', 'BEGIN');
    PERFORM * FROM t51_dblink.dblink('blk', format('SELECT 1 FROM public.account_deletion_requests WHERE id = %L FOR UPDATE', pg_temp.r(61))) AS t(x int);
    PERFORM t51_dblink.dblink_send_query('pg', format('SELECT public.prepare_account_purge(%L)::text', pg_temp.r(61)));
    PERFORM pg_temp.expect('prepare waits', pg_temp.wait('pg', v_pg_pid), 'blocked');
    PERFORM t51_dblink.dblink_send_query('cn', 'SELECT public.cancel_account_deletion()::text');
    PERFORM pg_temp.expect('cancel waits', pg_temp.wait('cn', v_cn_pid), 'blocked');
    PERFORM t51_dblink.dblink_exec('blk', 'ROLLBACK');
    v_purge := pg_temp.result('pg');
    v_cancel := pg_temp.result('cn');
    PERFORM pg_temp.disconnect_all();

    PERFORM pg_temp.expect('no deadlock in prepare', CASE WHEN v_purge LIKE 'ERR:%' THEN v_purge ELSE v_purge::jsonb ->> 'prepared' END, 'true');
    PERFORM pg_temp.expect('cancel after prepare is refused, not deadlocked', v_cancel, 'ERR:22023:deletion_in_progress');
    RAISE NOTICE 'PASSED: prepare and cancel take their locks in the same order.';
END $$;

SELECT pg_temp.disconnect_all();
SELECT pg_temp.cleanup();
DROP EXTENSION dblink;
DROP SCHEMA t51_dblink;
