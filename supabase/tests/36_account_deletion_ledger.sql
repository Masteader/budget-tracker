-- ============================================================================
-- Test 36: deleting a member keeps ledgers and balances intact
--
-- Migration: 20261105000000_account_deletion_ledger_fks.sql
--
-- Verifies:
--   1. A member's income into a shared pool survives their deletion with a NULL
--      creator and the pool balance does not move (was: CASCADE plus the balance
--      trigger lowered the pool).
--   2. Transfers touching a deleted member's personal account or a deleted
--      admin's personal account no longer block deletion. The pool does not move
--      and the row stays with the deleted side NULL (was: RESTRICT).
--   3. Income into a deleted member's personal account goes with the account, and
--      a transfer between two of their own accounts goes too.
--   4. A pool owned by someone who already left the household is re-owned, not
--      destroyed, when their account is deleted.
--   5. void_income_record cannot be abused through a NULL user_id: a regular
--      member is refused, an admin is allowed.
--   6. A household with income, transfers and several members deletes through the
--      purge's fixed order.
--   7. The foreign keys are in the required state.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.as_user(p_sub uuid, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
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
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated;

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

-- Fixtures: admin A, members B and C, plus D, who leaves before the deletion.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e3600000-0000-0000-0000-00000000000a', 't36-a@test.local'),
        ('e3600000-0000-0000-0000-00000000000b', 't36-b@test.local'),
        ('e3600000-0000-0000-0000-00000000000c', 't36-c@test.local'),
        ('e3600000-0000-0000-0000-00000000000d', 't36-d@test.local');

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        ('e36a0000-0000-0000-0000-000000000001', 'T36 Flat', 'T36FLATCODE00001', 'roommates');

    UPDATE public.users SET household_id = 'e36a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id IN ('e3600000-0000-0000-0000-00000000000a');
    UPDATE public.users SET household_id = 'e36a0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'peer'
    WHERE id IN ('e3600000-0000-0000-0000-00000000000b', 'e3600000-0000-0000-0000-00000000000c',
                 'e3600000-0000-0000-0000-00000000000d');
    UPDATE public.household_memberships SET created_at = now() - interval '1 day'
    WHERE user_id = 'e3600000-0000-0000-0000-00000000000c';

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('e36c0000-0000-0000-0000-000000000001', 'e36a0000-0000-0000-0000-000000000001', 'e3600000-0000-0000-0000-00000000000a', 'Pool', 'shared_pool', 1000, true),
        ('e36c0000-0000-0000-0000-00000000000a', 'e36a0000-0000-0000-0000-000000000001', 'e3600000-0000-0000-0000-00000000000a', 'A personal', 'bank', 500, false),
        ('e36c0000-0000-0000-0000-00000000000b', 'e36a0000-0000-0000-0000-000000000001', 'e3600000-0000-0000-0000-00000000000b', 'B personal', 'bank', 500, false),
        ('e36c0000-0000-0000-0000-00000000000e', 'e36a0000-0000-0000-0000-000000000001', 'e3600000-0000-0000-0000-00000000000b', 'B cash', 'cash', 100, false),
        -- D's pool: D leaves below and stays its owner (leave_household does not re-own).
        ('e36c0000-0000-0000-0000-00000000000d', 'e36a0000-0000-0000-0000-000000000001', 'e3600000-0000-0000-0000-00000000000d', 'D pool', 'shared_pool', 300, true);
END $$;

-- The app's paths: income through record_income, transfers through transfer_between_accounts.
DO $$
DECLARE
    v_income text := $q$SELECT public.record_income('e36a0000-0000-0000-0000-000000000001', '%s', '2026-11', 'salary', %L,
        %s, 0, 0, 0, now(), %L)::text$q$;
    v_transfer text := $q$SELECT public.transfer_between_accounts('e36a0000-0000-0000-0000-000000000001', '%s', '%s', %s, 0, %L)::text$q$;
    v_res text;
BEGIN
    -- B pays income into the pool: +200 (pool 1200).
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000b',
        format(v_income, 'e36c0000-0000-0000-0000-000000000001', 'T36 B pool income', 200, 'b private note'));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: B income into pool: %', v_res; END IF;
    -- B income into own personal account.
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000b',
        format(v_income, 'e36c0000-0000-0000-0000-00000000000b', 'T36 B personal income', 50, NULL));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: B income into personal: %', v_res; END IF;
    -- B personal -> pool: +40 (pool 1240).
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000b',
        format(v_transfer, 'e36c0000-0000-0000-0000-00000000000b', 'e36c0000-0000-0000-0000-000000000001', 40, 'T36 B to pool'));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: B transfer to pool: %', v_res; END IF;
    -- B between own accounts.
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000b',
        format(v_transfer, 'e36c0000-0000-0000-0000-00000000000b', 'e36c0000-0000-0000-0000-00000000000e', 5, 'T36 B own'));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: B own transfer: %', v_res; END IF;
    -- Admin A pool -> A personal: -30 (pool 1210).
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000a',
        format(v_transfer, 'e36c0000-0000-0000-0000-000000000001', 'e36c0000-0000-0000-0000-00000000000a', 30, 'T36 A from pool'));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: A transfer from pool: %', v_res; END IF;
    PERFORM pg_temp.expect('pool after fixtures',
        (SELECT balance::text FROM public.accounts WHERE id = 'e36c0000-0000-0000-0000-000000000001'), '1210.00');

    -- D leaves, keeping ownership of D pool, as leave_household does today.
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000d', $q$SELECT public.leave_household()::text$q$);
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: D leaves: %', v_res; END IF;
END $$;

-- 1, 2, 3. Deleting member B ------------------------------------------------------
DO $$
BEGIN
    BEGIN
        DELETE FROM auth.users WHERE id = 'e3600000-0000-0000-0000-00000000000b';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG: deleting a member with income and transfers failed (%): %', SQLSTATE, SQLERRM;
    END;

    PERFORM pg_temp.expect('pool balance after deleting B',
        (SELECT balance::text FROM public.accounts WHERE id = 'e36c0000-0000-0000-0000-000000000001'), '1210.00');
    PERFORM pg_temp.expect('B pool income kept with NULL creator',
        (SELECT count(*)::text FROM public.income_records WHERE title = 'T36 B pool income' AND user_id IS NULL), '1');
    PERFORM pg_temp.expect('B personal income gone with the account',
        (SELECT count(*)::text FROM public.income_records WHERE title = 'T36 B personal income'), '0');
    PERFORM pg_temp.expect('B personal accounts gone',
        (SELECT count(*)::text FROM public.accounts
         WHERE id IN ('e36c0000-0000-0000-0000-00000000000b', 'e36c0000-0000-0000-0000-00000000000e')), '0');
    PERFORM pg_temp.expect('B personal->pool transfer kept with NULL side and creator',
        (SELECT count(*)::text FROM public.account_transfers
         WHERE notes = 'T36 B to pool' AND user_id IS NULL AND from_account_id IS NULL
           AND to_account_id = 'e36c0000-0000-0000-0000-000000000001'), '1');
    PERFORM pg_temp.expect('transfer between B''s own accounts gone',
        (SELECT count(*)::text FROM public.account_transfers WHERE notes = 'T36 B own'), '0');
    RAISE NOTICE 'PASSED: deleting a member keeps the pool balance, pool income and pool transfers.';
END $$;

-- 5. NULL-creator income cannot be voided by a regular member ----------------------
DO $$
DECLARE
    v_id uuid;
    v_res text;
BEGIN
    SELECT id INTO v_id FROM public.income_records WHERE title = 'T36 B pool income';
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000c',
        format('SELECT public.void_income_record(%L)::text', v_id));
    PERFORM pg_temp.expect('regular member voids NULL-creator pool income', v_res, 'ERR:42501');
    PERFORM pg_temp.expect('row still there after the refused void',
        (SELECT count(*)::text FROM public.income_records WHERE id = v_id), '1');

    v_res := pg_temp.as_user('e3600000-0000-0000-0000-00000000000a',
        format('SELECT public.void_income_record(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'admin could not void NULL-creator pool income: %', v_res;
    END IF;
    PERFORM pg_temp.expect('admin voided the row',
        (SELECT count(*)::text FROM public.income_records WHERE id = v_id), '0');
    -- This file does not assert the balance after a void: see test 35.
    UPDATE public.accounts SET balance = 1210.00 WHERE id = 'e36c0000-0000-0000-0000-000000000001';
    RAISE NOTICE 'PASSED: void_income_record refuses a regular member on a NULL creator and allows an admin.';
END $$;

-- 2, 4. Deleting admin A and former member D ---------------------------------------
DO $$
BEGIN
    BEGIN
        DELETE FROM auth.users WHERE id = 'e3600000-0000-0000-0000-00000000000a';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG: deleting an admin with a pool->personal transfer failed (%): %', SQLSTATE, SQLERRM;
    END;
    PERFORM pg_temp.expect('handover promoted C',
        (SELECT role FROM public.household_memberships
         WHERE household_id = 'e36a0000-0000-0000-0000-000000000001' AND user_id = 'e3600000-0000-0000-0000-00000000000c'), 'admin');
    PERFORM pg_temp.expect('pool re-owned by C',
        (SELECT owner_user_id::text FROM public.accounts WHERE id = 'e36c0000-0000-0000-0000-000000000001'),
        'e3600000-0000-0000-0000-00000000000c');
    PERFORM pg_temp.expect('pool balance after deleting admin A',
        (SELECT balance::text FROM public.accounts WHERE id = 'e36c0000-0000-0000-0000-000000000001'), '1210.00');
    PERFORM pg_temp.expect('A pool->personal transfer kept with NULL side and creator',
        (SELECT count(*)::text FROM public.account_transfers
         WHERE notes = 'T36 A from pool' AND user_id IS NULL AND to_account_id IS NULL
           AND from_account_id = 'e36c0000-0000-0000-0000-000000000001'), '1');

    DELETE FROM auth.users WHERE id = 'e3600000-0000-0000-0000-00000000000d';
    PERFORM pg_temp.expect('former member''s pool survives, re-owned by the admin',
        (SELECT owner_user_id::text || '/' || balance::text FROM public.accounts WHERE id = 'e36c0000-0000-0000-0000-00000000000d'),
        'e3600000-0000-0000-0000-00000000000c/300.00');
    RAISE NOTICE 'PASSED: deleting an admin or a former member keeps pools, balances and transfer rows.';
END $$;

-- 6. Household deletion through the purge's fixed order ----------------------------
DO $$
DECLARE
    v_hh uuid := 'e36a0000-0000-0000-0000-000000000002';
    v_res text;
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e3600000-0000-0000-0000-0000000000e1', 't36-e1@test.local'),
        ('e3600000-0000-0000-0000-0000000000e2', 't36-e2@test.local'),
        ('e3600000-0000-0000-0000-0000000000e3', 't36-e3@test.local');
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (v_hh, 'T36 Doomed', 'T36DOOMEDCODE001', 'roommates');
    UPDATE public.users SET household_id = v_hh, role = 'admin', financial_role = 'peer'
    WHERE id IN ('e3600000-0000-0000-0000-0000000000e1', 'e3600000-0000-0000-0000-0000000000e2');
    UPDATE public.users SET household_id = v_hh, role = 'member', financial_role = 'peer'
    WHERE id = 'e3600000-0000-0000-0000-0000000000e3';
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('e36c0000-0000-0000-0000-0000000000f1', v_hh, 'e3600000-0000-0000-0000-0000000000e1', 'Doomed pool', 'shared_pool', 100, true),
        ('e36c0000-0000-0000-0000-0000000000f3', v_hh, 'e3600000-0000-0000-0000-0000000000e3', 'E3 personal', 'bank', 100, false);
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-0000000000e3',
        $q$SELECT public.record_income('e36a0000-0000-0000-0000-000000000002', 'e36c0000-0000-0000-0000-0000000000f1', '2026-11', 'salary', 'T36 doomed income', 10, 0, 0, 0, now(), NULL)::text$q$);
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: doomed income: %', v_res; END IF;
    v_res := pg_temp.as_user('e3600000-0000-0000-0000-0000000000e3',
        $q$SELECT public.transfer_between_accounts('e36a0000-0000-0000-0000-000000000002', 'e36c0000-0000-0000-0000-0000000000f3', 'e36c0000-0000-0000-0000-0000000000f1', 5, 0, NULL)::text$q$);
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: doomed transfer: %', v_res; END IF;

    DELETE FROM public.income_records WHERE household_id = v_hh;
    DELETE FROM public.account_transfers WHERE household_id = v_hh;
    DELETE FROM public.household_memberships WHERE household_id = v_hh AND role <> 'admin';
    DELETE FROM public.household_memberships WHERE household_id = v_hh;
    DELETE FROM public.households WHERE id = v_hh;

    PERFORM pg_temp.expect('household gone', (SELECT count(*)::text FROM public.households WHERE id = v_hh), '0');
    PERFORM pg_temp.expect('its accounts gone', (SELECT count(*)::text FROM public.accounts WHERE household_id = v_hh), '0');
    PERFORM pg_temp.expect('members keep their logins',
        (SELECT count(*)::text FROM public.users
         WHERE id IN ('e3600000-0000-0000-0000-0000000000e1', 'e3600000-0000-0000-0000-0000000000e2', 'e3600000-0000-0000-0000-0000000000e3')
           AND household_id IS NULL), '3');
    RAISE NOTICE 'PASSED: household with income, transfers and several members deletes through the fixed order.';
END $$;

-- 7. Foreign key state --------------------------------------------------------------
DO $$
DECLARE
    v_got text;
BEGIN
    SELECT string_agg(c.conrelid::regclass::text || '.' || a.attname || ':' || c.confdeltype::text || ':' || a.attnotnull::text,
                      ',' ORDER BY c.conrelid::regclass::text, a.attname) INTO v_got
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f'
      AND c.conrelid IN ('public.income_records'::regclass, 'public.account_transfers'::regclass)
      AND a.attname IN ('user_id', 'account_id', 'from_account_id', 'to_account_id');
    PERFORM pg_temp.expect('ledger FK state', v_got,
        'account_transfers.from_account_id:n:false,account_transfers.to_account_id:n:false,account_transfers.user_id:n:false,'
        || 'income_records.account_id:r:true,income_records.user_id:n:false');
    RAISE NOTICE 'PASSED: ledger foreign keys are in the required state.';
END $$;

ROLLBACK;
