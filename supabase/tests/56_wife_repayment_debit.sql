-- ============================================================================
-- Test 56: every repayment to the wife debits the account he picks, and only that
--
-- Migration: 20261105001300_wife_repayment_debit.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Owner decisions 2026-11-06: every repayment is tracked. It leaves an account he picks (a cash
-- payment leaves his Cash account) as one account_transfers row to no account: her account is
-- never credited. No budget moves: her expense counted when she recorded it. There is no
-- "not tracked" path any more, and a call without an account (the old signatures, or the new one
-- with none) is refused with app_update_required. The same holds for the payment of a former
-- member's record; her waiver moves nothing.
--
-- Verifies:
--   1. A repayment from his account: his balance goes down by exactly the amount, none of hers
--      moves, one account_transfers row to no account linked from the ledger row; no budget, no
--      transaction, and her allowance untouched. Cash comes out of his Cash account.
--   2. A double tap (same request key) records once; a key used for another wife is refused.
--   3. No untracked path: the old signatures and a missing account are refused with
--      app_update_required and write nothing; only the money-moving functions write the ledgers.
--   4. Refused, with nothing moved: overpayment, an account of another household, archived or not
--      in SAR, another member's personal account, a shared pool for a non-admin, the wife herself
--      (with her account or the pool), a member, insufficient funds, no request key.
--   5. A shared pool by the husband when he is an admin; a provider who is not an admin pays from
--      his own account; an admin does not while the husband is there (review R3-01); the API path
--      (service role, p_actor_user_id).
--   6. Append-only: no client deletes or edits the ledger, the transfers, the requests or outcomes,
--      nor deletes the account a repayment left (review R3-05: archived instead).
--   7. The purge of the wife with repayments in her history: the ledger invariant holds, the
--      record holds what remained.
--   8. A former member's record: a payment debits his account (only his side), a replay once, the
--      old signature and a missing account refused, refusals move nothing, the waiver moves nothing.
--   9. Privileges and pinned search_path.
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
AS $$ SELECT ('e5600000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e56a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e56c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e56e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.k(int) TO PUBLIC;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, true);
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
    WHERE id = pg_temp.u(p_user);
END;
$$;

CREATE FUNCTION pg_temp.acct(p_n int, p_hh int, p_owner int, p_pool boolean, p_balance numeric,
                             p_type text DEFAULT 'bank', p_archived boolean DEFAULT false, p_currency text DEFAULT 'SAR')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency)
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T56 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE p_type END, p_balance, p_pool, p_archived, p_currency);
END;
$$;

CREATE FUNCTION pg_temp.advance(p_hh int, p_wife int, p_amount numeric, p_account int DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id, account_id)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'T56 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me',
            'wife_reimbursable', pg_temp.u(p_wife), CASE WHEN p_account IS NULL THEN NULL ELSE pg_temp.a(p_account) END);
END;
$$;

-- A repayment through the 8-argument signature, as user p_actor (authenticated). p_account 0 = none.
CREATE FUNCTION pg_temp.repay(p_actor int, p_hh int, p_wife int, p_amount text, p_account int, p_key int, p_method text DEFAULT 'bank_transfer')
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid)::text',
               pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, p_method,
               CASE WHEN p_account = 0 THEN NULL ELSE pg_temp.a(p_account) END,
               CASE WHEN p_key = 0 THEN NULL ELSE pg_temp.k(p_key) END));
$$;

CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;

-- Every account balance and every budget's spend in the database.
CREATE FUNCTION pg_temp.balances() RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id), '') FROM public.accounts a;
$$;
CREATE FUNCTION pg_temp.budgets() RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id), '') FROM public.budgets b;
$$;
CREATE FUNCTION pg_temp.counts() RETURNS text LANGUAGE sql AS $$
    SELECT (SELECT count(*) FROM public.transactions)::text || '/' || (SELECT count(*) FROM public.account_transfers)::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursements)::text || '/' || (SELECT count(*) FROM public.former_member_debt_events)::text;
$$;

CREATE FUNCTION pg_temp.outstanding(p_hh int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.svc(format('SELECT (public.get_spouse_reimbursement_balance(%L, %L, %L)->>''outstanding'')',
                              pg_temp.h(p_hh), pg_temp.u(p_wife), pg_temp.u(p_wife)));
$$;

CREATE TABLE pg_temp.snap (label text PRIMARY KEY, val text);
CREATE FUNCTION pg_temp.keep(p_label text, p_val text) RETURNS void LANGUAGE sql
AS $$ INSERT INTO pg_temp.snap VALUES (p_label, p_val) ON CONFLICT (label) DO UPDATE SET val = EXCLUDED.val $$;
CREATE FUNCTION pg_temp.kept(p_label text) RETURNS text LANGUAGE sql AS $$ SELECT val FROM pg_temp.snap WHERE label = p_label $$;

-- The purge machinery, as test 54 drives it.
CREATE FUNCTION pg_temp.request(p_user int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_sess text;
    v_res text;
BEGIN
    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_user), now()) RETURNING id::text INTO v_sess;
    v_res := pg_temp.call(pg_temp.u(p_user), v_sess,
        format('SELECT public.request_account_deletion(%L, %L::jsonb, NULL, %L)::text', 'DELETE', '[]', 'en'));
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'request for user % refused: %', p_user, v_res;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.req_id(p_user int) RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.account_deletion_requests WHERE user_id = pg_temp.u(p_user) AND status IN ('scheduled', 'processing', 'failed') $$;

CREATE FUNCTION pg_temp.purge(p_user int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid := pg_temp.req_id(p_user);
    v_res text;
    v_prepared jsonb;
BEGIN
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

CREATE FUNCTION pg_temp.debt(p_hh int) RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.former_member_debts WHERE household_id = pg_temp.h(p_hh) $$;
GRANT EXECUTE ON FUNCTION pg_temp.debt(int) TO PUBLIC;

-- A former member payment through the 7-argument signature. p_account 0 = none.
CREATE FUNCTION pg_temp.fpay(p_actor int, p_hh int, p_amount text, p_account int, p_key int, p_method text DEFAULT 'bank_transfer')
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(p_hh), pg_temp.debt(p_hh), p_amount, p_method,
               CASE WHEN p_key = 0 THEN NULL ELSE pg_temp.k(p_key) END,
               CASE WHEN p_account = 0 THEN NULL ELSE pg_temp.a(p_account) END));
$$;

CREATE FUNCTION pg_temp.state(p_hh int) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(d.original_amount::text || '/' || d.paid_amount::text || '/' || d.status, ',')
    FROM public.former_member_debts d WHERE d.household_id = pg_temp.h(p_hh);
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) primary admin and provider, wife W(2), member K(3), co-admin C(4), second wife V(10).
-- F2(2): another family: husband O(5), wife Q(6).
-- F3(3): admin A(7); the provider PM(8) is a plain member; wife Z(9) has no account.
DO $$
DECLARE
    v_cycle text;
    v_month date := date_trunc('month', now())::date;
BEGIN
    SELECT cycle_key INTO v_cycle FROM public.get_saudi_cycle_for_timestamp(now(), 27);

    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't56-' || n || '@test.local', jsonb_build_object('display_name', 'T56 User ' || n)
    FROM generate_series(1, 10) AS n;
    UPDATE auth.users SET email = 't56-warda@test.local' WHERE id = pg_temp.u(2);
    UPDATE public.users SET display_name = 'Warda Uniquewife56' WHERE id = pg_temp.u(2);

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T56 H1', 'T56CODE000000001', 'family'),
        (pg_temp.h(2), 'T56 H2', 'T56CODE000000002', 'family'),
        (pg_temp.h(3), 'T56 H3', 'T56CODE000000003', 'family');
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'family_member');
    PERFORM pg_temp.join(4, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(10, 1, 'member', 'spouse');
    PERFORM pg_temp.join(5, 2, 'admin', 'provider');
    PERFORM pg_temp.join(6, 2, 'member', 'spouse');
    PERFORM pg_temp.join(7, 3, 'admin', 'family_member');
    PERFORM pg_temp.join(8, 3, 'member', 'provider');
    PERFORM pg_temp.join(9, 3, 'member', 'spouse');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(8) WHERE id = pg_temp.h(3);

    PERFORM pg_temp.acct(1, 1, 1, true, 1000);                        -- F1 pool
    PERFORM pg_temp.acct(2, 1, 2, false, 500);                        -- W bank
    PERFORM pg_temp.acct(3, 1, 1, false, 300);                        -- H bank
    PERFORM pg_temp.acct(4, 2, 5, false, 400);                        -- O bank (F2)
    PERFORM pg_temp.acct(5, 1, 1, false, 50, 'cash');                 -- H cash
    PERFORM pg_temp.acct(6, 1, 2, false, 20, 'cash');                 -- W cash
    PERFORM pg_temp.acct(7, 1, 3, false, 100);                        -- K bank
    PERFORM pg_temp.acct(8, 1, 4, false, 200);                        -- C bank
    PERFORM pg_temp.acct(9, 1, 1, false, 900, 'bank', true);          -- H archived
    PERFORM pg_temp.acct(10, 1, 1, false, 900, 'bank', false, 'USD'); -- H in dollars
    PERFORM pg_temp.acct(11, 3, 7, true, 600);                        -- F3 pool
    PERFORM pg_temp.acct(12, 3, 8, false, 250);                       -- PM bank
    PERFORM pg_temp.acct(13, 1, 2, false, 70, 'e_wallet');            -- W wallet
    PERFORM pg_temp.acct(14, 2, 6, false, 30);                        -- Q bank (F2)
    PERFORM pg_temp.acct(15, 1, 1, false, 5, 'e_wallet');             -- H wallet, nearly empty

    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key, account_id) VALUES
        ('e56b0000-0000-0000-0000-000000000001', pg_temp.h(1), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL),
        ('e56b0000-0000-0000-0000-000000000002', pg_temp.h(1), v_month, 'OPEX-DINING', 300, v_cycle, pg_temp.a(3)),
        ('e56b0000-0000-0000-0000-000000000003', pg_temp.h(3), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL);

    -- W: 300 unlinked plus 100 from her bank (500 -> 400): 400 owed. V: 40. Z: 200. Q: 50.
    PERFORM pg_temp.advance(1, 2, 300);
    PERFORM pg_temp.advance(1, 2, 100, 2);
    PERFORM pg_temp.advance(1, 10, 40);
    PERFORM pg_temp.advance(3, 9, 200);
    PERFORM pg_temp.advance(2, 6, 50);
    -- Her allowance (rule 3): 15 spent this cycle, which no repayment may touch.
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(1), pg_temp.u(2), 15, 'T56 Perfume', 'OPEX-SHOPPING', now(), 'manual', 'me', 'wife_personal', pg_temp.u(2));
END $$;

SELECT pg_temp.keep('budgets', pg_temp.budgets());

-- Her accounts, as they are now: no repayment may ever change them.
CREATE FUNCTION pg_temp.hers() RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.bal(2) || '/' || pg_temp.bal(6) || '/' || pg_temp.bal(13) $$;
SELECT pg_temp.keep('hers', pg_temp.hers());

-- 1. Out of his account, into none ------------------------------------------------------------
DO $$
DECLARE
    v_tx bigint := (SELECT count(*) FROM public.transactions);
    v_res jsonb;
    v_transfer record;
BEGIN
    PERFORM pg_temp.expect('fixture: owed', pg_temp.outstanding(1, 2), '400.00');
    PERFORM pg_temp.expect('fixture: her accounts', pg_temp.kept('hers'), '400.00/20.00/70.00');
    PERFORM pg_temp.expect('fixture: the budget counts her advances',
        (SELECT spent_amount::text FROM public.budgets WHERE id = 'e56b0000-0000-0000-0000-000000000001'), '440.00');

    v_res := pg_temp.repay(1, 1, 2, '100', 3, 1)::jsonb;
    PERFORM pg_temp.expect('recorded', (v_res ->> 'replayed') || '/' || (v_res ->> 'outstanding_after') || '/' || (v_res ->> 'account_id'),
        'false/300.00/' || pg_temp.a(3)::text);
    PERFORM pg_temp.expect('the answer says nothing of her account', COALESCE(v_res ->> 'wife_account_credited', 'absent'), 'absent');
    PERFORM pg_temp.expect('his bank down by exactly 100', pg_temp.bal(3), '200.00');
    PERFORM pg_temp.expect('none of her accounts moved', pg_temp.hers(), pg_temp.kept('hers'));
    PERFORM pg_temp.expect('owed after', pg_temp.outstanding(1, 2), '300.00');

    SELECT t.* INTO v_transfer FROM public.account_transfers t
    JOIN public.spouse_reimbursements r ON r.transfer_id = t.id
    WHERE r.id = (v_res ->> 'reimbursement_id')::uuid;
    PERFORM pg_temp.expect('one linked transfer, to no account',
        v_transfer.from_account_id::text || '>' || COALESCE(v_transfer.to_account_id::text, 'none') || ':' || v_transfer.amount::text || ':' || v_transfer.fee::text
        || ':' || (v_transfer.user_id = pg_temp.u(1))::text || ':' || (v_transfer.household_id = pg_temp.h(1))::text,
        pg_temp.a(3)::text || '>none:100.00:0.00:true:true');
    PERFORM pg_temp.expect('the request key is kept',
        (SELECT request_key::text || '/' || kind FROM public.spouse_reimbursements WHERE id = (v_res ->> 'reimbursement_id')::uuid), pg_temp.k(1)::text || '/payment');
    PERFORM pg_temp.expect('no transaction written', (SELECT count(*) FROM public.transactions)::text, v_tx::text);
    PERFORM pg_temp.expect('no budget moved', pg_temp.budgets(), pg_temp.kept('budgets'));

    -- Cash comes out of his Cash account; her cash account does not move.
    v_res := pg_temp.repay(1, 1, 2, '30', 5, 2, 'cash')::jsonb;
    PERFORM pg_temp.expect('cash repayment', (v_res ->> 'outstanding_after') || '/' || (v_res ->> 'payment_method'), '270.00/cash');
    PERFORM pg_temp.expect('his cash down', pg_temp.bal(5), '20.00');
    PERFORM pg_temp.expect('none of hers moved (cash)', pg_temp.hers(), pg_temp.kept('hers'));
    PERFORM pg_temp.expect('no budget moved (cash)', pg_temp.budgets(), pg_temp.kept('budgets'));
    PERFORM pg_temp.expect('her allowance is untouched',
        pg_temp.svc(format('SELECT (public.get_member_allowance_status(%L, %L, NULL, %L)->>''spent'')', pg_temp.h(1), pg_temp.u(2), pg_temp.u(1))), '15.00');
    RAISE NOTICE 'PASSED: his account goes down by exactly the amount, to no account; hers never moves; no budget moves.';
END $$;

-- 2. A double tap ------------------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
    v_res jsonb;
BEGIN
    -- The same tap again: the first answer, nothing new. With other figures it is not the same tap
    -- (review R1-04): refused, nothing new either.
    v_res := pg_temp.repay(1, 1, 2, '100', 3, 1)::jsonb;
    PERFORM pg_temp.expect('a replay answers the first', (v_res ->> 'replayed') || '/' || (v_res ->> 'amount') || '/' || (v_res ->> 'account_id')
        || '/' || (v_res ->> 'outstanding_before') || '/' || (v_res ->> 'outstanding_after'),
        'true/100.00/' || pg_temp.a(3)::text || '/400.00/300.00');
    PERFORM pg_temp.expect('the same key with other figures', pg_temp.repay(1, 1, 2, '99', 9, 1), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('replays move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('replays write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('a key used for another wife', pg_temp.repay(1, 1, 10, '5', 3, 1), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('owed unchanged by replays', pg_temp.outstanding(1, 2), '270.00');
    RAISE NOTICE 'PASSED: a double tap records once.';
END $$;

-- 3. No untracked path ---------------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
BEGIN
    PERFORM pg_temp.expect('no account (8 arguments)', pg_temp.repay(1, 1, 2, '20', 0, 3, 'cash'), 'ERR:app_update_required');
    PERFORM pg_temp.expect('the wife with no account (8 arguments)', pg_temp.repay(2, 1, 2, '20', 0, 3, 'cash'), 'ERR:app_update_required');
    PERFORM pg_temp.expect('the old signature, positional, as the old API',
        pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, %L)::text',
            pg_temp.h(1), pg_temp.u(2), 15, 'cash', pg_temp.u(1))), 'ERR:app_update_required');
    PERFORM pg_temp.expect('the old signature, named, as an old client',
        pg_temp.call(pg_temp.u(1), NULL, format(
            'SELECT public.record_spouse_reimbursement(p_household_id => %L, p_wife_user_id => %L, p_amount => 5)::text', pg_temp.h(1), pg_temp.u(2))),
        'ERR:app_update_required');
    PERFORM pg_temp.expect('the old signature, the wife confirming',
        pg_temp.call(pg_temp.u(2), NULL, format('SELECT public.record_spouse_reimbursement(%L, %L, 5)::text', pg_temp.h(1), pg_temp.u(2))),
        'ERR:app_update_required');
    PERFORM pg_temp.expect('refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('refusals write nothing', pg_temp.counts(), v_counts);

    -- Only the functions that move money write a repayment or a payment event.
    PERFORM pg_temp.expect('who writes the wife''s ledger',
        (SELECT string_agg(DISTINCT proname, ',' ORDER BY proname) FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace AND prosrc ~* 'INSERT\s+INTO\s+public\.spouse_reimbursements\s*\('),
        'nafaqah_repay_from_account,reverse_spouse_reimbursement');
    PERFORM pg_temp.expect('who writes a former member''s events',
        (SELECT string_agg(DISTINCT proname, ',' ORDER BY proname) FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace AND prosrc ~* 'INSERT\s+INTO\s+public\.former_member_debt_events\s*\('),
        'record_former_member_debt_payment,reverse_former_member_debt_payment,waive_former_member_debt');
    PERFORM pg_temp.expect('every repayment written has a transfer',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE household_id = pg_temp.h(1) AND transfer_id IS NULL), '0');
    PERFORM pg_temp.expect('no function picks her account any more',
        (SELECT count(*)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname IN ('nafaqah_repayment_lock_account', 'nafaqah_repayment_debit') AND prosrc ~* '(wife|v_pref|account_type)'), '0');
    PERFORM pg_temp.expect('the debit names no destination',
        (SELECT count(*)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname = 'nafaqah_repayment_debit' AND prosrc ~* 'p_account,\s*NULL,\s*p_amount'), '1');
    RAISE NOTICE 'PASSED: a repayment without an account is refused with app_update_required; nothing records one.';
END $$;

-- 4. Refusals move nothing ----------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
BEGIN
    PERFORM pg_temp.expect('overpayment from an account', pg_temp.repay(1, 1, 2, '270.01', 1, 10), 'ERR:overpayment');
    PERFORM pg_temp.expect('another household''s account', pg_temp.repay(1, 1, 2, '10', 4, 11), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('an archived account', pg_temp.repay(1, 1, 2, '10', 9, 12), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('an account not in SAR', pg_temp.repay(1, 1, 2, '10', 10, 13), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('an account that does not exist',
        pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.record_spouse_reimbursement(%L, %L, 10, %L, NULL, NULL, gen_random_uuid(), %L::uuid)::text',
            pg_temp.h(1), pg_temp.u(2), 'cash', pg_temp.k(14))), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('the husband with a co-admin''s account', pg_temp.repay(1, 1, 2, '10', 8, 15), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('the husband with a member''s account', pg_temp.repay(1, 1, 2, '10', 7, 16), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('a co-admin, while the husband is there (R3-01)', pg_temp.repay(4, 1, 2, '10', 8, 15), 'ERR:forbidden');
    PERFORM pg_temp.expect('the wife with her own account', pg_temp.repay(2, 1, 2, '10', 2, 17), 'ERR:wife_must_request');
    PERFORM pg_temp.expect('the wife with the pool', pg_temp.repay(2, 1, 2, '10', 1, 18), 'ERR:wife_must_request');
    PERFORM pg_temp.expect('a member records nothing', pg_temp.repay(3, 1, 2, '10', 7, 19), 'ERR:forbidden');
    PERFORM pg_temp.expect('insufficient funds', pg_temp.repay(1, 1, 2, '20.01', 5, 20, 'cash'), 'ERR:insufficient_funds');
    PERFORM pg_temp.expect('a request key is required', pg_temp.repay(1, 1, 2, '10', 3, 0), 'ERR:request_key_required');
    PERFORM pg_temp.expect('a sub-halala amount', pg_temp.repay(1, 1, 2, '10.001', 3, 21), 'ERR:invalid_amount');
    PERFORM pg_temp.expect('refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('refusals write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('a refused key is still free', (pg_temp.repay(1, 1, 2, '20', 5, 20, 'cash')::jsonb ->> 'replayed'), 'false');
    PERFORM pg_temp.expect('his cash emptied exactly', pg_temp.bal(5), '0.00');
    PERFORM pg_temp.expect('none of hers moved (refusals)', pg_temp.hers(), pg_temp.kept('hers'));
    PERFORM pg_temp.expect('no budget moved (refusals)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: wrong, archived, foreign or empty accounts, the wife and overpayments are refused, and nothing moves.';
END $$;

-- 5. Pools, a provider who is not an admin, the API path ----------------------------------------
DO $$
DECLARE
    v_res jsonb;
BEGIN
    -- The husband, an admin, pays from the pool.
    v_res := pg_temp.repay(1, 1, 2, '50', 1, 30, 'stc_pay')::jsonb;
    PERFORM pg_temp.expect('pool repayment', v_res ->> 'outstanding_after', '200.00');
    PERFORM pg_temp.expect('pool down', pg_temp.bal(1), '950.00');
    PERFORM pg_temp.expect('none of hers moved (pool)', pg_temp.hers(), pg_temp.kept('hers'));

    -- F3: the provider is a plain member; Z has no account.
    PERFORM pg_temp.expect('a non-admin provider and the pool', pg_temp.repay(8, 3, 9, '10', 11, 31), 'ERR:account_forbidden');
    v_res := pg_temp.repay(8, 3, 9, '100', 12, 32)::jsonb;
    PERFORM pg_temp.expect('the provider from his own account', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(12), '100.00/150.00');
    PERFORM pg_temp.expect('the transfer goes to no account',
        (SELECT (to_account_id IS NULL)::text || ':' || from_account_id::text FROM public.account_transfers WHERE id = (v_res ->> 'transfer_id')::uuid),
        'true:' || pg_temp.a(12)::text);
    PERFORM pg_temp.expect('an admin who is not the husband, while he is there (R3-01)', pg_temp.repay(7, 3, 9, '50', 11, 33) || '/' || pg_temp.bal(11), 'ERR:forbidden/600.00');

    -- The API: service role, the verified caller in p_actor_user_id.
    v_res := pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, 10, %L, NULL, %L, %L::uuid, %L::uuid)::text',
        pg_temp.h(1), pg_temp.u(2), 'bank_transfer', pg_temp.u(1), pg_temp.a(3), pg_temp.k(34)))::jsonb;
    PERFORM pg_temp.expect('API path', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(3) || '/' || pg_temp.hers(),
        '190.00/190.00/' || pg_temp.kept('hers'));
    PERFORM pg_temp.expect('API path checks the verified caller',
        pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, 10, %L, NULL, %L, %L::uuid, %L::uuid)::text',
            pg_temp.h(1), pg_temp.u(2), 'cash', pg_temp.u(4), pg_temp.a(3), pg_temp.k(35))), 'ERR:forbidden');
    PERFORM pg_temp.expect('no repayment transfer has a destination',
        (SELECT count(*)::text FROM public.account_transfers t JOIN public.spouse_reimbursements r ON r.transfer_id = t.id
         WHERE r.kind = 'payment' AND t.to_account_id IS NOT NULL), '0');
    PERFORM pg_temp.expect('no budget moved (pools)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: shared pools by the husband when an admin, his own account otherwise; her side never moves.';
END $$;

-- 6. Append-only ----------------------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
    v_tbl text;
BEGIN
    FOREACH v_tbl IN ARRAY ARRAY['spouse_reimbursements', 'account_transfers', 'spouse_reimbursement_requests',
                                 'spouse_reimbursement_request_outcomes', 'former_member_debt_events'] LOOP
        PERFORM pg_temp.expect('the husband cannot delete from ' || v_tbl,
            pg_temp.call(pg_temp.u(1), NULL, format('DELETE FROM public.%I RETURNING 1::text', v_tbl)), 'ERR:42501');
        PERFORM pg_temp.expect('nor edit ' || v_tbl,
            pg_temp.call(pg_temp.u(1), NULL, format('UPDATE public.%I SET created_at = now() RETURNING 1::text', v_tbl)), 'ERR:42501');
    END LOOP;
    PERFORM pg_temp.expect('nothing moved', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('nothing removed', pg_temp.counts(), v_counts);
    -- The account a repayment left is archived, not deleted (review R3-05): the history stays,
    -- nothing is credited back.
    PERFORM pg_temp.expect('he cannot delete his cash account',
        pg_temp.call(pg_temp.u(1), NULL, format('DELETE FROM public.accounts WHERE id = %L RETURNING id::text', pg_temp.a(5))), 'ERR:account_has_repayments');
    PERFORM pg_temp.expect('he archives it',
        pg_temp.call(pg_temp.u(1), NULL, format('UPDATE public.accounts SET is_archived = true WHERE id = %L RETURNING id::text', pg_temp.a(5))), pg_temp.a(5)::text);
    PERFORM pg_temp.expect('the transfers stay, from his archived account',
        (SELECT count(*)::text FROM public.account_transfers WHERE household_id = pg_temp.h(1) AND from_account_id = pg_temp.a(5) AND amount IN (30, 20)), '2');
    PERFORM pg_temp.expect('owed unchanged', pg_temp.outstanding(1, 2), '190.00');
    RAISE NOTICE 'PASSED: repayments, transfers, requests and outcomes are append-only for clients.';
END $$;

-- 7. Her purge with repayments in her history -------------------------------------------------
DO $$
DECLARE
    v_res jsonb;
    v_keep text;
BEGIN
    v_keep := regexp_replace(regexp_replace(regexp_replace(pg_temp.balances(),
        pg_temp.a(2)::text || '=[0-9.]+,?', ''), pg_temp.a(6)::text || '=[0-9.]+,?', ''), pg_temp.a(13)::text || '=[0-9.]+,?', '');
    PERFORM pg_temp.request(2);
    v_res := pg_temp.purge(2);
    PERFORM pg_temp.expect('the purge completes (its ledger invariant holds)', v_res ->> 'prepared', 'true');
    PERFORM pg_temp.expect('her accounts went with her, every other balance is equal',
        rtrim(pg_temp.balances(), ','), rtrim(v_keep, ','));
    PERFORM pg_temp.expect('no budget moved (purge)', pg_temp.budgets(), pg_temp.kept('budgets'));
    PERFORM pg_temp.expect('the record keeps what remained', pg_temp.state(1), '190.00/0.00/open');
    PERFORM pg_temp.expect('the repayment transfers stay',
        (SELECT count(*)::text FROM public.account_transfers WHERE household_id = pg_temp.h(1) AND to_account_id IS NULL AND amount IN (100, 30, 20, 50, 10)), '5');
    PERFORM pg_temp.expect('her id anywhere', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.expect('her email anywhere', pg_temp.scan('t56-warda@test.local'), '');
    PERFORM pg_temp.expect('her name anywhere', pg_temp.scan('Warda Uniquewife56'), '');
    RAISE NOTICE 'PASSED: the purge with repayments in history keeps its invariant and the record of what remained.';
END $$;

-- 8. A former member's record --------------------------------------------------------------
DO $$
DECLARE
    v_bal text;
    v_counts text;
    v_res jsonb;
    v_event record;
BEGIN
    v_res := pg_temp.fpay(1, 1, '40', 3, 40)::jsonb;
    PERFORM pg_temp.expect('payment from his account', (v_res ->> 'remaining') || '/' || (v_res ->> 'account_id') || '/' || pg_temp.bal(3),
        '150.00/' || pg_temp.a(3)::text || '/150.00');
    SELECT e.*, t.from_account_id, t.to_account_id, t.amount AS t_amount INTO v_event
    FROM public.former_member_debt_events e JOIN public.account_transfers t ON t.id = e.transfer_id
    WHERE e.id = (v_res ->> 'event_id')::uuid;
    PERFORM pg_temp.expect('one transfer, only his side', v_event.from_account_id::text || '>' || COALESCE(v_event.to_account_id::text, 'none') || ':' || v_event.t_amount::text,
        pg_temp.a(3)::text || '>none:40.00');

    v_bal := pg_temp.balances();
    v_counts := pg_temp.counts();
    v_res := pg_temp.fpay(1, 1, '40', 3, 40)::jsonb;
    PERFORM pg_temp.expect('a replay', (v_res ->> 'replayed') || '/' || (v_res ->> 'account_id'), 'true/' || pg_temp.a(3)::text);
    -- Another amount or account with the same key is not the same tap (review R1-04), and is refused
    -- before any account is checked or locked.
    PERFORM pg_temp.expect('the same key with another account', pg_temp.fpay(1, 1, '40', 9, 40), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('the same key with another amount', pg_temp.fpay(1, 1, '1', 3, 40), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('overpayment from an account', pg_temp.fpay(1, 1, '150.01', 3, 41), 'ERR:overpayment');
    PERFORM pg_temp.expect('another member''s account', pg_temp.fpay(1, 1, '10', 8, 42), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('insufficient funds', pg_temp.fpay(1, 1, '5.01', 15, 43), 'ERR:insufficient_funds');
    PERFORM pg_temp.expect('an archived account', pg_temp.fpay(1, 1, '10', 9, 44), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('another household''s account', pg_temp.fpay(1, 1, '10', 4, 45), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('a member', pg_temp.fpay(3, 1, '10', 7, 46), 'ERR:forbidden');
    PERFORM pg_temp.expect('no request key', pg_temp.fpay(1, 1, '10', 3, 0), 'ERR:request_key_required');
    PERFORM pg_temp.expect('no account (7 arguments)', pg_temp.fpay(1, 1, '10', 0, 47), 'ERR:app_update_required');
    PERFORM pg_temp.expect('the old signature is not a client''s (R3-03)',
        pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, %L)::text',
            pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.k(48))), 'ERR:42501');
    PERFORM pg_temp.expect('the old signature, as the old API',
        pg_temp.svc(format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, %L, %L)::text',
            pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.k(48), pg_temp.u(1))), 'ERR:app_update_required');
    PERFORM pg_temp.expect('replays and refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('replays and refusals write nothing', pg_temp.counts(), v_counts);

    -- The husband (an admin) from the pool.
    v_res := pg_temp.fpay(1, 1, '50', 1, 49)::jsonb;
    PERFORM pg_temp.expect('pool payment', (v_res ->> 'remaining') || '/' || pg_temp.bal(1), '100.00/900.00');
    PERFORM pg_temp.expect('every payment event has a transfer',
        (SELECT count(*)::text FROM public.former_member_debt_events WHERE debt_id = pg_temp.debt(1) AND transfer_id IS NULL), '0');

    -- Her waiver of the rest moves nothing.
    v_bal := pg_temp.balances();
    v_counts := (SELECT count(*) FROM public.account_transfers)::text;
    v_res := pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.waive_former_member_debt(%L, %L, %L)::text', pg_temp.h(1), pg_temp.debt(1), pg_temp.k(50)))::jsonb;
    PERFORM pg_temp.expect('waived', (v_res ->> 'status') || '/' || (v_res ->> 'waived_amount'), 'waived/100.00');
    PERFORM pg_temp.expect('the waiver moves nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('the waiver writes no transfer', (SELECT count(*) FROM public.account_transfers)::text, v_counts);
    PERFORM pg_temp.expect('closed takes no account payment', pg_temp.fpay(1, 1, '1', 3, 51), 'ERR:debt_closed');

    -- F3: Z goes; the provider (not an admin) pays from his own account, not from the pool.
    PERFORM pg_temp.request(9);
    PERFORM pg_temp.purge(9);
    PERFORM pg_temp.expect('F3 record', pg_temp.state(3), '100.00/0.00/open');
    PERFORM pg_temp.expect('a non-admin provider and the pool', pg_temp.fpay(8, 3, '10', 11, 52), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('an admin, while the husband is there (R3-01)', pg_temp.fpay(7, 3, '10', 11, 54), 'ERR:forbidden');
    PERFORM pg_temp.expect('the provider from his own account', (pg_temp.fpay(8, 3, '10', 12, 53)::jsonb ->> 'remaining') || '/' || pg_temp.bal(12), '90.00/140.00');
    PERFORM pg_temp.expect('no budget moved (former member)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: a former member payment debits his account only; replays once; no account is refused; the waiver moves nothing.';
END $$;

-- 9. Privileges ---------------------------------------------------------------------------
DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid)',
        'record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid)',
        'record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid)'
    ] LOOP
        IF has_function_privilege('anon', 'public.' || v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: anon can execute %', v_sig;
        END IF;
        IF NOT has_function_privilege('authenticated', 'public.' || v_sig, 'EXECUTE')
           OR NOT has_function_privilege('service_role', 'public.' || v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: % not executable by its callers', v_sig;
        END IF;
    END LOOP;
    -- The amount-only payment stays the service role's (reviews R1-11, R3-03).
    IF has_function_privilege('anon', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY: the amount-only former member payment is not the service role''s only';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
               AND p.proname IN ('record_spouse_reimbursement', 'record_former_member_debt_payment', 'get_spouse_reimbursement_balance',
                                 'former_member_debt_outstanding', 'guard_wife_reimbursable_ledger', 'remove_nafaqah_ledger_on_membership_end')
               AND (NOT p.prosecdef OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))) THEN
        RAISE EXCEPTION 'a repayment function without SECURITY DEFINER and a fixed search_path';
    END IF;
    PERFORM pg_temp.expect('exactly two overloads each',
        (SELECT string_agg(proname || ':' || n, ',' ORDER BY proname) FROM (
            SELECT proname, count(*) AS n FROM pg_proc WHERE pronamespace = 'public'::regnamespace
            AND proname IN ('record_spouse_reimbursement', 'record_former_member_debt_payment') GROUP BY proname) s),
        'record_former_member_debt_payment:2,record_spouse_reimbursement:2');
    PERFORM pg_temp.expect('the helpers of the first draft are gone',
        (SELECT count(*)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname IN ('nafaqah_repayment_move', 'nafaqah_repayment_lock_accounts')), '0');
    RAISE NOTICE 'PASSED: privileges of the repayment functions.';
END $$;

ROLLBACK;
