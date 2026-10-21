-- ============================================================================
-- Test 17 (audit DB-13): RLS evaluation cost and foreign-key index coverage
--
-- Policies call auth.uid() / get_auth_user_household_id() / get_auth_user_role()
-- directly, so Postgres evaluates them per row (transactions_select_household
-- re-parses the JWT claims for every row: ~50 ms for 50k rows). Wrapping them
-- in a scalar sub-select turns them into a single InitPlan (Supabase linter
-- rule auth_rls_initplan). Several FKs (incl. user_id columns hit by the
-- account-deletion cascade) and the invite lockout lookup had no index.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_list text;
BEGIN
    -- 1. Every auth/helper call inside a policy expression must be wrapped in (SELECT ...)
    SELECT string_agg(schemaname || '.' || tablename || ':' || policyname, ', ') INTO v_list
    FROM (
        SELECT schemaname, tablename, policyname,
               coalesce(qual, '') || ' ' || coalesce(with_check, '') AS expr
        FROM pg_policies
        WHERE schemaname IN ('public', 'storage')
    ) p
    WHERE (SELECT count(*) FROM regexp_matches(expr, '(auth\.uid\(\)|get_auth_user_household_id\(\)|get_auth_user_role\(\))', 'g'))
       <> (SELECT count(*) FROM regexp_matches(expr, 'SELECT (auth\.uid\(\)|get_auth_user_household_id\(\)|get_auth_user_role\(\))', 'g'));
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'PERF (DB-13): policies evaluate auth helpers per row (wrap in SELECT): %', v_list;
    END IF;
    RAISE NOTICE 'PASSED: all policy auth/helper calls are InitPlan-wrapped.';

    -- 2. Every foreign key has an index with the FK columns as leading key
    SELECT string_agg(c.conrelid::regclass::text || '.' || c.conname, ', ') INTO v_list
    FROM pg_constraint c
    WHERE c.contype = 'f'
      AND c.connamespace = 'public'::regnamespace
      AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          WHERE i.indrelid = c.conrelid
            AND (i.indkey::int2[])[0:cardinality(c.conkey) - 1] = c.conkey
      );
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'PERF (DB-13): foreign keys without a supporting index: %', v_list;
    END IF;
    RAISE NOTICE 'PASSED: every foreign key has a supporting index.';

    -- 3. Invite lockout lookup (user_id, attempted_at) is indexed
    IF NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = 'public.invite_attempt_log'::regclass
          AND (i.indkey::int2[])[0:1] = ARRAY[
              (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.invite_attempt_log'::regclass AND attname = 'user_id'),
              (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.invite_attempt_log'::regclass AND attname = 'attempted_at')
          ]::int2[]
    ) THEN
        RAISE EXCEPTION 'PERF (DB-13): invite_attempt_log has no (user_id, attempted_at) index';
    END IF;
    RAISE NOTICE 'PASSED: invite lockout lookup is indexed.';
END $$;

-- 4. Behaviour unchanged: a member still sees exactly their household's rows
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('db000000-0000-0000-0000-000000000001', 'db13-a@test.local'),
        ('db000000-0000-0000-0000-000000000002', 'db13-b@test.local');
    INSERT INTO public.households (id, name, invite_code) VALUES
        ('dbaa0000-0000-0000-0000-000000000001', 'DB13 A', 'DB13ACODE0000001'),
        ('dbbb0000-0000-0000-0000-000000000001', 'DB13 B', 'DB13BCODE0000001');
    UPDATE public.users SET household_id = 'dbaa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'db000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'dbbb0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'db000000-0000-0000-0000-000000000002';
    INSERT INTO public.transactions (household_id, amount, category_code, timestamp)
    SELECT 'dbaa0000-0000-0000-0000-000000000001', 1, 'OPEX-GROCERY', now() FROM generate_series(1, 3);
    INSERT INTO public.transactions (household_id, amount, category_code, timestamp)
    SELECT 'dbbb0000-0000-0000-0000-000000000001', 1, 'OPEX-GROCERY', now() FROM generate_series(1, 5);
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "db000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);
DO $$
DECLARE
    v_cnt int;
BEGIN
    SELECT count(*) INTO v_cnt FROM public.transactions
    WHERE household_id IN ('dbaa0000-0000-0000-0000-000000000001', 'dbbb0000-0000-0000-0000-000000000001');
    IF v_cnt <> 3 THEN
        RAISE EXCEPTION 'RLS behaviour changed: expected 3 visible transactions, saw %', v_cnt;
    END IF;
    RAISE NOTICE 'PASSED: wrapped policies keep household isolation.';
END $$;
RESET ROLE;

ROLLBACK;
