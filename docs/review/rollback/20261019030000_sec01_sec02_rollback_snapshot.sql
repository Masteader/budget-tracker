-- Rollback Snapshot for 20261019030000_sec01_sec02_household_takeover_prevention.sql
-- Captured from live production state before applying SEC-01 & SEC-02 hardening.

BEGIN;

-- 1. Restore users policies and table grants
DROP POLICY IF EXISTS users_update_own_profile ON public.users;
DROP POLICY IF EXISTS users_update_own_or_admin ON public.users;
CREATE POLICY users_update_own_or_admin ON public.users
    FOR UPDATE TO public
    USING (((id = auth.uid()) OR ((get_auth_user_role() = 'admin'::text) AND (household_id = get_auth_user_household_id()))));

DROP POLICY IF EXISTS users_insert_own ON public.users;
CREATE POLICY users_insert_own ON public.users
    FOR INSERT TO public
    WITH CHECK (id = auth.uid());

GRANT UPDATE ON public.users TO authenticated, anon;

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_financial_role_check;

-- 2. Restore household_invites policies
DROP POLICY IF EXISTS invites_select_household ON public.household_invites;
CREATE POLICY invites_select_household ON public.household_invites
    FOR SELECT TO public
    USING (true);

DROP POLICY IF EXISTS invites_insert_household ON public.household_invites;
CREATE POLICY invites_insert_household ON public.household_invites
    FOR INSERT TO public
    WITH CHECK (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

-- 3. Restore cost_control_codes policies & constraint
CREATE POLICY cost_control_codes_select_authenticated ON public.cost_control_codes
    FOR SELECT TO public
    USING (auth.role() = 'authenticated'::text);

-- 4. Restore function execute grants to PUBLIC and anon
GRANT EXECUTE ON FUNCTION public.create_household_and_claim(text) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_household_by_code(text) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.switch_active_household(uuid) TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_households() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_household_id() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_role() TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.handle_new_auth_user() TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_user_household_membership() TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_budget_on_transaction() TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_budget_on_transaction_delete() TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_budget_on_transaction_update() TO PUBLIC, anon, authenticated;

-- 5. Drop new RPCs if created
DROP FUNCTION IF EXISTS public.leave_household();
DROP FUNCTION IF EXISTS public.set_member_role(uuid, text);
DROP FUNCTION IF EXISTS public.remove_member(uuid);
DROP FUNCTION IF EXISTS public.revoke_invite(text);
DROP TABLE IF EXISTS public.invite_attempt_log;

COMMIT;
