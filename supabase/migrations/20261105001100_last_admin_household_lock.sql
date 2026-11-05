-- ============================================================================
-- Migration: 20261105001100_last_admin_household_lock.sql
--
-- A household could be left with members and no admin: a co-admin's account purge and the
-- primary admin leaving, at the same time, each counted the other as the admin who stays.
-- check_last_admin_membership counted what its own snapshot showed, and nothing made the two
-- removals wait for each other.
--
-- 1. check_last_admin_membership (the BUG-03 backstop trigger) locks the household row
--    (SELECT ... FOR UPDATE) before it counts the other admins, so removals and demotions of
--    admins in one household run one at a time, and each counts what the one before committed.
-- 2. leave_household and remove_member lock the household row before they touch a membership.
--    The trigger fires only after its membership row is locked, so without this a member
--    leaving would hold that row and wait for the household, while a purge deleting the
--    household holds the household and waits for that row: a deadlock. Locking the household
--    first is the order every other path already takes: prepare_account_purge,
--    account_deletion_schedule, transfer_primary_admin and revoke_admin lock the household
--    before any membership.
--
-- Both functions are otherwise exactly as last defined (leave_household in 20261019030000,
-- remove_member in 20261020400000). No data changes. Safe to run again.
--
-- Rollback: re-run the check_last_admin_membership definition in section 4 of
-- 20261019030000, the leave_household definition in 20261019030000, and the remove_member
-- definition in 20261020400000.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.check_last_admin_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_other_admins int;
    v_other_members int;
BEGIN
    IF OLD.role = 'admin' AND (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW.role <> 'admin')) THEN
        -- One admin removal per household at a time; the count below then sees the last one.
        PERFORM 1 FROM public.households WHERE id = OLD.household_id FOR UPDATE;

        SELECT count(*) INTO v_other_admins
        FROM public.household_memberships
        WHERE household_id = OLD.household_id AND role = 'admin' AND user_id <> OLD.user_id;

        IF v_other_admins = 0 THEN
            IF TG_OP = 'DELETE' THEN
                SELECT count(*) INTO v_other_members
                FROM public.household_memberships
                WHERE household_id = OLD.household_id AND user_id <> OLD.user_id;

                IF v_other_members > 0 THEN
                    RAISE EXCEPTION 'Cannot remove the sole admin while other household members remain';
                END IF;
            ELSE
                RAISE EXCEPTION 'Cannot demote the sole admin of a household';
            END IF;
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.check_last_admin_membership() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.leave_household()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_hh_id uuid;
    v_role text;
    v_other_admins int;
    v_other_members int;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT household_id, role INTO v_hh_id, v_role
    FROM public.users
    WHERE id = v_uid;

    IF v_hh_id IS NULL THEN
        SELECT household_id, role INTO v_hh_id, v_role
        FROM public.household_memberships
        WHERE user_id = v_uid
        LIMIT 1;
    END IF;

    IF v_hh_id IS NULL THEN
        RETURN jsonb_build_object('success', true, 'message', 'User is not in any household');
    END IF;

    -- The household before the membership, as every other path takes them.
    PERFORM 1 FROM public.households WHERE id = v_hh_id FOR UPDATE;

    -- Last admin check: sole admin cannot leave if other members remain
    SELECT count(*) INTO v_other_admins
    FROM public.household_memberships
    WHERE household_id = v_hh_id AND role = 'admin' AND user_id <> v_uid;

    SELECT count(*) INTO v_other_members
    FROM public.household_memberships
    WHERE household_id = v_hh_id AND user_id <> v_uid;

    IF v_role = 'admin' AND v_other_admins = 0 AND v_other_members > 0 THEN
        RAISE EXCEPTION 'Sole admin cannot leave while other members remain. Promote another member to admin first.';
    END IF;

    -- Delete membership
    DELETE FROM public.household_memberships
    WHERE household_id = v_hh_id AND user_id = v_uid;

    -- Reset active household
    UPDATE public.users
    SET household_id = NULL,
        role = 'member'
    WHERE id = v_uid;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', v_hh_id,
        'message', 'Successfully left household'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_member(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid uuid := auth.uid();
    v_caller_hh_id uuid;
    v_target_role text;
    v_other_admins int;
    v_other_members int;
BEGIN
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT household_id INTO v_caller_hh_id
    FROM public.users
    WHERE id = v_caller_uid;

    -- The household before the membership, as every other path takes them.
    IF v_caller_hh_id IS NOT NULL THEN
        PERFORM 1 FROM public.households WHERE id = v_caller_hh_id FOR UPDATE;
    END IF;

    IF v_caller_hh_id IS NULL OR public.household_member_role(v_caller_hh_id, v_caller_uid) IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    v_target_role := public.household_member_role(v_caller_hh_id, p_user_id);
    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household';
    END IF;

    IF p_user_id <> v_caller_uid AND p_user_id = public.household_primary_admin_id(v_caller_hh_id) THEN
        RAISE EXCEPTION 'Only the primary admin can remove themselves from the household' USING ERRCODE = '42501';
    END IF;

    IF p_user_id = v_caller_uid THEN
        SELECT count(*) INTO v_other_admins
        FROM public.household_memberships
        WHERE household_id = v_caller_hh_id AND role = 'admin' AND user_id <> p_user_id;

        SELECT count(*) INTO v_other_members
        FROM public.household_memberships
        WHERE household_id = v_caller_hh_id AND user_id <> p_user_id;

        IF v_other_admins = 0 AND v_other_members > 0 THEN
            RAISE EXCEPTION 'Sole admin cannot be removed while other members remain. Promote another member first.';
        END IF;
    END IF;

    DELETE FROM public.household_memberships
    WHERE household_id = v_caller_hh_id AND user_id = p_user_id;

    UPDATE public.users
    SET household_id = NULL,
        role = 'member'
    WHERE id = p_user_id AND household_id = v_caller_hh_id;

    RETURN jsonb_build_object(
        'success', true,
        'removed_user_id', p_user_id
    );
END;
$$;

COMMIT;
