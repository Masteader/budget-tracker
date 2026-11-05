-- ============================================================================
-- Rollback: in-app account deletion, migrations 20261105000100, 000200, 000300, 000400,
-- 000800 and 000900. See docs/review/OWNER_ACTIONS.md, "Rolling back".
--
-- Leaves in place, on purpose:
--   * 20261105000000 (ledger FKs). Restoring ON DELETE CASCADE on income_records.user_id
--     would bring back the bug where deleting a member's account lowered a shared pool.
--   * 000500, 000600, 000700 (the void fix and the access fixes), 001000 and 001100: they do
--     not depend on anything dropped here.
--   * inquiries_type_check still allows 'account_deletion': rows of that type may exist.
--
-- What it does, in one transaction:
--   1. Puts back the three existing functions 000100 replaced, as they were after 000000
--      (taken verbatim from the chain built through 000000). Their new versions use the
--      tables and helpers dropped below.
--   2. Drops the four triggers of 000100.
--   3. Drops every function 000100 to 000900 added (40).
--   4. Drops the three tables, and the three households columns of the deletion marks.
--
-- Data lost: every deletion request (open, cancelled and the completed tombstones), the
-- storage queue, the worker's run log and the households' deletion marks. Switch the worker
-- off (unset ACCOUNT_DELETION_PURGE_ENABLED) and copy what you want to keep first; the
-- read-only pre-checks are in OWNER_ACTIONS.md. Nothing else changes.
--
-- Verified 2026-11-06 on a throwaway Postgres 17 copy of the built chain: the result has
-- exactly the schema of the chain built without these six files, apart from that inquiries
-- check, and the database tests
-- that do not test account deletion still pass on it.
-- ============================================================================

BEGIN;

-- 1. The existing functions, as 000000 left them ---------------------------------------------
CREATE OR REPLACE FUNCTION public.handover_households_on_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_hh record;
    v_successor uuid;
    v_new_owner uuid;
BEGIN
    FOR v_hh IN
        SELECT m.household_id, m.role
        FROM public.household_memberships m
        WHERE m.user_id = OLD.id
    LOOP
        IF v_hh.role = 'admin'
           AND NOT EXISTS (
               SELECT 1 FROM public.household_memberships o
               WHERE o.household_id = v_hh.household_id
                 AND o.user_id <> OLD.id
                 AND o.role = 'admin'
           ) THEN
            SELECT o.user_id INTO v_successor
            FROM public.household_memberships o
            WHERE o.household_id = v_hh.household_id
              AND o.user_id <> OLD.id
            ORDER BY o.created_at ASC, o.user_id ASC
            LIMIT 1;

            IF v_successor IS NOT NULL THEN
                UPDATE public.household_memberships
                SET role = 'admin'
                WHERE household_id = v_hh.household_id
                  AND user_id = v_successor;

                UPDATE public.users
                SET role = 'admin'
                WHERE id = v_successor
                  AND household_id = v_hh.household_id;
            END IF;
        END IF;

        SELECT o.user_id INTO v_new_owner
        FROM public.household_memberships o
        WHERE o.household_id = v_hh.household_id
          AND o.user_id <> OLD.id
          AND o.role = 'admin'
        ORDER BY o.created_at ASC, o.user_id ASC
        LIMIT 1;

        IF v_new_owner IS NOT NULL THEN
            UPDATE public.accounts
            SET owner_user_id = v_new_owner,
                updated_at = now()
            WHERE household_id = v_hh.household_id
              AND owner_user_id = OLD.id
              AND is_shared_pool = true;
        END IF;
    END LOOP;

    -- A pool owned by someone who has already left: leave_household and remove_member
    -- do not re-own, so the loop above never sees it. Hand it to the household's admin.
    UPDATE public.accounts a
    SET owner_user_id = n.user_id,
        updated_at = now()
    FROM (
        SELECT DISTINCT ON (o.household_id) o.household_id, o.user_id
        FROM public.household_memberships o
        WHERE o.user_id <> OLD.id AND o.role = 'admin'
        ORDER BY o.household_id, o.created_at ASC, o.user_id ASC
    ) n
    WHERE a.household_id = n.household_id
      AND a.owner_user_id = OLD.id
      AND a.is_shared_pool = true;

    -- Whatever this user still owns now cascades. income_records.account_id is RESTRICT.
    DELETE FROM public.income_records i
    USING public.accounts a
    WHERE i.account_id = a.id
      AND a.owner_user_id = OLD.id;

    DELETE FROM public.account_transfers t
    USING public.accounts f, public.accounts d
    WHERE t.from_account_id = f.id
      AND t.to_account_id = d.id
      AND f.owner_user_id = OLD.id
      AND d.owner_user_id = OLD.id;

    RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION public.maintain_household_primary_admin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.households h
        SET owner_user_id = (
            SELECT m.user_id
            FROM public.household_memberships m
            WHERE m.household_id = OLD.household_id
              AND m.user_id <> OLD.user_id
              AND m.role = 'admin'
            ORDER BY m.created_at ASC, m.user_id ASC
            LIMIT 1
        )
        WHERE h.id = OLD.household_id
          AND (h.owner_user_id IS NULL OR h.owner_user_id = OLD.user_id);
        RETURN OLD;
    END IF;

    IF NEW.role = 'admin' THEN
        UPDATE public.households h
        SET owner_user_id = NEW.user_id,
            nafaqah_provider_user_id = CASE
                WHEN TG_OP = 'INSERT'
                     AND h.nafaqah_provider_user_id IS NULL
                     AND h.household_type = 'family'
                     AND NEW.financial_role IS DISTINCT FROM 'spouse'
                     AND NOT EXISTS (SELECT 1 FROM public.household_memberships o
                                     WHERE o.household_id = NEW.household_id AND o.user_id <> NEW.user_id)
                    THEN NEW.user_id
                ELSE h.nafaqah_provider_user_id
            END
        WHERE h.id = NEW.household_id AND h.owner_user_id IS NULL;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.transfer_primary_admin(p_household_id uuid, p_new_primary_user_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
    v_target_role text;
    v_provider uuid;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT owner_user_id INTO v_owner
    FROM public.households
    WHERE id = p_household_id
    FOR UPDATE;

    IF v_owner IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'Forbidden: only the primary admin can transfer primary admin' USING ERRCODE = '42501';
    END IF;

    IF p_new_primary_user_id IS NULL OR p_new_primary_user_id = v_actor THEN
        RAISE EXCEPTION 'Choose another member of this household' USING ERRCODE = '22023';
    END IF;

    v_target_role := public.household_member_role(p_household_id, p_new_primary_user_id);
    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;

    IF v_target_role <> 'admin' THEN
        PERFORM public.household_apply_role(p_household_id, p_new_primary_user_id, 'admin');
    END IF;

    UPDATE public.households
    SET owner_user_id = p_new_primary_user_id,
        nafaqah_provider_user_id = COALESCE(
            nafaqah_provider_user_id,
            CASE WHEN household_type = 'family'
                      AND public.household_member_financial_role(p_household_id, p_new_primary_user_id) <> 'spouse'
                 THEN p_new_primary_user_id END
        )
    WHERE id = p_household_id
    RETURNING nafaqah_provider_user_id INTO v_provider;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'primary_admin_user_id', p_new_primary_user_id,
        'previous_primary_admin_user_id', v_actor,
        'nafaqah_provider_user_id', v_provider
    );
END;
$function$;

-- 2. Triggers --------------------------------------------------------------------------------
DROP TRIGGER trg_account_deletion_guard_invite ON public.household_invites;
DROP TRIGGER trg_account_deletion_clear_marks ON public.household_memberships;
DROP TRIGGER trg_account_deletion_guard_membership ON public.household_memberships;
DROP TRIGGER trg_account_deletion_guard_provider ON public.households;

-- 3. Functions (no CASCADE: anything still depending on one stops the rollback) --------------
DROP FUNCTION public.account_deletion_clear_marks_on_membership_end();
DROP FUNCTION public.account_deletion_guard_invite();
DROP FUNCTION public.account_deletion_guard_membership();
DROP FUNCTION public.account_deletion_guard_provider();
DROP FUNCTION public.account_deletion_user_pending(uuid);
DROP FUNCTION public.account_deletion_household_positions(uuid);
DROP FUNCTION public.account_deletion_recent_login_ok();
DROP FUNCTION public.account_deletion_status_json(uuid);
DROP FUNCTION public.cancel_account_deletion();
DROP FUNCTION public.get_account_deletion_preflight();
DROP FUNCTION public.get_account_deletion_status();
DROP FUNCTION public.request_account_deletion(text, jsonb, text, text);
DROP FUNCTION public.account_deletion_note_token(text, text[]);
DROP FUNCTION public.account_deletion_replace_everywhere(text, text);
DROP FUNCTION public.account_deletion_repoint_active_household(uuid);
DROP FUNCTION public.account_deletion_require_service();
DROP FUNCTION public.account_deletion_scrub_item_names(jsonb, text[]);
DROP FUNCTION public.account_deletion_scrub_items(jsonb, text[]);
DROP FUNCTION public.account_deletion_scrub_other_note(text, text[]);
DROP FUNCTION public.account_deletion_scrub_own_note(text, text[]);
DROP FUNCTION public.account_deletion_scrub_text(text, text[]);
DROP FUNCTION public.claim_due_account_deletions(integer, integer);
DROP FUNCTION public.complete_account_purge(uuid);
DROP FUNCTION public.list_account_deletion_notices_due();
DROP FUNCTION public.list_account_purge_storage(uuid);
DROP FUNCTION public.mark_account_deletion_notice_sent(uuid, text);
DROP FUNCTION public.mark_account_purge_storage_done(uuid);
DROP FUNCTION public.prepare_account_purge(uuid);
DROP FUNCTION public.record_account_deletion_worker_run(timestamptz, integer, integer, integer);
DROP FUNCTION public.record_account_purge_failure(uuid, text);
DROP FUNCTION public.get_account_deletion_queue_summary();
DROP FUNCTION public.list_account_deletion_alerts_due();
DROP FUNCTION public.purge_expired_account_deletion_inquiries(integer);
DROP FUNCTION public.account_deletion_cancel(uuid, text, text);
DROP FUNCTION public.account_deletion_fold_confirmation(text);
DROP FUNCTION public.account_deletion_require_operator_handle(text);
DROP FUNCTION public.account_deletion_schedule(uuid, jsonb, text, text, text, text, text);
DROP FUNCTION public.cancel_account_deletion_by_operator(uuid, text, text);
DROP FUNCTION public.get_account_deletion_operator_preview(text, text);
DROP FUNCTION public.schedule_account_deletion_by_operator(uuid, text, text, jsonb, text);

-- 4. Tables and the households columns --------------------------------------------------------
DROP TABLE public.account_deletion_storage_queue;
DROP TABLE public.account_deletion_worker_runs;
DROP TABLE public.account_deletion_requests;
ALTER TABLE public.households
    DROP COLUMN deletion_requested_by,
    DROP COLUMN deletion_requested_at,
    DROP COLUMN deletion_scheduled_for;

COMMIT;
