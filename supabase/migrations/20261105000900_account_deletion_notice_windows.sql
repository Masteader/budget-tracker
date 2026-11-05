-- ============================================================================
-- Migration: 20261105000900_account_deletion_notice_windows.sql
-- Runbook: docs/runbooks/account-deletion-purge.md
--
-- ACCOUNT_DELETION_EMAILS_ENABLED can stay off for weeks, and a notice is not marked sent
-- while it is. So when it comes on, or after an outage, only a notice that still means
-- something may be offered:
--
--   holder_t7      7 days to 2 days before. Closer than that, T-1 is about to go out.
--   holder_t1      1 day to 1 hour before. Under an hour the purge is next, with no time
--                  left to act on it.
--   member_marked  Until 1 hour before.
--   member_t7      After member_marked, while more than 2 days remain.
--
-- Between 2 days and 1 day a holder gets nothing, so two reminders cannot land an hour
-- apart. The normal hourly flow, with the switch on, is unchanged.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.list_account_deletion_notices_due()
RETURNS TABLE(request_id uuid, user_id uuid, notice text, locale text, scheduled_for timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    RETURN QUERY
    -- The account holder at T-7 and T-1.
    SELECT r.id, r.user_id,
           CASE WHEN r.scheduled_for <= now() + interval '1 day' THEN 'holder_t1' ELSE 'holder_t7' END,
           r.locale, r.scheduled_for
    FROM public.account_deletion_requests r
    WHERE r.status = 'scheduled'
      AND (
          (r.scheduled_for > now() + interval '2 days'
      AND r.scheduled_for <= now() + interval '7 days')
          OR
          (r.scheduled_for >= now() + interval '1 hour'
      AND r.scheduled_for <= now() + interval '1 day')
      )
      AND NOT ((CASE WHEN r.scheduled_for <= now() + interval '1 day' THEN 'holder_t1' ELSE 'holder_t7' END) = ANY (r.notices_sent))
    UNION ALL
    -- Sent before the Auth delete takes the address away, once the database work is done.
    SELECT r.id, r.user_id, 'holder_completion', r.locale, r.scheduled_for
    FROM public.account_deletion_requests r
    WHERE r.stage <> 'none'
      AND r.status = 'processing'
      AND NOT ('holder_completion' = ANY (r.notices_sent))
      AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = r.user_id)
    UNION ALL
    -- Other members of a marked household: when marked, and at T-7.
    SELECT r.id, m.user_id, n.notice, r.locale, h.deletion_scheduled_for
    FROM public.account_deletion_requests r
    JOIN public.households h ON h.deletion_requested_by = r.user_id AND h.deletion_scheduled_for IS NOT NULL
    JOIN public.household_memberships m ON m.household_id = h.id AND m.user_id <> r.user_id
    CROSS JOIN LATERAL (
        SELECT CASE WHEN h.deletion_scheduled_for <= now() + interval '7 days' AND 'member_marked' = ANY (r.notices_sent)
                    THEN 'member_t7' ELSE 'member_marked' END AS notice
    ) n
    WHERE r.status = 'scheduled'
      AND h.deletion_scheduled_for >= now() + interval '1 hour'
      AND NOT (n.notice = ANY (r.notices_sent))
      AND (n.notice <> 'member_t7' OR h.deletion_scheduled_for > now() + interval '2 days');
END;
$$;

COMMIT;
