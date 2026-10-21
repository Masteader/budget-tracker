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
--
-- FABLE-DB-02 (20261020700000): household_invites.created_by / used_by were
-- ON DELETE NO ACTION, so the account of anyone who created or claimed an
-- invite could not be deleted either. Here the sole admin created two invites
-- and a fourth user claimed one of them through the RPC.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('da000000-0000-0000-0000-000000000001', 'db12-admin@test.local'),
        ('da000000-0000-0000-0000-000000000002', 'db12-first-member@test.local'),
        ('da000000-0000-0000-0000-000000000003', 'db12-second-member@test.local'),
        ('da000000-0000-0000-0000-000000000004', 'db12-invitee@test.local');

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

    -- FABLE-DB-02: the admin created two invites; one is claimed below.
    INSERT INTO public.household_invites (id, household_id, invite_code, role, created_by, expires_at) VALUES
        ('dae10000-0000-0000-0000-000000000001', 'daaa0000-0000-0000-0000-000000000001', 'DB12OPEN', 'family_member',
         'da000000-0000-0000-0000-000000000001', now() + interval '7 days'),
        ('dae10000-0000-0000-0000-000000000002', 'daaa0000-0000-0000-0000-000000000001', 'DB12USED', 'family_member',
         'da000000-0000-0000-0000-000000000001', now() + interval '7 days');
END $$;

-- The fourth user claims DB12USED through the RPC, as the app does.
SELECT set_config('request.jwt.claims', '{"sub": "da000000-0000-0000-0000-000000000004", "role": "authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT public.claim_household_role_invite('DB12USED') ->> 'success' AS db12_invite_claimed;
RESET ROLE;
SELECT set_config('request.jwt.claims', '', true);

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

    -- FABLE-DB-02: the admin's invites belong to the household and stay.
    IF (SELECT count(*) FROM public.household_invites
        WHERE id IN ('dae10000-0000-0000-0000-000000000001', 'dae10000-0000-0000-0000-000000000002')
          AND created_by IS NULL) <> 2 THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): the deleted creator''s invites were lost or still reference him';
    END IF;

    RAISE NOTICE 'PASSED: sole admin account deletion promotes successor and preserves shared pools.';
END $$;

-- 3. FABLE-DB-02: the user who claimed an invite can delete their account; the
--    spent invite goes with them (never re-opened), the open one stays.
DO $$
BEGIN
    IF (SELECT used_by FROM public.household_invites WHERE invite_code = 'DB12USED')
       IS DISTINCT FROM 'da000000-0000-0000-0000-000000000004'::uuid THEN
        RAISE EXCEPTION 'setup: DB12USED was not claimed by the invitee';
    END IF;

    BEGIN
        DELETE FROM auth.users WHERE id = 'da000000-0000-0000-0000-000000000004';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): deleting the account of an invite claimer failed: %', SQLERRM;
    END;

    IF EXISTS (SELECT 1 FROM public.household_invites WHERE invite_code = 'DB12USED') THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): the spent invite survived its claimer (it would become claimable again)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.household_invites WHERE invite_code = 'DB12OPEN' AND used_by IS NULL) THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): an unrelated open invite was removed';
    END IF;
    IF EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = 'da000000-0000-0000-0000-000000000004') THEN
        RAISE EXCEPTION 'deleted invitee still has a membership';
    END IF;

    RAISE NOTICE 'PASSED: FABLE-DB-02 invite creator and claimer can delete their accounts.';
END $$;

ROLLBACK;
