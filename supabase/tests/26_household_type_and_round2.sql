-- ============================================================================
-- Test 26 (owner decisions D1-D3 and Fable round-2 DB report, migration
-- 20261020900000): household type and round-2 fixes.
--
--   D1            households.household_type ('family' | 'roommates'), chosen in
--                 create_household_and_claim (old {p_name} call = family);
--                 static-code joiners are peer / family_member by type; role
--                 invites that do not fit the type are refused; set_household_type
--                 (admins; family -> roommates refused while a wife / Nafaqah data
--                 exists; roommates -> family makes peers family members).
--   D2            only the wife, the Nafaqah provider or an admin classifies.
--   D3            the wife's ledger in a household is removed when her membership
--                 there ends (leave, remove, account deletion); her expenses become
--                 ordinary (wife_personal enters the category budget).
--   FABLE2-DB-01  provider never re-defaulted on owner succession.
--   FABLE2-DB-02  installment counter CHECK, no client UPDATE of the counter /
--                 status, pay_installment_plan only counts ACTIVE plans.
--   FABLE2-DB-05  settlement rows never reach the category budgets.
--   FABLE2-DB-07  set_member_financial_role (admins, roles per type).
-- Fails before the migration (missing column / functions), passes after.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Helpers ----------------------------------------------------------------------
-- SQLSTATE:HINT of a statement run as an authenticated user ('00000:' on success).
CREATE FUNCTION pg_temp.as_user(p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_state text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN v_state || ':' || COALESCE(v_hint, '');
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN '00000:';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(text, text) TO authenticated;

-- One value of a query run as the user; errors surface as 'ERR:<sqlstate>:<hint>'.
CREATE FUNCTION pg_temp.as_user_val(p_sub text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v text;
    v_state text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        EXECUTE p_sql INTO v;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        v := 'ERR:' || v_state || ':' || COALESCE(v_hint, '');
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user_val(text, text) TO authenticated;

-- SQLSTATE:HINT of a statement run with the owner's (service) rights.
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

-- 1. Catalog (fails before the migration) -------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'households' AND column_name = 'household_type'
                     AND is_nullable = 'NO' AND column_default = '''family''::text') THEN
        RAISE EXCEPTION 'MISSING (D1): households.household_type text NOT NULL DEFAULT ''family''';
    END IF;
    IF to_regprocedure('public.set_household_type(uuid, text, uuid)') IS NULL
       OR to_regprocedure('public.set_member_financial_role(uuid, uuid, text, uuid)') IS NULL
       OR to_regprocedure('public.create_household_and_claim(text, text)') IS NULL THEN
        RAISE EXCEPTION 'MISSING (D1 / FABLE2-DB-07): set_household_type / set_member_financial_role / create_household_and_claim(text, text)';
    END IF;
    IF to_regprocedure('public.create_household_and_claim(text)') IS NOT NULL THEN
        RAISE EXCEPTION 'an overload create_household_and_claim(text) would make PostgREST calls with {p_name} ambiguous';
    END IF;
    IF has_column_privilege('authenticated', 'public.households', 'household_type', 'UPDATE') THEN
        RAISE EXCEPTION 'VULNERABILITY (D1): clients can write households.household_type directly';
    END IF;
    IF has_function_privilege('anon', 'public.set_household_type(uuid, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_member_financial_role(uuid, uuid, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.create_household_and_claim(text, text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.set_household_type(uuid, text, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.set_member_financial_role(uuid, uuid, text, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'public.set_member_financial_role(uuid, uuid, text, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.create_household_and_claim(text, text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'function privileges are wrong (authenticated + service_role only)';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p
               WHERE p.oid IN ('public.set_household_type(uuid, text, uuid)'::regprocedure,
                               'public.set_member_financial_role(uuid, uuid, text, uuid)'::regprocedure)
                 AND (NOT p.prosecdef OR p.proconfig IS NULL
                      OR NOT ('search_path=public, pg_temp' = ANY (p.proconfig)))) THEN
        RAISE EXCEPTION 'admin RPCs must be SECURITY DEFINER with a pinned search_path';
    END IF;
    RAISE NOTICE 'PASSED: household_type column, admin RPCs and privileges.';
END $$;

-- Fixtures -----------------------------------------------------------------------
-- F family: H (primary admin, provider), C (co-admin), K (adult son); W claims the spouse invite.
-- G family: GH (admin), GW (wife, removed later); W also becomes G's second wife.
-- J family: JH (admin), JW (wife who deletes her account).
-- Z family: ZH (owner/provider) + ZC (co-admin);  Y family: YH (owner/provider) + YS (son).
-- O creates the roommates flat X through the RPC; P joins it by code, Q by a peer invite.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('26000000-0000-0000-0000-0000000000a1', 'r26-h@test.local'),
        ('26000000-0000-0000-0000-0000000000a2', 'r26-w@test.local'),
        ('26000000-0000-0000-0000-0000000000a3', 'r26-k@test.local'),
        ('26000000-0000-0000-0000-0000000000a4', 'r26-c@test.local'),
        ('26000000-0000-0000-0000-0000000000b1', 'r26-o@test.local'),
        ('26000000-0000-0000-0000-0000000000b2', 'r26-p@test.local'),
        ('26000000-0000-0000-0000-0000000000b3', 'r26-q@test.local'),
        ('26000000-0000-0000-0000-0000000000b4', 'r26-x@test.local'),
        ('26000000-0000-0000-0000-0000000000c1', 'r26-s@test.local'),
        ('26000000-0000-0000-0000-0000000000c2', 'r26-m@test.local'),
        ('26000000-0000-0000-0000-0000000000d1', 'r26-gh@test.local'),
        ('26000000-0000-0000-0000-0000000000d2', 'r26-gw@test.local'),
        ('26000000-0000-0000-0000-0000000000e1', 'r26-jh@test.local'),
        ('26000000-0000-0000-0000-0000000000e2', 'r26-jw@test.local'),
        ('26000000-0000-0000-0000-0000000000f1', 'r26-zh@test.local'),
        ('26000000-0000-0000-0000-0000000000f2', 'r26-zc@test.local'),
        ('26000000-0000-0000-0000-0000000000f3', 'r26-yh@test.local'),
        ('26000000-0000-0000-0000-0000000000f4', 'r26-ys@test.local');

    INSERT INTO public.households (id, name, invite_code, payday_day) VALUES
        ('26aa0000-0000-0000-0000-000000000001', 'R26 Family', 'R26FAMILYCODE001', 27),
        ('26aa0000-0000-0000-0000-000000000002', 'R26 G Family', 'R26GFAMILYCODE01', 27),
        ('26aa0000-0000-0000-0000-000000000003', 'R26 J Family', 'R26JFAMILYCODE01', 27),
        ('26aa0000-0000-0000-0000-000000000004', 'R26 Z Family', 'R26ZFAMILYCODE01', 27),
        ('26aa0000-0000-0000-0000-000000000005', 'R26 Y Family', 'R26YFAMILYCODE01', 27);

    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = '26000000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'family_member'
    WHERE id = '26000000-0000-0000-0000-0000000000a3';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'family_member'
    WHERE id = '26000000-0000-0000-0000-0000000000a4';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000002', role = 'admin', financial_role = 'provider'
    WHERE id = '26000000-0000-0000-0000-0000000000d1';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000002', role = 'member', financial_role = 'spouse'
    WHERE id = '26000000-0000-0000-0000-0000000000d2';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000003', role = 'admin', financial_role = 'provider'
    WHERE id = '26000000-0000-0000-0000-0000000000e1';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000003', role = 'member', financial_role = 'spouse'
    WHERE id = '26000000-0000-0000-0000-0000000000e2';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000004', role = 'admin', financial_role = 'provider'
    WHERE id = '26000000-0000-0000-0000-0000000000f1';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000004', role = 'admin', financial_role = 'family_member'
    WHERE id = '26000000-0000-0000-0000-0000000000f2';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000005', role = 'admin', financial_role = 'provider'
    WHERE id = '26000000-0000-0000-0000-0000000000f3';
    UPDATE public.users SET household_id = '26aa0000-0000-0000-0000-000000000005', role = 'member', financial_role = 'family_member'
    WHERE id = '26000000-0000-0000-0000-0000000000f4';
    UPDATE public.household_memberships SET created_at = now() - interval '30 days'
    WHERE user_id IN ('26000000-0000-0000-0000-0000000000a1', '26000000-0000-0000-0000-0000000000f1', '26000000-0000-0000-0000-0000000000f3');

    INSERT INTO public.household_invites (household_id, invite_code, role, created_by, expires_at) VALUES
        ('26aa0000-0000-0000-0000-000000000001', 'R26WIFE1', 'spouse', '26000000-0000-0000-0000-0000000000a1', now() + interval '7 days'),
        ('26aa0000-0000-0000-0000-000000000001', 'R26FPEER', 'peer', '26000000-0000-0000-0000-0000000000a1', now() + interval '7 days'),
        ('26aa0000-0000-0000-0000-000000000002', 'R26GWIF2', 'spouse', '26000000-0000-0000-0000-0000000000d1', now() + interval '7 days');
END $$;

-- 2. D1: creation with a type, joins by code and by invite -----------------------------
DO $$
DECLARE
    v_res text;
    v_x uuid;
    v_s uuid;
    v_code text;
BEGIN
    -- The released app's call shape ({p_name} only) creates a family household.
    v_res := pg_temp.as_user_val('26000000-0000-0000-0000-0000000000c1',
        $q$SELECT public.create_household_and_claim(p_name => 'R26 Son House')::text$q$);
    v_s := (v_res::jsonb->>'id')::uuid;
    PERFORM pg_temp.expect('old call shape -> family', v_res::jsonb->>'household_type', 'family');
    PERFORM pg_temp.expect('family creator is provider', public.household_member_financial_role(v_s,
        '26000000-0000-0000-0000-0000000000c1'), 'provider');
    PERFORM pg_temp.expect('family creator is the default Nafaqah provider',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = v_s), '26000000-0000-0000-0000-0000000000c1');
    PERFORM pg_temp.expect('positional single-argument call still resolves',
        (pg_temp.as_user_val('26000000-0000-0000-0000-0000000000c2',
            $q$SELECT public.create_household_and_claim('R26 Tmp')->>'household_type'$q$)), 'family');
    PERFORM pg_temp.expect('unknown type refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000c2',
        $q$SELECT public.create_household_and_claim('R26 Bad', 'commune')$q$), '22023:invalid_household_type');

    -- A roommates flat: creator is a peer, no Nafaqah provider.
    v_res := pg_temp.as_user_val('26000000-0000-0000-0000-0000000000b1',
        $q$SELECT public.create_household_and_claim('R26 Flat', 'roommates')::text$q$);
    v_x := (v_res::jsonb->>'id')::uuid;
    PERFORM pg_temp.expect('flat type', v_res::jsonb->>'household_type', 'roommates');
    PERFORM pg_temp.expect('flat creator is a peer', public.household_member_financial_role(v_x,
        '26000000-0000-0000-0000-0000000000b1'), 'peer');
    PERFORM pg_temp.expect('flat has no provider', v_res::jsonb->>'nafaqah_provider_user_id', NULL);
    PERFORM pg_temp.expect('users cache of the flat creator',
        (SELECT financial_role FROM public.users WHERE id = '26000000-0000-0000-0000-0000000000b1'), 'peer');

    -- Static code: peer in the flat, family_member in a family.
    v_code := (SELECT invite_code FROM public.households WHERE id = v_x);
    PERFORM pg_temp.expect('P joins the flat by code', pg_temp.as_user('26000000-0000-0000-0000-0000000000b2',
        format('SELECT public.join_household_by_code(%L)', v_code)), '00000:');
    PERFORM pg_temp.expect('static-code joiner of roommates is a peer', public.household_member_financial_role(v_x,
        '26000000-0000-0000-0000-0000000000b2'), 'peer');
    PERFORM pg_temp.expect('M joins the son house by code', pg_temp.as_user('26000000-0000-0000-0000-0000000000c2',
        format('SELECT public.join_household_by_code(%L)', (SELECT invite_code FROM public.households WHERE id = v_s))), '00000:');
    PERFORM pg_temp.expect('static-code joiner of a family is a family member', public.household_member_financial_role(v_s,
        '26000000-0000-0000-0000-0000000000c2'), 'family_member');

    -- Role invites must fit the type.
    INSERT INTO public.household_invites (household_id, invite_code, role, created_by, expires_at) VALUES
        (v_x, 'R26XPEER', 'peer', '26000000-0000-0000-0000-0000000000b1', now() + interval '7 days'),
        (v_x, 'R26XWIFE', 'spouse', '26000000-0000-0000-0000-0000000000b1', now() + interval '7 days'),
        (v_x, 'R26XPROV', 'provider', '26000000-0000-0000-0000-0000000000b1', now() + interval '7 days');
    PERFORM pg_temp.expect('peer invite in roommates works', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000b3',
        $q$SELECT public.claim_household_role_invite('R26XPEER')->>'role'$q$), 'peer');
    PERFORM pg_temp.expect('spouse invite in roommates refused', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000b4',
        $q$SELECT public.claim_household_role_invite('R26XWIFE')->>'code'$q$), 'invite_role_mismatch');
    PERFORM pg_temp.expect('provider invite in roommates refused (old join path)', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000b4',
        $q$SELECT public.join_household_by_code('R26XPROV')->>'code'$q$), 'invite_role_mismatch');
    PERFORM pg_temp.expect('peer invite in a family refused', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000b4',
        $q$SELECT public.claim_household_role_invite('R26FPEER')->>'code'$q$), 'invite_role_mismatch');
    PERFORM pg_temp.expect('refused invites stay open',
        (SELECT count(*)::text FROM public.household_invites WHERE invite_code IN ('R26XWIFE', 'R26XPROV', 'R26FPEER') AND used_by IS NULL), '3');
    PERFORM pg_temp.expect('refused invitee joined nothing',
        (SELECT count(*)::text FROM public.household_memberships WHERE user_id = '26000000-0000-0000-0000-0000000000b4'), '0');

    -- W becomes the wife of F (and, below, the second wife of G).
    PERFORM pg_temp.expect('W claims the spouse invite of F', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000a2',
        $q$SELECT public.claim_household_role_invite('R26WIFE1')->>'role'$q$), 'spouse');

    -- Membership roles are bound to the type (service-role writes too).
    PERFORM pg_temp.expect('spouse membership in roommates refused', pg_temp.state_hint(format(
        $q$UPDATE public.household_memberships SET financial_role = 'spouse' WHERE household_id = %L AND user_id = %L$q$,
        v_x, '26000000-0000-0000-0000-0000000000b2')), '23514:financial_role_not_allowed');
    PERFORM pg_temp.expect('peer membership in a family refused', pg_temp.state_hint(
        $q$UPDATE public.household_memberships SET financial_role = 'peer'
           WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND user_id = '26000000-0000-0000-0000-0000000000a3'$q$),
        '23514:financial_role_not_allowed');
    PERFORM pg_temp.expect('provider in roommates refused (service role)', pg_temp.state_hint(format(
        $q$UPDATE public.households SET nafaqah_provider_user_id = %L WHERE id = %L$q$, '26000000-0000-0000-0000-0000000000b1', v_x)),
        '23514:not_family_household');
    PERFORM pg_temp.expect('set_nafaqah_provider in roommates refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000b1',
        format('SELECT public.set_nafaqah_provider(%L, %L)', v_x, '26000000-0000-0000-0000-0000000000b2')), '22023:not_family_household');
    PERFORM pg_temp.expect('admin cannot write household_type directly', pg_temp.as_user('26000000-0000-0000-0000-0000000000b1',
        format($q$UPDATE public.households SET household_type = 'family' WHERE id = %L$q$, v_x)), '42501:');

    -- A sync-trigger insert carrying a stale per-user role gets the type's default.
    UPDATE public.users SET household_id = v_x, financial_role = 'provider' WHERE id = '26000000-0000-0000-0000-0000000000b4';
    PERFORM pg_temp.expect('stale cached role coerced to peer', public.household_member_financial_role(v_x,
        '26000000-0000-0000-0000-0000000000b4'), 'peer');
    DELETE FROM public.household_memberships WHERE user_id = '26000000-0000-0000-0000-0000000000b4';
    UPDATE public.users SET household_id = NULL WHERE id = '26000000-0000-0000-0000-0000000000b4';
    RAISE NOTICE 'PASSED (D1): creation with a type (old call = family), joins and invites follow the type.';
END $$;

-- 3. D1: set_household_type ------------------------------------------------------------
DO $$
DECLARE
    v_s uuid := (SELECT id FROM public.households WHERE name = 'R26 Son House');
    v_res text;
BEGIN
    PERFORM pg_temp.expect('member cannot change the type', pg_temp.as_user('26000000-0000-0000-0000-0000000000c2',
        format($q$SELECT public.set_household_type(%L, 'roommates')$q$, v_s)), '42501:');
    PERFORM pg_temp.expect('actor spoofing refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000c2',
        format($q$SELECT public.set_household_type(%L, 'roommates', %L)$q$, v_s, '26000000-0000-0000-0000-0000000000c1')), '42501:');
    PERFORM pg_temp.expect('outsider admin refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        format($q$SELECT public.set_household_type(%L, 'roommates')$q$, v_s)), '42501:');
    PERFORM pg_temp.expect('invalid value refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000c1',
        format($q$SELECT public.set_household_type(%L, 'hostel')$q$, v_s)), '22023:invalid_household_type');

    -- F has a wife: family -> roommates is refused.
    PERFORM pg_temp.expect('family with a wife cannot become roommates', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.set_household_type('26aa0000-0000-0000-0000-000000000001', 'roommates')$q$), '22023:type_change_blocked');
    PERFORM pg_temp.expect('F still family', (SELECT household_type FROM public.households
        WHERE id = '26aa0000-0000-0000-0000-000000000001'), 'family');

    -- The son house (no wife, no ledger) -> roommates: everyone a peer, provider cleared.
    v_res := pg_temp.as_user_val('26000000-0000-0000-0000-0000000000c1',
        format($q$SELECT public.set_household_type(%L, 'roommates')::text$q$, v_s));
    PERFORM pg_temp.expect('switched to roommates', v_res::jsonb->>'household_type', 'roommates');
    PERFORM pg_temp.expect('previous type', v_res::jsonb->>'previous_household_type', 'family');
    PERFORM pg_temp.expect('all peers', (SELECT string_agg(DISTINCT financial_role, ',') FROM public.household_memberships
        WHERE household_id = v_s), 'peer');
    PERFORM pg_temp.expect('provider cleared', (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = v_s), NULL);
    PERFORM pg_temp.expect('creator cache follows', (SELECT financial_role FROM public.users
        WHERE id = '26000000-0000-0000-0000-0000000000c1'), 'peer');

    -- ... and back to family: peers become family members, the primary admin the provider.
    v_res := pg_temp.as_user_val('26000000-0000-0000-0000-0000000000c1',
        format($q$SELECT public.set_household_type(%L, 'family')::text$q$, v_s));
    PERFORM pg_temp.expect('back to family', v_res::jsonb->>'household_type', 'family');
    PERFORM pg_temp.expect('primary admin is provider again', public.household_member_financial_role(v_s,
        '26000000-0000-0000-0000-0000000000c1'), 'provider');
    PERFORM pg_temp.expect('other peer became family_member', public.household_member_financial_role(v_s,
        '26000000-0000-0000-0000-0000000000c2'), 'family_member');
    PERFORM pg_temp.expect('default provider = primary admin', v_res::jsonb->>'nafaqah_provider_user_id',
        '26000000-0000-0000-0000-0000000000c1');
    PERFORM pg_temp.expect('same type is a no-op', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000c1',
        format($q$SELECT public.set_household_type(%L, 'family')->>'changed'$q$, v_s)), 'false');
    RAISE NOTICE 'PASSED (D1): set_household_type (admins; blocked with a wife; peers <-> family members).';
END $$;

-- 4. FABLE2-DB-07: set_member_financial_role -------------------------------------------
DO $$
DECLARE
    v_x uuid := (SELECT id FROM public.households WHERE name = 'R26 Flat');
BEGIN
    PERFORM pg_temp.expect('member cannot set roles', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3', 'dependent')$q$),
        '42501:');
    PERFORM pg_temp.expect('actor spoofing refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3', 'dependent',
             '26000000-0000-0000-0000-0000000000a1')$q$), '42501:');
    PERFORM pg_temp.expect('admin sets the son dependent', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000a4',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3', 'dependent')->>'previous_financial_role'$q$),
        'family_member');
    PERFORM pg_temp.expect('son is dependent', public.household_member_financial_role('26aa0000-0000-0000-0000-000000000001',
        '26000000-0000-0000-0000-0000000000a3'), 'dependent');
    PERFORM pg_temp.expect('peer refused in a family', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3', 'peer')$q$),
        '22023:financial_role_not_allowed');
    PERFORM pg_temp.expect('provider label not set here', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3', 'provider')$q$),
        '22023:financial_role_not_allowed');
    PERFORM pg_temp.expect('the provider cannot become a spouse', pg_temp.as_user('26000000-0000-0000-0000-0000000000a4',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a1', 'spouse')$q$),
        '22023:provider_is_spouse');
    PERFORM pg_temp.expect('non-member target', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000b1', 'dependent')$q$),
        'P0002:');
    PERFORM pg_temp.expect('roommates: spouse refused', pg_temp.as_user('26000000-0000-0000-0000-0000000000b1',
        format($q$SELECT public.set_member_financial_role(%L, %L, 'spouse')$q$, v_x, '26000000-0000-0000-0000-0000000000b2')),
        '22023:financial_role_not_allowed');
    PERFORM pg_temp.expect('roommates: peer ok', pg_temp.as_user('26000000-0000-0000-0000-0000000000b1',
        format($q$SELECT public.set_member_financial_role(%L, %L, 'peer')$q$, v_x, '26000000-0000-0000-0000-0000000000b2')), '00000:');
    -- Service role (API) with an explicit actor.
    PERFORM pg_temp.expect('service role with admin actor', public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001',
        '26000000-0000-0000-0000-0000000000a3', 'family_member', '26000000-0000-0000-0000-0000000000a1')->>'financial_role', 'family_member');
    RAISE NOTICE 'PASSED (FABLE2-DB-07): set_member_financial_role is admin-only and type-bound.';
END $$;

-- 5. D2: who may classify -------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('son cannot record a wife advance', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
           VALUES ('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3', 900, 'Son claims advance', 'OPEX-MISC',
                   '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', '26000000-0000-0000-0000-0000000000a2')$q$),
        '42501:nafaqah_class_not_allowed');
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source)
    VALUES ('26f00000-0000-0000-0000-0000000000d1', '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3',
            40, 'Son groceries', 'OPEX-MISC', '2026-11-10 12:00+03', 'manual');
    PERFORM pg_temp.expect('son cannot classify his own row', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$UPDATE public.transactions SET nafaqah_class = 'wife_personal', nafaqah_spouse_id = '26000000-0000-0000-0000-0000000000a2'
           WHERE id = '26f00000-0000-0000-0000-0000000000d1'$q$), '42501:nafaqah_class_not_allowed');
    PERFORM pg_temp.expect('the wife records her own advance', pg_temp.as_user('26000000-0000-0000-0000-0000000000a2',
        $q$INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
           VALUES ('26f00000-0000-0000-0000-0000000000d2', '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a2', 25,
                   'Wife bakery', 'OPEX-MISC', '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', '26000000-0000-0000-0000-0000000000a2')$q$),
        '00000:');
    PERFORM pg_temp.expect('the provider classifies (admin edit of the son row)', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$UPDATE public.transactions SET nafaqah_class = 'wife_reimbursable', nafaqah_spouse_id = '26000000-0000-0000-0000-0000000000a2'
           WHERE id = '26f00000-0000-0000-0000-0000000000d1'$q$), '00000:');
    PERFORM pg_temp.expect('a co-admin declassifies', pg_temp.as_user('26000000-0000-0000-0000-0000000000a4',
        $q$UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = '26f00000-0000-0000-0000-0000000000d1'$q$),
        '00000:');
    -- Clearing only the spouse (which drops the class) is a change too.
    UPDATE public.transactions SET user_id = '26000000-0000-0000-0000-0000000000a3' WHERE id = '26f00000-0000-0000-0000-0000000000d2';
    PERFORM pg_temp.expect('son cannot drop the wife from a row he owns', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$UPDATE public.transactions SET nafaqah_spouse_id = NULL WHERE id = '26f00000-0000-0000-0000-0000000000d2'$q$),
        '42501:nafaqah_class_not_allowed');
    PERFORM pg_temp.expect('son still edits the amount of his row', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$UPDATE public.transactions SET amount = 30 WHERE id = '26f00000-0000-0000-0000-0000000000d2'$q$), '00000:');
    -- Service role (API) passes; the API applies the same rule.
    PERFORM pg_temp.expect('service role classifies', pg_temp.state_hint(
        $q$UPDATE public.transactions SET nafaqah_class = 'wife_personal', nafaqah_spouse_id = '26000000-0000-0000-0000-0000000000a2'
           WHERE id = '26f00000-0000-0000-0000-0000000000d1'$q$), '00000:');
    RAISE NOTICE 'PASSED (D2): only the wife, the provider or an admin classifies from a client.';
END $$;

-- 6. D3: the wife's ledger leaves with her membership (leave / remove / account deletion)
DO $$
DECLARE
    v_spent numeric;
BEGIN
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount) VALUES
        ('26aa0000-0000-0000-0000-000000000001', 'OPEX-SHOPPING', '2026-11-01', '2026-11', 1000, 0),
        ('26aa0000-0000-0000-0000-000000000001', 'OPEX-GROCERY', '2026-11-01', '2026-11', 1000, 0);
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id) VALUES
        ('26f00000-0000-0000-0000-000000000001', '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a2',
         300, 'Panda', 'OPEX-GROCERY', '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', '26000000-0000-0000-0000-0000000000a2'),
        ('26f00000-0000-0000-0000-000000000002', '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a2',
         100, 'Abaya', 'OPEX-SHOPPING', '2026-11-10 12:00+03', 'manual', 'wife_personal', '26000000-0000-0000-0000-0000000000a2');
    PERFORM public.record_spouse_reimbursement('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a2',
        200, 'cash', NULL, '26000000-0000-0000-0000-0000000000a1');
    PERFORM public.set_member_allowance('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a2',
        500, '2026-11', '26000000-0000-0000-0000-0000000000a1');
    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING';
    PERFORM pg_temp.expect('wife_personal not in the budget while classified', v_spent::text, '0.00');
    -- The guard still protects the ledger while she is a member.
    PERFORM pg_temp.expect('husband cannot shrink a repaid advance', pg_temp.state_hint(
        $q$UPDATE public.transactions SET amount = 50 WHERE id = '26f00000-0000-0000-0000-000000000001'$q$),
        '22023:ledger_would_be_overpaid');
    -- A wife with ledger data is not re-roled (her ledger would be orphaned).
    PERFORM pg_temp.expect('wife with a ledger keeps her role', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.set_member_financial_role('26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a2', 'family_member')$q$),
        '22023:spouse_has_ledger');
    -- Classified rows alone (no spouse check needed) also block family -> roommates.
    PERFORM pg_temp.expect('Nafaqah data blocks the switch to roommates', pg_temp.as_user('26000000-0000-0000-0000-0000000000a1',
        $q$SELECT public.set_household_type('26aa0000-0000-0000-0000-000000000001', 'roommates')$q$), '22023:type_change_blocked');

    -- W is also the second wife of G, with an allowance there.
    PERFORM pg_temp.expect('W claims G spouse invite', pg_temp.as_user_val('26000000-0000-0000-0000-0000000000a2',
        $q$SELECT public.claim_household_role_invite('R26GWIF2')->>'role'$q$), 'spouse');
    PERFORM public.set_member_allowance('26aa0000-0000-0000-0000-000000000002', '26000000-0000-0000-0000-0000000000a2',
        300, '2026-11', '26000000-0000-0000-0000-0000000000d1');

    -- (a) leave_household of F (switch back first: leave acts on the active household).
    PERFORM pg_temp.as_user('26000000-0000-0000-0000-0000000000a2',
        $q$SELECT public.switch_active_household('26aa0000-0000-0000-0000-000000000001')$q$);
    PERFORM pg_temp.expect('W leaves F', pg_temp.as_user('26000000-0000-0000-0000-0000000000a2',
        'SELECT public.leave_household()'), '00000:');
    PERFORM pg_temp.expect('her F rows are ordinary expenses', (SELECT count(*)::text FROM public.transactions
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001'
          AND (nafaqah_class IS NOT NULL OR nafaqah_spouse_id IS NOT NULL)), '0');
    PERFORM pg_temp.expect('the rows themselves remain', (SELECT count(*)::text FROM public.transactions
        WHERE id IN ('26f00000-0000-0000-0000-000000000001', '26f00000-0000-0000-0000-000000000002')), '2');
    PERFORM pg_temp.expect('her F repayments are gone', (SELECT count(*)::text FROM public.spouse_reimbursements
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001'), '0');
    PERFORM pg_temp.expect('her F allowance is gone', (SELECT count(*)::text FROM public.member_allowances
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001'), '0');
    PERFORM pg_temp.expect('her G ledger is untouched', (SELECT count(*)::text FROM public.member_allowances
        WHERE household_id = '26aa0000-0000-0000-0000-000000000002' AND member_user_id = '26000000-0000-0000-0000-0000000000a2'), '1');
    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING';
    PERFORM pg_temp.expect('the former wife_personal amount now counts in the category budget', v_spent::text, '100.00');
    PERFORM public.recompute_budget_spent('26aa0000-0000-0000-0000-000000000001', ARRAY['2026-11']);
    PERFORM pg_temp.expect('recompute agrees (shopping)', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-SHOPPING'), '100.00');
    PERFORM pg_temp.expect('recompute agrees (grocery)', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-GROCERY'), '300.00');

    -- (b) remove_member: GH removes GW from G.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('26f00000-0000-0000-0000-000000000011', '26aa0000-0000-0000-0000-000000000002', '26000000-0000-0000-0000-0000000000d2',
            80, 'Nahdi', 'OPEX-HEALTH', '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', '26000000-0000-0000-0000-0000000000d2');
    PERFORM public.record_spouse_reimbursement('26aa0000-0000-0000-0000-000000000002', '26000000-0000-0000-0000-0000000000d2',
        80, 'cash', NULL, '26000000-0000-0000-0000-0000000000d1');
    PERFORM pg_temp.expect('GH removes GW', pg_temp.as_user('26000000-0000-0000-0000-0000000000d1',
        $q$SELECT public.remove_member('26000000-0000-0000-0000-0000000000d2')$q$), '00000:');
    PERFORM pg_temp.expect('GW advance declassified', (SELECT COALESCE(nafaqah_class, 'none') FROM public.transactions
        WHERE id = '26f00000-0000-0000-0000-000000000011'), 'none');
    PERFORM pg_temp.expect('GW repayments gone', (SELECT count(*)::text FROM public.spouse_reimbursements
        WHERE household_id = '26aa0000-0000-0000-0000-000000000002' AND wife_user_id = '26000000-0000-0000-0000-0000000000d2'), '0');

    -- (c) account deletion: JW deletes her account.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('26f00000-0000-0000-0000-000000000021', '26aa0000-0000-0000-0000-000000000003', '26000000-0000-0000-0000-0000000000e2',
            50, 'Tamimi', 'OPEX-GROCERY', '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', '26000000-0000-0000-0000-0000000000e2');
    PERFORM public.record_spouse_reimbursement('26aa0000-0000-0000-0000-000000000003', '26000000-0000-0000-0000-0000000000e2',
        20, 'cash', NULL, '26000000-0000-0000-0000-0000000000e1');
    DELETE FROM auth.users WHERE id = '26000000-0000-0000-0000-0000000000e2';
    PERFORM pg_temp.expect('JW advance declassified after account deletion', (SELECT COALESCE(nafaqah_class, 'none') FROM public.transactions
        WHERE id = '26f00000-0000-0000-0000-000000000021'), 'none');
    PERFORM pg_temp.expect('JW repayments gone', (SELECT count(*)::text FROM public.spouse_reimbursements
        WHERE household_id = '26aa0000-0000-0000-0000-000000000003'), '0');
    RAISE NOTICE 'PASSED (D3): leave / remove / account deletion remove the wife''s ledger in that household only.';
END $$;

-- 7. FABLE2-DB-01: the provider is never re-defaulted on owner succession ------------
DO $$
BEGIN
    -- Z: the owner/provider deletes his account; the co-admin becomes primary admin.
    DELETE FROM auth.users WHERE id = '26000000-0000-0000-0000-0000000000f1';
    PERFORM pg_temp.expect('Z new primary admin', (SELECT owner_user_id::text FROM public.households
        WHERE id = '26aa0000-0000-0000-0000-000000000004'), '26000000-0000-0000-0000-0000000000f2');
    PERFORM pg_temp.expect('Z provider stays NULL', (SELECT nafaqah_provider_user_id::text FROM public.households
        WHERE id = '26aa0000-0000-0000-0000-000000000004'), NULL);
    -- Y: the only other member (a son) is promoted by the handover; still no provider.
    DELETE FROM auth.users WHERE id = '26000000-0000-0000-0000-0000000000f3';
    PERFORM pg_temp.expect('Y new primary admin', (SELECT owner_user_id::text FROM public.households
        WHERE id = '26aa0000-0000-0000-0000-000000000005'), '26000000-0000-0000-0000-0000000000f4');
    PERFORM pg_temp.expect('Y provider stays NULL', (SELECT nafaqah_provider_user_id::text FROM public.households
        WHERE id = '26aa0000-0000-0000-0000-000000000005'), NULL);
    -- An admin chooses one explicitly.
    PERFORM pg_temp.expect('admin sets the provider', pg_temp.as_user('26000000-0000-0000-0000-0000000000f4',
        $q$SELECT public.set_nafaqah_provider('26aa0000-0000-0000-0000-000000000005', '26000000-0000-0000-0000-0000000000f4')$q$), '00000:');
    RAISE NOTICE 'PASSED (FABLE2-DB-01): provider cleared on every membership end, never re-defaulted by succession.';
END $$;

-- 8. FABLE2-DB-02: installment plans ----------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'installment_plans_paid_installments_range'
                   AND conrelid = 'public.installment_plans'::regclass AND convalidated) THEN
        RAISE EXCEPTION 'MISSING (FABLE2-DB-02): validated CHECK on paid_installments';
    END IF;
    IF has_column_privilege('authenticated', 'public.installment_plans', 'paid_installments', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.installment_plans', 'status', 'UPDATE')
       OR NOT has_column_privilege('authenticated', 'public.installment_plans', 'notes', 'UPDATE') THEN
        RAISE EXCEPTION 'installment_plans column privileges are wrong';
    END IF;

    PERFORM pg_temp.expect('paid beyond the count refused', pg_temp.state_hint(
        $q$INSERT INTO public.installment_plans (household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments)
           VALUES ('26aa0000-0000-0000-0000-000000000001', 'Jarir', 400, 4, 100, 5)$q$), '23514:');
    INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments) VALUES
        ('26e00000-0000-0000-0000-000000000001', '26aa0000-0000-0000-0000-000000000001', 'Jarir', 400, 4, 100, 3),
        ('26e00000-0000-0000-0000-000000000002', '26aa0000-0000-0000-0000-000000000001', 'Extra', 200, 2, 100, 1);
    UPDATE public.installment_plans SET status = 'CANCELLED' WHERE id = '26e00000-0000-0000-0000-000000000002';

    PERFORM pg_temp.expect('member cannot bump the counter', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$UPDATE public.installment_plans SET paid_installments = 4, status = 'COMPLETED' WHERE id = '26e00000-0000-0000-0000-000000000001'$q$),
        '42501:');
    PERFORM pg_temp.expect('member edits notes', pg_temp.as_user('26000000-0000-0000-0000-0000000000a3',
        $q$UPDATE public.installment_plans SET notes = 'x' WHERE id = '26e00000-0000-0000-0000-000000000001'$q$), '00000:');

    PERFORM pg_temp.expect('active plan counts',
        (SELECT paid_installments || '/' || status FROM public.pay_installment_plan('26e00000-0000-0000-0000-000000000001',
            '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3')), '4/COMPLETED');
    PERFORM pg_temp.expect('completed plan returned unchanged',
        (SELECT paid_installments || '/' || status FROM public.pay_installment_plan('26e00000-0000-0000-0000-000000000001',
            '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3')), '4/COMPLETED');
    PERFORM pg_temp.expect('cancelled plan refused', pg_temp.state_hint(
        $q$SELECT * FROM public.pay_installment_plan('26e00000-0000-0000-0000-000000000002',
             '26aa0000-0000-0000-0000-000000000001', '26000000-0000-0000-0000-0000000000a3')$q$), '22023:plan_not_active');
    PERFORM pg_temp.expect('cancelled plan unchanged', (SELECT paid_installments::text FROM public.installment_plans
        WHERE id = '26e00000-0000-0000-0000-000000000002'), '1');
    RAISE NOTICE 'PASSED (FABLE2-DB-02): installment counter bounded, not client-writable, ACTIVE plans only.';
END $$;

-- 9. FABLE2-DB-05: settlements are not category spending ----------------------------
DO $$
BEGIN
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount)
    VALUES ('26aa0000-0000-0000-0000-000000000001', 'OPEX-DINING', '2026-11-01', '2026-11', 500, 0);
    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, is_settlement) VALUES
        ('26f00000-0000-0000-0000-000000000031', '26aa0000-0000-0000-0000-000000000001', 150, 'Settlement', 'OPEX-DINING',
         '2026-11-10 12:00+03', 'manual', true),
        ('26f00000-0000-0000-0000-000000000032', '26aa0000-0000-0000-0000-000000000001', 60, 'Dinner', 'OPEX-DINING',
         '2026-11-10 12:00+03', 'manual', false);
    PERFORM pg_temp.expect('insert: only the dinner counts', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-DINING'), '60.00');
    UPDATE public.transactions SET amount = 175 WHERE id = '26f00000-0000-0000-0000-000000000031';
    PERFORM pg_temp.expect('update of a settlement changes nothing', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-DINING'), '60.00');
    UPDATE public.transactions SET is_settlement = true WHERE id = '26f00000-0000-0000-0000-000000000032';
    PERFORM pg_temp.expect('turning a row into a settlement moves it out', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-DINING'), '0.00');
    UPDATE public.transactions SET is_settlement = false WHERE id = '26f00000-0000-0000-0000-000000000032';
    DELETE FROM public.transactions WHERE id = '26f00000-0000-0000-0000-000000000031';
    PERFORM pg_temp.expect('delete of a settlement changes nothing', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-DINING'), '60.00');
    PERFORM public.recompute_budget_spent('26aa0000-0000-0000-0000-000000000001', ARRAY['2026-11']);
    PERFORM pg_temp.expect('recompute agrees', (SELECT spent_amount::text FROM public.budgets
        WHERE household_id = '26aa0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-DINING'), '60.00');
    RAISE NOTICE 'PASSED (FABLE2-DB-05): budget triggers skip settlement rows, like the recompute.';
END $$;

ROLLBACK;
