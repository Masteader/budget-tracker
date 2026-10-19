-- ----------------------------------------------------------------------
-- Migration: 20261019070000_sec07_api_quota_and_rate_limits.sql
-- SEC-07: Persistent API Quota Tracking, Rate Limiting & Cost Control
-- ----------------------------------------------------------------------

-- 1. Create api_quota table
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

-- Index for lookup performance
CREATE INDEX IF NOT EXISTS idx_api_quota_lookup 
ON public.api_quota (user_id, bucket, window_start DESC);

-- Enable RLS
ALTER TABLE public.api_quota ENABLE ROW LEVEL SECURITY;

-- Zero client policies: clients cannot directly access this table
REVOKE ALL ON public.api_quota FROM anon, authenticated, public;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.api_quota TO service_role;

-- 2. Create consume_quota function
CREATE OR REPLACE FUNCTION public.consume_quota(
    p_user_id UUID,
    p_bucket TEXT,
    p_limit INT,
    p_window_seconds INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_window_start TIMESTAMPTZ;
    v_current_count INT;
BEGIN
    -- Derive window start boundary aligned to window size
    v_window_start := to_timestamp(floor(extract(epoch from v_now) / GREATEST(p_window_seconds, 1)) * GREATEST(p_window_seconds, 1));

    -- Upsert and increment quota
    INSERT INTO public.api_quota (user_id, bucket, window_start, count, created_at, updated_at)
    VALUES (p_user_id, p_bucket, v_window_start, 1, v_now, v_now)
    ON CONFLICT (user_id, bucket, window_start)
    DO UPDATE SET 
        count = public.api_quota.count + 1,
        updated_at = v_now
    RETURNING count INTO v_current_count;

    -- Return false if exceeded limit, true otherwise
    RETURN v_current_count <= p_limit;
END;
$$;

-- 3. Create check_quota_status function
CREATE OR REPLACE FUNCTION public.check_quota_status(
    p_user_id UUID,
    p_bucket TEXT,
    p_limit INT,
    p_window_seconds INT
)
RETURNS TABLE (
    allowed BOOLEAN,
    current_count INT,
    remaining INT,
    retry_after_seconds INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_cnt INT := 0;
BEGIN
    v_window_start := to_timestamp(floor(extract(epoch from v_now) / GREATEST(p_window_seconds, 1)) * GREATEST(p_window_seconds, 1));
    v_window_end := v_window_start + (GREATEST(p_window_seconds, 1) * interval '1 second');

    SELECT count INTO v_cnt
    FROM public.api_quota
    WHERE user_id = p_user_id
      AND bucket = p_bucket
      AND window_start = v_window_start;

    IF v_cnt IS NULL THEN
        v_cnt := 0;
    END IF;

    allowed := v_cnt < p_limit;
    current_count := v_cnt;
    remaining := GREATEST(p_limit - v_cnt, 0);
    retry_after_seconds := GREATEST(ceil(extract(epoch from (v_window_end - v_now)))::INT, 1);
    RETURN NEXT;
END;
$$;

-- Restrict execution grants
REVOKE ALL ON FUNCTION public.consume_quota(UUID, TEXT, INT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_quota(UUID, TEXT, INT, INT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.check_quota_status(UUID, TEXT, INT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_quota_status(UUID, TEXT, INT, INT) TO authenticated, service_role;
