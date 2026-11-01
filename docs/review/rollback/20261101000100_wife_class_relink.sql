-- Rollback Snapshot and Manual Reconciliation Log for 20261101000100_nafaqah_wife_account_owner_guard.sql
-- In accordance with Rule 02 §4 and Rule 04 §4:
-- Legacy wife transactions unlinked during 20261101000000 are documented here.
-- Any manual restoration of spouse personal accounts must use verifiable historical logs:

-- Snapshot template for pre-migration state audit:
-- SELECT id, account_id, amount, household_id, nafaqah_spouse_id, created_at
--   FROM public.transactions
--  WHERE nafaqah_class IN ('wife_personal', 'wife_reimbursable');

-- Manual Owner-Reconciliation Item:
-- Pre-migration row snapshot was unlinked by 20261101000000_nafaqah_wife_no_account.sql.
-- Because accounts were unlinked in production/tests without cached owner mappings,
-- we do not guess previous account IDs. Users can re-associate unlinked wife transactions
-- with their personal accounts through manual transaction editing.

