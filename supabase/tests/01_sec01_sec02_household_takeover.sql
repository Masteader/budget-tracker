-- Test 01: SEC-01 & SEC-02 Household Takeover Prevention & Policy Hardening
\set ON_ERROR_STOP on

BEGIN;

-- Setup test users and data
DO $$
DECLARE
    v_admin_id uuid := '11111111-1111-1111-1111-111111111111';
    v_member_id uuid := '22222222-2222-2222-2222-222222222222';
    v_attacker_id uuid := '33333333-3333-3333-3333-333333333333';
    v_victim_hh uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_attacker_hh uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    v_invite_code text;
    v_cnt int;
    v_err text;
BEGIN
    -- 0. Auth identities (public.users.id references auth.users.id)
    INSERT INTO auth.users (id, email) VALUES
        (v_admin_id, 'sec01-admin@test.local'),
        (v_member_id, 'sec01-member@test.local'),
        (v_attacker_id, 'sec01-attacker@test.local')
    ON CONFLICT (id) DO NOTHING;

    -- 1. Create clean test households
    DELETE FROM public.household_memberships WHERE household_id IN (v_victim_hh, v_attacker_hh);
    DELETE FROM public.household_invites WHERE household_id IN (v_victim_hh, v_attacker_hh) OR invite_code = 'SECRETINVITE99';
    DELETE FROM public.cost_control_codes WHERE household_id IN (v_victim_hh, v_attacker_hh) OR code = 'VICTIM_PRIVATE_CAT';
    DELETE FROM public.users WHERE id IN (v_admin_id, v_member_id, v_attacker_id);
    DELETE FROM public.households WHERE id IN (v_victim_hh, v_attacker_hh) OR invite_code IN ('VICTIM01', 'ATTACK01');

    INSERT INTO public.households (id, name, invite_code) VALUES 
        (v_victim_hh, 'Victim Family', 'VICTIM01'),
        (v_attacker_hh, 'Attacker Household', 'ATTACK01');

    -- Admin user of victim household
    INSERT INTO public.users (id, display_name, household_id, role, financial_role)
    VALUES (v_admin_id, 'Victim Admin', v_victim_hh, 'admin', 'provider');

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_victim_hh, v_admin_id, 'admin', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    -- Normal member of victim household
    INSERT INTO public.users (id, display_name, household_id, role, financial_role)
    VALUES (v_member_id, 'Victim Member', v_victim_hh, 'member', 'spouse');

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_victim_hh, v_member_id, 'member', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'member';

    -- Attacker user
    INSERT INTO public.users (id, display_name, household_id, role, financial_role)
    VALUES (v_attacker_id, 'Attacker', v_attacker_hh, 'member', 'peer');

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_attacker_hh, v_attacker_id, 'member', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'member';

    -- Create invite for victim household
    INSERT INTO public.household_invites (household_id, invite_code, role, created_by, expires_at)
    VALUES (v_victim_hh, 'SECRETINVITE99', 'peer', v_admin_id, now() + interval '1 day');

    -- Create custom cost control code for victim household
    INSERT INTO public.cost_control_codes (id, code, category, keywords, is_flexible, household_id)
    VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'VICTIM_PRIVATE_CAT', 'Secret Ops', '{}', true, v_victim_hh);

    RAISE NOTICE 'Test fixtures created successfully.';
END $$;

-- Subtest 1: Verify authenticated user CANNOT elevate own role or change household directly via UPDATE
DO $$
DECLARE
    v_attacker_id uuid := '33333333-3333-3333-3333-333333333333';
    v_victim_hh uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_succeeded boolean := false;
BEGIN
    -- Simulate authenticated attacker
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker_id::text, 'role', 'authenticated')::text, true);

    BEGIN
        UPDATE public.users SET role = 'admin' WHERE id = v_attacker_id;
        v_succeeded := true;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Direct UPDATE on users.role blocked by column privileges.';
    END;

    IF v_succeeded THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Authenticated user was able to directly UPDATE users.role!';
    END IF;

    -- Now test direct UPDATE on household_id
    v_succeeded := false;
    BEGIN
        UPDATE public.users SET household_id = v_victim_hh WHERE id = v_attacker_id;
        v_succeeded := true;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Direct UPDATE on users.household_id blocked by column privileges.';
    END;

    IF v_succeeded THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Authenticated user was able to directly UPDATE users.household_id!';
    END IF;

    -- But user CAN update their own display_name
    UPDATE public.users SET display_name = 'Attacker Renamed' WHERE id = v_attacker_id;
    RAISE NOTICE 'PASSED: User permitted to update permitted column (display_name).';
END $$;

-- Subtest 2: Verify users_insert_own blocks creating an admin or attaching to a household on insert
DO $$
DECLARE
    v_new_user uuid := '44444444-4444-4444-4444-444444444444';
    v_victim_hh uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_succeeded boolean := false;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_new_user::text, 'role', 'authenticated')::text, true);

    -- Try to insert self as admin
    BEGIN
        INSERT INTO public.users (id, display_name, role) VALUES (v_new_user, 'Rogue Admin', 'admin');
        v_succeeded := true;
    EXCEPTION WHEN check_violation OR insufficient_privilege OR SQLSTATE '44000' THEN
        RAISE NOTICE 'PASSED: Direct INSERT with role = admin blocked by RLS.';
    END;

    IF v_succeeded THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Authenticated user inserted self as admin!';
    END IF;

    -- Try to insert self directly into victim household
    v_succeeded := false;
    BEGIN
        INSERT INTO public.users (id, display_name, household_id, role) 
        VALUES (v_new_user, 'Rogue Member', v_victim_hh, 'member');
        v_succeeded := true;
    EXCEPTION WHEN check_violation OR insufficient_privilege OR SQLSTATE '44000' THEN
        RAISE NOTICE 'PASSED: Direct INSERT with foreign household_id blocked by RLS.';
    END;

    IF v_succeeded THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Authenticated user inserted self into victim household!';
    END IF;
END $$;

-- Subtest 3: Verify household_invites cannot be queried by anon or unrelated authenticated user
DO $$
DECLARE
    v_attacker_id uuid := '33333333-3333-3333-3333-333333333333';
    v_cnt int;
BEGIN
    -- Check as anon
    PERFORM set_config('role', 'anon', true);
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);

    -- anon has no table privilege at all since audit DB-01 (permission denied == 0 visible)
    BEGIN
        SELECT count(*) INTO v_cnt FROM public.household_invites;
    EXCEPTION WHEN insufficient_privilege THEN
        v_cnt := 0;
    END;
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Anon user can see % household invites!', v_cnt;
    ELSE
        RAISE NOTICE 'PASSED: Anon cannot view household_invites (0 visible).';
    END IF;

    -- Check as authenticated attacker (not in victim household)
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker_id::text, 'role', 'authenticated')::text, true);

    SELECT count(*) INTO v_cnt FROM public.household_invites WHERE invite_code = 'SECRETINVITE99';
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Attacker can see victim household invites!';
    ELSE
        RAISE NOTICE 'PASSED: Attacker cannot see victim household_invites.';
    END IF;
END $$;

-- Subtest 4: Verify cost_control_codes custom categories do NOT leak to other households
DO $$
DECLARE
    v_attacker_id uuid := '33333333-3333-3333-3333-333333333333';
    v_cnt int;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker_id::text, 'role', 'authenticated')::text, true);

    SELECT count(*) INTO v_cnt FROM public.cost_control_codes WHERE code = 'VICTIM_PRIVATE_CAT';
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Attacker can see victim custom category code!';
    ELSE
        RAISE NOTICE 'PASSED: Cross-household custom category codes do not leak.';
    END IF;
END $$;

-- Subtest 5: Verify trigger functions cannot be called directly by anon or authenticated
DO $$
DECLARE
    v_attacker_id uuid := '33333333-3333-3333-3333-333333333333';
    v_succeeded boolean := false;
BEGIN
    PERFORM set_config('role', 'anon', true);
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);

    BEGIN
        PERFORM public.sync_user_household_membership();
        v_succeeded := true;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Anon cannot execute sync_user_household_membership directly.';
    END;

    IF v_succeeded THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Anon can execute sync_user_household_membership!';
    END IF;

    v_succeeded := false;
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_attacker_id::text, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM public.handle_new_auth_user();
        v_succeeded := true;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSED: Authenticated cannot execute handle_new_auth_user directly.';
    END;

    IF v_succeeded THEN
        RAISE EXCEPTION 'VULNERABILITY DETECTED: Authenticated can execute handle_new_auth_user!';
    END IF;
END $$;

ROLLBACK;
