-- ============================================================================
-- Test 20 (owner decision on DB-16 / DB-18): admin permissions, co-admins and
-- the household's primary admin, in roommate and family households.
--
--   * A member creates transactions and edits/deletes only their own; only an
--     admin edits/deletes another member's. The creator is bound at insert and
--     immutable.
--   * Only an admin moves money out of a shared pool; members keep moving
--     money between their own personal accounts.
--   * Admins promote/revoke co-admins. Co-admins cannot demote or remove the
--     primary admin; only the primary admin transfers primary ownership. The
--     last-admin protection (BUG-03 / DB-12) keeps working.
--   * Family Nafaqah: any admin (co-admins included, never the wife herself)
--     sets the wife's allowance; the husband resolves to the primary admin.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Fixtures ------------------------------------------------------------------
-- Roommates R: P (primary admin), C (member, promoted later), M (member).
-- Family F: H (husband, primary admin), W (wife, member), K (adult child, member),
--           U (uncle/provider, member - promoted to co-admin later).
-- Outsider household X: O (admin).
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('f2000000-0000-0000-0000-0000000000a1', 'perm-p@test.local'),
        ('f2000000-0000-0000-0000-0000000000a2', 'perm-c@test.local'),
        ('f2000000-0000-0000-0000-0000000000a3', 'perm-m@test.local'),
        ('f2000000-0000-0000-0000-0000000000b1', 'perm-h@test.local'),
        ('f2000000-0000-0000-0000-0000000000b2', 'perm-w@test.local'),
        ('f2000000-0000-0000-0000-0000000000b3', 'perm-k@test.local'),
        ('f2000000-0000-0000-0000-0000000000b4', 'perm-u@test.local'),
        ('f2000000-0000-0000-0000-0000000000c1', 'perm-o@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('f2aa0000-0000-0000-0000-000000000001', 'Perm Roommates', 'PERMROOMCODE0001'),
        ('f2bb0000-0000-0000-0000-000000000001', 'Perm Family', 'PERMFAMCODE00001'),
        ('f2cc0000-0000-0000-0000-000000000001', 'Perm Outsider', 'PERMOUTCODE00001');
    -- Roommate household (household_type, migration 20261020900000).
    UPDATE public.households SET household_type = 'roommates'
    WHERE id IN ('f2aa0000-0000-0000-0000-000000000001', 'f2cc0000-0000-0000-0000-000000000001');

    UPDATE public.users SET household_id = 'f2aa0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'f2000000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = 'f2aa0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'peer'
    WHERE id IN ('f2000000-0000-0000-0000-0000000000a2', 'f2000000-0000-0000-0000-0000000000a3');

    UPDATE public.users SET household_id = 'f2bb0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'f2000000-0000-0000-0000-0000000000b1';
    UPDATE public.users SET household_id = 'f2bb0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'spouse'
    WHERE id = 'f2000000-0000-0000-0000-0000000000b2';
    UPDATE public.users SET household_id = 'f2bb0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'family_member'
    WHERE id = 'f2000000-0000-0000-0000-0000000000b3';
    UPDATE public.users SET household_id = 'f2bb0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'provider'
    WHERE id = 'f2000000-0000-0000-0000-0000000000b4';

    UPDATE public.users SET household_id = 'f2cc0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'f2000000-0000-0000-0000-0000000000c1';

    -- Deterministic seniority: P, C, M and H, W, K, U join in that order.
    UPDATE public.household_memberships SET created_at = now() - interval '40 days'
    WHERE user_id IN ('f2000000-0000-0000-0000-0000000000a1', 'f2000000-0000-0000-0000-0000000000b1');
    UPDATE public.household_memberships SET created_at = now() - interval '30 days'
    WHERE user_id IN ('f2000000-0000-0000-0000-0000000000a2', 'f2000000-0000-0000-0000-0000000000b2');
    UPDATE public.household_memberships SET created_at = now() - interval '20 days'
    WHERE user_id IN ('f2000000-0000-0000-0000-0000000000a3', 'f2000000-0000-0000-0000-0000000000b3');
    UPDATE public.household_memberships SET created_at = now() - interval '10 days'
    WHERE user_id = 'f2000000-0000-0000-0000-0000000000b4';

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('f2ac0000-0000-0000-0000-000000000001', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1', 'Flat pool', 'shared_pool', 1000, true),
        ('f2ac0000-0000-0000-0000-000000000002', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3', 'M bank', 'bank', 500, false),
        ('f2ac0000-0000-0000-0000-000000000003', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3', 'M wallet', 'e_wallet', 50, false),
        ('f2ac0000-0000-0000-0000-000000000004', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2', 'C bank', 'bank', 10, false),
        ('f2ac0000-0000-0000-0000-000000000005', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1', 'P bank', 'bank', 10, false);

    -- Transactions by P (admin) and by M (member), written by the service role path.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, account_id) VALUES
        ('f2e00000-0000-0000-0000-000000000001', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1', 120, 'Rent share', 'OPEX-MISC', now(), NULL),
        ('f2e00000-0000-0000-0000-000000000002', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3', 40, 'Groceries', 'OPEX-GROCERY', now(), 'f2ac0000-0000-0000-0000-000000000002'),
        ('f2e00000-0000-0000-0000-000000000003', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3', 15, 'Snacks', 'OPEX-GROCERY', now(), NULL),
        ('f2e00000-0000-0000-0000-000000000006', 'f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2', 25, 'Internet', 'OPEX-MISC', now(), NULL),
        ('f2e00000-0000-0000-0000-000000000004', 'f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b1', 300, 'Panda', 'OPEX-GROCERY', now(), NULL),
        ('f2e00000-0000-0000-0000-000000000005', 'f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b2', 80, 'Pharmacy', 'OPEX-MISC', now(), NULL);
END $$;

-- Helpers: run SQL as an authenticated user / as the service role; return SQLSTATE.
CREATE FUNCTION pg_temp.as_user(p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN '00000';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(text, text) TO authenticated;

CREATE FUNCTION pg_temp.as_service(p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);
    EXECUTE 'SET LOCAL ROLE service_role';
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN '00000';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_service(text) TO service_role;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION 'FAILED (%): got SQLSTATE %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

-- 1. Catalog: primary admin column, no client path to roles, hardened RPCs ----
DO $$
DECLARE
    v_list text;
BEGIN
    IF (SELECT owner_user_id FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a1'::uuid THEN
        RAISE EXCEPTION 'FAILED: roommate household primary admin is not its first admin';
    END IF;
    IF (SELECT owner_user_id FROM public.households WHERE id = 'f2bb0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000b1'::uuid THEN
        RAISE EXCEPTION 'FAILED: family household primary admin is not the husband';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.households h
        WHERE h.owner_user_id IS NULL
          AND EXISTS (SELECT 1 FROM public.household_memberships m WHERE m.household_id = h.id AND m.role = 'admin')
    ) THEN
        RAISE EXCEPTION 'FAILED: a household with admins has no primary admin';
    END IF;

    IF has_column_privilege('authenticated', 'public.households', 'owner_user_id', 'UPDATE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can rewrite households.owner_user_id';
    END IF;
    IF NOT has_column_privilege('authenticated', 'public.households', 'name', 'UPDATE')
       OR NOT has_column_privilege('authenticated', 'public.households', 'payday_day', 'UPDATE') THEN
        RAISE EXCEPTION 'REGRESSION: admins lost UPDATE on household settings columns';
    END IF;
    IF has_table_privilege('authenticated', 'public.household_memberships', 'INSERT')
       OR has_table_privilege('authenticated', 'public.household_memberships', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.household_memberships', 'DELETE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can write household_memberships directly';
    END IF;
    IF has_column_privilege('authenticated', 'public.users', 'role', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.users', 'household_id', 'UPDATE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can rewrite users.role / users.household_id';
    END IF;

    SELECT string_agg(p.proname, ', ') INTO v_list
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('get_household_members', 'promote_member_to_admin', 'revoke_admin',
                        'transfer_primary_admin', 'household_resolve_actor', 'household_member_role',
                        'household_primary_admin_id', 'household_apply_role', 'household_require_admin',
                        'protect_primary_admin_membership', 'maintain_household_primary_admin',
                        'bind_transaction_creator', 'enforce_transaction_write_permission',
                        'transfer_between_accounts', 'set_member_role', 'remove_member', 'get_user_households',
                        'transaction_account_matches', 'transaction_personal_account_writable',
                        'update_account_balance_on_transaction')
      AND (NOT p.prosecdef OR NOT EXISTS (
          SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'
      ));
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'VULNERABILITY: definer functions without pinned search_path: %', v_list;
    END IF;

    IF has_function_privilege('anon', 'public.promote_member_to_admin(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.revoke_admin(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.transfer_primary_admin(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_household_members(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_user_households()', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY: anon can execute role-management RPCs';
    END IF;
    IF has_function_privilege('authenticated', 'public.household_apply_role(uuid, uuid, text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.household_resolve_actor(uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.household_require_admin(uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can call internal role helpers';
    END IF;
    RAISE NOTICE 'PASSED: primary admin backfilled; roles, owner and memberships have no client write path; RPCs hardened.';
END $$;

-- 2. Direct table writes cannot change roles or the primary admin --------------
DO $$
BEGIN
    PERFORM pg_temp.expect('admin updates membership role directly',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.household_memberships SET role = 'admin' WHERE user_id = 'f2000000-0000-0000-0000-0000000000a3'$q$),
        '42501');
    PERFORM pg_temp.expect('member promotes self via users.role',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.users SET role = 'admin' WHERE id = 'f2000000-0000-0000-0000-0000000000a3'$q$),
        '42501');
    PERFORM pg_temp.expect('admin rewrites owner_user_id',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET owner_user_id = 'f2000000-0000-0000-0000-0000000000a3' WHERE id = 'f2aa0000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('admin still updates household settings',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET payday_day = 25 WHERE id = 'f2aa0000-0000-0000-0000-000000000001'$q$),
        '00000');
    IF (SELECT payday_day FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001') <> 25 THEN
        RAISE EXCEPTION 'REGRESSION: admin household settings update had no effect';
    END IF;
    IF (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a3') <> 'member' THEN
        RAISE EXCEPTION 'VULNERABILITY: a role changed through a direct write';
    END IF;
    RAISE NOTICE 'PASSED: roles and the primary admin change only through the RPCs.';
END $$;

-- 3. Transaction creator binding (DB-18) ----------------------------------------
DO $$
BEGIN
    -- Older builds omit user_id: the creator is filled in from the JWT.
    PERFORM pg_temp.expect('member inserts without user_id',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp)
               VALUES ('f2e00000-0000-0000-0000-000000000010', 'f2aa0000-0000-0000-0000-000000000001', 9, 'Bread', 'OPEX-GROCERY', now())$q$),
        '00000');
    IF (SELECT user_id FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000010')
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a3'::uuid THEN
        RAISE EXCEPTION 'FAILED: creator not bound to the caller on insert';
    END IF;

    PERFORM pg_temp.expect('member inserts as another member',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp)
               VALUES ('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1', 9, 'Spoof', 'OPEX-GROCERY', now())$q$),
        '42501');
    PERFORM pg_temp.expect('admin inserts as another member',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp)
               VALUES ('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3', 9, 'Spoof', 'OPEX-GROCERY', now())$q$),
        '42501');
    PERFORM pg_temp.expect('member inserts into another household',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp)
               VALUES ('f2cc0000-0000-0000-0000-000000000001', 9, 'X', 'OPEX-GROCERY', now())$q$),
        '42501');
    PERFORM pg_temp.expect('member changes the creator of own transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.transactions SET user_id = 'f2000000-0000-0000-0000-0000000000a1' WHERE id = 'f2e00000-0000-0000-0000-000000000003'$q$),
        '42501');
    PERFORM pg_temp.expect('admin reattributes a member transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.transactions SET user_id = 'f2000000-0000-0000-0000-0000000000a1' WHERE id = 'f2e00000-0000-0000-0000-000000000003'$q$),
        '42501');
    RAISE NOTICE 'PASSED: the creator is bound at insert (older builds keep working) and never changes.';
END $$;

-- 4. Owner-or-admin edits and deletes (roommates) ---------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('member edits own',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.transactions SET merchant = 'Snacks (fixed)' WHERE id = 'f2e00000-0000-0000-0000-000000000003'$q$),
        '00000');
    PERFORM pg_temp.expect('member edits admin transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.transactions SET amount = 1 WHERE id = 'f2e00000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('member deletes admin transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$DELETE FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('member edits another member transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$UPDATE public.transactions SET amount = 1 WHERE id = 'f2e00000-0000-0000-0000-000000000003'$q$),
        '42501');
    IF (SELECT amount FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000001') <> 120
       OR (SELECT amount FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000003') <> 15 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-18): a member changed another member''s transaction';
    END IF;

    -- Admin edits a member's transaction that sits on the member's personal account.
    PERFORM pg_temp.expect('admin edits member transaction on member account',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.transactions SET amount = 45 WHERE id = 'f2e00000-0000-0000-0000-000000000002'$q$),
        '00000');
    IF (SELECT balance FROM public.accounts WHERE id = 'f2ac0000-0000-0000-0000-000000000002') <> 455 THEN
        RAISE EXCEPTION 'FAILED: account balance not adjusted by the admin edit (got %)',
            (SELECT balance FROM public.accounts WHERE id = 'f2ac0000-0000-0000-0000-000000000002');
    END IF;
    -- ... but cannot move it onto the admin's own personal account.
    PERFORM pg_temp.expect('admin moves member transaction to own account',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.transactions SET account_id = 'f2ac0000-0000-0000-0000-000000000005' WHERE id = 'f2e00000-0000-0000-0000-000000000002'$q$),
        '42501');

    PERFORM pg_temp.expect('admin deletes member transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$DELETE FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000003'$q$),
        '00000');
    PERFORM pg_temp.expect('member deletes own',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$DELETE FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000010'$q$),
        '00000');
    IF EXISTS (SELECT 1 FROM public.transactions WHERE id IN ('f2e00000-0000-0000-0000-000000000003', 'f2e00000-0000-0000-0000-000000000010')) THEN
        RAISE EXCEPTION 'FAILED: permitted deletes did not delete';
    END IF;

    -- Another household's admin sees nothing to change.
    PERFORM pg_temp.expect('outsider admin edits',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000c1',
            $q$UPDATE public.transactions SET amount = 1 WHERE id = 'f2e00000-0000-0000-0000-000000000001'$q$),
        '00000');
    PERFORM pg_temp.expect('outsider admin deletes',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000c1',
            $q$DELETE FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000001'$q$),
        '00000');
    IF (SELECT amount FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000001') IS DISTINCT FROM 120 THEN
        RAISE EXCEPTION 'VULNERABILITY: another household changed this household''s transaction';
    END IF;
    RAISE NOTICE 'PASSED: members edit/delete only their own transactions; admins any in their household.';
END $$;

-- 5. Shared pool withdrawals are admin-only (DB-16) --------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('member drains pool to own account',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$SELECT public.transfer_between_accounts('f2aa0000-0000-0000-0000-000000000001',
                'f2ac0000-0000-0000-0000-000000000001', 'f2ac0000-0000-0000-0000-000000000002', 1000, 0, 'mine')$q$),
        '42501');
    PERFORM pg_temp.expect('member moves between own accounts',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$SELECT public.transfer_between_accounts('f2aa0000-0000-0000-0000-000000000001',
                'f2ac0000-0000-0000-0000-000000000002', 'f2ac0000-0000-0000-0000-000000000003', 20, 0, NULL)$q$),
        '00000');
    PERFORM pg_temp.expect('member pays into the pool',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$SELECT public.transfer_between_accounts('f2aa0000-0000-0000-0000-000000000001',
                'f2ac0000-0000-0000-0000-000000000002', 'f2ac0000-0000-0000-0000-000000000001', 100, 0, 'dues')$q$),
        '00000');
    PERFORM pg_temp.expect('admin moves pool money',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.transfer_between_accounts('f2aa0000-0000-0000-0000-000000000001',
                'f2ac0000-0000-0000-0000-000000000001', 'f2ac0000-0000-0000-0000-000000000005', 50, 0, 'repairs')$q$),
        '00000');
    IF (SELECT balance FROM public.accounts WHERE id = 'f2ac0000-0000-0000-0000-000000000001') <> 1050 THEN
        RAISE EXCEPTION 'FAILED: pool balance % (expected 1050)',
            (SELECT balance FROM public.accounts WHERE id = 'f2ac0000-0000-0000-0000-000000000001');
    END IF;
    RAISE NOTICE 'PASSED: only admins move money out of a shared pool; members keep personal transfers.';
END $$;

-- 6. Co-admins: promote, limits, primary admin protection -------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('member promotes self',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '42501');
    PERFORM pg_temp.expect('outsider promotes into another household',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000c1',
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '42501');
    PERFORM pg_temp.expect('admin promotes a non-member',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000c1')$q$),
        'P0002');
    PERFORM pg_temp.expect('member acts as the primary admin via p_actor_user_id',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3', 'f2000000-0000-0000-0000-0000000000a1')$q$),
        '42501');

    PERFORM pg_temp.expect('primary admin promotes C',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2')$q$),
        '00000');
    IF (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a2') <> 'admin'
       OR (SELECT role FROM public.users WHERE id = 'f2000000-0000-0000-0000-0000000000a2') <> 'admin' THEN
        RAISE EXCEPTION 'FAILED: promotion not applied to membership and users.role';
    END IF;

    -- The co-admin can do what admins do...
    PERFORM pg_temp.expect('co-admin edits member transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$UPDATE public.transactions SET merchant = 'Groceries (checked)' WHERE id = 'f2e00000-0000-0000-0000-000000000002'$q$),
        '00000');
    PERFORM pg_temp.expect('co-admin moves pool money',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.transfer_between_accounts('f2aa0000-0000-0000-0000-000000000001',
                'f2ac0000-0000-0000-0000-000000000001', 'f2ac0000-0000-0000-0000-000000000005', 10, 0, NULL)$q$),
        '00000');
    PERFORM pg_temp.expect('co-admin promotes M',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '00000');
    PERFORM pg_temp.expect('co-admin revokes M',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.revoke_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '00000');
    IF (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a3') <> 'member' THEN
        RAISE EXCEPTION 'FAILED: revoke_admin did not demote M';
    END IF;

    -- ... except touch the primary admin.
    PERFORM pg_temp.expect('co-admin revokes primary admin',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.revoke_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1')$q$),
        '42501');
    PERFORM pg_temp.expect('co-admin demotes primary via set_member_role',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.set_member_role('f2000000-0000-0000-0000-0000000000a1', 'member')$q$),
        '42501');
    PERFORM pg_temp.expect('co-admin removes primary via remove_member',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.remove_member('f2000000-0000-0000-0000-0000000000a1')$q$),
        '42501');
    PERFORM pg_temp.expect('co-admin transfers primary admin',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.transfer_primary_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2')$q$),
        '42501');
    PERFORM pg_temp.expect('primary admin demotes self',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.revoke_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1')$q$),
        '42501');
    IF (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a1') <> 'admin'
       OR (SELECT owner_user_id FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001')
          IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a1'::uuid THEN
        RAISE EXCEPTION 'VULNERABILITY: the primary admin was demoted or replaced';
    END IF;

    -- A co-admin may step down.
    PERFORM pg_temp.expect('co-admin revokes self',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$SELECT public.revoke_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2')$q$),
        '00000');
    PERFORM pg_temp.expect('former co-admin edits member transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2',
            $q$UPDATE public.transactions SET amount = 2 WHERE id = 'f2e00000-0000-0000-0000-000000000002'$q$),
        '42501');
    RAISE NOTICE 'PASSED: admins manage co-admins; co-admins cannot demote, remove or replace the primary admin.';
END $$;

-- 7. Transfer of primary admin ----------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('primary admin transfers to self',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.transfer_primary_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1')$q$),
        '22023');
    PERFORM pg_temp.expect('primary admin transfers to an outsider',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.transfer_primary_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000c1')$q$),
        'P0002');
    PERFORM pg_temp.expect('primary admin transfers to member M',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.transfer_primary_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '00000');
    IF (SELECT owner_user_id FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a3'::uuid
       OR (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a3') <> 'admin'
       OR (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a1') <> 'admin' THEN
        RAISE EXCEPTION 'FAILED: primary admin transfer did not make M primary while P stays admin';
    END IF;
    -- P is now a co-admin: the new primary admin is protected from them.
    PERFORM pg_temp.expect('former primary revokes new primary',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$SELECT public.revoke_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '42501');
    PERFORM pg_temp.expect('new primary revokes former primary',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3',
            $q$SELECT public.revoke_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a1')$q$),
        '00000');
    -- get_user_households() reports the primary flag; members list orders primary first.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'f2000000-0000-0000-0000-0000000000a3', 'role', 'authenticated')::text, true);
    IF NOT (SELECT is_primary FROM public.get_user_households() WHERE household_id = 'f2aa0000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'FAILED: get_user_households() does not flag the primary admin';
    END IF;
    IF (SELECT user_id FROM public.get_household_members('f2aa0000-0000-0000-0000-000000000001') LIMIT 1)
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a3'::uuid THEN
        RAISE EXCEPTION 'FAILED: get_household_members() does not list the primary admin first';
    END IF;
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM pg_temp.expect('outsider lists members',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000c1',
            $q$SELECT count(*) FROM public.get_household_members('f2aa0000-0000-0000-0000-000000000001')$q$),
        '42501');
    RAISE NOTICE 'PASSED: only the primary admin transfers primary admin; the new primary is protected.';
END $$;

-- 8. Service role acts only for the verified user ---------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('service role as member promotes',
        pg_temp.as_service(
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2', 'f2000000-0000-0000-0000-0000000000a1')$q$),
        '42501');
    PERFORM pg_temp.expect('service role without actor',
        pg_temp.as_service(
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2')$q$),
        '42501');
    PERFORM pg_temp.expect('service role as primary admin promotes',
        pg_temp.as_service(
            $q$SELECT public.promote_member_to_admin('f2aa0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000a2', 'f2000000-0000-0000-0000-0000000000a3')$q$),
        '00000');
    IF (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a2') <> 'admin' THEN
        RAISE EXCEPTION 'FAILED: service-role promotion for the verified primary admin not applied';
    END IF;
    RAISE NOTICE 'PASSED: the service role acts only on behalf of an authorised actor.';
END $$;

-- 9. Last-admin protection and primary handover ------------------------------------
DO $$
BEGIN
    -- Outsider household: O is the sole (and primary) admin of a one-person household.
    PERFORM pg_temp.expect('sole admin demotes self',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000c1',
            $q$SELECT public.revoke_admin('f2cc0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000c1')$q$),
        '42501');

    -- Roommates: M (primary) leaves while P is no longer admin but C is: C becomes primary.
    PERFORM pg_temp.expect('primary admin leaves',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a3', $q$SELECT public.leave_household()$q$),
        '00000');
    IF (SELECT owner_user_id FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a2'::uuid THEN
        RAISE EXCEPTION 'FAILED: primary admin did not pass to the remaining admin (got %)',
            (SELECT owner_user_id FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001');
    END IF;

    -- C is now the sole admin with P remaining: last-admin protection holds.
    PERFORM pg_temp.expect('sole admin leaves with members remaining',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a2', $q$SELECT public.leave_household()$q$),
        'P0001');

    -- Deleting the sole primary admin's account (in their own session, as in-app
    -- account deletion) hands the household to P (DB-12); the cascade that clears
    -- them from transactions is not blocked by the creator/edit rules.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'f2000000-0000-0000-0000-0000000000a2', 'role', 'authenticated')::text, true);
    DELETE FROM auth.users WHERE id = 'f2000000-0000-0000-0000-0000000000a2';
    PERFORM set_config('request.jwt.claims', '', true);
    IF (SELECT owner_user_id FROM public.households WHERE id = 'f2aa0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000a1'::uuid
       OR (SELECT role FROM public.household_memberships WHERE user_id = 'f2000000-0000-0000-0000-0000000000a1') <> 'admin' THEN
        RAISE EXCEPTION 'FAILED: account deletion did not hand primary admin to the successor';
    END IF;

    -- A deleted account's transactions stay, unattributed (ON DELETE SET NULL is allowed).
    IF (SELECT user_id FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000006') IS NOT NULL THEN
        RAISE EXCEPTION 'FAILED: deleted creator not cleared from transaction';
    END IF;
    -- Unattributed transactions are admin-only.
    PERFORM pg_temp.expect('admin edits unattributed transaction',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.transactions SET merchant = 'Internet (legacy)' WHERE id = 'f2e00000-0000-0000-0000-000000000006'$q$),
        '00000');

    -- Deleting a whole household still cascades cleanly.
    DELETE FROM public.households WHERE id = 'f2cc0000-0000-0000-0000-000000000001';
    RAISE NOTICE 'PASSED: last-admin protection, primary handover on leave and account deletion, household delete.';
END $$;

-- 10. Family mode: same rules, Nafaqah keeps working with co-admins -----------------
DO $$
DECLARE
    v_status jsonb;
BEGIN
    PERFORM pg_temp.expect('wife edits own expense',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b2',
            $q$UPDATE public.transactions SET merchant = 'Pharmacy (vitamins)' WHERE id = 'f2e00000-0000-0000-0000-000000000005'$q$),
        '00000');
    PERFORM pg_temp.expect('wife edits husband expense',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b2',
            $q$UPDATE public.transactions SET amount = 1 WHERE id = 'f2e00000-0000-0000-0000-000000000004'$q$),
        '42501');
    PERFORM pg_temp.expect('child deletes wife expense',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b3',
            $q$DELETE FROM public.transactions WHERE id = 'f2e00000-0000-0000-0000-000000000005'$q$),
        '42501');
    PERFORM pg_temp.expect('husband (admin) edits wife expense',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b1',
            $q$UPDATE public.transactions SET category_code = 'OPEX-MISC' WHERE id = 'f2e00000-0000-0000-0000-000000000005'$q$),
        '00000');

    IF public.nafaqah_husband_id('f2bb0000-0000-0000-0000-000000000001') IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000b1'::uuid THEN
        RAISE EXCEPTION 'FAILED: husband is not resolved to the primary admin';
    END IF;

    -- Uncle U (provider, member) cannot set the allowance; as a co-admin he can.
    PERFORM pg_temp.expect('member provider sets allowance',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b4',
            $q$SELECT public.set_member_allowance('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b2', 500, '2026-11')$q$),
        '42501');
    PERFORM pg_temp.expect('husband promotes U',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b1',
            $q$SELECT public.promote_member_to_admin('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b4')$q$),
        '00000');
    PERFORM pg_temp.expect('co-admin sets allowance',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b4',
            $q$SELECT public.set_member_allowance('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b2', 500, '2026-11')$q$),
        '00000');
    -- Making the wife a co-admin never lets her set her own allowance.
    PERFORM pg_temp.expect('husband promotes wife',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b1',
            $q$SELECT public.promote_member_to_admin('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b2')$q$),
        '00000');
    PERFORM pg_temp.expect('wife co-admin sets own allowance',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b2',
            $q$SELECT public.set_member_allowance('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b2', 9000, '2026-11')$q$),
        '42501');
    -- Co-admin wife cannot demote the husband (primary admin).
    PERFORM pg_temp.expect('wife co-admin revokes husband',
        pg_temp.as_user('f2000000-0000-0000-0000-0000000000b2',
            $q$SELECT public.revoke_admin('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b1')$q$),
        '42501');
    -- The husband stays the Nafaqah provider even with a second provider admin.
    IF public.nafaqah_husband_id('f2bb0000-0000-0000-0000-000000000001') IS DISTINCT FROM 'f2000000-0000-0000-0000-0000000000b1'::uuid THEN
        RAISE EXCEPTION 'FAILED: a co-admin displaced the husband as Nafaqah provider';
    END IF;

    -- The wife still reads her own allowance.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'f2000000-0000-0000-0000-0000000000b2', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    v_status := public.get_member_allowance_status('f2bb0000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-0000000000b2', '2026-11', NULL);
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    IF (v_status ->> 'allocated')::numeric <> 500 THEN
        RAISE EXCEPTION 'FAILED: wife cannot read her allowance (got %)', v_status;
    END IF;
    RAISE NOTICE 'PASSED: family mode follows the same admin rules; Nafaqah allowance respects co-admins.';
END $$;

ROLLBACK;
