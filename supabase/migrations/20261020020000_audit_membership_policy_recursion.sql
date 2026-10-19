-- ----------------------------------------------------------------------------
-- Migration: 20261020020000_audit_membership_policy_recursion.sql
-- Audit DB-02 (High): memberships_admin_manage (FOR ALL, role PUBLIC, from
--   20261018_household_memberships_and_switching.sql) selects from
--   household_memberships inside its own USING clause. Every authenticated read
--   of household_memberships, and every storage.objects receipts policy (which
--   consults the table), raised "infinite recursion detected in policy", i.e.
--   receipt upload/view was broken for all users. Had it evaluated, it would also
--   have let admins INSERT/UPDATE/DELETE membership rows directly, bypassing the
--   RPCs (remove_member, set_member_role, leave_household) that keep
--   users.household_id consistent.
-- Fix: drop it; expose read-only access through a SECURITY DEFINER helper
--   (no recursion); all writes stay in the SECURITY DEFINER RPCs.
-- Hardening: RLS helpers now require a live membership row for the active
--   household, so a stale users.household_id can never grant access.
-- Proof test: supabase/tests/09_audit_membership_policies.sql
-- ----------------------------------------------------------------------------

BEGIN;

-- 1. Non-recursive admin check
CREATE OR REPLACE FUNCTION public.is_household_admin(p_household_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        WHERE m.household_id = p_household_id
          AND m.user_id = auth.uid()
          AND m.role = 'admin'
    );
$$;

REVOKE EXECUTE ON FUNCTION public.is_household_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_household_admin(uuid) TO authenticated, service_role;

-- 2. Replace recursive / write-enabling policies with a single read policy
DROP POLICY IF EXISTS memberships_admin_manage ON public.household_memberships;
DROP POLICY IF EXISTS memberships_view_own ON public.household_memberships;
DROP POLICY IF EXISTS memberships_select_own_or_admin ON public.household_memberships;

CREATE POLICY memberships_select_own_or_admin ON public.household_memberships
    FOR SELECT
    TO authenticated
    USING (
        user_id = (SELECT auth.uid())
        OR public.is_household_admin(household_id)
    );

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.household_memberships FROM anon, authenticated;
REVOKE ALL ON public.household_memberships FROM anon;

-- 3. Backfill: every active household pointer must be backed by a membership
INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
SELECT u.household_id,
       u.id,
       COALESCE(u.role, 'member'),
       NOT EXISTS (SELECT 1 FROM public.household_memberships m2 WHERE m2.user_id = u.id)
FROM public.users u
WHERE u.household_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.household_memberships m
      WHERE m.user_id = u.id AND m.household_id = u.household_id
  )
ON CONFLICT (household_id, user_id) DO NOTHING;

-- 4. Membership-backed RLS helpers (signatures unchanged; policies keep working)
CREATE OR REPLACE FUNCTION public.get_auth_user_household_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.household_id
    FROM public.users u
    JOIN public.household_memberships m
      ON m.user_id = u.id
     AND m.household_id = u.household_id
    WHERE u.id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_auth_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT m.role
    FROM public.users u
    JOIN public.household_memberships m
      ON m.user_id = u.id
     AND m.household_id = u.household_id
    WHERE u.id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION public.get_auth_user_household_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_household_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_auth_user_role() TO authenticated, service_role;

COMMIT;
