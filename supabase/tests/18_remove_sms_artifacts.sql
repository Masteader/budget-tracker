-- ============================================================================
-- Test 18 (audit API-25, zero-SMS policy): no SMS artefacts in the schema
--
-- 20260925/20260930 created transactions.source with DEFAULT 'sms' and a
-- CHECK that allowed 'sms', so rows were labelled as SMS-sourced by default.
-- 20261020200000_remove_sms_artifacts.sql relabels history and removes the
-- SMS channel. This test fails if an SMS channel, an SMS-only object or an
-- SMS-sourced row reappears.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- 1. Schema: default is 'manual', CHECK has no 'sms', no SMS-named objects.
DO $$
DECLARE
    v_default text;
    v_check text;
    v_objects text;
BEGIN
    SELECT column_default INTO v_default
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'source';
    IF v_default IS DISTINCT FROM '''manual''::text' THEN
        RAISE EXCEPTION 'BUG (API-25): transactions.source default is %, expected manual', v_default;
    END IF;

    SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_check
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.conrelid = 'public.transactions'::regclass AND c.contype = 'c' AND a.attname = 'source';
    IF v_check IS NULL OR v_check ILIKE '%sms%' THEN
        RAISE EXCEPTION 'BUG (API-25): transactions.source CHECK still allows sms (or is missing): %', v_check;
    END IF;

    -- raw_sms is the documented legacy name of the audit-note column; nothing else may mention SMS.
    SELECT string_agg(obj, ', ') INTO v_objects FROM (
        SELECT 'relation ' || c.relname AS obj
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname ILIKE '%sms%'
        UNION ALL
        SELECT 'function ' || p.proname
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND (p.proname ILIKE '%sms%' OR p.prosrc ILIKE '%sms%')
        UNION ALL
        SELECT 'trigger ' || t.tgname
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal AND t.tgname ILIKE '%sms%'
        UNION ALL
        SELECT 'column ' || table_name || '.' || column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND column_name ILIKE '%sms%'
          AND NOT (table_name = 'transactions' AND column_name = 'raw_sms')
    ) s;
    IF v_objects IS NOT NULL THEN
        RAISE EXCEPTION 'BUG (API-25): SMS objects present: %', v_objects;
    END IF;

    IF col_description('public.transactions'::regclass,
           (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'raw_sms'))
       NOT ILIKE '%never reads SMS%' THEN
        RAISE EXCEPTION 'BUG (API-25): transactions.raw_sms is still documented as SMS text';
    END IF;

    SELECT string_agg(d.objoid::regclass::text || COALESCE('.' || a.attname, ''), ', ') INTO v_objects
    FROM pg_description d
    JOIN pg_class c ON c.oid = d.objoid AND d.classoid = 'pg_class'::regclass
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    LEFT JOIN pg_attribute a ON a.attrelid = d.objoid AND a.attnum = d.objsubid AND d.objsubid > 0
    WHERE d.description ILIKE '%sms%' AND d.description NOT ILIKE '%never reads SMS%';
    IF v_objects IS NOT NULL THEN
        RAISE EXCEPTION 'BUG (API-25): schema comments still describe SMS processing: %', v_objects;
    END IF;

    IF EXISTS (SELECT 1 FROM public.transactions WHERE source = 'sms') THEN
        RAISE EXCEPTION 'BUG (API-25): SMS-sourced transactions remain after relabel';
    END IF;
    RAISE NOTICE 'PASSED: no SMS channel, SMS objects or SMS-labelled rows in the schema.';
END $$;

-- 2. A member cannot create an SMS-sourced row; an insert without a source is 'manual'.
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES ('e1800000-0000-0000-0000-000000000001', 'sms18-member@test.local');
    INSERT INTO public.households (id, name, invite_code, payday_day)
    VALUES ('e18a0000-0000-0000-0000-000000000001', 'SMS18 Home', 'SMS18HOMECODE001', 27);
    UPDATE public.users SET household_id = 'e18a0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'e1800000-0000-0000-0000-000000000001';
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "e1800000-0000-0000-0000-000000000001", "role": "authenticated"}', true);

INSERT INTO public.transactions (id, household_id, user_id, amount, category_code, timestamp)
VALUES ('e18e0000-0000-0000-0000-000000000001', 'e18a0000-0000-0000-0000-000000000001',
        'e1800000-0000-0000-0000-000000000001', 25, 'OPEX-GROCERY', '2026-11-05 12:00:00+03');

DO $$
BEGIN
    BEGIN
        INSERT INTO public.transactions (household_id, user_id, amount, category_code, timestamp, source)
        VALUES ('e18a0000-0000-0000-0000-000000000001', 'e1800000-0000-0000-0000-000000000001',
                10, 'OPEX-GROCERY', '2026-11-05 12:00:00+03', 'sms');
        RAISE EXCEPTION 'BUG (API-25): an sms-sourced transaction was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        UPDATE public.transactions SET source = 'sms' WHERE id = 'e18e0000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'BUG (API-25): a transaction was relabelled as sms';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;
RESET ROLE;

DO $$
DECLARE
    v_source text;
BEGIN
    SELECT source INTO v_source FROM public.transactions WHERE id = 'e18e0000-0000-0000-0000-000000000001';
    IF v_source IS DISTINCT FROM 'manual' THEN
        RAISE EXCEPTION 'BUG (API-25): insert without source stored %, expected manual', v_source;
    END IF;
    RAISE NOTICE 'PASSED: new rows cannot be SMS-sourced; unlabelled inserts are manual.';
END $$;

ROLLBACK;
