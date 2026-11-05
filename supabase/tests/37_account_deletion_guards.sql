-- ============================================================================
-- Test 37: account deletion schema and pending-deletion guards
--
-- Migration: 20261105000100_account_deletion_schema.sql
--
-- Verifies:
--   1. The new tables have RLS, no policies and no client privileges.
--   2. Clients cannot write the new household columns or delete their own users row.
--   3. A user pending deletion cannot join, claim, create a household, be promoted,
--      receive primary admin or become Nafaqah provider, and the service role cannot
--      add them either. They CAN still switch active household.
--   4. A marked household refuses joins by invite and by permanent code, and new
--      invites. Its existing members can still switch to it.
--   5. A mark clears when the requester leaves or transfers primary admin.
--   6. Out-of-band deletion keeps the handover, prefers a member who is not pending,
--      falls back to a pending one rather than failing, and never deletes a household.
--   7. inquiries accepts type 'account_deletion'.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.run_as(p_role text, p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims',
        CASE WHEN p_sub IS NULL THEN json_build_object('role', p_role)::text
             ELSE json_build_object('sub', p_sub, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.run_as(text, text, text) TO PUBLIC;

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

-- Fixtures ---------------------------------------------------------------------------
-- Family household F: admin A (primary, provider), member P (pending), wife W, member M.
-- Roommate household R: admin P (pending). P is a member of both and active in F.
-- Open household O with invites, to test joining.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e3700000-0000-0000-0000-00000000000a', 't37-a@test.local'),
        ('e3700000-0000-0000-0000-00000000000b', 't37-p@test.local'),
        ('e3700000-0000-0000-0000-00000000000c', 't37-m@test.local'),
        ('e3700000-0000-0000-0000-00000000000d', 't37-o@test.local'),
        ('e3700000-0000-0000-0000-00000000000e', 't37-new@test.local');

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        ('e37a0000-0000-0000-0000-000000000001', 'T37 Family', 'T37FAMILYCODE001', 'family'),
        ('e37a0000-0000-0000-0000-000000000002', 'T37 Rooms',  'T37ROOMSCODE0001', 'roommates'),
        ('e37a0000-0000-0000-0000-000000000003', 'T37 Open',   'T37OPENCODE00001', 'family');

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role) VALUES
        ('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000a', 'admin', true, 'provider'),
        ('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000b', 'member', true, 'family_member'),
        ('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000c', 'member', true, 'family_member'),
        ('e37a0000-0000-0000-0000-000000000002', 'e3700000-0000-0000-0000-00000000000b', 'admin', false, 'peer'),
        ('e37a0000-0000-0000-0000-000000000003', 'e3700000-0000-0000-0000-00000000000d', 'admin', true, 'provider');
    UPDATE public.users SET household_id = 'e37a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'e3700000-0000-0000-0000-00000000000a';
    UPDATE public.users SET household_id = 'e37a0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'family_member'
    WHERE id IN ('e3700000-0000-0000-0000-00000000000b', 'e3700000-0000-0000-0000-00000000000c');
    UPDATE public.users SET household_id = 'e37a0000-0000-0000-0000-000000000003', role = 'admin', financial_role = 'provider'
    WHERE id = 'e3700000-0000-0000-0000-00000000000d';

    INSERT INTO public.household_invites (id, household_id, invite_code, role, created_by, expires_at) VALUES
        ('e37e0000-0000-0000-0000-000000000001', 'e37a0000-0000-0000-0000-000000000003', 'T37INV01', 'family_member',
         'e3700000-0000-0000-0000-00000000000d', now() + interval '7 days'),
        ('e37e0000-0000-0000-0000-000000000002', 'e37a0000-0000-0000-0000-000000000003', 'T37INV02', 'family_member',
         'e3700000-0000-0000-0000-00000000000d', now() + interval '7 days');

    -- P requests deletion.
    INSERT INTO public.account_deletion_requests (user_id, status, stage, scheduled_for)
    VALUES ('e3700000-0000-0000-0000-00000000000b', 'scheduled', 'none', now() + interval '30 days');
END $$;

-- 1. Tables: RLS, no policies, no client privileges ----------------------------------
DO $$
DECLARE
    v_t text;
    v_role text;
    v_priv text;
BEGIN
    FOREACH v_t IN ARRAY ARRAY['account_deletion_requests', 'account_deletion_storage_queue', 'account_deletion_worker_runs'] LOOP
        IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.' || v_t)::regclass) THEN
            RAISE EXCEPTION 'VULNERABILITY: % has no RLS', v_t;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = v_t) THEN
            RAISE EXCEPTION 'VULNERABILITY: % has a policy', v_t;
        END IF;
        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] LOOP
                IF has_table_privilege(v_role, 'public.' || v_t, v_priv) THEN
                    RAISE EXCEPTION 'VULNERABILITY: % holds % on %', v_role, v_priv, v_t;
                END IF;
            END LOOP;
            PERFORM pg_temp.expect(v_role || ' reads ' || v_t,
                pg_temp.run_as(v_role, 'e3700000-0000-0000-0000-00000000000b',
                    format('SELECT count(*)::text FROM public.%I', v_t)), 'ERR:42501');
            PERFORM pg_temp.expect(v_role || ' writes ' || v_t,
                pg_temp.run_as(v_role, 'e3700000-0000-0000-0000-00000000000b',
                    format('DELETE FROM public.%I', v_t)), 'ERR:42501');
        END LOOP;
    END LOOP;
    RAISE NOTICE 'PASSED: new tables have RLS, no policies and no client privileges.';
END $$;

-- 2. Clients cannot write the household marks or delete their users row --------------
DO $$
DECLARE
    v_col text;
BEGIN
    FOREACH v_col IN ARRAY ARRAY['deletion_requested_at', 'deletion_scheduled_for', 'deletion_requested_by'] LOOP
        IF has_column_privilege('authenticated', 'public.households', v_col, 'UPDATE')
           OR has_column_privilege('anon', 'public.households', v_col, 'UPDATE')
           OR has_column_privilege('authenticated', 'public.households', v_col, 'INSERT') THEN
            RAISE EXCEPTION 'VULNERABILITY: clients can write households.%', v_col;
        END IF;
    END LOOP;
    PERFORM pg_temp.expect('admin clears a mark directly',
        pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000a',
            $q$UPDATE public.households SET deletion_scheduled_for = NULL WHERE id = 'e37a0000-0000-0000-0000-000000000001'$q$),
        'ERR:42501');

    PERFORM pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000b',
        $q$DELETE FROM public.users WHERE id = 'e3700000-0000-0000-0000-00000000000b'$q$);
    PERFORM pg_temp.expect('users row survives a client delete',
        (SELECT count(*)::text FROM public.users WHERE id = 'e3700000-0000-0000-0000-00000000000b'), '1');
    RAISE NOTICE 'PASSED: clients cannot write household marks or delete their own users row.';
END $$;

-- 3. A pending user is locked out of new roles, and can still switch ------------------
DO $$
DECLARE
    v_p text := 'e3700000-0000-0000-0000-00000000000b';
    v_res text;
BEGIN
    PERFORM pg_temp.expect('pending user joins by permanent code',
        pg_temp.run_as('authenticated', v_p, $q$SELECT public.join_household_by_code('T37OPENCODE00001')::text$q$),
        'ERR:account_pending_deletion');
    PERFORM pg_temp.expect('pending user joins by invite code',
        pg_temp.run_as('authenticated', v_p, $q$SELECT public.join_household_by_code('T37INV01')::text$q$),
        'ERR:account_pending_deletion');
    PERFORM pg_temp.expect('pending user claims an invite',
        pg_temp.run_as('authenticated', v_p, $q$SELECT public.claim_household_role_invite('T37INV02')::text$q$),
        'ERR:account_pending_deletion');
    PERFORM pg_temp.expect('invite stays open after the refused claim',
        (SELECT used_by::text FROM public.household_invites WHERE invite_code = 'T37INV02'), NULL);
    PERFORM pg_temp.expect('pending user creates a household',
        pg_temp.run_as('authenticated', v_p, $q$SELECT public.create_household_and_claim('T37 Escape')::text$q$),
        'ERR:account_pending_deletion');
    PERFORM pg_temp.expect('no household row left by the refused create',
        (SELECT count(*)::text FROM public.households WHERE name = 'T37 Escape'), '0');

    -- The service role cannot add them directly either.
    PERFORM pg_temp.expect('service role inserts a pending member',
        pg_temp.run_as('service_role', NULL,
            $q$INSERT INTO public.household_memberships (household_id, user_id, role, financial_role)
               VALUES ('e37a0000-0000-0000-0000-000000000003', 'e3700000-0000-0000-0000-00000000000b', 'member', 'family_member')$q$),
        'ERR:account_pending_deletion');

    PERFORM pg_temp.expect('admin promotes a pending member',
        pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000a',
            $q$SELECT public.promote_member_to_admin('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000b')::text$q$),
        'ERR:account_pending_deletion');
    PERFORM pg_temp.expect('service role promotes a pending member directly',
        pg_temp.run_as('service_role', NULL,
            $q$UPDATE public.household_memberships SET role = 'admin'
               WHERE household_id = 'e37a0000-0000-0000-0000-000000000001' AND user_id = 'e3700000-0000-0000-0000-00000000000b'$q$),
        'ERR:account_pending_deletion');
    PERFORM pg_temp.expect('primary admin transfer to a pending member',
        pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000a',
            $q$SELECT public.transfer_primary_admin('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000b')::text$q$),
        'ERR:successor_pending_deletion');
    PERFORM pg_temp.expect('pending member as Nafaqah provider',
        pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000a',
            $q$SELECT public.set_nafaqah_provider('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000b')::text$q$),
        'ERR:account_pending_deletion');

    -- switch_active_household fires the users -> memberships sync, whose INSERT ... ON CONFLICT
    -- also fires BEFORE INSERT triggers. It must keep working, there and back.
    v_res := pg_temp.run_as('authenticated', v_p, $q$SELECT public.switch_active_household('e37a0000-0000-0000-0000-000000000002')::text$q$);
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'REGRESSION: a pending user cannot switch household: %', v_res;
    END IF;
    PERFORM pg_temp.expect('active household after switch',
        (SELECT household_id::text || '/' || role FROM public.users WHERE id = v_p::uuid),
        'e37a0000-0000-0000-0000-000000000002/admin');
    v_res := pg_temp.run_as('authenticated', v_p, $q$SELECT public.switch_active_household('e37a0000-0000-0000-0000-000000000001')::text$q$);
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'REGRESSION: a pending user cannot switch back: %', v_res;
    END IF;
    PERFORM pg_temp.expect('active household after switching back',
        (SELECT household_id::text || '/' || role FROM public.users WHERE id = v_p::uuid),
        'e37a0000-0000-0000-0000-000000000001/member');

    -- A user with no active request is unaffected.
    v_res := pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000a',
        $q$SELECT public.promote_member_to_admin('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000c')::text$q$);
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'REGRESSION: promoting an ordinary member failed: %', v_res;
    END IF;
    PERFORM public.revoke_admin('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000c', 'e3700000-0000-0000-0000-00000000000a');
    RAISE NOTICE 'PASSED: a pending user cannot join, claim, create or be promoted, and can still switch.';
END $$;

-- 4. A marked household refuses joins and invites --------------------------------------
DO $$
DECLARE
    v_new text := 'e3700000-0000-0000-0000-00000000000e';
    v_res text;
BEGIN
    UPDATE public.households
    SET deletion_requested_at = now(), deletion_scheduled_for = now() + interval '30 days',
        deletion_requested_by = 'e3700000-0000-0000-0000-00000000000d'
    WHERE id = 'e37a0000-0000-0000-0000-000000000003';

    PERFORM pg_temp.expect('join a marked household by permanent code',
        pg_temp.run_as('authenticated', v_new, $q$SELECT public.join_household_by_code('T37OPENCODE00001')::text$q$),
        'ERR:household_pending_deletion');
    PERFORM pg_temp.expect('join a marked household by invite',
        pg_temp.run_as('authenticated', v_new, $q$SELECT public.join_household_by_code('T37INV01')::text$q$),
        'ERR:household_pending_deletion');
    PERFORM pg_temp.expect('claim an invite of a marked household',
        pg_temp.run_as('authenticated', v_new, $q$SELECT public.claim_household_role_invite('T37INV02')::text$q$),
        'ERR:household_pending_deletion');
    PERFORM pg_temp.expect('new invite on a marked household',
        pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000d',
            $q$INSERT INTO public.household_invites (household_id, invite_code, role, created_by, expires_at)
               VALUES ('e37a0000-0000-0000-0000-000000000003', 'T37INV03', 'family_member',
                       'e3700000-0000-0000-0000-00000000000d', now() + interval '1 day')$q$),
        'ERR:household_pending_deletion');
    PERFORM pg_temp.expect('service role adds an invite to a marked household',
        pg_temp.run_as('service_role', NULL,
            $q$INSERT INTO public.household_invites (household_id, invite_code, role, expires_at)
               VALUES ('e37a0000-0000-0000-0000-000000000003', 'T37INV04', 'family_member', now() + interval '1 day')$q$),
        'ERR:household_pending_deletion');

    -- The household stays usable for its members during grace.
    v_res := pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000d',
        $q$SELECT public.switch_active_household('e37a0000-0000-0000-0000-000000000003')::text$q$);
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'REGRESSION: a member cannot use a marked household: %', v_res;
    END IF;
    RAISE NOTICE 'PASSED: a marked household refuses joins and invites and stays usable for its members.';
END $$;

-- 5. Marks clear with the requester ---------------------------------------------------
DO $$
DECLARE
    v_res text;
BEGIN
    -- Transfer of primary admin clears the requester's mark.
    v_res := pg_temp.run_as('service_role', NULL,
        $q$INSERT INTO public.household_memberships (household_id, user_id, role, financial_role)
           VALUES ('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000d', 'member', 'family_member') RETURNING 'ok'$q$);
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'fixture: %', v_res; END IF;
    UPDATE public.households
    SET deletion_requested_at = now(), deletion_scheduled_for = now() + interval '30 days',
        deletion_requested_by = 'e3700000-0000-0000-0000-00000000000a'
    WHERE id = 'e37a0000-0000-0000-0000-000000000001';
    -- An existing member, not pending, takes over.
    v_res := pg_temp.run_as('authenticated', 'e3700000-0000-0000-0000-00000000000a',
        $q$SELECT public.transfer_primary_admin('e37a0000-0000-0000-0000-000000000001', 'e3700000-0000-0000-0000-00000000000c')::text$q$);
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'transfer failed: %', v_res; END IF;
    PERFORM pg_temp.expect('mark cleared by transfer',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = 'e37a0000-0000-0000-0000-000000000001'), NULL);

    -- Leaving clears the requester's mark. M is now primary, A a co-admin.
    UPDATE public.households
    SET deletion_requested_at = now(), deletion_scheduled_for = now() + interval '30 days',
        deletion_requested_by = 'e3700000-0000-0000-0000-00000000000a'
    WHERE id = 'e37a0000-0000-0000-0000-000000000001';
    DELETE FROM public.household_memberships
    WHERE household_id = 'e37a0000-0000-0000-0000-000000000001' AND user_id = 'e3700000-0000-0000-0000-00000000000a';
    PERFORM pg_temp.expect('mark cleared by leaving',
        (SELECT coalesce(deletion_scheduled_for::text, 'null') || '/' || coalesce(deletion_requested_at::text, 'null') || '/' || coalesce(deletion_requested_by::text, 'null')
         FROM public.households WHERE id = 'e37a0000-0000-0000-0000-000000000001'), 'null/null/null');
    -- Someone else's mark is not cleared when another member leaves.
    PERFORM pg_temp.expect('mark on Open household untouched',
        (SELECT (deletion_scheduled_for IS NOT NULL)::text FROM public.households WHERE id = 'e37a0000-0000-0000-0000-000000000003'), 'true');
    RAISE NOTICE 'PASSED: a mark clears when its requester transfers primary admin or leaves.';
END $$;

-- 6. Out-of-band deletion: handover kept, never deletes a household ---------------------
DO $$
DECLARE
    v_hh uuid := 'e37a0000-0000-0000-0000-000000000009';
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e3700000-0000-0000-0000-0000000000f1', 't37-f1@test.local'),
        ('e3700000-0000-0000-0000-0000000000f2', 't37-f2@test.local'),
        ('e3700000-0000-0000-0000-0000000000f3', 't37-f3@test.local');
    INSERT INTO public.households (id, name, invite_code, household_type) VALUES (v_hh, 'T37 Handover', 'T37HANDOVER00001', 'roommates');
    INSERT INTO public.household_memberships (household_id, user_id, role, is_default, financial_role, created_at) VALUES
        (v_hh, 'e3700000-0000-0000-0000-0000000000f1', 'admin', true, 'peer', now() - interval '3 days'),
        (v_hh, 'e3700000-0000-0000-0000-0000000000f2', 'member', true, 'peer', now() - interval '2 days'),
        (v_hh, 'e3700000-0000-0000-0000-0000000000f3', 'member', true, 'peer', now() - interval '1 day');
    UPDATE public.users SET household_id = v_hh WHERE id IN
        ('e3700000-0000-0000-0000-0000000000f1', 'e3700000-0000-0000-0000-0000000000f2', 'e3700000-0000-0000-0000-0000000000f3');
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool) VALUES
        ('e37c0000-0000-0000-0000-000000000001', v_hh, 'e3700000-0000-0000-0000-0000000000f1', 'Pool', 'shared_pool', 77, true);
    -- f2 is the longest-standing member but pending, so f3 is preferred.
    INSERT INTO public.account_deletion_requests (user_id, status, stage, scheduled_for)
    VALUES ('e3700000-0000-0000-0000-0000000000f2', 'scheduled', 'none', now() + interval '30 days');
    -- f1 marked the household, then is deleted from the dashboard: the mark must not outlive them.
    UPDATE public.households
    SET deletion_requested_at = now(), deletion_scheduled_for = now() + interval '30 days',
        deletion_requested_by = 'e3700000-0000-0000-0000-0000000000f1'
    WHERE id = v_hh;

    DELETE FROM auth.users WHERE id = 'e3700000-0000-0000-0000-0000000000f1';
    PERFORM pg_temp.expect('household survives an out-of-band delete',
        (SELECT count(*)::text FROM public.households WHERE id = v_hh), '1');
    PERFORM pg_temp.expect('non-pending member promoted',
        (SELECT user_id::text FROM public.household_memberships WHERE household_id = v_hh AND role = 'admin'),
        'e3700000-0000-0000-0000-0000000000f3');
    PERFORM pg_temp.expect('primary admin moved to the non-pending member',
        (SELECT owner_user_id::text FROM public.households WHERE id = v_hh), 'e3700000-0000-0000-0000-0000000000f3');
    PERFORM pg_temp.expect('pool re-owned, balance kept',
        (SELECT owner_user_id::text || '/' || balance::text FROM public.accounts WHERE id = 'e37c0000-0000-0000-0000-000000000001'),
        'e3700000-0000-0000-0000-0000000000f3/77.00');
    PERFORM pg_temp.expect('requester''s mark did not outlive them',
        (SELECT deletion_scheduled_for::text FROM public.households WHERE id = v_hh), NULL);

    -- f3 goes too: only pending f2 remains. A household must keep an admin, so the delete still succeeds.
    DELETE FROM auth.users WHERE id = 'e3700000-0000-0000-0000-0000000000f3';
    PERFORM pg_temp.expect('household survives with only a pending member',
        (SELECT count(*)::text FROM public.households WHERE id = v_hh), '1');
    PERFORM pg_temp.expect('pending member promoted as the last resort',
        (SELECT user_id::text FROM public.household_memberships WHERE household_id = v_hh AND role = 'admin'),
        'e3700000-0000-0000-0000-0000000000f2');
    PERFORM pg_temp.expect('pool re-owned by the last member',
        (SELECT owner_user_id::text || '/' || balance::text FROM public.accounts WHERE id = 'e37c0000-0000-0000-0000-000000000001'),
        'e3700000-0000-0000-0000-0000000000f2/77.00');
    RAISE NOTICE 'PASSED: out-of-band deletion keeps the handover, prefers non-pending members and keeps the household.';
END $$;

-- 7. inquiries accepts the new type, and only known types -------------------------------
DO $$
DECLARE
    v_failed boolean := false;
BEGIN
    INSERT INTO public.inquiries (type, email, reference)
    VALUES ('account_deletion', 't37-public@test.local', 'T37-INQ-1');
    BEGIN
        INSERT INTO public.inquiries (type, email, reference)
        VALUES ('nonsense', 't37-public@test.local', 'T37-INQ-2');
    EXCEPTION WHEN check_violation THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'inquiries accepted an unknown type';
    END IF;
    RAISE NOTICE 'PASSED: inquiries accepts type account_deletion and still refuses unknown types.';
END $$;

ROLLBACK;
