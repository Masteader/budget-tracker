-- ============================================================================
-- Test 28: Inquiries Persistence and Anonymous Access
--
-- Migration: 20261024000000_create_inquiries_table.sql
--
-- Verifies:
--   1. Anonymous visitors can insert inquiries into public.inquiries.
--   2. Reference column uniqueness is enforced.
--   3. Anonymous visitors CANNOT select from public.inquiries (RLS read protection).
--   4. Service role / admin can view inquiries.
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
PERFORM pg_temp.expect(
    'inquiries table exists',
    (SELECT count(*)::text FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inquiries'),
    '1'
);

-- 2. Verify anonymous insert works
SET LOCAL ROLE anon;
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

-- 3. Verify anonymous cannot read the inquiries table (0 rows returned via RLS)
PERFORM pg_temp.expect(
    'anonymous select returns 0 rows',
    (SELECT count(*)::text FROM public.inquiries),
    '0'
);

-- 4. Reset role to postgres / service_role and verify record is present
RESET ROLE;
PERFORM pg_temp.expect(
    'record was stored and readable by postgres',
    (SELECT count(*)::text FROM public.inquiries WHERE reference = 'ref_anon_test_001'),
    '1'
);

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
