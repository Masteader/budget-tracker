-- ============================================================================
-- Test 18 (UI-24 owner decision): Islamic family Nafaqah in the database
--
-- Rules (see .agents/rules/02-saudi-fintech-and-islamic-compliance.md §3):
--   1. Shared family expenses are the husband's Nafaqah: never split 50/50.
--   2. Wife pays from her own money for something shared (household / children)
--      -> transaction classified 'wife_reimbursable' -> the husband owes her;
--      reimbursements (partial or full) reduce the debt, never below zero.
--   3. A personal purchase for the wife -> 'wife_personal' -> charged to her
--      personal allowance (member_allowances, per salary cycle_key); overspend
--      shows as negative remaining and is not blocked.
--   4. Husband-paid shared expenses carry no class and create no debt.
-- Integrity: classification must name a spouse member of the transaction's
-- household; allowance amounts are set only by the husband or a household
-- admin other than the wife herself; reimbursements go only through the RPC,
-- which rejects overpayment; money is numeric(14,2) with positive amounts.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Fixtures ------------------------------------------------------------------
-- Family household F: husband H (admin, provider), wife W (member, spouse),
-- adult child K (member, family_member).
-- Other family household G: admin O (provider) - must never reach F.
-- Roommate household R: P1 (admin, peer), P2 (member, peer).
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        ('e1000000-0000-0000-0000-00000000000a', 'naf-husband@test.local'),
        ('e1000000-0000-0000-0000-00000000000b', 'naf-wife@test.local'),
        ('e1000000-0000-0000-0000-00000000000c', 'naf-child@test.local'),
        ('e1000000-0000-0000-0000-00000000000d', 'naf-outsider@test.local'),
        ('e1000000-0000-0000-0000-0000000000e1', 'naf-peer1@test.local'),
        ('e1000000-0000-0000-0000-0000000000e2', 'naf-peer2@test.local');

    INSERT INTO public.households (id, name, invite_code) VALUES
        ('e1aa0000-0000-0000-0000-000000000001', 'Nafaqah Family', 'NAFFAMILYCODE001'),
        ('e1bb0000-0000-0000-0000-000000000001', 'Other Family', 'NAFOTHERCODE0001'),
        ('e1cc0000-0000-0000-0000-000000000001', 'Roommates', 'NAFROOMCODE00001');
    -- Roommate household (household_type, migration 20261020900000).
    UPDATE public.households SET household_type = 'roommates' WHERE id = 'e1cc0000-0000-0000-0000-000000000001';

    UPDATE public.users SET household_id = 'e1aa0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'e1000000-0000-0000-0000-00000000000a';
    UPDATE public.users SET household_id = 'e1aa0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'spouse'
    WHERE id = 'e1000000-0000-0000-0000-00000000000b';
    UPDATE public.users SET household_id = 'e1aa0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'family_member'
    WHERE id = 'e1000000-0000-0000-0000-00000000000c';
    UPDATE public.users SET household_id = 'e1bb0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'provider'
    WHERE id = 'e1000000-0000-0000-0000-00000000000d';
    UPDATE public.users SET household_id = 'e1cc0000-0000-0000-0000-000000000001', role = 'admin', financial_role = 'peer'
    WHERE id = 'e1000000-0000-0000-0000-0000000000e1';
    UPDATE public.users SET household_id = 'e1cc0000-0000-0000-0000-000000000001', role = 'member', financial_role = 'peer'
    WHERE id = 'e1000000-0000-0000-0000-0000000000e2';
END $$;

-- 1. Catalog: new objects exist, RLS on, no direct client writes, anon locked out
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'nafaqah_class') THEN
        RAISE EXCEPTION 'MISSING: transactions.nafaqah_class';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'nafaqah_spouse_id') THEN
        RAISE EXCEPTION 'MISSING: transactions.nafaqah_spouse_id';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.member_allowances'::regclass) THEN
        RAISE EXCEPTION 'member_allowances has RLS disabled';
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.spouse_reimbursements'::regclass) THEN
        RAISE EXCEPTION 'spouse_reimbursements has RLS disabled';
    END IF;
    IF (SELECT format_type(atttypid, atttypmod) FROM pg_attribute
        WHERE attrelid = 'public.spouse_reimbursements'::regclass AND attname = 'amount') <> 'numeric(14,2)' THEN
        RAISE EXCEPTION 'spouse_reimbursements.amount must be numeric(14,2)';
    END IF;
    IF (SELECT format_type(atttypid, atttypmod) FROM pg_attribute
        WHERE attrelid = 'public.member_allowances'::regclass AND attname = 'amount') <> 'numeric(14,2)' THEN
        RAISE EXCEPTION 'member_allowances.amount must be numeric(14,2)';
    END IF;
    IF has_table_privilege('authenticated', 'public.spouse_reimbursements', 'INSERT')
       OR has_table_privilege('authenticated', 'public.spouse_reimbursements', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.spouse_reimbursements', 'DELETE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can write spouse_reimbursements directly';
    END IF;
    IF has_table_privilege('authenticated', 'public.member_allowances', 'INSERT')
       OR has_table_privilege('authenticated', 'public.member_allowances', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.member_allowances', 'DELETE') THEN
        RAISE EXCEPTION 'VULNERABILITY: clients can write member_allowances directly';
    END IF;
    IF has_table_privilege('anon', 'public.spouse_reimbursements', 'SELECT')
       OR has_table_privilege('anon', 'public.member_allowances', 'SELECT') THEN
        RAISE EXCEPTION 'VULNERABILITY: anon can read Nafaqah ledgers';
    END IF;
    IF has_function_privilege('anon', 'public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.set_member_allowance(uuid, uuid, numeric, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_member_allowance_status(uuid, uuid, text, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_spouse_reimbursement_balance(uuid, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY: anon can execute Nafaqah RPCs';
    END IF;
    RAISE NOTICE 'PASSED: Nafaqah catalog objects exist with RLS, numeric(14,2) money and RPC-only writes.';
END $$;

-- Helper: run SQL as a given authenticated user, return SQLSTATE ('00000' on success)
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
        RETURN SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    RETURN '00000';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(text, text) TO authenticated;

-- 2. Classification integrity (trigger binds service-role writes too)
DO $$
DECLARE
    v_state text;
BEGIN
    -- valid: wife-paid shared expense in the family household
    INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
    VALUES ('e1f00000-0000-0000-0000-000000000001', 'e1aa0000-0000-0000-0000-000000000001', 300.00, 'Panda', 'OPEX-GROCERY',
            '2026-11-10 12:00+03', 'manual', 'wife_reimbursable', 'e1000000-0000-0000-0000-00000000000b');

    -- the husband is not a spouse: rejected
    v_state := 'ok';
    BEGIN
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
        VALUES ('e1aa0000-0000-0000-0000-000000000001', 10, 'X', 'OPEX-MISC', now(), 'manual', 'wife_reimbursable', 'e1000000-0000-0000-0000-00000000000a');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'BUG: non-spouse accepted as nafaqah_spouse_id'; END IF;

    -- the wife of household F cannot be attached to a transaction of household G
    v_state := 'ok';
    BEGIN
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
        VALUES ('e1bb0000-0000-0000-0000-000000000001', 10, 'X', 'OPEX-MISC', now(), 'manual', 'wife_personal', 'e1000000-0000-0000-0000-00000000000b');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'VULNERABILITY: cross-household spouse attached to a transaction'; END IF;

    -- roommate households have no spouse: a peer can never be a Nafaqah creditor
    v_state := 'ok';
    BEGIN
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
        VALUES ('e1cc0000-0000-0000-0000-000000000001', 10, 'X', 'OPEX-MISC', now(), 'manual', 'wife_reimbursable', 'e1000000-0000-0000-0000-0000000000e2');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'BUG: roommate classified as wife'; END IF;

    -- class without spouse and spouse without class are both rejected
    v_state := 'ok';
    BEGIN
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class)
        VALUES ('e1aa0000-0000-0000-0000-000000000001', 10, 'X', 'OPEX-MISC', now(), 'manual', 'wife_personal');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'BUG: nafaqah_class accepted without a spouse'; END IF;
    v_state := 'ok';
    BEGIN
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_spouse_id)
        VALUES ('e1aa0000-0000-0000-0000-000000000001', 10, 'X', 'OPEX-MISC', now(), 'manual', 'e1000000-0000-0000-0000-00000000000b');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'BUG: nafaqah_spouse_id accepted without a class'; END IF;

    -- unknown class value
    v_state := 'ok';
    BEGIN
        INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id)
        VALUES ('e1aa0000-0000-0000-0000-000000000001', 10, 'X', 'OPEX-MISC', now(), 'manual', 'split_50_50', 'e1000000-0000-0000-0000-00000000000b');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state <> '23514' THEN RAISE EXCEPTION 'BUG: unknown nafaqah_class not rejected by CHECK (got %)', v_state; END IF;

    RAISE NOTICE 'PASSED: Nafaqah classification requires a spouse member of the same household.';
END $$;

-- More fixtures: second reimbursable expense (children), husband-paid shared expense,
-- personal purchases in two cycles.
INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, nafaqah_class, nafaqah_spouse_id) VALUES
    ('e1f00000-0000-0000-0000-000000000002', 'e1aa0000-0000-0000-0000-000000000001', 200.50, 'Nahdi (kids)', 'OPEX-HEALTH', '2026-11-12 12:00+03', 'manual', 'wife_reimbursable', 'e1000000-0000-0000-0000-00000000000b'),
    ('e1f00000-0000-0000-0000-000000000003', 'e1aa0000-0000-0000-0000-000000000001', 400.00, 'Abaya shop', 'OPEX-SHOPPING', '2026-11-05 12:00+03', 'manual', 'wife_personal', 'e1000000-0000-0000-0000-00000000000b'),
    ('e1f00000-0000-0000-0000-000000000004', 'e1aa0000-0000-0000-0000-000000000001', 1300.00, 'Perfume', 'OPEX-SHOPPING', '2026-11-20 12:00+03', 'manual', 'wife_personal', 'e1000000-0000-0000-0000-00000000000b'),
    ('e1f00000-0000-0000-0000-000000000005', 'e1aa0000-0000-0000-0000-000000000001', 99.00, 'Salon (next cycle)', 'OPEX-SHOPPING', '2026-12-01 12:00+03', 'manual', 'wife_personal', 'e1000000-0000-0000-0000-00000000000b');
INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source) VALUES
    ('e1f00000-0000-0000-0000-000000000006', 'e1aa0000-0000-0000-0000-000000000001', 950.00, 'Rent share (husband)', 'OPEX-UTILITIES', '2026-11-03 12:00+03', 'manual');

-- 3. Clients cannot write the ledgers directly
DO $$
DECLARE
    v_state text;
BEGIN
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000b',
        $q$INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, amount) VALUES ('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: direct reimbursement insert accepted'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$INSERT INTO public.member_allowances (household_id, member_user_id, cycle_key, amount) VALUES ('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', '2026-11', 5)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: direct allowance insert accepted'; END IF;
    RAISE NOTICE 'PASSED: Nafaqah ledgers are written only through RPCs.';
END $$;

-- 4. Allowance authorization and validation
DO $$
DECLARE
    v_state text;
    v_amount numeric;
BEGIN
    -- the wife cannot set her own allowance
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000b',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1500, '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: wife set her own allowance'; END IF;
    -- a non-admin, non-husband member cannot set it
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000c',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1500, '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: ordinary member set the wife allowance'; END IF;
    -- another household's admin cannot set it
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000d',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1500, '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: foreign admin set the wife allowance'; END IF;
    -- allowances exist only for spouse members
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000c', 100, '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: allowance set for a non-spouse member'; END IF;
    -- negative, sub-halala and malformed cycle keys are rejected
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', -1, '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: negative allowance accepted'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 10.005, '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: sub-halala allowance accepted'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 10, '2026-13')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: malformed cycle_key accepted'; END IF;

    -- the husband sets it, then updates it (upsert, one row per cycle)
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1000, '2026-11')$q$);
    IF v_state <> '00000' THEN RAISE EXCEPTION 'Husband could not set allowance (%)', v_state; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1500, '2026-11')$q$);
    IF v_state <> '00000' THEN RAISE EXCEPTION 'Husband could not update allowance (%)', v_state; END IF;
    SELECT amount INTO v_amount FROM public.member_allowances
    WHERE household_id = 'e1aa0000-0000-0000-0000-000000000001' AND member_user_id = 'e1000000-0000-0000-0000-00000000000b' AND cycle_key = '2026-11';
    IF v_amount IS DISTINCT FROM 1500.00 OR (SELECT count(*) FROM public.member_allowances WHERE member_user_id = 'e1000000-0000-0000-0000-00000000000b') <> 1 THEN
        RAISE EXCEPTION 'Allowance upsert wrong: amount %', v_amount;
    END IF;
    RAISE NOTICE 'PASSED: only the husband/admin sets the wife allowance; amounts and cycle keys are validated.';
END $$;

-- 5. Allowance status: personal purchases of the cycle only; overspend is negative, not blocked
DO $$
DECLARE
    v_status jsonb;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000b', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    v_status := public.get_member_allowance_status('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', '2026-11');
    RESET ROLE;
    IF (v_status->>'allocated')::numeric <> 1500.00
       OR (v_status->>'spent')::numeric <> 1700.00
       OR (v_status->>'remaining')::numeric <> -200.00
       OR (v_status->>'is_set')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'Allowance status wrong: %', v_status;
    END IF;

    -- next cycle has no allocation yet: the 99.00 purchase still shows (remaining -99)
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000a', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    v_status := public.get_member_allowance_status('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', '2026-12');
    RESET ROLE;
    IF (v_status->>'allocated')::numeric <> 0 OR (v_status->>'spent')::numeric <> 99.00
       OR (v_status->>'remaining')::numeric <> -99.00 OR (v_status->>'is_set')::boolean IS NOT FALSE THEN
        RAISE EXCEPTION 'Next-cycle allowance status wrong: %', v_status;
    END IF;
    RAISE NOTICE 'PASSED: allowance spent/remaining per cycle; overspend reported as negative remaining.';
END $$;

-- 6. Reimbursement ledger: balance, partial, overpayment rejected, full, authorization
DO $$
DECLARE
    v_state text;
    v_bal jsonb;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000b', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    v_bal := public.get_spouse_reimbursement_balance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b');
    RESET ROLE;
    -- 300.00 + 200.50 wife-paid shared; husband-paid rent and personal purchases are not debt
    IF (v_bal->>'gross_advanced')::numeric <> 500.50 OR (v_bal->>'outstanding')::numeric <> 500.50 THEN
        RAISE EXCEPTION 'Initial balance wrong: %', v_bal;
    END IF;

    -- husband pays back 200 (partial)
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 200, 'stc_pay', 'partial')$q$);
    IF v_state <> '00000' THEN RAISE EXCEPTION 'Partial reimbursement failed (%)', v_state; END IF;

    -- overpayment is rejected and changes nothing
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 400, 'cash', NULL)$q$);
    IF v_state <> '22023' THEN RAISE EXCEPTION 'Overpayment not rejected with 22023 (got %)', v_state; END IF;

    -- ai_service maps the refusal by SQLSTATE 22023 + HINT 'overpayment' (PostgREST JSON code/hint)
    DECLARE
        v_code text;
        v_hint text;
    BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000a', 'role', 'authenticated')::text, true);
        SET LOCAL ROLE authenticated;
        PERFORM public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 400, 'cash', NULL);
        RAISE EXCEPTION 'BUG: overpayment accepted';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_code = RETURNED_SQLSTATE, v_hint = PG_EXCEPTION_HINT;
        IF v_code <> '22023' OR v_hint IS DISTINCT FROM 'overpayment' THEN
            RAISE EXCEPTION 'Overpayment refusal must carry SQLSTATE 22023 and HINT overpayment (got %, %)', v_code, v_hint;
        END IF;
    END;
    RESET ROLE;

    -- zero / negative / sub-halala / unknown method rejected
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 0, 'cash', NULL)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: zero reimbursement accepted'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 0.005, 'cash', NULL)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: sub-halala reimbursement accepted'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1, 'bitcoin', NULL)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: unknown payment method accepted'; END IF;

    -- an ordinary member and a foreign admin cannot record repayments
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000c',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1, 'cash', NULL)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: ordinary member recorded a reimbursement'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000d',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 1, 'cash', NULL)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: foreign admin recorded a reimbursement'; END IF;
    -- a roommate is never a Nafaqah creditor
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-0000000000e1',
        $q$SELECT public.record_spouse_reimbursement('e1cc0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-0000000000e2', 1, 'cash', NULL)$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'BUG: roommate reimbursement recorded in Nafaqah ledger'; END IF;
    -- a foreign user cannot read the balance either
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000d',
        $q$SELECT public.get_spouse_reimbursement_balance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: foreign user read the reimbursement balance'; END IF;
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000d',
        $q$SELECT public.get_member_allowance_status('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', '2026-11')$q$);
    IF v_state = '00000' THEN RAISE EXCEPTION 'VULNERABILITY: foreign user read the allowance status'; END IF;

    -- the wife confirms receipt of the remaining 300.50 (full settlement)
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000b',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 300.50, 'bank_transfer', 'rest')$q$);
    IF v_state <> '00000' THEN RAISE EXCEPTION 'Final reimbursement failed (%)', v_state; END IF;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000a', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    v_bal := public.get_spouse_reimbursement_balance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b');
    RESET ROLE;
    IF (v_bal->>'reimbursed')::numeric <> 500.50 OR (v_bal->>'outstanding')::numeric <> 0 THEN
        RAISE EXCEPTION 'Final balance wrong: %', v_bal;
    END IF;

    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000a',
        $q$SELECT public.record_spouse_reimbursement('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 0.01, 'cash', NULL)$q$);
    IF v_state <> '22023' THEN RAISE EXCEPTION 'Reimbursement after full settlement not rejected (got %)', v_state; END IF;

    IF (SELECT paid_by_user_id FROM public.spouse_reimbursements WHERE notes = 'rest') IS DISTINCT FROM 'e1000000-0000-0000-0000-00000000000a'::uuid
       OR (SELECT recorded_by FROM public.spouse_reimbursements WHERE notes = 'rest') IS DISTINCT FROM 'e1000000-0000-0000-0000-00000000000b'::uuid THEN
        RAISE EXCEPTION 'Reimbursement payer/recorder not attributed correctly';
    END IF;
    RAISE NOTICE 'PASSED: wife reimbursement debt: partial and full repayments, overpayment rejected, household-scoped.';
END $$;

-- 7. Household isolation of ledger reads (RLS)
DO $$
DECLARE
    v_count int;
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000d', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    SELECT (SELECT count(*) FROM public.spouse_reimbursements) + (SELECT count(*) FROM public.member_allowances) INTO v_count;
    RESET ROLE;
    IF v_count <> 0 THEN RAISE EXCEPTION 'VULNERABILITY: foreign user sees % Nafaqah ledger rows', v_count; END IF;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', 'e1000000-0000-0000-0000-00000000000b', 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    SELECT (SELECT count(*) FROM public.spouse_reimbursements) + (SELECT count(*) FROM public.member_allowances) INTO v_count;
    RESET ROLE;
    IF v_count <> 3 THEN RAISE EXCEPTION 'Wife should see her 2 reimbursements and 1 allowance, saw %', v_count; END IF;
    RAISE NOTICE 'PASSED: Nafaqah ledgers are readable only inside the household.';
END $$;

-- 8. Service role (ai_service) acts for a verified user; it cannot act anonymously
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role": "service_role"}', true);
DO $$
DECLARE
    v_state text := 'ok';
    v_status jsonb;
BEGIN
    v_status := public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 800, '2026-12',
                                            'e1000000-0000-0000-0000-00000000000a');
    IF (v_status->>'allocated')::numeric <> 800 OR (v_status->>'remaining')::numeric <> 701.00 THEN
        RAISE EXCEPTION 'service-role allowance set wrong: %', v_status;
    END IF;
    BEGIN
        PERFORM public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 800, '2026-12');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'VULNERABILITY: service role set allowance without an actor'; END IF;
    v_state := 'ok';
    BEGIN
        PERFORM public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 800, '2026-12',
                                            'e1000000-0000-0000-0000-00000000000b');
    EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE;
    END;
    IF v_state = 'ok' THEN RAISE EXCEPTION 'VULNERABILITY: service role let the wife set her own allowance'; END IF;
    RAISE NOTICE 'PASSED: service role acts only on behalf of an authorised actor.';
END $$;
RESET ROLE;

-- 9. An authenticated user cannot impersonate another actor
DO $$
DECLARE
    v_state text;
BEGIN
    v_state := pg_temp.as_user('e1000000-0000-0000-0000-00000000000b',
        $q$SELECT public.set_member_allowance('e1aa0000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-00000000000b', 5000, '2026-12', 'e1000000-0000-0000-0000-00000000000a')$q$);
    IF v_state <> '42501' THEN RAISE EXCEPTION 'VULNERABILITY: actor impersonation not rejected (got %)', v_state; END IF;
    RAISE NOTICE 'PASSED: p_actor_user_id cannot differ from the JWT subject.';
END $$;

-- 10. Deleting the wife's account cleans her ledgers and declassifies her transactions
DO $$
BEGIN
    DELETE FROM auth.users WHERE id = 'e1000000-0000-0000-0000-00000000000b';
    IF EXISTS (SELECT 1 FROM public.spouse_reimbursements WHERE wife_user_id = 'e1000000-0000-0000-0000-00000000000b')
       OR EXISTS (SELECT 1 FROM public.member_allowances WHERE member_user_id = 'e1000000-0000-0000-0000-00000000000b') THEN
        RAISE EXCEPTION 'Wife ledgers survived account deletion';
    END IF;
    IF EXISTS (SELECT 1 FROM public.transactions WHERE id = 'e1f00000-0000-0000-0000-000000000001' AND (nafaqah_class IS NOT NULL OR nafaqah_spouse_id IS NOT NULL)) THEN
        RAISE EXCEPTION 'Transactions kept a Nafaqah class for a deleted spouse';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.transactions WHERE id = 'e1f00000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'Household expense history was deleted with the spouse account';
    END IF;
    RAISE NOTICE 'PASSED: spouse account deletion keeps household history and drops her ledgers.';
END $$;

-- 11. Every refusal the ai_service maps carries an explicit SQLSTATE (PL/pgSQL defaults to
--     P0001, which nafaqah_service._map_db_error / household_permissions._map_rpc_error
--     would not recognise).
DO $$
DECLARE
    r record;
    v_chunk text;
    v_checked int := 0;
BEGIN
    FOR r IN
        SELECT p.proname, p.prosrc
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'nafaqah_resolve_actor', 'nafaqah_require_member', 'get_member_allowance_status',
              'set_member_allowance', 'get_spouse_reimbursement_balance', 'record_spouse_reimbursement',
              'validate_transaction_nafaqah_class', 'household_resolve_actor', 'household_require_admin',
              'promote_member_to_admin', 'revoke_admin', 'transfer_primary_admin',
              'protect_primary_admin_membership', 'get_household_members')
    LOOP
        -- string literals are blanked first: messages may contain ';'
        FOREACH v_chunk IN ARRAY (regexp_split_to_array(
            regexp_replace(r.prosrc, '''([^'']|'''')*''', '''''', 'g'), 'RAISE EXCEPTION'))[2:]
        LOOP
            v_checked := v_checked + 1;
            IF split_part(v_chunk, ';', 1) !~ 'ERRCODE' THEN
                RAISE EXCEPTION 'RAISE without ERRCODE in %: %', r.proname, left(split_part(v_chunk, ';', 1), 120);
            END IF;
        END LOOP;
    END LOOP;
    IF v_checked < 20 THEN
        RAISE EXCEPTION 'Expected to inspect the Nafaqah and role RPC refusals, inspected only %', v_checked;
    END IF;
    RAISE NOTICE 'PASSED: % mapped RPC refusals set an explicit SQLSTATE.', v_checked;
END $$;

ROLLBACK;
