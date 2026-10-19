-- ====================================================================
-- Test: 04_sec07_api_quota.sql
-- Proof test for SEC-07: Persistent API Quota Tracking & Rate Limiting
-- ====================================================================

DO $$
DECLARE
    v_user_id UUID := '77777777-7777-7777-7777-777777777777'::UUID;
    v_allowed BOOLEAN;
    v_stat RECORD;
    v_leak_count INT := 0;
BEGIN
    -- 1. Apply Migration to ensure table and functions exist
    CREATE TABLE IF NOT EXISTS public.api_quota (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        bucket TEXT NOT NULL,
        window_start TIMESTAMPTZ NOT NULL,
        count INT NOT NULL DEFAULT 1,
        created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
        CONSTRAINT uq_api_quota_user_bucket_window UNIQUE (user_id, bucket, window_start)
    );

    CREATE INDEX IF NOT EXISTS idx_api_quota_lookup 
    ON public.api_quota (user_id, bucket, window_start DESC);

    ALTER TABLE public.api_quota ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.api_quota FROM anon, authenticated, public;
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.api_quota TO service_role;

    -- Setup test user
    INSERT INTO auth.users (id, email)
    VALUES (v_user_id, 'quota_test_user@example.com')
    ON CONFLICT (id) DO NOTHING;

    -- 2. Test Quota Consumption: Limit of 3 per 600s
    -- Call 1: Allowed
    v_allowed := public.consume_quota(v_user_id, 'test_bucket', 3, 600);
    IF NOT v_allowed THEN
        RAISE EXCEPTION 'TEST FAILED: Call 1 should be allowed under limit 3';
    END IF;

    -- Call 2: Allowed
    v_allowed := public.consume_quota(v_user_id, 'test_bucket', 3, 600);
    IF NOT v_allowed THEN
        RAISE EXCEPTION 'TEST FAILED: Call 2 should be allowed under limit 3';
    END IF;

    -- Call 3: Allowed (at limit)
    v_allowed := public.consume_quota(v_user_id, 'test_bucket', 3, 600);
    IF NOT v_allowed THEN
        RAISE EXCEPTION 'TEST FAILED: Call 3 should be allowed at limit 3';
    END IF;

    -- Call 4: Blocked (over limit)
    v_allowed := public.consume_quota(v_user_id, 'test_bucket', 3, 600);
    IF v_allowed THEN
        RAISE EXCEPTION 'TEST FAILED: Call 4 should be blocked exceeding limit 3';
    END IF;
    RAISE NOTICE 'PASSED: consume_quota correctly permits up to limit and blocks subsequent calls.';

    -- 3. Test check_quota_status
    SELECT * INTO v_stat FROM public.check_quota_status(v_user_id, 'test_bucket', 3, 600);
    IF v_stat.allowed THEN
        RAISE EXCEPTION 'TEST FAILED: check_quota_status reports allowed when quota is exhausted';
    END IF;
    IF v_stat.current_count <> 4 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected count 4, got %', v_stat.current_count;
    END IF;
    IF v_stat.remaining <> 0 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected remaining 0, got %', v_stat.remaining;
    END IF;
    RAISE NOTICE 'PASSED: check_quota_status correctly reports exhausted quota.';

    -- 4. Test RLS / Permission Hardening
    -- Simulate authenticated user attempting to directly read or mutate api_quota table
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id::text, 'role', 'authenticated')::text, true);

    BEGIN
        SELECT count(*) INTO v_leak_count FROM public.api_quota;
        RAISE EXCEPTION 'TEST FAILED: Authenticated user should not have SELECT privilege on api_quota!';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'PASSED: Direct SELECT on api_quota blocked by permissions (insufficient_privilege).';
    END;

    BEGIN
        INSERT INTO public.api_quota (user_id, bucket, window_start, count)
        VALUES (v_user_id, 'hacked_bucket', now(), 1);
        RAISE EXCEPTION 'TEST FAILED: Authenticated user should not have INSERT privilege on api_quota!';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'PASSED: Direct INSERT on api_quota blocked by permissions (insufficient_privilege).';
    END;

    -- Clean up local role
    RESET ROLE;

    -- Clean up test fixtures
    DELETE FROM public.api_quota WHERE user_id = v_user_id;
    DELETE FROM auth.users WHERE id = v_user_id;
    RAISE NOTICE 'PASSED: Cleaned up test fixtures.';
END $$;
