-- ============================================================================
-- Test 23 (independent Fable review, docs/review/audit/fable_review.md §B)
-- Migration: 20261020700000_fable_db_hardening.sql
--
--   FABLE-DB-02  invite creator / claimer can delete their account
--                (created_by ON DELETE SET NULL, used_by ON DELETE CASCADE;
--                a spent invite is never re-opened)
--   FABLE-DB-04  reallocate_budget refuses callers without JWT subject unless
--                they are the service role
--   FABLE-DB-05  nafaqah_current_cycle_key / generate_secure_invite_code are
--                not client RPCs; the definer RPCs using them still work
--   FABLE-DB-06  households: clients update only name, payday_day,
--                monthly_income, rollover_rule
--   FABLE-DB-07  household_dependents.linked_user_id is not client-writable;
--                the targeted invite claim still links
--   FABLE-DB-08  no TRUNCATE / TRIGGER for clients, no anon DML
--   FABLE-DB-09  users.financial_role is not client-insertable
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('f2300000-0000-0000-0000-0000000000a1', 'f23-h@test.local'),   -- H husband, primary admin of F
        ('f2300000-0000-0000-0000-0000000000a2', 'f23-w@test.local'),   -- W wife, claims the spouse invite
        ('f2300000-0000-0000-0000-0000000000a3', 'f23-k@test.local'),   -- K plain member of F
        ('f2300000-0000-0000-0000-0000000000b1', 'f23-o@test.local'),   -- O admin of another household X
        ('f2300000-0000-0000-0000-0000000000c1', 'f23-n@test.local');   -- N new user without a profile row

    INSERT INTO public.households (id, name, invite_code, payday_day) VALUES
        ('f23a0000-0000-0000-0000-000000000001', 'F23 Family', 'F23FAMILYCODE001', 27),
        ('f23b0000-0000-0000-0000-000000000001', 'F23 Other', 'F23OTHERCODE0001', 5);

    UPDATE public.users SET household_id = 'f23a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'f2300000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = 'f23a0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'family_member'
    WHERE id = 'f2300000-0000-0000-0000-0000000000a3';
    UPDATE public.users SET household_id = 'f23b0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'f2300000-0000-0000-0000-0000000000b1';
    UPDATE public.household_memberships SET created_at = now() - interval '30 days'
    WHERE user_id = 'f2300000-0000-0000-0000-0000000000a1';

    INSERT INTO public.household_dependents (id, household_id, name, relationship) VALUES
        ('f23d0000-0000-0000-0000-000000000001', 'f23a0000-0000-0000-0000-000000000001', 'Umm F23', 'spouse');
    INSERT INTO public.household_invites (id, household_id, invite_code, role, created_by, expires_at, target_member_id) VALUES
        ('f23e0000-0000-0000-0000-000000000001', 'f23a0000-0000-0000-0000-000000000001', 'F23WIFE1', 'spouse',
         'f2300000-0000-0000-0000-0000000000a1', now() + interval '7 days', 'f23d0000-0000-0000-0000-000000000001'),
        ('f23e0000-0000-0000-0000-000000000002', 'f23a0000-0000-0000-0000-000000000001', 'F23PEER1', 'peer',
         'f2300000-0000-0000-0000-0000000000a1', now() + interval '7 days', NULL);

    INSERT INTO public.budgets (id, household_id, month, cycle_key, category_code, allocated_amount, spent_amount) VALUES
        ('f23f0000-0000-0000-0000-000000000001', 'f23b0000-0000-0000-0000-000000000001', date_trunc('month', now())::date,
         (SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(now(), 5)), 'OPEX-GROCERY', 1000, 0),
        ('f23f0000-0000-0000-0000-000000000002', 'f23b0000-0000-0000-0000-000000000001', date_trunc('month', now())::date,
         (SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(now(), 5)), 'OPEX-DINING', 100, 0);

    -- N has an auth account but no public.users row yet (older signup path).
    DELETE FROM public.users WHERE id = 'f2300000-0000-0000-0000-0000000000c1';
END $$;

-- Run p_sql as p_role with the given JWT claims ('' = none); return the SQLSTATE.
CREATE FUNCTION pg_temp.run_as(p_role text, p_claims text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_state text := '00000';
BEGIN
    PERFORM set_config('request.jwt.claims', p_claims, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v_state;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.run_as(text, text, text) TO PUBLIC;

CREATE FUNCTION pg_temp.as_user(p_sub text, p_sql text)
RETURNS text
LANGUAGE sql
AS $$
    SELECT pg_temp.run_as('authenticated', json_build_object('sub', p_sub, 'role', 'authenticated')::text, p_sql);
$$;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION '%: got SQLSTATE %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

-- FABLE-DB-09: users.financial_role is not client-insertable --------------------
DO $$
DECLARE
    v_role text;
BEGIN
    IF has_column_privilege('authenticated', 'public.users', 'financial_role', 'INSERT')
       OR has_column_privilege('anon', 'public.users', 'financial_role', 'INSERT') THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-09): a client role can INSERT users.financial_role';
    END IF;
    PERFORM pg_temp.expect('new user inserts own profile as spouse',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000c1',
            $q$INSERT INTO public.users (id, display_name, financial_role)
               VALUES ('f2300000-0000-0000-0000-0000000000c1', 'N', 'spouse')$q$),
        '42501');
    -- The profile insert the policy allows still works (with or without the policy's own values).
    PERFORM pg_temp.expect('new user inserts own profile',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000c1',
            $q$INSERT INTO public.users (id, display_name, payday_day, household_id, role)
               VALUES ('f2300000-0000-0000-0000-0000000000c1', 'N', 25, NULL, 'member')$q$),
        '00000');
    SELECT financial_role INTO v_role FROM public.users WHERE id = 'f2300000-0000-0000-0000-0000000000c1';
    IF v_role = 'spouse' THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-09): financial_role taken from the client';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-09 users.financial_role is not client-insertable; profile insert still works.';
END $$;

-- FABLE-DB-06: households client-updatable columns ------------------------------
DO $$
DECLARE
    v_hh public.households%ROWTYPE;
BEGIN
    PERFORM pg_temp.expect('admin probes another household''s join code',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET invite_code = 'F23OTHERCODE0001' WHERE id = 'f23a0000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('admin sets a weak join code',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET invite_code = 'AAAA' WHERE id = 'f23a0000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('admin rewrites the rollover ledger',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET accumulated_savings = 999999, last_rollover_cycle = '2099-01' WHERE id = 'f23a0000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('admin re-keys the household',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET created_at = now() - interval '9 years' WHERE id = 'f23a0000-0000-0000-0000-000000000001'$q$),
        '42501');

    -- Settings the deployed and the new app write directly keep working.
    PERFORM pg_temp.expect('admin updates payday_day / monthly_income / rollover_rule / name',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a1',
            $q$UPDATE public.households SET payday_day = 25, monthly_income = 12000, rollover_rule = 'send_to_savings', name = 'F23 Renamed'
               WHERE id = 'f23a0000-0000-0000-0000-000000000001'$q$),
        '00000');
    SELECT * INTO v_hh FROM public.households WHERE id = 'f23a0000-0000-0000-0000-000000000001';
    IF v_hh.payday_day <> 25 OR v_hh.monthly_income <> 12000 OR v_hh.rollover_rule <> 'send_to_savings'
       OR v_hh.name <> 'F23 Renamed' OR v_hh.invite_code <> 'F23FAMILYCODE001' THEN
        RAISE EXCEPTION 'households settings not stored as expected: %', row_to_json(v_hh);
    END IF;
    -- RLS still limits it to admins.
    PERFORM pg_temp.expect('member update (RLS filters, no error)',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.households SET payday_day = 1 WHERE id = 'f23a0000-0000-0000-0000-000000000001'$q$),
        '00000');
    IF (SELECT payday_day FROM public.households WHERE id = 'f23a0000-0000-0000-0000-000000000001') <> 25 THEN
        RAISE EXCEPTION 'REGRESSION: a plain member changed the payday';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-06 households: clients update only name, payday_day, monthly_income, rollover_rule.';
END $$;

-- FABLE-DB-07: household_dependents.linked_user_id ------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('member re-points a manual member to an outsider',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.household_dependents SET linked_user_id = 'f2300000-0000-0000-0000-0000000000b1'
               WHERE id = 'f23d0000-0000-0000-0000-000000000001'$q$),
        '42501');
    PERFORM pg_temp.expect('member inserts a manual member linked to an outsider',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$INSERT INTO public.household_dependents (household_id, name, relationship, linked_user_id)
               VALUES ('f23a0000-0000-0000-0000-000000000001', 'Fake', 'spouse', 'f2300000-0000-0000-0000-0000000000b1')$q$),
        '42501');
    PERFORM pg_temp.expect('member moves a manual member to another id',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.household_dependents SET id = gen_random_uuid() WHERE id = 'f23d0000-0000-0000-0000-000000000001'$q$),
        '42501');
    IF (SELECT linked_user_id FROM public.household_dependents WHERE id = 'f23d0000-0000-0000-0000-000000000001') IS NOT NULL THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-07): linked_user_id changed by a member';
    END IF;

    -- Ordinary manual-member edits still work.
    PERFORM pg_temp.expect('member edits a manual member',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$UPDATE public.household_dependents SET name = 'Umm F23 (edited)', avatar_icon = 'woman', monthly_allowance = 300
               WHERE id = 'f23d0000-0000-0000-0000-000000000001'$q$),
        '00000');
    PERFORM pg_temp.expect('member adds a manual member',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$INSERT INTO public.household_dependents (household_id, name, relationship, avatar_icon, monthly_allowance)
               VALUES ('f23a0000-0000-0000-0000-000000000001', 'Child F23', 'child', 'child', 50)$q$),
        '00000');
    IF (SELECT name FROM public.household_dependents WHERE id = 'f23d0000-0000-0000-0000-000000000001') <> 'Umm F23 (edited)' THEN
        RAISE EXCEPTION 'manual member edit not stored';
    END IF;

    -- The targeted invite claim (SECURITY DEFINER) still links the real wife.
    PERFORM pg_temp.expect('wife claims her targeted invite',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a2',
            $q$SELECT public.claim_household_role_invite('F23WIFE1')$q$),
        '00000');
    IF (SELECT linked_user_id FROM public.household_dependents WHERE id = 'f23d0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2300000-0000-0000-0000-0000000000a2'::uuid THEN
        RAISE EXCEPTION 'REGRESSION: the targeted invite claim no longer links the manual member';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-07 linked_user_id is set only by the invite claim; other manual-member edits work.';
END $$;

-- FABLE-DB-05: helpers are not client RPCs; definer callers still work -----------
DO $$
DECLARE
    v_status text;
BEGIN
    PERFORM pg_temp.expect('member reads another household''s cycle key',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$SELECT public.nafaqah_current_cycle_key('f23b0000-0000-0000-0000-000000000001')$q$),
        '42501');
    PERFORM pg_temp.expect('member calls generate_secure_invite_code',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$SELECT public.generate_secure_invite_code()$q$),
        '42501');
    PERFORM pg_temp.expect('service role keeps nafaqah_current_cycle_key',
        pg_temp.run_as('service_role', '{"role": "service_role"}',
            $q$SELECT public.nafaqah_current_cycle_key('f23b0000-0000-0000-0000-000000000001')$q$),
        '00000');

    -- The wife (claimed above) is a spouse member: the allowance RPCs that call
    -- nafaqah_current_cycle_key internally still work for clients.
    PERFORM pg_temp.expect('husband sets the allowance (current cycle)',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a1',
            $q$SELECT public.set_member_allowance('f23a0000-0000-0000-0000-000000000001', 'f2300000-0000-0000-0000-0000000000a2', 800)$q$),
        '00000');
    PERFORM pg_temp.expect('wife reads her allowance status (current cycle)',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a2',
            $q$SELECT public.get_member_allowance_status('f23a0000-0000-0000-0000-000000000001', 'f2300000-0000-0000-0000-0000000000a2')$q$),
        '00000');
    IF NOT EXISTS (SELECT 1 FROM public.member_allowances
                   WHERE household_id = 'f23a0000-0000-0000-0000-000000000001'
                     AND member_user_id = 'f2300000-0000-0000-0000-0000000000a2' AND amount = 800) THEN
        RAISE EXCEPTION 'REGRESSION: set_member_allowance did not store the allowance';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-05 helpers are not client RPCs; allowance RPCs still work.';
END $$;

-- FABLE-DB-04: reallocate_budget fails closed --------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('authenticated without any JWT claims',
        pg_temp.run_as('authenticated', '',
            $q$SELECT public.reallocate_budget('f23f0000-0000-0000-0000-000000000001', 'f23f0000-0000-0000-0000-000000000002', 900)$q$),
        '42501');
    PERFORM pg_temp.expect('authenticated role claim without subject',
        pg_temp.run_as('authenticated', '{"role": "authenticated"}',
            $q$SELECT public.reallocate_budget('f23f0000-0000-0000-0000-000000000001', 'f23f0000-0000-0000-0000-000000000002', 900)$q$),
        '42501');
    PERFORM pg_temp.expect('member of another household',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000a3',
            $q$SELECT public.reallocate_budget('f23f0000-0000-0000-0000-000000000001', 'f23f0000-0000-0000-0000-000000000002', 900)$q$),
        '42501');
    IF (SELECT allocated_amount FROM public.budgets WHERE id = 'f23f0000-0000-0000-0000-000000000001') <> 1000 THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-04): reallocation without authentication went through';
    END IF;

    PERFORM pg_temp.expect('household admin',
        pg_temp.as_user('f2300000-0000-0000-0000-0000000000b1',
            $q$SELECT public.reallocate_budget('f23f0000-0000-0000-0000-000000000001', 'f23f0000-0000-0000-0000-000000000002', 100)$q$),
        '00000');
    PERFORM pg_temp.expect('service role (ai_service)',
        pg_temp.run_as('service_role', '{"role": "service_role"}',
            $q$SELECT public.reallocate_budget('f23f0000-0000-0000-0000-000000000001', 'f23f0000-0000-0000-0000-000000000002', 50)$q$),
        '00000');
    IF (SELECT allocated_amount FROM public.budgets WHERE id = 'f23f0000-0000-0000-0000-000000000001') <> 850
       OR (SELECT allocated_amount FROM public.budgets WHERE id = 'f23f0000-0000-0000-0000-000000000002') <> 250 THEN
        RAISE EXCEPTION 'reallocations by admin / service role not applied';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-04 reallocate_budget requires the service role or an authenticated subject.';
END $$;

-- FABLE-DB-08: no TRUNCATE / TRIGGER for clients, no anon DML ----------------------
DO $$
DECLARE
    v_bad text;
BEGIN
    PERFORM pg_temp.expect('authenticated TRUNCATE transactions',
        pg_temp.run_as('authenticated', '', $q$TRUNCATE public.transactions CASCADE$q$),
        '42501');
    PERFORM pg_temp.expect('authenticated TRUNCATE household_invites',
        pg_temp.run_as('authenticated', '', $q$TRUNCATE public.household_invites$q$),
        '42501');
    PERFORM pg_temp.expect('anon INSERT invite_attempt_log',
        pg_temp.run_as('anon', '{"role": "anon"}',
            $q$INSERT INTO public.invite_attempt_log DEFAULT VALUES$q$),
        '42501');
    PERFORM pg_temp.expect('anon DELETE users',
        pg_temp.run_as('anon', '{"role": "anon"}', $q$DELETE FROM public.users$q$),
        '42501');

    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
    FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p')
      AND (has_table_privilege('anon', c.oid, 'TRUNCATE')
           OR has_table_privilege('authenticated', c.oid, 'TRUNCATE')
           OR has_table_privilege('authenticated', c.oid, 'TRIGGER')
           OR has_table_privilege('anon', c.oid, 'TRIGGER')
           OR has_table_privilege('authenticated', c.oid, 'REFERENCES')
           OR has_any_column_privilege('anon', c.oid, 'INSERT')
           OR has_any_column_privilege('anon', c.oid, 'UPDATE')
           OR has_table_privilege('anon', c.oid, 'DELETE'));
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-08): TRUNCATE/TRIGGER/REFERENCES or anon DML on %', v_bad;
    END IF;

    -- What clients really use is still there.
    IF NOT has_table_privilege('authenticated', 'public.transactions', 'INSERT')
       OR NOT has_table_privilege('authenticated', 'public.transactions', 'UPDATE')
       OR NOT has_table_privilege('authenticated', 'public.transactions', 'DELETE')
       OR NOT has_table_privilege('authenticated', 'public.budgets', 'UPDATE')
       OR NOT has_table_privilege('authenticated', 'public.accounts', 'INSERT')
       OR NOT has_table_privilege('service_role', 'public.transactions', 'TRUNCATE') THEN
        RAISE EXCEPTION 'REGRESSION (FABLE-DB-08): a privilege clients or the service role use was revoked';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-08 no client TRUNCATE/TRIGGER/REFERENCES, no anon DML; client DML intact.';
END $$;

-- FABLE-DB-02: invite creator and claimer can delete their account ----------------
DO $$
DECLARE
    v_fk text;
BEGIN
    SELECT string_agg(a.attname || ':' || c.confdeltype::text, ',' ORDER BY a.attname) INTO v_fk
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.conrelid = 'public.household_invites'::regclass AND c.contype = 'f'
      AND a.attname IN ('created_by', 'used_by');
    IF v_fk IS DISTINCT FROM 'created_by:n,used_by:c' THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): household_invites FKs are % (want created_by SET NULL, used_by CASCADE)', v_fk;
    END IF;

    -- W claimed F23WIFE1 above: deleting her account removes the spent invite
    -- (it is NOT re-opened) and unlinks the manual member.
    BEGIN
        DELETE FROM auth.users WHERE id = 'f2300000-0000-0000-0000-0000000000a2';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): deleting the invite claimer failed: %', SQLERRM;
    END;
    IF EXISTS (SELECT 1 FROM public.household_invites WHERE invite_code = 'F23WIFE1') THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): the claimed invite survived its claimer (would be re-claimable)';
    END IF;
    IF (SELECT linked_user_id FROM public.household_dependents WHERE id = 'f23d0000-0000-0000-0000-000000000001') IS NOT NULL THEN
        RAISE EXCEPTION 'manual member still linked to a deleted user';
    END IF;

    -- H created both invites: deleting his account keeps the open invite (household-owned).
    BEGIN
        DELETE FROM auth.users WHERE id = 'f2300000-0000-0000-0000-0000000000a1';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): deleting the invite creator failed: %', SQLERRM;
    END;
    IF NOT EXISTS (SELECT 1 FROM public.household_invites
                   WHERE invite_code = 'F23PEER1' AND created_by IS NULL AND used_by IS NULL) THEN
        RAISE EXCEPTION 'BUG (FABLE-DB-02): the open invite of a deleted creator was lost or not unlinked';
    END IF;
    IF (SELECT owner_user_id FROM public.households WHERE id = 'f23a0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2300000-0000-0000-0000-0000000000a3'::uuid THEN
        RAISE EXCEPTION 'primary admin not handed over to the remaining member';
    END IF;
    RAISE NOTICE 'PASSED: FABLE-DB-02 invite creator and claimer can delete their accounts; spent invites are not re-opened.';
END $$;

ROLLBACK;
