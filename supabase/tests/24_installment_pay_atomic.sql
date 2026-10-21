-- ============================================================================
-- Test 24 (independent review FABLE-API-10, docs/review/audit/fable_review.md)
--
--   pay_installment_plan() records one installment payment as a single
--   conditional increment: each call counts exactly once, never beyond
--   installment_count; a paid-up plan is returned unchanged; another
--   household's plan returns nothing; the actor must be a member; only the
--   service role may execute it; SECURITY DEFINER with a pinned search_path.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('f2400000-0000-0000-0000-0000000000a1', 'inst-a@test.local'),
        ('f2400000-0000-0000-0000-0000000000a2', 'inst-b@test.local'),
        ('f2400000-0000-0000-0000-0000000000c1', 'inst-out@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('f24a0000-0000-0000-0000-000000000001', 'Installments A', 'INSTCODEA0000001'),
        ('f24b0000-0000-0000-0000-000000000001', 'Installments B', 'INSTCODEB0000001');

    UPDATE public.users SET household_id = 'f24a0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'f2400000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = 'f24a0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'f2400000-0000-0000-0000-0000000000a2';
    UPDATE public.users SET household_id = 'f24b0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'f2400000-0000-0000-0000-0000000000c1';

    INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count,
                                          monthly_amount, paid_installments)
    VALUES ('f24d0000-0000-0000-0000-000000000001', 'f24a0000-0000-0000-0000-000000000001', 'Jarir',
            300, 3, 100, 1);
END $$;

CREATE FUNCTION pg_temp.as_role(p_role text, p_claims text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', p_claims, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
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
GRANT EXECUTE ON FUNCTION pg_temp.as_role(text, text, text) TO authenticated, anon, service_role;

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

DO $$
DECLARE
    v_paid integer;
    v_status text;
    v_rows integer;
    v_definer boolean;
    v_config text[];
BEGIN
    -- Catalogue: SECURITY DEFINER, pinned search_path, service_role only.
    SELECT p.prosecdef, p.proconfig INTO v_definer, v_config
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'pay_installment_plan';
    IF NOT v_definer OR NOT (v_config @> ARRAY['search_path=public, pg_temp']) THEN
        RAISE EXCEPTION 'pay_installment_plan must be SECURITY DEFINER with a pinned search_path (got %, %)',
            v_definer, v_config;
    END IF;
    IF has_function_privilege('authenticated', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'anon/authenticated must not execute pay_installment_plan';
    END IF;
    PERFORM pg_temp.expect('authenticated member calls the RPC directly',
        pg_temp.as_role('authenticated',
            '{"sub": "f2400000-0000-0000-0000-0000000000a2", "role": "authenticated"}',
            $q$SELECT * FROM public.pay_installment_plan('f24d0000-0000-0000-0000-000000000001',
                'f24a0000-0000-0000-0000-000000000001', 'f2400000-0000-0000-0000-0000000000a2')$q$),
        '42501');

    -- A non-member actor is refused even through the service role.
    PERFORM pg_temp.expect('outsider as actor',
        pg_temp.as_role('service_role', '{"role": "service_role"}',
            $q$SELECT * FROM public.pay_installment_plan('f24d0000-0000-0000-0000-000000000001',
                'f24a0000-0000-0000-0000-000000000001', 'f2400000-0000-0000-0000-0000000000c1')$q$),
        '42501');

    -- Each call counts exactly once: 1 -> 2 -> 3 (COMPLETED) -> 3 (unchanged).
    SELECT paid_installments, status INTO v_paid, v_status
    FROM public.pay_installment_plan('f24d0000-0000-0000-0000-000000000001',
        'f24a0000-0000-0000-0000-000000000001', 'f2400000-0000-0000-0000-0000000000a2');
    PERFORM pg_temp.expect('first payment', v_paid || '/' || v_status, '2/ACTIVE');
    SELECT paid_installments, status INTO v_paid, v_status
    FROM public.pay_installment_plan('f24d0000-0000-0000-0000-000000000001',
        'f24a0000-0000-0000-0000-000000000001', 'f2400000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('last payment', v_paid || '/' || v_status, '3/COMPLETED');
    SELECT paid_installments, status INTO v_paid, v_status
    FROM public.pay_installment_plan('f24d0000-0000-0000-0000-000000000001',
        'f24a0000-0000-0000-0000-000000000001', 'f2400000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('paid-up plan is unchanged', v_paid || '/' || v_status, '3/COMPLETED');
    SELECT paid_installments INTO v_paid FROM public.installment_plans
    WHERE id = 'f24d0000-0000-0000-0000-000000000001';
    PERFORM pg_temp.expect('stored count', v_paid::text, '3');

    -- Another household's plan: no row, nothing changed (B's admin names his own household).
    SELECT count(*) INTO v_rows
    FROM public.pay_installment_plan('f24d0000-0000-0000-0000-000000000001',
        'f24b0000-0000-0000-0000-000000000001', 'f2400000-0000-0000-0000-0000000000c1');
    PERFORM pg_temp.expect('foreign plan', v_rows::text, '0');

    -- Missing arguments are a client error.
    PERFORM pg_temp.expect('null plan id',
        pg_temp.as_role('service_role', '{"role": "service_role"}',
            $q$SELECT * FROM public.pay_installment_plan(NULL, 'f24a0000-0000-0000-0000-000000000001',
                'f2400000-0000-0000-0000-0000000000a1')$q$),
        '22023');

    RAISE NOTICE 'PASSED: pay_installment_plan counts each payment once, never beyond the plan, members only.';
END $$;

ROLLBACK;
