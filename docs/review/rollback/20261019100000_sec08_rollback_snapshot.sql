-- ============================================================================
-- Rollback Snapshot for 20261019100000_sec08_round6_hardening.sql
-- Snapshot Date: 2026-10-19
-- ============================================================================

-- 1. Restore accounts grants & policies
GRANT ALL ON TABLE public.accounts TO authenticated;

DROP POLICY IF EXISTS "accounts_update_personal" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_shared" ON public.accounts;
CREATE POLICY "accounts_update_personal" ON public.accounts
    FOR UPDATE TO authenticated
    USING (
        owner_user_id = auth.uid()
        AND household_id = public.get_auth_user_household_id()
    )
    WITH CHECK (
        owner_user_id = auth.uid()
        AND household_id = public.get_auth_user_household_id()
        AND is_shared_pool = false
    );

CREATE POLICY "accounts_update_shared" ON public.accounts
    FOR UPDATE TO authenticated
    USING (
        is_shared_pool = true
        AND household_id = public.get_auth_user_household_id()
        AND public.get_auth_user_role() = 'admin'
    )
    WITH CHECK (
        is_shared_pool = true
        AND household_id = public.get_auth_user_household_id()
        AND public.get_auth_user_role() = 'admin'
    );

-- 2. Restore transactions RLS policies
DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
DROP POLICY IF EXISTS "transactions_update_household" ON public.transactions;

CREATE POLICY "transactions_insert_household" ON public.transactions
    FOR INSERT TO authenticated
    WITH CHECK (household_id = public.get_auth_user_household_id());

CREATE POLICY "transactions_update_household" ON public.transactions
    FOR UPDATE TO authenticated
    USING (household_id = public.get_auth_user_household_id())
    WITH CHECK (household_id = public.get_auth_user_household_id());

-- 3. Restore account_transfers & income_records policies
DROP POLICY IF EXISTS "transfers_insert_household" ON public.account_transfers;
CREATE POLICY "transfers_insert_household" ON public.account_transfers
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
        AND user_id = auth.uid()
    );

DROP POLICY IF EXISTS "income_update_household" ON public.income_records;
DROP POLICY IF EXISTS "income_delete_household" ON public.income_records;
CREATE POLICY "income_update_household" ON public.income_records
    FOR UPDATE TO authenticated
    USING (
        household_id = public.get_auth_user_household_id()
        AND (user_id = auth.uid() OR public.get_auth_user_role() = 'admin')
    )
    WITH CHECK (
        household_id = public.get_auth_user_household_id()
    );

CREATE POLICY "income_delete_household" ON public.income_records
    FOR DELETE TO authenticated
    USING (
        household_id = public.get_auth_user_household_id()
        AND (user_id = auth.uid() OR public.get_auth_user_role() = 'admin')
    );

DROP TRIGGER IF EXISTS trg_adjust_account_balance_on_income_change ON public.income_records;
DROP FUNCTION IF EXISTS public.adjust_account_balance_on_income_change();

-- 4. Drop category validation trigger
DROP TRIGGER IF EXISTS trg_validate_category_budgets ON public.budgets;
DROP TRIGGER IF EXISTS trg_validate_category_transactions ON public.transactions;
DROP TRIGGER IF EXISTS trg_validate_category_settings ON public.household_category_settings;
DROP FUNCTION IF EXISTS public.validate_category_code_exists();

-- 5. Drop claim_household_role_invite RPC
DROP FUNCTION IF EXISTS public.claim_household_role_invite(text, uuid);
DROP FUNCTION IF EXISTS public.claim_household_role_invite(text);

-- 6. Restore quota and trigger function grants
GRANT EXECUTE ON FUNCTION public.consume_quota(UUID, TEXT, INT, INT) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_quota_status(UUID, TEXT, INT, INT) TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_last_admin_membership() TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.populate_transaction_cycle_key() TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_account_balance_on_transaction() TO PUBLIC, anon, authenticated;
