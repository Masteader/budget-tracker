-- ============================================================================
-- Migration: 20261105001300_wife_repayment_debit.sql
-- Proof tests: supabase/tests/56_wife_repayment_debit.sql, 57_wife_repayment_debit_concurrency.sql,
--              58_wife_repayment_requests_and_reversals.sql, 59_wife_repayment_review_fixes.sql,
--              60_wife_repayment_r2_fixes.sql, 61_wife_repayment_r2_concurrency.sql,
--              62_wife_repayment_r3_fixes.sql, 63_wife_allowance_access.sql,
--              64_wife_personal_privacy.sql, 65_wife_transfer_privacy.sql, 66_wife_plan_owner.sql,
--              67_wife_privacy_write_paths.sql, 68_wife_account.sql, 69_wife_account_concurrency.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rules 2 and 3
--
-- Owner decisions 2026-11-06. Repaying the wife for shared things she paid (wife_reimbursable):
--
--   1. Every repayment is tracked. It leaves an account the payer picks (a cash payment leaves his
--      Cash account) and must be held there (insufficient_funds). There is no "not tracked" path:
--      any call without an account, including the old 6-argument signatures of
--      record_spouse_reimbursement and record_former_member_debt_payment, is refused with HINT
--      app_update_required and records nothing.
--   2. Her wife account is credited (owner decisions 2026-11-06, point 11, superseding "her account
--      is never credited"). Each repayment writes one account_transfers row from the payer's account
--      to the wife account the payer picks (purpose 'wife_repayment', so each account's own history
--      names it) and moves both balances by exactly the amount in the same statement; a former
--      member's payment ('former_member_payment') still goes to no account. Her own accounts are
--      never credited. No budget or transaction moves (her expense counted when she recorded
--      it). The ledger row records who actually paid (paid_by_user_id: the payer, not always the
--      husband), the wife account it credited (wife_account_id) and what was owed before and after
--      it, which a replay answers again.
--   3. The wife asks, the husband approves. She no longer records a repayment (wife_must_request).
--      She marks "I received X": a pending request (spouse_reimbursement_requests) that moves no
--      money and does not lower what is owed. Her husband (when he is gone, an admin who is not a
--      wife: point 5) approves it with an account, which is the normal repayment of exactly the
--      requested amount, re-checked against what is owed at that moment (request_exceeds_outstanding), linked to the request; or declines it with
--      an optional reason; she can cancel her own pending one. New requests never take the pending
--      total above what is owed (pending_exceeds_outstanding), and whatever lowers what is owed (a
--      direct repayment, an approval, a smaller or removed advance) closes, in the same
--      transaction, the pending requests that no longer fit (outcome 'already_repaid', nothing
--      moves): they are kept in the order she made them while they fit, so the most recent close
--      first and a later, smaller one that still fits stays. Pending never exceeds what is owed.
--      Outcomes are rows of their own (spouse_reimbursement_request_outcomes, one per request), so
--      requests are append-only too. A former member's record takes no requests: she is gone.
--   4. Nothing is deleted, edited or voided; a correction is a reversing entry. A reversal of a
--      tracked repayment (spouse_reimbursements.kind = 'reversal', reverses_id unique) credits the
--      original account back in full, as a transfer from no account, and adds the amount back to
--      what is owed. The same for a former member's payment (former_member_debt_events.kind =
--      'reversal', reverses_event_id unique), which reopens a settled record. Refused for a legacy
--      row without a transfer (reversal_not_tracked), an archived or deleted account
--      (reversal_account_unavailable), a record waived after the payment (reversal_after_waiver),
--      and a second time (already_reversed). Who reverses: her ledger's manager only (her husband;
--      an admin who is not a wife when he is gone; for a former member's record, its manager), from
--      the account it left as the account rules say: a personal account as its owner, a pool as an
--      admin (review R3B-06, owner decision 2026-11-06, superseding R1-07). A replaced husband or
--      a demoted admin no longer reverses, even from his own account; such a repayment is then
--      reversed by nobody.
--   5. Who sees and who acts (owner decisions 2026-11-06, reviews R1-01 and R3-01). Her husband is
--      the household's Nafaqah provider while he is a current member who is not a wife
--      (001200's nafaqah_ledger_husband_id); he is gone when there is none (he left, his account
--      was deleted, or nobody was named). Her ledger (what is owed, repayments, reversals, her
--      requests, their outcomes, decline reasons and notes) is read by her and by her husband
--      only; when he is gone, by an admin who is not a wife too. Only her husband (when he is
--      gone, an admin who is not a wife: 001200's nafaqah_may_manage_ledgers) records a
--      repayment, approves or declines a request, pays or waives a former member's record. She
--      only makes and cancels her own requests. No wife sees or does any of it for a co-wife or a
--      former member, even as an admin; an ordinary member never; and a wife never pays from a
--      shared pool (account_forbidden in the account helper itself). The account rules stay: a
--      personal account only by its owner, a pool only by an admin, so the husband pays from a
--      pool only if he is an admin.
--   6. A client cannot delete an account a repayment or a reversal used (review R3-05,
--      account_has_repayments): it is archived instead, so the reversal stays possible and its
--      history stays in the household's books. The purge (no JWT subject) still deletes it.
--   7. Her allowance (rule 3; owner decision 2026-11-06, section 10c) is read by her (her own),
--      her husband (as in point 5) and an admin who is not a wife; never by a co-wife, even an
--      admin, nor an ordinary member (the read policy of member_allowances through
--      nafaqah_caller_sees_allowances, and get_member_allowance_status). It is set as before by the
--      husband or an admin, never by a wife: set_member_allowance refuses a wife who is an admin.
--   8. Her personal purchases (rule 3; owner decision 2026-11-06, section 10d): transactions with
--      nafaqah_class 'wife_personal' are read by the same people as her allowance (her own, her
--      husband, an admin who is not a wife), and so is the receipt photo of one; never by a
--      co-wife, even an admin, nor an ordinary member (the read policy of transactions through
--      nafaqah_caller_sees_allowances, the receipts read policy through nafaqah_receipt_hidden).
--      Every other transaction keeps its household-wide read. Who writes them is unchanged, but a
--      caller who cannot read a row cannot update or delete it, also by a statement that names no
--      row (review R3B-01: the UPDATE and DELETE policies of transactions and the receipts DELETE
--      policy carry the read test). nafaqah_receipt_hidden answers alike for a path of nothing and
--      a photo the caller does not read (review R3B-04). Her advance's wife or class is changed by
--      a client only by her ledger's managers, or by her clearing her own (review R3B-08).
--   9. Transfers of her personal account and plans of her personal purchases (owner decision
--      2026-11-06, section 10e) are read by the same people: an account_transfers row with either
--      side a personal account of a wife of the household (her own rows by her, a transfer between
--      two wives' accounts by both, and a row with his own personal account on the other side by
--      that account's owner), and an installment plan linked to a purchase only by whoever reads
--      that purchase (its schedule and payments are the plan's columns); the plan of her personal
--      purchase stays hers after the purchase is deleted or unlinked. Never by a co-wife, even an
--      admin, nor an ordinary member (the read policy of account_transfers through
--      personal_owner_ids and nafaqah_caller_hidden_wives, the installment_plans policy through the
--      plan's kept personal_owner_id, which looks nothing up per plan: review R3B-03). A plan is
--      created or linked again only to a purchase the caller reads (review R3B-05). A repayment's
--      own transfer rows (a repayment, its reversal, a former member's payment, its reversal) are
--      read only by the wife whose ledger it is, its managers and the owner of the personal account
--      on the row (review R3B-02): a pool's lines too, whose balance every member still reads.
--      Balances are unchanged; a repayment's transfer never involves her account.
--  10. A deleted wife's personal plans stay hidden (owner decision 2026-11-06): the purge clears
--      her id from them and marks them a former wife's (installment_plans.former_member_personal,
--      which names nobody); they are read only by her husband and the admins who are not wives.
--  11. The wife account (owner decisions 2026-11-06, section 12): an account of kind 'wife' that her
--      husband creates, owns and assigns to one wife (accounts.assigned_wife_id). Seen by her, its
--      owner and her ledger's managers only; spent from only by her (her personal purchases and
--      advances); funded by its owner or her ledger's managers; nothing is transferred out of it.
--      Every repayment credits one of hers (the payer picks it; on her request she picks it, and the
--      approval uses it or another of hers), none: wife_account_required. A reversal takes the
--      amount back out of it (wife_account_insufficient_funds when she spent it; archived refused).
--      Her leaving or her purge archives it (his, naming nobody); his purge passes it to the
--      household's primary admin, or to her when that admin is a co-wife.
--
-- What is owed is advances less repayments plus reversals (nafaqah_net_repaid); pending requests
-- never count. get_spouse_reimbursement_balance, former_member_debt_outstanding (the purge's
-- snapshot and the deletion notices) and guard_wife_reimbursable_ledger all use it.
--
-- Account rules, as transfer_between_accounts: the account is in the household, not archived, in
-- SAR (account_unavailable); a personal account only by its owner, a shared pool only by a household
-- admin, and never by a wife (account_forbidden). Every money-moving call takes a request key: the
-- same key again, for the same thing by the same person (amount, account, kind and actor), answers
-- as the first time and changes nothing; anything else with it is request_key_reused.
-- One key, one operation, per household (review R2-01): every call here that takes a key (a
-- repayment, an approval, a reversal, her request, a former member's payment or reversal) claims
-- it in 001200's nafaqah_request_keys once it found no exact replay of its own, so a key used on
-- another path, for another wife or on another record is request_key_reused and moves nothing,
-- also when two calls race (review R2-07). The ledger row and the former member's event keep the
-- account the money left or returned to (account_id, no foreign key), so a replay after that
-- account is deleted still answers the stored answer (review R2-06).
--
-- Lock order: the spouse_reimbursement advisory lock (as before), then a shared pool, the household
-- (KEY SHARE), the personal accounts (his and her wife account, in id order), then the request rows
-- or the former member's record row, and
-- last the request key (nafaqah_request_keys, whose insert waits for a call that claimed the same
-- key and has not finished). The guard trigger, closing requests after a smaller advance, takes
-- the advisory lock, then the household (KEY SHARE), then the request rows. Her request takes the
-- advisory lock, then the household (KEY SHARE), and checks again that she is a wife of the
-- household (review R2-05): a purge ending her membership meanwhile has closed her requests and
-- her new one is refused.
-- prepare_account_purge locks pools, then households FOR UPDATE, then the wife accounts of the
-- person it deletes, and only then closes requests, so a repayment, approval or reversal in flight
-- either finishes before the purge or waits for it without holding anything the purge needs.
-- transfer_between_accounts locks pools first, then the other accounts in id order, the same way.
--
-- The purge (prepare_account_purge, replaced with 001200's body plus two steps): pending requests of
-- the wife being deleted, and pending requests in households whose husband (provider) is being
-- deleted, are closed (outcome 'closed', nothing moved); a decline reason he wrote is removed with
-- his other free text. Her requests then go with her ledger at the leave
-- (remove_nafaqah_ledger_on_membership_end, replaced). The ledger invariant is unchanged.
--
-- Replaces: record_spouse_reimbursement (both signatures), record_former_member_debt_payment (both),
-- get_spouse_reimbursement_balance (20261020300000) and its policy spouse_reimbursements_select_household,
-- get_member_allowance_status, set_member_allowance and their table's policy
-- member_allowances_select_household (20261020300000),
-- the read policies transactions_select_household, storage's receipts_select_household,
-- transfers_select_household (account_transfers) and the installment_plans policy (20261020100000),
-- the write policies transactions_update_household and transactions_delete_household
-- (20261020400000) and storage's receipts_delete_household (20261020100000),
-- guard_wife_reimbursable_ledger and remove_nafaqah_ledger_on_membership_end (20261020900000),
-- former_member_debt_outstanding and prepare_account_purge (20261105001200); for the wife account
-- (section 12): the policies accounts_select (20261020100000) and transactions_insert_household,
-- transfer_between_accounts, transaction_account_matches, transaction_personal_account_writable and
-- update_account_balance_on_transaction (20261020400000), enforce_wife_class_account (20261101000100)
-- and the constraint accounts_account_type_check (20261026000000). Re-running 001200 after
-- this file puts its own versions back (an amount-only 6-argument payment among them, which both
-- files grant to the service role only, so no client can call it: review R1-11, R3-03): run this
-- file again after it.
--
-- Safe to run again (IF NOT EXISTS, CREATE OR REPLACE, DROP ... IF EXISTS).
--
-- Rollback (one transaction), after rolling back the app and the API:
--   DO $$ BEGIN
--       IF EXISTS (SELECT 1 FROM public.spouse_reimbursements WHERE kind = 'reversal')
--          OR EXISTS (SELECT 1 FROM public.former_member_debt_events WHERE kind = 'reversal') THEN
--           RAISE EXCEPTION 'A reversal exists: without this file it would count as a repayment. Stop.';
--       END IF;
--       IF EXISTS (SELECT 1 FROM public.accounts WHERE account_type = 'wife') THEN
--           RAISE EXCEPTION 'A wife account exists: without this file its kind is invalid and every member would read its transfers. Stop.';
--       END IF;
--   END $$;
--   DROP TRIGGER trg_accounts_wife_account_guard ON public.accounts;
--   DROP TRIGGER trg_wife_account_spending ON public.transactions;
--   DROP POLICY "accounts_select" ON public.accounts;
--   CREATE POLICY "accounts_select" ON public.accounts
--       FOR SELECT
--       TO authenticated
--       USING (owner_user_id = (SELECT auth.uid())
--           OR (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id())));
--   DROP POLICY "transactions_insert_household" ON public.transactions;
--   CREATE POLICY "transactions_insert_household" ON public.transactions
--       FOR INSERT TO authenticated
--       WITH CHECK (
--           household_id = (SELECT public.get_auth_user_household_id())
--           AND user_id = (SELECT auth.uid())
--           AND (
--               account_id IS NULL
--               OR EXISTS (
--                   SELECT 1 FROM public.accounts a
--                   WHERE a.id = transactions.account_id
--                     AND a.household_id = transactions.household_id
--                     AND (a.is_shared_pool = true OR a.owner_user_id = (SELECT auth.uid()))
--               )
--           )
--       );
--   ALTER TABLE public.accounts DROP CONSTRAINT accounts_wife_account, DROP CONSTRAINT accounts_account_type_check,
--     ADD CONSTRAINT accounts_account_type_check
--     CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool', 'savings'));
--   COMMENT ON CONSTRAINT accounts_account_type_check ON public.accounts IS
--     'Enforces valid account types including savings vaults protected from daily budgets.';
--   Then run these CREATE OR REPLACE statements: transfer_between_accounts,
--   transaction_account_matches, transaction_personal_account_writable and
--   update_account_balance_on_transaction from 20261020400000, and enforce_wife_class_account from
--   20261101000100 (they keep their privileges). Then:
--   DROP FUNCTION public.create_wife_account(uuid, uuid, text, uuid),
--     public.assign_wife_account(uuid, uuid, uuid, uuid),
--     public.archive_wife_account(uuid, uuid, uuid),
--     public.nafaqah_guard_wife_account_row(),
--     public.nafaqah_guard_wife_account_spending(),
--     public.nafaqah_may_see_wife_account(uuid, uuid, uuid, uuid),
--     public.account_deletion_wife_account_recipient(uuid, uuid);
--   DROP TRIGGER trg_accounts_keep_repayment_history ON public.accounts;
--   DROP POLICY spouse_reimbursements_select_household ON public.spouse_reimbursements;
--   CREATE POLICY spouse_reimbursements_select_household ON public.spouse_reimbursements
--       FOR SELECT TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()));
--   DROP POLICY member_allowances_select_household ON public.member_allowances;
--   CREATE POLICY member_allowances_select_household ON public.member_allowances
--       FOR SELECT TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()));
--   DROP POLICY transactions_select_household ON public.transactions;
--   CREATE POLICY transactions_select_household ON public.transactions
--       FOR SELECT TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()));
--   DROP POLICY transactions_update_household ON public.transactions;
--   CREATE POLICY transactions_update_household ON public.transactions
--       FOR UPDATE TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()))
--       WITH CHECK (
--           household_id = (SELECT public.get_auth_user_household_id())
--           AND (user_id = (SELECT auth.uid()) OR (SELECT public.get_auth_user_role()) = 'admin')
--           AND (
--               account_id IS NULL
--               OR public.transaction_account_matches(account_id, household_id, user_id)
--           )
--       );
--   DROP POLICY transactions_delete_household ON public.transactions;
--   CREATE POLICY transactions_delete_household ON public.transactions
--       FOR DELETE TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()));
--   DROP TRIGGER trg_wife_advance_attribution ON public.transactions;
--   DROP POLICY receipts_select_household ON storage.objects;
--   CREATE POLICY receipts_select_household ON storage.objects
--       FOR SELECT TO authenticated
--       USING (bucket_id = 'receipts'
--           AND (SELECT auth.uid()) IS NOT NULL
--           AND (storage.foldername(name))[1] IN (
--               SELECT m.household_id::text
--               FROM public.household_memberships m
--               WHERE m.user_id = (SELECT auth.uid())
--           ));
--   DROP POLICY receipts_delete_household ON storage.objects;
--   CREATE POLICY receipts_delete_household ON storage.objects
--       FOR DELETE TO authenticated
--       USING (bucket_id = 'receipts'
--           AND (SELECT auth.uid()) IS NOT NULL
--           AND (storage.foldername(name))[1] IN (
--               SELECT m.household_id::text
--               FROM public.household_memberships m
--               WHERE m.user_id = (SELECT auth.uid())
--           ));
--   DROP INDEX public.idx_transactions_wife_personal_receipt;
--   DROP POLICY transfers_select_household ON public.account_transfers;
--   CREATE POLICY transfers_select_household ON public.account_transfers
--       FOR SELECT TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()));
--   DROP POLICY "Allow household members full access to installment_plans" ON public.installment_plans;
--   CREATE POLICY "Allow household members full access to installment_plans" ON public.installment_plans
--       FOR ALL TO authenticated
--       USING (household_id = (SELECT public.get_auth_user_household_id()))
--       WITH CHECK (household_id = (SELECT public.get_auth_user_household_id()));
--   DROP TRIGGER trg_account_transfers_personal_owners ON public.account_transfers;
--   DROP TRIGGER trg_users_forget_transfer_owner ON public.users;
--   DROP TRIGGER trg_installment_plans_personal_owner ON public.installment_plans;
--   DROP TRIGGER trg_transactions_plan_owner ON public.transactions;
--   ALTER TABLE public.account_transfers DROP COLUMN personal_owner_ids, DROP COLUMN touches_wife_account;
--   ALTER TABLE public.accounts DROP COLUMN assigned_wife_id;
--   ALTER TABLE public.installment_plans DROP COLUMN personal_owner_id, DROP COLUMN former_member_personal;
--   DROP FUNCTION public.nafaqah_transfer_personal_owners(), public.nafaqah_personal_owners_of(uuid, uuid),
--     public.nafaqah_forget_transfer_owner(), public.nafaqah_plan_personal_owner(),
--     public.nafaqah_transaction_plan_owner(), public.nafaqah_purchase_personal_owner(uuid, uuid);
--   DROP FUNCTION public.request_spouse_reimbursement(uuid, numeric, text, uuid, uuid, uuid),
--     public.cancel_spouse_reimbursement_request(uuid, uuid, uuid),
--     public.decline_spouse_reimbursement_request(uuid, uuid, text, uuid),
--     public.approve_spouse_reimbursement_request(uuid, uuid, uuid, uuid, uuid, uuid),
--     public.reverse_spouse_reimbursement(uuid, uuid, uuid, uuid),
--     public.reverse_former_member_debt_payment(uuid, uuid, uuid, uuid, uuid),
--     public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid, uuid),
--     public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid),
--     public.nafaqah_repay_from_account(uuid, uuid, uuid, numeric, text, text, uuid, uuid, uuid, uuid),
--     public.nafaqah_repayment_debit(uuid, uuid, uuid, numeric, text),
--     public.nafaqah_repayment_credit(uuid, uuid, uuid, numeric, text),
--     public.nafaqah_repayment_transfer(uuid, uuid, uuid, uuid, numeric, text),
--     public.nafaqah_repayment_lock_account(uuid, uuid, uuid),
--     public.nafaqah_repayment_lock(uuid, uuid, uuid, uuid, uuid),
--     public.nafaqah_require_wife_account(uuid, uuid, uuid),
--     public.nafaqah_repayment_replay(public.spouse_reimbursements, uuid),
--     public.nafaqah_request_close(public.spouse_reimbursement_requests, text, text, uuid),
--     public.nafaqah_close_unfit_requests(uuid, uuid, numeric),
--     public.nafaqah_may_repay(uuid, uuid),
--     public.nafaqah_refuse_account_delete(),
--     public.nafaqah_guard_advance_attribution(),
--     public.nafaqah_receipt_hidden(text),
--     public.nafaqah_caller_hidden_wives(),
--     public.nafaqah_caller_sees_allowances(),
--     public.nafaqah_caller_hidden_wife_accounts(),
--     public.nafaqah_may_see_allowances(uuid, uuid);
--   Then run these CREATE OR REPLACE statements: record_spouse_reimbursement,
--   get_spouse_reimbursement_balance, get_member_allowance_status and set_member_allowance from
--   20261020300000 (they keep their privileges); guard_wife_reimbursable_ledger and
--   remove_nafaqah_ledger_on_membership_end from 20261020900000; record_former_member_debt_payment,
--   former_member_debt_outstanding and prepare_account_purge from 20261105001200. (The amount-only
--   payment keeps 001200's privilege, the service role only: this file never grants it to a client.)
--   DROP FUNCTION public.nafaqah_outstanding(uuid, uuid), public.nafaqah_net_repaid(uuid, uuid);
--   DROP TABLE public.spouse_reimbursement_request_outcomes, public.spouse_reimbursement_requests;
--   ALTER TABLE public.former_member_debt_events DROP CONSTRAINT former_member_debt_events_kind_check,
--     DROP CONSTRAINT former_member_debt_events_reversal,
--     ADD CONSTRAINT former_member_debt_events_kind_check CHECK (kind IN ('payment', 'waiver')),
--     DROP COLUMN reverses_event_id, DROP COLUMN transfer_id, DROP COLUMN account_id;
--   ALTER TABLE public.spouse_reimbursements DROP CONSTRAINT spouse_reimbursements_kind,
--     DROP COLUMN reverses_id, DROP COLUMN kind, DROP COLUMN transfer_id, DROP COLUMN request_key,
--     DROP COLUMN outstanding_before, DROP COLUMN outstanding_after, DROP COLUMN account_id, DROP COLUMN wife_account_id;
--   ALTER TABLE public.account_transfers DROP CONSTRAINT account_transfers_purpose, DROP COLUMN purpose;
--   (Their indexes go with the columns.) Balances already moved stay moved: the money did leave his
--   account; the transfers stay in account_transfers as ordinary history. Data lost: requests and
--   their outcomes, the ledger's links to the transfers, its request keys and stored outstanding
--   figures, the transfers' labels and who owned their personal sides (personal_owner_ids), and
--   whose personal purchase each installment plan was (personal_owner_id), and which were a
--   deleted wife's (former_member_personal: those plans become household-wide), the wife account
--   each repayment credited (wife_account_id) and which transfers had a wife account on them
--   (touches_wife_account). The rollback refuses while a wife account exists: archive and settle
--   them by hand first (a wife account's balance is her husband's money she has not spent).
--   paid_by_user_id keeps whoever paid (a co-admin, say), where
--   the old record_spouse_reimbursement wrote the husband. The keys this file's calls claimed stay
--   in 001200's nafaqah_request_keys (ids only): 001200's own calls keep refusing them.
-- ============================================================================

BEGIN;

-- 0. The first draft of this file (never applied anywhere) had other helpers -------------------
DROP FUNCTION IF EXISTS public.nafaqah_repayment_move(uuid, uuid, uuid, uuid, numeric, text);
DROP FUNCTION IF EXISTS public.nafaqah_repayment_lock_accounts(uuid, uuid, uuid, uuid, text);
-- Its second draft named the last argument of these two p_note; they now take the purpose. Dropped
-- and created again below on every run (nothing depends on them but the functions of this file).
DROP FUNCTION IF EXISTS public.nafaqah_repayment_debit(uuid, uuid, uuid, numeric, text);
DROP FUNCTION IF EXISTS public.nafaqah_repayment_credit(uuid, uuid, uuid, numeric, text);
-- Before the wife account (owner decision 2026-11-06, section 12) these took no account of hers:
-- each now takes the wife account a repayment credits as its last argument.
DROP FUNCTION IF EXISTS public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.request_spouse_reimbursement(uuid, numeric, text, uuid, uuid);
DROP FUNCTION IF EXISTS public.approve_spouse_reimbursement_request(uuid, uuid, uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.nafaqah_repay_from_account(uuid, uuid, uuid, numeric, text, text, uuid, uuid, uuid);

-- 1. The wife's ledger: links to the transfer, request keys, reversals ------------------------
ALTER TABLE public.spouse_reimbursements
    ADD COLUMN IF NOT EXISTS transfer_id uuid REFERENCES public.account_transfers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS request_key uuid,
    ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'payment',
    ADD COLUMN IF NOT EXISTS reverses_id uuid REFERENCES public.spouse_reimbursements(id) ON DELETE CASCADE;
ALTER TABLE public.spouse_reimbursements DROP CONSTRAINT IF EXISTS spouse_reimbursements_kind;
ALTER TABLE public.spouse_reimbursements ADD CONSTRAINT spouse_reimbursements_kind
    CHECK (kind IN ('payment', 'reversal') AND (kind = 'reversal') = (reverses_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS uq_spouse_reimbursements_request
    ON public.spouse_reimbursements (household_id, request_key) WHERE request_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_spouse_reimbursements_reverses
    ON public.spouse_reimbursements (reverses_id) WHERE reverses_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursements_transfer ON public.spouse_reimbursements (transfer_id);
-- What was owed before and after the row, as its call answered (a replay answers the same).
ALTER TABLE public.spouse_reimbursements
    ADD COLUMN IF NOT EXISTS outstanding_before numeric(14, 2),
    ADD COLUMN IF NOT EXISTS outstanding_after numeric(14, 2);
-- The account the money left (a payment) or returned to (a reversal), kept when that account is
-- deleted (no foreign key: an id of nothing then, with no name), so a replay still answers
-- (review R2-06).
ALTER TABLE public.spouse_reimbursements ADD COLUMN IF NOT EXISTS account_id uuid;
COMMENT ON COLUMN public.spouse_reimbursements.account_id IS
    'The account the money left (payment) or returned to (reversal), as its call named it; kept after that account is deleted, for replays. NULL on rows from before 20261105001300.';

COMMENT ON COLUMN public.spouse_reimbursements.outstanding_before IS
    'What was owed to her just before this row, as its call answered. NULL on rows from before 20261105001300.';
COMMENT ON COLUMN public.spouse_reimbursements.outstanding_after IS
    'What was owed to her just after this row, as its call answered. NULL on rows from before 20261105001300.';
-- paid_by_user_id (20261020300000) now holds who paid: the owner of the personal account it left, or
-- the admin who paid from a pool (the husband on older rows). A reversal keeps the payer of the
-- repayment it reverses. Its ON DELETE SET NULL and the purge's scrub of his notes are unchanged.

-- What a system transfer is, so the account's own history can name it. Only these RPCs set it:
-- clients cannot write account_transfers (20261020050000). NULL for ordinary transfers.
ALTER TABLE public.account_transfers ADD COLUMN IF NOT EXISTS purpose text;
ALTER TABLE public.account_transfers DROP CONSTRAINT IF EXISTS account_transfers_purpose;
ALTER TABLE public.account_transfers ADD CONSTRAINT account_transfers_purpose
    CHECK (purpose IS NULL OR purpose IN ('wife_repayment', 'wife_repayment_reversal',
                                          'former_member_payment', 'former_member_payment_reversal'));
COMMENT ON COLUMN public.account_transfers.purpose IS
    'Set by the Nafaqah RPCs (20261105001300): a repayment to the wife, its reversal, a payment of a former member''s record, or its reversal. Carries no name or text of anyone. NULL for transfers between accounts.';

COMMENT ON COLUMN public.spouse_reimbursements.transfer_id IS
    'The account_transfers row that moved the money: out of his account for a payment, back into it for a reversal. NULL only on rows from before 20261105001300.';
COMMENT ON COLUMN public.spouse_reimbursements.request_key IS
    'The client''s idempotency key: the same key again answers as the first time.';
COMMENT ON COLUMN public.spouse_reimbursements.kind IS
    '''payment'' lowers what is owed; ''reversal'' (reverses_id, at most one per payment) adds it back and returned the money.';

-- 2. A former member's events: links to the transfer, reversals ------------------------------
ALTER TABLE public.former_member_debt_events
    ADD COLUMN IF NOT EXISTS transfer_id uuid REFERENCES public.account_transfers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reverses_event_id uuid REFERENCES public.former_member_debt_events(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS account_id uuid;
ALTER TABLE public.former_member_debt_events DROP CONSTRAINT IF EXISTS former_member_debt_events_kind_check;
ALTER TABLE public.former_member_debt_events ADD CONSTRAINT former_member_debt_events_kind_check
    CHECK (kind IN ('payment', 'waiver', 'reversal'));
ALTER TABLE public.former_member_debt_events DROP CONSTRAINT IF EXISTS former_member_debt_events_reversal;
ALTER TABLE public.former_member_debt_events ADD CONSTRAINT former_member_debt_events_reversal
    CHECK ((kind = 'reversal') = (reverses_event_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS uq_former_member_debt_events_reverses
    ON public.former_member_debt_events (reverses_event_id) WHERE reverses_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_former_member_debt_events_transfer ON public.former_member_debt_events (transfer_id);

COMMENT ON COLUMN public.former_member_debt_events.transfer_id IS
    'The account_transfers row that moved the money: out of his account for a payment, back into it for a reversal.';
COMMENT ON COLUMN public.former_member_debt_events.reverses_event_id IS
    'For a reversal: the payment it reverses (at most one reversal per payment).';
COMMENT ON COLUMN public.former_member_debt_events.account_id IS
    'The account the money left (payment) or returned to (reversal); kept after that account is deleted, for replays (review R2-06). NULL for a waiver and on rows from before 20261105001300.';

-- 3. The wife's requests and their outcomes -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.spouse_reimbursement_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    wife_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    payment_method text NOT NULL DEFAULT 'cash'
        CHECK (payment_method IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other')),
    request_key uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_spouse_reimbursement_requests_key UNIQUE (household_id, request_key)
);
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursement_requests_wife
    ON public.spouse_reimbursement_requests (household_id, wife_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursement_requests_wife_user ON public.spouse_reimbursement_requests (wife_user_id);

-- One outcome per request; none while it is pending. reimbursement_id has no ON DELETE action and
-- is checked at commit: every path that removes a repayment (her leaving, her account or the
-- household deleted) removes her requests with it, so an approved request can never be left
-- looking pending, and a cascade that removes both in one statement is not refused halfway.
CREATE TABLE IF NOT EXISTS public.spouse_reimbursement_request_outcomes (
    request_id uuid PRIMARY KEY REFERENCES public.spouse_reimbursement_requests(id) ON DELETE CASCADE,
    outcome text NOT NULL CHECK (outcome IN ('approved', 'declined', 'cancelled', 'closed', 'already_repaid')),
    reimbursement_id uuid REFERENCES public.spouse_reimbursements(id) DEFERRABLE INITIALLY DEFERRED,
    reason text CHECK (reason IS NULL OR char_length(reason) <= 200),
    decided_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT spouse_reimbursement_request_outcomes_approved CHECK ((outcome = 'approved') = (reimbursement_id IS NOT NULL)),
    CONSTRAINT spouse_reimbursement_request_outcomes_reason CHECK (reason IS NULL OR outcome = 'declined')
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_spouse_reimbursement_request_outcomes_reimbursement
    ON public.spouse_reimbursement_request_outcomes (reimbursement_id) WHERE reimbursement_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursement_request_outcomes_decided_by
    ON public.spouse_reimbursement_request_outcomes (decided_by);

COMMENT ON TABLE public.spouse_reimbursement_requests IS
    'The wife''s "I received X": pending until it has an outcome. Moves no money and lowers nothing owed. Via request_spouse_reimbursement.';
COMMENT ON TABLE public.spouse_reimbursement_request_outcomes IS
    'Approved (linked to the repayment), declined (optional reason), cancelled by her, closed by an account deletion, or already_repaid: closed because what is owed dropped below her pending total (nothing moved). One per request; append-only.';

ALTER TABLE public.spouse_reimbursement_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spouse_reimbursement_request_outcomes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.spouse_reimbursement_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.spouse_reimbursement_request_outcomes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.spouse_reimbursement_requests TO authenticated;
GRANT SELECT ON public.spouse_reimbursement_request_outcomes TO authenticated;
GRANT ALL ON public.spouse_reimbursement_requests TO service_role;
GRANT ALL ON public.spouse_reimbursement_request_outcomes TO service_role;

-- Her ledger's read rule (review R3-01, owner decision 2026-11-06): she reads her own rows; her
-- husband reads them, and when he is gone an admin who is not a wife (001200's
-- nafaqah_caller_manages_ledgers, evaluated once per statement). A co-wife (even an admin), an
-- ordinary member and an admin while the husband is there read nothing of it. The repayments'
-- policy of 20261020300000 (any member of the household) is replaced here; the requests and their
-- outcomes follow the same rule. The policy names are kept.
DROP POLICY IF EXISTS spouse_reimbursements_select_household ON public.spouse_reimbursements;
CREATE POLICY spouse_reimbursements_select_household ON public.spouse_reimbursements
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (wife_user_id = (SELECT auth.uid()) OR (SELECT public.nafaqah_caller_manages_ledgers())));
DROP POLICY IF EXISTS spouse_reimbursement_requests_select_household ON public.spouse_reimbursement_requests;
CREATE POLICY spouse_reimbursement_requests_select_household ON public.spouse_reimbursement_requests
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (wife_user_id = (SELECT auth.uid()) OR (SELECT public.nafaqah_caller_manages_ledgers())));
DROP POLICY IF EXISTS spouse_reimbursement_request_outcomes_select_household ON public.spouse_reimbursement_request_outcomes;
CREATE POLICY spouse_reimbursement_request_outcomes_select_household ON public.spouse_reimbursement_request_outcomes
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.spouse_reimbursement_requests r
        WHERE r.id = spouse_reimbursement_request_outcomes.request_id
          AND r.household_id = (SELECT public.get_auth_user_household_id())
          AND (r.wife_user_id = (SELECT auth.uid()) OR (SELECT public.nafaqah_caller_manages_ledgers()))
    ));

-- The keys this file's calls already used (a second run of this file): one key, one operation, per
-- household (review R2-01, 001200's nafaqah_request_keys). Nothing on a first run.
INSERT INTO public.nafaqah_request_keys (household_id, request_key)
SELECT k.household_id, k.request_key
FROM (
    SELECT r.household_id, r.request_key FROM public.spouse_reimbursements r WHERE r.request_key IS NOT NULL
    UNION
    SELECT q.household_id, q.request_key FROM public.spouse_reimbursement_requests q
) k
ON CONFLICT (household_id, request_key) DO NOTHING;

-- 3b. The wife account: its columns (owner decision 2026-11-06; the rules are in section 12) -----
-- A personal (not shared) SAR account of kind 'wife' that the husband owns and assigns to one wife
-- of the household. She spends from it; he funds it; every repayment to her credits one of them.
-- assigned_wife_id names her while she is a wife of the household; it is cleared (and the account
-- archived) when she leaves or her account is deleted, so a former wife's account names nobody
-- (the former member pattern of 001200: an archived wife account with no one assigned).
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS assigned_wife_id uuid REFERENCES public.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.accounts.assigned_wife_id IS
    'The wife a wife account (account_type ''wife'') is assigned to (20261105001300, section 12). Written only by its RPCs, never by a client; cleared when she leaves the household or her account is deleted (the account is archived then).';
CREATE INDEX IF NOT EXISTS idx_accounts_assigned_wife ON public.accounts (assigned_wife_id) WHERE assigned_wife_id IS NOT NULL;
ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS accounts_account_type_check;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_account_type_check
    CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool', 'savings', 'wife'));
COMMENT ON CONSTRAINT accounts_account_type_check ON public.accounts IS
    'Enforces valid account types including savings vaults protected from daily budgets.';
-- A wife account is personal, in SAR, and assigned to a wife unless archived; no other account is
-- assigned to anyone.
ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS accounts_wife_account;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_wife_account CHECK (
    CASE WHEN account_type = 'wife'
         THEN is_shared_pool IS FALSE AND currency = 'SAR' AND (assigned_wife_id IS NOT NULL OR is_archived IS TRUE)
         ELSE assigned_wife_id IS NULL
    END);

-- Whether a transfer has a wife account on either side (kept on insert, like personal_owner_ids):
-- such a row is read only by her, the account's owner, the owner of the other personal side and
-- her ledger's managers (section 12).
ALTER TABLE public.account_transfers ADD COLUMN IF NOT EXISTS touches_wife_account boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.account_transfers.touches_wife_account IS
    'A wife account (20261105001300, section 12) is on either side. Set on insert by trg_account_transfers_personal_owners; never names anyone.';

-- The wife account a repayment credited (a reversal: debited), as its call named it; kept after the
-- account is deleted, for replays (like account_id).
ALTER TABLE public.spouse_reimbursements ADD COLUMN IF NOT EXISTS wife_account_id uuid;
COMMENT ON COLUMN public.spouse_reimbursements.wife_account_id IS
    'The wife account the repayment credited (a reversal: took back from). NULL on rows from before the wife account.';
-- The wife account she said the money went into; an approval uses it unless the payer names another
-- of hers.
ALTER TABLE public.spouse_reimbursement_requests
    ADD COLUMN IF NOT EXISTS wife_account_id uuid REFERENCES public.accounts(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursement_requests_wife_account
    ON public.spouse_reimbursement_requests (wife_account_id) WHERE wife_account_id IS NOT NULL;
COMMENT ON COLUMN public.spouse_reimbursement_requests.wife_account_id IS
    'The wife account she received it into (one of hers); the approval credits it unless the payer picks another of hers.';

-- 4. What is owed ----------------------------------------------------------------------------

-- Repaid, net: payments less reversals.
CREATE OR REPLACE FUNCTION public.nafaqah_net_repaid(p_household_id uuid, p_wife_user_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(sum(CASE WHEN r.kind = 'reversal' THEN -r.amount ELSE r.amount END), 0)::numeric(14, 2)
    FROM public.spouse_reimbursements r
    WHERE r.household_id = p_household_id AND r.wife_user_id = p_wife_user_id;
$$;

-- What the husband owes this wife in this household now: her advances less the net repaid, never
-- below zero. Pending requests do not count.
CREATE OR REPLACE FUNCTION public.nafaqah_outstanding(p_household_id uuid, p_wife_user_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT GREATEST(
        (SELECT COALESCE(sum(t.amount), 0) FROM public.transactions t
         WHERE t.household_id = p_household_id
           AND t.nafaqah_spouse_id = p_wife_user_id
           AND t.nafaqah_class = 'wife_reimbursable')
      - public.nafaqah_net_repaid(p_household_id, p_wife_user_id),
        0)::numeric(14, 2);
$$;

-- 001200's helper, now net of reversals (the purge's snapshot and the deletion notices use it).
CREATE OR REPLACE FUNCTION public.former_member_debt_outstanding(p_household_id uuid, p_wife_user_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT public.nafaqah_outstanding(p_household_id, p_wife_user_id);
$$;

CREATE OR REPLACE FUNCTION public.get_spouse_reimbursement_balance(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_gross numeric(14, 2);
    v_paid numeric(14, 2);
    v_pending numeric(14, 2);
    v_pending_n integer;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    -- Her ledger is read by her, by her husband, and when he is gone by an admin who is not a wife
    -- (review R3-01): nobody else gets a total, before anything about her is looked at.
    IF v_actor IS DISTINCT FROM p_wife_user_id AND NOT public.nafaqah_may_manage_ledgers(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only she, her husband, or an admin who is not a wife when he is gone, reads this ledger'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'Reimbursements apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(sum(t.amount), 0) INTO v_gross
    FROM public.transactions t
    WHERE t.household_id = p_household_id
      AND t.nafaqah_spouse_id = p_wife_user_id
      AND t.nafaqah_class = 'wife_reimbursable';
    v_paid := public.nafaqah_net_repaid(p_household_id, p_wife_user_id);

    SELECT COALESCE(sum(q.amount), 0), count(*) INTO v_pending, v_pending_n
    FROM public.spouse_reimbursement_requests q
    WHERE q.household_id = p_household_id AND q.wife_user_id = p_wife_user_id
      AND NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = q.id);

    RETURN jsonb_build_object(
        'household_id', p_household_id,
        'wife_user_id', p_wife_user_id,
        'husband_user_id', public.nafaqah_husband_id(p_household_id),
        'gross_advanced', v_gross,
        'reimbursed', v_paid,
        'outstanding', GREATEST(v_gross - v_paid, 0),
        'overpaid', GREATEST(v_paid - v_gross, 0),
        'pending_requested', v_pending,
        'pending_count', v_pending_n
    );
END;
$$;

-- Who records, approves or declines a repayment to a wife (reviews R1-01 and R3-01, owner decisions
-- 2026-11-06): her husband; when he is gone, an admin who is not a wife (001200's
-- nafaqah_may_manage_ledgers, the same rule as who reads her ledger). A wife never does, for a
-- co-wife either, even as an admin; an admin does not while the husband is there.
CREATE OR REPLACE FUNCTION public.nafaqah_may_repay(p_household_id uuid, p_actor uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT public.nafaqah_may_manage_ledgers(p_household_id, p_actor);
$$;

-- Pending total <= what is owed (review R1-03). Called whenever what is owed may have dropped: the
-- pending requests that no longer fit [p_owed] close as 'already_repaid', with nothing moved. They
-- are kept in the order she made them while they fit, so the most recent close first, and a later
-- one that still fits (a smaller one) stays. The caller holds the spouse_reimbursement advisory
-- lock and the household (KEY SHARE). Returns how many closed.
CREATE OR REPLACE FUNCTION public.nafaqah_close_unfit_requests(p_household_id uuid, p_wife_user_id uuid, p_owed numeric)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req record;
    v_kept numeric(14, 2) := 0;
    v_closed integer := 0;
BEGIN
    FOR v_req IN
        SELECT q.id, q.amount
        FROM public.spouse_reimbursement_requests q
        WHERE q.household_id = p_household_id AND q.wife_user_id = p_wife_user_id
          AND NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = q.id)
        ORDER BY q.created_at, q.id
        FOR UPDATE OF q
    LOOP
        IF v_kept + v_req.amount <= GREATEST(COALESCE(p_owed, 0), 0) THEN
            v_kept := v_kept + v_req.amount;
        ELSE
            INSERT INTO public.spouse_reimbursement_request_outcomes (request_id, outcome, decided_by)
            VALUES (v_req.id, 'already_repaid', NULL)
            ON CONFLICT (request_id) DO NOTHING;
            v_closed := v_closed + 1;
        END IF;
    END LOOP;
    RETURN v_closed;
END;
$$;

-- 20261020900000's guard, with the repaid amount net of reversals, closing the requests a smaller
-- advance leaves above what is owed (review R1-03).
CREATE OR REPLACE FUNCTION public.guard_wife_reimbursable_ledger()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_kept numeric(14, 2) := 0;
    v_advanced numeric(14, 2);
    v_repaid numeric(14, 2);
    v_after numeric(14, 2);
BEGIN
    IF OLD.nafaqah_class IS DISTINCT FROM 'wife_reimbursable' OR OLD.nafaqah_spouse_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        JOIN public.households h ON h.id = m.household_id
        JOIN public.users u ON u.id = m.user_id
        WHERE m.household_id = OLD.household_id
          AND m.user_id = OLD.nafaqah_spouse_id
    ) THEN
        RETURN COALESCE(NEW, OLD);  -- D3: her ledger in this household is being removed
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.nafaqah_class IS NOT DISTINCT FROM 'wife_reimbursable'
       AND NEW.nafaqah_spouse_id IS NOT DISTINCT FROM OLD.nafaqah_spouse_id
       AND NEW.household_id IS NOT DISTINCT FROM OLD.household_id THEN
        v_kept := COALESCE(NEW.amount, 0);
    END IF;

    IF v_kept >= COALESCE(OLD.amount, 0) THEN
        RETURN COALESCE(NEW, OLD);  -- the advance does not shrink
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(
        'spouse_reimbursement:' || OLD.household_id::text || ':' || OLD.nafaqah_spouse_id::text, 0));

    SELECT COALESCE(sum(t.amount), 0) INTO v_advanced
    FROM public.transactions t
    WHERE t.household_id = OLD.household_id
      AND t.nafaqah_spouse_id = OLD.nafaqah_spouse_id
      AND t.nafaqah_class = 'wife_reimbursable';

    -- Net of reversals (20261105001300).
    v_repaid := public.nafaqah_net_repaid(OLD.household_id, OLD.nafaqah_spouse_id);

    v_after := v_advanced - COALESCE(OLD.amount, 0) + v_kept;
    IF v_after < v_repaid THEN
        RAISE EXCEPTION 'This change would leave the wife''s reimbursement ledger overpaid: % SAR already repaid, only % SAR of advances would remain', v_repaid, v_after
            USING ERRCODE = '22023',
                  HINT = 'ledger_would_be_overpaid',
                  DETAIL = format('repaid=%s advances_after=%s', v_repaid, v_after);
    END IF;

    -- What is owed drops to v_after - v_repaid: her pending requests that no longer fit close. The
    -- household before the request rows, as everywhere else; only when there is something to close.
    IF (SELECT COALESCE(sum(q.amount), 0) FROM public.spouse_reimbursement_requests q
        WHERE q.household_id = OLD.household_id AND q.wife_user_id = OLD.nafaqah_spouse_id
          AND NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = q.id))
       > v_after - v_repaid THEN
        PERFORM 1 FROM public.households WHERE id = OLD.household_id FOR KEY SHARE;
        PERFORM public.nafaqah_close_unfit_requests(OLD.household_id, OLD.nafaqah_spouse_id, v_after - v_repaid);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 20261020900000's D3 removal, with her requests first (their outcomes go with them).
CREATE OR REPLACE FUNCTION public.remove_nafaqah_ledger_on_membership_end()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM public.spouse_reimbursement_requests
    WHERE household_id = OLD.household_id AND wife_user_id = OLD.user_id;

    DELETE FROM public.spouse_reimbursements
    WHERE household_id = OLD.household_id AND wife_user_id = OLD.user_id;

    DELETE FROM public.member_allowances
    WHERE household_id = OLD.household_id AND member_user_id = OLD.user_id;

    -- Her advances and personal purchases become ordinary expenses of the household
    -- (the budget triggers move wife_personal amounts into the category budget).
    UPDATE public.transactions
    SET nafaqah_class = NULL,
        nafaqah_spouse_id = NULL
    WHERE household_id = OLD.household_id
      AND nafaqah_spouse_id = OLD.user_id;

    -- Her wife accounts here (section 12) stay their owner's, with their balance and history, as a
    -- former wife's: archived (nobody spends from them or credits them) and naming nobody.
    UPDATE public.accounts
    SET is_archived = true,
        assigned_wife_id = NULL,
        updated_at = now()
    WHERE household_id = OLD.household_id
      AND assigned_wife_id = OLD.user_id;
    RETURN OLD;
END;
$$;

-- 5. Helpers that move money (no client executes them) -----------------------------------------

-- Her wife account for a repayment (section 12), before any lock: she has none that is not archived
-- (wife_account_required: the app offers him to create one), or the one named is not one of hers
-- (wife_account_invalid: not a wife account of this household assigned to her, archived, or none
-- named). Never an account that is not hers. The caller has checked who acts.
CREATE OR REPLACE FUNCTION public.nafaqah_require_wife_account(p_household_id uuid, p_wife_user_id uuid, p_wife_account_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.accounts a
                   WHERE a.household_id = p_household_id AND a.account_type = 'wife'
                     AND a.assigned_wife_id = p_wife_user_id AND a.is_archived IS NOT TRUE) THEN
        RAISE EXCEPTION 'She has no wife account to receive this: create one for her first'
            USING ERRCODE = '22023', HINT = 'wife_account_required';
    END IF;
    IF p_wife_account_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = p_wife_account_id AND a.household_id = p_household_id AND a.account_type = 'wife'
          AND a.assigned_wife_id = p_wife_user_id AND a.is_archived IS NOT TRUE AND a.currency = 'SAR'
    ) THEN
        RAISE EXCEPTION 'Pick one of her wife accounts'
            USING ERRCODE = '22023', HINT = 'wife_account_invalid';
    END IF;
END;
$$;

-- Checks and locks the account a repayment leaves (or a reversal returns to) and, when named, her
-- wife account it credits (or a reversal takes back from). Returns the payer's account id.
-- Lock order, as the purge and transfer_between_accounts take them: a shared pool, the household
-- (KEY SHARE), then the personal accounts (his and her wife account) in id order.
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_lock(p_household_id uuid, p_actor uuid, p_account_id uuid,
                                                         p_wife_user_id uuid, p_wife_account_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_acc public.accounts%ROWTYPE;
    v_wife public.accounts%ROWTYPE;
    v_pass int;
BEGIN
    FOR v_pass IN 1..2 LOOP
        -- Checked before any lock (a clear refusal locks nothing), and again under the locks.
        SELECT * INTO v_acc FROM public.accounts WHERE id = p_account_id;
        IF v_acc.id IS NULL OR v_acc.household_id IS DISTINCT FROM p_household_id
           OR v_acc.is_archived IS TRUE OR v_acc.currency IS DISTINCT FROM 'SAR'
           OR v_acc.account_type = 'wife' THEN
            -- A wife account is never the one a repayment leaves: it is hers to spend.
            RAISE EXCEPTION 'This account cannot be used in this household'
                USING ERRCODE = 'P0002', HINT = 'account_unavailable';
        END IF;
        IF p_wife_account_id IS NOT NULL THEN
            SELECT * INTO v_wife FROM public.accounts WHERE id = p_wife_account_id;
            IF v_wife.id IS NULL OR v_wife.household_id IS DISTINCT FROM p_household_id
               OR v_wife.account_type IS DISTINCT FROM 'wife' OR v_wife.is_archived IS TRUE
               OR v_wife.currency IS DISTINCT FROM 'SAR' OR v_wife.assigned_wife_id IS DISTINCT FROM p_wife_user_id THEN
                RAISE EXCEPTION 'Pick one of her wife accounts'
                    USING ERRCODE = 'P0002', HINT = 'wife_account_invalid';
            END IF;
        END IF;
        -- A spouse member never pays a repayment or takes one back, from a pool above all (review
        -- R1-01). The account is still never picked for anyone: the payer names it.
        IF public.nafaqah_is_spouse_member(p_household_id, p_actor) THEN
            RAISE EXCEPTION 'Forbidden: a spouse member does not pay or reverse a repayment'
                USING ERRCODE = '42501', HINT = 'account_forbidden';
        END IF;
        IF v_acc.is_shared_pool IS TRUE THEN
            IF public.household_member_role(p_household_id, p_actor) IS DISTINCT FROM 'admin' THEN
                RAISE EXCEPTION 'Forbidden: only household admins can move money of a shared pool'
                    USING ERRCODE = '42501', HINT = 'account_forbidden';
            END IF;
        ELSIF v_acc.owner_user_id IS DISTINCT FROM p_actor THEN
            RAISE EXCEPTION 'Forbidden: a personal account is used only by its owner'
                USING ERRCODE = '42501', HINT = 'account_forbidden';
        END IF;
        IF v_pass = 2 THEN
            RETURN v_acc.id;
        END IF;
        -- The purge's order: pools, then the household, then personal accounts (in id order).
        IF v_acc.is_shared_pool IS TRUE THEN
            PERFORM 1 FROM public.accounts WHERE id = v_acc.id FOR UPDATE;
        END IF;
        PERFORM 1 FROM public.households WHERE id = p_household_id FOR KEY SHARE;
        PERFORM 1 FROM public.accounts
        WHERE (id = v_acc.id AND v_acc.is_shared_pool IS NOT TRUE) OR id = p_wife_account_id
        ORDER BY id
        FOR UPDATE;
    END LOOP;
    RETURN NULL;
END;
$$;

-- The account a payment leaves with no wife account (a former member's record), as before.
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_lock_account(p_household_id uuid, p_actor uuid, p_account_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN public.nafaqah_repayment_lock(p_household_id, p_actor, p_account_id, NULL, NULL);
END;
$$;

-- One transfer between locked accounts: p_from goes down by the amount (it must hold it), p_to up
-- by the same amount, in one row, each side exactly once. Either side may be no account: a former
-- member's payment leaves his account for no account, a reversal of a payment that credited
-- nobody returns from no account. p_purpose labels it in each account's own history. A side that
-- is a wife account and does not hold the amount (a reversal after she spent it) is refused as
-- wife_account_insufficient_funds; any other as insufficient_funds.
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_transfer(p_household_id uuid, p_actor uuid, p_from uuid, p_to uuid,
                                                             p_amount numeric, p_purpose text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_from public.accounts%ROWTYPE;
    v_now timestamptz := now();
    v_id uuid;
BEGIN
    IF p_from IS NOT NULL THEN
        SELECT * INTO v_from FROM public.accounts WHERE id = p_from;
        IF v_from.balance IS NULL OR v_from.balance < p_amount THEN
            IF v_from.account_type = 'wife' THEN
                RAISE EXCEPTION 'Her wife account holds % now, less than the % to take back', v_from.balance, p_amount
                    USING ERRCODE = '22000', HINT = 'wife_account_insufficient_funds', DETAIL = COALESCE(v_from.balance, 0)::text;
            END IF;
            RAISE EXCEPTION 'Insufficient funds: balance (%) is less than the repayment (%)', v_from.balance, p_amount
                USING ERRCODE = '22000', HINT = 'insufficient_funds';
        END IF;
        UPDATE public.accounts SET balance = balance - p_amount, updated_at = v_now WHERE id = p_from;
    END IF;
    IF p_to IS NOT NULL THEN
        UPDATE public.accounts SET balance = balance + p_amount, updated_at = v_now WHERE id = p_to;
    END IF;
    -- No free text: the purpose says what it is, and a former member's line names nobody.
    INSERT INTO public.account_transfers (household_id, user_id, from_account_id, to_account_id, amount, fee, timestamp, notes, purpose, created_at)
    VALUES (p_household_id, p_actor, p_from, p_to, p_amount, 0, v_now, NULL, p_purpose, v_now)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- Money out of a locked account, into no account (a former member's payment: she is gone).
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_debit(p_household_id uuid, p_actor uuid, p_account uuid, p_amount numeric, p_purpose text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN public.nafaqah_repayment_transfer(p_household_id, p_actor, p_account, NULL, p_amount, p_purpose);
END;
$$;

-- Money back into a locked account, from no account (the reversal of a former member's payment, or
-- of a repayment from before the wife account, which credited nobody).
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_credit(p_household_id uuid, p_actor uuid, p_account uuid, p_amount numeric, p_purpose text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN public.nafaqah_repayment_transfer(p_household_id, p_actor, NULL, p_account, p_amount, p_purpose);
END;
$$;

-- The repayment itself, for a direct record and for an approved request. The caller has checked
-- who may do it, holds the spouse_reimbursement advisory lock and found no replay. With a request:
-- it must still be pending, and its amount must not exceed what is owed now. The ledger row names
-- who paid (the actor: his own account, or a pool he administers) and keeps what was owed before
-- and after it; then her pending requests that no longer fit close (review R1-03, R1-05, R1-08).
-- The money goes from his account into her wife account (section 12): one transfer, his side down
-- and hers up by exactly the amount.
CREATE OR REPLACE FUNCTION public.nafaqah_repay_from_account(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_actor uuid,
    p_amount numeric,
    p_method text,
    p_notes text,
    p_account_id uuid,
    p_request_key uuid,
    p_request_id uuid,
    p_wife_account_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_amount numeric(14, 2) := p_amount;
    v_from uuid;
    v_outcome text;
    v_outstanding numeric(14, 2);
    v_transfer uuid;
    v_id uuid;
BEGIN
    -- Her wife account: she has one, and the one named is hers (a clear refusal, before any lock).
    PERFORM public.nafaqah_require_wife_account(p_household_id, p_wife_user_id, p_wife_account_id);
    v_from := public.nafaqah_repayment_lock(p_household_id, p_actor, p_account_id, p_wife_user_id, p_wife_account_id);
    -- Under the household lock: a purge that ended her membership meanwhile took her ledger with it.
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'Reimbursements apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    IF p_request_id IS NOT NULL THEN
        PERFORM 1 FROM public.spouse_reimbursement_requests WHERE id = p_request_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'No such request in this household' USING ERRCODE = 'P0002', HINT = 'request_not_found';
        END IF;
        SELECT o.outcome INTO v_outcome FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = p_request_id;
        IF v_outcome IS NOT NULL THEN
            RAISE EXCEPTION 'This request is no longer pending (%)', v_outcome
                USING ERRCODE = '22023', HINT = 'request_not_pending', DETAIL = v_outcome;
        END IF;
    END IF;

    v_outstanding := public.nafaqah_outstanding(p_household_id, p_wife_user_id);
    IF v_amount > v_outstanding THEN
        IF p_request_id IS NOT NULL THEN
            RAISE EXCEPTION 'The request of % is more than the % now owed', v_amount, v_outstanding
                USING ERRCODE = '22023', HINT = 'request_exceeds_outstanding', DETAIL = v_outstanding::text;
        END IF;
        RAISE EXCEPTION 'Reimbursement of % exceeds the outstanding balance of %', v_amount, v_outstanding
            USING ERRCODE = '22023', HINT = 'overpayment', DETAIL = v_outstanding::text;
    END IF;

    -- A key the household used for anything else (another path, wife or record) is refused, under
    -- every lock this call takes (review R2-01).
    PERFORM public.nafaqah_claim_request_key(p_household_id, p_request_key);

    v_transfer := public.nafaqah_repayment_transfer(p_household_id, p_actor, v_from, p_wife_account_id, v_amount, 'wife_repayment');

    INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, paid_by_user_id, amount, payment_method, notes,
                                              recorded_by, request_key, transfer_id, kind,
                                              outstanding_before, outstanding_after, account_id, wife_account_id)
    VALUES (p_household_id, p_wife_user_id, p_actor, v_amount, p_method, NULLIF(left(trim(p_notes), 500), ''),
            p_actor, p_request_key, v_transfer, 'payment',
            v_outstanding, v_outstanding - v_amount, v_from, p_wife_account_id)
    RETURNING id INTO v_id;

    IF p_request_id IS NOT NULL THEN
        INSERT INTO public.spouse_reimbursement_request_outcomes (request_id, outcome, reimbursement_id, decided_by)
        VALUES (p_request_id, 'approved', v_id, p_actor);
    END IF;

    -- Less is owed now: what she still has pending must fit in it.
    PERFORM public.nafaqah_close_unfit_requests(p_household_id, p_wife_user_id, v_outstanding - v_amount);

    RETURN jsonb_build_object(
        'success', true,
        'replayed', false,
        'reimbursement_id', v_id,
        'request_id', p_request_id,
        'household_id', p_household_id,
        'wife_user_id', p_wife_user_id,
        'paid_by_user_id', p_actor,
        'amount', v_amount,
        'payment_method', p_method,
        'account_id', v_from,
        'wife_account_id', p_wife_account_id,
        'transfer_id', v_transfer,
        'outstanding_before', v_outstanding,
        'outstanding_after', v_outstanding - v_amount
    );
END;
$$;

-- The answer to a replayed repayment or reversal: what the first call stored, the outstanding
-- figures and the account included (review R1-05, R2-06), whatever happened since.
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_replay(p_row public.spouse_reimbursements, p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_transfer public.account_transfers%ROWTYPE;
BEGIN
    SELECT * INTO v_transfer FROM public.account_transfers WHERE id = p_row.transfer_id;
    RETURN jsonb_build_object(
        'success', true, 'replayed', true,
        'reimbursement_id', p_row.id,
        'request_id', p_request_id,
        'kind', p_row.kind,
        'reverses_id', p_row.reverses_id,
        'household_id', p_row.household_id,
        'wife_user_id', p_row.wife_user_id,
        'paid_by_user_id', p_row.paid_by_user_id,
        'amount', p_row.amount,
        'payment_method', p_row.payment_method,
        'account_id', COALESCE(p_row.account_id,
                               CASE WHEN p_row.kind = 'reversal' THEN v_transfer.to_account_id ELSE v_transfer.from_account_id END),
        'wife_account_id', p_row.wife_account_id,
        'transfer_id', p_row.transfer_id,
        'outstanding_before', p_row.outstanding_before,
        'outstanding_after', p_row.outstanding_after);
END;
$$;

-- 6. Repaying the wife ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_spouse_reimbursement(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_amount numeric,
    p_payment_method text,
    p_notes text,
    p_actor_user_id uuid,
    p_account_id uuid,
    p_request_key uuid,
    p_wife_account_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_method text := lower(COALESCE(NULLIF(trim(p_payment_method), ''), 'cash'));
    v_prev public.spouse_reimbursements%ROWTYPE;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'Reimbursements apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;
    -- Every repayment leaves an account: a call without one comes from an app that predates it.
    IF p_account_id IS NULL THEN
        RAISE EXCEPTION 'Repayments are paid from an account: update the app'
            USING ERRCODE = '0A000', HINT = 'app_update_required';
    END IF;
    -- She asks (request_spouse_reimbursement); her husband (when he is gone, an admin who is not a
    -- wife) records or approves.
    IF v_actor = p_wife_user_id THEN
        RAISE EXCEPTION 'Forbidden: the wife asks for a repayment to be recorded; she does not record it'
            USING ERRCODE = '42501', HINT = 'wife_must_request';
    END IF;
    -- Never a wife, not even a co-wife who is an admin (review R1-01).
    IF NOT public.nafaqah_may_repay(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only her husband, or an admin who is not a wife when he is gone, records a repayment'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'Reimbursement must be a positive SAR amount with at most 2 decimals' USING ERRCODE = '22023', HINT = 'invalid_amount';
    END IF;
    IF v_method NOT IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method %', v_method USING ERRCODE = '22023', HINT = 'invalid_payment_method';
    END IF;
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required to move money' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    -- Serialise everything that changes what one wife is owed, so two calls cannot both pass a check.
    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_household_id::text || ':' || p_wife_user_id::text, 0));

    -- The same tap again: answer as the first time, change nothing. Only the same call is a replay:
    -- the same wife, amount, method, account and wife account (the stored ones, even if deleted
    -- since: review R2-06), by the same person, and not an approval's key (review R1-04). A key
    -- used anywhere else in the household is refused when it is claimed (review R2-01).
    SELECT * INTO v_prev FROM public.spouse_reimbursements
    WHERE household_id = p_household_id AND request_key = p_request_key;
    IF v_prev.id IS NOT NULL THEN
        IF v_prev.wife_user_id IS DISTINCT FROM p_wife_user_id OR v_prev.kind <> 'payment'
           OR v_prev.amount IS DISTINCT FROM p_amount OR v_prev.payment_method IS DISTINCT FROM v_method
           OR v_prev.recorded_by IS DISTINCT FROM v_actor
           OR v_prev.account_id IS DISTINCT FROM p_account_id
           OR v_prev.wife_account_id IS DISTINCT FROM p_wife_account_id
           OR EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.reimbursement_id = v_prev.id) THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN public.nafaqah_repayment_replay(v_prev, NULL);
    END IF;

    RETURN public.nafaqah_repay_from_account(p_household_id, p_wife_user_id, v_actor, p_amount, v_method, p_notes,
                                             p_account_id, p_request_key, NULL, p_wife_account_id);
END;
$$;

-- The old signature: old app builds and the old API. Nothing is recorded without an account.
CREATE OR REPLACE FUNCTION public.record_spouse_reimbursement(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_amount numeric,
    p_payment_method text DEFAULT 'cash',
    p_notes text DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'Repayments are paid from an account: update the app'
        USING ERRCODE = '0A000', HINT = 'app_update_required';
END;
$$;

-- 7. The wife's requests ----------------------------------------------------------------------------

-- "I received X": she asks; nothing moves and nothing owed changes until it is approved. She names
-- which of her wife accounts it went into (section 12); the approval credits that one.
CREATE OR REPLACE FUNCTION public.request_spouse_reimbursement(
    p_household_id uuid,
    p_amount numeric,
    p_payment_method text,
    p_request_key uuid,
    p_actor_user_id uuid,
    p_wife_account_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_method text := lower(COALESCE(NULLIF(trim(p_payment_method), ''), 'cash'));
    v_req public.spouse_reimbursement_requests%ROWTYPE;
    v_outstanding numeric(14, 2);
    v_pending numeric(14, 2);
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only the wife asks for a repayment to be recorded'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'A request is a positive SAR amount with at most 2 decimals' USING ERRCODE = '22023', HINT = 'invalid_amount';
    END IF;
    IF v_method NOT IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method %', v_method USING ERRCODE = '22023', HINT = 'invalid_payment_method';
    END IF;
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_household_id::text || ':' || v_actor::text, 0));
    -- The household, as the purge locks it (FOR UPDATE), then she is checked again (review R2-05): a
    -- purge that ended her membership while this call waited has closed her requests, and a new one
    -- would be the pending request of a non-member.
    PERFORM 1 FROM public.households WHERE id = p_household_id FOR KEY SHARE;
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only the wife asks for a repayment to be recorded'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;

    SELECT * INTO v_req FROM public.spouse_reimbursement_requests
    WHERE household_id = p_household_id AND request_key = p_request_key;
    IF v_req.id IS NULL THEN
        -- Into one of her own wife accounts (section 12), never anyone else's.
        PERFORM public.nafaqah_require_wife_account(p_household_id, v_actor, p_wife_account_id);
        v_outstanding := public.nafaqah_outstanding(p_household_id, v_actor);
        SELECT COALESCE(sum(q.amount), 0) INTO v_pending
        FROM public.spouse_reimbursement_requests q
        WHERE q.household_id = p_household_id AND q.wife_user_id = v_actor
          AND NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = q.id);
        IF v_pending + p_amount > v_outstanding THEN
            RAISE EXCEPTION 'Pending requests (% with this one) would exceed the % owed', v_pending + p_amount, v_outstanding
                USING ERRCODE = '22023', HINT = 'pending_exceeds_outstanding',
                      DETAIL = GREATEST(v_outstanding - v_pending, 0)::text;
        END IF;
        -- A key the household used for anything else is refused (review R2-01).
        PERFORM public.nafaqah_claim_request_key(p_household_id, p_request_key);
        -- The moment itself, not the transaction's start: the order she made them in decides which
        -- close first when less is owed (nafaqah_close_unfit_requests).
        INSERT INTO public.spouse_reimbursement_requests (household_id, wife_user_id, amount, payment_method, request_key, created_at,
                                                          wife_account_id)
        VALUES (p_household_id, v_actor, p_amount, v_method, p_request_key, clock_timestamp(), p_wife_account_id)
        RETURNING * INTO v_req;
        RETURN jsonb_build_object(
            'success', true, 'replayed', false, 'request_id', v_req.id, 'status', 'pending',
            'amount', v_req.amount, 'payment_method', v_req.payment_method, 'created_at', v_req.created_at,
            'wife_account_id', v_req.wife_account_id,
            'outstanding', v_outstanding, 'pending_requested', v_pending + v_req.amount);
    END IF;

    -- Only the same request is a replay: hers, for the same amount, method and wife account
    -- (review R1-04).
    IF v_req.wife_user_id IS DISTINCT FROM v_actor OR v_req.amount IS DISTINCT FROM p_amount
       OR v_req.payment_method IS DISTINCT FROM v_method OR v_req.wife_account_id IS DISTINCT FROM p_wife_account_id THEN
        RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
    END IF;
    RETURN jsonb_build_object(
        'success', true, 'replayed', true, 'request_id', v_req.id,
        'status', COALESCE((SELECT o.outcome FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = v_req.id), 'pending'),
        'amount', v_req.amount, 'payment_method', v_req.payment_method, 'created_at', v_req.created_at,
        'wife_account_id', v_req.wife_account_id,
        'outstanding', public.nafaqah_outstanding(p_household_id, v_actor));
END;
$$;

-- Closes a pending request with an outcome that moves nothing: her cancel, or his decline.
-- Returns the answer; the same outcome again is a replay.
CREATE OR REPLACE FUNCTION public.nafaqah_request_close(p_request public.spouse_reimbursement_requests, p_outcome text,
                                                        p_reason text, p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_existing text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_request.household_id::text || ':' || p_request.wife_user_id::text, 0));
    PERFORM 1 FROM public.spouse_reimbursement_requests WHERE id = p_request.id FOR UPDATE;
    SELECT o.outcome INTO v_existing FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = p_request.id;
    IF v_existing = p_outcome THEN
        RETURN jsonb_build_object('success', true, 'replayed', true, 'request_id', p_request.id, 'outcome', v_existing);
    ELSIF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'This request is no longer pending (%)', v_existing
            USING ERRCODE = '22023', HINT = 'request_not_pending', DETAIL = v_existing;
    END IF;
    INSERT INTO public.spouse_reimbursement_request_outcomes (request_id, outcome, reason, decided_by)
    VALUES (p_request.id, p_outcome, p_reason, p_actor);
    RETURN jsonb_build_object('success', true, 'replayed', false, 'request_id', p_request.id, 'outcome', p_outcome,
                              'reason', p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_spouse_reimbursement_request(
    p_household_id uuid,
    p_request_id uuid,
    p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_req public.spouse_reimbursement_requests%ROWTYPE;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    SELECT * INTO v_req FROM public.spouse_reimbursement_requests WHERE id = p_request_id AND household_id = p_household_id;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'No such request in this household' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_req.wife_user_id IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'Forbidden: only she cancels her request' USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    RETURN public.nafaqah_request_close(v_req, 'cancelled', NULL, v_actor);
END;
$$;

CREATE OR REPLACE FUNCTION public.decline_spouse_reimbursement_request(
    p_household_id uuid,
    p_request_id uuid,
    p_reason text,
    p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_req public.spouse_reimbursement_requests%ROWTYPE;
    v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    -- Her husband, or an admin who is not a wife when he is gone: never she herself, nor a co-wife (R1-01, R3-01).
    -- Checked before the request is looked up (review R3C-05): anyone else gets this answer for a
    -- request that exists and for an id of nothing alike.
    IF NOT public.nafaqah_may_repay(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only her husband, or an admin who is not a wife when he is gone, declines a request'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    SELECT * INTO v_req FROM public.spouse_reimbursement_requests WHERE id = p_request_id AND household_id = p_household_id;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'No such request in this household' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_actor = v_req.wife_user_id THEN
        RAISE EXCEPTION 'Forbidden: only her husband, or an admin who is not a wife when he is gone, declines a request'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    -- At most 200 characters, counted as Unicode code points (char_length), as the API (len) and
    -- the app (runes) count them.
    IF char_length(v_reason) > 200 THEN
        RAISE EXCEPTION 'A reason is at most 200 characters' USING ERRCODE = '22023', HINT = 'invalid_reason';
    END IF;
    RETURN public.nafaqah_request_close(v_req, 'declined', v_reason, v_actor);
END;
$$;

-- Approval: the normal repayment of exactly the requested amount, from the account he picks, into
-- the wife account she named; he may name another of hers instead (p_wife_account_id), never an
-- account that is not hers (section 12).
CREATE OR REPLACE FUNCTION public.approve_spouse_reimbursement_request(
    p_household_id uuid,
    p_request_id uuid,
    p_account_id uuid,
    p_request_key uuid,
    p_actor_user_id uuid,
    p_wife_account_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_req public.spouse_reimbursement_requests%ROWTYPE;
    v_prev public.spouse_reimbursements%ROWTYPE;
    v_wife_account uuid;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    -- Her husband, or an admin who is not a wife when he is gone: never she herself, nor a co-wife (R1-01, R3-01).
    -- Checked before the request is looked up (review R3C-05): anyone else gets this answer for a
    -- request that exists and for an id of nothing alike.
    IF NOT public.nafaqah_may_repay(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only her husband, or an admin who is not a wife when he is gone, approves a request'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    SELECT * INTO v_req FROM public.spouse_reimbursement_requests WHERE id = p_request_id AND household_id = p_household_id;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'No such request in this household' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_actor = v_req.wife_user_id THEN
        RAISE EXCEPTION 'Forbidden: only her husband, or an admin who is not a wife when he is gone, approves a request'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    IF p_account_id IS NULL THEN
        RAISE EXCEPTION 'An approval is paid from an account' USING ERRCODE = '22023', HINT = 'account_required';
    END IF;
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required to move money' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_household_id::text || ':' || v_req.wife_user_id::text, 0));

    -- The wife account she named, unless he names another (checked to be hers below).
    v_wife_account := COALESCE(p_wife_account_id, v_req.wife_account_id);

    SELECT * INTO v_prev FROM public.spouse_reimbursements
    WHERE household_id = p_household_id AND request_key = p_request_key;
    IF v_prev.id IS NOT NULL THEN
        -- Only the same approval is a replay: this request, from the same account into the same
        -- wife account (the stored ones, review R2-06), by the same person (review R1-04).
        IF NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o
                       WHERE o.request_id = p_request_id AND o.reimbursement_id = v_prev.id)
           OR v_prev.recorded_by IS DISTINCT FROM v_actor
           OR v_prev.account_id IS DISTINCT FROM p_account_id
           OR v_prev.wife_account_id IS DISTINCT FROM v_wife_account THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN public.nafaqah_repayment_replay(v_prev, p_request_id);
    END IF;

    RETURN public.nafaqah_repay_from_account(p_household_id, v_req.wife_user_id, v_actor, v_req.amount, v_req.payment_method,
                                             NULL, p_account_id, p_request_key, p_request_id, v_wife_account);
END;
$$;

-- 8. Reversing a repayment --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reverse_spouse_reimbursement(
    p_household_id uuid,
    p_reimbursement_id uuid,
    p_request_key uuid,
    p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_orig public.spouse_reimbursements%ROWTYPE;
    v_prev public.spouse_reimbursements%ROWTYPE;
    v_account uuid;
    v_wife_account uuid;
    v_before numeric(14, 2);
    v_after numeric(14, 2);
    v_transfer uuid;
    v_id uuid;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required to move money' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;
    -- Never a wife (review R1-01). Only her ledger's manager now: her husband, or an admin who is
    -- not a wife when he is gone (review R3B-06, owner decision 2026-11-06, superseding R1-07): a
    -- replaced husband or a demoted admin no longer reverses, even from his own account. Within
    -- that, the account it left decides (the account helper below, under the locks): a personal
    -- account only by its owner, a pool only by an admin. So a personal account's repayment whose
    -- owner no longer manages her ledger is reversed by nobody. Checked before the repayment is
    -- looked up (review R3C-05): anyone else gets the same answer for a repayment that exists and
    -- for an id of nothing.
    IF public.nafaqah_is_spouse_member(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: a wife does not reverse a repayment'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    IF NOT public.nafaqah_may_manage_ledgers(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: a repayment is reversed by the husband, or by an admin who is not a wife when he is gone'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    SELECT * INTO v_orig FROM public.spouse_reimbursements WHERE id = p_reimbursement_id AND household_id = p_household_id;
    IF v_orig.id IS NULL THEN
        RAISE EXCEPTION 'No such repayment in this household' USING ERRCODE = 'P0002', HINT = 'reimbursement_not_found';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_household_id::text || ':' || v_orig.wife_user_id::text, 0));

    SELECT * INTO v_prev FROM public.spouse_reimbursements
    WHERE household_id = p_household_id AND request_key = p_request_key;
    IF v_prev.id IS NOT NULL THEN
        IF v_prev.kind <> 'reversal' OR v_prev.reverses_id IS DISTINCT FROM v_orig.id
           OR v_prev.recorded_by IS DISTINCT FROM v_actor THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN public.nafaqah_repayment_replay(v_prev, NULL);
    END IF;

    IF v_orig.kind <> 'payment' THEN
        RAISE EXCEPTION 'A reversal is not reversed' USING ERRCODE = '22023', HINT = 'not_reversible';
    END IF;
    IF EXISTS (SELECT 1 FROM public.spouse_reimbursements WHERE reverses_id = v_orig.id) THEN
        RAISE EXCEPTION 'This repayment is already reversed' USING ERRCODE = '22023', HINT = 'already_reversed';
    END IF;
    IF v_orig.transfer_id IS NULL THEN
        RAISE EXCEPTION 'This repayment moved no money in the app, so there is nothing to return'
            USING ERRCODE = '22023', HINT = 'reversal_not_tracked';
    END IF;
    SELECT t.from_account_id, t.to_account_id INTO v_account, v_wife_account
    FROM public.account_transfers t WHERE t.id = v_orig.transfer_id;
    IF v_account IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = v_account AND a.household_id = p_household_id AND a.is_archived IS NOT TRUE AND a.currency = 'SAR'
    ) THEN
        RAISE EXCEPTION 'The account it was paid from is archived or gone' USING ERRCODE = '22023', HINT = 'reversal_account_unavailable';
    END IF;
    -- The wife account it credited gives the money back (section 12), so it must still be usable:
    -- archived (her account deleted, or by its owner) or gone is refused as for any account. A
    -- repayment from before the wife account credited nobody: its reversal returns from no account.
    IF v_orig.wife_account_id IS NOT NULL AND (v_wife_account IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = v_wife_account AND a.household_id = p_household_id AND a.account_type = 'wife'
          AND a.is_archived IS NOT TRUE AND a.currency = 'SAR' AND a.assigned_wife_id = v_orig.wife_user_id
    )) THEN
        RAISE EXCEPTION 'Her wife account it was paid into is archived or gone' USING ERRCODE = '22023', HINT = 'reversal_account_unavailable';
    END IF;
    IF v_orig.wife_account_id IS NULL THEN
        v_wife_account := NULL;
    END IF;
    -- The manager (checked above) reverses from the account it left as the account rules say: a
    -- pool's only as an admin, a personal account's only as its owner (the helper below, under the
    -- locks), and takes it back from her wife account.
    BEGIN
        v_account := public.nafaqah_repayment_lock(p_household_id, v_actor, v_account, v_orig.wife_user_id, v_wife_account);
    EXCEPTION WHEN SQLSTATE 'P0002' THEN
        -- Archived or deleted while this call waited for it, by a purge of its owner say (review
        -- R2-08): the same answer as when it was already gone.
        RAISE EXCEPTION 'The account it was paid from is archived or gone' USING ERRCODE = '22023', HINT = 'reversal_account_unavailable';
    END;
    -- Under the household lock: a purge that ended her membership meanwhile took her ledger with it.
    IF NOT EXISTS (SELECT 1 FROM public.spouse_reimbursements WHERE id = v_orig.id) THEN
        RAISE EXCEPTION 'No such repayment in this household' USING ERRCODE = 'P0002', HINT = 'reimbursement_not_found';
    END IF;
    -- A key the household used for anything else is refused (review R2-01).
    PERFORM public.nafaqah_claim_request_key(p_household_id, p_request_key);

    v_before := public.nafaqah_outstanding(p_household_id, v_orig.wife_user_id);
    -- One transfer back: out of her wife account (it must still hold the amount:
    -- wife_account_insufficient_funds), into his account.
    v_transfer := public.nafaqah_repayment_transfer(p_household_id, v_actor, v_wife_account, v_account, v_orig.amount,
                                                    'wife_repayment_reversal');
    -- What is owed after it, as nafaqah_outstanding will count it with this row (never below zero).
    v_after := GREATEST(
        (SELECT COALESCE(sum(t.amount), 0) FROM public.transactions t
         WHERE t.household_id = p_household_id AND t.nafaqah_spouse_id = v_orig.wife_user_id
           AND t.nafaqah_class = 'wife_reimbursable')
      - public.nafaqah_net_repaid(p_household_id, v_orig.wife_user_id) + v_orig.amount,
        0);
    INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, paid_by_user_id, amount, payment_method, notes,
                                              recorded_by, request_key, transfer_id, kind, reverses_id,
                                              outstanding_before, outstanding_after, account_id, wife_account_id)
    VALUES (p_household_id, v_orig.wife_user_id, v_orig.paid_by_user_id, v_orig.amount, v_orig.payment_method, NULL,
            v_actor, p_request_key, v_transfer, 'reversal', v_orig.id, v_before, v_after, v_account, v_wife_account)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', true, 'replayed', false,
        'reimbursement_id', v_id, 'kind', 'reversal', 'reverses_id', v_orig.id,
        'household_id', p_household_id, 'wife_user_id', v_orig.wife_user_id,
        'paid_by_user_id', v_orig.paid_by_user_id,
        'amount', v_orig.amount, 'payment_method', v_orig.payment_method,
        'account_id', v_account, 'wife_account_id', v_wife_account, 'transfer_id', v_transfer,
        'outstanding_before', v_before,
        'outstanding_after', v_after);
END;
$$;

-- 9. A former member's record ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_former_member_debt_payment(
    p_household_id uuid,
    p_debt_id uuid,
    p_amount numeric,
    p_payment_method text,
    p_request_key uuid,
    p_actor_user_id uuid,
    p_account_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_debt public.former_member_debts%ROWTYPE;
    v_event public.former_member_debt_events%ROWTYPE;
    v_method text := lower(COALESCE(NULLIF(trim(p_payment_method), ''), 'cash'));
    v_remaining numeric(14, 2);
    v_from uuid;
    v_transfer_id uuid;
BEGIN
    PERFORM public.former_member_debt_require_manager(p_household_id, v_actor);
    IF p_account_id IS NULL THEN
        RAISE EXCEPTION 'Payments are paid from an account: update the app'
            USING ERRCODE = '0A000', HINT = 'app_update_required';
    END IF;
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    -- A replay answers before any account is checked or locked: events never change.
    SELECT e.* INTO v_event FROM public.former_member_debt_events e
    JOIN public.former_member_debts d ON d.id = e.debt_id AND d.household_id = p_household_id
    WHERE e.debt_id = p_debt_id AND e.request_key = p_request_key;
    -- A record of another household is named as such, before any account is looked at (no lock).
    IF NOT EXISTS (SELECT 1 FROM public.former_member_debts WHERE id = p_debt_id AND household_id = p_household_id) THEN
        RAISE EXCEPTION 'No such record in this household' USING ERRCODE = 'P0002', HINT = 'debt_not_found';
    END IF;
    -- The account before the record row: a purge deleting the household holds the pools and
    -- the household and then waits for the record row, so it must never be held while waiting.
    IF v_event.id IS NULL THEN
        v_from := public.nafaqah_repayment_lock_account(p_household_id, v_actor, p_account_id);
    END IF;

    SELECT * INTO v_debt FROM public.former_member_debts
    WHERE id = p_debt_id AND household_id = p_household_id
    FOR UPDATE;
    IF v_debt.id IS NULL THEN
        RAISE EXCEPTION 'No such record in this household' USING ERRCODE = 'P0002', HINT = 'debt_not_found';
    END IF;

    -- The same tap again: answer as the first time, change nothing.
    SELECT * INTO v_event FROM public.former_member_debt_events
    WHERE debt_id = p_debt_id AND request_key = p_request_key;
    IF v_event.id IS NOT NULL THEN
        -- Only the same call is a replay: a payment of the same amount and method, from the same
        -- account (the stored one, even if it was deleted since: review R2-06), by the same person
        -- (review R1-04). It answers what the first call answered: what remained after it, and the
        -- status that left (review R1-05).
        IF v_event.kind <> 'payment' OR v_event.amount IS DISTINCT FROM p_amount
           OR v_event.payment_method IS DISTINCT FROM v_method OR v_event.recorded_by IS DISTINCT FROM v_actor
           OR v_event.account_id IS DISTINCT FROM p_account_id THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'replayed', true, 'event_id', v_event.id, 'debt_id', v_debt.id,
            'amount', v_event.amount, 'payment_method', v_event.payment_method,
            'remaining', v_event.remaining_after,
            'status', CASE WHEN v_event.remaining_after = 0 THEN 'settled' ELSE 'open' END,
            'transfer_id', v_event.transfer_id,
            'account_id', v_event.account_id);
    END IF;
    IF v_debt.status <> 'open' THEN
        RAISE EXCEPTION 'This record is already closed' USING ERRCODE = '22023', HINT = 'debt_closed';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'A payment is a positive SAR amount with at most 2 decimals' USING ERRCODE = '22023', HINT = 'invalid_amount';
    END IF;
    IF v_method NOT IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method %', v_method USING ERRCODE = '22023', HINT = 'invalid_payment_method';
    END IF;

    v_remaining := v_debt.original_amount - v_debt.paid_amount;
    IF p_amount > v_remaining THEN
        RAISE EXCEPTION 'Payment of % exceeds the remaining % SAR', p_amount, v_remaining
            USING ERRCODE = '22023', HINT = 'overpayment', DETAIL = v_remaining::text;
    END IF;

    -- A key the household used for anything else (another path or another record) is refused, under
    -- every lock this call takes (review R2-01).
    PERFORM public.nafaqah_claim_request_key(p_household_id, p_request_key);

    -- She is gone: only his side moves.
    v_transfer_id := public.nafaqah_repayment_debit(p_household_id, v_actor, v_from, p_amount, 'former_member_payment');

    UPDATE public.former_member_debts
    SET paid_amount = paid_amount + p_amount,
        status = CASE WHEN p_amount = v_remaining THEN 'settled' ELSE 'open' END,
        closed_at = CASE WHEN p_amount = v_remaining THEN now() END
    WHERE id = p_debt_id
    RETURNING * INTO v_debt;

    INSERT INTO public.former_member_debt_events (debt_id, kind, amount, payment_method, remaining_after, recorded_by, request_key,
                                                  transfer_id, account_id)
    VALUES (p_debt_id, 'payment', p_amount, v_method, v_remaining - p_amount, v_actor, p_request_key, v_transfer_id, v_from)
    RETURNING * INTO v_event;

    RETURN jsonb_build_object(
        'success', true, 'replayed', false, 'event_id', v_event.id, 'debt_id', v_debt.id,
        'amount', v_event.amount, 'payment_method', v_event.payment_method,
        'remaining', v_event.remaining_after, 'status', v_debt.status,
        'transfer_id', v_transfer_id, 'account_id', v_from);
END;
$$;

-- The old signature: old app builds and the old API. Nothing is recorded without an account.
CREATE OR REPLACE FUNCTION public.record_former_member_debt_payment(
    p_household_id uuid,
    p_debt_id uuid,
    p_amount numeric,
    p_payment_method text DEFAULT 'cash',
    p_request_key uuid DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'Payments are paid from an account: update the app'
        USING ERRCODE = '0A000', HINT = 'app_update_required';
END;
$$;

-- Reversing a payment of the record: the money goes back to his account, the amount back to what
-- remains, and a settled record opens again. Not after her waiver: that closed what remained.
CREATE OR REPLACE FUNCTION public.reverse_former_member_debt_payment(
    p_household_id uuid,
    p_debt_id uuid,
    p_event_id uuid,
    p_request_key uuid,
    p_actor_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_debt public.former_member_debts%ROWTYPE;
    v_orig public.former_member_debt_events%ROWTYPE;
    v_event public.former_member_debt_events%ROWTYPE;
    v_account uuid;
    v_pass int;
    v_transfer uuid;
BEGIN
    -- Never a wife (review R1-01). Only the record's manager now: the husband it is owed by, or an
    -- admin who is not a wife when he is gone (review R3B-06, owner decision 2026-11-06, superseding
    -- R1-07); within that, the account it left decides (the account helper below, under the locks):
    -- a personal account only by its owner, a pool only by an admin.
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF public.nafaqah_is_spouse_member(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: a wife does not reverse a payment of this record'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    PERFORM public.former_member_debt_require_manager(p_household_id, v_actor);
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    -- Checked without locks (a clear refusal or a replay locks nothing), then again under the record lock.
    FOR v_pass IN 1..2 LOOP
        IF v_pass = 2 THEN
            BEGIN
                v_account := public.nafaqah_repayment_lock_account(p_household_id, v_actor, v_account);
            EXCEPTION WHEN SQLSTATE 'P0002' THEN
                -- Archived or deleted while this call waited for it (review R2-08).
                RAISE EXCEPTION 'The account it was paid from is archived or gone' USING ERRCODE = '22023', HINT = 'reversal_account_unavailable';
            END;
            SELECT * INTO v_debt FROM public.former_member_debts WHERE id = p_debt_id AND household_id = p_household_id FOR UPDATE;
        ELSE
            SELECT * INTO v_debt FROM public.former_member_debts WHERE id = p_debt_id AND household_id = p_household_id;
        END IF;
        IF v_debt.id IS NULL THEN
            RAISE EXCEPTION 'No such record in this household' USING ERRCODE = 'P0002', HINT = 'debt_not_found';
        END IF;

        SELECT * INTO v_event FROM public.former_member_debt_events WHERE debt_id = p_debt_id AND request_key = p_request_key;
        IF v_event.id IS NOT NULL THEN
            IF v_event.kind <> 'reversal' OR v_event.reverses_event_id IS DISTINCT FROM p_event_id
               OR v_event.recorded_by IS DISTINCT FROM v_actor THEN
                RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
            END IF;
            RETURN jsonb_build_object(
                'success', true, 'replayed', true, 'event_id', v_event.id, 'debt_id', v_debt.id,
                'reverses_event_id', v_event.reverses_event_id, 'amount', v_event.amount,
                'remaining', v_event.remaining_after, 'status', 'open', 'transfer_id', v_event.transfer_id,
                'account_id', COALESCE(v_event.account_id,
                                       (SELECT t.to_account_id FROM public.account_transfers t WHERE t.id = v_event.transfer_id)));
        END IF;

        SELECT * INTO v_orig FROM public.former_member_debt_events WHERE id = p_event_id AND debt_id = p_debt_id;
        IF v_orig.id IS NULL THEN
            RAISE EXCEPTION 'No such payment of this record' USING ERRCODE = 'P0002', HINT = 'payment_not_found';
        END IF;
        IF v_orig.kind <> 'payment' THEN
            RAISE EXCEPTION 'Only a payment is reversed' USING ERRCODE = '22023', HINT = 'not_reversible';
        END IF;
        IF EXISTS (SELECT 1 FROM public.former_member_debt_events WHERE reverses_event_id = v_orig.id) THEN
            RAISE EXCEPTION 'This payment is already reversed' USING ERRCODE = '22023', HINT = 'already_reversed';
        END IF;
        IF v_debt.status = 'waived' THEN
            RAISE EXCEPTION 'She waived what remained after this payment' USING ERRCODE = '22023', HINT = 'reversal_after_waiver';
        END IF;
        IF v_orig.transfer_id IS NULL THEN
            RAISE EXCEPTION 'This payment moved no money in the app, so there is nothing to return'
                USING ERRCODE = '22023', HINT = 'reversal_not_tracked';
        END IF;
        SELECT t.from_account_id INTO v_account FROM public.account_transfers t WHERE t.id = v_orig.transfer_id;
        IF v_account IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.accounts a
            WHERE a.id = v_account AND a.household_id = p_household_id AND a.is_archived IS NOT TRUE AND a.currency = 'SAR'
        ) THEN
            RAISE EXCEPTION 'The account it was paid from is archived or gone' USING ERRCODE = '22023', HINT = 'reversal_account_unavailable';
        END IF;
    END LOOP;

    -- A key the household used for anything else is refused (review R2-01).
    PERFORM public.nafaqah_claim_request_key(p_household_id, p_request_key);

    v_transfer := public.nafaqah_repayment_credit(p_household_id, v_actor, v_account, v_orig.amount, 'former_member_payment_reversal');

    UPDATE public.former_member_debts
    SET paid_amount = paid_amount - v_orig.amount,
        status = 'open',
        closed_at = NULL
    WHERE id = p_debt_id
    RETURNING * INTO v_debt;

    INSERT INTO public.former_member_debt_events (debt_id, kind, amount, payment_method, remaining_after, recorded_by,
                                                  request_key, transfer_id, reverses_event_id, account_id)
    VALUES (p_debt_id, 'reversal', v_orig.amount, NULL, v_debt.original_amount - v_debt.paid_amount, v_actor,
            p_request_key, v_transfer, v_orig.id, v_account)
    RETURNING * INTO v_event;

    RETURN jsonb_build_object(
        'success', true, 'replayed', false, 'event_id', v_event.id, 'debt_id', v_debt.id,
        'reverses_event_id', v_orig.id, 'amount', v_event.amount,
        'remaining', v_event.remaining_after, 'status', v_debt.status,
        'transfer_id', v_transfer, 'account_id', v_account);
END;
$$;

-- 10. The purge: 001200's function, closing pending requests and removing his decline reasons -----
-- With the wife account (section 12): her purge archives the wife accounts assigned to her, which
-- stay their owner's with their balance and history and name nobody (assigned_wife_id cleared, her
-- name taken out of the account's name); his purge passes the wife accounts he owns to the
-- household's primary admin, or to the wife it is assigned to when that admin is another wife
-- (account_deletion_wife_account_recipient). Both are in the ledger invariant: their balances
-- do not move, also when her personal purchases on them are deleted.

-- Who a wife account of p_user_id (being deleted) passes to: the household's primary admin (the
-- longest-standing other admin when that is p_user_id), unless that admin is a wife other than the
-- one it is assigned to, then the wife it is assigned to. A former wife's account (no one assigned)
-- never goes to a wife: then the longest-standing admin who is not a wife. NULL: nobody is left to
-- take it, and it goes with his accounts.
CREATE OR REPLACE FUNCTION public.account_deletion_wife_account_recipient(p_account_id uuid, p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN p.primary_admin IS NOT NULL
             AND (p.primary_admin = a.assigned_wife_id OR NOT public.nafaqah_is_spouse_member(a.household_id, p.primary_admin))
            THEN p.primary_admin
        WHEN a.assigned_wife_id IS NOT NULL AND a.assigned_wife_id <> p_user_id
             AND public.nafaqah_is_spouse_member(a.household_id, a.assigned_wife_id)
            THEN a.assigned_wife_id
        ELSE (SELECT o.user_id FROM public.household_memberships o
              WHERE o.household_id = a.household_id AND o.user_id <> p_user_id AND o.role = 'admin'
                AND o.financial_role IS DISTINCT FROM 'spouse'
              ORDER BY public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
              LIMIT 1)
    END
    FROM public.accounts a
    CROSS JOIN LATERAL (
        SELECT COALESCE(
            (SELECT h.owner_user_id FROM public.households h
             JOIN public.household_memberships m ON m.household_id = h.id AND m.user_id = h.owner_user_id
             WHERE h.id = a.household_id AND h.owner_user_id <> p_user_id),
            (SELECT o.user_id FROM public.household_memberships o
             WHERE o.household_id = a.household_id AND o.user_id <> p_user_id AND o.role = 'admin'
             ORDER BY public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
             LIMIT 1)) AS primary_admin
    ) p
    WHERE a.id = p_account_id AND a.account_type = 'wife';
$$;

CREATE OR REPLACE FUNCTION public.prepare_account_purge(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req public.account_deletion_requests%ROWTYPE;
    v_uid uuid;
    v_email text;
    v_pos record;
    v_delete uuid[] := '{}';
    v_late uuid[] := '{}';
    v_former uuid[];
    v_hh uuid;
    v_member uuid;
    v_notice timestamptz;
    v_refs text[];
    v_id_refs text[];
    v_scope uuid[];
    v_lock_hhs uuid[];
    v_ledger_hhs uuid[];
    v_keep_pools uuid[];
    v_reowned uuid[];
    v_name text;
    v_name_re text;
    v_email_re text;
    v_ledger_before text;
    v_ledger_after text;
    v_keep_wife uuid[];
    v_wife_ids uuid[];
    v_wife_balances numeric[];
    v_moved record;
BEGIN
    PERFORM public.account_deletion_require_service();

    -- The user's lock, then the request row: the order account_deletion_cancel takes them in.
    SELECT * INTO v_req FROM public.account_deletion_requests WHERE id = p_request_id;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'Account deletion request not found' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;
    IF v_req.user_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('account_deletion:' || v_req.user_id::text, 0));
    END IF;
    SELECT * INTO v_req FROM public.account_deletion_requests WHERE id = p_request_id FOR UPDATE;
    IF v_req.id IS NULL THEN
        RAISE EXCEPTION 'Account deletion request not found' USING ERRCODE = 'P0002', HINT = 'request_not_found';
    END IF;

    IF v_req.stage <> 'none' OR v_req.status = 'completed' THEN
        RETURN jsonb_build_object('prepared', true, 'deferred', false, 'already_prepared', true, 'stage', v_req.stage);
    END IF;

    -- Only a claimed, due job. A cancelled or unclaimed request never reaches the data.
    IF v_req.status <> 'processing' OR v_req.scheduled_for > now() THEN
        RAISE EXCEPTION 'This request is not due for purging' USING ERRCODE = '22023', HINT = 'purge_not_allowed';
    END IF;

    v_uid := v_req.user_id;

    -- Deleted out of band during grace: the FKs did the work.
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid) THEN
        UPDATE public.account_deletion_requests
        SET stage = 'db_prepared', last_error_code = NULL
        WHERE id = p_request_id;
        RETURN jsonb_build_object('prepared', true, 'deferred', false, 'user_missing', true, 'deleted_households', 0);
    END IF;

    -- Every household whose ledger the purge can reach: theirs, those of the pools they own
    -- (re-owned below), and those of the wife_personal rows deleted below. Pools, then
    -- households, then budgets, each by id: an expense locks its account (a BEFORE trigger),
    -- then its household (the foreign key), then its budget, so this order cannot deadlock with it.
    SELECT COALESCE(array_agg(DISTINCT s.household_id), '{}') INTO v_lock_hhs
    FROM (
        SELECT m.household_id FROM public.household_memberships m WHERE m.user_id = v_uid
        UNION ALL
        SELECT a.household_id FROM public.accounts a WHERE a.owner_user_id = v_uid AND a.is_shared_pool
        UNION ALL
        SELECT t.household_id FROM public.transactions t WHERE t.nafaqah_spouse_id = v_uid AND t.nafaqah_class = 'wife_personal'
        UNION ALL
        -- The wife accounts they own or are assigned (section 12).
        SELECT a.household_id FROM public.accounts a
        WHERE a.account_type = 'wife' AND (a.owner_user_id = v_uid OR a.assigned_wife_id = v_uid)
    ) s;

    PERFORM 1 FROM public.accounts a WHERE a.is_shared_pool AND a.household_id = ANY (v_lock_hhs) ORDER BY a.id FOR UPDATE;

    PERFORM 1
    FROM public.households h
    WHERE h.id = ANY (v_lock_hhs)
    ORDER BY h.id
    FOR UPDATE;

    -- Then their wife accounts, in id order: a repayment, a reversal or her spending takes the
    -- household before a personal account too, so nothing holds one of these while waiting for it.
    PERFORM 1 FROM public.accounts a
    WHERE a.account_type = 'wife' AND (a.owner_user_id = v_uid OR a.assigned_wife_id = v_uid)
      AND a.household_id = ANY (v_lock_hhs)
    ORDER BY a.id
    FOR UPDATE;

    FOR v_pos IN
        SELECT p.household_id, p.member_position,
               (h.deletion_requested_by = v_uid AND h.deletion_scheduled_for IS NOT NULL) AS marked
        FROM public.account_deletion_household_positions(v_uid) p
        JOIN public.households h ON h.id = p.household_id
    LOOP
        IF v_pos.member_position = 'sole_member' OR COALESCE(v_pos.marked, false) THEN
            v_delete := v_delete || v_pos.household_id;
        ELSIF v_pos.member_position = 'primary_admin' THEN
            v_late := v_late || v_pos.household_id;
        END IF;
    END LOOP;

    -- Late-surfaced: never delete a household its members were not warned about.
    IF array_length(v_late, 1) IS NOT NULL THEN
        v_notice := now() + interval '7 days';
        UPDATE public.households h
        SET deletion_requested_at = COALESCE(h.deletion_requested_at, now()),
            deletion_scheduled_for = v_notice,
            deletion_requested_by = v_uid
        WHERE h.id = ANY (v_late)
           OR h.deletion_requested_by = v_uid;
        UPDATE public.account_deletion_requests
        SET status = 'scheduled',
            scheduled_for = v_notice,
            lease_expires_at = NULL,
            attempts = 0,
            last_error_code = NULL,
            notices_sent = '{}'
        WHERE id = p_request_id;
        RETURN jsonb_build_object('prepared', false, 'deferred', true,
                                  'scheduled_for', v_notice, 'households', to_jsonb(v_late));
    END IF;

    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;
    SELECT NULLIF(btrim(display_name), '') INTO v_name FROM public.users WHERE id = v_uid;
    -- The whole address or name, any case, never part of a longer one.
    IF v_email IS NOT NULL AND v_email <> '' THEN
        v_email_re := '(?<![[:alnum:]._%+-])' || regexp_replace(v_email, '([^[:alnum:][:space:]])', '\\\1', 'g')
                      || '(?![[:alnum:]_-]|\.[[:alnum:]])';
    END IF;
    IF v_name IS NOT NULL THEN
        v_name_re := '(?<![[:alnum:]_])' || regexp_replace(v_name, '([^[:alnum:][:space:]])', '\\\1', 'g') || '(?![[:alnum:]_])';
    END IF;

    -- What must not move: the surviving households the purge can reach, and nothing else, so
    -- another household's expense in the meantime is not mistaken for one. Locked above (pools
    -- and households); a pool made since is locked now, then the budgets, before the snapshot.
    SELECT COALESCE(array_agg(x), '{}') INTO v_ledger_hhs
    FROM unnest(v_lock_hhs) AS x
    WHERE NOT (x = ANY (v_delete));
    PERFORM 1 FROM public.accounts a WHERE a.is_shared_pool AND a.household_id = ANY (v_ledger_hhs) ORDER BY a.id FOR UPDATE;
    PERFORM 1 FROM public.budgets b WHERE b.household_id = ANY (v_ledger_hhs) ORDER BY b.id FOR UPDATE;

    -- A pool in a household with no other admin has nobody to go to.
    SELECT COALESCE(array_agg(a.id), '{}') INTO v_keep_pools
    FROM public.accounts a
    WHERE a.is_shared_pool
      AND a.household_id = ANY (v_ledger_hhs)
      AND (a.owner_user_id <> v_uid
           OR EXISTS (SELECT 1 FROM public.household_memberships o
                      WHERE o.household_id = a.household_id AND o.user_id <> v_uid AND o.role = 'admin'));
    -- The wife accounts that survive the purge (section 12): hers, which stay their owner's, and his
    -- that pass to someone. Their balances are in the invariant too.
    SELECT COALESCE(array_agg(a.id ORDER BY a.id), '{}') INTO v_keep_wife
    FROM public.accounts a
    WHERE a.account_type = 'wife'
      AND a.household_id = ANY (v_ledger_hhs)
      AND ((a.assigned_wife_id = v_uid AND a.owner_user_id <> v_uid)
           OR (a.owner_user_id = v_uid AND public.account_deletion_wife_account_recipient(a.id, v_uid) IS NOT NULL));
    SELECT COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.id = ANY (v_keep_pools)), '')
        || '|'
        || COALESCE((SELECT string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id)
                     FROM public.budgets b WHERE b.household_id = ANY (v_ledger_hhs)), '')
        || '|'
        || COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.id = ANY (v_keep_wife)), '')
    INTO v_ledger_before;

    -- ── Storage queue, while the paths still exist ──────────────────────────
    INSERT INTO public.account_deletion_storage_queue (request_id, bucket, path, is_prefix)
    SELECT p_request_id, 'receipts', d || '/', true
    FROM unnest(v_delete) AS d
    ON CONFLICT (request_id, bucket, path) DO NOTHING;

    -- Their receipts in households that survive. Only inside the row's own household
    -- folder: receipt_url is client-influenced and must never reach another household.
    INSERT INTO public.account_deletion_storage_queue (request_id, bucket, path, is_prefix)
    SELECT DISTINCT p_request_id, 'receipts', q.path, false
    FROM (
        SELECT t.household_id,
               split_part(regexp_replace(t.receipt_url, '^.*/receipts/', ''), '?', 1) AS path
        FROM public.transactions t
        WHERE t.user_id = v_uid
          AND t.receipt_url IS NOT NULL
          AND NOT (t.household_id = ANY (v_delete))
    ) q
    WHERE q.path LIKE q.household_id::text || '/%'
      AND q.path NOT LIKE '%..%'
    ON CONFLICT (request_id, bucket, path) DO NOTHING;

    -- ── Households being deleted, in the fixed order ────────────────────────
    SELECT COALESCE(array_agg(DISTINCT m.user_id), '{}') INTO v_former
    FROM public.household_memberships m
    WHERE m.household_id = ANY (v_delete) AND m.user_id <> v_uid;

    FOREACH v_hh IN ARRAY v_delete LOOP
        DELETE FROM public.income_records WHERE household_id = v_hh;
        DELETE FROM public.account_transfers WHERE household_id = v_hh;
        DELETE FROM public.household_memberships WHERE household_id = v_hh AND role <> 'admin';
        DELETE FROM public.household_memberships WHERE household_id = v_hh;
        DELETE FROM public.households WHERE id = v_hh;
    END LOOP;

    FOREACH v_member IN ARRAY v_former LOOP
        PERFORM public.account_deletion_repoint_active_household(v_member);
    END LOOP;

    -- What the husband still owes her stays with each surviving household (one anonymised record
    -- each), taken before anything below touches her rows and before the leave removes her ledger.
    -- The households are locked above, so the amount cannot change under it.
    PERFORM public.account_deletion_snapshot_former_member_debts(v_uid);

    -- Her pending requests, and those in households whose husband (provider) this is, close with
    -- nothing moved (20261105001300). The households are locked above; an approval in flight either
    -- committed first (the request is no longer pending) or waits and then finds it closed. Her own
    -- requests then go with her ledger at the leave below.
    INSERT INTO public.spouse_reimbursement_request_outcomes (request_id, outcome, decided_by)
    SELECT q.id, 'closed', NULL
    FROM public.spouse_reimbursement_requests q
    JOIN public.households h ON h.id = q.household_id
    WHERE (q.wife_user_id = v_uid OR h.nafaqah_provider_user_id = v_uid)
      AND NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = q.id)
    ORDER BY q.id
    ON CONFLICT (request_id) DO NOTHING;

    -- ── Households that survive ─────────────────────────────────────────────
    -- D5: before the membership trigger can declassify them into the budgets. Deleting a purchase
    -- puts its amount back into its account (the balance trigger); on a wife account that stays
    -- (section 12) the money she spent is still spent, so its balance is put back as it was.
    SELECT COALESCE(array_agg(a.id ORDER BY a.id), '{}'), COALESCE(array_agg(a.balance ORDER BY a.id), '{}')
    INTO v_wife_ids, v_wife_balances
    FROM public.accounts a WHERE a.id = ANY (v_keep_wife);
    DELETE FROM public.transactions
    WHERE nafaqah_spouse_id = v_uid AND nafaqah_class = 'wife_personal';
    UPDATE public.accounts a
    SET balance = s.balance
    FROM unnest(v_wife_ids, v_wife_balances) AS s(id, balance)
    WHERE a.id = s.id AND a.balance IS DISTINCT FROM s.balance;

    -- Every pool they own, including in a household they already left.
    WITH reowned AS (
        UPDATE public.accounts a
        SET owner_user_id = n.user_id,
            updated_at = now()
        FROM (
            SELECT DISTINCT ON (o.household_id) o.household_id, o.user_id
            FROM public.household_memberships o
            WHERE o.user_id <> v_uid AND o.role = 'admin'
            ORDER BY o.household_id, public.account_deletion_user_pending(o.user_id) ASC, o.created_at ASC, o.user_id ASC
        ) n
        WHERE a.household_id = n.household_id
          AND a.owner_user_id = v_uid
          AND a.is_shared_pool
        RETURNING a.id
    )
    SELECT COALESCE(array_agg(id), '{}') INTO v_reowned FROM reowned;

    -- The wife accounts they own pass on with their balance and history (section 12): to the
    -- household's primary admin, or to the wife it is assigned to when that admin is another wife.
    -- Before their accounts' transfers and the accounts themselves go below, so none of it goes.
    -- Each moved account's past transfers are its new owner's too, as his own account's are.
    FOR v_moved IN
        SELECT a.id, public.account_deletion_wife_account_recipient(a.id, v_uid) AS recipient
        FROM public.accounts a
        WHERE a.id = ANY (v_keep_wife) AND a.owner_user_id = v_uid
        ORDER BY a.id
    LOOP
        UPDATE public.accounts SET owner_user_id = v_moved.recipient, updated_at = now() WHERE id = v_moved.id;
        UPDATE public.account_transfers t
        SET personal_owner_ids = ARRAY(SELECT DISTINCT x FROM unnest(t.personal_owner_ids || v_moved.recipient) AS x ORDER BY x)
        WHERE (t.from_account_id = v_moved.id OR t.to_account_id = v_moved.id)
          AND NOT (v_moved.recipient = ANY (t.personal_owner_ids));
        v_reowned := v_reowned || v_moved.id;
    END LOOP;

    -- Its name now belongs to someone else's pool: their name goes from it.
    IF v_name_re IS NOT NULL THEN
        UPDATE public.accounts a
        SET name = regexp_replace(a.name, v_name_re, 'deleted_member', 'gi')
        WHERE a.id = ANY (v_reowned)
          AND a.name ~* v_name_re;
    END IF;

    -- What other rows may call them: their id, and any dependent claimed by them.
    SELECT array_agg(DISTINCT r) INTO v_refs
    FROM (
        SELECT v_uid::text AS r
        UNION ALL
        SELECT d.id::text FROM public.household_dependents d WHERE d.linked_user_id = v_uid
        UNION ALL
        SELECT lower(trim(d.name)) FROM public.household_dependents d WHERE d.linked_user_id = v_uid
    ) q;
    -- Ids mean them in any household. A dependent's name only means them in its own.
    SELECT array_agg(r) INTO v_id_refs
    FROM unnest(v_refs) AS r
    WHERE r ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    SELECT COALESCE(array_agg(DISTINCT s.household_id), '{}') INTO v_scope
    FROM (
        SELECT m.household_id FROM public.household_memberships m WHERE m.user_id = v_uid
        UNION ALL
        SELECT t.household_id FROM public.transactions t WHERE t.user_id = v_uid
        UNION ALL
        SELECT i.household_id FROM public.income_records i WHERE i.user_id = v_uid
        UNION ALL
        SELECT a.household_id FROM public.accounts a WHERE a.owner_user_id = v_uid
    ) s;

    -- Their own rows. Their name and address go from the merchant and the item names too.
    UPDATE public.transactions t
    SET notes = public.account_deletion_scrub_own_note(t.notes, v_refs),
        receipt_url = NULL,
        beneficiary_id = CASE WHEN lower(trim(t.beneficiary_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.beneficiary_id END,
        settlement_target_id = CASE WHEN lower(trim(t.settlement_target_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.settlement_target_id END,
        merchant = public.account_deletion_scrub_text(t.merchant, ARRAY[v_name_re, v_email_re]),
        items = public.account_deletion_scrub_item_names(public.account_deletion_scrub_items(t.items, v_refs), ARRAY[v_name_re, v_email_re]),
        line_items = public.account_deletion_scrub_item_names(public.account_deletion_scrub_items(t.line_items, v_refs), ARRAY[v_name_re, v_email_re])
    WHERE t.user_id = v_uid;

    -- Other members' rows anywhere that name them by id, including in a household they left
    -- where only others' rows mention them (v_scope below would not reach it).
    UPDATE public.transactions t
    SET notes = public.account_deletion_scrub_other_note(t.notes, v_id_refs),
        beneficiary_id = CASE WHEN lower(trim(t.beneficiary_id)) = ANY (v_id_refs) THEN 'deleted_member' ELSE t.beneficiary_id END,
        settlement_target_id = CASE WHEN lower(trim(t.settlement_target_id)) = ANY (v_id_refs) THEN 'deleted_member' ELSE t.settlement_target_id END,
        items = public.account_deletion_scrub_items(t.items, v_id_refs),
        line_items = public.account_deletion_scrub_items(t.line_items, v_id_refs)
    WHERE t.user_id IS DISTINCT FROM v_uid
      AND (lower(trim(t.beneficiary_id)) = ANY (v_id_refs)
           OR lower(trim(t.settlement_target_id)) = ANY (v_id_refs)
           OR public.account_deletion_scrub_other_note(t.notes, v_id_refs) IS DISTINCT FROM t.notes
           OR public.account_deletion_scrub_items(t.items, v_id_refs) IS DISTINCT FROM t.items
           OR public.account_deletion_scrub_items(t.line_items, v_id_refs) IS DISTINCT FROM t.line_items);

    -- Other members' rows in those households that name them, by id or by a claimed dependent's name.
    UPDATE public.transactions t
    SET notes = public.account_deletion_scrub_other_note(t.notes, v_refs),
        beneficiary_id = CASE WHEN lower(trim(t.beneficiary_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.beneficiary_id END,
        settlement_target_id = CASE WHEN lower(trim(t.settlement_target_id)) = ANY (v_refs) THEN 'deleted_member' ELSE t.settlement_target_id END,
        items = public.account_deletion_scrub_items(t.items, v_refs),
        line_items = public.account_deletion_scrub_items(t.line_items, v_refs)
    WHERE t.household_id = ANY (v_scope)
      AND t.user_id IS DISTINCT FROM v_uid
      AND (lower(trim(t.beneficiary_id)) = ANY (v_refs)
           OR lower(trim(t.settlement_target_id)) = ANY (v_refs)
           OR public.account_deletion_scrub_other_note(t.notes, v_refs) IS DISTINCT FROM t.notes
           OR public.account_deletion_scrub_items(t.items, v_refs) IS DISTINCT FROM t.items
           OR public.account_deletion_scrub_items(t.line_items, v_refs) IS DISTINCT FROM t.line_items);

    UPDATE public.installment_plans p
    SET notes = NULL
    FROM public.transactions t
    WHERE p.original_transaction_id = t.id AND t.user_id = v_uid AND p.notes IS NOT NULL;

    -- Income they recorded stays where it landed; its free text goes. title is free text too.
    UPDATE public.income_records
    SET notes = NULL,
        title = source_type
    WHERE user_id = v_uid;

    -- Whatever they still own after the re-own above goes, with its income.
    DELETE FROM public.income_records i
    USING public.accounts a
    WHERE i.account_id = a.id AND a.owner_user_id = v_uid;

    UPDATE public.account_transfers t
    SET notes = NULL
    WHERE t.user_id = v_uid
       OR t.from_account_id IN (SELECT a.id FROM public.accounts a WHERE a.owner_user_id = v_uid)
       OR t.to_account_id IN (SELECT a.id FROM public.accounts a WHERE a.owner_user_id = v_uid);

    DELETE FROM public.account_transfers t
    USING public.accounts f, public.accounts d
    WHERE t.from_account_id = f.id AND t.to_account_id = d.id
      AND f.owner_user_id = v_uid AND d.owner_user_id = v_uid;

    DELETE FROM public.accounts WHERE owner_user_id = v_uid;

    UPDATE public.spouse_reimbursements
    SET notes = NULL
    WHERE (paid_by_user_id = v_uid OR recorded_by = v_uid) AND notes IS NOT NULL;

    -- A reason they gave for declining a request is their free text too (20261105001300).
    UPDATE public.spouse_reimbursement_request_outcomes
    SET reason = NULL
    WHERE decided_by = v_uid AND reason IS NOT NULL;

    -- The real name stays on a linked dependent row, and its targeted invites cascade.
    DELETE FROM public.household_dependents WHERE linked_user_id = v_uid;

    -- Her personal plans in the households she leaves as a wife stay hidden as a former wife's
    -- (section 10e, owner decision 2026-11-06): her id goes from them now, before the leave below
    -- would make her no wife of the household, and the mark keeps them read only by her husband and
    -- the admins who are not wives. Her personal purchases were deleted above, so none is linked.
    UPDATE public.installment_plans p
    SET personal_owner_id = NULL,
        former_member_personal = true
    WHERE p.personal_owner_id = v_uid
      AND public.nafaqah_is_spouse_member(p.household_id, v_uid);

    -- The wife accounts assigned to her stay their owner's, with their balance and history, as a
    -- former wife's (section 12): archived, naming nobody (her id and her name go), read only by
    -- their owner and her ledger's managers, never by a co-wife or a member. The leave below would
    -- archive them too; her name is taken out here, where it is known.
    UPDATE public.accounts a
    SET is_archived = true,
        assigned_wife_id = NULL,
        name = CASE WHEN v_name_re IS NOT NULL THEN regexp_replace(a.name, v_name_re, 'deleted_member', 'gi') ELSE a.name END,
        updated_at = now()
    WHERE a.id = ANY (v_keep_wife) AND a.assigned_wife_id = v_uid;

    -- The leave itself. Fires the Nafaqah, provider, primary admin and mark triggers.
    DELETE FROM public.household_memberships WHERE user_id = v_uid;

    DELETE FROM public.invite_attempt_log WHERE user_id = v_uid;

    DELETE FROM public.inquiries i
    WHERE i.name = 'User ' || v_uid::text
       OR i.email = v_uid::text || '@auth.internal'
       OR (v_email IS NOT NULL AND lower(i.email) = v_email);

    -- Their address, wherever it still is in public, other members' text included. Their
    -- display name stays in others' text: a common name could be anyone's.
    PERFORM public.account_deletion_replace_everywhere(v_email, v_email_re);

    -- The shell the Auth Admin delete will cascade from.
    UPDATE public.users
    SET display_name = 'deleted_member',
        household_id = NULL,
        role = 'member',
        financial_role = NULL
    WHERE id = v_uid;

    -- ── The invariant ───────────────────────────────────────────────────────
    SELECT COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.id = ANY (v_keep_pools)), '')
        || '|'
        || COALESCE((SELECT string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id)
                     FROM public.budgets b WHERE b.household_id = ANY (v_ledger_hhs)), '')
        || '|'
        || COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.id = ANY (v_keep_wife)), '')
    INTO v_ledger_after;
    IF v_ledger_after IS DISTINCT FROM v_ledger_before THEN
        RAISE EXCEPTION 'A surviving pool balance or budget would have moved; nothing was purged'
            USING ERRCODE = '23514', HINT = 'purge_ledger_invariant';
    END IF;

    UPDATE public.account_deletion_requests
    SET stage = 'db_prepared', last_error_code = NULL
    WHERE id = p_request_id;

    RETURN jsonb_build_object('prepared', true, 'deferred', false,
                              'deleted_households', COALESCE(array_length(v_delete, 1), 0));
END;
$$;

-- 10b. An account a repayment used is archived, not deleted (review R3-05) ---------------------
-- A client deleting the account a repayment left (or a reversal returned to) would leave the
-- repayment impossible to reverse (reversal_account_unavailable) and take its balance out of the
-- household's books. A client (a JWT subject) is refused, naming archiving instead; the purge and
-- the service role run without one and still delete as designed. Other accounts are unaffected.
CREATE OR REPLACE FUNCTION public.nafaqah_refuse_account_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.account_transfers t
        WHERE (t.from_account_id = OLD.id OR t.to_account_id = OLD.id)
          AND t.purpose IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'A repayment was paid from or returned to this account: archive it instead of deleting it'
            USING ERRCODE = '23503', HINT = 'account_has_repayments';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_accounts_keep_repayment_history ON public.accounts;
CREATE TRIGGER trg_accounts_keep_repayment_history
BEFORE DELETE ON public.accounts
FOR EACH ROW EXECUTE FUNCTION public.nafaqah_refuse_account_delete();

-- 10c. Her allowance: who sees it and who sets it (owner decision 2026-11-06) ------------------
-- Her allowance (member_allowances; allocated, spent and remaining for a cycle) is read by the wife
-- herself (her own only), by her husband (001200's nafaqah_ledger_husband_id: the provider while
-- he is a current member who is not a wife) and by an admin of the household who is not a wife.
-- A co-wife (even an admin) and an ordinary member read nothing of it: no row, no figure. It is set
-- as before by the husband (an admin or not) or an admin, but never by a wife: a wife who is an
-- admin no longer sets a co-wife's. Replaces 20261020300000's read policy (any member of the
-- household), get_member_allowance_status (any member) and set_member_allowance (any admin).

-- Who sees every wife's allowance in the household (beside each wife, who sees her own).
CREATE OR REPLACE FUNCTION public.nafaqah_may_see_allowances(p_household_id uuid, p_actor uuid)
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
          AND m.user_id = p_actor
          AND m.financial_role IS DISTINCT FROM 'spouse'
          AND (m.role = 'admin' OR p_actor = public.nafaqah_ledger_husband_id(p_household_id))
    );
$$;

-- The half of the read rule that depends on the caller only (their active household), evaluated
-- once per statement in the policy below.
CREATE OR REPLACE FUNCTION public.nafaqah_caller_sees_allowances()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(public.nafaqah_may_see_allowances(public.get_auth_user_household_id(), auth.uid()), false);
$$;

DROP POLICY IF EXISTS member_allowances_select_household ON public.member_allowances;
CREATE POLICY member_allowances_select_household ON public.member_allowances
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (member_user_id = (SELECT auth.uid()) OR (SELECT public.nafaqah_caller_sees_allowances())));

-- 20261020300000's body, with the read rule before anything about her is looked at.
CREATE OR REPLACE FUNCTION public.get_member_allowance_status(
    p_household_id uuid,
    p_member_user_id uuid,
    p_cycle_key text DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_cycle text;
    v_allocated numeric(14, 2);
    v_spent numeric(14, 2);
    v_count int;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    -- She reads her own; her husband and an admin who is not a wife read every wife's. Nobody
    -- else gets a figure (owner decision 2026-11-06).
    IF v_actor IS DISTINCT FROM p_member_user_id AND NOT public.nafaqah_may_see_allowances(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: only she, her husband, or an admin who is not a wife, reads this allowance'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_member_user_id) THEN
        RAISE EXCEPTION 'Allowances apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    v_cycle := COALESCE(NULLIF(trim(p_cycle_key), ''), public.nafaqah_current_cycle_key(p_household_id));
    IF v_cycle !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
        RAISE EXCEPTION 'Invalid cycle_key %', v_cycle USING ERRCODE = '22023';
    END IF;

    SELECT a.amount INTO v_allocated
    FROM public.member_allowances a
    WHERE a.household_id = p_household_id AND a.member_user_id = p_member_user_id AND a.cycle_key = v_cycle;

    SELECT COALESCE(sum(t.amount), 0), count(*) INTO v_spent, v_count
    FROM public.transactions t
    WHERE t.household_id = p_household_id
      AND t.nafaqah_spouse_id = p_member_user_id
      AND t.nafaqah_class = 'wife_personal'
      AND t.cycle_key = v_cycle;

    RETURN jsonb_build_object(
        'household_id', p_household_id,
        'member_user_id', p_member_user_id,
        'cycle_key', v_cycle,
        'is_set', v_allocated IS NOT NULL,
        'allocated', COALESCE(v_allocated, 0),
        'spent', v_spent,
        'remaining', COALESCE(v_allocated, 0) - v_spent,
        'transaction_count', v_count
    );
END;
$$;

-- 20261020300000's body, refusing every wife as the one who sets it.
CREATE OR REPLACE FUNCTION public.set_member_allowance(
    p_household_id uuid,
    p_member_user_id uuid,
    p_amount numeric,
    p_cycle_key text DEFAULT NULL,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_cycle text;
    v_is_admin boolean;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_member_user_id) THEN
        RAISE EXCEPTION 'Allowances apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;
    IF v_actor = p_member_user_id THEN
        RAISE EXCEPTION 'Forbidden: the allowance is set by the husband or a household admin' USING ERRCODE = '42501';
    END IF;
    -- Never a wife: not a co-wife, even an admin (owner decision 2026-11-06).
    IF public.nafaqah_is_spouse_member(p_household_id, v_actor) THEN
        RAISE EXCEPTION 'Forbidden: the allowance is set by the husband or a household admin who is not a wife'
            USING ERRCODE = '42501', HINT = 'forbidden';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.household_memberships m
        WHERE m.household_id = p_household_id AND m.user_id = v_actor AND m.role = 'admin'
    ) INTO v_is_admin;
    IF NOT v_is_admin AND v_actor IS DISTINCT FROM public.nafaqah_husband_id(p_household_id) THEN
        RAISE EXCEPTION 'Forbidden: the allowance is set by the husband or a household admin' USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount < 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'Allowance must be a non-negative SAR amount with at most 2 decimals' USING ERRCODE = '22023';
    END IF;

    v_cycle := COALESCE(NULLIF(trim(p_cycle_key), ''), public.nafaqah_current_cycle_key(p_household_id));
    IF v_cycle !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
        RAISE EXCEPTION 'Invalid cycle_key %', v_cycle USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.member_allowances (household_id, member_user_id, cycle_key, amount, set_by)
    VALUES (p_household_id, p_member_user_id, v_cycle, p_amount, v_actor)
    ON CONFLICT (household_id, member_user_id, cycle_key)
    DO UPDATE SET amount = EXCLUDED.amount, set_by = EXCLUDED.set_by, updated_at = now();

    RETURN public.get_member_allowance_status(p_household_id, p_member_user_id, v_cycle, v_actor);
END;
$$;

-- 10d. Her personal purchases: who reads them (owner decision 2026-11-06) ----------------------
-- A wife's personal purchases (transactions with nafaqah_class 'wife_personal') are read by the
-- same people as her allowance (10c): she herself (her own), her husband, and an admin of the
-- household who is not a wife. A co-wife (even an admin) and an ordinary member read none of those
-- rows, and so nothing derived from them through RLS: no amount, merchant, note, receipt photo,
-- nafaqah_spouse_id link or sum. Every other transaction keeps the household-wide read of
-- 20261020100000 (her wife_reimbursable advances among them). Who creates, edits or voids is
-- unchanged (the write triggers), and a caller who cannot read a row cannot update or delete it
-- (review R3B-01, owner decision 2026-11-06): the UPDATE and DELETE policies carry the same test,
-- so a statement that reads no column (UPDATE ... WHERE true, a DELETE with no WHERE, which
-- PostgreSQL does not filter by the read policy) reaches no row the caller does not read, and an
-- update never leaves a row the caller could not read (WITH CHECK).
-- Replaces 20261020100000's transactions_select_household and receipts_select_household, and
-- 20261020400000's transactions_update_household and transactions_delete_household (and
-- 20261020100000's receipts_delete_household).
--
-- The policy is on the hottest read path. The class is tested first, on the row itself; the
-- caller's half (nafaqah_caller_sees_allowances: one membership row and the provider) runs once per
-- statement as an InitPlan and only when a personal row is met; the household filter keeps using
-- the household indexes.
DROP POLICY IF EXISTS transactions_select_household ON public.transactions;
CREATE POLICY transactions_select_household ON public.transactions
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (nafaqah_class IS DISTINCT FROM 'wife_personal'
                OR nafaqah_spouse_id = (SELECT auth.uid())
                OR (SELECT public.nafaqah_caller_sees_allowances())));

-- The wife accounts (section 12) of the caller's active household that the caller may not see:
-- nobody but her, its owner and her ledger's managers updates or deletes a transaction recorded on
-- one (review R3C-01, owner decision 2026-11-07). Her advances are read household-wide, but a
-- co-wife (even an admin), an ordinary member, and an admin who is not a wife while the husband is
-- there reach none of the rows on her wife account: an edit or a delete of one changes 0 rows, the
-- answer for a row they do not read, and nothing moves her account's balance. Runs once per
-- statement (an InitPlan of the policies below), as the caller; PL/pgSQL so that it may name
-- section 12's nafaqah_may_see_wife_account, made further down.
CREATE OR REPLACE FUNCTION public.nafaqah_caller_hidden_wife_accounts()
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_hh uuid := public.get_auth_user_household_id();
BEGIN
    RETURN COALESCE((SELECT array_agg(a.id ORDER BY a.id)
                     FROM public.accounts a
                     WHERE a.household_id = v_hh AND a.account_type = 'wife'
                       AND NOT public.nafaqah_may_see_wife_account(a.household_id, v_uid, a.owner_user_id, a.assigned_wife_id)),
                    '{}');
END;
$$;

-- 20261020400000's rules (the creator or an admin; a personal account only on its owner's rows),
-- with the read test above on the row it picks and on the row it leaves, and no row on a wife
-- account the caller does not see, before or after (review R3C-01).
DROP POLICY IF EXISTS transactions_update_household ON public.transactions;
CREATE POLICY transactions_update_household ON public.transactions
    FOR UPDATE TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (nafaqah_class IS DISTINCT FROM 'wife_personal'
                OR nafaqah_spouse_id = (SELECT auth.uid())
                OR (SELECT public.nafaqah_caller_sees_allowances()))
           AND (account_id IS NULL OR NOT (ARRAY[account_id] && (SELECT public.nafaqah_caller_hidden_wife_accounts()))))
    WITH CHECK (
        household_id = (SELECT public.get_auth_user_household_id())
        AND (user_id = (SELECT auth.uid()) OR (SELECT public.get_auth_user_role()) = 'admin')
        AND (
            account_id IS NULL
            OR public.transaction_account_matches(account_id, household_id, user_id)
        )
        AND (nafaqah_class IS DISTINCT FROM 'wife_personal'
             OR nafaqah_spouse_id = (SELECT auth.uid())
             OR (SELECT public.nafaqah_caller_sees_allowances()))
        AND (account_id IS NULL OR NOT (ARRAY[account_id] && (SELECT public.nafaqah_caller_hidden_wife_accounts())))
    );

DROP POLICY IF EXISTS transactions_delete_household ON public.transactions;
CREATE POLICY transactions_delete_household ON public.transactions
    FOR DELETE TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (nafaqah_class IS DISTINCT FROM 'wife_personal'
                OR nafaqah_spouse_id = (SELECT auth.uid())
                OR (SELECT public.nafaqah_caller_sees_allowances()))
           AND (account_id IS NULL OR NOT (ARRAY[account_id] && (SELECT public.nafaqah_caller_hidden_wife_accounts()))));

-- Her receipt photo follows her purchase. Receipts are stored under the household's folder
-- (<household id>/<file>); transactions.receipt_url holds that path, or a legacy URL ending in
-- /receipts/<path>?..., read the same way as the purge reads it. True when the caller does not
-- read the object named: the photo of a personal purchase of the household that the caller does
-- not read. It is no oracle for a guessed path (review R3B-04): membership of the folder's
-- household is checked first, and a path that names no photo is answered as one the caller does
-- not read, so "nothing there" and "there, not yours" are the same answer (true). Only those who
-- read every personal purchase of the household (10c) get false for every path. Each step is one
-- index probe (the membership, the object by bucket and name, the purchase by its path below), so
-- a listing costs the same per object whatever the household holds. The read and the delete
-- policies of the receipts bucket run it per object, as the caller (live postgres owns it and
-- bypasses RLS, so its look at storage.objects is not filtered).
CREATE OR REPLACE FUNCTION public.nafaqah_receipt_hidden(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_folder text := split_part(COALESCE(p_name, ''), '/', 1);
    v_household uuid;
BEGIN
    -- The server's own read (no JWT subject): RLS does not apply to it.
    IF v_uid IS NULL THEN
        RETURN false;
    END IF;
    IF v_folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN true;
    END IF;
    v_household := v_folder::uuid;
    IF NOT EXISTS (SELECT 1 FROM public.household_memberships m
                   WHERE m.household_id = v_household AND m.user_id = v_uid) THEN
        RETURN true;
    END IF;
    IF public.nafaqah_may_see_allowances(v_household, v_uid) THEN
        RETURN false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'receipts' AND o.name = p_name) THEN
        RETURN true;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.transactions t
        WHERE t.household_id = v_household
          AND t.nafaqah_class = 'wife_personal'
          AND t.receipt_url IS NOT NULL
          AND split_part(regexp_replace(t.receipt_url, '^.*/receipts/', ''), '?', 1) = p_name
          AND t.nafaqah_spouse_id IS DISTINCT FROM v_uid
    );
END;
$$;

-- The lookup above finds the household's personal purchases by the path of their photo. A first
-- version of this file indexed the household only; it is rebuilt on the path once.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_transactions_wife_personal_receipt'
               AND indexdef NOT LIKE '%regexp_replace%') THEN
        DROP INDEX public.idx_transactions_wife_personal_receipt;
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_transactions_wife_personal_receipt
    ON public.transactions (household_id, (split_part(regexp_replace(receipt_url, '^.*/receipts/', ''), '?', 1)))
    WHERE nafaqah_class = 'wife_personal' AND receipt_url IS NOT NULL;

DROP POLICY IF EXISTS receipts_select_household ON storage.objects;
CREATE POLICY receipts_select_household ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'receipts'
        AND (SELECT auth.uid()) IS NOT NULL
        AND (storage.foldername(name))[1] IN (
            SELECT m.household_id::text
            FROM public.household_memberships m
            WHERE m.user_id = (SELECT auth.uid())
        )
        AND NOT public.nafaqah_receipt_hidden(name));

-- Her photo is no target of a delete by someone who does not read it (review R3B-01). No client
-- updates a receipt at all: the bucket has no UPDATE policy.
DROP POLICY IF EXISTS receipts_delete_household ON storage.objects;
CREATE POLICY receipts_delete_household ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'receipts'
        AND (SELECT auth.uid()) IS NOT NULL
        AND (storage.foldername(name))[1] IN (
            SELECT m.household_id::text
            FROM public.household_memberships m
            WHERE m.user_id = (SELECT auth.uid())
        )
        AND NOT public.nafaqah_receipt_hidden(name));

-- Her advance (wife_reimbursable) is her ledger's (review R3B-08, owner decision 2026-11-06): its
-- wife or its class is changed by a client only by her ledger's managers (her husband; an admin
-- who is not a wife when he is gone), or by her clearing or keeping her own. Not by a wife-admin,
-- and not by another admin while the husband is there, though both may still edit its other
-- columns as before. The server (no JWT subject: the API checks its own callers) and the system's
-- own cascades (her leaving, an account deletion) are not clients. It fires after
-- trg_validate_transaction_nafaqah_class (trigger names order them), so a member who may not
-- classify at all keeps that answer (nafaqah_class_not_allowed).
CREATE OR REPLACE FUNCTION public.nafaqah_guard_advance_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL OR pg_trigger_depth() > 1 OR OLD.nafaqah_class IS DISTINCT FROM 'wife_reimbursable' THEN
        RETURN NEW;
    END IF;
    IF NEW.nafaqah_class IS NOT DISTINCT FROM OLD.nafaqah_class
       AND NEW.nafaqah_spouse_id IS NOT DISTINCT FROM OLD.nafaqah_spouse_id THEN
        RETURN NEW;
    END IF;
    IF v_uid = OLD.nafaqah_spouse_id
       AND (NEW.nafaqah_spouse_id IS NULL OR NEW.nafaqah_spouse_id = OLD.nafaqah_spouse_id) THEN
        RETURN NEW;
    END IF;
    IF public.nafaqah_may_manage_ledgers(OLD.household_id, v_uid) THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Forbidden: her advance is changed by her husband, or by an admin who is not a wife when he is gone'
        USING ERRCODE = '42501', HINT = 'forbidden';
END;
$$;

DROP TRIGGER IF EXISTS trg_wife_advance_attribution ON public.transactions;
CREATE TRIGGER trg_wife_advance_attribution
    BEFORE UPDATE OF nafaqah_class, nafaqah_spouse_id ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.nafaqah_guard_advance_attribution();

-- 10e. Transfers of her personal account, plans of her personal purchases (owner decision 2026-11-06)
-- Read by the same people as her personal purchases (10d): she herself, her husband, and an admin
-- of the household who is not a wife. A co-wife (even an admin) and an ordinary member read none.
--   * account_transfers: a row with either side a personal (not shared) account owned by a wife
--     of the household: no amount, account, note or row. She reads the rows of her own accounts
--     (one between two wives' accounts is read by both). The owner of the other side reads it too
--     when that side is his own personal account (owner decision 2026-11-06): a member who sends
--     money to her account, or receives from it, keeps that row in his account's history, as its
--     balance shows it. A shared pool is the household's, so its owner_user_id reads nothing more:
--     a pool's history is as before. The other side's balance is unchanged and read as before (a
--     pool's by every member); only the row leaves its history for the others.
--     A repayment (his account or a pool to no account) never involves her account.
--     A repayment's own rows (purpose set: a repayment to the wife, its reversal, a former
--     member's payment, its reversal) are her ledger's (review R3B-02, owner decision 2026-11-06):
--     read by the wife whose ledger it is (a repayment to her or its reversal), her ledger's
--     managers (her husband; the admins who are not wives when he is gone; for a former member's
--     record, its managers), and the owner of the personal account the money left or returned to,
--     his own account's rows only. Nobody else, a pool's lines included: the other members see the
--     pool's balance move, not the line (a co-wife, an ordinary member, an admin who is not a wife
--     while the husband is there). The ledger's managers are evaluated once per statement; her own
--     rows are found through her ledger's link (spouse_reimbursements.transfer_id, read under its
--     own policy), only for a repayment row the caller neither manages nor owns.
--     Replaces 20261020100000's transfers_select_household.
--   * installment_plans: a plan linked to her personal purchase (original_transaction_id) is read
--     by whoever reads that purchase under transactions_select_household (10d): its shop, amounts,
--     dates, schedule (next_due_at) and payments (paid_installments) are columns of the plan. The
--     database keeps whose it is on the plan itself (personal_owner_id, below), so the read test
--     compares the kept owner and looks nothing up per plan (review R3B-03: a plan list costs the
--     same whatever the household's transactions). It stays hers after the link is cleared (owner
--     decision 2026-11-06): her purchase deleted (ON DELETE SET NULL) or the plan unlinked. When her
--     account is deleted, her plans stay hidden as a former wife's (former_member_personal, below):
--     read only by her husband and the admins who are not wives. An unlinked plan with no owner, and
--     one of any other purchase, stay household-wide. A caller who does not read a plan cannot pick
--     it to edit or delete it (the policy covers every command). A plan is created or linked again
--     only to a purchase the caller reads (review R3B-05: the insert and update check reads the
--     purchase under the caller's own RLS, so a purchase she does not read, an id of nothing and
--     another household's purchase are the same refusal), and never by anyone to another household's
--     purchase (the plan's trigger, for the server). Replaces 20261020100000's policy (its name is
--     kept for the rollback).
--
-- Whose accounts a transfer touched is kept on the row (personal_owner_ids: the owners of its
-- personal sides when it was made), so the read policy compares two small arrays per row and looks
-- nothing up. It stays when an account is later deleted (its side becomes NULL), so the row stays
-- hers, and his. An account's owner and pool flag are never changed by a client (20261019100000
-- grants neither column); the server re-owns only pools, which the column never holds. Whether an
-- owner is a wife is read at the time of the read, so a wife who leaves the household is no longer
-- one (as her purchases become household expenses then).
--
-- Whose personal purchase a plan is linked to is kept on the plan the same way (personal_owner_id:
-- the wife whose wife_personal purchase of the household it is, else NULL). The database works it
-- out on every insert and every change of the link; no client writes it (no column privilege, and
-- an insert's value is replaced). It follows the purchase while linked: reclassified to an ordinary
-- expense or to her advance, the plan becomes household-wide (and stays so after the purchase is
-- deleted); made hers, the plan becomes hers. When the link is cleared it keeps the last owner. A
-- deleted person's id leaves it, as it leaves personal_owner_ids.
--
-- A deleted wife's personal plans (owner decision 2026-11-06, item 4 of review R3B) keep a mark
-- instead of her id: former_member_personal, a boolean that names nobody. The purge sets it (and
-- clears her id) on her plans in the households she leaves as a wife, before the leave, so they
-- are never household-wide, not even between the purge and her Auth delete; a delete of her
-- account by any other path does the same through the users trigger. A marked plan is read only
-- by those who read every personal purchase of the household (10c: her husband and the admins who
-- are not wives). It is the former member record's pattern (001200: one anonymised record, no
-- name, id or email of hers) applied to the plan: the mark says "a former wife's", never which.
-- A client never sets it (no column privilege; a new plan is never marked); linked again to a
-- purchase, the plan follows that purchase as any other.

ALTER TABLE public.account_transfers ADD COLUMN IF NOT EXISTS personal_owner_ids uuid[];
COMMENT ON COLUMN public.account_transfers.personal_owner_ids IS
    'Owners of the personal (not shared) accounts on either side when the transfer was made (20261105001300, 10e). Set by trg_account_transfers_personal_owners; the read policy hides a row with a wife''s from a co-wife and an ordinary member.';

-- The owners of the personal accounts among these (none for a pool or no account), and the wife a
-- wife account is assigned to (section 12): her wife account's rows are hers to read too.
CREATE OR REPLACE FUNCTION public.nafaqah_personal_owners_of(p_from uuid, p_to uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(array_agg(DISTINCT o.id ORDER BY o.id), '{}'::uuid[])
    FROM public.accounts a
    CROSS JOIN LATERAL (VALUES (a.owner_user_id), (a.assigned_wife_id)) AS o(id)
    WHERE a.id IN (p_from, p_to)
      AND a.is_shared_pool = false
      AND o.id IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION public.nafaqah_transfer_personal_owners()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.personal_owner_ids := public.nafaqah_personal_owners_of(NEW.from_account_id, NEW.to_account_id);
    NEW.touches_wife_account := EXISTS (SELECT 1 FROM public.accounts a
                                        WHERE a.id IN (NEW.from_account_id, NEW.to_account_id) AND a.account_type = 'wife');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_transfers_personal_owners ON public.account_transfers;
CREATE TRIGGER trg_account_transfers_personal_owners
    BEFORE INSERT ON public.account_transfers
    FOR EACH ROW EXECUTE FUNCTION public.nafaqah_transfer_personal_owners();

-- Existing rows, once (a second run finds none left to fill and changes nothing).
UPDATE public.account_transfers t
SET personal_owner_ids = public.nafaqah_personal_owners_of(t.from_account_id, t.to_account_id)
WHERE t.personal_owner_ids IS NULL;
ALTER TABLE public.account_transfers ALTER COLUMN personal_owner_ids SET DEFAULT '{}'::uuid[];
ALTER TABLE public.account_transfers ALTER COLUMN personal_owner_ids SET NOT NULL;
-- No wife account exists before this file; a second run finds every row of one already marked.
UPDATE public.account_transfers t
SET touches_wife_account = true
WHERE NOT t.touches_wife_account
  AND EXISTS (SELECT 1 FROM public.accounts a WHERE a.id IN (t.from_account_id, t.to_account_id) AND a.account_type = 'wife');

-- The plan's owner: the wife whose personal purchase of the plan's household it is linked to.
-- An ordinary purchase or her advance give none; another household's purchase is never linked.
ALTER TABLE public.installment_plans ADD COLUMN IF NOT EXISTS personal_owner_id uuid;
ALTER TABLE public.installment_plans ADD COLUMN IF NOT EXISTS former_member_personal boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.installment_plans.former_member_personal IS
    'A plan of a personal purchase of a wife whose account was deleted (20261105001300, 10e): she is no longer named on it. Read only by her husband and the admins who are not wives. Set by the purge and trg_users_forget_transfer_owner, never by a client.';
COMMENT ON COLUMN public.installment_plans.personal_owner_id IS
    'The wife whose personal (wife_personal) purchase the plan is or was linked to (20261105001300, 10e). Kept by trg_installment_plans_personal_owner and trg_transactions_plan_owner, never by a client; it stays when the link is cleared, and the read policy hides the plan from a co-wife and an ordinary member.';

CREATE OR REPLACE FUNCTION public.nafaqah_purchase_personal_owner(p_transaction_id uuid, p_household_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT t.nafaqah_spouse_id
    FROM public.transactions t
    WHERE t.id = p_transaction_id
      AND t.household_id = p_household_id
      AND t.nafaqah_class = 'wife_personal';
$$;

-- On insert and on a change of the link: the linked purchase decides (and a linked plan is no
-- former wife's); a cleared link keeps the last owner and mark (her purchase deleted, or the plan
-- unlinked by hand). A client's values are never kept: a new plan is never marked. The server (no
-- JWT subject) never links a plan to a purchase outside the plan's household (review R3B-05); a
-- client is refused that by the policy's check first, with the same answer as for any purchase
-- it does not read, so this trigger raises nothing a client could tell apart.
CREATE OR REPLACE FUNCTION public.nafaqah_plan_personal_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.original_transaction_id IS NOT NULL THEN
        IF auth.uid() IS NULL AND NOT EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = NEW.original_transaction_id AND t.household_id = NEW.household_id
        ) THEN
            RAISE EXCEPTION 'No such purchase in this household' USING ERRCODE = 'P0002', HINT = 'purchase_not_found';
        END IF;
        NEW.personal_owner_id := public.nafaqah_purchase_personal_owner(NEW.original_transaction_id, NEW.household_id);
        NEW.former_member_personal := false;
    ELSIF TG_OP = 'INSERT' THEN
        NEW.personal_owner_id := NULL;
        NEW.former_member_personal := false;
    ELSE
        NEW.personal_owner_id := OLD.personal_owner_id;
        NEW.former_member_personal := OLD.former_member_personal;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_installment_plans_personal_owner ON public.installment_plans;
CREATE TRIGGER trg_installment_plans_personal_owner
    BEFORE INSERT OR UPDATE OF original_transaction_id ON public.installment_plans
    FOR EACH ROW EXECUTE FUNCTION public.nafaqah_plan_personal_owner();

-- A linked purchase reclassified (or moved to another wife) takes its plans with it.
CREATE OR REPLACE FUNCTION public.nafaqah_transaction_plan_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.installment_plans p
    SET personal_owner_id = public.nafaqah_purchase_personal_owner(NEW.id, p.household_id),
        former_member_personal = false
    WHERE p.original_transaction_id = NEW.id
      AND (p.personal_owner_id IS DISTINCT FROM public.nafaqah_purchase_personal_owner(NEW.id, p.household_id)
           OR p.former_member_personal);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_plan_owner ON public.transactions;
CREATE TRIGGER trg_transactions_plan_owner
    AFTER UPDATE OF nafaqah_class, nafaqah_spouse_id, household_id ON public.transactions
    FOR EACH ROW
    WHEN (OLD.nafaqah_class IS DISTINCT FROM NEW.nafaqah_class
          OR OLD.nafaqah_spouse_id IS DISTINCT FROM NEW.nafaqah_spouse_id
          OR OLD.household_id IS DISTINCT FROM NEW.household_id)
    EXECUTE FUNCTION public.nafaqah_transaction_plan_owner();

-- Existing plans, once: a linked plan gets its purchase's owner (a second run finds nothing to
-- change). A plan whose purchase was deleted before this file has no link to learn it from: it
-- stays household-wide, as it was.
UPDATE public.installment_plans p
SET personal_owner_id = public.nafaqah_purchase_personal_owner(p.original_transaction_id, p.household_id)
WHERE p.original_transaction_id IS NOT NULL
  AND p.personal_owner_id IS DISTINCT FROM public.nafaqah_purchase_personal_owner(p.original_transaction_id, p.household_id);

-- The delete of a person (below) finds their plans by this.
CREATE INDEX IF NOT EXISTS idx_installment_plans_personal_owner
    ON public.installment_plans (personal_owner_id)
    WHERE personal_owner_id IS NOT NULL;

-- A deleted person's id leaves both columns with them, as user_id does (ON DELETE SET NULL): the
-- purge's "nothing names them" holds, and an out-of-band delete leaves no id behind either. It runs
-- before their row goes, while their accounts (which cascade from it) still exist, so the rows it
-- rewrites still satisfy their account keys. A plan of a wife still a wife of its household (an
-- out-of-band delete; the purge marked hers already) keeps the former wife's mark, so it stays
-- hidden; a linked one then follows its purchase, which her leaving makes the household's.
-- (Setting these two columns alone does not wake the plan's trigger.)
CREATE OR REPLACE FUNCTION public.nafaqah_forget_transfer_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.account_transfers t
    SET personal_owner_ids = array_remove(t.personal_owner_ids, OLD.id)
    WHERE OLD.id = ANY (t.personal_owner_ids);
    UPDATE public.installment_plans p
    SET personal_owner_id = NULL,
        former_member_personal = p.former_member_personal OR public.nafaqah_is_spouse_member(p.household_id, OLD.id)
    WHERE p.personal_owner_id = OLD.id;
    -- A wife account still assigned to her (a delete by any other path than the purge, which did
    -- this already) becomes a former wife's before her id goes: archived, naming nobody (section 12).
    UPDATE public.accounts a
    SET is_archived = true,
        assigned_wife_id = NULL,
        updated_at = now()
    WHERE a.assigned_wife_id = OLD.id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_forget_transfer_owner ON public.users;
CREATE TRIGGER trg_users_forget_transfer_owner
    BEFORE DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.nafaqah_forget_transfer_owner();

-- The wives of the caller's household whose transfers and plans the caller does not read: every
-- wife but the caller, and none for whoever sees allowances (10c). Who the wives of the household
-- are is no secret to its members (users_select_household); nothing of their accounts is returned.
CREATE OR REPLACE FUNCTION public.nafaqah_caller_hidden_wives()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN public.nafaqah_caller_sees_allowances() THEN '{}'::uuid[]
        ELSE COALESCE((SELECT array_agg(m.user_id ORDER BY m.user_id)
                       FROM public.household_memberships m
                       WHERE m.household_id = public.get_auth_user_household_id()
                         AND m.financial_role = 'spouse'
                         AND m.user_id IS DISTINCT FROM auth.uid()), '{}'::uuid[])
    END;
$$;

-- A row whose personal side is the caller's own is read (she reads her own accounts' rows; a member
-- who sent her money or got some from her reads that row; the owner of the account a repayment left
-- or returned to reads that row). Otherwise a transfer between accounts (no purpose) is read unless
-- a wife's account the caller does not read is on it, and a repayment's row (a purpose) only by her
-- ledger's managers and by the wife whose repayment it is (review R3B-02). The caller's halves run
-- once per statement (InitPlans); per row, array tests, and the ledger link only for a repayment's
-- row the caller neither manages nor owns.
-- A row with a wife account on it (section 12) is read like the account: by her and its owner (both
-- in personal_owner_ids), the owner of the other personal side, and her ledger's managers; never by
-- an admin who is not a wife while the husband is there, a co-wife or a member.
DROP POLICY IF EXISTS transfers_select_household ON public.account_transfers;
CREATE POLICY transfers_select_household ON public.account_transfers
    FOR SELECT TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND ((SELECT auth.uid()) = ANY (personal_owner_ids)
                OR (purpose IS NULL AND NOT touches_wife_account
                    AND NOT (personal_owner_ids && (SELECT public.nafaqah_caller_hidden_wives())))
                OR (purpose IS NULL AND touches_wife_account AND (SELECT public.nafaqah_caller_manages_ledgers()))
                OR (purpose IS NOT NULL
                    AND ((SELECT public.nafaqah_caller_manages_ledgers())
                         OR (purpose IN ('wife_repayment', 'wife_repayment_reversal')
                             AND EXISTS (SELECT 1 FROM public.spouse_reimbursements r
                                         WHERE r.transfer_id = account_transfers.id
                                           AND r.wife_user_id = (SELECT auth.uid())))))));
-- The first version of 10e named a wife's own rows with this helper; the caller's own id covers them.
DROP FUNCTION IF EXISTS public.nafaqah_caller_wife_id();

-- The kept owner hides the plan as her purchase would, linked or not, and the former wife's mark as
-- a deleted wife's purchase would be (two InitPlans, an array test and a boolean per row: nothing
-- looked up, review R3B-03). A new or linked-again plan's purchase is read under the caller's own
-- RLS (one primary key probe per written row, review R3B-05).
DROP POLICY IF EXISTS "Allow household members full access to installment_plans" ON public.installment_plans;
CREATE POLICY "Allow household members full access to installment_plans" ON public.installment_plans
    FOR ALL TO authenticated
    USING (household_id = (SELECT public.get_auth_user_household_id())
           AND (personal_owner_id IS NULL
                OR NOT (ARRAY[personal_owner_id] && (SELECT public.nafaqah_caller_hidden_wives())))
           AND (NOT former_member_personal OR (SELECT public.nafaqah_caller_sees_allowances())))
    WITH CHECK (household_id = (SELECT public.get_auth_user_household_id())
                AND (original_transaction_id IS NULL
                     OR EXISTS (SELECT 1 FROM public.transactions t WHERE t.id = installment_plans.original_transaction_id)));

-- 12. The wife account (owner decisions 2026-11-06, superseding "her account is never credited") --
-- An account of kind 'wife' (columns in section 3b): personal (not shared), in SAR, owned by the
-- husband and assigned to one wife of the household (assigned_wife_id). A wife may still have
-- accounts of her own; those stay hers alone and no repayment credits them.
--   * Created and assigned only by her husband (the household's provider while he is a current
--     member who is not a wife: nafaqah_ledger_husband_id), through create_wife_account and
--     assign_wife_account, never by a client's own insert or update (trg_accounts_wife_account_guard).
--     Assigning again is for a mistake only: refused once the account has any history, which would
--     otherwise show one wife's spending to another. Its owner names and archives it.
--   * Seen (its row, balance, history and transfer rows) by her (assigned_wife_id), its owner and
--     her ledger's managers (her husband; when he is gone, an admin who is not a wife): never by a
--     co-wife (even an admin), an ordinary member, or an admin who is not a wife while the husband is
--     there, who do not learn it exists (transfer_between_accounts answers an account they do not
--     see as no account).
--   * Spent from only by her: her personal purchases (wife_personal) and her advances
--     (wife_reimbursable), as their creator (trg_wife_account_spending). Nobody else spends from it,
--     the husband included: what is in it is hers to spend, and he only funds it.
--   * Funded by its owner or her ledger's managers (transfer_between_accounts into it); nothing is
--     transferred out of it. Every repayment to her credits one of hers (sections 5 to 8): the
--     payer picks it (on a direct repayment and on an approval, where he may change her choice to
--     another of hers), she picks it on her request. A reversal takes the amount back out of it
--     (refused when it no longer holds it, or is archived). A former member's payment credits none.
--   * When she leaves or her account is deleted it is archived and assigned to nobody, and stays
--     its owner's (her purge also takes her name out of its name); when his account is deleted it
--     passes to the household's primary admin, or to her when that admin is a co-wife (section 10).

-- Who sees a wife account (beside the owner, who sees every account he owns): her and her ledger's
-- managers, in the household.
CREATE OR REPLACE FUNCTION public.nafaqah_may_see_wife_account(p_household_id uuid, p_actor uuid, p_owner uuid, p_assigned uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT p_actor IS NOT NULL AND (
        p_actor = p_owner
        OR (p_actor = p_assigned AND EXISTS (SELECT 1 FROM public.household_memberships m
                                             WHERE m.household_id = p_household_id AND m.user_id = p_actor))
        OR public.nafaqah_may_manage_ledgers(p_household_id, p_actor));
$$;

-- 20261020100000's read rule (the owner; a shared pool by its household), with the wife account:
-- the wife it is assigned to and her ledger's managers, in their active household. The caller's
-- half runs once per statement (InitPlan) and only for a wife account.
DROP POLICY IF EXISTS "accounts_select" ON public.accounts;
CREATE POLICY "accounts_select" ON public.accounts
    FOR SELECT
    TO authenticated
    USING (owner_user_id = (SELECT auth.uid())
        OR (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id()))
        OR (account_type = 'wife' AND household_id = (SELECT public.get_auth_user_household_id())
            AND (assigned_wife_id = (SELECT auth.uid()) OR (SELECT public.nafaqah_caller_manages_ledgers()))));

-- A client never makes a wife account or changes whom it is assigned to (or makes one into another
-- kind): only the RPCs below and the server do. Run as the caller (SECURITY INVOKER), so it tells a
-- client's own statement (current_user authenticated or anon) from one inside an RPC.
CREATE OR REPLACE FUNCTION public.nafaqah_guard_wife_account_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.account_type = 'wife' OR NEW.assigned_wife_id IS NOT NULL THEN
            RAISE EXCEPTION 'Forbidden: a wife account is created by her husband in the app'
                USING ERRCODE = '42501', HINT = 'wife_account_forbidden';
        END IF;
    ELSIF (NEW.account_type = 'wife') IS DISTINCT FROM (OLD.account_type = 'wife')
          OR NEW.assigned_wife_id IS DISTINCT FROM OLD.assigned_wife_id THEN
        RAISE EXCEPTION 'Forbidden: a wife account stays one, and only her husband assigns it'
            USING ERRCODE = '42501', HINT = 'wife_account_forbidden';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_accounts_wife_account_guard ON public.accounts;
CREATE TRIGGER trg_accounts_wife_account_guard
    BEFORE INSERT OR UPDATE ON public.accounts
    FOR EACH ROW EXECUTE FUNCTION public.nafaqah_guard_wife_account_row();

-- Only she spends from her wife account, and only her personal purchases and her advances, as their
-- creator; not archived (nobody spends from a former wife's). The husband does not: he funds it.
-- Runs after trg_bind_transaction_creator (names order BEFORE triggers), so user_id is filled in.
-- The system's own cascades (her leaving declassifies her rows) leave the account as it is.
CREATE OR REPLACE FUNCTION public.nafaqah_guard_wife_account_spending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_acc public.accounts%ROWTYPE;
BEGIN
    IF NEW.account_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.account_id IS NOT DISTINCT FROM OLD.account_id AND pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;
    SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id;
    IF v_acc.account_type IS DISTINCT FROM 'wife' THEN
        RETURN NEW;
    END IF;
    -- A client who does not see it gets the answer the row policy gives for any account not theirs,
    -- word for word: this refusal must not tell that a wife account is there.
    IF auth.uid() IS NOT NULL
       AND NOT public.nafaqah_may_see_wife_account(v_acc.household_id, auth.uid(), v_acc.owner_user_id, v_acc.assigned_wife_id) THEN
        RAISE EXCEPTION 'new row violates row-level security policy for table "transactions"' USING ERRCODE = '42501';
    END IF;
    IF v_acc.assigned_wife_id IS NULL OR v_acc.is_archived IS TRUE
       OR NEW.user_id IS DISTINCT FROM v_acc.assigned_wife_id
       OR NEW.nafaqah_spouse_id IS DISTINCT FROM v_acc.assigned_wife_id
       OR NEW.nafaqah_class IS NULL OR NEW.nafaqah_class NOT IN ('wife_personal', 'wife_reimbursable') THEN
        RAISE EXCEPTION 'A wife account is spent from only by her, for her personal purchases and her advances'
            USING ERRCODE = '42501', HINT = 'wife_account_spending';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wife_account_spending ON public.transactions;
CREATE TRIGGER trg_wife_account_spending
    BEFORE INSERT OR UPDATE OF account_id, nafaqah_class, nafaqah_spouse_id, user_id ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.nafaqah_guard_wife_account_spending();

-- 20261101000100's guard, with her wife account among the accounts a wife-class row may use.
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
         AND (a.owner_user_id = NEW.nafaqah_spouse_id
              OR (a.account_type = 'wife' AND a.assigned_wife_id = NEW.nafaqah_spouse_id))
         AND a.is_shared_pool = false
         AND a.is_archived = false
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

-- 20261020400000's balance trigger and its helper, with the wife account: the wife it is assigned
-- to debits it with her own purchases, as an owner debits his own account. An admin edits or
-- deletes her purchases on it only when he may see it (review R3C-01, owner decision 2026-11-07):
-- its owner, or her ledger's manager (an admin who is not a wife when her husband is gone); a
-- co-wife admin, and an admin who is not a wife while the husband is there, never move its balance,
-- also on a path the row policies do not cover. Nothing else of either changes;
-- trg_wife_account_spending decides which of her purchases may be on it.
CREATE OR REPLACE FUNCTION public.transaction_personal_account_writable(
    p_account public.accounts,
    p_creator_user_id uuid,
    p_caller_uid uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT p_caller_uid IS NULL
        OR p_account.is_shared_pool
        OR p_account.owner_user_id = p_caller_uid
        OR (p_account.account_type = 'wife' AND p_account.assigned_wife_id = p_caller_uid)
        OR (
            (p_account.owner_user_id = p_creator_user_id
             OR (p_account.account_type = 'wife' AND p_account.assigned_wife_id = p_creator_user_id))
            AND public.household_member_role(p_account.household_id, p_caller_uid) = 'admin'
            AND (p_account.account_type IS DISTINCT FROM 'wife'
                 OR public.nafaqah_may_see_wife_account(p_account.household_id, p_caller_uid,
                                                        p_account.owner_user_id, p_account.assigned_wife_id))
        );
$$;

CREATE OR REPLACE FUNCTION public.update_account_balance_on_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_acc public.accounts%ROWTYPE;
    v_caller_uid UUID;
BEGIN
    BEGIN
        v_caller_uid := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_caller_uid := NULL;
    END;
    IF TG_OP = 'INSERT' THEN
        IF NEW.account_id IS NOT NULL THEN
            SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id FOR UPDATE;
            IF v_acc.id IS NULL THEN
                RAISE EXCEPTION 'Target account % not found', NEW.account_id USING ERRCODE = 'P0002';
            END IF;
            IF v_acc.household_id <> NEW.household_id THEN
                RAISE EXCEPTION 'Account % does not belong to transaction household %', NEW.account_id, NEW.household_id USING ERRCODE = '42501';
            END IF;
            IF v_caller_uid IS NOT NULL AND v_acc.is_shared_pool = false AND v_acc.owner_user_id <> v_caller_uid
               AND NOT (v_acc.account_type = 'wife' AND v_acc.assigned_wife_id IS NOT DISTINCT FROM v_caller_uid) THEN
                RAISE EXCEPTION 'Access denied: cannot debit personal account owned by another user' USING ERRCODE = '42501';
            END IF;

            UPDATE public.accounts
            SET balance = balance - NEW.amount,
                updated_at = now()
            WHERE id = NEW.account_id;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.account_id IS NOT NULL THEN
            SELECT * INTO v_acc FROM public.accounts WHERE id = OLD.account_id FOR UPDATE;
            IF v_acc.id IS NOT NULL THEN
                IF v_acc.household_id <> OLD.household_id THEN
                    RAISE EXCEPTION 'Account % does not belong to transaction household %', OLD.account_id, OLD.household_id USING ERRCODE = '42501';
                END IF;
                IF NOT public.transaction_personal_account_writable(v_acc, OLD.user_id, v_caller_uid) THEN
                    RAISE EXCEPTION 'Access denied: cannot credit personal account owned by another user' USING ERRCODE = '42501';
                END IF;

                UPDATE public.accounts
                SET balance = balance + OLD.amount,
                    updated_at = now()
                WHERE id = OLD.account_id;
            END IF;
        END IF;
        RETURN OLD;

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.account_id IS DISTINCT FROM NEW.account_id OR OLD.amount <> NEW.amount THEN
            -- Revert old account debit
            IF OLD.account_id IS NOT NULL THEN
                SELECT * INTO v_acc FROM public.accounts WHERE id = OLD.account_id FOR UPDATE;
                IF v_acc.id IS NOT NULL THEN
                    IF v_acc.household_id <> OLD.household_id THEN
                        RAISE EXCEPTION 'Account % does not belong to transaction household %', OLD.account_id, OLD.household_id USING ERRCODE = '42501';
                    END IF;
                    IF NOT public.transaction_personal_account_writable(v_acc, OLD.user_id, v_caller_uid) THEN
                        RAISE EXCEPTION 'Access denied: cannot credit personal account owned by another user' USING ERRCODE = '42501';
                    END IF;

                    UPDATE public.accounts
                    SET balance = balance + OLD.amount,
                        updated_at = now()
                    WHERE id = OLD.account_id;
                END IF;
            END IF;

            -- Apply new account debit
            IF NEW.account_id IS NOT NULL THEN
                SELECT * INTO v_acc FROM public.accounts WHERE id = NEW.account_id FOR UPDATE;
                IF v_acc.id IS NULL THEN
                    RAISE EXCEPTION 'Target account % not found', NEW.account_id USING ERRCODE = 'P0002';
                END IF;
                IF v_acc.household_id <> NEW.household_id THEN
                    RAISE EXCEPTION 'Account % does not belong to transaction household %', NEW.account_id, NEW.household_id USING ERRCODE = '42501';
                END IF;
                IF NOT public.transaction_personal_account_writable(v_acc, NEW.user_id, v_caller_uid) THEN
                    RAISE EXCEPTION 'Access denied: cannot debit personal account owned by another user' USING ERRCODE = '42501';
                END IF;

                UPDATE public.accounts
                SET balance = balance - NEW.amount,
                    updated_at = now()
                WHERE id = NEW.account_id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- 20261020400000's helper, with her wife account among the accounts of a transaction she creates
-- (the spending guard above decides which of her transactions).
CREATE OR REPLACE FUNCTION public.transaction_account_matches(
    p_account_id uuid,
    p_household_id uuid,
    p_creator_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.accounts a
        WHERE a.id = p_account_id
          AND a.household_id = p_household_id
          AND (a.is_shared_pool = true OR a.owner_user_id = p_creator_user_id
               OR (a.account_type = 'wife' AND a.assigned_wife_id = p_creator_user_id))
    );
$$;

-- 20261020400000's insert rule, through the same helper as the update rule.
DROP POLICY IF EXISTS "transactions_insert_household" ON public.transactions;
CREATE POLICY "transactions_insert_household" ON public.transactions
    FOR INSERT TO authenticated
    WITH CHECK (
        household_id = (SELECT public.get_auth_user_household_id())
        AND user_id = (SELECT auth.uid())
        AND (
            account_id IS NULL
            OR public.transaction_account_matches(account_id, household_id, user_id)
        )
    );

-- 20261020400000's transfer, with the wife account: an account the caller does not see is no
-- account (a wife account is not revealed, also not by a refusal), nothing leaves a wife account,
-- and only its owner or her ledger's managers put money into one (not an archived one). Locks
-- pools first, then the other accounts in id order: the order of the purge and the repayments.
CREATE OR REPLACE FUNCTION public.transfer_between_accounts(
    p_household_id uuid,
    p_from_account_id uuid,
    p_to_account_id uuid,
    p_amount numeric,
    p_fee numeric DEFAULT 0.0,
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_uid UUID;
    v_from_acc RECORD;
    v_to_acc RECORD;
    v_total_deduction NUMERIC;
    v_transfer_id UUID;
    v_created_at TIMESTAMPTZ := now();
    v_result jsonb;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive' USING ERRCODE = '22023';
    END IF;

    IF p_fee IS NULL OR p_fee < 0 THEN
        RAISE EXCEPTION 'Transfer fee cannot be negative' USING ERRCODE = '22023';
    END IF;

    -- Columns are NUMERIC(14,2)/(10,2): a third decimal would be rounded
    -- independently on each side of the transfer and mint or burn money.
    IF p_amount <> round(p_amount, 2) OR p_fee <> round(p_fee, 2) THEN
        RAISE EXCEPTION 'Transfer amount and fee must have at most 2 decimal places' USING ERRCODE = '22023';
    END IF;

    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'Cannot transfer between the same account' USING ERRCODE = '22023';
    END IF;

    -- Strict NULL-safe membership check
    IF p_household_id IS NULL OR public.get_auth_user_household_id() IS NULL OR p_household_id IS DISTINCT FROM public.get_auth_user_household_id() THEN
        RAISE EXCEPTION 'Access denied: caller does not belong to specified household' USING ERRCODE = '42501';
    END IF;

    -- Pools first, then the rest, each in id order.
    PERFORM 1 FROM public.accounts WHERE id IN (p_from_account_id, p_to_account_id)
    ORDER BY is_shared_pool DESC, id
    FOR UPDATE;
    SELECT * INTO v_from_acc FROM public.accounts WHERE id = p_from_account_id;
    SELECT * INTO v_to_acc FROM public.accounts WHERE id = p_to_account_id;

    -- A wife account the caller does not see is answered as no account.
    IF v_from_acc.id IS NULL
       OR (v_from_acc.account_type = 'wife'
           AND NOT public.nafaqah_may_see_wife_account(v_from_acc.household_id, v_caller_uid,
                                                       v_from_acc.owner_user_id, v_from_acc.assigned_wife_id)) THEN
        RAISE EXCEPTION 'Source account not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_to_acc.id IS NULL
       OR (v_to_acc.account_type = 'wife'
           AND NOT public.nafaqah_may_see_wife_account(v_to_acc.household_id, v_caller_uid,
                                                       v_to_acc.owner_user_id, v_to_acc.assigned_wife_id)) THEN
        RAISE EXCEPTION 'Destination account not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_from_acc.household_id <> p_household_id OR v_to_acc.household_id <> p_household_id THEN
        RAISE EXCEPTION 'Both accounts must belong to the household' USING ERRCODE = '42501';
    END IF;

    -- The wife account: she spends from it; nothing is transferred out of it, by its owner either.
    IF v_from_acc.account_type = 'wife' THEN
        RAISE EXCEPTION 'Forbidden: a wife account is spent from, not transferred out of'
            USING ERRCODE = '42501', HINT = 'wife_account_no_transfer_out';
    END IF;

    -- Personal source: only its owner. Shared pool source: only a household admin (DB-16).
    IF v_from_acc.is_shared_pool = false AND v_from_acc.owner_user_id <> v_caller_uid THEN
        RAISE EXCEPTION 'Access denied: cannot transfer from an account owned by another user' USING ERRCODE = '42501';
    END IF;
    IF v_from_acc.is_shared_pool = true
       AND public.household_member_role(p_household_id, v_caller_uid) IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Forbidden: only household admins can move money out of a shared pool' USING ERRCODE = '42501';
    END IF;

    -- Its owner or her ledger's managers fund it, not once it is archived.
    IF v_to_acc.account_type = 'wife' THEN
        IF v_caller_uid IS DISTINCT FROM v_to_acc.owner_user_id
           AND NOT public.nafaqah_may_manage_ledgers(p_household_id, v_caller_uid) THEN
            RAISE EXCEPTION 'Forbidden: her wife account is funded by her husband'
                USING ERRCODE = '42501', HINT = 'wife_account_forbidden';
        END IF;
        IF v_to_acc.is_archived IS TRUE THEN
            RAISE EXCEPTION 'This wife account is archived' USING ERRCODE = 'P0002', HINT = 'account_unavailable';
        END IF;
    END IF;

    v_total_deduction := p_amount + p_fee;
    IF v_from_acc.balance < v_total_deduction THEN
        RAISE EXCEPTION 'Insufficient funds: balance (%) is less than transfer plus fee (%)', v_from_acc.balance, v_total_deduction USING ERRCODE = '22000';
    END IF;

    UPDATE public.accounts
    SET balance = balance - v_total_deduction,
        updated_at = v_created_at
    WHERE id = p_from_account_id;

    UPDATE public.accounts
    SET balance = balance + p_amount,
        updated_at = v_created_at
    WHERE id = p_to_account_id;

    INSERT INTO public.account_transfers (
        household_id,
        user_id,
        from_account_id,
        to_account_id,
        amount,
        fee,
        timestamp,
        notes,
        created_at
    ) VALUES (
        p_household_id,
        v_caller_uid,
        p_from_account_id,
        p_to_account_id,
        p_amount,
        p_fee,
        v_created_at,
        p_notes,
        v_created_at
    ) RETURNING id INTO v_transfer_id;

    SELECT jsonb_build_object(
        'id', v_transfer_id,
        'household_id', p_household_id,
        'user_id', v_caller_uid,
        'from_account_id', p_from_account_id,
        'to_account_id', p_to_account_id,
        'amount', p_amount,
        'fee', p_fee,
        'timestamp', v_created_at,
        'notes', p_notes,
        'created_at', v_created_at
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Her husband makes her a wife account (in SAR, empty, his own, assigned to her). Returns it.
CREATE OR REPLACE FUNCTION public.create_wife_account(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_name text,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_name text := btrim(COALESCE(p_name, ''));
    v_acc public.accounts%ROWTYPE;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    -- The household as the purge locks it, so her purge either ran (she is no wife here now) or
    -- waits for this account and archives it.
    PERFORM 1 FROM public.households WHERE id = p_household_id FOR KEY SHARE;
    IF v_actor IS DISTINCT FROM public.nafaqah_ledger_husband_id(p_household_id) THEN
        RAISE EXCEPTION 'Forbidden: only her husband creates a wife account'
            USING ERRCODE = '42501', HINT = 'wife_account_forbidden';
    END IF;
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'A wife account is for a wife of this household' USING ERRCODE = '22023', HINT = 'not_a_wife';
    END IF;
    IF v_name = '' OR char_length(v_name) > 60 THEN
        RAISE EXCEPTION 'A name of 1 to 60 characters' USING ERRCODE = '22023', HINT = 'invalid_name';
    END IF;
    INSERT INTO public.accounts (household_id, owner_user_id, name, account_type, currency, balance, is_shared_pool,
                                 is_archived, icon_name, assigned_wife_id)
    VALUES (p_household_id, v_actor, v_name, 'wife', 'SAR', 0, false, false, 'favorite_rounded', p_wife_user_id)
    RETURNING * INTO v_acc;
    RETURN jsonb_build_object('id', v_acc.id, 'household_id', v_acc.household_id, 'owner_user_id', v_acc.owner_user_id,
                              'assigned_wife_id', v_acc.assigned_wife_id, 'name', v_acc.name, 'account_type', v_acc.account_type,
                              'currency', v_acc.currency, 'balance', v_acc.balance, 'is_archived', v_acc.is_archived,
                              'created_at', v_acc.created_at);
END;
$$;

-- Her husband corrects whom a wife account he owns is assigned to, before it has any history
-- (a transaction or a transfer): afterwards it would show one wife's money to another.
CREATE OR REPLACE FUNCTION public.assign_wife_account(
    p_household_id uuid,
    p_account_id uuid,
    p_wife_user_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_acc public.accounts%ROWTYPE;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    PERFORM 1 FROM public.households WHERE id = p_household_id FOR KEY SHARE;
    SELECT * INTO v_acc FROM public.accounts WHERE id = p_account_id FOR UPDATE;
    IF v_acc.id IS NULL OR v_acc.household_id IS DISTINCT FROM p_household_id OR v_acc.account_type IS DISTINCT FROM 'wife'
       OR NOT public.nafaqah_may_see_wife_account(p_household_id, v_actor, v_acc.owner_user_id, v_acc.assigned_wife_id) THEN
        RAISE EXCEPTION 'No such wife account in this household' USING ERRCODE = 'P0002', HINT = 'account_not_found';
    END IF;
    IF v_actor IS DISTINCT FROM public.nafaqah_ledger_husband_id(p_household_id) OR v_actor IS DISTINCT FROM v_acc.owner_user_id THEN
        RAISE EXCEPTION 'Forbidden: her husband assigns the wife accounts he owns'
            USING ERRCODE = '42501', HINT = 'wife_account_forbidden';
    END IF;
    IF v_acc.is_archived IS TRUE THEN
        RAISE EXCEPTION 'This wife account is archived' USING ERRCODE = 'P0002', HINT = 'account_unavailable';
    END IF;
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'A wife account is for a wife of this household' USING ERRCODE = '22023', HINT = 'not_a_wife';
    END IF;
    IF v_acc.assigned_wife_id = p_wife_user_id THEN
        RETURN jsonb_build_object('id', v_acc.id, 'assigned_wife_id', v_acc.assigned_wife_id, 'changed', false);
    END IF;
    IF EXISTS (SELECT 1 FROM public.transactions t WHERE t.account_id = v_acc.id)
       OR EXISTS (SELECT 1 FROM public.account_transfers t WHERE t.from_account_id = v_acc.id OR t.to_account_id = v_acc.id)
       OR EXISTS (SELECT 1 FROM public.spouse_reimbursement_requests q WHERE q.wife_account_id = v_acc.id) THEN
        RAISE EXCEPTION 'This wife account has history: make her a new one instead'
            USING ERRCODE = '22023', HINT = 'wife_account_has_history';
    END IF;
    UPDATE public.accounts SET assigned_wife_id = p_wife_user_id, updated_at = now() WHERE id = v_acc.id;
    RETURN jsonb_build_object('id', v_acc.id, 'assigned_wife_id', p_wife_user_id, 'changed', true);
END;
$$;

-- Its owner archives a wife account: nobody spends from it, credits it or funds it any more; its
-- balance and history stay. (He may also archive it from the accounts screen, as any account.)
CREATE OR REPLACE FUNCTION public.archive_wife_account(
    p_household_id uuid,
    p_account_id uuid,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_acc public.accounts%ROWTYPE;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    PERFORM 1 FROM public.households WHERE id = p_household_id FOR KEY SHARE;
    SELECT * INTO v_acc FROM public.accounts WHERE id = p_account_id FOR UPDATE;
    IF v_acc.id IS NULL OR v_acc.household_id IS DISTINCT FROM p_household_id OR v_acc.account_type IS DISTINCT FROM 'wife'
       OR NOT public.nafaqah_may_see_wife_account(p_household_id, v_actor, v_acc.owner_user_id, v_acc.assigned_wife_id) THEN
        RAISE EXCEPTION 'No such wife account in this household' USING ERRCODE = 'P0002', HINT = 'account_not_found';
    END IF;
    IF v_actor IS DISTINCT FROM v_acc.owner_user_id THEN
        RAISE EXCEPTION 'Forbidden: a wife account is archived by its owner'
            USING ERRCODE = '42501', HINT = 'wife_account_forbidden';
    END IF;
    IF v_acc.is_archived IS NOT TRUE THEN
        UPDATE public.accounts SET is_archived = true, updated_at = now() WHERE id = v_acc.id;
    END IF;
    RETURN jsonb_build_object('id', v_acc.id, 'is_archived', true, 'changed', v_acc.is_archived IS NOT TRUE);
END;
$$;

-- 11. Privileges ---------------------------------------------------------------------------------
-- The wife account (section 12): the read policy runs its caller's half as the caller; the three
-- RPCs are the clients' and the API's; the rest is internal.
REVOKE ALL ON FUNCTION public.nafaqah_may_see_wife_account(uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nafaqah_may_see_wife_account(uuid, uuid, uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.nafaqah_require_wife_account(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_lock(uuid, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_transfer(uuid, uuid, uuid, uuid, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.account_deletion_wife_account_recipient(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.account_deletion_wife_account_recipient(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.nafaqah_guard_wife_account_row() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nafaqah_guard_wife_account_spending() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_wife_account(uuid, uuid, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_wife_account(uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.archive_wife_account(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_wife_account(uuid, uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_wife_account(uuid, uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.archive_wife_account(uuid, uuid, uuid) TO authenticated, service_role;
-- As 20261101000100 and 20261020400000 left them.
REVOKE EXECUTE ON FUNCTION public.transaction_personal_account_writable(public.accounts, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_account_balance_on_transaction() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_wife_class_account() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.transfer_between_accounts(uuid, uuid, uuid, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_between_accounts(uuid, uuid, uuid, numeric, numeric, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.transaction_account_matches(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transaction_account_matches(uuid, uuid, uuid) TO authenticated, service_role;
-- Her transfers and plans: the read policies run the caller's helper as the caller; the others are
-- internal.
REVOKE ALL ON FUNCTION public.nafaqah_caller_hidden_wives() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nafaqah_caller_hidden_wives() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_personal_owners_of(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nafaqah_personal_owners_of(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.nafaqah_purchase_personal_owner(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nafaqah_purchase_personal_owner(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.nafaqah_transfer_personal_owners() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nafaqah_plan_personal_owner() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nafaqah_transaction_plan_owner() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nafaqah_forget_transfer_owner() FROM PUBLIC, anon, authenticated;
-- Her advance's guard (10d) is a trigger: nobody executes it.
REVOKE ALL ON FUNCTION public.nafaqah_guard_advance_attribution() FROM PUBLIC, anon, authenticated;
-- Who edits a row on her wife account (10d, review R3C-01): the write policies run it as the caller.
REVOKE ALL ON FUNCTION public.nafaqah_caller_hidden_wife_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nafaqah_caller_hidden_wife_accounts() TO authenticated, service_role;
-- Her receipt photo: the storage policy runs the helper as the caller.
REVOKE ALL ON FUNCTION public.nafaqah_receipt_hidden(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nafaqah_receipt_hidden(text) TO authenticated, service_role;
-- Her allowance: the helper is internal; the policy's half runs as the caller; both RPCs keep
-- 20261020300000's privileges (CREATE OR REPLACE keeps them; stated again for a fresh replay).
REVOKE ALL ON FUNCTION public.nafaqah_may_see_allowances(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nafaqah_may_see_allowances(uuid, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.nafaqah_caller_sees_allowances() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nafaqah_caller_sees_allowances() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_member_allowance_status(uuid, uuid, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_member_allowance(uuid, uuid, numeric, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_allowance_status(uuid, uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_member_allowance(uuid, uuid, numeric, text, uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.nafaqah_refuse_account_delete() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.nafaqah_net_repaid(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_outstanding(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_lock_account(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_debit(uuid, uuid, uuid, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_credit(uuid, uuid, uuid, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repay_from_account(uuid, uuid, uuid, numeric, text, text, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_replay(public.spouse_reimbursements, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_request_close(public.spouse_reimbursement_requests, text, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_may_repay(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_close_unfit_requests(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated, service_role;
-- As 001200 left it.
REVOKE ALL ON FUNCTION public.former_member_debt_outstanding(uuid, uuid) FROM PUBLIC, anon, authenticated;
-- As 20261020900000 left them.
REVOKE EXECUTE ON FUNCTION public.guard_wife_reimbursable_ledger() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.remove_nafaqah_ledger_on_membership_end() FROM PUBLIC, anon, authenticated;
-- As 001200 left it.
REVOKE ALL ON FUNCTION public.prepare_account_purge(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_purge(uuid) TO service_role;

DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'get_spouse_reimbursement_balance(uuid, uuid, uuid)',
        'record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid, uuid)',
        'record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid)',
        'request_spouse_reimbursement(uuid, numeric, text, uuid, uuid, uuid)',
        'cancel_spouse_reimbursement_request(uuid, uuid, uuid)',
        'decline_spouse_reimbursement_request(uuid, uuid, text, uuid)',
        'approve_spouse_reimbursement_request(uuid, uuid, uuid, uuid, uuid, uuid)',
        'reverse_spouse_reimbursement(uuid, uuid, uuid, uuid)',
        'record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid)',
        'reverse_former_member_debt_payment(uuid, uuid, uuid, uuid, uuid)'
    ] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', v_sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated, service_role', v_sig);
    END LOOP;
END $$;
-- The amount-only payment (the old 6-argument signature) keeps 001200's privilege: the service role
-- only (review R3-03). It only answers app_update_required; an old app reaches it through the API,
-- which answers 426 before calling it, so no client needs to execute it, and OWNER_ACTIONS step 15's
-- check (no client executes it) holds before and after this file.
REVOKE ALL ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid) TO service_role;

COMMIT;
