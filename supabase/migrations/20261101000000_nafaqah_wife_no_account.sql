BEGIN;
ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_wife_class_no_account
  CHECK (nafaqah_class IS NULL
         OR nafaqah_class NOT IN ('wife_personal', 'wife_reimbursable')
         OR account_id IS NULL) NOT VALID;

-- Unlink legacy wife rows; the balance trigger credits the account back.
UPDATE public.transactions
   SET account_id = NULL
 WHERE nafaqah_class IN ('wife_personal', 'wife_reimbursable')
   AND account_id IS NOT NULL;

ALTER TABLE public.transactions VALIDATE CONSTRAINT transactions_wife_class_no_account;
COMMIT;
