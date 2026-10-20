-- ============================================================================
-- Test 22 (real-stack e2e follow-ups, docs/review/audit/e2e_results.md)
--
--   E2E-04  household_primary_admin_id(uuid), nafaqah_husband_id(uuid) and
--           nafaqah_is_spouse_member(uuid, uuid) are SECURITY DEFINER helpers
--           with no membership check. They must not be callable by clients
--           (they leaked another household's admin / husband id and answered
--           "is X the wife of household H" for any household), while every
--           SECURITY DEFINER function and trigger that uses them keeps working
--           for authenticated callers.
--   E2E-05  cost_control_sub_categories has no household_id. A row is readable
--           only when its parent category is: a global code, or a code of the
--           caller's active household (same rule as cost_control_codes_select).
--           Clients cannot write the table; anon cannot read it.
--
-- Migration: 20261020600000_e2e_helper_rpcs_and_sub_category_visibility.sql
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Fixtures ------------------------------------------------------------------
-- Family household X: husband H (admin, provider), wife W (member, spouse).
-- Roommate household Y: admin P (peer), member Q (peer).
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('f2200000-0000-0000-0000-0000000000a1', 'e2e22-h@test.local'),
        ('f2200000-0000-0000-0000-0000000000a2', 'e2e22-w@test.local'),
        ('f2200000-0000-0000-0000-0000000000b1', 'e2e22-p@test.local'),
        ('f2200000-0000-0000-0000-0000000000b2', 'e2e22-q@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('f22a0000-0000-0000-0000-000000000001', 'E2E22 Family', 'E2E22FAMCODE0001'),
        ('f22b0000-0000-0000-0000-000000000001', 'E2E22 Flat', 'E2E22FLATCODE001');

    UPDATE public.users SET household_id = 'f22a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'f2200000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = 'f22a0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'spouse'
    WHERE id = 'f2200000-0000-0000-0000-0000000000a2';
    UPDATE public.users SET household_id = 'f22b0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'f2200000-0000-0000-0000-0000000000b1';
    UPDATE public.users SET household_id = 'f22b0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'peer'
    WHERE id = 'f2200000-0000-0000-0000-0000000000b2';

    INSERT INTO public.cost_control_codes (household_id, code, category, keywords, is_system) VALUES
        ('f22a0000-0000-0000-0000-000000000001', 'CUSTOM-E2E22X', 'X only', '{}', false),
        ('f22b0000-0000-0000-0000-000000000001', 'CUSTOM-E2E22Y', 'Y only', '{}', false);
    INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar) VALUES
        ('CUSTOM-E2E22X', 'x-sub', 'X private', 'X'),
        ('CUSTOM-E2E22Y', 'y-sub', 'Y private', 'Y');

    -- Fixture sanity (as the owner): the helpers still answer for internal callers.
    IF public.household_primary_admin_id('f22a0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2200000-0000-0000-0000-0000000000a1'::uuid THEN
        RAISE EXCEPTION 'fixture: X has no primary admin';
    END IF;
    IF public.nafaqah_husband_id('f22a0000-0000-0000-0000-000000000001')
       IS DISTINCT FROM 'f2200000-0000-0000-0000-0000000000a1'::uuid THEN
        RAISE EXCEPTION 'fixture: X has no husband';
    END IF;
    IF NOT public.nafaqah_is_spouse_member('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2') THEN
        RAISE EXCEPTION 'fixture: W is not the wife of X';
    END IF;
END $$;

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

-- Runs a scalar count query as a user; NULL when the query itself is refused.
CREATE FUNCTION pg_temp.count_as(p_role text, p_sub text, p_sql text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v bigint;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_role)::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v;
    EXCEPTION WHEN OTHERS THEN
        v := NULL;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.count_as(text, text, text) TO authenticated, anon;

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

-- E2E-04: the helpers are not client-callable ---------------------------------
DO $$
DECLARE
    v_fn text;
BEGIN
    FOREACH v_fn IN ARRAY ARRAY['public.household_primary_admin_id(uuid)', 'public.nafaqah_husband_id(uuid)',
                                'public.nafaqah_is_spouse_member(uuid, uuid)'] LOOP
        IF has_function_privilege('authenticated', v_fn, 'EXECUTE')
           OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY (E2E-04): % is client-callable', v_fn;
        END IF;
        IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'E2E-04: service_role lost EXECUTE on %', v_fn;
        END IF;
    END LOOP;

    -- An outsider (roommate P) probing the family household X.
    PERFORM pg_temp.expect('outsider reads X primary admin',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$SELECT public.household_primary_admin_id('f22a0000-0000-0000-0000-000000000001')$q$), '42501');
    PERFORM pg_temp.expect('outsider reads X husband',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$SELECT public.nafaqah_husband_id('f22a0000-0000-0000-0000-000000000001')$q$), '42501');
    PERFORM pg_temp.expect('outsider probes X wife',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$SELECT public.nafaqah_is_spouse_member('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2')$q$),
        '42501');
    -- Members do not need them either (the app never calls them).
    PERFORM pg_temp.expect('member calls helper',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a2',
            $q$SELECT public.nafaqah_husband_id('f22a0000-0000-0000-0000-000000000001')$q$), '42501');

    RAISE NOTICE 'PASSED: E2E-04 helpers are not client-callable; service_role keeps them.';
END $$;

-- E2E-04: every definer caller keeps working for authenticated users ----------
DO $$
DECLARE
    v_primary boolean;
    v_count bigint;
BEGIN
    -- household_primary_admin_id via get_household_members (members see who is primary).
    v_count := pg_temp.count_as('authenticated', 'f2200000-0000-0000-0000-0000000000a2',
        $q$SELECT count(*) FROM public.get_household_members('f22a0000-0000-0000-0000-000000000001', NULL)
           WHERE is_primary AND user_id = 'f2200000-0000-0000-0000-0000000000a1'$q$);
    IF v_count IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'REGRESSION (E2E-04): get_household_members fails for a member (%)', v_count;
    END IF;

    -- nafaqah_is_spouse_member via the validate_transaction_nafaqah_class trigger: the wife
    -- records a shared expense she paid, as herself through RLS.
    PERFORM pg_temp.expect('wife inserts a wife_reimbursable expense',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a2',
            $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
               VALUES ('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2', 120.50, 'Panda', 'OPEX-GROCERY',
                       now(), 'manual', 'wife_reimbursable', 'f2200000-0000-0000-0000-0000000000a2')$q$),
        '00000');
    -- ...and the trigger still refuses a class naming a non-spouse.
    PERFORM pg_temp.expect('class naming the husband',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a1',
            $q$INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
               VALUES ('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a1', 10, 'Panda', 'OPEX-GROCERY',
                       now(), 'manual', 'wife_reimbursable', 'f2200000-0000-0000-0000-0000000000a1')$q$),
        '23503');

    -- nafaqah_husband_id + nafaqah_is_spouse_member via the Nafaqah RPCs.
    PERFORM pg_temp.expect('husband reads the reimbursement balance',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a1',
            $q$SELECT public.get_spouse_reimbursement_balance('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2', NULL)$q$),
        '00000');
    PERFORM pg_temp.expect('husband sets the wife allowance',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a1',
            $q$SELECT public.set_member_allowance('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2', 250, NULL, NULL)$q$),
        '00000');
    PERFORM pg_temp.expect('wife reads her allowance status',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a2',
            $q$SELECT public.get_member_allowance_status('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2', NULL, NULL)$q$),
        '00000');
    PERFORM pg_temp.expect('husband records a repayment',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000a1',
            $q$SELECT public.record_spouse_reimbursement('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2', 20.50, 'cash', NULL)$q$),
        '00000');
    -- The outsider is still refused by the RPCs' own checks, not by a missing helper.
    IF pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$SELECT public.get_spouse_reimbursement_balance('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a2', NULL)$q$)
       = '00000' THEN
        RAISE EXCEPTION 'VULNERABILITY: outsider read the reimbursement balance';
    END IF;

    -- household_primary_admin_id via protect_primary_admin_membership / revoke_admin: the
    -- primary admin still cannot be demoted, through the RPC as a co-member.
    SELECT (m.user_id = public.household_primary_admin_id(m.household_id)) INTO v_primary
    FROM public.household_memberships m
    WHERE m.household_id = 'f22a0000-0000-0000-0000-000000000001' AND m.user_id = 'f2200000-0000-0000-0000-0000000000a1';
    IF NOT v_primary THEN
        RAISE EXCEPTION 'fixture: H is not primary';
    END IF;
    IF pg_temp.as_user('f2200000-0000-0000-0000-0000000000a1',
            $q$SELECT public.revoke_admin('f22a0000-0000-0000-0000-000000000001', 'f2200000-0000-0000-0000-0000000000a1', NULL)$q$)
       = '00000' THEN
        RAISE EXCEPTION 'REGRESSION: the primary admin was demoted';
    END IF;
    IF (SELECT role FROM public.household_memberships
        WHERE household_id = 'f22a0000-0000-0000-0000-000000000001' AND user_id = 'f2200000-0000-0000-0000-0000000000a1') <> 'admin' THEN
        RAISE EXCEPTION 'REGRESSION: primary admin membership changed';
    END IF;

    RAISE NOTICE 'PASSED: definer RPCs and triggers that use the helpers still work for members.';
END $$;

-- E2E-05: sub-categories follow their parent category's visibility ------------
DO $$
DECLARE
    v bigint;
BEGIN
    -- The wife (household X) sees system and X's own sub-categories, never Y's.
    v := pg_temp.count_as('authenticated', 'f2200000-0000-0000-0000-0000000000a2',
        $q$SELECT count(*) FROM public.cost_control_sub_categories WHERE parent_code = 'CUSTOM-E2E22Y'$q$);
    IF v IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'VULNERABILITY (E2E-05): X member reads Y custom sub-categories (%)', v;
    END IF;
    v := pg_temp.count_as('authenticated', 'f2200000-0000-0000-0000-0000000000a2',
        $q$SELECT count(*) FROM public.cost_control_sub_categories WHERE parent_code = 'CUSTOM-E2E22X'$q$);
    IF v IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'REGRESSION (E2E-05): X member cannot read X custom sub-categories (%)', v;
    END IF;
    v := pg_temp.count_as('authenticated', 'f2200000-0000-0000-0000-0000000000a2',
        $q$SELECT count(*) FROM public.cost_control_sub_categories WHERE parent_code = 'OPEX-DINING'$q$);
    IF v IS NULL OR v < 1 THEN
        RAISE EXCEPTION 'REGRESSION (E2E-05): system sub-categories are hidden (%)', v;
    END IF;
    -- A whole-table read shows exactly the visible rows.
    v := pg_temp.count_as('authenticated', 'f2200000-0000-0000-0000-0000000000b2',
        $q$SELECT count(*) FROM public.cost_control_sub_categories WHERE parent_code LIKE 'CUSTOM-E2E22%'$q$);
    IF v IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'E2E-05: Y member should see only Y custom sub-category (got %)', v;
    END IF;

    -- Clients cannot write definitions (ai_service writes them with the service role).
    PERFORM pg_temp.expect('admin inserts a sub-category directly',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar)
               VALUES ('OPEX-DINING', 'planted', 'Planted', 'Planted')$q$), '42501');
    PERFORM pg_temp.expect('admin renames another household''s sub-category',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$UPDATE public.cost_control_sub_categories SET name_en = 'pwned' WHERE parent_code = 'CUSTOM-E2E22X'$q$), '42501');
    PERFORM pg_temp.expect('admin deletes sub-categories',
        pg_temp.as_user('f2200000-0000-0000-0000-0000000000b1',
            $q$DELETE FROM public.cost_control_sub_categories WHERE parent_code = 'CUSTOM-E2E22Y'$q$), '42501');
    IF has_table_privilege('authenticated', 'public.cost_control_sub_categories', 'INSERT')
       OR has_table_privilege('authenticated', 'public.cost_control_sub_categories', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.cost_control_sub_categories', 'DELETE')
       OR has_table_privilege('authenticated', 'public.cost_control_sub_categories', 'TRUNCATE')
       OR has_table_privilege('anon', 'public.cost_control_sub_categories', 'SELECT') THEN
        RAISE EXCEPTION 'VULNERABILITY (E2E-05): client privileges remain on cost_control_sub_categories';
    END IF;
    IF NOT has_table_privilege('authenticated', 'public.cost_control_sub_categories', 'SELECT') THEN
        RAISE EXCEPTION 'REGRESSION (E2E-05): the app can no longer read sub-categories';
    END IF;
    v := pg_temp.count_as('anon', NULL, $q$SELECT count(*) FROM public.cost_control_sub_categories$q$);
    IF v IS NOT NULL THEN
        RAISE EXCEPTION 'VULNERABILITY (E2E-05): anon reads sub-categories (%)', v;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_policies
               WHERE schemaname = 'public' AND tablename = 'cost_control_sub_categories'
                 AND (qual = 'true' OR cmd <> 'SELECT')) THEN
        RAISE EXCEPTION 'VULNERABILITY (E2E-05): permissive or write policy on cost_control_sub_categories';
    END IF;

    -- The service role (ai_service) still reads and writes every row.
    PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);
    SET LOCAL ROLE service_role;
    SELECT count(*) INTO v FROM public.cost_control_sub_categories WHERE parent_code LIKE 'CUSTOM-E2E22%';
    UPDATE public.cost_control_sub_categories SET name_ar = 'X2' WHERE parent_code = 'CUSTOM-E2E22X';
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    IF v <> 2 THEN
        RAISE EXCEPTION 'REGRESSION (E2E-05): service role sees % of 2 rows', v;
    END IF;

    RAISE NOTICE 'PASSED: E2E-05 sub-categories are visible only with their parent category; clients cannot write them.';
END $$;

ROLLBACK;
