-- ============================================================================
-- Test 28: Inquiries Persistence
--
-- Migrations: 20261024000000_create_inquiries_table.sql,
--             20261105000600_limit_anonymous_contact_form.sql
--
-- Inquiries reach this table only through POST /public/inquiries, which writes with the
-- service role. This test used to require a direct anonymous insert, which no client ever
-- made and which rule 04 and tests 14 and 23 forbid.
--
-- Verifies:
--   1. The service role stores and reads inquiries.
--   2. Reference column uniqueness is enforced.
--   3. Anonymous visitors CANNOT insert into or select from public.inquiries.
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

-- 1. Table existence and structure
SELECT pg_temp.expect(
    'inquiries table exists',
    (SELECT count(*)::text FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inquiries'),
    '1'
);

-- 2. The service role stores an inquiry, as ai_service does
SET LOCAL ROLE service_role;
INSERT INTO public.inquiries (
    type,
    email,
    name,
    locale,
    source,
    reference
) VALUES (
    'vip_early_access',
    'test_anon@example.com',
    'Test Visitor',
    'ar',
    'web',
    'ref_anon_test_001'
);

-- 3. And reads it back
SELECT pg_temp.expect(
    'record was stored and readable by the service role',
    (SELECT count(*)::text FROM public.inquiries WHERE reference = 'ref_anon_test_001'),
    '1'
);
RESET ROLE;

-- 4. Anonymous visitors can neither write nor read
DO $$
DECLARE
    v_refused int := 0;
BEGIN
    SET LOCAL ROLE anon;
    BEGIN
        INSERT INTO public.inquiries (type, email, reference)
        VALUES ('vip_early_access', 'test_anon@example.com', 'ref_anon_test_002');
    EXCEPTION WHEN insufficient_privilege THEN
        v_refused := v_refused + 1;
    END;
    BEGIN
        PERFORM count(*) FROM public.inquiries;
    EXCEPTION WHEN insufficient_privilege THEN
        v_refused := v_refused + 1;
    END;
    RESET ROLE;
    IF v_refused <> 2 THEN
        RAISE EXCEPTION 'anonymous access to inquiries was not refused (% of 2)', v_refused;
    END IF;
END;
$$;

-- 5. Duplicate reference must fail
DO $$
BEGIN
    INSERT INTO public.inquiries (
        type, email, reference
    ) VALUES (
        'vip_early_access', 'other@example.com', 'ref_anon_test_001'
    );
    RAISE EXCEPTION 'duplicate reference should have thrown unique constraint violation';
EXCEPTION
    WHEN unique_violation THEN
        -- Expected
        NULL;
END;
$$;

ROLLBACK;
