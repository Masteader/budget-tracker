-- ============================================================================
-- Migration: 20261105000100_account_deletion_schema.sql
-- Plan: docs/superpowers/plans/2026-11-05-account-deletion-corrected.md, Task 2
--
-- Tables for the deletion request lifecycle, the household deletion marks, and the
-- guards for the 30-day grace period.
--
-- Tables: RLS on, no policies, no client privileges; clients reach them only through
-- the RPCs of 20261105000200. account_deletion_requests has no FK to users on
-- purpose: its tombstone outlives the user. A separate table, because
-- users_select_household would expose new users columns to housemates.
--
-- A pending user (active request) keeps normal use, exports and
-- switch_active_household. They cannot join, claim an invite, create a household, be
-- promoted, receive primary admin or become Nafaqah provider. A marked household
-- stays active for its members but takes no new members and no new invites.
--
-- These are triggers so the RPC and the service-role paths are both covered. BEFORE
-- INSERT also fires on the ON CONFLICT of sync_user_household_membership, so the
-- membership guard returns early when the membership already exists. Otherwise
-- switch_active_household would break for pending users.
--
-- handover_households_on_user_delete still only hands over and never deletes a
-- household; household deletion lives in the purge alone. It prefers a member who is
-- not pending and promotes a pending one only when nobody else is left, because a
-- household with members must keep an admin. maintain_household_primary_admin
-- prefers a non-pending admin in the same way; with nobody pending, both pick exactly
-- what they picked before. For an account deleted out of band it also removes the
-- user's invite_attempt_log rows and cancelled deletion requests, which have no FK.
-- ============================================================================

BEGIN;

CREATE TABLE public.account_deletion_requests (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid,
    status           text NOT NULL DEFAULT 'scheduled'
                     CHECK (status IN ('scheduled', 'processing', 'completed', 'failed', 'cancelled')),
    stage            text NOT NULL DEFAULT 'none'
                     CHECK (stage IN ('none', 'db_prepared', 'storage_done')),
    requested_at     timestamptz NOT NULL DEFAULT now(),
    scheduled_for    timestamptz NOT NULL,
    locale           text NOT NULL DEFAULT 'ar' CHECK (locale IN ('ar', 'en', 'ur')),
    reason           text CHECK (char_length(reason) <= 500),
    attempts         integer NOT NULL DEFAULT 0,
    lease_expires_at timestamptz,
    last_error_code  text,
    notices_sent     text[] NOT NULL DEFAULT '{}',
    cancelled_at     timestamptz,
    completed_at     timestamptz,
    CONSTRAINT account_deletion_requests_user_required
        CHECK (user_id IS NOT NULL OR status = 'completed')
);

-- One active request per user; a double request finds the existing one.
CREATE UNIQUE INDEX uq_account_deletion_requests_active_user
    ON public.account_deletion_requests (user_id)
    WHERE status IN ('scheduled', 'processing', 'failed');
CREATE INDEX idx_account_deletion_requests_user ON public.account_deletion_requests (user_id);
CREATE INDEX idx_account_deletion_requests_due
    ON public.account_deletion_requests (scheduled_for)
    WHERE status IN ('scheduled', 'processing');

CREATE TABLE public.account_deletion_storage_queue (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id uuid NOT NULL REFERENCES public.account_deletion_requests(id) ON DELETE CASCADE,
    bucket     text NOT NULL,
    path       text NOT NULL,
    is_prefix  boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_account_deletion_storage_queue UNIQUE (request_id, bucket, path)
);

CREATE TABLE public.account_deletion_worker_runs (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at  timestamptz NOT NULL,
    finished_at timestamptz NOT NULL DEFAULT now(),
    claimed     integer NOT NULL DEFAULT 0,
    completed   integer NOT NULL DEFAULT 0,
    failed      integer NOT NULL DEFAULT 0
);

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_deletion_storage_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_deletion_worker_runs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.account_deletion_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.account_deletion_storage_queue FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.account_deletion_worker_runs FROM PUBLIC, anon, authenticated;

-- Household marks. No client grant: households UPDATE is column-listed.
ALTER TABLE public.households
    ADD COLUMN deletion_requested_at timestamptz,
    ADD COLUMN deletion_scheduled_for timestamptz,
    ADD COLUMN deletion_requested_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
CREATE INDEX idx_households_deletion_requested_by ON public.households (deletion_requested_by);

-- The public deletion form stores its requests as inquiries.
ALTER TABLE public.inquiries DROP CONSTRAINT IF EXISTS inquiries_type_check;
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_type_check
    CHECK (type IN ('vip_early_access', 'support', 'contact', 'account_deletion'));

-- ── Helpers and guards ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.account_deletion_user_pending(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.account_deletion_requests r
        WHERE r.user_id = p_user_id
          AND r.status IN ('scheduled', 'processing', 'failed')
    );
$$;

CREATE OR REPLACE FUNCTION public.account_deletion_guard_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- The ON CONFLICT of sync_user_household_membership lands here for existing members.
        IF EXISTS (SELECT 1 FROM public.household_memberships m
                   WHERE m.household_id = NEW.household_id AND m.user_id = NEW.user_id) THEN
            RETURN NEW;
        END IF;
        IF public.account_deletion_user_pending(NEW.user_id) THEN
            RAISE EXCEPTION 'This account is scheduled for deletion and cannot join a household'
                USING ERRCODE = '22023', HINT = 'account_pending_deletion';
        END IF;
        IF EXISTS (SELECT 1 FROM public.households h
                   WHERE h.id = NEW.household_id AND h.deletion_scheduled_for IS NOT NULL) THEN
            RAISE EXCEPTION 'This household is scheduled for deletion and takes no new members'
                USING ERRCODE = '22023', HINT = 'household_pending_deletion';
        END IF;
        RETURN NEW;
    END IF;

    -- The handover promotes a pending member only when nobody else is left.
    IF NEW.role = 'admin' AND OLD.role IS DISTINCT FROM 'admin'
       AND COALESCE(current_setting('app.account_deletion_handover', true), '') <> 'on'
       AND public.account_deletion_user_pending(NEW.user_id) THEN
        RAISE EXCEPTION 'This account is scheduled for deletion and cannot be promoted'
            USING ERRCODE = '22023', HINT = 'account_pending_deletion';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_deletion_guard_membership ON public.household_memberships;
CREATE TRIGGER trg_account_deletion_guard_membership
BEFORE INSERT OR UPDATE OF role ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.account_deletion_guard_membership();

CREATE OR REPLACE FUNCTION public.account_deletion_guard_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.households h
               WHERE h.id = NEW.household_id AND h.deletion_scheduled_for IS NOT NULL) THEN
        RAISE EXCEPTION 'This household is scheduled for deletion and takes no new invites'
            USING ERRCODE = '22023', HINT = 'household_pending_deletion';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_deletion_guard_invite ON public.household_invites;
CREATE TRIGGER trg_account_deletion_guard_invite
BEFORE INSERT ON public.household_invites
FOR EACH ROW EXECUTE FUNCTION public.account_deletion_guard_invite();

-- A trigger covers set_nafaqah_provider, transfer_primary_admin and the service role alike.
CREATE OR REPLACE FUNCTION public.account_deletion_guard_provider()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.nafaqah_provider_user_id IS NOT NULL
       AND NEW.nafaqah_provider_user_id IS DISTINCT FROM OLD.nafaqah_provider_user_id
       AND public.account_deletion_user_pending(NEW.nafaqah_provider_user_id) THEN
        RAISE EXCEPTION 'This account is scheduled for deletion and cannot become the Nafaqah provider'
            USING ERRCODE = '22023', HINT = 'account_pending_deletion';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_deletion_guard_provider ON public.households;
CREATE TRIGGER trg_account_deletion_guard_provider
BEFORE UPDATE OF nafaqah_provider_user_id ON public.households
FOR EACH ROW EXECUTE FUNCTION public.account_deletion_guard_provider();

CREATE OR REPLACE FUNCTION public.account_deletion_clear_marks_on_membership_end()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.households
    SET deletion_requested_at = NULL,
        deletion_scheduled_for = NULL,
        deletion_requested_by = NULL
    WHERE id = OLD.household_id
      AND deletion_requested_by = OLD.user_id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_deletion_clear_marks ON public.household_memberships;
CREATE TRIGGER trg_account_deletion_clear_marks
AFTER DELETE ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.account_deletion_clear_marks_on_membership_end();

-- ── Lifecycle functions that must know about pending users ──────────────────

CREATE OR REPLACE FUNCTION public.handover_households_on_user_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_hh record;
    v_successor uuid;
    v_new_owner uuid;
BEGIN
    -- The FK SET NULL could run before the membership cascade, leaving a mark nobody owns.
    UPDATE public.households
    SET deletion_requested_at = NULL,
        deletion_scheduled_for = NULL,
        deletion_requested_by = NULL
    WHERE deletion_requested_by = OLD.id;

    -- Lets account_deletion_guard_membership accept a last-resort promotion. Transaction
    -- scoped, reset below, and clients cannot set it: PostgREST exposes only public.
    PERFORM set_config('app.account_deletion_handover', 'on', true);

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
            ORDER BY public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
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
        ORDER BY public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
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

    PERFORM set_config('app.account_deletion_handover', '', true);

    -- A pool owned by someone who has already left: leave_household and remove_member
    -- do not re-own, so the loop above never sees it. Hand it to the household's admin.
    UPDATE public.accounts a
    SET owner_user_id = n.user_id,
        updated_at = now()
    FROM (
        SELECT DISTINCT ON (o.household_id) o.household_id, o.user_id
        FROM public.household_memberships o
        WHERE o.user_id <> OLD.id AND o.role = 'admin'
        ORDER BY o.household_id, public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
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

    -- Rows that only name this user, with no foreign key to take them along, for an account
    -- deleted out of band (the Auth dashboard). An open request stays: the worker closes it.
    DELETE FROM public.invite_attempt_log WHERE user_id = OLD.id;
    DELETE FROM public.account_deletion_requests WHERE user_id = OLD.id AND status = 'cancelled';

    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.maintain_household_primary_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.households h
        SET owner_user_id = (
            SELECT m.user_id
            FROM public.household_memberships m
            WHERE m.household_id = OLD.household_id
              AND m.user_id <> OLD.user_id
              AND m.role = 'admin'
            ORDER BY public.account_deletion_user_pending(m.user_id) ASC, m.created_at ASC, m.user_id ASC
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
$$;

CREATE OR REPLACE FUNCTION public.transfer_primary_admin(
    p_household_id uuid,
    p_new_primary_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

    IF public.account_deletion_user_pending(p_new_primary_user_id) THEN
        RAISE EXCEPTION 'This member is scheduled for deletion and cannot become the primary admin'
            USING ERRCODE = '22023', HINT = 'successor_pending_deletion';
    END IF;

    IF v_target_role <> 'admin' THEN
        PERFORM public.household_apply_role(p_household_id, p_new_primary_user_id, 'admin');
    END IF;

    -- The requester's deletion mark ends with their primary admin title.
    UPDATE public.households
    SET owner_user_id = p_new_primary_user_id,
        nafaqah_provider_user_id = COALESCE(
            nafaqah_provider_user_id,
            CASE WHEN household_type = 'family'
                      AND public.household_member_financial_role(p_household_id, p_new_primary_user_id) <> 'spouse'
                 THEN p_new_primary_user_id END
        ),
        deletion_requested_at = CASE WHEN deletion_requested_by = v_actor THEN NULL ELSE deletion_requested_at END,
        deletion_scheduled_for = CASE WHEN deletion_requested_by = v_actor THEN NULL ELSE deletion_scheduled_for END,
        deletion_requested_by = CASE WHEN deletion_requested_by = v_actor THEN NULL ELSE deletion_requested_by END
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
$$;

REVOKE ALL ON FUNCTION public.account_deletion_user_pending(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_guard_membership() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_guard_invite() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_guard_provider() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_clear_marks_on_membership_end() FROM PUBLIC, anon, authenticated;

COMMIT;
