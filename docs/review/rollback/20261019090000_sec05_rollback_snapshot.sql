-- ----------------------------------------------------------------------
-- Rollback snapshot for SEC-05 (Accounts security and atomic transfers)
-- Captured at: 2026-10-19T06:45:00Z
-- ----------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_update_account_balance_on_transaction ON public.transactions;
DROP FUNCTION IF EXISTS public.update_account_balance_on_transaction();
DROP FUNCTION IF EXISTS public.transfer_between_accounts(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.record_income(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT);

DROP POLICY IF EXISTS "accounts_select" ON public.accounts;
DROP POLICY IF EXISTS "accounts_insert_personal" ON public.accounts;
DROP POLICY IF EXISTS "accounts_insert_shared" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_personal" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_shared" ON public.accounts;
DROP POLICY IF EXISTS "accounts_delete_admin_or_owner" ON public.accounts;

CREATE POLICY "Users view their accounts or shared pools" ON public.accounts
    FOR SELECT TO authenticated
    USING ((owner_user_id = auth.uid()) OR ((is_shared_pool = true) AND (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()))));

CREATE POLICY "Users can manage personal accounts" ON public.accounts
    FOR ALL TO authenticated
    USING (owner_user_id = auth.uid());

CREATE POLICY "Household members can update shared pool accounts" ON public.accounts
    FOR UPDATE TO authenticated
    USING ((is_shared_pool = true) AND (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid())))
    WITH CHECK ((is_shared_pool = true) AND (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid())));

DROP POLICY IF EXISTS "transfers_select_household" ON public.account_transfers;
DROP POLICY IF EXISTS "transfers_insert_household" ON public.account_transfers;

CREATE POLICY "Household members view and create transfers" ON public.account_transfers
    FOR ALL TO authenticated
    USING (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));

DROP POLICY IF EXISTS "income_select_household" ON public.income_records;
DROP POLICY IF EXISTS "income_insert_household" ON public.income_records;
DROP POLICY IF EXISTS "income_update_household" ON public.income_records;
DROP POLICY IF EXISTS "income_delete_household" ON public.income_records;

CREATE POLICY "Household members view and record income" ON public.income_records
    FOR ALL TO authenticated
    USING (household_id IN (SELECT users.household_id FROM users WHERE users.id = auth.uid()));
