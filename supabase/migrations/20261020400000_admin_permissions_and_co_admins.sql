-- =============================================================================
-- Admin permissions, co-admins and the household's primary admin
-- (owner decision on audit items DB-16 and DB-18; applies to family and
-- roommate households alike).
--
--   1. Transactions (DB-18). A member creates transactions and edits or deletes
--      only their own. Only a household admin edits or deletes another
--      member's transaction. The creator is bound at insert:
--      transactions.user_id = auth.uid() for client writes (filled in when an
--      older app build omits it, rejected when it names someone else) and it
--      can never be changed afterwards.
--   2. Shared pools (DB-16). Only a household admin moves money out of a shared
--      pool (transfer_between_accounts). Members still move money between
--      their own personal accounts and pay into the pool.
--   3. Co-admins. An admin promotes members to admin ("second admins") and
--      revokes that. The household's primary admin (households.owner_user_id,
--      backfilled from the longest-standing admin) cannot be demoted or removed
--      by a co-admin; only the primary admin transfers primary ownership. The
--      last-admin protections (BUG-03 / DB-12) are unchanged.
--   4. Family Nafaqah keeps its rules: the husband or any household admin
--      (co-admins included, never the wife herself) sets the wife's allowance.
--      The husband is now resolved preferring the primary admin.
--
-- Role changes happen only through the SECURITY DEFINER RPCs below (clients
-- hold no write privilege on household_memberships, users.role or
-- households.owner_user_id). Every RPC pins search_path, checks the caller and
-- scopes to the household. The service role acts for a verified user by
-- passing p_actor_user_id; an authenticated caller can never act for anyone
-- else.
--
-- Not changed here: DB-17 (households.invite_code column revoke). Column
-- privileges cannot be limited to non-admins, and released app builds read
-- households.name, invite_code directly to render the whole household settings
-- section, so the revoke would break that screen for every user of an older
-- build. It ships once those builds are retired (see docs/review/audit/db.md).
-- =============================================================================

-- 1. Primary admin -------------------------------------------------------------
ALTER TABLE public.households
    ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.households.owner_user_id IS
    'Primary admin: always an admin member. Co-admins cannot demote or remove them; only they transfer it (transfer_primary_admin).';

CREATE INDEX IF NOT EXISTS idx_households_owner_user_id
    ON public.households (owner_user_id) WHERE owner_user_id IS NOT NULL;

-- Backfill: the longest-standing admin of each household.
UPDATE public.households h
SET owner_user_id = (
    SELECT m.user_id
    FROM public.household_memberships m
    WHERE m.household_id = h.id AND m.role = 'admin'
    ORDER BY m.created_at ASC, m.user_id ASC
    LIMIT 1
)
WHERE h.owner_user_id IS NULL;

-- Clients may keep updating household settings (admins only, via RLS) but never
-- the primary admin: replace the table-wide UPDATE grant by a column list.
DO $$
DECLARE
    v_cols text;
BEGIN
    SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum) INTO v_cols
    FROM pg_attribute
    WHERE attrelid = 'public.households'::regclass
      AND attnum > 0
      AND NOT attisdropped
      AND attname <> 'owner_user_id';

    REVOKE UPDATE ON public.households FROM PUBLIC, anon, authenticated;
    EXECUTE format('GRANT UPDATE (%s) ON public.households TO authenticated', v_cols);
END $$;

-- 2. Helpers ---------------------------------------------------------------------
-- Acting user: the JWT subject, or (service role only, no JWT subject) p_actor_user_id.
CREATE OR REPLACE FUNCTION public.household_resolve_actor(p_actor_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NOT NULL AND p_actor_user_id IS NOT NULL AND p_actor_user_id IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'Forbidden: cannot act on behalf of another user' USING ERRCODE = '42501';
    END IF;
    v_uid := COALESCE(v_uid, p_actor_user_id);
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    RETURN v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.household_member_role(p_household_id uuid, p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT m.role
    FROM public.household_memberships m
    WHERE m.household_id = p_household_id AND m.user_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.household_primary_admin_id(p_household_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT h.owner_user_id FROM public.households h WHERE h.id = p_household_id;
$$;

REVOKE EXECUTE ON FUNCTION public.household_resolve_actor(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.household_member_role(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.household_primary_admin_id(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.household_primary_admin_id(uuid) TO authenticated, service_role;

-- 3. Primary-admin invariants on memberships --------------------------------------
-- The primary admin is never demoted (transfer first), and only they can end
-- their own membership (leave / remove themselves / delete their account).
CREATE OR REPLACE FUNCTION public.protect_primary_admin_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_owner uuid := public.household_primary_admin_id(OLD.household_id);
    v_uid uuid := auth.uid();
BEGIN
    IF v_owner IS NULL OR OLD.user_id IS DISTINCT FROM v_owner THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.role = 'admin' AND NEW.role IS DISTINCT FROM 'admin' THEN
            RAISE EXCEPTION 'The primary admin cannot be demoted; transfer primary admin to another member first'
                USING ERRCODE = '42501';
        END IF;
        RETURN NEW;
    END IF;

    IF v_uid IS NOT NULL AND v_uid IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'Only the primary admin can remove themselves from the household'
            USING ERRCODE = '42501';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_primary_admin ON public.household_memberships;
CREATE TRIGGER trg_protect_primary_admin
BEFORE UPDATE OF role OR DELETE ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.protect_primary_admin_membership();

-- The first admin of a household becomes its primary admin; when the primary
-- admin's membership ends, the longest-standing remaining admin takes over
-- (DB-12 handover already promotes one when they were the sole admin).
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
            ORDER BY m.created_at ASC, m.user_id ASC
            LIMIT 1
        )
        WHERE h.id = OLD.household_id
          AND (h.owner_user_id IS NULL OR h.owner_user_id = OLD.user_id);
        RETURN OLD;
    END IF;

    IF NEW.role = 'admin' THEN
        UPDATE public.households
        SET owner_user_id = NEW.user_id
        WHERE id = NEW.household_id AND owner_user_id IS NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_maintain_primary_admin ON public.household_memberships;
CREATE TRIGGER trg_maintain_primary_admin
AFTER INSERT OR UPDATE OF role OR DELETE ON public.household_memberships
FOR EACH ROW EXECUTE FUNCTION public.maintain_household_primary_admin();

REVOKE EXECUTE ON FUNCTION public.protect_primary_admin_membership() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.maintain_household_primary_admin() FROM PUBLIC, anon, authenticated;

-- 4. Role management RPCs -----------------------------------------------------------
-- Members of a household with their roles (any member may read; same data the
-- users_select_household policy already exposes, plus the membership role).
CREATE OR REPLACE FUNCTION public.get_household_members(
    p_household_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS TABLE (
    user_id uuid,
    display_name text,
    role text,
    financial_role text,
    is_primary boolean,
    joined_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
BEGIN
    IF p_household_id IS NULL OR public.household_member_role(p_household_id, v_actor) IS NULL THEN
        RAISE EXCEPTION 'Forbidden: not a member of this household' USING ERRCODE = '42501';
    END IF;
    v_owner := public.household_primary_admin_id(p_household_id);

    RETURN QUERY
    SELECT m.user_id,
           u.display_name,
           m.role,
           u.financial_role,
           (m.user_id = v_owner) AS is_primary,
           m.created_at AS joined_at
    FROM public.household_memberships m
    JOIN public.users u ON u.id = m.user_id
    WHERE m.household_id = p_household_id
    ORDER BY (m.user_id = v_owner) DESC, (m.role = 'admin') DESC, m.created_at ASC, m.user_id ASC;
END;
$$;

-- Internal: set a member's role in one household (membership + cached users.role).
CREATE OR REPLACE FUNCTION public.household_apply_role(p_household_id uuid, p_user_id uuid, p_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.household_memberships
    SET role = p_role
    WHERE household_id = p_household_id AND user_id = p_user_id;

    UPDATE public.users
    SET role = p_role
    WHERE id = p_user_id AND household_id = p_household_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.household_apply_role(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.household_require_admin(p_household_id uuid, p_actor uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text := public.household_member_role(p_household_id, p_actor);
BEGIN
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Forbidden: not a member of this household' USING ERRCODE = '42501';
    END IF;
    IF v_role <> 'admin' THEN
        RAISE EXCEPTION 'Forbidden: household admin privileges required' USING ERRCODE = '42501';
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.household_require_admin(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Any admin (primary or co-admin) makes another member an admin.
CREATE OR REPLACE FUNCTION public.promote_member_to_admin(
    p_household_id uuid,
    p_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_target_role text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    SELECT m.role INTO v_target_role
    FROM public.household_memberships m
    WHERE m.household_id = p_household_id AND m.user_id = p_user_id
    FOR UPDATE;

    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;

    IF v_target_role <> 'admin' THEN
        PERFORM public.household_apply_role(p_household_id, p_user_id, 'admin');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'user_id', p_user_id,
        'role', 'admin',
        'is_primary', p_user_id = public.household_primary_admin_id(p_household_id)
    );
END;
$$;

-- Any admin revokes a co-admin (themselves included), never the primary admin;
-- the last remaining admin cannot be demoted (BUG-03 trigger).
CREATE OR REPLACE FUNCTION public.revoke_admin(
    p_household_id uuid,
    p_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_target_role text;
BEGIN
    PERFORM public.household_require_admin(p_household_id, v_actor);

    -- Serialise concurrent role changes in this household.
    PERFORM 1 FROM public.households WHERE id = p_household_id FOR UPDATE;

    SELECT m.role INTO v_target_role
    FROM public.household_memberships m
    WHERE m.household_id = p_household_id AND m.user_id = p_user_id;

    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not a member of this household' USING ERRCODE = 'P0002';
    END IF;

    IF p_user_id = public.household_primary_admin_id(p_household_id) THEN
        RAISE EXCEPTION 'The primary admin cannot be demoted; transfer primary admin to another member first'
            USING ERRCODE = '42501';
    END IF;

    IF v_target_role = 'admin' THEN
        PERFORM public.household_apply_role(p_household_id, p_user_id, 'member');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'user_id', p_user_id,
        'role', 'member',
        'is_primary', false
    );
END;
$$;

-- Only the primary admin hands primary ownership to another member (who is
-- made an admin if needed). The previous primary admin stays a co-admin.
CREATE OR REPLACE FUNCTION public.transfer_primary_admin(
    p_household_id uuid,
    p_new_primary_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.household_resolve_actor(p_actor_user_id);
    v_owner uuid;
    v_target_role text;
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
    SET owner_user_id = p_new_primary_user_id
    WHERE id = p_household_id;

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'primary_admin_user_id', p_new_primary_user_id,
        'previous_primary_admin_user_id', v_actor
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_household_members(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.promote_member_to_admin(uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.revoke_admin(uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.transfer_primary_admin(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_household_members(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.promote_member_to_admin(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_admin(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transfer_primary_admin(uuid, uuid, uuid) TO authenticated, service_role;

-- Existing role RPCs (active household) keep working and respect the primary admin.
CREATE OR REPLACE FUNCTION public.set_member_role(p_user_id uuid, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid uuid := auth.uid();
    v_caller_hh_id uuid;
BEGIN
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT household_id INTO v_caller_hh_id
    FROM public.users
    WHERE id = v_caller_uid;

    IF v_caller_hh_id IS NULL OR public.household_member_role(v_caller_hh_id, v_caller_uid) IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    IF p_role NOT IN ('admin', 'member') THEN
        RAISE EXCEPTION 'Invalid role: must be admin or member';
    END IF;

    IF p_role = 'admin' THEN
        RETURN public.promote_member_to_admin(v_caller_hh_id, p_user_id, NULL)
            || jsonb_build_object('new_role', 'admin');
    END IF;
    RETURN public.revoke_admin(v_caller_hh_id, p_user_id, NULL)
        || jsonb_build_object('new_role', 'member');
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

-- get_user_households(): also reports whether the caller is the primary admin.
-- (Return type changes, so the function is re-created; the invite code is still
-- served to admins only.)
DROP FUNCTION IF EXISTS public.get_user_households();
CREATE FUNCTION public.get_user_households()
RETURNS TABLE (
    household_id uuid,
    household_name text,
    invite_code text,
    role text,
    is_active boolean,
    is_primary boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT
        h.id AS household_id,
        h.name::text AS household_name,
        CASE WHEN m.role = 'admin' THEN h.invite_code::text ELSE NULL END AS invite_code,
        m.role::text,
        (h.id = u.household_id) AS is_active,
        (h.owner_user_id = m.user_id) AS is_primary
    FROM public.household_memberships m
    JOIN public.households h ON h.id = m.household_id
    JOIN public.users u ON u.id = m.user_id
    WHERE m.user_id = auth.uid()
    ORDER BY is_active DESC, m.created_at ASC;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_user_households() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_households() TO authenticated, service_role;

-- 5. Transactions: creator binding and owner-or-admin writes (DB-18) ------------------
-- Older app builds insert without user_id: the creator is filled in from the
-- JWT. Naming anyone else is rejected. Service-role writes (no JWT subject)
-- are checked by ai_service, which passes the verified user.
CREATE OR REPLACE FUNCTION public.bind_transaction_creator()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.user_id IS NULL THEN
        NEW.user_id := v_uid;
    ELSIF NEW.user_id <> v_uid THEN
        RAISE EXCEPTION 'Forbidden: a transaction cannot be created on behalf of another member'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

-- Edits and deletes of another member's transaction need a household admin.
-- Raised (HTTP 403) rather than filtered out by RLS so that clients, including
-- older builds, report the refusal instead of a silent no-op. Writes issued by
-- other triggers (pg_trigger_depth() > 1: foreign-key ON DELETE SET NULL /
-- CASCADE when an account, spouse or household is deleted) are system-driven
-- and pass; the service role (no JWT subject) is checked by ai_service.
CREATE OR REPLACE FUNCTION public.enforce_transaction_write_permission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL OR pg_trigger_depth() > 1 THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'Forbidden: the creator of a transaction cannot be changed' USING ERRCODE = '42501';
    END IF;

    IF OLD.user_id IS DISTINCT FROM v_uid
       AND public.household_member_role(OLD.household_id, v_uid) IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Forbidden: only household admins can edit or delete another member''s transactions'
            USING ERRCODE = '42501';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.bind_transaction_creator() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enforce_transaction_write_permission() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_bind_transaction_creator ON public.transactions;
CREATE TRIGGER trg_bind_transaction_creator
BEFORE INSERT ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.bind_transaction_creator();

DROP TRIGGER IF EXISTS trg_enforce_transaction_write_permission ON public.transactions;
CREATE TRIGGER trg_enforce_transaction_write_permission
BEFORE UPDATE OR DELETE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.enforce_transaction_write_permission();

DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
CREATE POLICY "transactions_insert_household" ON public.transactions
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = (SELECT public.get_auth_user_household_id())
        AND user_id = (SELECT auth.uid())
        AND (
            account_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.accounts a
                WHERE a.id = transactions.account_id
                  AND a.household_id = transactions.household_id
                  AND (a.is_shared_pool = true OR a.owner_user_id = (SELECT auth.uid()))
            )
        )
    );

-- A transaction's account is a shared pool of its household or a personal
-- account of the transaction's creator. Definer: an admin editing a member's
-- transaction cannot read that member's personal account under RLS.
CREATE OR REPLACE FUNCTION public.transaction_account_matches(
    p_account_id uuid,
    p_household_id uuid,
    p_creator_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = p_account_id
          AND a.household_id = p_household_id
          AND (a.is_shared_pool = true OR a.owner_user_id = p_creator_user_id)
    );
$$;
REVOKE EXECUTE ON FUNCTION public.transaction_account_matches(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transaction_account_matches(uuid, uuid, uuid) TO authenticated, service_role;

-- USING keeps household scoping (the row is visible to the trigger, which
-- raises for a non-admin); WITH CHECK repeats the owner-or-admin rule and keeps
-- a personal account attached only to its owner's transactions.
DROP POLICY IF EXISTS "transactions_update_household" ON public.transactions;
CREATE POLICY "transactions_update_household" ON public.transactions
    FOR UPDATE TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()))
    WITH CHECK (
        household_id = (SELECT public.get_auth_user_household_id())
        AND (user_id = (SELECT auth.uid()) OR (SELECT public.get_auth_user_role()) = 'admin')
        AND (
            account_id IS NULL
            OR public.transaction_account_matches(account_id, household_id, user_id)
        )
    );

DROP POLICY IF EXISTS "transactions_delete_household" ON public.transactions;
CREATE POLICY "transactions_delete_household" ON public.transactions
    FOR DELETE TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

-- Account balances follow a transaction's edits and deletes. A personal
-- account is touched only by its owner, or - for that owner's own transaction -
-- by a household admin exercising the edit/delete right above. Nobody can
-- attach a transaction to someone else's personal account.
CREATE OR REPLACE FUNCTION public.transaction_personal_account_writable(
    p_account public.accounts,
    p_creator_user_id uuid,
    p_caller_uid uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT p_caller_uid IS NULL
        OR p_account.is_shared_pool
        OR p_account.owner_user_id = p_caller_uid
        OR (
            p_account.owner_user_id = p_creator_user_id
            AND public.household_member_role(p_account.household_id, p_caller_uid) = 'admin'
        );
$$;
REVOKE EXECUTE ON FUNCTION public.transaction_personal_account_writable(public.accounts, uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_account_balance_on_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_acc public.accounts%ROWTYPE;
    v_caller_uid UUID;
BEGIN
    BEGIN
        v_caller_uid := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_caller_uid := NULL;
    END;
    IF TG_OP = 'INSERT' THEN
        IF NEW.account_id IS NOT NULL THEN
            SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id FOR UPDATE;
            IF v_acc.id IS NULL THEN
                RAISE EXCEPTION 'Target account % not found', NEW.account_id USING ERRCODE = 'P0002';
            END IF;
            IF v_acc.household_id <> NEW.household_id THEN
                RAISE EXCEPTION 'Account % does not belong to transaction household %', NEW.account_id, NEW.household_id USING ERRCODE = '42501';
            END IF;
            IF v_caller_uid IS NOT NULL AND v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid THEN
                RAISE EXCEPTION 'Access denied: cannot debit personal account owned by another user' USING ERRCODE = '42501';
            END IF;

            UPDATE public.accounts
            SET balance = balance - NEW.amount,
                updated_at = now()
            WHERE id = NEW.account_id;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.account_id IS NOT NULL THEN
            SELECT * INTO v_acc FROM public.accounts WHERE id = OLD.account_id FOR UPDATE;
            IF v_acc.id IS NOT NULL THEN
                IF v_acc.household_id <> OLD.household_id THEN
                    RAISE EXCEPTION 'Account % does not belong to transaction household %', OLD.account_id, OLD.household_id USING ERRCODE = '42501';
                END IF;
                IF NOT public.transaction_personal_account_writable(v_acc, OLD.user_id, v_caller_uid) THEN
                    RAISE EXCEPTION 'Access denied: cannot credit personal account owned by another user' USING ERRCODE = '42501';
                END IF;

                UPDATE public.accounts
                SET balance = balance + OLD.amount,
                    updated_at = now()
                WHERE id = OLD.account_id;
            END IF;
        END IF;
        RETURN OLD;

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.account_id IS DISTINCT FROM NEW.account_id OR OLD.amount <> NEW.amount THEN
            -- Revert old account debit
            IF OLD.account_id IS NOT NULL THEN
                SELECT * INTO v_acc FROM public.accounts WHERE id = OLD.account_id FOR UPDATE;
                IF v_acc.id IS NOT NULL THEN
                    IF v_acc.household_id <> OLD.household_id THEN
                        RAISE EXCEPTION 'Account % does not belong to transaction household %', OLD.account_id, OLD.household_id USING ERRCODE = '42501';
                    END IF;
                    IF NOT public.transaction_personal_account_writable(v_acc, OLD.user_id, v_caller_uid) THEN
                        RAISE EXCEPTION 'Access denied: cannot credit personal account owned by another user' USING ERRCODE = '42501';
                    END IF;

                    UPDATE public.accounts
                    SET balance = balance + OLD.amount,
                        updated_at = now()
                    WHERE id = OLD.account_id;
                END IF;
            END IF;

            -- Apply new account debit
            IF NEW.account_id IS NOT NULL THEN
                SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id FOR UPDATE;
                IF v_acc.id IS NULL THEN
                    RAISE EXCEPTION 'Target account % not found', NEW.account_id USING ERRCODE = 'P0002';
                END IF;
                IF v_acc.household_id <> NEW.household_id THEN
                    RAISE EXCEPTION 'Account % does not belong to transaction household %', NEW.account_id, NEW.household_id USING ERRCODE = '42501';
                END IF;
                IF NOT public.transaction_personal_account_writable(v_acc, NEW.user_id, v_caller_uid) THEN
                    RAISE EXCEPTION 'Access denied: cannot debit personal account owned by another user' USING ERRCODE = '42501';
                END IF;

                UPDATE public.accounts
                SET balance = balance - NEW.amount,
                    updated_at = now()
                WHERE id = NEW.account_id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_account_balance_on_transaction() FROM PUBLIC, anon, authenticated;

-- 6. Shared pools: only admins move money out (DB-16) --------------------------------
CREATE OR REPLACE FUNCTION public.transfer_between_accounts(
    p_household_id uuid,
    p_from_account_id uuid,
    p_to_account_id uuid,
    p_amount numeric,
    p_fee numeric DEFAULT 0.0,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid UUID;
    v_from_acc RECORD;
    v_to_acc RECORD;
    v_total_deduction NUMERIC;
    v_transfer_id UUID;
    v_created_at TIMESTAMPTZ := now();
    v_result jsonb;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive' USING ERRCODE = '22023';
    END IF;

    IF p_fee IS NULL OR p_fee < 0 THEN
        RAISE EXCEPTION 'Transfer fee cannot be negative' USING ERRCODE = '22023';
    END IF;

    -- Columns are NUMERIC(14,2)/(10,2): a third decimal would be rounded
    -- independently on each side of the transfer and mint or burn money.
    IF p_amount <> round(p_amount, 2) OR p_fee <> round(p_fee, 2) THEN
        RAISE EXCEPTION 'Transfer amount and fee must have at most 2 decimal places' USING ERRCODE = '22023';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'Cannot transfer between the same account' USING ERRCODE = '22023';
    END IF;

    -- Strict NULL-safe membership check
    IF p_household_id IS NULL OR public.get_auth_user_household_id() IS NULL OR p_household_id IS DISTINCT FROM public.get_auth_user_household_id() THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to specified household' USING ERRCODE = '42501';
    END IF;

    -- Lock accounts in deterministic UUID order to prevent deadlocks
    IF p_from_account_id < p_to_account_id THEN
        SELECT * INTO v_from_acc FROM public.accounts WHERE id = p_from_account_id FOR UPDATE;
        SELECT * INTO v_to_acc FROM public.accounts WHERE id = p_to_account_id FOR UPDATE;
    ELSE
        SELECT * INTO v_to_acc FROM public.accounts WHERE id = p_to_account_id FOR UPDATE;
        SELECT * INTO v_from_acc FROM public.accounts WHERE id = p_from_account_id FOR UPDATE;
    END IF;

    IF v_from_acc.id IS NULL THEN
        RAISE EXCEPTION 'Source account not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_to_acc.id IS NULL THEN
        RAISE EXCEPTION 'Destination account not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_from_acc.household_id <> p_household_id OR v_to_acc.household_id <> p_household_id THEN
        RAISE EXCEPTION 'Both accounts must belong to the household' USING ERRCODE = '42501';
    END IF;

    -- Personal source: only its owner. Shared pool source: only a household admin (DB-16).
    IF v_from_acc.is_shared_pool = false AND v_from_acc.owner_user_id <> v_caller_uid THEN
        RAISE EXCEPTION 'Access denied: cannot transfer from an account owned by another user' USING ERRCODE = '42501';
    END IF;
    IF v_from_acc.is_shared_pool = true
       AND public.household_member_role(p_household_id, v_caller_uid) IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Forbidden: only household admins can move money out of a shared pool' USING ERRCODE = '42501';
    END IF;

    v_total_deduction := p_amount + p_fee;
    IF v_from_acc.balance < v_total_deduction THEN
        RAISE EXCEPTION 'Insufficient funds: balance (%) is less than transfer plus fee (%)', v_from_acc.balance, v_total_deduction USING ERRCODE = '22000';
    END IF;

    UPDATE public.accounts
    SET balance = balance - v_total_deduction,
        updated_at = v_created_at
    WHERE id = p_from_account_id;

    UPDATE public.accounts
    SET balance = balance + p_amount,
        updated_at = v_created_at
    WHERE id = p_to_account_id;

    INSERT INTO public.account_transfers (
        household_id,
        user_id,
        from_account_id,
        to_account_id,
        amount,
        fee,
        timestamp,
        notes,
        created_at
    ) VALUES (
        p_household_id,
        v_caller_uid,
        p_from_account_id,
        p_to_account_id,
        p_amount,
        p_fee,
        v_created_at,
        p_notes,
        v_created_at
    ) RETURNING id INTO v_transfer_id;

    SELECT jsonb_build_object(
        'id', v_transfer_id,
        'household_id', p_household_id,
        'user_id', v_caller_uid,
        'from_account_id', p_from_account_id,
        'to_account_id', p_to_account_id,
        'amount', p_amount,
        'fee', p_fee,
        'timestamp', v_created_at,
        'notes', p_notes,
        'created_at', v_created_at
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- 7. Family Nafaqah: the husband is the provider member, preferring the primary
--    admin, then any admin, then the longest-standing membership.
CREATE OR REPLACE FUNCTION public.nafaqah_husband_id(p_household_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT m.user_id
    FROM public.household_memberships m
    JOIN public.users u ON u.id = m.user_id
    JOIN public.households h ON h.id = m.household_id
    WHERE m.household_id = p_household_id
      AND COALESCE(u.financial_role, 'provider') = 'provider'
      AND EXISTS (
          SELECT 1
          FROM public.household_memberships sm
          JOIN public.users su ON su.id = sm.user_id
          WHERE sm.household_id = p_household_id AND su.financial_role = 'spouse'
      )
    ORDER BY (m.user_id = h.owner_user_id) DESC NULLS LAST, (m.role = 'admin') DESC, m.created_at, m.user_id
    LIMIT 1;
$$;
