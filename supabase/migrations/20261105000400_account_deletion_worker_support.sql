-- ============================================================================
-- Migration: 20261105000400_account_deletion_worker_support.sql
-- Plan: docs/superpowers/plans/2026-11-05-account-deletion-corrected.md, Task 5
--
-- Three service-only functions the plan's design needs and its function list lacks:
--
-- get_account_deletion_queue_summary   Read only. Disabled, the worker logs due counts,
--                                      and claim_due_account_deletions cannot be used for
--                                      that because it takes a lease and counts an attempt.
-- list_account_deletion_alerts_due     The developer alert on a failed job or one more than
--                                      48 hours overdue, once each. A job can reach 'failed'
--                                      inside claim_due_account_deletions, where the worker
--                                      gets no signal. Carries no user id.
-- purge_expired_account_deletion_inquiries
--                                      The public page says deletion requests are kept 90
--                                      days, so something has to remove them. Only type
--                                      account_deletion, and never sooner than 90 days.
--
-- Also: list_account_deletion_notices_due no longer offers a reminder for a date already
-- past, and mark_account_deletion_notice_sent accepts the two operator alerts.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_account_deletion_queue_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    RETURN (
        SELECT jsonb_build_object(
            'due', count(*) FILTER (WHERE r.status = 'scheduled' AND r.scheduled_for <= now()),
            'in_progress', count(*) FILTER (WHERE r.status = 'processing'),
            'failed', count(*) FILTER (WHERE r.status = 'failed'),
            'overdue', count(*) FILTER (WHERE r.status IN ('scheduled', 'processing')
                                          AND r.scheduled_for < now() - interval '48 hours')
        )
        FROM public.account_deletion_requests r
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_account_deletion_alerts_due()
RETURNS TABLE(request_id uuid, alert text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();
    RETURN QUERY
    SELECT r.id, q.alert
    FROM public.account_deletion_requests r
    CROSS JOIN LATERAL (
        SELECT CASE WHEN r.status = 'failed' THEN 'ops_failed' ELSE 'ops_overdue' END AS alert
    ) q
    WHERE (r.status = 'failed'
           OR (r.status IN ('scheduled', 'processing') AND r.scheduled_for < now() - interval '48 hours'))
      AND NOT (q.alert = ANY (r.notices_sent));
END;
$$;

CREATE OR REPLACE FUNCTION public.purge_expired_account_deletion_inquiries(p_days integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_removed integer;
BEGIN
    PERFORM public.account_deletion_require_service();
    DELETE FROM public.inquiries i
    WHERE i.type = 'account_deletion'
      AND i.created_at < now() - make_interval(days => GREATEST(COALESCE(p_days, 90), 90));
    GET DIAGNOSTICS v_removed = ROW_COUNT;
    RETURN v_removed;
END;
$$;

-- Same function, except that a date already past gets no reminder: the job is about to run,
-- and "will be deleted on <yesterday>" helps nobody.
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
      AND r.scheduled_for > now()
      AND r.scheduled_for <= now() + interval '7 days'
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
      AND h.deletion_scheduled_for > now()
      AND NOT (n.notice = ANY (r.notices_sent))
      AND (n.notice <> 'member_t7' OR h.deletion_scheduled_for > now() + interval '1 day');
END;
$$;

-- Same function, with the two operator alerts added to the accepted names.
CREATE OR REPLACE FUNCTION public.mark_account_deletion_notice_sent(p_request_id uuid, p_notice text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.account_deletion_require_service();

    IF p_notice IS NULL OR p_notice NOT IN ('holder_t7', 'holder_t1', 'holder_completion', 'member_marked', 'member_t7',
                                            'ops_failed', 'ops_overdue') THEN
        RAISE EXCEPTION 'Unknown notice' USING ERRCODE = '22023';
    END IF;

    UPDATE public.account_deletion_requests
    SET notices_sent = array_append(notices_sent, p_notice)
    WHERE id = p_request_id
      AND NOT (p_notice = ANY (notices_sent));

    -- A first notice sent inside the last 7 days already says the date.
    IF p_notice = 'member_marked' THEN
        UPDATE public.account_deletion_requests
        SET notices_sent = array_append(notices_sent, 'member_t7')
        WHERE id = p_request_id
          AND scheduled_for <= now() + interval '7 days'
          AND NOT ('member_t7' = ANY (notices_sent));
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_account_deletion_queue_summary() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_account_deletion_alerts_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_expired_account_deletion_inquiries(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_queue_summary() TO service_role;
GRANT EXECUTE ON FUNCTION public.list_account_deletion_alerts_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_expired_account_deletion_inquiries(integer) TO service_role;

COMMIT;
