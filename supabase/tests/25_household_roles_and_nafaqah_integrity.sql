-- ============================================================================
-- Test 25 (Fable review A + B, migration 20261020800000): household roles and
-- Nafaqah integrity.
--
--   FABLE-LOGIC-01  financial role per membership: a wife who joins a roommate
--                   household stays the wife of her family; a spouse joining
--                   roommates by code does not turn the flat into a family.
--   FABLE-LOGIC-04  explicit households.nafaqah_provider_user_id: defaults to the
--                   primary admin (a son who created the household), changeable
--                   by an admin via set_nafaqah_provider, cleared when the
--                   provider leaves (new classified rows refused until set);
--                   transfer_primary_admin keeps it; family joiners by code are
--                   'family_member'.
--   FABLE-DB-01/03  invites admin-readable only; existing members cannot claim
--                   an invite of their own household; re-joining never demotes.
--   FABLE-LOGIC-02  300 advance, 200 repaid, edit to 100 / delete / declassify
--                   refused (22023 ledger_would_be_overpaid).
--   FABLE-LOGIC-06  wife_personal never reaches the category budget.
--   FABLE-LOGIC-05  payday 27 -> 10 re-keys the Nov 5 purchase; open-cycle
--                   budgets and allowances follow the new key without duplicates.
-- Fails before the migration (missing column / function), passes after.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Helpers ----------------------------------------------------------------------
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

-- Run a query returning one value as the user; errors surface as 'ERR:<sqlstate>'.
CREATE FUNCTION pg_temp.as_user_val(p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v text;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        EXECUTE p_sql INTO v;
    EXCEPTION WHEN OTHERS THEN
        v := 'ERR:' || SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user_val(text, text) TO authenticated;

-- SQLSTATE and HINT of a statement run with the owner's rights ('00000:' on success).
CREATE FUNCTION pg_temp.state_hint(p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_state text;
    v_hint text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        RETURN v_state || ':' || COALESCE(v_hint, '');
    END;
    RETURN '00000:';
END;
$$;

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

-- Fixtures -----------------------------------------------------------------------
-- F family: H (primary admin, provider), C (co-admin), W (wife), K (adult son).
-- R roommates: P1 (admin, peer), P2 (peer).  G family: O (admin), J (wife).
-- Y / Y2 / Z: payday households.  S creates household N through the RPC later.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('25000000-0000-0000-0000-0000000000a1', 'r25-h@test.local'),
        ('25000000-0000-0000-0000-0000000000a2', 'r25-w@test.local'),
        ('25000000-0000-0000-0000-0000000000a3', 'r25-k@test.local'),
        ('25000000-0000-0000-0000-0000000000a4', 'r25-c@test.local'),
        ('25000000-0000-0000-0000-0000000000a5', 'r25-wr@test.local'),
        ('25000000-0000-0000-0000-0000000000b1', 'r25-p1@test.local'),
        ('25000000-0000-0000-0000-0000000000b2', 'r25-p2@test.local'),
        ('25000000-0000-0000-0000-0000000000c1', 'r25-o@test.local'),
        ('25000000-0000-0000-0000-0000000000c2', 'r25-j@test.local'),
        ('25000000-0000-0000-0000-0000000000d1', 'r25-s@test.local'),
        ('25000000-0000-0000-0000-0000000000d2', 'r25-w3@test.local'),
        ('25000000-0000-0000-0000-0000000000d3', 'r25-h2@test.local'),
        ('25000000-0000-0000-0000-0000000000d4', 'r25-m@test.local'),
        ('25000000-0000-0000-0000-0000000000e1', 'r25-y1@test.local'),
        ('25000000-0000-0000-0000-0000000000e2', 'r25-y2@test.local'),
        ('25000000-0000-0000-0000-0000000000e3', 'r25-z1@test.local'),
        ('25000000-0000-0000-0000-0000000000e4', 'r25-q1@test.local'),
        ('25000000-0000-0000-0000-0000000000e5', 'r25-q2@test.local');

    INSERT INTO public.households (id, name, invite_code, payday_day) VALUES
        ('25aa0000-0000-0000-0000-000000000001', 'R25 Family', 'R25FAMILYCODE001', 27),
        ('25aa0000-0000-0000-0000-000000000002', 'R25 Flat', 'R25FLATCODE00001', 27),
        ('25aa0000-0000-0000-0000-000000000003', 'R25 Other Family', 'R25OTHERFAM00001', 27),
        ('25aa0000-0000-0000-0000-000000000004', 'R25 Payday Y', 'R25PAYDAYY000001', 27),
        ('25aa0000-0000-0000-0000-000000000005', 'R25 Payday Z', 'R25PAYDAYZ000001', 27),
        ('25aa0000-0000-0000-0000-000000000006', 'R25 Payday Y2', 'R25PAYDAYY200001', 27);
    -- Roommate household (household_type, migration 20261020900000).
    UPDATE public.households SET household_type = 'roommates' WHERE id = '25aa0000-0000-0000-0000-000000000002';

    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = '25000000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'spouse'
    WHERE id = '25000000-0000-0000-0000-0000000000a2';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'family_member'
    WHERE id = '25000000-0000-0000-0000-0000000000a3';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = '25000000-0000-0000-0000-0000000000a4';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000002', role = 'admin', financial_role = 'peer'
    WHERE id = '25000000-0000-0000-0000-0000000000b1';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000002', role = 'member', financial_role = 'peer'
    WHERE id = '25000000-0000-0000-0000-0000000000b2';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000003', role = 'admin', financial_role = 'provider'
    WHERE id = '25000000-0000-0000-0000-0000000000c1';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000003', role = 'member', financial_role = 'spouse'
    WHERE id = '25000000-0000-0000-0000-0000000000c2';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000004', role = 'admin', financial_role = 'provider'
    WHERE id = '25000000-0000-0000-0000-0000000000e1';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000004', role = 'member', financial_role = 'spouse'
    WHERE id = '25000000-0000-0000-0000-0000000000e2';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000005', role = 'admin', financial_role = 'provider'
    WHERE id = '25000000-0000-0000-0000-0000000000e3';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000006', role = 'admin', financial_role = 'provider'
    WHERE id = '25000000-0000-0000-0000-0000000000e4';
    UPDATE public.users SET household_id = '25aa0000-0000-0000-0000-000000000006', role = 'member', financial_role = 'spouse'
    WHERE id = '25000000-0000-0000-0000-0000000000e5';

    -- Targeted spouse invite of F (meant for WR) and a peer invite of R.
    INSERT INTO public.household_invites (id, household_id, invite_code, role, created_by, expires_at) VALUES
        ('25ee0000-0000-0000-0000-000000000001', '25aa0000-0000-0000-0000-000000000001', 'R25WIFE1', 'spouse',
         '25000000-0000-0000-0000-0000000000a1', now() + interval '7 days'),
        ('25ee0000-0000-0000-0000-000000000002', '25aa0000-0000-0000-0000-000000000002', 'R25PEER1', 'peer',
         '25000000-0000-0000-0000-0000000000b1', now() + interval '7 days');
END $$;

-- 1. Catalog and backfill/defaults ------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'household_memberships'
                     AND column_name = 'financial_role' AND is_nullable = 'NO') THEN
        RAISE EXCEPTION 'MISSING (FABLE-LOGIC-01): household_memberships.financial_role NOT NULL';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'households' AND column_name = 'nafaqah_provider_user_id') THEN
        RAISE EXCEPTION 'MISSING (FABLE-LOGIC-04): households.nafaqah_provider_user_id';
    END IF;
    IF has_column_privilege('authenticated', 'public.households', 'nafaqah_provider_user_id', 'UPDATE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can write the Nafaqah provider directly';
    END IF;
    IF NOT has_function_privilege('authenticated', 'public.set_nafaqah_provider(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_nafaqah_provider(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.rekey_household_cycles(uuid, integer, integer, timestamptz)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.nafaqah_husband_id(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'function privileges are wrong (set_nafaqah_provider for authenticated only; internals not client-callable)';
    END IF;

    PERFORM pg_temp.expect('wife membership role in F',
        public.household_member_financial_role('25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a2'), 'spouse');
    PERFORM pg_temp.expect('F provider defaults to the primary admin',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = '25aa0000-0000-0000-0000-000000000001'),
        '25000000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('F husband', public.nafaqah_husband_id('25aa0000-0000-0000-0000-000000000001')::text,
        '25000000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('roommates have no husband', public.nafaqah_husband_id('25aa0000-0000-0000-0000-000000000002')::text, NULL);
    RAISE NOTICE 'PASSED: membership financial_role and provider column exist; provider defaults to the primary admin.';
END $$;

-- 2. FABLE-LOGIC-01: the wife joins a roommate household -> family unaffected -------
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a2',
        $q$SELECT public.claim_household_role_invite('R25PEER1')::text$q$);
    IF (v_res::jsonb->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'wife could not join the roommates: %', v_res;
    END IF;

    PERFORM pg_temp.expect('wife role in R', public.household_member_financial_role(
        '25aa0000-0000-0000-0000-000000000002', '25000000-0000-0000-0000-0000000000a2'), 'peer');
    PERFORM pg_temp.expect('wife role in F unchanged', public.household_member_financial_role(
        '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a2'), 'spouse');
    PERFORM pg_temp.expect('users cache follows the active household (R)',
        (SELECT financial_role FROM public.users WHERE id = '25000000-0000-0000-0000-0000000000a2'), 'peer');
    IF NOT public.nafaqah_is_spouse_member('25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a2') THEN
        RAISE EXCEPTION 'FAILED (FABLE-LOGIC-01): the wife stopped being a spouse of her family';
    END IF;
    IF public.nafaqah_is_spouse_member('25aa0000-0000-0000-0000-000000000002', '25000000-0000-0000-0000-0000000000a2') THEN
        RAISE EXCEPTION 'FAILED (FABLE-LOGIC-01): the roommate household gained a spouse';
    END IF;
    PERFORM pg_temp.expect('F husband unchanged', public.nafaqah_husband_id('25aa0000-0000-0000-0000-000000000001')::text,
        '25000000-0000-0000-0000-0000000000a1');
    -- The family ledger stays readable (was 22023 before).
    PERFORM public.get_spouse_reimbursement_balance('25aa0000-0000-0000-0000-000000000001',
        '25000000-0000-0000-0000-0000000000a2', '25000000-0000-0000-0000-0000000000a1');
    -- Members list shows the per-household role.
    PERFORM pg_temp.expect('get_household_members(F) shows spouse',
        (SELECT financial_role FROM public.get_household_members('25aa0000-0000-0000-0000-000000000001',
            '25000000-0000-0000-0000-0000000000a1') WHERE user_id = '25000000-0000-0000-0000-0000000000a2'), 'spouse');

    -- Switching back restores the cache from the membership.
    PERFORM pg_temp.as_user('25000000-0000-0000-0000-0000000000a2',
        $q$SELECT public.switch_active_household('25aa0000-0000-0000-0000-000000000001')$q$);
    PERFORM pg_temp.expect('users cache after switching to F',
        (SELECT financial_role FROM public.users WHERE id = '25000000-0000-0000-0000-0000000000a2'), 'spouse');
    RAISE NOTICE 'PASSED (FABLE-LOGIC-01): a wife joining roommates keeps her family role; roommates stay roommates.';
END $$;

-- 3. FABLE-LOGIC-01: a spouse joins the roommates by the static code ---------------
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000c2',
        $q$SELECT public.join_household_by_code('r25flatcode00001')::text$q$);
    IF v_res::jsonb ? 'error' THEN
        RAISE EXCEPTION 'spouse could not join by code: %', v_res;
    END IF;
    PERFORM pg_temp.expect('spouse joining roommates by code is a peer there', public.household_member_financial_role(
        '25aa0000-0000-0000-0000-000000000002', '25000000-0000-0000-0000-0000000000c2'), 'peer');
    PERFORM pg_temp.expect('her family role is untouched', public.household_member_financial_role(
        '25aa0000-0000-0000-0000-000000000003', '25000000-0000-0000-0000-0000000000c2'), 'spouse');
    IF EXISTS (SELECT 1 FROM public.household_memberships
               WHERE household_id = '25aa0000-0000-0000-0000-000000000002' AND financial_role = 'spouse') THEN
        RAISE EXCEPTION 'FAILED (FABLE-LOGIC-01): the flat now has a spouse member (family mode)';
    END IF;
    PERFORM pg_temp.expect('classifying in the flat is refused', pg_temp.state_hint($q$
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
        VALUES ('25aa0000-0000-0000-0000-000000000002', 10, 'X', 'OPEX-MISC', now(), 'manual', 'wife_reimbursable',
                '25000000-0000-0000-0000-0000000000c2')$q$), '23503:');
    RAISE NOTICE 'PASSED (FABLE-LOGIC-01): a spouse joining roommates by code does not make the flat a family.';
END $$;

-- 4. FABLE-DB-01 / DB-03: invites and existing members -----------------------------
DO $$
DECLARE
    v_res text;
BEGIN
    -- Members cannot read invite codes; admins can.
    PERFORM pg_temp.expect('member K sees no invites',
        pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a3', 'SELECT count(*)::text FROM public.household_invites'), '0');
    PERFORM pg_temp.expect('admin H sees the invite',
        pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a1',
            $q$SELECT count(*)::text FROM public.household_invites WHERE invite_code = 'R25WIFE1'$q$), '1');

    -- K (already a member) cannot claim the spouse invite meant for someone else.
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a3',
        $q$SELECT public.claim_household_role_invite('R25WIFE1')::text$q$);
    IF (v_res::jsonb->>'success')::boolean IS TRUE THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-01): an existing member claimed the spouse invite: %', v_res;
    END IF;
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a3',
        $q$SELECT public.join_household_by_code('r25wife1')::text$q$);
    IF NOT (v_res::jsonb ? 'error') THEN
        RAISE EXCEPTION 'VULNERABILITY (FABLE-DB-01): join_household_by_code let a member take the spouse invite: %', v_res;
    END IF;
    PERFORM pg_temp.expect('K is still family_member', public.household_member_financial_role(
        '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a3'), 'family_member');
    PERFORM pg_temp.expect('invite still open',
        (SELECT used_by::text FROM public.household_invites WHERE invite_code = 'R25WIFE1'), NULL);
    -- Service-role writes are bound too.
    PERFORM pg_temp.expect('trigger refuses marking an invite used by a member', pg_temp.state_hint($q$
        UPDATE public.household_invites SET used_by = '25000000-0000-0000-0000-0000000000a3' WHERE invite_code = 'R25WIFE1'$q$), '42501:');

    -- The real invitee claims it; her retry through join_household_by_code is a no-op switch.
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a5',
        $q$SELECT public.claim_household_role_invite('R25WIFE1')::text$q$);
    IF (v_res::jsonb->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'the real invitee could not claim: %', v_res;
    END IF;
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a5',
        $q$SELECT public.join_household_by_code('R25WIFE1')::text$q$);
    IF v_res::jsonb ? 'error' OR (v_res::jsonb->>'id') IS DISTINCT FROM '25aa0000-0000-0000-0000-000000000001' THEN
        RAISE EXCEPTION 'claim-then-join retry (older app flow) failed: %', v_res;
    END IF;
    PERFORM pg_temp.expect('invitee is a spouse of F', public.household_member_financial_role(
        '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a5'), 'spouse');

    -- DB-03: the co-admin and the primary admin re-join by the static code: no demotion, no error.
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a4',
        $q$SELECT public.join_household_by_code('R25FAMILYCODE001')::text$q$);
    IF v_res LIKE 'ERR:%' OR v_res::jsonb ? 'error' THEN
        RAISE EXCEPTION 'co-admin re-join failed: %', v_res;
    END IF;
    PERFORM pg_temp.expect('co-admin keeps admin', public.household_member_role(
        '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a4'), 'admin');
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.join_household_by_code('R25FAMILYCODE001')::text$q$);
    IF v_res LIKE 'ERR:%' OR v_res::jsonb ? 'error' THEN
        RAISE EXCEPTION 'primary admin re-join failed: %', v_res;
    END IF;
    PERFORM pg_temp.expect('primary admin keeps admin', public.household_member_role(
        '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a1'), 'admin');

    -- The users -> memberships sync trigger never downgrades an admin membership.
    UPDATE public.users SET role = 'member' WHERE id = '25000000-0000-0000-0000-0000000000a4';
    PERFORM pg_temp.expect('sync trigger keeps the admin membership', public.household_member_role(
        '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a4'), 'admin');
    UPDATE public.users SET role = 'admin' WHERE id = '25000000-0000-0000-0000-0000000000a4';
    RAISE NOTICE 'PASSED (FABLE-DB-01/03): invites admin-only; members cannot claim; re-joining never demotes.';
END $$;

-- 5. FABLE-LOGIC-04: son-created household, provider changeable, provider leaves ----
DO $$
DECLARE
    v_n uuid;
    v_res text;
BEGIN
    v_res := pg_temp.as_user_val('25000000-0000-0000-0000-0000000000d1',
        $q$SELECT public.create_household_and_claim('R25 Son House')::text$q$);
    v_n := (v_res::jsonb->>'id')::uuid;
    PERFORM pg_temp.expect('son is the default provider (primary admin)',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = v_n), '25000000-0000-0000-0000-0000000000d1');
    PERFORM pg_temp.expect('creator membership is provider', public.household_member_financial_role(v_n,
        '25000000-0000-0000-0000-0000000000d1'), 'provider');

    -- A wife (spouse invite) and the real husband + another member (static code) join.
    INSERT INTO public.household_invites (household_id, invite_code, role, created_by, expires_at)
    VALUES (v_n, 'R25SONW1', 'spouse', '25000000-0000-0000-0000-0000000000d1', now() + interval '1 day');
    PERFORM pg_temp.as_user('25000000-0000-0000-0000-0000000000d2', $q$SELECT public.claim_household_role_invite('R25SONW1')$q$);
    PERFORM pg_temp.as_user('25000000-0000-0000-0000-0000000000d3',
        format('SELECT public.join_household_by_code(%L)', (SELECT invite_code FROM public.households WHERE id = v_n)));
    PERFORM pg_temp.as_user('25000000-0000-0000-0000-0000000000d4',
        format('SELECT public.join_household_by_code(%L)', (SELECT invite_code FROM public.households WHERE id = v_n)));
    PERFORM pg_temp.expect('family joiner by code is family_member (not provider)', public.household_member_financial_role(v_n,
        '25000000-0000-0000-0000-0000000000d3'), 'family_member');
    PERFORM pg_temp.expect('husband defaults to the son (primary admin)', public.nafaqah_husband_id(v_n)::text,
        '25000000-0000-0000-0000-0000000000d1');

    -- Only an admin changes it, only to a non-spouse member.
    PERFORM pg_temp.expect('member cannot set the provider', pg_temp.as_user('25000000-0000-0000-0000-0000000000d3',
        format('SELECT public.set_nafaqah_provider(%L, %L)', v_n, '25000000-0000-0000-0000-0000000000d3')), '42501');
    PERFORM pg_temp.expect('spouse cannot be the provider', pg_temp.as_user('25000000-0000-0000-0000-0000000000d1',
        format('SELECT public.set_nafaqah_provider(%L, %L)', v_n, '25000000-0000-0000-0000-0000000000d2')), '22023');
    PERFORM pg_temp.expect('non-member cannot be the provider', pg_temp.as_user('25000000-0000-0000-0000-0000000000d1',
        format('SELECT public.set_nafaqah_provider(%L, %L)', v_n, '25000000-0000-0000-0000-0000000000a1')), 'P0002');
    PERFORM pg_temp.expect('direct client update refused', pg_temp.as_user('25000000-0000-0000-0000-0000000000d1',
        format('UPDATE public.households SET nafaqah_provider_user_id = %L WHERE id = %L',
               '25000000-0000-0000-0000-0000000000d3', v_n)), '42501');
    PERFORM pg_temp.expect('admin sets the real husband', pg_temp.as_user('25000000-0000-0000-0000-0000000000d1',
        format('SELECT public.set_nafaqah_provider(%L, %L)', v_n, '25000000-0000-0000-0000-0000000000d3')), '00000');
    PERFORM pg_temp.expect('husband is now H2', public.nafaqah_husband_id(v_n)::text, '25000000-0000-0000-0000-0000000000d3');

    -- A classified row while the provider is set; then the provider leaves.
    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('25f00000-0000-0000-0000-0000000000a1', v_n, 40, 'Bakery', 'OPEX-GROCERY', now(), 'manual',
            'wife_reimbursable', '25000000-0000-0000-0000-0000000000d2');
    PERFORM pg_temp.as_user('25000000-0000-0000-0000-0000000000d3', 'SELECT public.leave_household()');
    PERFORM pg_temp.expect('provider cleared when he leaves',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = v_n), NULL);
    PERFORM pg_temp.expect('new classified rows refused without a provider', pg_temp.state_hint(format($q$
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
        VALUES (%L, 10, 'X', 'OPEX-MISC', now(), 'manual', 'wife_personal', '25000000-0000-0000-0000-0000000000d2')$q$, v_n)),
        '23514:no_nafaqah_provider');
    PERFORM pg_temp.expect('existing classified row stays editable', pg_temp.state_hint($q$
        UPDATE public.transactions SET merchant = 'Bakery (edited)' WHERE id = '25f00000-0000-0000-0000-0000000000a1'$q$), '00000:');

    -- transfer_primary_admin fills an unset provider with the new primary admin (non-spouse).
    PERFORM pg_temp.expect('transfer primary admin', pg_temp.as_user('25000000-0000-0000-0000-0000000000d1',
        format('SELECT public.transfer_primary_admin(%L, %L)', v_n, '25000000-0000-0000-0000-0000000000d4')), '00000');
    PERFORM pg_temp.expect('unset provider defaults to the new primary admin',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = v_n), '25000000-0000-0000-0000-0000000000d4');

    -- ... but keeps a provider that is set: F's provider H survives H -> K transfer.
    PERFORM pg_temp.expect('transfer in F', pg_temp.as_user('25000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.transfer_primary_admin('25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a3')$q$), '00000');
    PERFORM pg_temp.expect('F provider unchanged by the transfer',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = '25aa0000-0000-0000-0000-000000000001'),
        '25000000-0000-0000-0000-0000000000a1');
    RAISE NOTICE 'PASSED (FABLE-LOGIC-04): explicit provider, default primary admin, admin-changeable, cleared on leave.';
END $$;

-- 6. FABLE-LOGIC-02: ledger guard (300 advance, 200 repaid) --------------------------
DO $$
DECLARE
    v_bal jsonb;
BEGIN
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('25f00000-0000-0000-0000-000000000001', '25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a2',
            300.00, 'Panda', 'OPEX-GROCERY', '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', '25000000-0000-0000-0000-0000000000a2');
    PERFORM public.record_spouse_reimbursement('25aa0000-0000-0000-0000-000000000001', '25000000-0000-0000-0000-0000000000a2',
        200, 'cash', NULL, '25000000-0000-0000-0000-0000000000a1');

    PERFORM pg_temp.expect('edit 300 -> 100 refused', pg_temp.state_hint($q$
        UPDATE public.transactions SET amount = 100 WHERE id = '25f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    PERFORM pg_temp.expect('delete refused', pg_temp.state_hint($q$
        DELETE FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    PERFORM pg_temp.expect('declassify refused', pg_temp.state_hint($q$
        UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = '25f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    PERFORM pg_temp.expect('reclassify as personal refused', pg_temp.state_hint($q$
        UPDATE public.transactions SET nafaqah_class = 'wife_personal' WHERE id = '25f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    PERFORM pg_temp.expect('changing the spouse refused', pg_temp.state_hint($q$
        UPDATE public.transactions SET nafaqah_spouse_id = '25000000-0000-0000-0000-0000000000a5' WHERE id = '25f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    -- The wife (creator) editing through the API is refused the same way.
    PERFORM pg_temp.expect('wife lowers her advance as a client', pg_temp.as_user('25000000-0000-0000-0000-0000000000a2',
        $q$UPDATE public.transactions SET amount = 100 WHERE id = '25f00000-0000-0000-0000-000000000001'$q$), '22023');

    -- Allowed: lowering to exactly the repaid amount, raising, unrelated edits.
    PERFORM pg_temp.expect('edit 300 -> 200 allowed', pg_temp.state_hint($q$
        UPDATE public.transactions SET amount = 200 WHERE id = '25f00000-0000-0000-0000-000000000001'$q$), '00000:');
    PERFORM pg_temp.expect('edit 200 -> 199.99 refused', pg_temp.state_hint($q$
        UPDATE public.transactions SET amount = 199.99 WHERE id = '25f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    PERFORM pg_temp.expect('raise allowed', pg_temp.state_hint($q$
        UPDATE public.transactions SET amount = 300, merchant = 'Panda Hyper' WHERE id = '25f00000-0000-0000-0000-000000000001'$q$), '00000:');

    -- A second advance can be removed while the first still covers the repayments.
    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('25f00000-0000-0000-0000-000000000002', '25aa0000-0000-0000-0000-000000000001', 50, 'Nahdi', 'OPEX-HEALTH',
            '2026-11-11 12:00+03', 'manual', 'wife_reimbursable', '25000000-0000-0000-0000-0000000000a2');
    PERFORM pg_temp.expect('delete of a covered advance allowed', pg_temp.state_hint($q$
        DELETE FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000002'$q$), '00000:');

    v_bal := public.get_spouse_reimbursement_balance('25aa0000-0000-0000-0000-000000000001',
        '25000000-0000-0000-0000-0000000000a2', '25000000-0000-0000-0000-0000000000a1');
    IF NOT v_bal ? 'overpaid' OR (v_bal->>'outstanding')::numeric <> 100 OR (v_bal->>'overpaid')::numeric <> 0 THEN
        RAISE EXCEPTION 'balance after guarded edits is wrong: %', v_bal;
    END IF;
    RAISE NOTICE 'PASSED (FABLE-LOGIC-02): edits/deletes that would overpay the ledger are refused.';
END $$;

-- 7. FABLE-LOGIC-06: wife_personal never reaches the category budget ---------------
DO $$
DECLARE
    v_spent numeric;
BEGIN
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount)
    VALUES ('25aa0000-0000-0000-0000-000000000001', 'OPEX-SHOPPING', '2026-11-01', '2026-11', 1000, 0);

    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('25f00000-0000-0000-0000-000000000010', '25aa0000-0000-0000-0000-000000000001', 400, 'Abaya', 'OPEX-SHOPPING',
            '2026-11-05 12:00+03', 'manual', 'wife_personal', '25000000-0000-0000-0000-0000000000a2');
    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source)
    VALUES ('25f00000-0000-0000-0000-000000000011', '25aa0000-0000-0000-0000-000000000001', 100, 'Towels', 'OPEX-SHOPPING',
            '2026-11-06 12:00+03', 'manual');

    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '25aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING' AND cycle_key = '2026-11';
    PERFORM pg_temp.expect('wife_personal 400 not in the budget', v_spent::text, '100.00');

    UPDATE public.transactions SET amount = 450 WHERE id = '25f00000-0000-0000-0000-000000000010';
    UPDATE public.transactions SET nafaqah_class = 'wife_personal', nafaqah_spouse_id = '25000000-0000-0000-0000-0000000000a2'
    WHERE id = '25f00000-0000-0000-0000-000000000011';
    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '25aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING' AND cycle_key = '2026-11';
    PERFORM pg_temp.expect('reclassifying to personal moves it out', v_spent::text, '0.00');

    UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = '25f00000-0000-0000-0000-000000000011';
    DELETE FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000010';
    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '25aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING' AND cycle_key = '2026-11';
    PERFORM pg_temp.expect('declassifying moves it back; deleting personal changes nothing', v_spent::text, '100.00');

    PERFORM public.recompute_budget_spent('25aa0000-0000-0000-0000-000000000001', ARRAY['2026-11']);
    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '25aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING' AND cycle_key = '2026-11';
    PERFORM pg_temp.expect('recalculation agrees with the triggers', v_spent::text, '100.00');
    RAISE NOTICE 'PASSED (FABLE-LOGIC-06): wife_personal purchases count against her allowance only.';
END $$;

-- 8. FABLE-LOGIC-05: payday 27 -> 10 re-keys the Nov 5 purchase (as of 15 Nov) -----
DO $$
DECLARE
    v_status jsonb;
    v_spent numeric;
BEGIN
    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id) VALUES
        ('25f00000-0000-0000-0000-000000000020', '25aa0000-0000-0000-0000-000000000004', 70, 'Oct groceries', 'OPEX-GROCERY',
         '2026-10-20 12:00+03', 'manual', NULL, NULL),
        ('25f00000-0000-0000-0000-000000000021', '25aa0000-0000-0000-0000-000000000004', 120, 'Nov 5 groceries', 'OPEX-GROCERY',
         '2026-11-05 12:00+03', 'manual', NULL, NULL),
        ('25f00000-0000-0000-0000-000000000022', '25aa0000-0000-0000-0000-000000000004', 80, 'Nov 20 groceries', 'OPEX-GROCERY',
         '2026-11-20 12:00+03', 'manual', NULL, NULL),
        ('25f00000-0000-0000-0000-000000000023', '25aa0000-0000-0000-0000-000000000004', 250, 'Salon Nov 5', 'OPEX-SHOPPING',
         '2026-11-05 12:00+03', 'manual', 'wife_personal', '25000000-0000-0000-0000-0000000000e2'),
        ('25f00000-0000-0000-0000-000000000024', '25aa0000-0000-0000-0000-000000000004', 60, 'Perfume Nov 12', 'OPEX-SHOPPING',
         '2026-11-12 12:00+03', 'manual', 'wife_personal', '25000000-0000-0000-0000-0000000000e2');
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount)
    VALUES ('25aa0000-0000-0000-0000-000000000004', 'OPEX-GROCERY', '2026-11-01', '2026-11', 500, 0);
    PERFORM public.recompute_budget_spent('25aa0000-0000-0000-0000-000000000004', ARRAY['2026-11']);
    PERFORM public.set_member_allowance('25aa0000-0000-0000-0000-000000000004', '25000000-0000-0000-0000-0000000000e2',
        400, '2026-11', '25000000-0000-0000-0000-0000000000e1');
    PERFORM pg_temp.expect('Nov 5 keyed 2026-11 under payday 27',
        (SELECT cycle_key FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000021'), '2026-11');

    -- Deterministic "as of 15 Nov": the trigger (which uses now()) is bypassed for this household.
    ALTER TABLE public.households DISABLE TRIGGER trg_rekey_cycles_on_payday_change;
    UPDATE public.households SET payday_day = 10 WHERE id = '25aa0000-0000-0000-0000-000000000004';
    ALTER TABLE public.households ENABLE TRIGGER trg_rekey_cycles_on_payday_change;
    PERFORM public.rekey_household_cycles('25aa0000-0000-0000-0000-000000000004', 27, 10, '2026-11-15 12:00+03');

    PERFORM pg_temp.expect('Nov 5 re-keyed to 2026-10 (10 Oct - 9 Nov)',
        (SELECT cycle_key FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000021'), '2026-10');
    PERFORM pg_temp.expect('Nov 20 is 2026-11 (10 Nov - 9 Dec)',
        (SELECT cycle_key FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000022'), '2026-11');
    PERFORM pg_temp.expect('Oct 20 (before the open cycle) untouched',
        (SELECT cycle_key FROM public.transactions WHERE id = '25f00000-0000-0000-0000-000000000020'), '2026-10');

    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '25aa0000-0000-0000-0000-000000000004' AND category_code = 'OPEX-GROCERY' AND cycle_key = '2026-11';
    PERFORM pg_temp.expect('2026-11 grocery budget holds only its own dates', v_spent::text, '80.00');

    v_status := public.get_member_allowance_status('25aa0000-0000-0000-0000-000000000004', '25000000-0000-0000-0000-0000000000e2',
        '2026-11', '25000000-0000-0000-0000-0000000000e1');
    IF (v_status->>'spent')::numeric <> 60 OR (v_status->>'allocated')::numeric <> 400 THEN
        RAISE EXCEPTION 'FAILED (FABLE-LOGIC-05): 2026-11 allowance includes purchases outside its dates: %', v_status;
    END IF;
    RAISE NOTICE 'PASSED (FABLE-LOGIC-05): payday 27 -> 10 re-keys the open cycle (Nov 5 -> 2026-10).';
END $$;

-- 9. FABLE-LOGIC-05: when the open key changes, budgets/allowances follow it -------
-- Payday 27 -> 20 as of 25 Nov: open 2026-11 (27 Oct - 26 Nov) -> 2026-12 (20 Nov - 19 Dec).
DO $$
DECLARE
    v_res jsonb;
BEGIN
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount) VALUES
        ('25aa0000-0000-0000-0000-000000000006', 'OPEX-DINING', '2026-11-01', '2026-11', 300, 0),
        ('25aa0000-0000-0000-0000-000000000006', 'OPEX-GROCERY', '2026-11-01', '2026-11', 900, 0),
        ('25aa0000-0000-0000-0000-000000000006', 'OPEX-GROCERY', '2026-12-01', '2026-12', 950, 0);
    INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source) VALUES
        ('25aa0000-0000-0000-0000-000000000006', 45, 'Dinner Nov 22', 'OPEX-DINING', '2026-11-22 20:00+03', 'manual'),
        ('25aa0000-0000-0000-0000-000000000006', 30, 'Lunch Nov 2', 'OPEX-DINING', '2026-11-02 13:00+03', 'manual');
    PERFORM public.set_member_allowance('25aa0000-0000-0000-0000-000000000006', '25000000-0000-0000-0000-0000000000e5',
        500, '2026-11', '25000000-0000-0000-0000-0000000000e4');

    ALTER TABLE public.households DISABLE TRIGGER trg_rekey_cycles_on_payday_change;
    UPDATE public.households SET payday_day = 20 WHERE id = '25aa0000-0000-0000-0000-000000000006';
    ALTER TABLE public.households ENABLE TRIGGER trg_rekey_cycles_on_payday_change;
    v_res := public.rekey_household_cycles('25aa0000-0000-0000-0000-000000000006', 27, 20, '2026-11-25 12:00+03');
    PERFORM pg_temp.expect('new open key', v_res->>'new_cycle_key', '2026-12');

    PERFORM pg_temp.expect('dining budget moved to 2026-12',
        (SELECT cycle_key || '/' || month::text FROM public.budgets
         WHERE household_id = '25aa0000-0000-0000-0000-000000000006' AND category_code = 'OPEX-DINING'), '2026-12/2026-12-01');
    PERFORM pg_temp.expect('dining 2026-12 spent = Nov 22 only',
        (SELECT spent_amount::text FROM public.budgets
         WHERE household_id = '25aa0000-0000-0000-0000-000000000006' AND category_code = 'OPEX-DINING'), '45.00');
    PERFORM pg_temp.expect('existing 2026-12 grocery row kept, no duplicate',
        (SELECT string_agg(cycle_key || '=' || allocated_amount::text, ',' ORDER BY cycle_key) FROM public.budgets
         WHERE household_id = '25aa0000-0000-0000-0000-000000000006' AND category_code = 'OPEX-GROCERY'),
        '2026-11=900.00,2026-12=950.00');
    PERFORM pg_temp.expect('allowance moved to 2026-12',
        (SELECT string_agg(cycle_key || '=' || amount::text, ',') FROM public.member_allowances
         WHERE household_id = '25aa0000-0000-0000-0000-000000000006'), '2026-12=500.00');
    RAISE NOTICE 'PASSED (FABLE-LOGIC-05): open-cycle budgets and allowances follow the new key without duplicates.';
END $$;

-- 10. FABLE-LOGIC-05: the trigger itself (backend / older app write payday_day) ----
DO $$
DECLARE
    v_changed int;
    v_bad int;
BEGIN
    INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source)
    SELECT '25aa0000-0000-0000-0000-000000000005', 10, 'day ' || d, 'OPEX-MISC', now() + make_interval(days => d), 'manual'
    FROM generate_series(0, 40) d;
    CREATE TEMP TABLE r25_before ON COMMIT DROP AS
        SELECT id, cycle_key FROM public.transactions WHERE household_id = '25aa0000-0000-0000-0000-000000000005';

    -- As the admin through the client grant (older app builds) - the trigger runs with definer rights.
    PERFORM pg_temp.expect('admin updates payday directly', pg_temp.as_user('25000000-0000-0000-0000-0000000000e3',
        $q$UPDATE public.households SET payday_day = 10 WHERE id = '25aa0000-0000-0000-0000-000000000005'$q$), '00000');

    SELECT count(*) INTO v_bad
    FROM public.transactions t
    WHERE t.household_id = '25aa0000-0000-0000-0000-000000000005'
      AND t.cycle_key IS DISTINCT FROM (SELECT c.cycle_key FROM public.get_saudi_cycle_for_timestamp(t.timestamp, 10) c);
    SELECT count(*) INTO v_changed
    FROM public.transactions t JOIN r25_before b ON b.id = t.id
    WHERE t.cycle_key IS DISTINCT FROM b.cycle_key;
    IF v_bad > 0 OR v_changed = 0 THEN
        RAISE EXCEPTION 'FAILED (FABLE-LOGIC-05): payday trigger left % stale key(s) (% re-keyed)', v_bad, v_changed;
    END IF;
    RAISE NOTICE 'PASSED (FABLE-LOGIC-05): a payday_day update re-stamps the open cycle onward (% rows re-keyed).', v_changed;
END $$;

ROLLBACK;
