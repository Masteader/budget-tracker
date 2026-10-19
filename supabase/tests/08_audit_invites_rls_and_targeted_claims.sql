-- ============================================================================
-- Test 08 (audit DB-01, DB-05): household_invites RLS + targeted invite claims
--
-- DB-01: household_invites was created without ENABLE ROW LEVEL SECURITY, so
--        its policies were inert and Supabase's default grants let anon read
--        every invite code and any authenticated user forge an invite for any
--        household and then join it.
-- DB-05: join_household_by_code / claim_household_role_invite wrote to the
--        non-existent column household_dependents.claimed_user_id, so every
--        targeted (manual-member) invite failed; the target member was also not
--        checked against the invite's household.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('d1000000-0000-0000-0000-000000000001', 'db01-victim-admin@test.local'),
        ('d1000000-0000-0000-0000-000000000002', 'db01-attacker@test.local'),
        ('d1000000-0000-0000-0000-000000000003', 'db01-newcomer@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('d1aa0000-0000-0000-0000-000000000001', 'DB01 Victim', 'DB01VICTIMSTATIC'),
        ('d1bb0000-0000-0000-0000-000000000001', 'DB01 Attacker', 'DB01ATTACKSTATIC');

    UPDATE public.users SET household_id = 'd1aa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd1000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'd1bb0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd1000000-0000-0000-0000-000000000002';

    INSERT INTO public.household_dependents (id, household_id, name) VALUES
        ('d1de0000-0000-0000-0000-000000000001', 'd1aa0000-0000-0000-0000-000000000001', 'Victim manual member'),
        ('d1de0000-0000-0000-0000-000000000002', 'd1bb0000-0000-0000-0000-000000000001', 'Attacker manual member');

    INSERT INTO public.household_invites (household_id, invite_code, role, expires_at) VALUES
        ('d1aa0000-0000-0000-0000-000000000001', 'DB01REALINVITE01', 'peer', now() + interval '1 day');
END $$;

-- 1. RLS must be enabled on household_invites
DO $$
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.household_invites'::regclass) THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-01): RLS is not enabled on public.household_invites';
    END IF;
    RAISE NOTICE 'PASSED: RLS enabled on household_invites.';
END $$;

-- 2. anon must not read invite codes
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);
DO $$
DECLARE
    v_cnt int := 0;
BEGIN
    BEGIN
        SELECT count(*) INTO v_cnt FROM public.household_invites;
    EXCEPTION WHEN insufficient_privilege THEN
        v_cnt := 0;
    END;
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-01): anon can read % invite code(s)', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: anon cannot read household_invites.';
END $$;
RESET ROLE;

-- 3. A user from another household must neither see nor forge invites for the victim household
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d1000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int;
    v_forged boolean := false;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.household_invites
    WHERE household_id = 'd1aa0000-0000-0000-0000-000000000001';
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-01): attacker can read % victim invite(s)', v_cnt;
    END IF;

    BEGIN
        INSERT INTO public.household_invites (household_id, invite_code, role, expires_at)
        VALUES ('d1aa0000-0000-0000-0000-000000000001', 'DB01FORGEDCODE01', 'peer', now() + interval '1 day');
        v_forged := true;
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    IF v_forged THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-01): attacker forged an invite for a foreign household';
    END IF;

    -- Re-opening a used/expired invite must not be possible either
    UPDATE public.household_invites SET used_by = NULL, expires_at = now() + interval '1 year'
    WHERE invite_code = 'DB01REALINVITE01';
    GET DIAGNOSTICS v_cnt = ROW_COUNT;
    IF v_cnt > 0 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-01): attacker updated a foreign invite';
    END IF;
    RAISE NOTICE 'PASSED: attacker cannot read, forge or modify foreign invites.';
END $$;
RESET ROLE;

-- 4. Invites must not target a manual member of a different household (even via service role)
DO $$
DECLARE
    v_blocked boolean := false;
BEGIN
    BEGIN
        INSERT INTO public.household_invites (household_id, invite_code, role, expires_at, target_member_id)
        VALUES ('d1bb0000-0000-0000-0000-000000000001', 'DB05CROSSTARGET1', 'spouse', now() + interval '1 day',
                'd1de0000-0000-0000-0000-000000000001');
    EXCEPTION WHEN foreign_key_violation OR check_violation OR insufficient_privilege THEN
        v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-05): invite may target a manual member of another household';
    END IF;
    RAISE NOTICE 'PASSED: cross-household target_member_id rejected.';
END $$;

-- 5. Targeted invite via join_household_by_code links the manual member to the claimer
INSERT INTO public.household_invites (household_id, invite_code, role, expires_at, target_member_id)
VALUES ('d1aa0000-0000-0000-0000-000000000001', 'DB05TARGETED0001', 'spouse', now() + interval '1 day',
        'd1de0000-0000-0000-0000-000000000001');

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d1000000-0000-0000-0000-000000000003", "role": "authenticated"}', true);
DO $$
DECLARE
    v_res jsonb;
BEGIN
    v_res := public.join_household_by_code('db05targeted0001');
    IF v_res ? 'error' THEN
        RAISE EXCEPTION 'BUG (DB-05): targeted join failed: %', v_res;
    END IF;
    RAISE NOTICE 'PASSED: targeted invite accepted by join_household_by_code.';
END $$;
RESET ROLE;

DO $$
DECLARE
    v_linked uuid;
    v_hh uuid;
BEGIN
    SELECT linked_user_id INTO v_linked FROM public.household_dependents WHERE id = 'd1de0000-0000-0000-0000-000000000001';
    IF v_linked IS DISTINCT FROM 'd1000000-0000-0000-0000-000000000003'::uuid THEN
        RAISE EXCEPTION 'BUG (DB-05): manual member not linked to claimer (linked_user_id=%)', v_linked;
    END IF;
    SELECT household_id INTO v_hh FROM public.users WHERE id = 'd1000000-0000-0000-0000-000000000003';
    IF v_hh IS DISTINCT FROM 'd1aa0000-0000-0000-0000-000000000001'::uuid THEN
        RAISE EXCEPTION 'BUG (DB-05): claimer not moved into invite household';
    END IF;
    RAISE NOTICE 'PASSED: manual member linked to claiming user.';
END $$;

-- 6. Targeted invite via claim_household_role_invite (service-role path used by ai_service)
UPDATE public.household_dependents SET linked_user_id = NULL WHERE id = 'd1de0000-0000-0000-0000-000000000001';
INSERT INTO public.household_invites (household_id, invite_code, role, expires_at, target_member_id)
VALUES ('d1aa0000-0000-0000-0000-000000000001', 'DB05TARGETED0002', 'spouse', now() + interval '1 day',
        'd1de0000-0000-0000-0000-000000000001');

SET ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role": "service_role"}', true);
DO $$
DECLARE
    v_res jsonb;
BEGIN
    v_res := public.claim_household_role_invite('DB05TARGETED0002', 'd1000000-0000-0000-0000-000000000003');
    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'BUG (DB-05): targeted claim failed: %', v_res;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.household_dependents
        WHERE id = 'd1de0000-0000-0000-0000-000000000001'
          AND linked_user_id = 'd1000000-0000-0000-0000-000000000003'
    ) THEN
        RAISE EXCEPTION 'BUG (DB-05): claim_household_role_invite did not link the manual member';
    END IF;
    RAISE NOTICE 'PASSED: claim_household_role_invite links the manual member.';
END $$;
RESET ROLE;

-- 7. claim_household_role_invite must share the failed-attempt lockout of join_household_by_code
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d1000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);
DO $$
DECLARE
    v_res jsonb;
    v_locked boolean := false;
    i int;
BEGIN
    FOR i IN 1..5 LOOP
        v_res := public.claim_household_role_invite('DB01WRONGCODE00' || i);
        IF (v_res->>'success')::boolean IS TRUE THEN
            RAISE EXCEPTION 'unexpected success for wrong code';
        END IF;
    END LOOP;

    BEGIN
        v_res := public.claim_household_role_invite('DB01WRONGCODE006');
        IF coalesce(v_res->>'error', '') LIKE '%Too many failed%' THEN
            v_locked := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Too many failed%' THEN
            v_locked := true;
        ELSE
            RAISE;
        END IF;
    END;

    IF NOT v_locked THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-01): claim_household_role_invite has no brute-force lockout';
    END IF;
    RAISE NOTICE 'PASSED: claim_household_role_invite enforces the failed-attempt lockout.';
END $$;
RESET ROLE;

ROLLBACK;
