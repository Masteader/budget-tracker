-- ============================================================================
-- Test 62: Round 3 review fixes of tracked repayments (owner decisions 2026-11-06)
--
-- Migrations: 20261105001200_account_deletion_former_member_debt.sql,
--             20261105001300_wife_repayment_debit.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Verifies, one finding each (every check is collected, so a failing run lists them all):
--   R3-01  Who sees and who acts on a wife's repayment ledger (her advances' balance, repayments,
--          reversals, her requests, their outcomes and decline reasons) and on a former member's
--          record. The matrix: the wife, her husband (the household's Nafaqah provider), a co-wife,
--          an ordinary member, an admin who is not a wife, a wife who is an admin; with the husband
--          a member, and gone (he left, or his account was deleted).
--            Husband present: she sees her own ledger, he sees it and acts on it; nobody else sees
--            a row, a total or a request of it, or the former member's record.
--            Husband gone: an admin who is not a wife sees and acts (approves her pending request,
--            records a repayment, reverses one from a pool, pays and waives the record).
--            Always: a wife never sees or acts for a co-wife, even as an admin; a personal
--            account's repayment is reversed by its owner while a member and not a wife.
--   R3-03  The 6-argument (amount-only) former member payment stays the service role's only.
--   R3-04  The second pass of reverse_former_member_debt_payment reads the record of the household.
--   R3-05  A client cannot delete an account a repayment or a reversal used (archive it instead);
--          other accounts delete as before, and the purge still deletes its accounts.
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
AS $$ SELECT ('e6200000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e62a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e62c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e62e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
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
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T62 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE p_type END, p_balance, p_pool, false, 'SAR');
END;
$$;

CREATE FUNCTION pg_temp.advance(p_hh int, p_wife int, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'T62 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me',
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
CREATE FUNCTION pg_temp.uid(p_val text) RETURNS uuid LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN p_val ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN p_val::uuid END $$;
GRANT EXECUTE ON FUNCTION pg_temp.uid(text) TO PUBLIC;
CREATE FUNCTION pg_temp.id(p_label text) RETURNS uuid LANGUAGE sql AS $$ SELECT pg_temp.uid(val) FROM pg_temp.snap WHERE label = p_label $$;

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


CREATE FUNCTION pg_temp.waive(p_actor int, p_hh int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.waive_former_member_debt(%L, %L, %L::uuid, NULL)::text', pg_temp.h(p_hh), pg_temp.debt(p_hh), pg_temp.k(p_key)));
$$;
-- As the test's own role (the internal helpers are executable by no API role).
CREATE FUNCTION pg_temp.raw(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_val text;
    v_hint text;
BEGIN
    EXECUTE p_sql INTO v_val;
    RETURN COALESCE(v_val, 'ok');
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
END;
$$;
CREATE FUNCTION pg_temp.j(p_res text, p_field text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    IF p_res IS NULL OR p_res LIKE 'ERR:%' THEN RETURN p_res; END IF;
    RETURN p_res::jsonb ->> p_field;
END;
$$;
CREATE FUNCTION pg_temp.payer(p_row uuid) RETURNS text LANGUAGE sql
AS $$ SELECT COALESCE((SELECT paid_by_user_id::text FROM public.spouse_reimbursements WHERE id = p_row), 'none') $$;
CREATE FUNCTION pg_temp.purpose(p_transfer text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.raw(format('SELECT COALESCE(purpose, ''-'') || ''/'' || COALESCE(notes, ''-'') FROM public.account_transfers WHERE id = %L', p_transfer));
$$;
CREATE FUNCTION pg_temp.pending(p_hh int, p_wife int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.balance_of(p_hh, p_wife, 'pending_requested') $$;
-- Every wife's pending total against what is owed to her: the households and wives above it.
CREATE FUNCTION pg_temp.over() RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(p.household_id::text || ':' || p.pend::text, ','), 'none')
    FROM (SELECT q.household_id, q.wife_user_id, sum(q.amount) AS pend
          FROM public.spouse_reimbursement_requests q
          WHERE NOT EXISTS (SELECT 1 FROM public.spouse_reimbursement_request_outcomes o WHERE o.request_id = q.id)
          GROUP BY 1, 2) p
    WHERE p.pend > public.nafaqah_outstanding(p.household_id, p.wife_user_id);
$$;

CREATE TABLE pg_temp.fails (n serial PRIMARY KEY, label text, got text, want text);
CREATE FUNCTION pg_temp.check(p_label text, p_got text, p_want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 240), p_want);
    END IF;
END;
$$;

-- What one caller reads of a wife's ledger, as the client (RLS): her repayment rows, her requests
-- and their outcomes (counted by the request ids, so a hidden request does not hide its outcome).
CREATE FUNCTION pg_temp.led_sql(p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT format($q$SELECT (SELECT count(*) FROM public.spouse_reimbursements WHERE wife_user_id = %1$L)::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursement_requests WHERE wife_user_id = %1$L)::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursement_request_outcomes WHERE request_id = ANY (%2$L::uuid[]))::text$q$,
        pg_temp.u(p_wife),
        (SELECT COALESCE(array_agg(q.id), '{}') FROM public.spouse_reimbursement_requests q WHERE q.wife_user_id = pg_temp.u(p_wife)));
$$;
-- The household's former member records and their events, as the client reads them.
CREATE FUNCTION pg_temp.fmd_sql(p_hh int) RETURNS text LANGUAGE sql AS $$
    SELECT format($q$SELECT (SELECT count(*) FROM public.former_member_debts WHERE household_id = %1$L)::text
        || '/' || (SELECT count(*) FROM public.former_member_debt_events WHERE debt_id = ANY (%2$L::uuid[]))::text$q$,
        pg_temp.h(p_hh),
        (SELECT COALESCE(array_agg(d.id), '{}') FROM public.former_member_debts d WHERE d.household_id = pg_temp.h(p_hh)));
$$;
CREATE FUNCTION pg_temp.led(p_actor int, p_wife int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.call(pg_temp.u(p_actor), NULL, pg_temp.led_sql(p_wife)) $$;
CREATE FUNCTION pg_temp.led_all(p_wife int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.raw(pg_temp.led_sql(p_wife)) $$;
CREATE FUNCTION pg_temp.fmd(p_actor int, p_hh int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.call(pg_temp.u(p_actor), NULL, pg_temp.fmd_sql(p_hh)) $$;
CREATE FUNCTION pg_temp.fmd_all(p_hh int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.raw(pg_temp.fmd_sql(p_hh)) $$;
-- get_spouse_reimbursement_balance as the client (the read RPC).
CREATE FUNCTION pg_temp.owed_as(p_actor int, p_hh int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT (public.get_spouse_reimbursement_balance(%L, %L, NULL) ->> %L)', pg_temp.h(p_hh), pg_temp.u(p_wife), 'outstanding'));
$$;
-- The same, as the API calls it: the service role naming the verified caller.
CREATE FUNCTION pg_temp.owed_api(p_actor int, p_hh int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.svc(format('SELECT (public.get_spouse_reimbursement_balance(%L, %L, %L) ->> %L)',
                              pg_temp.h(p_hh), pg_temp.u(p_wife), pg_temp.u(p_actor), 'outstanding'));
$$;
-- A client's delete of an account: how many rows went, or the refusal.
CREATE FUNCTION pg_temp.del_acct(p_actor int, p_n int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('WITH d AS (DELETE FROM public.accounts WHERE id = %L RETURNING 1) SELECT count(*)::text FROM d', pg_temp.a(p_n)));
$$;
CREATE FUNCTION pg_temp.waive2(p_actor int, p_hh int, p_key int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.j(pg_temp.waive(p_actor, p_hh, p_key), 'status') $$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider; wife W(2); co-wife W2(3); member K(4); admin C(5) who is
--        not a wife; wife WA(6) who is an admin. A former member's record of 300.
-- F2(2): husband H2(7) admin (not primary) and provider; wife V(8); primary admin D(9). A record of 200.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't62-' || n || '@test.local', jsonb_build_object('display_name', 'T62 User ' || n)
    FROM generate_series(1, 9) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T62 H1', 'T62CODE000000001', 'family'),
        (pg_temp.h(2), 'T62 H2', 'T62CODE000000002', 'family');
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'member', 'family_member');
    PERFORM pg_temp.join(6, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(7, 2, 'admin', 'provider');
    PERFORM pg_temp.join(8, 2, 'member', 'spouse');
    PERFORM pg_temp.join(9, 2, 'admin', 'family_member');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(9), nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);

    PERFORM pg_temp.acct(1, 1, 1, true, 5000);    -- F1 pool
    PERFORM pg_temp.acct(2, 1, 1, false, 5000);   -- H
    PERFORM pg_temp.acct(3, 1, 5, false, 5000);   -- C
    PERFORM pg_temp.acct(4, 1, 4, false, 1000);   -- K
    PERFORM pg_temp.acct(5, 1, 2, false, 1000);   -- W
    PERFORM pg_temp.acct(6, 1, 6, false, 1000);   -- WA
    PERFORM pg_temp.acct(7, 1, 3, false, 1000);   -- W2
    PERFORM pg_temp.acct(8, 1, 5, false, 100, 'cash');  -- C, never used for a repayment
    PERFORM pg_temp.acct(11, 2, 7, true, 5000);   -- F2 pool
    PERFORM pg_temp.acct(12, 2, 7, false, 5000);  -- H2
    PERFORM pg_temp.acct(13, 2, 9, false, 5000);  -- D

    PERFORM pg_temp.advance(1, 2, 1000);
    PERFORM pg_temp.advance(1, 3, 100);
    PERFORM pg_temp.advance(1, 6, 50);
    PERFORM pg_temp.advance(2, 8, 400);
    INSERT INTO public.former_member_debts (household_id, original_amount) VALUES (pg_temp.h(1), 300), (pg_temp.h(2), 200);
END $$;

-- ── R3-01, husband present: a ledger with every kind of row ─────────────────────────────────
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.repay(1, 1, 2, '100', 2, 1);
    PERFORM pg_temp.keep('p_h', pg_temp.j(v_res, 'reimbursement_id'));
    v_res := pg_temp.req(2, 1, '50', 2);
    PERFORM pg_temp.keep('r_pend', pg_temp.j(v_res, 'request_id'));
    v_res := pg_temp.req(2, 1, '30', 3);
    PERFORM pg_temp.keep('r_dec', pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('setup: the husband declines', pg_temp.j(pg_temp.decline(1, 1, pg_temp.id('r_dec'), 'T62 secret reason'), 'outcome'), 'declined');
    v_res := pg_temp.req(3, 1, '20', 4);
    PERFORM pg_temp.keep('r_w2', pg_temp.j(v_res, 'request_id'));
    v_res := pg_temp.repay(1, 1, 2, '20', 1, 5);
    PERFORM pg_temp.keep('p_pool', pg_temp.j(v_res, 'reimbursement_id'));
    v_res := pg_temp.fpay(1, 1, '50', 2, 6);
    PERFORM pg_temp.keep('e_h', pg_temp.j(v_res, 'event_id'));
    PERFORM pg_temp.check('setup: her ledger', pg_temp.led_all(2), '2/2/1');
    PERFORM pg_temp.check('setup: the record', pg_temp.fmd_all(1), '1/1');
    PERFORM pg_temp.check('setup: what is owed', pg_temp.owed_api(1, 1, 2), '880.00');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.check('setup F1', SQLERRM, 'ok');
END $$;

-- ── R3-01, husband present: who reads ───────────────────────────────────────────────────────
DO $$
DECLARE
    v_who record;
BEGIN
    -- The wife and the husband read her ledger; the record is the husband's alone.
    PERFORM pg_temp.check('present: the wife reads her ledger', pg_temp.led(2, 2), pg_temp.led_all(2));
    PERFORM pg_temp.check('present: the wife reads what is owed', pg_temp.owed_as(2, 1, 2), '880.00');
    PERFORM pg_temp.check('present: the wife does not read the record', pg_temp.fmd(2, 1), '0/0');
    PERFORM pg_temp.check('present: the husband reads her ledger', pg_temp.led(1, 2), pg_temp.led_all(2));
    PERFORM pg_temp.check('present: the husband reads what is owed', pg_temp.owed_as(1, 1, 2), '880.00');
    PERFORM pg_temp.check('present: the husband reads the record', pg_temp.fmd(1, 1), '1/1');
    PERFORM pg_temp.check('present: the API reads for the husband', pg_temp.owed_api(1, 1, 2), '880.00');
    -- Nobody else: no row, no total, no request, no decline reason, no record.
    FOR v_who IN SELECT * FROM (VALUES (3, 'a co-wife'), (4, 'a member'), (5, 'an admin who is not a wife'),
                                       (6, 'a wife who is an admin')) AS x(n, label) LOOP
        PERFORM pg_temp.check('present: ' || v_who.label || ' reads none of her ledger', pg_temp.led(v_who.n, 2), '0/0/0');
        PERFORM pg_temp.check('present: ' || v_who.label || ' reads no total', pg_temp.owed_as(v_who.n, 1, 2), 'ERR:forbidden');
        PERFORM pg_temp.check('present: ' || v_who.label || ' reads no total through the API', pg_temp.owed_api(v_who.n, 1, 2), 'ERR:forbidden');
        PERFORM pg_temp.check('present: ' || v_who.label || ' reads no record', pg_temp.fmd(v_who.n, 1), '0/0');
    END LOOP;
    PERFORM pg_temp.check('present: no decline reason for the co-wife',
        pg_temp.call(pg_temp.u(3), NULL, format('SELECT count(*)::text FROM public.spouse_reimbursement_request_outcomes WHERE reason IS NOT NULL AND request_id = %L', pg_temp.id('r_dec'))), '0');
    -- A wife reads her own, never a co-wife's.
    PERFORM pg_temp.check('present: the co-wife reads her own request', pg_temp.led(3, 3), '0/1/0');
    PERFORM pg_temp.check('present: the wife does not read the co-wife''s', pg_temp.led(2, 3), '0/0/0');
    PERFORM pg_temp.check('present: the wife reads no total of the co-wife', pg_temp.owed_as(2, 1, 3), 'ERR:forbidden');
END $$;

-- ── R3-01, husband present: who acts ────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('present: an admin who is not a wife repays from his account', pg_temp.repay(5, 1, 2, '10', 3, 101), 'ERR:forbidden');
    PERFORM pg_temp.check('present: an admin who is not a wife repays from the pool', pg_temp.repay(5, 1, 2, '10', 1, 102), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a member repays', pg_temp.repay(4, 1, 2, '10', 4, 103), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a co-wife repays', pg_temp.repay(3, 1, 2, '10', 7, 104), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a wife-admin repays', pg_temp.repay(6, 1, 2, '10', 6, 105), 'ERR:forbidden');
    PERFORM pg_temp.check('present: the wife records', pg_temp.repay(2, 1, 2, '10', 5, 106), 'ERR:wife_must_request');
    PERFORM pg_temp.check('present: an admin who is not a wife approves', pg_temp.approve(5, 1, pg_temp.id('r_pend'), 3, 107), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a wife-admin approves', pg_temp.approve(6, 1, pg_temp.id('r_pend'), 6, 108), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a member approves', pg_temp.approve(4, 1, pg_temp.id('r_pend'), 4, 109), 'ERR:forbidden');
    PERFORM pg_temp.check('present: an admin who is not a wife declines', pg_temp.decline(5, 1, pg_temp.id('r_pend'), 'no'), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a wife-admin declines', pg_temp.decline(6, 1, pg_temp.id('r_pend'), 'no'), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a co-wife cancels her request', pg_temp.cancel(3, 1, pg_temp.id('r_pend')), 'ERR:forbidden');
    PERFORM pg_temp.check('present: an admin who is not a wife reverses the pool repayment', pg_temp.rev(5, 1, pg_temp.id('p_pool'), 110), 'ERR:forbidden');
    PERFORM pg_temp.check('present: an admin reverses the husband''s own repayment', pg_temp.rev(5, 1, pg_temp.id('p_h'), 111), 'ERR:account_forbidden');
    PERFORM pg_temp.check('present: an admin who is not a wife pays the record', pg_temp.fpay(5, 1, '10', 3, 112), 'ERR:forbidden');
    PERFORM pg_temp.check('present: an admin who is not a wife waives the record', pg_temp.waive(5, 1, 113), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a member pays the record', pg_temp.fpay(4, 1, '10', 4, 114), 'ERR:forbidden');
    PERFORM pg_temp.check('present: a wife-admin waives the record', pg_temp.waive(6, 1, 115), 'ERR:forbidden');
    PERFORM pg_temp.check('present: an admin reverses the husband''s record payment', pg_temp.frev(5, 1, pg_temp.id('e_h'), 116), 'ERR:account_forbidden');
    PERFORM pg_temp.check('present: nothing moved', pg_temp.bal(1) || '/' || pg_temp.bal(3) || '/' || pg_temp.bal(4) || '/' || pg_temp.bal(6),
                          '4980.00/5000.00/1000.00/1000.00');
    PERFORM pg_temp.check('present: still owed', pg_temp.owed_api(1, 1, 2), '880.00');
    PERFORM pg_temp.check('present: the record unchanged', pg_temp.state(1), '300.00/50.00/open/true');
END $$;

-- ── R3-01, husband gone (he left the household) ─────────────────────────────────────────────
DO $$
DECLARE
    v_who record;
    v_res text;
BEGIN
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(1);
    PERFORM pg_temp.check('gone: no provider', (SELECT (nafaqah_provider_user_id IS NULL)::text FROM public.households WHERE id = pg_temp.h(1)), 'true');

    -- Reads: the wife hers; an admin who is not a wife hers and the record; nobody else.
    PERFORM pg_temp.check('gone: the wife reads her ledger', pg_temp.led(2, 2), pg_temp.led_all(2));
    PERFORM pg_temp.check('gone: the wife does not read the record', pg_temp.fmd(2, 1), '0/0');
    PERFORM pg_temp.check('gone: an admin who is not a wife reads her ledger', pg_temp.led(5, 2), pg_temp.led_all(2));
    PERFORM pg_temp.check('gone: an admin who is not a wife reads what is owed', pg_temp.owed_as(5, 1, 2), '880.00');
    PERFORM pg_temp.check('gone: an admin who is not a wife reads the co-wife''s too', pg_temp.led(5, 3), pg_temp.led_all(3));
    PERFORM pg_temp.check('gone: an admin who is not a wife reads the record', pg_temp.fmd(5, 1), '1/1');
    PERFORM pg_temp.check('gone: the husband who left reads none of it', pg_temp.led(1, 2), '0/0/0');
    PERFORM pg_temp.check('gone: the husband who left reads no total', pg_temp.owed_api(1, 1, 2), 'ERR:42501');
    FOR v_who IN SELECT * FROM (VALUES (3, 'a co-wife'), (4, 'a member'), (6, 'a wife who is an admin')) AS x(n, label) LOOP
        PERFORM pg_temp.check('gone: ' || v_who.label || ' reads none of her ledger', pg_temp.led(v_who.n, 2), '0/0/0');
        PERFORM pg_temp.check('gone: ' || v_who.label || ' reads no total', pg_temp.owed_as(v_who.n, 1, 2), 'ERR:forbidden');
        PERFORM pg_temp.check('gone: ' || v_who.label || ' reads no record', pg_temp.fmd(v_who.n, 1), '0/0');
    END LOOP;

    -- Acts: an admin who is not a wife settles; a wife-admin, a co-wife and a member never.
    v_res := pg_temp.approve(5, 1, pg_temp.id('r_pend'), 1, 11);
    PERFORM pg_temp.check('gone: an admin who is not a wife approves her pending request from the pool', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('ap_c', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('gone: who paid the approval', pg_temp.payer(pg_temp.id('ap_c')), pg_temp.u(5)::text);
    v_res := pg_temp.repay(5, 1, 2, '10', 3, 12);
    PERFORM pg_temp.check('gone: an admin who is not a wife records a repayment from his account', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('p_c', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('gone: an admin who is not a wife reverses the husband''s pool repayment',
        pg_temp.j(pg_temp.rev(5, 1, pg_temp.id('p_pool'), 13), 'kind'), 'reversal');
    PERFORM pg_temp.check('gone: never the husband''s personal account', pg_temp.rev(5, 1, pg_temp.id('p_h'), 14), 'ERR:account_forbidden');
    PERFORM pg_temp.check('gone: the pool after the approval and the reversal', pg_temp.bal(1), '4950.00');
    v_res := pg_temp.req(2, 1, '5', 15);
    PERFORM pg_temp.keep('r2', pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('gone: a wife-admin approves', pg_temp.approve(6, 1, pg_temp.id('r2'), 6, 16), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a member approves', pg_temp.approve(4, 1, pg_temp.id('r2'), 4, 17), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a co-wife declines', pg_temp.decline(3, 1, pg_temp.id('r2'), 'no'), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a wife-admin repays from the pool', pg_temp.repay(6, 1, 2, '1', 1, 18), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a member repays', pg_temp.repay(4, 1, 2, '1', 4, 19), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a wife-admin reverses', pg_temp.rev(6, 1, pg_temp.id('p_c'), 20), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: an admin who is not a wife declines',
        pg_temp.j(pg_temp.decline(5, 1, pg_temp.id('r2'), 'T62 gone reason'), 'outcome'), 'declined');
    -- The former member's record.
    v_res := pg_temp.fpay(5, 1, '30', 3, 21);
    PERFORM pg_temp.check('gone: an admin who is not a wife pays the record', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('e_c', pg_temp.j(v_res, 'event_id'));
    PERFORM pg_temp.check('gone: never from the husband''s personal account', pg_temp.frev(5, 1, pg_temp.id('e_h'), 22), 'ERR:account_forbidden');
    PERFORM pg_temp.check('gone: a member pays the record', pg_temp.fpay(4, 1, '1', 4, 23), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a co-wife pays the record', pg_temp.fpay(3, 1, '1', 7, 24), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: a wife-admin waives the record', pg_temp.waive(6, 1, 25), 'ERR:forbidden');
    PERFORM pg_temp.check('gone: he reverses his own record payment', pg_temp.j(pg_temp.frev(5, 1, pg_temp.id('e_c'), 26), 'success'), 'true');
    PERFORM pg_temp.check('gone: an admin who is not a wife waives the record', pg_temp.waive2(5, 1, 27), 'waived');
    PERFORM pg_temp.check('gone: what is owed after the approval and his repayment', pg_temp.owed_api(5, 1, 2), '840.00');
    PERFORM pg_temp.check('gone: the wife reads the same', pg_temp.owed_as(2, 1, 2), '840.00');
    PERFORM pg_temp.check('gone: pending fits', pg_temp.over(), 'none');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.check('husband gone (left)', SQLERRM, 'ok');
END $$;

-- ── R3-01: a new husband takes the ledger back; a personal repayment stays its owner's ─────
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.repay(5, 1, 2, '5', 3, 31);
    PERFORM pg_temp.keep('p_c2', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('back: the admin names a new husband',
        (pg_temp.call(pg_temp.u(5), NULL, format('SELECT public.set_nafaqah_provider(%L, %L, NULL)::text', pg_temp.h(1), pg_temp.u(4))) LIKE 'ERR:%')::text, 'false');
    PERFORM pg_temp.check('back: the admin no longer reads her ledger', pg_temp.led(5, 2), '0/0/0');
    PERFORM pg_temp.check('back: the admin no longer reads the record', pg_temp.fmd(5, 1), '0/0');
    PERFORM pg_temp.check('back: the new husband reads her ledger', pg_temp.led(4, 2), pg_temp.led_all(2));
    PERFORM pg_temp.check('back: the new husband reads the record', pg_temp.fmd(4, 1), pg_temp.fmd_all(1));
    PERFORM pg_temp.check('back: the admin repays', pg_temp.repay(5, 1, 2, '1', 3, 32), 'ERR:forbidden');
    PERFORM pg_temp.check('back: the admin still reverses his own personal repayment (R1-07)',
        pg_temp.j(pg_temp.rev(5, 1, pg_temp.id('p_c2'), 33), 'kind'), 'reversal');
    PERFORM pg_temp.check('back: the new husband repays from his account', pg_temp.j(pg_temp.repay(4, 1, 2, '5', 4, 34), 'success'), 'true');
    PERFORM pg_temp.check('back: the new husband is no admin: never the pool', pg_temp.rev(4, 1, pg_temp.id('ap_c'), 35), 'ERR:account_forbidden');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.check('a new husband', SQLERRM, 'ok');
END $$;

-- ── R3-01, husband gone (his account deleted) ───────────────────────────────────────────────
DO $$
DECLARE
    v_res text;
BEGIN
    PERFORM pg_temp.check('deleted: setup repayment', pg_temp.j(pg_temp.repay(7, 2, 8, '100', 12, 41), 'success'), 'true');
    v_res := pg_temp.req(8, 2, '40', 42);
    PERFORM pg_temp.keep('q_v', pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('deleted: before, the admin reads nothing', pg_temp.led(9, 8), '0/0/0');
    PERFORM pg_temp.check('deleted: before, the admin reads no record', pg_temp.fmd(9, 2), '0/0');
    PERFORM pg_temp.purge(7);
    PERFORM pg_temp.check('deleted: her pending request closed', pg_temp.outcome(pg_temp.id('q_v')), 'closed/-');
    PERFORM pg_temp.check('deleted: the admin reads her ledger', pg_temp.led(9, 8), pg_temp.led_all(8));
    PERFORM pg_temp.check('deleted: the admin reads the record', pg_temp.fmd(9, 2), '1/0');
    PERFORM pg_temp.check('deleted: the wife reads hers', pg_temp.led(8, 8), pg_temp.led_all(8));
    v_res := pg_temp.req(8, 2, '60', 43);
    PERFORM pg_temp.keep('q_v2', pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('deleted: the admin approves her new request from the pool',
        pg_temp.j(pg_temp.approve(9, 2, pg_temp.id('q_v2'), 11, 44), 'success'), 'true');
    PERFORM pg_temp.check('deleted: the admin pays the record', pg_temp.j(pg_temp.fpay(9, 2, '50', 13, 45), 'remaining'), '150.00');
    PERFORM pg_temp.check('deleted: the admin waives the record', pg_temp.waive2(9, 2, 46), 'waived');
    PERFORM pg_temp.check('deleted: owed', pg_temp.owed_as(8, 2, 8), '240.00');
    -- R3-05: the purge still deleted the account his repayment left.
    PERFORM pg_temp.check('R3-05 the purge deletes an account with repayments',
        (SELECT count(*)::text FROM public.accounts WHERE id = pg_temp.a(12)), '0');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.check('husband gone (deleted)', SQLERRM, 'ok');
END $$;

-- ── R3-01: every read policy of her ledger and of the records states the rule itself ─────────
-- The outcomes' policy also reads the requests under theirs; each states the rule on its own, so
-- no table's rows depend on another table's policy staying as it is.
DO $$
BEGIN
    PERFORM pg_temp.check('R3-01 each ledger and record policy names the caller rule',
        (SELECT string_agg(tablename, ',' ORDER BY tablename) FROM pg_policies
         WHERE schemaname = 'public' AND cmd = 'SELECT'
           AND tablename IN ('spouse_reimbursements', 'spouse_reimbursement_requests', 'spouse_reimbursement_request_outcomes',
                             'former_member_debts', 'former_member_debt_events')
           AND qual LIKE '%nafaqah_caller_manages_ledgers%'),
        'former_member_debt_events,former_member_debts,spouse_reimbursement_request_outcomes,spouse_reimbursement_requests,spouse_reimbursements');
    PERFORM pg_temp.check('R3-01 and no other read policy on them',
        (SELECT count(*)::text FROM pg_policies
         WHERE schemaname = 'public'
           AND tablename IN ('spouse_reimbursements', 'spouse_reimbursement_requests', 'spouse_reimbursement_request_outcomes',
                             'former_member_debts', 'former_member_debt_events')), '5');
END $$;

-- ── R3-03: the amount-only payment stays the service role's ────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('R3-03 authenticated cannot execute the 6-argument payment',
        has_function_privilege('authenticated', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE')::text, 'false');
    PERFORM pg_temp.check('R3-03 anon cannot execute it',
        has_function_privilege('anon', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE')::text, 'false');
    PERFORM pg_temp.check('R3-03 the service role still can (it answers app_update_required)',
        pg_temp.svc(format('SELECT public.record_former_member_debt_payment(%L, %L, 1, %L, %L::uuid, %L)::text',
                           pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.k(51), pg_temp.u(5))), 'ERR:app_update_required');
    PERFORM pg_temp.check('R3-03 the 7-argument payment stays the clients''',
        has_function_privilege('authenticated', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid)', 'EXECUTE')::text, 'true');
END $$;

-- ── R3-04: both passes read the record of the URL's household ──────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('R3-04 no record read by id alone',
        (SELECT count(*)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace
           AND proname = 'reverse_former_member_debt_payment'
           AND prosrc ~ 'former_member_debts\s+WHERE\s+id\s*=\s*p_debt_id\s+FOR\s+UPDATE'), '0');
    PERFORM pg_temp.check('R3-04 the locked read names the household',
        (SELECT count(*)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace
           AND proname = 'reverse_former_member_debt_payment'
           AND prosrc ~ 'former_member_debts\s+WHERE\s+id\s*=\s*p_debt_id\s+AND\s+household_id\s*=\s*p_household_id\s+FOR\s+UPDATE'), '1');
END $$;

-- ── R3-05: an account a repayment or a reversal used is archived, not deleted ──────────────
DO $$
BEGIN
    PERFORM pg_temp.check('R3-05 his account a repayment left', pg_temp.del_acct(5, 3), 'ERR:account_has_repayments');
    PERFORM pg_temp.check('R3-05 still there', (SELECT count(*)::text FROM public.accounts WHERE id = pg_temp.a(3)), '1');
    PERFORM pg_temp.check('R3-05 the pool repayments and reversals used', pg_temp.del_acct(5, 1), 'ERR:account_has_repayments');
    PERFORM pg_temp.check('R3-05 the new husband''s account', pg_temp.del_acct(4, 4), 'ERR:account_has_repayments');
    PERFORM pg_temp.check('R3-05 an account never used for one deletes as before', pg_temp.del_acct(5, 8), '1');
    PERFORM pg_temp.check('R3-05 her own account deletes as before', pg_temp.del_acct(2, 5), '1');
    PERFORM pg_temp.check('R3-05 another member''s account is still not his to delete', pg_temp.del_acct(5, 6), '0');
    PERFORM pg_temp.check('R3-05 archiving it still works',
        pg_temp.call(pg_temp.u(5), NULL, format('WITH d AS (UPDATE public.accounts SET is_archived = true WHERE id = %L RETURNING 1) SELECT count(*)::text FROM d', pg_temp.a(3))), '1');
    PERFORM pg_temp.check('R3-05 and the archived one is still not deleted', pg_temp.del_acct(5, 3), 'ERR:account_has_repayments');
END $$;

DO $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(label || ': got ' || COALESCE(got, 'NULL') || ', expected ' || COALESCE(want, 'NULL'), E'\n' ORDER BY n)
    INTO v_list FROM pg_temp.fails;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION E'% check(s) failed:\n%', (SELECT count(*) FROM pg_temp.fails), v_list;
    END IF;
    RAISE NOTICE 'PASSED: the Round 3 fixes of tracked repayments (R3-01, R3-03, R3-04, R3-05).';
END $$;

ROLLBACK;
