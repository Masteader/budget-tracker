-- ============================================================================
-- Test 27 (product review R4 + R10, migration 20261021000000)
--
--   A. Eight new system categories with system sub-categories (en/ar names,
--      keywords >= 3 chars), visible to every household through RLS; the old
--      OPEX-UTILITIES/housing_rent row is untouched and a new housing_rent
--      exists under OPEX-HOUSING; no household setting / budget is created;
--      no top-level keyword of a new code overlaps a keyword of the ten seeded
--      codes (so no existing merchant changes category).
--   B. installment_plans.frequency (monthly | biweekly, default monthly) and
--      the derived next_due_at; pay_installment_plan advances it by 14 days /
--      1 month from the start_date anchor and keeps the ACTIVE-only rule and
--      its grants; clients cannot write frequency / next_due_at.
-- Fails before the migration (columns / categories missing).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

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

CREATE FUNCTION pg_temp.as_role(p_role text, p_claims text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_out text;
BEGIN
    PERFORM set_config('request.jwt.claims', p_claims, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_out;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR ' || SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN coalesce(v_out, 'NULL');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_role(text, text, text) TO authenticated, anon, service_role;

-- A. Taxonomy -------------------------------------------------------------------------
DO $$
DECLARE
    v_n int;
    v_bad text;
BEGIN
    SELECT string_agg(code || '=' || category, ',' ORDER BY code) INTO v_bad
    FROM public.cost_control_codes
    WHERE household_id IS NULL AND is_system AND NOT is_flexible
      AND code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                   'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    PERFORM pg_temp.expect('new system categories', v_bad,
        'OPEX-CHARITY=Charity & Zakat,OPEX-DOMESTIC-HELP=Domestic Help,OPEX-EDUCATION=School Costs,'
        'OPEX-FAMILY-SUPPORT=Family Support,OPEX-HOUSING=Housing & Rent,OPEX-INSURANCE=Insurance,'
        'OPEX-REMITTANCE=Remittances Abroad,OPEX-TRANSPORT=Car & Transport');

    SELECT string_agg(parent_code || ':' || n, ',' ORDER BY parent_code) INTO v_bad
    FROM (SELECT parent_code, count(*) AS n FROM public.cost_control_sub_categories
          WHERE parent_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                                'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')
            AND name_en <> '' AND name_ar <> '' AND cardinality(keywords) >= 2
          GROUP BY parent_code) s;
    PERFORM pg_temp.expect('sub-categories per new parent', v_bad,
        'OPEX-CHARITY:2,OPEX-DOMESTIC-HELP:3,OPEX-EDUCATION:4,OPEX-FAMILY-SUPPORT:2,OPEX-HOUSING:3,'
        'OPEX-INSURANCE:3,OPEX-REMITTANCE:2,OPEX-TRANSPORT:4');

    -- Every keyword of the new definitions is at least 3 characters (the matcher ignores shorter ones).
    SELECT count(*) INTO v_n FROM (
        SELECT k FROM public.cost_control_codes c, unnest(c.keywords) k
        WHERE c.household_id IS NULL AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP',
              'OPEX-FAMILY-SUPPORT', 'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')
        UNION ALL
        SELECT k FROM public.cost_control_sub_categories s, unnest(s.keywords) k
        WHERE s.parent_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
              'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')) x
    WHERE char_length(btrim(k)) < 3 OR k <> lower(k);
    PERFORM pg_temp.expect('short or upper-case keywords', v_n::text, '0');

    -- Arabic and English keywords on every new code.
    SELECT count(*) INTO v_n FROM public.cost_control_codes c
    WHERE c.household_id IS NULL AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP',
          'OPEX-FAMILY-SUPPORT', 'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')
      AND EXISTS (SELECT 1 FROM unnest(c.keywords) k WHERE k ~ '[a-z]')
      AND EXISTS (SELECT 1 FROM unnest(c.keywords) k WHERE k ~ '[؀-ۿ]');
    PERFORM pg_temp.expect('codes with Arabic and English keywords', v_n::text, '8');

    -- No top-level keyword of a new code overlaps a keyword of the ten seeded codes, in the
    -- matcher's terms (supabase_client.match_category: keywords < 4 chars match as whole
    -- words, longer ones as substrings in either direction).
    SELECT string_agg(DISTINCT n.k || '~' || o.k || '(' || o.code || ')', ', ') INTO v_bad
    FROM (SELECT lower(btrim(k)) AS k FROM public.cost_control_codes c, unnest(c.keywords) k
          WHERE c.household_id IS NULL AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP',
                'OPEX-FAMILY-SUPPORT', 'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')) n,
         (SELECT c.code, lower(btrim(k)) AS k FROM public.cost_control_codes c, unnest(c.keywords) k
          WHERE c.household_id IS NULL AND c.code IN ('OPEX-GROCERY', 'OPEX-DINING', 'OPEX-FUEL', 'OPEX-UTILITIES',
                'OPEX-SHOPPING', 'OPEX-ENTERTAINMENT', 'OPEX-HEALTH', 'CAPEX-EDUCATION', 'OPEX-GOV', 'OPEX-MISC')) o
    WHERE n.k = o.k
       OR (char_length(o.k) < 4 AND n.k ~ ('(^|[^[:alnum:]_])' || regexp_replace(o.k, '([^[:alnum:]_ ])', '\\\1', 'g') || '($|[^[:alnum:]_])'))
       OR (char_length(n.k) < 4 AND o.k ~ ('(^|[^[:alnum:]_])' || regexp_replace(n.k, '([^[:alnum:]_ ])', '\\\1', 'g') || '($|[^[:alnum:]_])'))
       OR (char_length(o.k) >= 4 AND char_length(n.k) >= 4 AND (strpos(n.k, o.k) > 0 OR strpos(o.k, n.k) > 0));
    PERFORM pg_temp.expect('keyword overlaps with seeded codes', v_bad, NULL);

    -- housing_rent: the old row is untouched, a new one lives under OPEX-HOUSING.
    SELECT string_agg(parent_code || '/' || name_en || '/' || name_ar, ',' ORDER BY parent_code) INTO v_bad
    FROM public.cost_control_sub_categories WHERE sub_code = 'housing_rent';
    PERFORM pg_temp.expect('housing_rent rows', v_bad,
        'OPEX-HOUSING/Housing Rent/إيجار السكن,OPEX-UTILITIES/Housing Rent/إيجار السكن');

    -- The migration creates no per-household state.
    SELECT count(*) INTO v_n FROM public.household_category_settings
    WHERE category_code LIKE 'OPEX-%' AND category_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP',
          'OPEX-FAMILY-SUPPORT', 'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    PERFORM pg_temp.expect('household settings for the new codes', v_n::text, '0');
    SELECT count(*) INTO v_n FROM public.budgets
    WHERE category_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP',
          'OPEX-FAMILY-SUPPORT', 'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    PERFORM pg_temp.expect('budgets for the new codes', v_n::text, '0');
END $$;

-- Fixture: one household with an admin.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('f2700000-0000-0000-0000-0000000000a1', 'tax-a@test.local');
    INSERT INTO public.households (id, name, invite_code) VALUES
        ('f27a0000-0000-0000-0000-000000000001', 'Taxonomy A', 'TAXCODEA00000001');
    UPDATE public.users SET household_id = 'f27a0000-0000-0000-0000-000000000001', role = 'admin'
    WHERE id = 'f2700000-0000-0000-0000-0000000000a1';
END $$;

DO $$
DECLARE
    c_admin constant text := '{"sub": "f2700000-0000-0000-0000-0000000000a1", "role": "authenticated"}';
BEGIN
    -- Visible through RLS to a household member, sub-categories included.
    PERFORM pg_temp.expect('member sees the new codes',
        pg_temp.as_role('authenticated', c_admin,
            $q$SELECT count(*)::text FROM public.cost_control_codes
               WHERE code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                              'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')$q$), '8');
    PERFORM pg_temp.expect('member sees the new sub-categories',
        pg_temp.as_role('authenticated', c_admin,
            $q$SELECT count(*)::text FROM public.cost_control_sub_categories
               WHERE parent_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                                     'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')$q$), '23');
    -- System rows stay read-only for clients.
    PERFORM pg_temp.expect('client cannot rewrite a system code',
        pg_temp.as_role('authenticated', c_admin,
            $q$WITH u AS (UPDATE public.cost_control_codes SET category = 'x' WHERE code = 'OPEX-HOUSING' RETURNING 1)
               SELECT count(*)::text FROM u$q$), '0');

    -- A transaction can use a new category and sub-category.
    INSERT INTO public.transactions (household_id, merchant, amount, category_code, sub_category, source, timestamp)
    VALUES ('f27a0000-0000-0000-0000-000000000001', 'Ejar', 3000, 'OPEX-HOUSING', 'housing_rent', 'manual',
            '2026-10-05 10:00:00+03');
END $$;

-- B. BNPL schedule --------------------------------------------------------------------
DO $$
DECLARE
    v text;
    v_paid int;
    v_status text;
    v_due date;
BEGIN
    -- Column shape.
    SELECT data_type || '/' || is_nullable || '/' || column_default INTO v
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'installment_plans' AND column_name = 'frequency';
    PERFORM pg_temp.expect('frequency column', v, 'text/NO/''monthly''::text');
    SELECT data_type || '/' || is_nullable INTO v
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'installment_plans' AND column_name = 'next_due_at';
    PERFORM pg_temp.expect('next_due_at column', v, 'date/YES');

    -- Default monthly; next_due_at derived even when an insert names another value.
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, next_due_at)
    VALUES ('f27d0000-0000-0000-0000-000000000001', 'f27a0000-0000-0000-0000-000000000001', 'Bank TV', 'Bank',
            1200, 3, 400, 1, '2026-01-31', '2030-01-01');
    SELECT frequency || '/' || next_due_at INTO v FROM public.installment_plans
    WHERE id = 'f27d0000-0000-0000-0000-000000000001';
    PERFORM pg_temp.expect('monthly default, derived next due (end-of-month clamp)', v, 'monthly/2026-02-28');

    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, frequency)
    VALUES ('f27d0000-0000-0000-0000-000000000002', 'f27a0000-0000-0000-0000-000000000001', 'Noon', 'Tabby',
            400, 4, 100, 1, '2026-10-01', 'biweekly');
    SELECT next_due_at::text INTO v FROM public.installment_plans WHERE id = 'f27d0000-0000-0000-0000-000000000002';
    PERFORM pg_temp.expect('biweekly next due', v, '2026-10-15');

    -- CHECK on frequency.
    BEGIN
        UPDATE public.installment_plans SET frequency = 'weekly' WHERE id = 'f27d0000-0000-0000-0000-000000000002';
        RAISE EXCEPTION 'frequency weekly was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- Biweekly payments: 2026-10-15 -> 10-29 -> 11-12 -> NULL (COMPLETED).
    SELECT paid_installments, status, next_due_at INTO v_paid, v_status, v_due
    FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000002',
        'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('biweekly payment 2', v_paid || '/' || v_status || '/' || v_due, '2/ACTIVE/2026-10-29');
    SELECT paid_installments, status, next_due_at INTO v_paid, v_status, v_due
    FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000002',
        'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('biweekly payment 3', v_paid || '/' || v_status || '/' || v_due, '3/ACTIVE/2026-11-12');
    SELECT paid_installments, status, coalesce(next_due_at::text, 'NULL') INTO v_paid, v_status, v
    FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000002',
        'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('biweekly payment 4', v_paid || '/' || v_status || '/' || v, '4/COMPLETED/NULL');
    SELECT paid_installments, status, coalesce(next_due_at::text, 'NULL') INTO v_paid, v_status, v
    FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000002',
        'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('paid-up plan unchanged', v_paid || '/' || v_status || '/' || v, '4/COMPLETED/NULL');

    -- Monthly payments anchored on start_date: 31 Jan -> 28 Feb -> 31 Mar (no drift) -> NULL.
    SELECT next_due_at::text INTO v
    FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000001',
        'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('monthly payment 2', v, '2026-03-31');
    SELECT coalesce(next_due_at::text, 'NULL') || '/' || status INTO v
    FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000001',
        'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1');
    PERFORM pg_temp.expect('monthly payment 3', v, 'NULL/COMPLETED');

    -- ACTIVE-only rule (20261020900000) kept: a CANCELLED plan takes no payment.
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, status, frequency)
    VALUES ('f27d0000-0000-0000-0000-000000000003', 'f27a0000-0000-0000-0000-000000000001', 'Shein', 'Tamara',
            200, 4, 50, 1, '2026-10-01', 'CANCELLED', 'biweekly');
    SELECT coalesce(next_due_at::text, 'NULL') INTO v FROM public.installment_plans
    WHERE id = 'f27d0000-0000-0000-0000-000000000003';
    PERFORM pg_temp.expect('cancelled plan has no next due', v, 'NULL');
    PERFORM pg_temp.expect('cancelled plan payment',
        pg_temp.as_role('service_role', '{"role": "service_role"}',
            $q$SELECT paid_installments::text FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000003',
                'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1')$q$),
        'ERR 22023');

    -- A schedule change recomputes next_due_at.
    UPDATE public.installment_plans SET status = 'ACTIVE', start_date = '2026-11-01'
    WHERE id = 'f27d0000-0000-0000-0000-000000000003';
    SELECT next_due_at::text INTO v FROM public.installment_plans WHERE id = 'f27d0000-0000-0000-0000-000000000003';
    PERFORM pg_temp.expect('rescheduled plan', v, '2026-11-15');

    -- Grants: service_role only on the RPC; clients cannot write frequency / next_due_at.
    IF has_function_privilege('authenticated', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'pay_installment_plan grants changed';
    END IF;
    PERFORM pg_temp.expect('client UPDATE of next_due_at',
        pg_temp.as_role('authenticated', '{"sub": "f2700000-0000-0000-0000-0000000000a1", "role": "authenticated"}',
            $q$WITH u AS (UPDATE public.installment_plans SET next_due_at = '2030-01-01'
                          WHERE id = 'f27d0000-0000-0000-0000-000000000003' RETURNING 1)
               SELECT count(*)::text FROM u$q$), 'ERR 42501');
    PERFORM pg_temp.expect('client UPDATE of frequency',
        pg_temp.as_role('authenticated', '{"sub": "f2700000-0000-0000-0000-0000000000a1", "role": "authenticated"}',
            $q$WITH u AS (UPDATE public.installment_plans SET frequency = 'monthly'
                          WHERE id = 'f27d0000-0000-0000-0000-000000000003' RETURNING 1)
               SELECT count(*)::text FROM u$q$), 'ERR 42501');
    PERFORM pg_temp.expect('client calls the RPC',
        pg_temp.as_role('authenticated', '{"sub": "f2700000-0000-0000-0000-0000000000a1", "role": "authenticated"}',
            $q$SELECT paid_installments::text FROM public.pay_installment_plan('f27d0000-0000-0000-0000-000000000003',
                'f27a0000-0000-0000-0000-000000000001', 'f2700000-0000-0000-0000-0000000000a1')$q$),
        'ERR 42501');
    -- The helper is a pure function clients may use; the trigger function is internal.
    IF has_function_privilege('anon', 'public.installment_next_due_at(date, text, integer, integer, text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.installment_plans_schedule()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.installment_plans_schedule()', 'EXECUTE') THEN
        RAISE EXCEPTION 'schedule function grants are wrong';
    END IF;

    RAISE NOTICE 'PASSED: Saudi taxonomy present and isolated; BNPL frequency / next_due_at derived and advanced by pay_installment_plan.';
END $$;

ROLLBACK;
