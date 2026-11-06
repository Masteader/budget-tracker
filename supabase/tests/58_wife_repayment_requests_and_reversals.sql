-- ============================================================================
-- Test 58: the wife asks, the husband approves; corrections are reversing entries
--
-- Migration: 20261105001300_wife_repayment_debit.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Owner decisions 2026-11-06:
--   * The wife no longer records a repayment. She marks "I received X": a pending request that
--     moves no money and does not reduce what is owed. The husband (when he is gone, an admin who
--     is not a wife: test 62) approves it with an account (the normal repayment: debit,
--     idempotent, overpayment refused, linked to the request) or declines it with an optional reason. She can cancel her own pending request.
--     Approval uses the requested amount exactly and re-checks what is owed at that moment.
--     Pending requests together never exceed what is owed (review R1-03: those that no longer fit close).
--   * Nothing is deleted, edited or voided. A tracked repayment is corrected by a reversal: one
--     per original (unique), crediting the original account back in full and adding the amount
--     back to what is owed. Refused for a legacy row without a transfer, an archived or deleted
--     account, and a former member's record waived after the payment.
--
-- Verifies:
--   1. Requests: pending, nothing moves, nothing owed changes; replay; only the wife asks; the
--      pending total is capped by what is owed.
--   2. Cancel: only by her, only while pending, replayed.
--   3. Decline: only the husband (an admin who is not a wife when he is gone, review R3-01), with an
--      optional reason; nothing moves.
--   4. Approve: the debit of exactly the requested amount, linked to the request; replay; refusals
--      (the wife herself, a member, another member's account, insufficient funds, no account)
--      leave the request pending; a second approval or a cancel afterwards is refused.
--   5. What is owed drops below a pending request: it closes as already repaid, nothing moves; the wife
--      cannot record directly.
--   6. Reversal of a repayment: credits the original account back, restores what is owed, refused
--      twice, refused for a reversal, a legacy row, an archived or a deleted account, and for the
--      wrong people; a corrected repayment afterwards.
--   7. A former member's record: reversing a payment reopens a settled record; replay; refused
--      twice, for a legacy payment, an archived account and after her waiver.
--   8. The husband's purge with a pending request and a reversal in history: the request is closed
--      with nothing moved, and the ledger invariant holds.
--   9. The wife's purge with a pending request and a reversal in history: the record keeps what was
--      owed with the reversal counted; her requests go with her ledger.
--  10. Privileges, row level security and pinned search_path.
--
-- Every budget's spent_amount (the whole table) is compared before and after each section.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.call(p_sub uuid, p_session text, p_sql text, p_role text DEFAULT 'authenticated')
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
    v_hint text;
    v_claims jsonb := jsonb_build_object('role', p_role);
BEGIN
    IF p_sub IS NOT NULL THEN
        v_claims := v_claims || jsonb_build_object('sub', p_sub);
    END IF;
    IF p_session IS NOT NULL THEN
        v_claims := v_claims || jsonb_build_object('session_id', p_session);
    END IF;
    PERFORM set_config('request.jwt.claims', v_claims::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text, text) TO PUBLIC;

CREATE FUNCTION pg_temp.svc(p_sql text)
RETURNS text
LANGUAGE sql
AS $$ SELECT pg_temp.call(NULL, NULL, p_sql, 'service_role') $$;

CREATE FUNCTION pg_temp.expect(p_label text, p_got text, p_want text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        RAISE EXCEPTION '%: got %, expected %', p_label, p_got, p_want;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e5800000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e58a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e58c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e58e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.k(int) TO PUBLIC;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, true);
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
    WHERE id = pg_temp.u(p_user);
END;
$$;

CREATE FUNCTION pg_temp.acct(p_n int, p_hh int, p_owner int, p_pool boolean, p_balance numeric, p_type text DEFAULT 'bank')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency)
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T58 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE p_type END, p_balance, p_pool, false, 'SAR');
END;
$$;

CREATE FUNCTION pg_temp.advance(p_hh int, p_wife int, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'T58 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me',
            'wife_reimbursable', pg_temp.u(p_wife));
END;
$$;

CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;
CREATE FUNCTION pg_temp.balances() RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id), '') FROM public.accounts a;
$$;
CREATE FUNCTION pg_temp.budgets() RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id), '') FROM public.budgets b;
$$;
CREATE FUNCTION pg_temp.counts() RETURNS text LANGUAGE sql AS $$
    SELECT (SELECT count(*) FROM public.transactions)::text || '/' || (SELECT count(*) FROM public.account_transfers)::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursements)::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursement_requests)::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursement_request_outcomes)::text
        || '/' || (SELECT count(*) FROM public.former_member_debt_events)::text;
$$;
CREATE FUNCTION pg_temp.balance_of(p_hh int, p_wife int, p_field text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.svc(format('SELECT (public.get_spouse_reimbursement_balance(%L, %L, %L)->>%L)',
                              pg_temp.h(p_hh), pg_temp.u(p_wife), pg_temp.u(p_wife), p_field));
$$;
CREATE FUNCTION pg_temp.owed(p_hh int, p_wife int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.balance_of(p_hh, p_wife, 'outstanding') $$;

CREATE TABLE pg_temp.snap (label text PRIMARY KEY, val text);
CREATE FUNCTION pg_temp.keep(p_label text, p_val text) RETURNS void LANGUAGE sql
AS $$ INSERT INTO pg_temp.snap VALUES (p_label, p_val) ON CONFLICT (label) DO UPDATE SET val = EXCLUDED.val $$;
CREATE FUNCTION pg_temp.kept(p_label text) RETURNS text LANGUAGE sql AS $$ SELECT val FROM pg_temp.snap WHERE label = p_label $$;
CREATE FUNCTION pg_temp.id(p_label text) RETURNS uuid LANGUAGE sql AS $$ SELECT val::uuid FROM pg_temp.snap WHERE label = p_label $$;

-- The calls, as user p_actor (authenticated). Account 0 = none.
CREATE FUNCTION pg_temp.req(p_actor int, p_hh int, p_amount text, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.request_spouse_reimbursement(%L, %s, %L, %L::uuid, NULL)::text',
               pg_temp.h(p_hh), p_amount, 'cash', pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.cancel(p_actor int, p_hh int, p_request uuid) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.cancel_spouse_reimbursement_request(%L, %L, NULL)::text', pg_temp.h(p_hh), p_request));
$$;
CREATE FUNCTION pg_temp.decline(p_actor int, p_hh int, p_request uuid, p_reason text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.decline_spouse_reimbursement_request(%L, %L, %L, NULL)::text', pg_temp.h(p_hh), p_request, p_reason));
$$;
CREATE FUNCTION pg_temp.approve(p_actor int, p_hh int, p_request uuid, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.approve_spouse_reimbursement_request(%L, %L, %L::uuid, %L::uuid, NULL)::text',
               pg_temp.h(p_hh), p_request,
               CASE WHEN p_account = 0 THEN NULL ELSE pg_temp.a(p_account) END, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.repay(p_actor int, p_hh int, p_wife int, p_amount text, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid)::text',
               pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'bank_transfer',
               CASE WHEN p_account = 0 THEN NULL ELSE pg_temp.a(p_account) END, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.rev(p_actor int, p_hh int, p_row uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.reverse_spouse_reimbursement(%L, %L, %L::uuid, NULL)::text', pg_temp.h(p_hh), p_row, pg_temp.k(p_key)));
$$;

CREATE FUNCTION pg_temp.debt(p_hh int) RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.former_member_debts WHERE household_id = pg_temp.h(p_hh) $$;
GRANT EXECUTE ON FUNCTION pg_temp.debt(int) TO PUBLIC;
CREATE FUNCTION pg_temp.fpay(p_actor int, p_hh int, p_amount text, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(p_hh), pg_temp.debt(p_hh), p_amount, 'cash', pg_temp.k(p_key), pg_temp.a(p_account)));
$$;
CREATE FUNCTION pg_temp.frev(p_actor int, p_hh int, p_event uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.reverse_former_member_debt_payment(%L, %L, %L, %L::uuid, NULL)::text',
               pg_temp.h(p_hh), pg_temp.debt(p_hh), p_event, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.state(p_hh int) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(d.original_amount::text || '/' || d.paid_amount::text || '/' || d.status || '/' || (d.closed_at IS NULL)::text, ',')
    FROM public.former_member_debts d WHERE d.household_id = pg_temp.h(p_hh);
$$;
CREATE FUNCTION pg_temp.outcome(p_request uuid) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE((SELECT o.outcome || '/' || COALESCE(o.reason, '-') FROM public.spouse_reimbursement_request_outcomes o
                     WHERE o.request_id = p_request), 'pending');
$$;

-- The purge machinery, as tests 54 and 56 drive it.
CREATE FUNCTION pg_temp.purge(p_user int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_sess text;
    v_id uuid;
    v_res text;
    v_prepared jsonb;
BEGIN
    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_user), now()) RETURNING id::text INTO v_sess;
    v_res := pg_temp.call(pg_temp.u(p_user), v_sess,
        format('SELECT public.request_account_deletion(%L, %L::jsonb, NULL, %L)::text', 'DELETE', '[]', 'en'));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'request for user % refused: %', p_user, v_res; END IF;
    SELECT id INTO v_id FROM public.account_deletion_requests WHERE user_id = pg_temp.u(p_user) AND status = 'scheduled';
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_id;
    v_res := pg_temp.svc('SELECT count(*)::text FROM public.claim_due_account_deletions(50, 30)');
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'claim failed: %', v_res; END IF;
    v_res := pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'prepare failed: %', v_res; END IF;
    v_prepared := v_res::jsonb;
    v_res := pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'mark storage failed: %', v_res; END IF;
    DELETE FROM auth.users WHERE id = pg_temp.u(p_user);
    v_res := pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'complete failed: %', v_res; END IF;
    RETURN v_prepared;
END;
$$;

CREATE FUNCTION pg_temp.scan(p_needle text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_t record;
    v_n bigint;
    v_found text := '';
BEGIN
    FOR v_t IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r' ORDER BY c.relname LOOP
        EXECUTE format('SELECT count(*) FROM public.%I x WHERE x::text ILIKE %L', v_t.relname, '%' || p_needle || '%') INTO v_n;
        IF v_n > 0 THEN
            v_found := v_found || v_t.relname || ':' || v_n || ' ';
        END IF;
    END LOOP;
    RETURN v_found;
END;
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) primary admin and provider, wife W(2), member K(3), co-admin C(4).
-- F2(2): primary admin A(5); the husband HB(6) is a co-admin and the provider; wife WB(7).
-- F3(3): husband H3(8) admin and provider, wife W3(9).
DO $$
DECLARE
    v_cycle text;
    v_month date := date_trunc('month', now())::date;
BEGIN
    SELECT cycle_key INTO v_cycle FROM public.get_saudi_cycle_for_timestamp(now(), 27);

    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't58-' || n || '@test.local', jsonb_build_object('display_name', 'T58 User ' || n)
    FROM generate_series(1, 9) AS n;
    UPDATE auth.users SET email = 't58-noor@test.local' WHERE id = pg_temp.u(2);
    UPDATE public.users SET display_name = 'Noor Uniquewife58' WHERE id = pg_temp.u(2);

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T58 H1', 'T58CODE000000001', 'family'),
        (pg_temp.h(2), 'T58 H2', 'T58CODE000000002', 'family'),
        (pg_temp.h(3), 'T58 H3', 'T58CODE000000003', 'family');
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'family_member');
    PERFORM pg_temp.join(4, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(5, 2, 'admin', 'family_member');
    PERFORM pg_temp.join(6, 2, 'admin', 'provider');
    PERFORM pg_temp.join(7, 2, 'member', 'spouse');
    PERFORM pg_temp.join(8, 3, 'admin', 'provider');
    PERFORM pg_temp.join(9, 3, 'member', 'spouse');
    UPDATE public.households SET owner_user_id = pg_temp.u(5), nafaqah_provider_user_id = pg_temp.u(6) WHERE id = pg_temp.h(2);

    PERFORM pg_temp.acct(1, 1, 1, true, 1000);           -- F1 pool
    PERFORM pg_temp.acct(2, 1, 2, false, 500);           -- W bank
    PERFORM pg_temp.acct(3, 1, 1, false, 1000);          -- H bank
    PERFORM pg_temp.acct(4, 1, 1, false, 200, 'cash');   -- H cash
    PERFORM pg_temp.acct(5, 1, 4, false, 300);           -- C bank
    PERFORM pg_temp.acct(6, 2, 5, true, 500);            -- F2 pool
    PERFORM pg_temp.acct(7, 2, 6, false, 400);           -- HB bank
    PERFORM pg_temp.acct(8, 2, 7, false, 100);           -- WB bank
    PERFORM pg_temp.acct(9, 3, 8, false, 1000);          -- H3 bank
    PERFORM pg_temp.acct(10, 3, 8, false, 100, 'cash');  -- H3 cash
    PERFORM pg_temp.acct(11, 3, 8, true, 300);           -- F3 pool
    PERFORM pg_temp.acct(12, 1, 1, false, 50, 'e_wallet'); -- H wallet, nearly empty
    PERFORM pg_temp.acct(13, 1, 1, false, 50, 'e_wallet'); -- H second wallet (deleted later)

    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key, account_id) VALUES
        ('e58b0000-0000-0000-0000-000000000001', pg_temp.h(1), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL),
        ('e58b0000-0000-0000-0000-000000000002', pg_temp.h(2), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL),
        ('e58b0000-0000-0000-0000-000000000003', pg_temp.h(3), v_month, 'OPEX-GROCERY', 900, v_cycle, pg_temp.a(9));

    PERFORM pg_temp.advance(1, 2, 400);
    PERFORM pg_temp.advance(2, 7, 300);
    PERFORM pg_temp.advance(3, 9, 500);
END $$;

SELECT pg_temp.keep('budgets', pg_temp.budgets());

-- 1. Requests ---------------------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_res jsonb;
    v_counts text;
BEGIN
    PERFORM pg_temp.expect('fixture: owed', pg_temp.owed(1, 2), '400.00');
    v_res := pg_temp.req(2, 1, '100', 1)::jsonb;
    PERFORM pg_temp.keep('r1', v_res ->> 'request_id');
    PERFORM pg_temp.expect('a pending request', (v_res ->> 'status') || '/' || (v_res ->> 'replayed') || '/' || (v_res ->> 'amount'),
        'pending/false/100.00');
    PERFORM pg_temp.expect('it does not reduce what is owed', pg_temp.owed(1, 2), '400.00');
    PERFORM pg_temp.expect('it shows as pending', pg_temp.balance_of(1, 2, 'pending_requested') || '/' || pg_temp.balance_of(1, 2, 'pending_count'),
        '100.00/1');
    PERFORM pg_temp.expect('it moves no money', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('it writes no repayment', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE household_id = pg_temp.h(1)), '0');

    v_counts := pg_temp.counts();
    v_res := pg_temp.req(2, 1, '100', 1)::jsonb;
    PERFORM pg_temp.expect('a double tap answers the first', (v_res ->> 'replayed') || '/' || (v_res ->> 'request_id') || '/' || (v_res ->> 'amount'),
        'true/' || pg_temp.kept('r1') || '/100.00');
    -- Another amount with the same key is not the same tap (review R1-04).
    PERFORM pg_temp.expect('the same key with another amount', pg_temp.req(2, 1, '77', 1), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('the replay writes nothing', pg_temp.counts(), v_counts);

    PERFORM pg_temp.expect('the husband does not ask', pg_temp.req(1, 1, '10', 2), 'ERR:forbidden');
    PERFORM pg_temp.expect('a member does not ask', pg_temp.req(3, 1, '10', 2), 'ERR:forbidden');
    PERFORM pg_temp.expect('a zero amount', pg_temp.req(2, 1, '0', 2), 'ERR:invalid_amount');
    PERFORM pg_temp.expect('a sub-halala amount', pg_temp.req(2, 1, '1.001', 2), 'ERR:invalid_amount');
    PERFORM pg_temp.expect('a request key is required',
        pg_temp.call(pg_temp.u(2), NULL, format('SELECT public.request_spouse_reimbursement(%L, 5, %L, NULL, NULL)::text', pg_temp.h(1), 'cash')),
        'ERR:request_key_required');

    v_res := pg_temp.req(2, 1, '250', 2)::jsonb;
    PERFORM pg_temp.keep('r2', v_res ->> 'request_id');
    PERFORM pg_temp.expect('pending 350 of 400', pg_temp.balance_of(1, 2, 'pending_requested'), '350.00');
    PERFORM pg_temp.expect('the pending total is capped by what is owed', pg_temp.req(2, 1, '50.01', 3), 'ERR:pending_exceeds_outstanding');
    v_res := pg_temp.req(2, 1, '50', 3)::jsonb;
    PERFORM pg_temp.keep('r3', v_res ->> 'request_id');
    PERFORM pg_temp.expect('up to exactly what is owed', pg_temp.balance_of(1, 2, 'pending_requested') || '/' || pg_temp.balance_of(1, 2, 'pending_count'),
        '400.00/3');
    PERFORM pg_temp.expect('nothing more', pg_temp.req(2, 1, '0.01', 4), 'ERR:pending_exceeds_outstanding');
    PERFORM pg_temp.expect('requests move no money', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('no budget moved (requests)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: a request is pending, moves nothing, is replayed once and is capped by what is owed.';
END $$;

-- 2 and 3. Cancel and decline -------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_res jsonb;
BEGIN
    PERFORM pg_temp.expect('the husband cannot cancel her request', pg_temp.cancel(1, 1, pg_temp.id('r2')), 'ERR:forbidden');
    PERFORM pg_temp.expect('another household', pg_temp.cancel(2, 2, pg_temp.id('r2')), 'ERR:42501');
    v_res := pg_temp.cancel(2, 1, pg_temp.id('r2'))::jsonb;
    PERFORM pg_temp.expect('she cancels', (v_res ->> 'outcome') || '/' || (v_res ->> 'replayed'), 'cancelled/false');
    PERFORM pg_temp.expect('cancelled', pg_temp.outcome(pg_temp.id('r2')), 'cancelled/-');
    PERFORM pg_temp.expect('cancel again is a replay', pg_temp.cancel(2, 1, pg_temp.id('r2'))::jsonb ->> 'replayed', 'true');
    PERFORM pg_temp.expect('pending after the cancel', pg_temp.balance_of(1, 2, 'pending_requested'), '150.00');
    PERFORM pg_temp.expect('an unknown request', pg_temp.cancel(2, 1, gen_random_uuid()), 'ERR:request_not_found');

    PERFORM pg_temp.expect('she cannot decline her own', pg_temp.decline(2, 1, pg_temp.id('r3'), NULL), 'ERR:forbidden');
    PERFORM pg_temp.expect('a member cannot decline', pg_temp.decline(3, 1, pg_temp.id('r3'), NULL), 'ERR:forbidden');
    v_res := pg_temp.decline(1, 1, pg_temp.id('r3'), '  Not received yet  ')::jsonb;
    PERFORM pg_temp.expect('the husband declines', (v_res ->> 'outcome') || '/' || (v_res ->> 'replayed'), 'declined/false');
    PERFORM pg_temp.expect('with the reason', pg_temp.outcome(pg_temp.id('r3')), 'declined/Not received yet');
    PERFORM pg_temp.expect('decline again is a replay', pg_temp.decline(1, 1, pg_temp.id('r3'), NULL)::jsonb ->> 'replayed', 'true');
    PERFORM pg_temp.expect('a declined request cannot be cancelled', pg_temp.cancel(2, 1, pg_temp.id('r3')), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('a co-admin cannot decline while the husband is there (R3-01)', pg_temp.decline(4, 1, pg_temp.id('r1'), NULL), 'ERR:forbidden');
    PERFORM pg_temp.expect('a cancelled request cannot be declined', pg_temp.decline(1, 1, pg_temp.id('r2'), NULL), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('a long reason', pg_temp.decline(1, 1, pg_temp.id('r1'), repeat('x', 201)), 'ERR:invalid_reason');
    PERFORM pg_temp.expect('nothing moved', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('what is owed is unchanged', pg_temp.owed(1, 2), '400.00');
    PERFORM pg_temp.expect('no budget moved (cancel, decline)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: she cancels her own pending request; the husband declines; nothing moves.';
END $$;

-- 4. Approve ------------------------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
    v_res jsonb;
    v_row record;
BEGIN
    PERFORM pg_temp.expect('she cannot approve her own', pg_temp.approve(2, 1, pg_temp.id('r1'), 2, 10), 'ERR:forbidden');
    PERFORM pg_temp.expect('a member cannot approve', pg_temp.approve(3, 1, pg_temp.id('r1'), 1, 10), 'ERR:forbidden');
    PERFORM pg_temp.expect('a co-admin, while the husband is there (R3-01)', pg_temp.approve(4, 1, pg_temp.id('r1'), 5, 10), 'ERR:forbidden');
    PERFORM pg_temp.expect('the husband with a co-admin''s account', pg_temp.approve(1, 1, pg_temp.id('r1'), 5, 10), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('insufficient funds', pg_temp.approve(1, 1, pg_temp.id('r1'), 12, 10), 'ERR:insufficient_funds');
    PERFORM pg_temp.expect('an account is required', pg_temp.approve(1, 1, pg_temp.id('r1'), 0, 10), 'ERR:account_required');
    PERFORM pg_temp.expect('another household''s account', pg_temp.approve(1, 1, pg_temp.id('r1'), 7, 10), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('refusals write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('the request stays pending', pg_temp.outcome(pg_temp.id('r1')), 'pending');

    v_res := pg_temp.approve(1, 1, pg_temp.id('r1'), 3, 10)::jsonb;
    PERFORM pg_temp.keep('p_r1', v_res ->> 'reimbursement_id');
    PERFORM pg_temp.expect('approved', (v_res ->> 'replayed') || '/' || (v_res ->> 'amount') || '/' || (v_res ->> 'outstanding_after'),
        'false/100.00/300.00');
    PERFORM pg_temp.expect('his bank down by exactly the requested amount', pg_temp.bal(3), '900.00');
    PERFORM pg_temp.expect('her account is never credited', pg_temp.bal(2), '500.00');
    PERFORM pg_temp.expect('approved, linked to the repayment',
        (SELECT o.outcome || '/' || (o.reimbursement_id = pg_temp.id('p_r1'))::text || '/' || (o.decided_by = pg_temp.u(1))::text
         FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = pg_temp.id('r1')), 'approved/true/true');
    SELECT r.amount, r.payment_method, r.kind, t.from_account_id, t.to_account_id, t.amount AS t_amount INTO v_row
    FROM public.spouse_reimbursements r JOIN public.account_transfers t ON t.id = r.transfer_id
    WHERE r.id = pg_temp.id('p_r1');
    PERFORM pg_temp.expect('one transfer out of his account, into nothing',
        v_row.amount::text || '/' || v_row.payment_method || '/' || v_row.kind || '/' || (v_row.from_account_id = pg_temp.a(3))::text
        || '/' || COALESCE(v_row.to_account_id::text, 'none') || '/' || v_row.t_amount::text,
        '100.00/cash/payment/true/none/100.00');
    PERFORM pg_temp.expect('pending after approval', pg_temp.balance_of(1, 2, 'pending_requested'), '0.00');

    v_bal := pg_temp.balances();
    v_counts := pg_temp.counts();
    v_res := pg_temp.approve(1, 1, pg_temp.id('r1'), 3, 10)::jsonb;
    PERFORM pg_temp.expect('a double tap answers the first', (v_res ->> 'replayed') || '/' || (v_res ->> 'reimbursement_id') || '/' || (v_res ->> 'account_id'),
        'true/' || pg_temp.kept('p_r1') || '/' || pg_temp.a(3)::text);
    -- From another account it is not the same tap (review R1-04).
    PERFORM pg_temp.expect('the same key from another account', pg_temp.approve(1, 1, pg_temp.id('r1'), 4, 10), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('a second approval', pg_temp.approve(1, 1, pg_temp.id('r1'), 1, 11), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('a cancel after approval', pg_temp.cancel(2, 1, pg_temp.id('r1')), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('a decline after approval', pg_temp.decline(1, 1, pg_temp.id('r1'), NULL), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('approving a cancelled request', pg_temp.approve(1, 1, pg_temp.id('r2'), 3, 12), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('the approval key is not a record key', pg_temp.repay(1, 1, 2, '5', 3, 10), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('replays and refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('replays and refusals write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('no budget moved (approve)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: approval debits exactly the requested amount from his account, once, linked to the request.';
END $$;

-- 5. What is owed dropped below a pending request; she cannot record directly ---------------------------
DO $$
DECLARE
    v_bal text;
    v_res jsonb;
BEGIN
    v_res := pg_temp.req(2, 1, '200', 13)::jsonb;
    PERFORM pg_temp.keep('r4', v_res ->> 'request_id');
    v_res := pg_temp.repay(1, 1, 2, '150', 3, 14)::jsonb;
    PERFORM pg_temp.keep('p_150', v_res ->> 'reimbursement_id');
    PERFORM pg_temp.expect('he paid 150 meanwhile', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(3), '150.00/750.00');
    -- What is owed (150) dropped below her pending 200 in the same transaction: the request no longer
    -- fits and closed as already repaid, with nothing moved (review R1-03).
    PERFORM pg_temp.expect('the request that no longer fits is closed', pg_temp.outcome(pg_temp.id('r4')), 'already_repaid/-');
    PERFORM pg_temp.expect('nothing pending above what is owed', pg_temp.balance_of(1, 2, 'pending_requested'), '0.00');
    v_bal := pg_temp.balances();
    PERFORM pg_temp.expect('approving it is refused', pg_temp.approve(1, 1, pg_temp.id('r4'), 3, 15), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('nothing moved', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('nor is it declined', pg_temp.decline(1, 1, pg_temp.id('r4'), ''), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('no new request beyond what is owed', pg_temp.req(2, 1, '150.01', 16), 'ERR:pending_exceeds_outstanding');
    v_res := pg_temp.req(2, 1, '10', 19)::jsonb;
    PERFORM pg_temp.keep('r5', v_res ->> 'request_id');
    PERFORM pg_temp.expect('he declines one', pg_temp.decline(1, 1, pg_temp.id('r5'), '')::jsonb ->> 'outcome', 'declined');
    PERFORM pg_temp.expect('an empty reason is none', pg_temp.outcome(pg_temp.id('r5')), 'declined/-');

    PERFORM pg_temp.expect('the wife cannot record directly', pg_temp.repay(2, 1, 2, '10', 2, 17), 'ERR:wife_must_request');
    PERFORM pg_temp.expect('nor with the pool', pg_temp.repay(2, 1, 2, '10', 1, 18), 'ERR:wife_must_request');
    PERFORM pg_temp.expect('nothing moved (wife)', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('owed 150', pg_temp.owed(1, 2), '150.00');
    PERFORM pg_temp.expect('no budget moved (re-check)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: a request that no longer fits what is owed closes as already repaid; the wife never records directly.';
END $$;

-- 6. Reversal of a repayment --------------------------------------------------------------------
DO $$
DECLARE
    v_bal text;
    v_counts text;
    v_res jsonb;
    v_row record;
    v_legacy uuid;
BEGIN
    v_res := pg_temp.rev(1, 1, pg_temp.id('p_150'), 20)::jsonb;
    PERFORM pg_temp.keep('rev_150', v_res ->> 'reimbursement_id');
    PERFORM pg_temp.expect('reversed', (v_res ->> 'replayed') || '/' || (v_res ->> 'amount') || '/' || (v_res ->> 'outstanding_after'),
        'false/150.00/300.00');
    PERFORM pg_temp.expect('his bank credited back in full', pg_temp.bal(3), '900.00');
    PERFORM pg_temp.expect('her account untouched', pg_temp.bal(2), '500.00');
    PERFORM pg_temp.expect('what is owed is restored', pg_temp.owed(1, 2), '300.00');
    PERFORM pg_temp.expect('the original stays', (SELECT kind || '/' || amount::text FROM public.spouse_reimbursements WHERE id = pg_temp.id('p_150')),
        'payment/150.00');
    SELECT r.kind, r.reverses_id, r.amount, t.from_account_id, t.to_account_id, t.amount AS t_amount INTO v_row
    FROM public.spouse_reimbursements r JOIN public.account_transfers t ON t.id = r.transfer_id
    WHERE r.id = pg_temp.id('rev_150');
    PERFORM pg_temp.expect('a reversal entry with a transfer back into his account',
        v_row.kind || '/' || (v_row.reverses_id = pg_temp.id('p_150'))::text || '/' || v_row.amount::text || '/'
        || COALESCE(v_row.from_account_id::text, 'none') || '/' || (v_row.to_account_id = pg_temp.a(3))::text || '/' || v_row.t_amount::text,
        'reversal/true/150.00/none/true/150.00');
    PERFORM pg_temp.expect('reimbursed is net of the reversal', pg_temp.balance_of(1, 2, 'reimbursed'), '100.00');

    v_bal := pg_temp.balances();
    v_counts := pg_temp.counts();
    PERFORM pg_temp.expect('a double tap answers the first', pg_temp.rev(1, 1, pg_temp.id('p_150'), 20)::jsonb ->> 'reimbursement_id', pg_temp.kept('rev_150'));
    PERFORM pg_temp.expect('reversed twice', pg_temp.rev(1, 1, pg_temp.id('p_150'), 21), 'ERR:already_reversed');
    PERFORM pg_temp.expect('a reversal is not reversed', pg_temp.rev(1, 1, pg_temp.id('rev_150'), 22), 'ERR:not_reversible');
    PERFORM pg_temp.expect('the wife does not reverse', pg_temp.rev(2, 1, pg_temp.id('p_r1'), 23), 'ERR:forbidden');
    -- Only her ledger's manager reverses (review R3B-06), and then from the account it left.
    PERFORM pg_temp.expect('a member does not reverse another''s', pg_temp.rev(3, 1, pg_temp.id('p_r1'), 23), 'ERR:forbidden');
    PERFORM pg_temp.expect('a co-admin does not credit his personal account', pg_temp.rev(4, 1, pg_temp.id('p_r1'), 23), 'ERR:forbidden');
    PERFORM pg_temp.expect('an unknown repayment', pg_temp.rev(1, 1, gen_random_uuid(), 23), 'ERR:reimbursement_not_found');
    PERFORM pg_temp.expect('another household''s repayment', pg_temp.rev(6, 2, pg_temp.id('p_r1'), 23), 'ERR:reimbursement_not_found');
    PERFORM pg_temp.expect('a request key is required',
        pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.reverse_spouse_reimbursement(%L, %L, NULL, NULL)::text', pg_temp.h(1), pg_temp.id('p_r1'))),
        'ERR:request_key_required');
    PERFORM pg_temp.expect('refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('refusals write nothing', pg_temp.counts(), v_counts);

    -- The corrected repayment.
    v_res := pg_temp.repay(1, 1, 2, '120', 3, 24)::jsonb;
    PERFORM pg_temp.expect('corrected', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(3), '180.00/780.00');

    -- A pool payment by the husband (an admin), reversed by him: back into the pool. A co-admin does
    -- not reverse it while he is there (review R3-01).
    v_res := pg_temp.repay(1, 1, 2, '30', 1, 25)::jsonb;
    PERFORM pg_temp.expect('pool paid', pg_temp.bal(1), '970.00');
    PERFORM pg_temp.expect('a co-admin does not reverse the pool''s repayment while the husband is there',
        pg_temp.rev(4, 1, (v_res ->> 'reimbursement_id')::uuid, 39), 'ERR:forbidden');
    v_res := pg_temp.rev(1, 1, (v_res ->> 'reimbursement_id')::uuid, 26)::jsonb;
    PERFORM pg_temp.expect('pool credited back', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(1), '180.00/1000.00');

    -- An archived account, then a deleted one.
    v_res := pg_temp.repay(1, 1, 2, '20', 4, 27)::jsonb;
    PERFORM pg_temp.keep('p_cash', v_res ->> 'reimbursement_id');
    UPDATE public.accounts SET is_archived = true WHERE id = pg_temp.a(4);
    v_res := pg_temp.repay(1, 1, 2, '10', 13, 28)::jsonb;
    PERFORM pg_temp.keep('p_wallet', v_res ->> 'reimbursement_id');
    -- He cannot delete it (review R3-05: archive instead); the service path still can, as the purge does.
    PERFORM pg_temp.expect('he cannot delete that wallet',
        pg_temp.call(pg_temp.u(1), NULL, format('DELETE FROM public.accounts WHERE id = %L RETURNING id::text', pg_temp.a(13))), 'ERR:account_has_repayments');
    DELETE FROM public.accounts WHERE id = pg_temp.a(13);
    -- A repayment from before this release: amount only, no transfer.
    INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, paid_by_user_id, amount, payment_method, recorded_by)
    VALUES (pg_temp.h(1), pg_temp.u(2), pg_temp.u(1), 5, 'cash', pg_temp.u(1)) RETURNING id INTO v_legacy;
    v_bal := pg_temp.balances();
    v_counts := pg_temp.counts();
    PERFORM pg_temp.expect('an archived account', pg_temp.rev(1, 1, pg_temp.id('p_cash'), 29), 'ERR:reversal_account_unavailable');
    PERFORM pg_temp.expect('a deleted account', pg_temp.rev(1, 1, pg_temp.id('p_wallet'), 30), 'ERR:reversal_account_unavailable');
    PERFORM pg_temp.expect('a legacy row', pg_temp.rev(1, 1, v_legacy, 31), 'ERR:reversal_not_tracked');
    PERFORM pg_temp.expect('refused reversals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('refused reversals write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('owed: 400 - 100 - 150 + 150 - 120 - 30 + 30 - 20 - 10 - 5', pg_temp.owed(1, 2), '145.00');
    PERFORM pg_temp.expect('reimbursed: net', pg_temp.balance_of(1, 2, 'reimbursed'), '255.00');
    PERFORM pg_temp.expect('the guard counts reversals: an advance can drop to what is repaid net',
        pg_temp.call(pg_temp.u(2), NULL, format('UPDATE public.transactions SET amount = 255 WHERE household_id = %L AND nafaqah_spouse_id = %L RETURNING amount::text',
            pg_temp.h(1), pg_temp.u(2))), '255.00');
    PERFORM pg_temp.expect('but not below', pg_temp.call(pg_temp.u(2), NULL, format('UPDATE public.transactions SET amount = 254.99 WHERE household_id = %L AND nafaqah_spouse_id = %L RETURNING amount::text',
            pg_temp.h(1), pg_temp.u(2))), 'ERR:ledger_would_be_overpaid');
    UPDATE public.transactions SET amount = 400 WHERE household_id = pg_temp.h(1) AND nafaqah_spouse_id = pg_temp.u(2);
    -- The advance is back at 400, so its budget is where it was: no repayment or reversal moved one.
    PERFORM pg_temp.expect('no budget moved (reversals)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: a reversal credits the original account back once and restores what is owed; legacy, archived and deleted are refused.';
END $$;

-- 7. A former member's record ---------------------------------------------------------------------
DO $$
DECLARE
    v_bal text;
    v_counts text;
    v_res jsonb;
    v_ev record;
    v_legacy uuid;
BEGIN
    PERFORM pg_temp.purge(9);
    PERFORM pg_temp.expect('her record', pg_temp.state(3), '500.00/0.00/open/true');
    v_res := pg_temp.fpay(8, 3, '200', 9, 30)::jsonb;
    PERFORM pg_temp.keep('e200', v_res ->> 'event_id');
    v_res := pg_temp.fpay(8, 3, '300', 9, 31)::jsonb;
    PERFORM pg_temp.keep('e300', v_res ->> 'event_id');
    PERFORM pg_temp.expect('settled', pg_temp.state(3) || ' ' || pg_temp.bal(9), '500.00/500.00/settled/false 500.00');

    v_res := pg_temp.frev(8, 3, pg_temp.id('e300'), 32)::jsonb;
    PERFORM pg_temp.keep('ev_rev', v_res ->> 'event_id');
    PERFORM pg_temp.expect('the reversal reopens it', (v_res ->> 'status') || '/' || (v_res ->> 'remaining') || '/' || (v_res ->> 'replayed'),
        'open/300.00/false');
    PERFORM pg_temp.expect('reopened, what remains restored', pg_temp.state(3), '500.00/200.00/open/true');
    PERFORM pg_temp.expect('his bank credited back', pg_temp.bal(9), '800.00');
    SELECT e.kind, e.amount, e.remaining_after, e.reverses_event_id, t.from_account_id, t.to_account_id INTO v_ev
    FROM public.former_member_debt_events e JOIN public.account_transfers t ON t.id = e.transfer_id
    WHERE e.id = pg_temp.id('ev_rev');
    PERFORM pg_temp.expect('a reversal event with a transfer back',
        v_ev.kind || '/' || v_ev.amount::text || '/' || v_ev.remaining_after::text || '/' || (v_ev.reverses_event_id = pg_temp.id('e300'))::text
        || '/' || COALESCE(v_ev.from_account_id::text, 'none') || '/' || (v_ev.to_account_id = pg_temp.a(9))::text,
        'reversal/300.00/300.00/true/none/true');

    v_bal := pg_temp.balances();
    v_counts := pg_temp.counts();
    PERFORM pg_temp.expect('a double tap', pg_temp.frev(8, 3, pg_temp.id('e300'), 32)::jsonb ->> 'replayed', 'true');
    PERFORM pg_temp.expect('reversed twice', pg_temp.frev(8, 3, pg_temp.id('e300'), 33), 'ERR:already_reversed');
    PERFORM pg_temp.expect('a reversal is not reversed', pg_temp.frev(8, 3, pg_temp.id('ev_rev'), 33), 'ERR:not_reversible');
    PERFORM pg_temp.expect('an unknown payment', pg_temp.frev(8, 3, gen_random_uuid(), 33), 'ERR:payment_not_found');
    PERFORM pg_temp.expect('another household''s manager', pg_temp.call(pg_temp.u(1), NULL,
        format('SELECT public.reverse_former_member_debt_payment(%L, %L, %L, %L::uuid, NULL)::text', pg_temp.h(1), pg_temp.debt(3), pg_temp.id('e200'), pg_temp.k(33))),
        'ERR:debt_not_found');
    PERFORM pg_temp.expect('replays and refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('replays and refusals write nothing', pg_temp.counts(), v_counts);

    -- A payment from before this release: amount only.
    UPDATE public.former_member_debts SET paid_amount = paid_amount + 10 WHERE id = pg_temp.debt(3);
    INSERT INTO public.former_member_debt_events (debt_id, kind, amount, payment_method, remaining_after, recorded_by, request_key)
    VALUES (pg_temp.debt(3), 'payment', 10, 'cash', 290, pg_temp.u(8), gen_random_uuid()) RETURNING id INTO v_legacy;
    PERFORM pg_temp.expect('a legacy payment', pg_temp.frev(8, 3, v_legacy, 34), 'ERR:reversal_not_tracked');

    v_res := pg_temp.fpay(8, 3, '50', 10, 35)::jsonb;
    PERFORM pg_temp.keep('e_cash', v_res ->> 'event_id');
    UPDATE public.accounts SET is_archived = true WHERE id = pg_temp.a(10);
    PERFORM pg_temp.expect('an archived account', pg_temp.frev(8, 3, pg_temp.id('e_cash'), 36), 'ERR:reversal_account_unavailable');

    -- Her waiver after the payment: the payment is no longer reversed.
    v_res := pg_temp.call(pg_temp.u(8), NULL, format('SELECT public.waive_former_member_debt(%L, %L, %L)::text', pg_temp.h(3), pg_temp.debt(3), pg_temp.k(37)))::jsonb;
    PERFORM pg_temp.expect('waived', (v_res ->> 'status') || '/' || (v_res ->> 'waived_amount'), 'waived/240.00');
    v_bal := pg_temp.balances();
    PERFORM pg_temp.expect('after her waiver', pg_temp.frev(8, 3, pg_temp.id('e200'), 38), 'ERR:reversal_after_waiver');
    PERFORM pg_temp.expect('nothing moved after the waiver', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('the record as it was', pg_temp.state(3), '500.00/260.00/waived/false');
    PERFORM pg_temp.expect('no budget moved (former member)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: reversing a former member payment reopens the record; legacy, archived and waived are refused.';
END $$;

-- 8. The husband's purge with a pending request and a reversal in history ---------------------------
DO $$
DECLARE
    v_res jsonb;
    v_keep text;
    v_request uuid;
BEGIN
    v_request := (pg_temp.req(7, 2, '50', 40)::jsonb ->> 'request_id')::uuid;
    v_res := pg_temp.repay(6, 2, 7, '100', 7, 41)::jsonb;
    PERFORM pg_temp.rev(6, 2, (v_res ->> 'reimbursement_id')::uuid, 42);
    PERFORM pg_temp.repay(6, 2, 7, '60', 7, 43);
    PERFORM pg_temp.expect('fixture: his bank and what is owed', pg_temp.bal(7) || '/' || pg_temp.owed(2, 7), '340.00/240.00');

    v_keep := regexp_replace(pg_temp.balances(), pg_temp.a(7)::text || '=[0-9.]+,?', '');
    v_res := pg_temp.purge(6);
    PERFORM pg_temp.expect('the purge completes (its ledger invariant holds)', v_res ->> 'prepared', 'true');
    PERFORM pg_temp.expect('the pending request is closed', pg_temp.outcome(v_request), 'closed/-');
    PERFORM pg_temp.expect('closed by nobody, with nothing moved',
        (SELECT (decided_by IS NULL)::text || '/' || (reimbursement_id IS NULL)::text FROM public.spouse_reimbursement_request_outcomes WHERE request_id = v_request),
        'true/true');
    PERFORM pg_temp.expect('every other balance is equal', rtrim(pg_temp.balances(), ','), rtrim(v_keep, ','));
    PERFORM pg_temp.expect('what is owed to her is unchanged', pg_temp.owed(2, 7), '240.00');
    PERFORM pg_temp.expect('she cannot cancel a closed request', pg_temp.cancel(7, 2, v_request), 'ERR:request_not_pending');
    PERFORM pg_temp.expect('no budget moved (his purge)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: the husband''s purge closes her pending request, moves nothing, and keeps its invariant.';
END $$;

-- 9. The wife's purge with a pending request and a reversal in history ------------------------------
DO $$
DECLARE
    v_res jsonb;
    v_keep text;
BEGIN
    PERFORM pg_temp.expect('a pending request of hers', pg_temp.req(2, 1, '10', 50)::jsonb ->> 'status', 'pending');
    v_keep := regexp_replace(pg_temp.balances(), pg_temp.a(2)::text || '=[0-9.]+,?', '');
    v_res := pg_temp.purge(2);
    PERFORM pg_temp.expect('the purge completes (its ledger invariant holds)', v_res ->> 'prepared', 'true');
    PERFORM pg_temp.expect('the record keeps what was owed, with the reversal counted', pg_temp.state(1), '145.00/0.00/open/true');
    PERFORM pg_temp.expect('every other balance is equal', rtrim(pg_temp.balances(), ','), rtrim(v_keep, ','));
    PERFORM pg_temp.expect('her requests went with her ledger',
        (SELECT count(*)::text FROM public.spouse_reimbursement_requests WHERE household_id = pg_temp.h(1)), '0');
    PERFORM pg_temp.expect('her id anywhere', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.expect('her email anywhere', pg_temp.scan('t58-noor@test.local'), '');
    PERFORM pg_temp.expect('her name anywhere', pg_temp.scan('Noor Uniquewife58'), '');
    PERFORM pg_temp.expect('no budget moved (her purge)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: the wife''s purge keeps what was owed net of reversals; her requests go with her.';
END $$;

-- 10. Privileges ---------------------------------------------------------------------------------
DO $$
DECLARE
    v_sig text;
    v_tbl text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'request_spouse_reimbursement(uuid, numeric, text, uuid, uuid)',
        'cancel_spouse_reimbursement_request(uuid, uuid, uuid)',
        'decline_spouse_reimbursement_request(uuid, uuid, text, uuid)',
        'approve_spouse_reimbursement_request(uuid, uuid, uuid, uuid, uuid)',
        'reverse_spouse_reimbursement(uuid, uuid, uuid, uuid)',
        'reverse_former_member_debt_payment(uuid, uuid, uuid, uuid, uuid)'
    ] LOOP
        IF has_function_privilege('anon', 'public.' || v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: anon can execute %', v_sig;
        END IF;
        IF NOT has_function_privilege('authenticated', 'public.' || v_sig, 'EXECUTE')
           OR NOT has_function_privilege('service_role', 'public.' || v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: % not executable by its callers', v_sig;
        END IF;
    END LOOP;
    FOREACH v_sig IN ARRAY ARRAY[
        'nafaqah_repayment_lock_account(uuid, uuid, uuid)',
        'nafaqah_repayment_debit(uuid, uuid, uuid, numeric, text)',
        'nafaqah_repayment_credit(uuid, uuid, uuid, numeric, text)',
        'nafaqah_repay_from_account(uuid, uuid, uuid, numeric, text, text, uuid, uuid, uuid)',
        'nafaqah_net_repaid(uuid, uuid)',
        'nafaqah_outstanding(uuid, uuid)'
    ] LOOP
        IF has_function_privilege('anon', 'public.' || v_sig, 'EXECUTE')
           OR has_function_privilege('authenticated', 'public.' || v_sig, 'EXECUTE')
           OR has_function_privilege('service_role', 'public.' || v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client can execute the internal %', v_sig;
        END IF;
    END LOOP;
    FOREACH v_tbl IN ARRAY ARRAY['spouse_reimbursement_requests', 'spouse_reimbursement_request_outcomes'] LOOP
        IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.' || v_tbl)::regclass) THEN
            RAISE EXCEPTION 'RLS off on %', v_tbl;
        END IF;
        IF has_table_privilege('anon', 'public.' || v_tbl, 'SELECT')
           OR has_table_privilege('authenticated', 'public.' || v_tbl, 'INSERT')
           OR has_table_privilege('authenticated', 'public.' || v_tbl, 'UPDATE')
           OR has_table_privilege('authenticated', 'public.' || v_tbl, 'DELETE')
           OR NOT has_table_privilege('authenticated', 'public.' || v_tbl, 'SELECT') THEN
            RAISE EXCEPTION 'privileges on % are not read-only for clients', v_tbl;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
               AND p.proname IN ('request_spouse_reimbursement', 'cancel_spouse_reimbursement_request', 'decline_spouse_reimbursement_request',
                                 'approve_spouse_reimbursement_request', 'reverse_spouse_reimbursement', 'reverse_former_member_debt_payment',
                                 'nafaqah_repayment_lock_account', 'nafaqah_repayment_debit', 'nafaqah_repayment_credit',
                                 'nafaqah_repay_from_account', 'nafaqah_net_repaid')
               AND (NOT p.prosecdef OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))) THEN
        RAISE EXCEPTION 'a request or reversal function without SECURITY DEFINER and a fixed search_path';
    END IF;
    -- Her husband gone (purged in section 8), an admin who is not a wife reads the household's
    -- requests (review R3-01); another household reads none.
    PERFORM pg_temp.expect('the admin reads them, her husband gone',
        pg_temp.call(pg_temp.u(5), NULL, 'SELECT count(*)::text FROM public.spouse_reimbursement_requests'),
        (SELECT count(*)::text FROM public.spouse_reimbursement_requests WHERE household_id = pg_temp.h(2)));
    PERFORM pg_temp.expect('and their outcomes',
        pg_temp.call(pg_temp.u(5), NULL, 'SELECT count(*)::text FROM public.spouse_reimbursement_request_outcomes'),
        (SELECT count(*)::text FROM public.spouse_reimbursement_request_outcomes o
         JOIN public.spouse_reimbursement_requests r ON r.id = o.request_id WHERE r.household_id = pg_temp.h(2)));
    PERFORM pg_temp.expect('another household reads none',
        pg_temp.call(pg_temp.u(8), NULL, 'SELECT count(*)::text FROM public.spouse_reimbursement_requests'), '0');
    RAISE NOTICE 'PASSED: privileges, row level security and search_path of requests and reversals.';
END $$;

ROLLBACK;
