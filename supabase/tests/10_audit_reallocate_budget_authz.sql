-- ============================================================================
-- Test 10 (audit DB-03): reallocate_budget authorization & validation
--
-- schema.sql defines reallocate_budget(p_from_id, p_to_id, p_amount) as
-- SECURITY DEFINER with no caller checks and the default EXECUTE grant to
-- PUBLIC, so anon (and any authenticated user) could move allocated budget
-- between any two budget rows of any household, with negative or fractional
-- amounts.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('d3000000-0000-0000-0000-000000000001', 'db03-admin@test.local'),
        ('d3000000-0000-0000-0000-000000000002', 'db03-member@test.local'),
        ('d3000000-0000-0000-0000-000000000003', 'db03-attacker@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('d3aa0000-0000-0000-0000-000000000001', 'DB03 Victim', 'DB03VICTIMCODE01'),
        ('d3bb0000-0000-0000-0000-000000000001', 'DB03 Attacker', 'DB03ATTACKCODE01');

    UPDATE public.users SET household_id = 'd3aa0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd3000000-0000-0000-0000-000000000001';
    UPDATE public.users SET household_id = 'd3aa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'd3000000-0000-0000-0000-000000000002';
    UPDATE public.users SET household_id = 'd3bb0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'd3000000-0000-0000-0000-000000000003';

    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key) VALUES
        ('d3b00000-0000-0000-0000-000000000001', 'd3aa0000-0000-0000-0000-000000000001', '2026-11-01', 'OPEX-GROCERY', 1000, '2026-11'),
        ('d3b00000-0000-0000-0000-000000000002', 'd3aa0000-0000-0000-0000-000000000001', '2026-11-01', 'OPEX-DINING', 500, '2026-11'),
        ('d3b00000-0000-0000-0000-000000000003', 'd3bb0000-0000-0000-0000-000000000001', '2026-11-01', 'OPEX-DINING', 10, '2026-11');
END $$;

-- 1. anon must not be able to execute it at all
DO $$
BEGIN
    IF has_function_privilege('anon', 'public.reallocate_budget(uuid, uuid, numeric)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-03): anon can EXECUTE reallocate_budget';
    END IF;
    RAISE NOTICE 'PASSED: anon cannot execute reallocate_budget.';
END $$;

-- Helper: run a reallocation as a given user and return the SQLSTATE ('00000' on success)
CREATE FUNCTION pg_temp.try_reallocate(p_sub text, p_from uuid, p_to uuid, p_amount numeric)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        PERFORM public.reallocate_budget(p_from, p_to, p_amount);
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    RETURN '00000';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.try_reallocate(text, uuid, uuid, numeric) TO authenticated;

DO $$
DECLARE
    v_state text;
    v_from numeric;
    v_to numeric;
BEGIN
    -- 2. Attacker (admin of another household) cannot move the victim's budget
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000003',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000002', 900);
    IF v_state = '00000' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-03): foreign user reallocated victim budget';
    END IF;

    -- 3. Attacker cannot siphon allocation into their own household's budget row
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000003',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000003', 500);
    IF v_state = '00000' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-03): cross-household reallocation succeeded';
    END IF;

    -- 4. Non-admin member of the household cannot reallocate (budgets are admin-managed)
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000002',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000002', 100);
    IF v_state = '00000' THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-03): non-admin member reallocated budget';
    END IF;

    -- 5. Admin cannot pass negative / zero / sub-halala amounts
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000001',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000002', -100);
    IF v_state = '00000' THEN
        RAISE EXCEPTION 'BUG (DB-03): negative reallocation accepted';
    END IF;
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000001',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000002', 0.005);
    IF v_state = '00000' THEN
        RAISE EXCEPTION 'BUG (DB-03): sub-halala reallocation accepted';
    END IF;

    SELECT allocated_amount INTO v_from FROM public.budgets WHERE id = 'd3b00000-0000-0000-0000-000000000001';
    SELECT allocated_amount INTO v_to FROM public.budgets WHERE id = 'd3b00000-0000-0000-0000-000000000002';
    IF v_from <> 1000 OR v_to <> 500 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-03): budgets changed by rejected calls (% / %)', v_from, v_to;
    END IF;

    -- 6. Admin of the household can reallocate a valid amount
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000001',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000002', 250.50);
    IF v_state <> '00000' THEN
        RAISE EXCEPTION 'Admin reallocation failed with SQLSTATE %', v_state;
    END IF;
    SELECT allocated_amount INTO v_from FROM public.budgets WHERE id = 'd3b00000-0000-0000-0000-000000000001';
    SELECT allocated_amount INTO v_to FROM public.budgets WHERE id = 'd3b00000-0000-0000-0000-000000000002';
    IF v_from <> 749.50 OR v_to <> 750.50 THEN
        RAISE EXCEPTION 'Admin reallocation produced wrong balances (% / %)', v_from, v_to;
    END IF;

    -- 7. Cannot over-draw the source allocation
    v_state := pg_temp.try_reallocate('d3000000-0000-0000-0000-000000000001',
        'd3b00000-0000-0000-0000-000000000001', 'd3b00000-0000-0000-0000-000000000002', 10000);
    IF v_state = '00000' THEN
        RAISE EXCEPTION 'BUG (DB-03): reallocation larger than source allocation accepted';
    END IF;

    RAISE NOTICE 'PASSED: reallocate_budget enforces household admin, same-household rows and amount validation.';
END $$;

-- 8. Service role (ai_service) keeps working without a user JWT
SET ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role": "service_role"}', true);
DO $$
BEGIN
    PERFORM public.reallocate_budget('d3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 0.50);
    RAISE NOTICE 'PASSED: service_role reallocation still allowed.';
END $$;
RESET ROLE;

ROLLBACK;
