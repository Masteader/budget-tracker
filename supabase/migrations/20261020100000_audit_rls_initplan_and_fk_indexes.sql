-- ----------------------------------------------------------------------------
-- Migration: 20261020100000_audit_rls_initplan_and_fk_indexes.sql
-- Audit DB-13 (Low, performance): RLS policies call auth.uid(),
--   get_auth_user_household_id() and get_auth_user_role() directly, so they are
--   evaluated per row (transactions_select_household also re-parses the JWT
--   claims per row via "auth.uid() IS NOT NULL"; 50k rows ~= 50 ms of pure
--   policy overhead). Wrapping each call in a scalar sub-select makes it a
--   one-off InitPlan (Supabase linter: auth_rls_initplan). Policy semantics are
--   unchanged except that the legacy "household_id IN (SELECT household_id FROM
--   users WHERE id = auth.uid())" form now goes through the membership-backed
--   helper (20261020020000), and the receipts storage policies no longer accept
--   a stale users.household_id without a membership row.
--   Missing indexes: 6 foreign keys (incl. user_id columns scanned by the
--   account-deletion cascade) and the invite lockout lookup.
-- Proof test: supabase/tests/17_audit_rls_performance.sql
-- ----------------------------------------------------------------------------

BEGIN;

-- transactions

DROP POLICY IF EXISTS "transactions_select_household" ON public.transactions;
CREATE POLICY "transactions_select_household" ON public.transactions
    FOR SELECT
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
CREATE POLICY "transactions_insert_household" ON public.transactions
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id())
        AND (
            account_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.accounts a
                WHERE a.id = transactions.account_id
                  AND a.household_id = transactions.household_id
                  AND (a.is_shared_pool = true OR a.owner_user_id = (SELECT auth.uid()))
            )
        ));

DROP POLICY IF EXISTS "transactions_update_household" ON public.transactions;
CREATE POLICY "transactions_update_household" ON public.transactions
    FOR UPDATE
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()))
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id())
        AND (
            account_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.accounts a
                WHERE a.id = transactions.account_id
                  AND a.household_id = transactions.household_id
                  AND (a.is_shared_pool = true OR a.owner_user_id = (SELECT auth.uid()))
            )
        ));

DROP POLICY IF EXISTS "transactions_delete_household" ON public.transactions;
CREATE POLICY "transactions_delete_household" ON public.transactions
    FOR DELETE
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

-- budgets

DROP POLICY IF EXISTS "budgets_select_household" ON public.budgets;
CREATE POLICY "budgets_select_household" ON public.budgets
    FOR SELECT
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "budgets_insert_admin" ON public.budgets;
CREATE POLICY "budgets_insert_admin" ON public.budgets
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin');

DROP POLICY IF EXISTS "budgets_update_admin" ON public.budgets;
CREATE POLICY "budgets_update_admin" ON public.budgets
    FOR UPDATE
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin')
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin');

-- accounts

DROP POLICY IF EXISTS "accounts_select" ON public.accounts;
CREATE POLICY "accounts_select" ON public.accounts
    FOR SELECT
    TO authenticated
    USING (owner_user_id = (SELECT auth.uid())
        OR (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id())));

DROP POLICY IF EXISTS "accounts_insert_personal" ON public.accounts;
CREATE POLICY "accounts_insert_personal" ON public.accounts
    FOR INSERT
    TO authenticated
    WITH CHECK (owner_user_id = (SELECT auth.uid()) AND household_id = (SELECT public.get_auth_user_household_id()) AND is_shared_pool = false);

DROP POLICY IF EXISTS "accounts_insert_shared" ON public.accounts;
CREATE POLICY "accounts_insert_shared" ON public.accounts
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()) AND is_shared_pool = true AND (SELECT public.get_auth_user_role()) = 'admin');

DROP POLICY IF EXISTS "accounts_update_personal" ON public.accounts;
CREATE POLICY "accounts_update_personal" ON public.accounts
    FOR UPDATE
    TO authenticated
    USING (owner_user_id = (SELECT auth.uid()) AND household_id = (SELECT public.get_auth_user_household_id()))
    WITH CHECK (owner_user_id = (SELECT auth.uid()) AND household_id = (SELECT public.get_auth_user_household_id()) AND is_shared_pool = false);

DROP POLICY IF EXISTS "accounts_update_shared" ON public.accounts;
CREATE POLICY "accounts_update_shared" ON public.accounts
    FOR UPDATE
    TO authenticated
    USING (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin')
    WITH CHECK (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin');

DROP POLICY IF EXISTS "accounts_delete_admin_or_owner" ON public.accounts;
CREATE POLICY "accounts_delete_admin_or_owner" ON public.accounts
    FOR DELETE
    TO authenticated
    USING ((owner_user_id = (SELECT auth.uid()) AND is_shared_pool = false)
        OR (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin'));

-- ledgers

DROP POLICY IF EXISTS "transfers_select_household" ON public.account_transfers;
CREATE POLICY "transfers_select_household" ON public.account_transfers
    FOR SELECT
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "income_select_household" ON public.income_records;
CREATE POLICY "income_select_household" ON public.income_records
    FOR SELECT
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

-- households / users / invites

DROP POLICY IF EXISTS "households_select_own" ON public.households;
CREATE POLICY "households_select_own" ON public.households
    FOR SELECT
    TO authenticated
    USING (id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "households_update_admin" ON public.households;
CREATE POLICY "households_update_admin" ON public.households
    FOR UPDATE
    TO authenticated
    USING (id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin')
    WITH CHECK (id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin');

DROP POLICY IF EXISTS "users_select_household" ON public.users;
CREATE POLICY "users_select_household" ON public.users
    FOR SELECT
    TO authenticated
    USING (id = (SELECT auth.uid())
        OR (household_id IS NOT NULL AND household_id = (SELECT public.get_auth_user_household_id())));

DROP POLICY IF EXISTS "users_insert_own" ON public.users;
CREATE POLICY "users_insert_own" ON public.users
    FOR INSERT
    TO authenticated
    WITH CHECK (id = (SELECT auth.uid()) AND household_id IS NULL AND role = 'member');

DROP POLICY IF EXISTS "users_update_own_profile" ON public.users;
CREATE POLICY "users_update_own_profile" ON public.users
    FOR UPDATE
    TO authenticated
    USING (id = (SELECT auth.uid()))
    WITH CHECK (id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "invites_select_household" ON public.household_invites;
CREATE POLICY "invites_select_household" ON public.household_invites
    FOR SELECT
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "invites_insert_household" ON public.household_invites;
CREATE POLICY "invites_insert_household" ON public.household_invites
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin');

DROP POLICY IF EXISTS "invites_delete_admin" ON public.household_invites;
CREATE POLICY "invites_delete_admin" ON public.household_invites
    FOR DELETE
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()) AND (SELECT public.get_auth_user_role()) = 'admin');

-- taxonomy / settings / dependents / installments

DROP POLICY IF EXISTS "cost_control_codes_select" ON public.cost_control_codes;
CREATE POLICY "cost_control_codes_select" ON public.cost_control_codes
    FOR SELECT
    TO authenticated
    USING (household_id IS NULL OR household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "household_category_settings_all" ON public.household_category_settings;
CREATE POLICY "household_category_settings_all" ON public.household_category_settings
    FOR ALL
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()))
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "dependents_select_household" ON public.household_dependents;
CREATE POLICY "dependents_select_household" ON public.household_dependents
    FOR SELECT
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "dependents_delete_household" ON public.household_dependents;
CREATE POLICY "dependents_delete_household" ON public.household_dependents
    FOR DELETE
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "dependents_insert_household" ON public.household_dependents;
CREATE POLICY "dependents_insert_household" ON public.household_dependents
    FOR INSERT
    TO authenticated
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "dependents_update_household" ON public.household_dependents;
CREATE POLICY "dependents_update_household" ON public.household_dependents
    FOR UPDATE
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()))
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()));

DROP POLICY IF EXISTS "Allow household members full access to installment_plans" ON public.installment_plans;
CREATE POLICY "Allow household members full access to installment_plans" ON public.installment_plans
    FOR ALL
    TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id()))
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()));

-- storage.objects (receipts): membership-scoped, no stale users.household_id branch

DROP POLICY IF EXISTS "receipts_insert_household" ON storage.objects;
CREATE POLICY "receipts_insert_household" ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'receipts'
        AND (SELECT auth.uid()) IS NOT NULL
        AND (storage.foldername(name))[1] IN (
            SELECT m.household_id::text
            FROM public.household_memberships m
            WHERE m.user_id = (SELECT auth.uid())
        )
        AND lower(storage.extension(name)) = ANY (ARRAY['jpg', 'jpeg', 'png', 'webp'])
        AND name !~ '\.\.');

DROP POLICY IF EXISTS "receipts_select_household" ON storage.objects;
CREATE POLICY "receipts_select_household" ON storage.objects
    FOR SELECT
    TO authenticated
    USING (bucket_id = 'receipts'
        AND (SELECT auth.uid()) IS NOT NULL
        AND (storage.foldername(name))[1] IN (
            SELECT m.household_id::text
            FROM public.household_memberships m
            WHERE m.user_id = (SELECT auth.uid())
        ));

DROP POLICY IF EXISTS "receipts_delete_household" ON storage.objects;
CREATE POLICY "receipts_delete_household" ON storage.objects
    FOR DELETE
    TO authenticated
    USING (bucket_id = 'receipts'
        AND (SELECT auth.uid()) IS NOT NULL
        AND (storage.foldername(name))[1] IN (
            SELECT m.household_id::text
            FROM public.household_memberships m
            WHERE m.user_id = (SELECT auth.uid())
        ));

-- Foreign-key / lookup indexes
CREATE INDEX IF NOT EXISTS idx_transactions_reallocated_from_budget ON public.transactions (reallocated_from_budget_id) WHERE reallocated_from_budget_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_household_invites_household ON public.household_invites (household_id);
CREATE INDEX IF NOT EXISTS idx_household_invites_created_by ON public.household_invites (created_by);
CREATE INDEX IF NOT EXISTS idx_household_invites_used_by ON public.household_invites (used_by);
CREATE INDEX IF NOT EXISTS idx_account_transfers_user ON public.account_transfers (user_id);
CREATE INDEX IF NOT EXISTS idx_income_records_user ON public.income_records (user_id);
CREATE INDEX IF NOT EXISTS idx_invite_attempt_log_user_time ON public.invite_attempt_log (user_id, attempted_at DESC);

COMMIT;
