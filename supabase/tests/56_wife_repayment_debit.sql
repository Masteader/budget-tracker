-- ============================================================================
-- Test 56: a repayment to the wife moves money out of the account he picks
--
-- Migration: 20261105001300_wife_repayment_debit.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Owner decision 2026-11-06: when the husband repays the wife (wife_reimbursable), the amount
-- leaves the account he picks and, when she has a personal account in the app, arrives in hers,
-- as a transfer. No budget moves: her expense counted when she recorded it. "Not tracked in the
-- app" records the amount and method only, as before. The same holds for the payment of a former
-- member's record; her waiver moves nothing.
--
-- Verifies:
--   1. A repayment from his account: his balance goes down by exactly the amount, hers up by the
--      same, one account_transfers row linked from the ledger row; no budget, no transaction, and
--      her allowance untouched.
--   2. Her account follows the payment method (cash to her cash account), else her oldest one;
--      never an archived account.
--   3. Not tracked in the app: nothing moves, no transfer.
--   4. Refused, with nothing moved: overpayment, an account of another household, archived or not
--      in SAR, another member's personal account, a shared pool for a non-admin, any account for the
--      wife herself, insufficient funds, an account without a request key.
--   5. A shared pool by an admin; a provider who is not an admin pays from his own account; a wife
--      with no account: only his side moves. The API path (service role, p_actor_user_id).
--   6. A double tap (same request key) records once; a key used for another wife is refused.
--   7. The old signature still records amount only, positional and named.
--   8. Nothing voids a repayment: no client deletes or edits the ledger or the transfer.
--   9. The purge of the wife with repayments in her history: the ledger invariant holds, the
--      transfers stay without her account, the record holds what remained.
--  10. A former member's record: a payment from an account debits it (only his side), a replay
--      once, the old signature amount only, refusals move nothing, the waiver moves nothing.
--  11. Privileges and pinned search_path.
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

-- A repayment through the new signature, as user p_actor (authenticated). p_account 0 = not tracked.
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

-- A former member payment through the new signature. p_account 0 = not tracked.
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
    PERFORM pg_temp.acct(13, 1, 2, false, 70, 'e_wallet', true);      -- W archived wallet
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

-- 1. From his account to hers -------------------------------------------------------------
DO $$
DECLARE
    v_tx bigint := (SELECT count(*) FROM public.transactions);
    v_res jsonb;
    v_transfer record;
BEGIN
    PERFORM pg_temp.expect('fixture: owed', pg_temp.outstanding(1, 2), '400.00');
    PERFORM pg_temp.expect('fixture: her bank after the advance', pg_temp.bal(2), '400.00');
    PERFORM pg_temp.expect('fixture: the budget counts her advances',
        (SELECT spent_amount::text FROM public.budgets WHERE id = 'e56b0000-0000-0000-0000-000000000001'), '440.00');

    v_res := pg_temp.repay(1, 1, 2, '100', 3, 1)::jsonb;
    PERFORM pg_temp.expect('recorded', (v_res ->> 'replayed') || '/' || (v_res ->> 'outstanding_after') || '/' || (v_res ->> 'account_id'),
        'false/300.00/' || pg_temp.a(3)::text);
    PERFORM pg_temp.expect('her account was credited', v_res ->> 'wife_account_credited', 'true');
    PERFORM pg_temp.expect('his bank down by exactly 100', pg_temp.bal(3), '200.00');
    PERFORM pg_temp.expect('her bank up by exactly 100', pg_temp.bal(2), '500.00');
    PERFORM pg_temp.expect('her cash untouched', pg_temp.bal(6), '20.00');
    PERFORM pg_temp.expect('her archived wallet untouched', pg_temp.bal(13), '70.00');
    PERFORM pg_temp.expect('owed after', pg_temp.outstanding(1, 2), '300.00');

    SELECT t.* INTO v_transfer FROM public.account_transfers t
    JOIN public.spouse_reimbursements r ON r.transfer_id = t.id
    WHERE r.id = (v_res ->> 'reimbursement_id')::uuid;
    PERFORM pg_temp.expect('one linked transfer',
        v_transfer.from_account_id::text || '>' || v_transfer.to_account_id::text || ':' || v_transfer.amount::text || ':' || v_transfer.fee::text
        || ':' || (v_transfer.user_id = pg_temp.u(1))::text || ':' || (v_transfer.household_id = pg_temp.h(1))::text,
        pg_temp.a(3)::text || '>' || pg_temp.a(2)::text || ':100.00:0.00:true:true');
    PERFORM pg_temp.expect('the request key is kept',
        (SELECT request_key::text FROM public.spouse_reimbursements WHERE id = (v_res ->> 'reimbursement_id')::uuid), pg_temp.k(1)::text);
    PERFORM pg_temp.expect('no transaction written', (SELECT count(*) FROM public.transactions)::text, v_tx::text);
    PERFORM pg_temp.expect('no budget moved', pg_temp.budgets(), pg_temp.kept('budgets'));

    -- 2. Her account follows the method: cash into her cash account, from his cash.
    v_res := pg_temp.repay(1, 1, 2, '30', 5, 2, 'cash')::jsonb;
    PERFORM pg_temp.expect('cash repayment', v_res ->> 'outstanding_after', '270.00');
    PERFORM pg_temp.expect('his cash down', pg_temp.bal(5), '20.00');
    PERFORM pg_temp.expect('her cash up', pg_temp.bal(6), '50.00');
    PERFORM pg_temp.expect('her bank as before', pg_temp.bal(2), '500.00');
    PERFORM pg_temp.expect('no budget moved (cash)', pg_temp.budgets(), pg_temp.kept('budgets'));
    PERFORM pg_temp.expect('her allowance is untouched',
        pg_temp.svc(format('SELECT (public.get_member_allowance_status(%L, %L, NULL, %L)->>''spent'')', pg_temp.h(1), pg_temp.u(2), pg_temp.u(1))), '15.00');
    RAISE NOTICE 'PASSED: his account goes down and hers up by exactly the amount, as a transfer; no budget moves.';
END $$;

-- 3 and 6. Not tracked in the app; a double tap ---------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text;
    v_first jsonb;
    v_res jsonb;
BEGIN
    v_first := pg_temp.repay(1, 1, 2, '20', 0, 3, 'cash')::jsonb;
    PERFORM pg_temp.expect('not tracked recorded', (v_first ->> 'outstanding_after') || '/' || COALESCE(v_first ->> 'account_id', 'none')
        || '/' || (v_first ->> 'wife_account_credited'), '250.00/none/false');
    PERFORM pg_temp.expect('not tracked moves no balance', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('not tracked has no transfer',
        (SELECT (transfer_id IS NULL)::text FROM public.spouse_reimbursements WHERE id = (v_first ->> 'reimbursement_id')::uuid), 'true');

    -- The same tap again, even with other figures: the first answer, nothing new.
    v_counts := pg_temp.counts();
    v_res := pg_temp.repay(1, 1, 2, '20', 0, 3, 'cash')::jsonb;
    PERFORM pg_temp.expect('not tracked replay', (v_res ->> 'replayed') || '/' || (v_res ->> 'reimbursement_id'), 'true/' || (v_first ->> 'reimbursement_id'));
    v_res := pg_temp.repay(1, 1, 2, '99', 9, 1)::jsonb;
    PERFORM pg_temp.expect('account replay answers the first', (v_res ->> 'replayed') || '/' || (v_res ->> 'amount') || '/' || (v_res ->> 'account_id'),
        'true/100.00/' || pg_temp.a(3)::text);
    PERFORM pg_temp.expect('replays move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('replays write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('a key used for another wife', pg_temp.repay(1, 1, 10, '5', 3, 1), 'ERR:request_key_reused');
    PERFORM pg_temp.expect('owed unchanged by replays', pg_temp.outstanding(1, 2), '250.00');
    RAISE NOTICE 'PASSED: not tracked moves nothing; a double tap records once.';
END $$;

-- 4. Refusals move nothing ----------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
BEGIN
    PERFORM pg_temp.expect('overpayment from an account', pg_temp.repay(1, 1, 2, '250.01', 1, 10), 'ERR:overpayment');
    PERFORM pg_temp.expect('another household''s account', pg_temp.repay(1, 1, 2, '10', 4, 11), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('an archived account', pg_temp.repay(1, 1, 2, '10', 9, 12), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('an account not in SAR', pg_temp.repay(1, 1, 2, '10', 10, 13), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('an account that does not exist',
        pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.record_spouse_reimbursement(%L, %L, 10, %L, NULL, NULL, gen_random_uuid(), %L::uuid)::text',
            pg_temp.h(1), pg_temp.u(2), 'cash', pg_temp.k(14))), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('a co-admin with the husband''s account', pg_temp.repay(4, 1, 2, '10', 3, 15), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('a co-admin with a member''s account', pg_temp.repay(4, 1, 2, '10', 7, 16), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('the wife with her own account', pg_temp.repay(2, 1, 2, '10', 2, 17), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('the wife with the pool', pg_temp.repay(2, 1, 2, '10', 1, 18), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('a member records nothing', pg_temp.repay(3, 1, 2, '10', 7, 19), 'ERR:42501');
    PERFORM pg_temp.expect('insufficient funds', pg_temp.repay(1, 1, 2, '20.01', 5, 20, 'cash'), 'ERR:insufficient_funds');
    PERFORM pg_temp.expect('an account needs a request key', pg_temp.repay(1, 1, 2, '10', 3, 0), 'ERR:request_key_required');
    PERFORM pg_temp.expect('a sub-halala amount', pg_temp.repay(1, 1, 2, '10.001', 3, 21), 'ERR:22023');
    PERFORM pg_temp.expect('refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('refusals write nothing', pg_temp.counts(), v_counts);
    PERFORM pg_temp.expect('a refused key is still free', (pg_temp.repay(1, 1, 2, '20', 5, 20, 'cash')::jsonb ->> 'replayed'), 'false');
    PERFORM pg_temp.expect('his cash emptied exactly', pg_temp.bal(5), '0.00');
    PERFORM pg_temp.expect('no budget moved (refusals)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: wrong, archived, foreign or empty accounts and overpayments are refused, and nothing moves.';
END $$;

-- 5. Pools, a provider who is not an admin, a wife with no account, the API path ----------------
DO $$
DECLARE
    v_res jsonb;
BEGIN
    -- A co-admin pays from the pool; W has no wallet, so the stc_pay amount lands in her bank.
    v_res := pg_temp.repay(4, 1, 2, '50', 1, 30, 'stc_pay')::jsonb;
    PERFORM pg_temp.expect('pool repayment', v_res ->> 'outstanding_after', '180.00');
    PERFORM pg_temp.expect('pool down', pg_temp.bal(1), '950.00');
    PERFORM pg_temp.expect('her bank up', pg_temp.bal(2), '550.00');

    -- F3: the provider is a plain member.
    PERFORM pg_temp.expect('a non-admin provider and the pool', pg_temp.repay(8, 3, 9, '10', 11, 31), 'ERR:account_forbidden');
    v_res := pg_temp.repay(8, 3, 9, '100', 12, 32)::jsonb;
    PERFORM pg_temp.expect('no account of hers: only his side', (v_res ->> 'wife_account_credited') || '/' || pg_temp.bal(12), 'false/150.00');
    PERFORM pg_temp.expect('the transfer goes nowhere in the app',
        (SELECT (to_account_id IS NULL)::text || ':' || from_account_id::text FROM public.account_transfers WHERE id = (v_res ->> 'transfer_id')::uuid),
        'true:' || pg_temp.a(12)::text);
    v_res := pg_temp.repay(7, 3, 9, '50', 11, 33)::jsonb;
    PERFORM pg_temp.expect('an admin who is not the husband, from the pool', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(11), '50.00/550.00');

    -- The API: service role, the verified caller in p_actor_user_id.
    v_res := pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, 10, %L, NULL, %L, %L::uuid, %L::uuid)::text',
        pg_temp.h(1), pg_temp.u(2), 'bank_transfer', pg_temp.u(1), pg_temp.a(3), pg_temp.k(34)))::jsonb;
    PERFORM pg_temp.expect('API path', (v_res ->> 'outstanding_after') || '/' || pg_temp.bal(3) || '/' || pg_temp.bal(2), '170.00/190.00/560.00');
    PERFORM pg_temp.expect('API path checks the verified caller',
        pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, 10, %L, NULL, %L, %L::uuid, %L::uuid)::text',
            pg_temp.h(1), pg_temp.u(2), 'cash', pg_temp.u(4), pg_temp.a(3), pg_temp.k(35))), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('no budget moved (pools)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: shared pools by admins only, his own account otherwise, and only his side without an account of hers.';
END $$;

-- 7. The old signature ----------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_transfers bigint := (SELECT count(*) FROM public.account_transfers);
    v_res jsonb;
BEGIN
    v_res := pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, %L)::text',
        pg_temp.h(1), pg_temp.u(2), 15, 'cash', pg_temp.u(1)))::jsonb;
    PERFORM pg_temp.expect('positional, as the API did', v_res ->> 'outstanding_after', '155.00');
    v_res := pg_temp.call(pg_temp.u(1), NULL, format(
        'SELECT public.record_spouse_reimbursement(p_household_id => %L, p_wife_user_id => %L, p_amount => 5)::text', pg_temp.h(1), pg_temp.u(2)))::jsonb;
    PERFORM pg_temp.expect('named, as an old client', (v_res ->> 'outstanding_after') || '/' || (v_res ->> 'payment_method'), '150.00/cash');
    PERFORM pg_temp.expect('the old signature overpays nothing',
        pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, 150.01, %L, NULL, %L)::text', pg_temp.h(1), pg_temp.u(2), 'cash', pg_temp.u(1))),
        'ERR:overpayment');
    PERFORM pg_temp.expect('the old signature moves nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('and writes no transfer', (SELECT count(*) FROM public.account_transfers)::text, v_transfers::text);
    PERFORM pg_temp.expect('its rows have no transfer',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE household_id = pg_temp.h(1) AND amount IN (15, 5) AND transfer_id IS NULL), '2');
    RAISE NOTICE 'PASSED: the old signature still records amount and method only.';
END $$;

-- 8. Nothing voids a repayment ------------------------------------------------------------------
DO $$
DECLARE
    v_bal text := pg_temp.balances();
    v_counts text := pg_temp.counts();
BEGIN
    PERFORM pg_temp.expect('the husband cannot delete a repayment',
        pg_temp.call(pg_temp.u(1), NULL, 'DELETE FROM public.spouse_reimbursements RETURNING id::text'), 'ERR:42501');
    PERFORM pg_temp.expect('nor edit it',
        pg_temp.call(pg_temp.u(1), NULL, 'UPDATE public.spouse_reimbursements SET amount = 1 RETURNING id::text'), 'ERR:42501');
    PERFORM pg_temp.expect('nor delete its transfer',
        pg_temp.call(pg_temp.u(1), NULL, 'DELETE FROM public.account_transfers RETURNING id::text'), 'ERR:42501');
    PERFORM pg_temp.expect('nor edit its transfer',
        pg_temp.call(pg_temp.u(1), NULL, 'UPDATE public.account_transfers SET amount = 1 RETURNING id::text'), 'ERR:42501');
    PERFORM pg_temp.expect('no function voids a repayment',
        (SELECT count(*)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname ~ '(void|delete|reverse|undo).*(reimburs|repay)'), '0');
    PERFORM pg_temp.expect('nothing moved', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('nothing removed', pg_temp.counts(), v_counts);
    -- The husband may still delete his own account: the history stays, nothing is credited back.
    PERFORM pg_temp.expect('he deletes his cash account',
        pg_temp.call(pg_temp.u(1), NULL, format('DELETE FROM public.accounts WHERE id = %L RETURNING id::text', pg_temp.a(5))), pg_temp.a(5)::text);
    PERFORM pg_temp.expect('the transfer stays, without his account',
        (SELECT count(*)::text FROM public.account_transfers WHERE household_id = pg_temp.h(1) AND from_account_id IS NULL AND amount IN (30, 20)), '2');
    PERFORM pg_temp.expect('owed unchanged', pg_temp.outstanding(1, 2), '150.00');
    RAISE NOTICE 'PASSED: a repayment is append-only, like the ledger; clients cannot void it or its transfer.';
END $$;

-- 9. Her purge with repayments in her history -------------------------------------------------
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
    PERFORM pg_temp.expect('the record keeps what remained', pg_temp.state(1), '150.00/0.00/open');
    PERFORM pg_temp.expect('the transfers into her accounts stay, without her account',
        (SELECT count(*)::text FROM public.account_transfers WHERE household_id = pg_temp.h(1) AND to_account_id IS NULL AND amount IN (100, 30, 50, 10)), '4');
    PERFORM pg_temp.expect('her id anywhere', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.expect('her email anywhere', pg_temp.scan('t56-warda@test.local'), '');
    PERFORM pg_temp.expect('her name anywhere', pg_temp.scan('Warda Uniquewife56'), '');
    RAISE NOTICE 'PASSED: the purge with repayments in history keeps its invariant and the record of what remained.';
END $$;

-- 10. A former member's record --------------------------------------------------------------
DO $$
DECLARE
    v_bal text;
    v_counts text;
    v_res jsonb;
    v_event record;
BEGIN
    v_res := pg_temp.fpay(1, 1, '40', 3, 40)::jsonb;
    PERFORM pg_temp.expect('payment from his account', (v_res ->> 'remaining') || '/' || (v_res ->> 'account_id') || '/' || pg_temp.bal(3),
        '110.00/' || pg_temp.a(3)::text || '/150.00');
    SELECT e.*, t.from_account_id, t.to_account_id, t.amount AS t_amount INTO v_event
    FROM public.former_member_debt_events e JOIN public.account_transfers t ON t.id = e.transfer_id
    WHERE e.id = (v_res ->> 'event_id')::uuid;
    PERFORM pg_temp.expect('one transfer, only his side', v_event.from_account_id::text || '>' || COALESCE(v_event.to_account_id::text, 'none') || ':' || v_event.t_amount::text,
        pg_temp.a(3)::text || '>none:40.00');

    v_bal := pg_temp.balances();
    v_counts := pg_temp.counts();
    v_res := pg_temp.fpay(1, 1, '40', 3, 40)::jsonb;
    PERFORM pg_temp.expect('a replay', (v_res ->> 'replayed') || '/' || (v_res ->> 'account_id'), 'true/' || pg_temp.a(3)::text);
    -- Even with an account that would now be refused: the replay answers before any account check.
    PERFORM pg_temp.expect('a replay with another account answers the first', (pg_temp.fpay(1, 1, '1', 9, 40)::jsonb ->> 'account_id'), pg_temp.a(3)::text);
    PERFORM pg_temp.expect('overpayment from an account', pg_temp.fpay(1, 1, '110.01', 3, 41), 'ERR:overpayment');
    PERFORM pg_temp.expect('another member''s account', pg_temp.fpay(1, 1, '10', 8, 42), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('insufficient funds', pg_temp.fpay(1, 1, '5.01', 15, 43), 'ERR:insufficient_funds');
    PERFORM pg_temp.expect('an archived account', pg_temp.fpay(1, 1, '10', 9, 44), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('another household''s account', pg_temp.fpay(1, 1, '10', 4, 45), 'ERR:account_unavailable');
    PERFORM pg_temp.expect('a member', pg_temp.fpay(3, 1, '10', 7, 46), 'ERR:forbidden');
    PERFORM pg_temp.expect('no request key', pg_temp.fpay(1, 1, '10', 3, 0), 'ERR:request_key_required');
    PERFORM pg_temp.expect('replays and refusals move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('replays and refusals write nothing', pg_temp.counts(), v_counts);

    -- A co-admin from the pool.
    v_res := pg_temp.fpay(4, 1, '50', 1, 47)::jsonb;
    PERFORM pg_temp.expect('pool payment', (v_res ->> 'remaining') || '/' || pg_temp.bal(1), '60.00/900.00');

    -- The old signature: amount and method only.
    v_bal := pg_temp.balances();
    v_res := pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, %L)::text',
        pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.k(48)))::jsonb;
    PERFORM pg_temp.expect('old signature payment', (v_res ->> 'remaining') || '/' || COALESCE(v_res ->> 'account_id', 'none'), '50.00/none');
    PERFORM pg_temp.expect('not tracked (new signature)', (pg_temp.fpay(1, 1, '5', 0, 49)::jsonb ->> 'remaining'), '45.00');
    PERFORM pg_temp.expect('amount-only payments move nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('their events have no transfer',
        (SELECT count(*)::text FROM public.former_member_debt_events WHERE debt_id = pg_temp.debt(1) AND transfer_id IS NULL), '2');

    -- Her waiver of the rest moves nothing.
    v_counts := (SELECT count(*) FROM public.account_transfers)::text;
    v_res := pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.waive_former_member_debt(%L, %L, %L)::text', pg_temp.h(1), pg_temp.debt(1), pg_temp.k(50)))::jsonb;
    PERFORM pg_temp.expect('waived', (v_res ->> 'status') || '/' || (v_res ->> 'waived_amount'), 'waived/45.00');
    PERFORM pg_temp.expect('the waiver moves nothing', pg_temp.balances(), v_bal);
    PERFORM pg_temp.expect('the waiver writes no transfer', (SELECT count(*) FROM public.account_transfers)::text, v_counts);
    PERFORM pg_temp.expect('closed takes no account payment', pg_temp.fpay(1, 1, '1', 3, 51), 'ERR:debt_closed');

    -- F3: Z goes; the provider (not an admin) pays from his own account, not from the pool.
    PERFORM pg_temp.request(9);
    PERFORM pg_temp.purge(9);
    PERFORM pg_temp.expect('F3 record', pg_temp.state(3), '50.00/0.00/open');
    PERFORM pg_temp.expect('a non-admin provider and the pool', pg_temp.fpay(8, 3, '10', 11, 52), 'ERR:account_forbidden');
    PERFORM pg_temp.expect('the provider from his own account', (pg_temp.fpay(8, 3, '10', 12, 53)::jsonb ->> 'remaining') || '/' || pg_temp.bal(12), '40.00/140.00');
    PERFORM pg_temp.expect('no budget moved (former member)', pg_temp.budgets(), pg_temp.kept('budgets'));
    RAISE NOTICE 'PASSED: a former member payment debits his account only; replays once; old signature and waiver move nothing.';
END $$;

-- 11. Privileges ---------------------------------------------------------------------------
DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid, uuid, uuid)',
        'record_spouse_reimbursement(uuid, uuid, numeric, text, text, uuid)',
        'record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid)',
        'record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)'
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
        'nafaqah_repayment_lock_accounts(uuid, uuid, uuid, uuid, text)',
        'nafaqah_repayment_move(uuid, uuid, uuid, uuid, numeric, text)'
    ] LOOP
        IF has_function_privilege('anon', 'public.' || v_sig, 'EXECUTE')
           OR has_function_privilege('authenticated', 'public.' || v_sig, 'EXECUTE')
           OR has_function_privilege('service_role', 'public.' || v_sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client can execute the internal %', v_sig;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
               AND p.proname IN ('record_spouse_reimbursement', 'record_former_member_debt_payment',
                                 'nafaqah_repayment_lock_accounts', 'nafaqah_repayment_move')
               AND (NOT p.prosecdef OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))) THEN
        RAISE EXCEPTION 'a repayment function without SECURITY DEFINER and a fixed search_path';
    END IF;
    PERFORM pg_temp.expect('exactly two overloads each',
        (SELECT string_agg(proname || ':' || n, ',' ORDER BY proname) FROM (
            SELECT proname, count(*) AS n FROM pg_proc WHERE pronamespace = 'public'::regnamespace
            AND proname IN ('record_spouse_reimbursement', 'record_former_member_debt_payment') GROUP BY proname) s),
        'record_former_member_debt_payment:2,record_spouse_reimbursement:2');
    RAISE NOTICE 'PASSED: privileges of the repayment functions.';
END $$;

ROLLBACK;
