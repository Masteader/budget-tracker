-- ============================================================================
-- Migration: 20261105001300_wife_repayment_debit.sql
-- Proof tests: supabase/tests/56_wife_repayment_debit.sql, 57_wife_repayment_debit_concurrency.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Owner decision 2026-11-06. When the husband repays the wife for shared things she paid
-- (wife_reimbursable), the money leaves an account he picks:
--   * his account goes down by the amount;
--   * when she has a personal account in the app (hers, not shared, same household, not archived,
--     in SAR), it goes up by the same amount, as a transfer. Without one, or for a former member's
--     record (she is gone), only his side moves;
--   * no budget moves: her expense counted in the budget when she recorded it.
-- "Not tracked in the app" (no account) records the amount and method only, as before. Her waiver
-- of a former member's record still moves nothing. Her allowance is unaffected. Existing ledger rows
-- stay as they are: nothing is debited retroactively and no outstanding amount changes.
--
-- Design. Each repayment that names an account writes one account_transfers row (from his account,
-- to hers or NULL) and moves the two balances in the same statement, exactly as
-- transfer_between_accounts does. Transfers never touch budgets or transactions, so nothing can be
-- counted twice, and no budget, cycle-key or wife-class trigger is involved. The ledger row links
-- it (spouse_reimbursements.transfer_id, former_member_debt_events.transfer_id, ON DELETE SET NULL
-- so deleting an account keeps the history). Like the ledger itself, a repayment is append-only:
-- clients can neither delete nor edit the ledger or the transfer, so there is nothing to reverse.
--
-- His account must be in the household, not archived and in SAR (account_unavailable); his own
-- personal account, or a shared pool when he is a household admin (account_forbidden, the rule of
-- transfer_between_accounts); never when the wife records the repayment herself; and hold the amount
-- (insufficient_funds, as transfer_between_accounts refuses). Her account: one whose type matches
-- the payment method (cash -> cash, bank_transfer/iban -> bank, stc_pay/urpay -> e_wallet), else
-- her oldest. A repayment from an account needs a request key; the same key again answers as the
-- first time and changes nothing.
--
-- Signatures. The existing ones stay, amount only, so the deployed API and old app builds keep
-- working: record_spouse_reimbursement(6) and record_former_member_debt_payment(6) now call the
-- new ones with no account. The new ones take every argument explicitly (no defaults), so a call
-- with the old arguments can only mean the old function and no call is ambiguous:
--   record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, p_account_id uuid, p_request_key uuid)
--   record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, p_account_id uuid)
-- Re-running 20261105001200 after this file puts its own body of the 6-argument payment back,
-- which is the same amount-only payment, so that stays harmless.
--
-- Lock order: shared pool, household (KEY SHARE), personal accounts by id, then the ledger
-- (the spouse_reimbursement advisory lock comes first, as before; a former member's record row
-- comes last). prepare_account_purge locks pools, then households FOR UPDATE, then deletes her
-- accounts, so a repayment in flight either finishes before the purge or waits for it, never
-- holding her account while it waits for the household.
--
-- Safe to run again (IF NOT EXISTS, CREATE OR REPLACE).
--
-- Rollback (one transaction), after rolling back the app and the API:
--   DROP FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid),
--     public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid),
--     public.nafaqah_repayment_move(uuid, uuid, uuid, uuid, numeric, text),
--     public.nafaqah_repayment_lock_accounts(uuid, uuid, uuid, uuid, text);
--   Then run record_spouse_reimbursement's CREATE OR REPLACE statement from 20261020300000 and
--   record_former_member_debt_payment's from 20261105001200 (they replace the wrappers).
--   DROP INDEX public.uq_spouse_reimbursements_request, public.idx_spouse_reimbursements_transfer,
--     public.idx_former_member_debt_events_transfer;
--   ALTER TABLE public.spouse_reimbursements DROP COLUMN transfer_id, DROP COLUMN request_key;
--   ALTER TABLE public.former_member_debt_events DROP COLUMN transfer_id;
--   Balances already moved stay moved (the money did leave his account); the transfers stay in
--   account_transfers as ordinary history.
-- ============================================================================

BEGIN;

-- 1. Links from the ledger to the transfer ------------------------------------------------
ALTER TABLE public.spouse_reimbursements
    ADD COLUMN IF NOT EXISTS transfer_id uuid REFERENCES public.account_transfers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS request_key uuid;
CREATE UNIQUE INDEX IF NOT EXISTS uq_spouse_reimbursements_request
    ON public.spouse_reimbursements (household_id, request_key) WHERE request_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_spouse_reimbursements_transfer ON public.spouse_reimbursements (transfer_id);

ALTER TABLE public.former_member_debt_events
    ADD COLUMN IF NOT EXISTS transfer_id uuid REFERENCES public.account_transfers(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_former_member_debt_events_transfer ON public.former_member_debt_events (transfer_id);

COMMENT ON COLUMN public.spouse_reimbursements.transfer_id IS
    'The account_transfers row that moved the money (his account to hers, or to none), or NULL when not tracked in the app.';
COMMENT ON COLUMN public.spouse_reimbursements.request_key IS
    'The client''s idempotency key: the same key again answers as the first time.';
COMMENT ON COLUMN public.former_member_debt_events.transfer_id IS
    'The account_transfers row that moved the payment out of his account, or NULL when not tracked in the app.';

-- 2. Helpers (no client executes them) ---------------------------------------------------

-- Checks and locks the account he pays from, and finds and locks hers (p_wife_user_id NULL for a
-- former member). Returns both ids; to_account is NULL when she has none.
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_lock_accounts(
    p_household_id uuid,
    p_actor uuid,
    p_account_id uuid,
    p_wife_user_id uuid,
    p_payment_method text
)
RETURNS TABLE(from_account uuid, to_account uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_from public.accounts%ROWTYPE;
    v_to uuid;
    v_pref text := CASE lower(COALESCE(p_payment_method, ''))
                       WHEN 'cash' THEN 'cash'
                       WHEN 'bank_transfer' THEN 'bank'
                       WHEN 'iban' THEN 'bank'
                       WHEN 'stc_pay' THEN 'e_wallet'
                       WHEN 'urpay' THEN 'e_wallet'
                   END;
    v_pass int;
BEGIN
    FOR v_pass IN 1..2 LOOP
        -- Checked before any lock (a clear refusal locks nothing), and again under the locks.
        SELECT * INTO v_from FROM public.accounts WHERE id = p_account_id;
        IF v_from.id IS NULL OR v_from.household_id IS DISTINCT FROM p_household_id
           OR v_from.is_archived OR v_from.currency IS DISTINCT FROM 'SAR' THEN
            RAISE EXCEPTION 'This account cannot be used in this household'
                USING ERRCODE = 'P0002', HINT = 'account_unavailable';
        END IF;
        IF v_from.is_shared_pool THEN
            IF public.household_member_role(p_household_id, p_actor) IS DISTINCT FROM 'admin' THEN
                RAISE EXCEPTION 'Forbidden: only household admins can move money out of a shared pool'
                    USING ERRCODE = '42501', HINT = 'account_forbidden';
            END IF;
        ELSIF v_from.owner_user_id IS DISTINCT FROM p_actor THEN
            RAISE EXCEPTION 'Forbidden: a personal account is debited only by its owner'
                USING ERRCODE = '42501', HINT = 'account_forbidden';
        END IF;
        IF v_pass = 2 THEN
            -- Hers may have changed while we waited: credit it only if it still qualifies.
            IF v_to IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM public.accounts a
                WHERE a.id = v_to AND a.household_id = p_household_id AND a.owner_user_id = p_wife_user_id
                  AND NOT a.is_shared_pool AND NOT a.is_archived AND a.currency = 'SAR'
            ) THEN
                v_to := NULL;
            END IF;
            from_account := v_from.id;
            to_account := v_to;
            RETURN NEXT;
            RETURN;
        END IF;

        IF p_wife_user_id IS NOT NULL THEN
            SELECT a.id INTO v_to
            FROM public.accounts a
            WHERE a.household_id = p_household_id
              AND a.owner_user_id = p_wife_user_id
              AND NOT a.is_shared_pool
              AND NOT a.is_archived
              AND a.currency = 'SAR'
              AND a.id <> v_from.id
            ORDER BY (a.account_type = v_pref) DESC, a.created_at, a.id
            LIMIT 1;
        END IF;

        -- The purge's order: pools, then the household, then personal accounts.
        IF v_from.is_shared_pool THEN
            PERFORM 1 FROM public.accounts WHERE id = v_from.id FOR UPDATE;
        END IF;
        PERFORM 1 FROM public.households WHERE id = p_household_id FOR KEY SHARE;
        PERFORM 1 FROM public.accounts a
        WHERE a.id IN (CASE WHEN NOT v_from.is_shared_pool THEN v_from.id END, v_to)
        ORDER BY a.id
        FOR UPDATE;
    END LOOP;
END;
$$;

-- Moves the money: his account down, hers up (when there is one), one account_transfers row.
-- Both rows are locked by nafaqah_repayment_lock_accounts. Returns the transfer id.
CREATE OR REPLACE FUNCTION public.nafaqah_repayment_move(
    p_household_id uuid,
    p_actor uuid,
    p_from_account uuid,
    p_to_account uuid,
    p_amount numeric,
    p_note text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_balance numeric(14, 2);
    v_now timestamptz := now();
    v_id uuid;
BEGIN
    SELECT balance INTO v_balance FROM public.accounts WHERE id = p_from_account;
    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds: balance (%) is less than the repayment (%)', v_balance, p_amount
            USING ERRCODE = '22000', HINT = 'insufficient_funds';
    END IF;

    UPDATE public.accounts SET balance = balance - p_amount, updated_at = v_now WHERE id = p_from_account;
    IF p_to_account IS NOT NULL THEN
        UPDATE public.accounts SET balance = balance + p_amount, updated_at = v_now WHERE id = p_to_account;
    END IF;

    INSERT INTO public.account_transfers (household_id, user_id, from_account_id, to_account_id, amount, fee, timestamp, notes, created_at)
    VALUES (p_household_id, p_actor, p_from_account, p_to_account, p_amount, 0, v_now, p_note, v_now)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- 3. Repaying the wife ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_spouse_reimbursement(
    p_household_id uuid,
    p_wife_user_id uuid,
    p_amount numeric,
    p_payment_method text,
    p_notes text,
    p_actor_user_id uuid,
    p_account_id uuid,
    p_request_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := public.nafaqah_resolve_actor(p_actor_user_id);
    v_husband uuid;
    v_is_admin boolean;
    v_balance jsonb;
    v_outstanding numeric(14, 2);
    v_id uuid;
    v_method text := lower(COALESCE(NULLIF(trim(p_payment_method), ''), 'cash'));
    v_prev public.spouse_reimbursements%ROWTYPE;
    v_transfer public.account_transfers%ROWTYPE;
    v_from uuid;
    v_to uuid;
    v_transfer_id uuid;
BEGIN
    PERFORM public.nafaqah_require_member(p_household_id, v_actor);
    IF NOT public.nafaqah_is_spouse_member(p_household_id, p_wife_user_id) THEN
        RAISE EXCEPTION 'Reimbursements apply to a spouse member of this household' USING ERRCODE = '22023';
    END IF;

    v_husband := public.nafaqah_husband_id(p_household_id);
    SELECT EXISTS (
        SELECT 1 FROM public.household_memberships m
        WHERE m.household_id = p_household_id AND m.user_id = v_actor AND m.role = 'admin'
    ) INTO v_is_admin;
    IF v_actor <> p_wife_user_id AND v_actor IS DISTINCT FROM v_husband AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Forbidden: only the husband, the wife or a household admin can record a reimbursement'
            USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount > 999999999999.99 THEN
        RAISE EXCEPTION 'Reimbursement must be a positive SAR amount with at most 2 decimals' USING ERRCODE = '22023';
    END IF;
    IF v_method NOT IN ('stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other') THEN
        RAISE EXCEPTION 'Unsupported payment method %', v_method USING ERRCODE = '22023';
    END IF;
    IF p_account_id IS NOT NULL THEN
        -- She confirms what she received; the payer's account is his to pick.
        IF v_actor = p_wife_user_id THEN
            RAISE EXCEPTION 'Forbidden: the wife records a repayment without an account'
                USING ERRCODE = '42501', HINT = 'account_forbidden';
        END IF;
        IF p_request_key IS NULL THEN
            RAISE EXCEPTION 'A request key is required to move money' USING ERRCODE = '22023', HINT = 'request_key_required';
        END IF;
    END IF;

    -- Serialise repayments of one wife's debt so two concurrent calls cannot both pass the check.
    PERFORM pg_advisory_xact_lock(hashtextextended('spouse_reimbursement:' || p_household_id::text || ':' || p_wife_user_id::text, 0));

    -- The same tap again: answer as the first time, change nothing.
    IF p_request_key IS NOT NULL THEN
        SELECT * INTO v_prev FROM public.spouse_reimbursements
        WHERE household_id = p_household_id AND request_key = p_request_key;
        IF v_prev.id IS NOT NULL THEN
            IF v_prev.wife_user_id IS DISTINCT FROM p_wife_user_id THEN
                RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
            END IF;
            SELECT * INTO v_transfer FROM public.account_transfers WHERE id = v_prev.transfer_id;
            v_outstanding := (public.get_spouse_reimbursement_balance(p_household_id, p_wife_user_id, v_actor)->>'outstanding')::numeric;
            RETURN jsonb_build_object(
                'success', true, 'replayed', true,
                'reimbursement_id', v_prev.id,
                'household_id', p_household_id,
                'wife_user_id', p_wife_user_id,
                'paid_by_user_id', v_prev.paid_by_user_id,
                'amount', v_prev.amount,
                'payment_method', v_prev.payment_method,
                'account_id', v_transfer.from_account_id,
                'transfer_id', v_prev.transfer_id,
                'wife_account_credited', v_transfer.to_account_id IS NOT NULL,
                'outstanding_before', v_outstanding + v_prev.amount,
                'outstanding_after', v_outstanding);
        END IF;
    END IF;

    IF p_account_id IS NOT NULL THEN
        SELECT l.from_account, l.to_account INTO v_from, v_to
        FROM public.nafaqah_repayment_lock_accounts(p_household_id, v_actor, p_account_id, p_wife_user_id, v_method) l;
    END IF;

    v_balance := public.get_spouse_reimbursement_balance(p_household_id, p_wife_user_id, v_actor);
    v_outstanding := (v_balance->>'outstanding')::numeric;
    IF p_amount > v_outstanding THEN
        RAISE EXCEPTION 'Reimbursement of % exceeds the outstanding balance of %', p_amount, v_outstanding
            USING ERRCODE = '22023', HINT = 'overpayment';
    END IF;

    IF v_from IS NOT NULL THEN
        v_transfer_id := public.nafaqah_repayment_move(p_household_id, v_actor, v_from, v_to, p_amount, 'nafaqah_reimbursement');
    END IF;

    INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, paid_by_user_id, amount, payment_method, notes,
                                              recorded_by, request_key, transfer_id)
    VALUES (p_household_id, p_wife_user_id, v_husband, p_amount, v_method, NULLIF(left(trim(p_notes), 500), ''),
            v_actor, p_request_key, v_transfer_id)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', true,
        'replayed', false,
        'reimbursement_id', v_id,
        'household_id', p_household_id,
        'wife_user_id', p_wife_user_id,
        'paid_by_user_id', v_husband,
        'amount', p_amount,
        'payment_method', v_method,
        'account_id', v_from,
        'transfer_id', v_transfer_id,
        'wife_account_credited', v_to IS NOT NULL,
        'outstanding_before', v_outstanding,
        'outstanding_after', v_outstanding - p_amount
    );
END;
$$;

-- The old signature: amount and method only, as before.
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
    RETURN public.record_spouse_reimbursement(p_household_id, p_wife_user_id, p_amount, p_payment_method, p_notes,
                                              p_actor_user_id, NULL::uuid, NULL::uuid);
END;
$$;

-- 4. Paying a former member's record --------------------------------------------------------
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
    IF p_request_key IS NULL THEN
        RAISE EXCEPTION 'A request key is required' USING ERRCODE = '22023', HINT = 'request_key_required';
    END IF;

    IF p_account_id IS NOT NULL THEN
        -- A replay answers before any account is checked or locked: events never change.
        SELECT e.* INTO v_event FROM public.former_member_debt_events e
        JOIN public.former_member_debts d ON d.id = e.debt_id AND d.household_id = p_household_id
        WHERE e.debt_id = p_debt_id AND e.request_key = p_request_key;
        -- The accounts before the record row: a purge deleting the household holds the pools and
        -- the household and then waits for the record row, so it must never be held while waiting.
        IF v_event.id IS NULL THEN
            SELECT l.from_account INTO v_from
            FROM public.nafaqah_repayment_lock_accounts(p_household_id, v_actor, p_account_id, NULL, v_method) l;
        END IF;
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
        IF v_event.kind <> 'payment' THEN
            RAISE EXCEPTION 'This request key was used for something else' USING ERRCODE = '22023', HINT = 'request_key_reused';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'replayed', true, 'event_id', v_event.id, 'debt_id', v_debt.id,
            'amount', v_event.amount, 'payment_method', v_event.payment_method,
            'remaining', v_event.remaining_after, 'status', v_debt.status,
            'transfer_id', v_event.transfer_id,
            'account_id', (SELECT t.from_account_id FROM public.account_transfers t WHERE t.id = v_event.transfer_id));
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
            USING ERRCODE = '22023', HINT = 'overpayment';
    END IF;

    -- She is gone: only his side moves.
    IF v_from IS NOT NULL THEN
        v_transfer_id := public.nafaqah_repayment_move(p_household_id, v_actor, v_from, NULL, p_amount, 'former_member_debt_payment');
    END IF;

    UPDATE public.former_member_debts
    SET paid_amount = paid_amount + p_amount,
        status = CASE WHEN p_amount = v_remaining THEN 'settled' ELSE 'open' END,
        closed_at = CASE WHEN p_amount = v_remaining THEN now() END
    WHERE id = p_debt_id
    RETURNING * INTO v_debt;

    INSERT INTO public.former_member_debt_events (debt_id, kind, amount, payment_method, remaining_after, recorded_by, request_key, transfer_id)
    VALUES (p_debt_id, 'payment', p_amount, v_method, v_remaining - p_amount, v_actor, p_request_key, v_transfer_id)
    RETURNING * INTO v_event;

    RETURN jsonb_build_object(
        'success', true, 'replayed', false, 'event_id', v_event.id, 'debt_id', v_debt.id,
        'amount', v_event.amount, 'payment_method', v_event.payment_method,
        'remaining', v_event.remaining_after, 'status', v_debt.status,
        'transfer_id', v_transfer_id, 'account_id', v_from);
END;
$$;

-- The old signature: amount and method only, as before.
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
    RETURN public.record_former_member_debt_payment(p_household_id, p_debt_id, p_amount, p_payment_method,
                                                    p_request_key, p_actor_user_id, NULL::uuid);
END;
$$;

-- 5. Privileges --------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.nafaqah_repayment_lock_accounts(uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.nafaqah_repayment_move(uuid, uuid, uuid, uuid, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid) TO authenticated, service_role;

COMMIT;
