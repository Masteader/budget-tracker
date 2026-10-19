-- ----------------------------------------------------------------------
-- Rollback snapshot for SEC-07 (api_quota table and rate limits)
-- Captured at: 2026-10-19T06:25:00Z
-- ----------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.check_quota_status(UUID, TEXT, INT, INT);
DROP FUNCTION IF EXISTS public.consume_quota(UUID, TEXT, INT, INT);
DROP TABLE IF EXISTS public.api_quota CASCADE;
