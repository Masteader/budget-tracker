-- ============================================================================
-- Test 16 (audit DB-12): account deletion of a household's sole admin
--
-- check_last_admin_membership() (BUG-03) raises when the sole admin's
-- membership is deleted while other members remain - including when the
-- delete is the ON DELETE CASCADE from auth.users -> public.users. Deleting
-- such a user's account (Supabase Auth admin API / "delete my account") fails,
-- so the app cannot honour account-deletion requests. The same cascade would
-- also delete the household's shared-pool accounts the admin created
-- (accounts.owner_user_id ON DELETE CASCADE), destroying shared funds history.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('da000000-0000-0000-0000-000000000001', 'db12-admin@test.local'),
        ('da000000-0000-0000-0000-000000000002', 'db12-first-member@test.local'),
        ('da000000-0000-0000-0000-000000000003', 'db12-second-member@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('daaa0000-0000-0000-0000-000000000001', 'DB12 Home', 'DB12HOMECODE0001');

    UPDATE public.users SET household_id = 'daaa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'da000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'daaa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'da000000-0000-0000-0000-000000000002';
    UPDATE public.users SET household_id = 'daaa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'da000000-0000-0000-0000-000000000003';

    -- make the first member unambiguously the longest-standing one
    UPDATE public.household_memberships SET created_at = now() - interval '30 days'
    WHERE user_id = 'da000000-0000-0000-0000-000000000002';

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('daac0000-0000-0000-0000-000000000001', 'daaa0000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'Admin personal', 'bank', 10, false),
        ('daac0000-0000-0000-0000-000000000002', 'daaa0000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'Family pool', 'shared_pool', 900, true);
END $$;

-- 1. Demoting/removing the sole admin by other means is still blocked (BUG-03 intact)
DO $$
DECLARE
    v_blocked boolean := false;
BEGIN
    BEGIN
        DELETE FROM public.household_memberships
        WHERE user_id = 'da000000-0000-0000-0000-000000000001';
    EXCEPTION WHEN raise_exception THEN
        v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'REGRESSION: sole admin membership deleted while members remain';
    END IF;
    RAISE NOTICE 'PASSED: last-admin protection still blocks direct removal.';
END $$;

-- 2. Deleting the sole admin's account succeeds and hands the household over
DO $$
DECLARE
    v_role text;
    v_user_role text;
    v_pool record;
BEGIN
    BEGIN
        DELETE FROM auth.users WHERE id = 'da000000-0000-0000-0000-000000000001';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG (DB-12): deleting the sole admin''s account failed: %', SQLERRM;
    END;

    SELECT role INTO v_role FROM public.household_memberships
    WHERE household_id = 'daaa0000-0000-0000-0000-000000000001'
      AND user_id = 'da000000-0000-0000-0000-000000000002';
    SELECT role INTO v_user_role FROM public.users WHERE id = 'da000000-0000-0000-0000-000000000002';
    IF v_role IS DISTINCT FROM 'admin' OR v_user_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'BUG (DB-12): longest-standing member not promoted (membership %, users.role %)', v_role, v_user_role;
    END IF;

    IF (SELECT role FROM public.household_memberships
        WHERE user_id = 'da000000-0000-0000-0000-000000000003') IS DISTINCT FROM 'member' THEN
        RAISE EXCEPTION 'BUG (DB-12): more than one member promoted';
    END IF;

    SELECT * INTO v_pool FROM public.accounts WHERE id = 'daac0000-0000-0000-0000-000000000002';
    IF v_pool.id IS NULL OR v_pool.owner_user_id IS DISTINCT FROM 'da000000-0000-0000-0000-000000000002'::uuid
       OR v_pool.balance <> 900 THEN
        RAISE EXCEPTION 'BUG (DB-12): shared pool lost or not handed to the new admin (%)', row_to_json(v_pool);
    END IF;

    IF EXISTS (SELECT 1 FROM public.accounts WHERE id = 'daac0000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'BUG (DB-12): deleted user''s personal account still exists';
    END IF;

    RAISE NOTICE 'PASSED: sole admin account deletion promotes successor and preserves shared pools.';
END $$;

ROLLBACK;
