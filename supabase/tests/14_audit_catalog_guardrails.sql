-- ============================================================================
-- Test 14 (audit DB-09, DB-10 + catalog guardrails)
--
-- DB-09: sync_user_household_membership() is SECURITY DEFINER without a pinned
--        search_path (it runs with the invoking session's search_path).
-- DB-10: households_insert_authenticated lets any authenticated client INSERT
--        households rows directly (bypassing create_household_and_claim's
--        5-household quota and server-generated invite code). The UNIQUE
--        violation on a chosen invite_code is also an existence oracle for
--        other households' static join codes that is not rate limited.
-- Guardrails (regressions of SEC-01/02/05/08 and DB-01..04 class bugs):
--   * every public table has RLS enabled;
--   * no public/storage policy targets PUBLIC or anon;
--   * every SECURITY DEFINER function in public pins search_path;
--   * anon can execute no function in public.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(c.relname, ', ') INTO v_list
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'GUARDRAIL: tables without RLS: %', v_list;
    END IF;

    SELECT string_agg(schemaname || '.' || tablename || ':' || policyname, ', ') INTO v_list
    FROM pg_policies
    WHERE schemaname IN ('public', 'storage')
      AND NOT (roles <@ ARRAY['authenticated', 'service_role']::name[]);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'GUARDRAIL: policies granted to PUBLIC/anon: %', v_list;
    END IF;

    SELECT string_agg(p.proname, ', ') INTO v_list
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg WHERE cfg LIKE 'search_path=%');
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'GUARDRAIL (DB-09): SECURITY DEFINER functions without pinned search_path: %', v_list;
    END IF;

    -- Extension members are skipped: live installs `unaccent` into public, its
    -- functions are owned by the platform superuser, and they are not app RPCs.
    SELECT string_agg(p.proname, ', ') INTO v_list
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND NOT EXISTS (
          SELECT 1 FROM pg_depend d
          WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
      );
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'GUARDRAIL: functions executable by anon: %', v_list;
    END IF;

    RAISE NOTICE 'PASSED: RLS on all tables, no PUBLIC/anon policies, definer search_path pinned, nothing anon-executable.';
END $$;

-- DB-10: no direct household creation from clients
INSERT INTO auth.users (id, email) VALUES ('d9000000-0000-0000-0000-000000000001', 'db10-user@test.local');
INSERT INTO public.households (id, name, invite_code) VALUES ('d9aa0000-0000-0000-0000-000000000001', 'DB10 Existing', 'DB10EXISTINGCODE');

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d9000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);
DO $$
DECLARE
    v_state text := 'inserted';
BEGIN
    BEGIN
        INSERT INTO public.households (name, invite_code) VALUES ('Direct insert', 'DB10EXISTINGCODE');
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
    END;
    IF v_state = '23505' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-10): direct INSERT reached the invite_code UNIQUE check (existence oracle)';
    END IF;

    v_state := 'inserted';
    BEGIN
        INSERT INTO public.households (name) VALUES ('Direct insert');
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
    END;
    IF v_state = 'inserted' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-10): authenticated client inserted a household directly';
    END IF;
    RAISE NOTICE 'PASSED: households are created only through create_household_and_claim.';

    -- The RPC path keeps working
    IF (public.create_household_and_claim('DB10 via RPC')->>'id') IS NULL THEN
        RAISE EXCEPTION 'create_household_and_claim failed';
    END IF;
    RAISE NOTICE 'PASSED: create_household_and_claim still creates households.';
END $$;
RESET ROLE;

ROLLBACK;
