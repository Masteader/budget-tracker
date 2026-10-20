-- ============================================================================
-- Test 21 (final backend review, docs/review/audit/final_review_backend.md)
--
--   FR-B-04  users.financial_role decides who is the wife (Nafaqah creditor),
--            who is the husband and whether a household is a family at all
--            (20261020300000 / 20261020400000). Members must not be able to
--            change it on their own row: only the invite RPCs (SECURITY
--            DEFINER) set it. display_name and payday_day stay editable.
--   FR-B-01  The roommate settlement row written by ai_service
--            (supabase_client.record_household_reimbursement) uses only
--            columns that exist on public.transactions, passes every trigger
--            as the service role and never touches a budget. The previous
--            payload (paid_by / notes columns, category OPEX-SETTLEMENT) is
--            rejected by the schema.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('f2100000-0000-0000-0000-0000000000a1', 'rev-a@test.local'),
        ('f2100000-0000-0000-0000-0000000000a2', 'rev-b@test.local'),
        ('f2100000-0000-0000-0000-0000000000b1', 'rev-h@test.local'),
        ('f2100000-0000-0000-0000-0000000000b2', 'rev-w@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('f21a0000-0000-0000-0000-000000000001', 'Review Roommates', 'REVROOMCODE00001'),
        ('f21b0000-0000-0000-0000-000000000001', 'Review Family', 'REVFAMCODE000001');

    UPDATE public.users SET household_id = 'f21a0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'f2100000-0000-0000-0000-0000000000a1';
    UPDATE public.users SET household_id = 'f21a0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'peer'
    WHERE id = 'f2100000-0000-0000-0000-0000000000a2';
    UPDATE public.users SET household_id = 'f21b0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'f2100000-0000-0000-0000-0000000000b1';
    UPDATE public.users SET household_id = 'f21b0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'spouse'
    WHERE id = 'f2100000-0000-0000-0000-0000000000b2';

    INSERT INTO public.budgets (household_id, month, cycle_key, category_code, allocated_amount, spent_amount)
    VALUES ('f21a0000-0000-0000-0000-000000000001', date_trunc('month', now())::date,
            (SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(now(), 27)), 'OPEX-MISC', 500, 0);
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

CREATE FUNCTION pg_temp.as_service(p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);
    EXECUTE 'SET LOCAL ROLE service_role';
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
GRANT EXECUTE ON FUNCTION pg_temp.as_service(text) TO service_role;

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

-- FR-B-04 --------------------------------------------------------------------
DO $$
DECLARE
    v_role text;
BEGIN
    -- A roommate cannot make themselves a "wife" (would turn the household into a family and
    -- let them raise Nafaqah debts against the provider).
    PERFORM pg_temp.expect('roommate sets own financial_role',
        pg_temp.as_user('f2100000-0000-0000-0000-0000000000a2',
            $q$UPDATE public.users SET financial_role = 'spouse' WHERE id = 'f2100000-0000-0000-0000-0000000000a2'$q$),
        '42501');
    -- The wife cannot drop out of her own reimbursement ledger, the husband cannot swap roles.
    PERFORM pg_temp.expect('wife sets own financial_role',
        pg_temp.as_user('f2100000-0000-0000-0000-0000000000b2',
            $q$UPDATE public.users SET financial_role = 'provider' WHERE id = 'f2100000-0000-0000-0000-0000000000b2'$q$),
        '42501');
    PERFORM pg_temp.expect('husband sets own financial_role',
        pg_temp.as_user('f2100000-0000-0000-0000-0000000000b1',
            $q$UPDATE public.users SET financial_role = 'spouse' WHERE id = 'f2100000-0000-0000-0000-0000000000b1'$q$),
        '42501');

    SELECT financial_role INTO v_role FROM public.users WHERE id = 'f2100000-0000-0000-0000-0000000000a2';
    IF v_role IS DISTINCT FROM 'peer' THEN
        RAISE EXCEPTION 'VULNERABILITY (FR-B-04): roommate financial_role is now %', v_role;
    END IF;

    -- Profile fields stay editable on the own row.
    PERFORM pg_temp.expect('own display_name',
        pg_temp.as_user('f2100000-0000-0000-0000-0000000000a2',
            $q$UPDATE public.users SET display_name = 'Renamed' WHERE id = 'f2100000-0000-0000-0000-0000000000a2'$q$),
        '00000');
    PERFORM pg_temp.expect('own payday_day',
        pg_temp.as_user('f2100000-0000-0000-0000-0000000000a2',
            $q$UPDATE public.users SET payday_day = 25 WHERE id = 'f2100000-0000-0000-0000-0000000000a2'$q$),
        '00000');

    IF has_column_privilege('authenticated', 'public.users', 'financial_role', 'UPDATE')
       OR has_column_privilege('anon', 'public.users', 'financial_role', 'UPDATE') THEN
        RAISE EXCEPTION 'VULNERABILITY (FR-B-04): a client role can still UPDATE users.financial_role';
    END IF;

    RAISE NOTICE 'PASSED: users.financial_role is not client-writable; profile fields still are.';
END $$;

-- FR-B-01 --------------------------------------------------------------------
DO $$
DECLARE
    v_spent numeric;
    v_row public.transactions%ROWTYPE;
BEGIN
    -- The payload ai_service sends today (service role, creator = verified caller).
    PERFORM pg_temp.expect('settlement row as written by ai_service',
        pg_temp.as_service($q$
            INSERT INTO public.transactions (
                id, household_id, user_id, amount, currency, merchant, category_code,
                beneficiary_type, beneficiary_id, settlement_target_id, is_settlement, source, raw_sms, timestamp)
            VALUES (
                'f21c0000-0000-0000-0000-000000000001', 'f21a0000-0000-0000-0000-000000000001',
                'f2100000-0000-0000-0000-0000000000a2', '30.00', 'SAR', 'Settlement Reimbursement (STC_PAY)', NULL,
                'individual', 'f2100000-0000-0000-0000-0000000000a1', 'f2100000-0000-0000-0000-0000000000a1', true,
                'manual',
                'Settlement | PaidBy: f2100000-0000-0000-0000-0000000000a2 | Recipient: f2100000-0000-0000-0000-0000000000a1 | Method: STC_PAY',
                now())
        $q$),
        '00000');

    SELECT * INTO v_row FROM public.transactions WHERE id = 'f21c0000-0000-0000-0000-000000000001';
    IF v_row.amount IS DISTINCT FROM 30.00 OR v_row.cycle_key IS NULL OR v_row.is_settlement IS NOT TRUE THEN
        RAISE EXCEPTION 'settlement row stored wrongly: amount %, cycle_key %, is_settlement %',
            v_row.amount, v_row.cycle_key, v_row.is_settlement;
    END IF;

    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = 'f21a0000-0000-0000-0000-000000000001' AND category_code = 'OPEX-MISC';
    IF v_spent <> 0 THEN
        RAISE EXCEPTION 'a settlement was counted as spending (OPEX-MISC spent = %)', v_spent;
    END IF;

    -- The previous payload could never be stored.
    PERFORM pg_temp.expect('old payload: paid_by / notes columns',
        pg_temp.as_service($q$
            INSERT INTO public.transactions (household_id, user_id, amount, merchant, paid_by, notes, timestamp)
            VALUES ('f21a0000-0000-0000-0000-000000000001', 'f2100000-0000-0000-0000-0000000000a2', 30,
                    'Settlement', 'f2100000-0000-0000-0000-0000000000a2', 'x', now())
        $q$),
        '42703');
    PERFORM pg_temp.expect('old payload: OPEX-SETTLEMENT category',
        pg_temp.as_service($q$
            INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, is_settlement, timestamp)
            VALUES ('f21a0000-0000-0000-0000-000000000001', 'f2100000-0000-0000-0000-0000000000a2', 30,
                    'Settlement', 'OPEX-SETTLEMENT', true, now())
        $q$),
        '23503');

    RAISE NOTICE 'PASSED: the roommate settlement row fits the real schema and never counts as spending.';
END $$;

ROLLBACK;
