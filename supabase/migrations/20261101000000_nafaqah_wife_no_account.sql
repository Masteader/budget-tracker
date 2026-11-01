-- Enforce that wife-classified transactions (personal allowance or reimbursable advance)
-- cannot be linked to a household account, preventing accidental household balance debits.
ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_wife_class_no_account
  CHECK (nafaqah_class IS NULL
         OR nafaqah_class NOT IN ('wife_personal', 'wife_reimbursable')
         OR account_id IS NULL) NOT VALID;

