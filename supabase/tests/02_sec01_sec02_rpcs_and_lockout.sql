-- Test 02: Verification of RPCs, Last Admin Protection, and Join Rate Limiting
\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_admin_id uuid := '11111111-1111-1111-1111-111111111111';
    v_member_id uuid := '22222222-2222-2222-2222-222222222222';
    v_hh_id uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_res jsonb;
    v_blocked boolean := false;
    i int;
BEGIN
    -- Auth identities (public.users.id references auth.users.id)
    INSERT INTO auth.users (id, email) VALUES
        (v_admin_id, 'sec02-admin@test.local'),
        (v_member_id, 'sec02-member@test.local')
    ON CONFLICT (id) DO NOTHING;

    -- Setup clean fixtures
    DELETE FROM public.household_memberships WHERE household_id = v_hh_id;
    DELETE FROM public.household_invites WHERE household_id = v_hh_id;
    DELETE FROM public.users WHERE id IN (v_admin_id, v_member_id);
    DELETE FROM public.households WHERE id = v_hh_id;
    DELETE FROM public.invite_attempt_log WHERE user_id IN (v_admin_id, v_member_id);

    INSERT INTO public.households (id, name, invite_code) VALUES (v_hh_id, 'Test Family', 'TESTHH01');

    INSERT INTO public.users (id, display_name, household_id, role, financial_role)
    VALUES (v_admin_id, 'Admin User', v_hh_id, 'admin', 'provider');

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_hh_id, v_admin_id, 'admin', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    INSERT INTO public.users (id, display_name, household_id, role, financial_role)
    VALUES (v_member_id, 'Member User', v_hh_id, 'member', 'spouse');

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_hh_id, v_member_id, 'member', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'member';

    RAISE NOTICE 'Fixtures for RPC test created.';

    -- 1. Sole admin cannot leave household while other members remain
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM public.leave_household();
        v_blocked := false;
    EXCEPTION WHEN OTHERS THEN
        v_blocked := true;
        RAISE NOTICE 'PASSED: Sole admin prevented from leaving while other members remain: %', SQLERRM;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION 'BUG DETECTED: Sole admin was allowed to leave household!';
    END IF;

    -- 2. Sole admin cannot demote themselves to member
    v_blocked := false;
    BEGIN
        PERFORM public.set_member_role(v_admin_id, 'member');
    EXCEPTION WHEN OTHERS THEN
        v_blocked := true;
        RAISE NOTICE 'PASSED: Sole admin prevented from self-demotion: %', SQLERRM;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION 'BUG DETECTED: Sole admin was allowed to demote themselves!';
    END IF;

    -- 3. Non-admin member cannot promote/demote
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_member_id::text, 'role', 'authenticated')::text, true);

    v_blocked := false;
    BEGIN
        PERFORM public.set_member_role(v_member_id, 'admin');
    EXCEPTION WHEN OTHERS THEN
        v_blocked := true;
        RAISE NOTICE 'PASSED: Non-admin member blocked from calling set_member_role: %', SQLERRM;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION 'BUG DETECTED: Non-admin was allowed to set roles!';
    END IF;

    -- 4. Member leaves household successfully
    v_res := public.leave_household();
    IF (v_res->>'success')::boolean IS TRUE THEN
        RAISE NOTICE 'PASSED: Member successfully left household.';
    ELSE
        RAISE EXCEPTION 'Failed to leave household as normal member';
    END IF;

    -- 5. Now that no other members remain, sole admin CAN leave
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    v_res := public.leave_household();
    IF (v_res->>'success')::boolean IS TRUE THEN
        RAISE NOTICE 'PASSED: Last member (sole admin) successfully left empty household.';
    ELSE
        RAISE EXCEPTION 'Failed to leave household as last member';
    END IF;

    -- 6. Test invite rate limiting (lockout window after 5 failed attempts)
    FOR i IN 1..5 LOOP
        v_res := public.join_household_by_code('WRONGCODE' || i);
        IF (v_res->>'error') IS NULL THEN
            RAISE EXCEPTION 'Expected error for wrong code %', i;
        END IF;
    END LOOP;

    v_blocked := false;
    BEGIN
        v_res := public.join_household_by_code('WRONGCODE6');
        IF (v_res->>'error') IS NOT NULL AND v_res->>'error' LIKE '%Too many failed join attempts%' THEN
            v_blocked := true;
            RAISE NOTICE 'PASSED: Join rate limiting returned lockout error: %', v_res->>'error';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Too many failed join attempts%' THEN
            v_blocked := true;
            RAISE NOTICE 'PASSED: Join rate limiting locked out user with exception: %', SQLERRM;
        ELSE
            RAISE NOTICE 'Other error: %', SQLERRM;
        END IF;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION 'Rate limiting did not trigger after 5 failed join attempts!';
    END IF;
END $$;

ROLLBACK;
