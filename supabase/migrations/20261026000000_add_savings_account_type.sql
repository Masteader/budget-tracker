-- Migration: Add savings account type to public.accounts
-- Ring-fences emergency savings vaults from the operating budget pool.

ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS accounts_account_type_check;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_account_type_check 
  CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool', 'savings'));

COMMENT ON CONSTRAINT accounts_account_type_check ON public.accounts IS 
  'Enforces valid account types including savings vaults protected from daily budgets.';
