BEGIN;

-- Drop the rigid CHECK constraint that forbade all accounts for wife-class transactions
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_wife_class_no_account;

-- Create dynamic trigger function enforcing that wife-class transactions may only link
-- to a non-shared personal account owned by the designated spouse in the same household.
CREATE OR REPLACE FUNCTION public.enforce_wife_class_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.nafaqah_class IN ('wife_personal', 'wife_reimbursable') AND NEW.account_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
        FROM public.accounts a
       WHERE a.id = NEW.account_id
         AND a.owner_user_id = NEW.nafaqah_spouse_id
         AND a.is_shared_pool = false
         AND a.household_id = NEW.household_id
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'check_violation',
        CONSTRAINT = 'transactions_wife_class_no_account',
        HINT = 'wife_class_household_account',
        MESSAGE = 'Wife expense cannot be debited from household shared accounts or other members accounts.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_wife_class_account ON public.transactions;

CREATE TRIGGER trg_enforce_wife_class_account
BEFORE INSERT OR UPDATE OF account_id, nafaqah_class, nafaqah_spouse_id
ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_wife_class_account();

COMMIT;

