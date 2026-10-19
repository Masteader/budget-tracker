-- ============================================================================
-- Test 09 (audit DB-02): household_memberships policy recursion & write surface
--
-- memberships_admin_manage (FOR ALL, role PUBLIC) queried household_memberships
-- from inside its own policy, so every authenticated read of the table - and
-- every storage.objects receipts policy that consults it - failed with
-- "infinite recursion detected in policy". The same policy (had it evaluated)
-- let admins write membership rows directly, bypassing the RPCs that keep
-- users.household_id in sync, and the RLS helpers trusted users.household_id
-- without checking that a membership still exists.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('d2000000-0000-0000-0000-000000000001', 'db02-admin@test.local'),
        ('d2000000-0000-0000-0000-000000000002', 'db02-member@test.local'),
        ('d2000000-0000-0000-0000-000000000003', 'db02-outsider@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('d2aa0000-0000-0000-0000-000000000001', 'DB02 Home', 'DB02HOMECODE0001'),
        ('d2bb0000-0000-0000-0000-000000000001', 'DB02 Other', 'DB02OTHERCODE001');

    UPDATE public.users SET household_id = 'd2aa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd2000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'd2aa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'd2000000-0000-0000-0000-000000000002';
    UPDATE public.users SET household_id = 'd2bb0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd2000000-0000-0000-0000-000000000003';

    INSERT INTO public.transactions (household_id, user_id, amount, category_code, timestamp)
    VALUES ('d2aa0000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 25, 'OPEX-GROCERY', now());

    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('receipts', 'd2aa0000-0000-0000-0000-000000000001/db02_receipt.jpg', 'd2000000-0000-0000-0000-000000000001');
END $$;

-- 1. Members can read their own memberships without a recursion error
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d2000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.household_memberships;
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'Member expected to see exactly own membership, saw %', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: member reads own membership (no policy recursion).';

    SELECT count(*) INTO v_cnt FROM storage.objects WHERE bucket_id = 'receipts'
      AND name LIKE 'd2aa0000-0000-0000-0000-000000000001/%';
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'Member expected to see household receipt, saw %', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: storage receipts policy evaluates for members.';
END $$;
RESET ROLE;

-- 2. Admin sees the household roster; outsider sees nothing of it
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d2000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.household_memberships
    WHERE household_id = 'd2aa0000-0000-0000-0000-000000000001';
    IF v_cnt <> 2 THEN
        RAISE EXCEPTION 'Admin expected to see 2 memberships, saw %', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: admin sees household roster.';
END $$;
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d2000000-0000-0000-0000-000000000003", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.household_memberships
    WHERE household_id = 'd2aa0000-0000-0000-0000-000000000001';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: outsider sees % foreign memberships', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: outsider cannot see foreign memberships.';
END $$;
RESET ROLE;

-- 3. Membership rows are written only through the SECURITY DEFINER RPCs
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d2000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int := 0;
    v_inserted boolean := false;
BEGIN
    BEGIN
        INSERT INTO public.household_memberships (household_id, user_id, role)
        VALUES ('d2aa0000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000003', 'admin');
        v_inserted := true;
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    IF v_inserted THEN
        RAISE EXCEPTION 'VULNERABILITY: admin inserted a membership for a user who never accepted an invite';
    END IF;

    BEGIN
        DELETE FROM public.household_memberships
        WHERE household_id = 'd2aa0000-0000-0000-0000-000000000001'
          AND user_id = 'd2000000-0000-0000-0000-000000000002';
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        v_cnt := 0;
    END;
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: direct membership DELETE bypasses remove_member (users.household_id left stale)';
    END IF;
    RAISE NOTICE 'PASSED: direct membership writes are rejected; RPCs are the only write path.';
END $$;
RESET ROLE;

-- 4. Defence in depth: a stale users.household_id without a membership grants nothing
DELETE FROM public.household_memberships
WHERE household_id = 'd2aa0000-0000-0000-0000-000000000001'
  AND user_id = 'd2000000-0000-0000-0000-000000000002';

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d2000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.transactions
    WHERE household_id = 'd2aa0000-0000-0000-0000-000000000001';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'VULNERABILITY: user without membership still reads % household transaction(s)', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: household access requires a live membership row.';
END $$;
RESET ROLE;

ROLLBACK;
