-- ============================================================================
-- Test 60: Round 2 review fixes of tracked repayments (owner decisions 2026-11-06)
--
-- Migrations: 20261105001200_account_deletion_former_member_debt.sql,
--             20261105001300_wife_repayment_debit.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Verifies, one finding each (every check is collected, so a failing run lists them all):
--   R2-01  A request key names one operation in a household, whatever the path: a repayment, an
--          approval, a reversal, her request, a former member's payment, waiver or reversal, on any
--          of the household's records. The same key on another path or record is
--          request_key_reused and moves nothing; the exact same call is still a replay; another
--          household may use the same key.
--   R2-04  A family does not become roommates while a former member's record is open
--          (type_change_blocked, DETAIL former_member_debt); once it is paid or waived, it may.
--   R2-06  A replay after the account it was paid from is deleted answers the stored answer; the
--          same key with another account is still request_key_reused.
-- The races (R2-05, R2-07, R2-08, and R2-01 under concurrency) are in test 61.
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
AS $$ SELECT ('e6000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e60a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e60c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e60e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
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
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T60 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE p_type END, p_balance, p_pool, false, 'SAR');
END;
$$;

CREATE FUNCTION pg_temp.advance(p_hh int, p_wife int, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'T60 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me',
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


-- A call that answers its HINT and DETAIL when refused.
CREATE FUNCTION pg_temp.call_detail(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_val text;
    v_hint text;
    v_detail text;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_detail = PG_EXCEPTION_DETAIL;
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || COALESCE(NULLIF(v_hint, ''), SQLSTATE) || ':' || COALESCE(v_detail, '');
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
CREATE FUNCTION pg_temp.to_roommates(p_actor int, p_hh int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call_detail(pg_temp.u(p_actor),
        format('SELECT (public.set_household_type(%L, %L, NULL) ->> %L)', pg_temp.h(p_hh), 'roommates', 'household_type'));
$$;

-- A former member's record by its own id (a household may keep two: one per deleted wife).
CREATE FUNCTION pg_temp.fpayd(p_actor int, p_hh int, p_debt uuid, p_amount text, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(p_hh), p_debt, p_amount, 'cash', pg_temp.k(p_key), pg_temp.a(p_account)));
$$;
CREATE FUNCTION pg_temp.frevd(p_actor int, p_hh int, p_debt uuid, p_event uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.reverse_former_member_debt_payment(%L, %L, %L, %L::uuid, NULL)::text',
               pg_temp.h(p_hh), p_debt, p_event, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.waived(p_actor int, p_hh int, p_debt uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.waive_former_member_debt(%L, %L, %L::uuid, NULL)::text', pg_temp.h(p_hh), p_debt, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.dstate(p_debt uuid) RETURNS text LANGUAGE sql AS $$
    SELECT d.paid_amount::text || '/' || d.status FROM public.former_member_debts d WHERE d.id = p_debt;
$$;
CREATE FUNCTION pg_temp.debt_of(p_hh int, p_amount numeric) RETURNS uuid LANGUAGE sql AS $$
    SELECT id FROM public.former_member_debts WHERE household_id = pg_temp.h(p_hh) AND original_amount = p_amount;
$$;
CREATE FUNCTION pg_temp.moves() RETURNS text LANGUAGE sql AS $$
    SELECT (SELECT count(*) FROM public.account_transfers WHERE household_id::text LIKE 'e60a%')::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursements WHERE household_id::text LIKE 'e60a%')::text
        || '/' || (SELECT count(*) FROM public.former_member_debt_events e JOIN public.former_member_debts d ON d.id = e.debt_id
                   WHERE d.household_id::text LIKE 'e60a%')::text
        || '/' || (SELECT count(*) FROM public.spouse_reimbursement_requests WHERE household_id::text LIKE 'e60a%')::text;
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider, wives W1(2) and W2(3), co-admin C(4). Two former
--        members' records (two wives deleted earlier): 300 and 200.
-- F2(2): husband H2(7) admin and provider, wife W(8).
-- F3(3): admin X(9), the provider, and no wife now: an open record of 50.
-- F4(4): admin Z(10), the provider, and no wife now: an open record of 40.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't60-' || n || '@test.local', jsonb_build_object('display_name', 'T60 User ' || n)
    FROM generate_series(1, 10) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T60 H1', 'T60CODE000000001', 'family'),
        (pg_temp.h(2), 'T60 H2', 'T60CODE000000002', 'family'),
        (pg_temp.h(3), 'T60 H3', 'T60CODE000000003', 'family'),
        (pg_temp.h(4), 'T60 H4', 'T60CODE000000004', 'family');
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(7, 2, 'admin', 'provider');
    PERFORM pg_temp.join(8, 2, 'member', 'spouse');
    PERFORM pg_temp.join(9, 3, 'admin', 'provider');
    PERFORM pg_temp.join(10, 4, 'admin', 'provider');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(7), nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);
    UPDATE public.households SET owner_user_id = pg_temp.u(9), nafaqah_provider_user_id = pg_temp.u(9) WHERE id = pg_temp.h(3);
    UPDATE public.households SET owner_user_id = pg_temp.u(10), nafaqah_provider_user_id = pg_temp.u(10) WHERE id = pg_temp.h(4);

    PERFORM pg_temp.acct(1, 1, 1, true, 5000);    -- F1 pool
    PERFORM pg_temp.acct(2, 1, 1, false, 1000);   -- H
    PERFORM pg_temp.acct(9, 1, 1, false, 500);    -- H, a spare account he later deletes
    PERFORM pg_temp.acct(11, 2, 7, false, 5000);  -- H2
    PERFORM pg_temp.acct(41, 4, 10, false, 100);  -- Z

    PERFORM pg_temp.advance(1, 2, 600);
    PERFORM pg_temp.advance(1, 3, 100);
    PERFORM pg_temp.advance(2, 8, 600);
    INSERT INTO public.former_member_debts (household_id, original_amount) VALUES
        (pg_temp.h(1), 300), (pg_temp.h(1), 200), (pg_temp.h(3), 50), (pg_temp.h(4), 40);
END $$;

-- ── R2-01: one key, one operation, whatever the path ─────────────────────────────────────────
DO $$
DECLARE
    v_d1 uuid := pg_temp.debt_of(1, 300);
    v_d2 uuid := pg_temp.debt_of(1, 200);
    v_res text;
    v_req uuid;
    v_moves text;
BEGIN
    -- A repayment with key 1, then key 1 on every other path.
    v_res := pg_temp.repay(1, 1, 2, '100', 2, 1);
    PERFORM pg_temp.check('R2-01 a repayment', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('rep1', pg_temp.j(v_res, 'reimbursement_id'));
    v_moves := pg_temp.moves();
    PERFORM pg_temp.check('R2-01 its key for a former member payment', pg_temp.fpayd(1, 1, v_d1, '100', 2, 1), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 its key for a waiver', pg_temp.waived(1, 1, v_d1, 1), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 its key for the co-wife', pg_temp.repay(1, 1, 3, '100', 2, 1), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 its key for her request', pg_temp.req(2, 1, '5', 1), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 nothing moved under the reused key', pg_temp.moves(), v_moves);
    PERFORM pg_temp.check('R2-01 his account moved once', pg_temp.bal(2), '900.00');
    PERFORM pg_temp.check('R2-01 the record is untouched', pg_temp.dstate(v_d1), '0.00/open');

    -- A former member's payment with key 2, then key 2 on the household's other record.
    v_res := pg_temp.fpayd(1, 1, v_d1, '50', 2, 2);
    PERFORM pg_temp.check('R2-01 a former member payment', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('ev2', pg_temp.j(v_res, 'event_id'));
    v_moves := pg_temp.moves();
    PERFORM pg_temp.check('R2-01 its key on the other record', pg_temp.fpayd(1, 1, v_d2, '50', 2, 2), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 its key to waive the other record', pg_temp.waived(1, 1, v_d2, 2), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 its key for a repayment', pg_temp.repay(1, 1, 2, '50', 2, 2), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 its key, another admin, the other record, the pool', pg_temp.fpayd(4, 1, v_d2, '50', 1, 2), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 nothing moved under it', pg_temp.moves(), v_moves);
    PERFORM pg_temp.check('R2-01 the other record is untouched', pg_temp.dstate(v_d2), '0.00/open');
    PERFORM pg_temp.check('R2-01 his account moved once more', pg_temp.bal(2), '850.00');

    -- Her request with key 3; its key for his approval or a repayment.
    v_res := pg_temp.req(2, 1, '10', 3);
    v_req := pg_temp.uid(pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('R2-01 her request', pg_temp.j(v_res, 'status'), 'pending');
    PERFORM pg_temp.check('R2-01 her request''s key to approve it', pg_temp.approve(1, 1, v_req, 2, 3), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 the key of a payment to approve it', pg_temp.approve(1, 1, v_req, 2, 2), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 her request''s key for a former member payment', pg_temp.fpayd(1, 1, v_d2, '10', 2, 3), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 her request''s key for the co-wife''s request', pg_temp.req(3, 1, '10', 3), 'ERR:request_key_reused');
    v_res := pg_temp.approve(1, 1, v_req, 2, 4);
    PERFORM pg_temp.check('R2-01 approved with a key of its own', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.check('R2-01 the approval''s key for the co-wife''s request', pg_temp.req(3, 1, '10', 4), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 the approval''s key for a waiver', pg_temp.waived(1, 1, v_d2, 4), 'ERR:request_key_reused');

    -- Reversals: each takes a key no other operation used.
    v_moves := pg_temp.moves();
    PERFORM pg_temp.check('R2-01 a reversal with a payment''s key', pg_temp.rev(1, 1, pg_temp.id('rep1'), 2), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 a former member reversal with a repayment''s key', pg_temp.frevd(1, 1, v_d1, pg_temp.id('ev2'), 1), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 a former member reversal with her request''s key', pg_temp.frevd(1, 1, v_d1, pg_temp.id('ev2'), 3), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 nothing moved under them', pg_temp.moves(), v_moves);
    PERFORM pg_temp.check('R2-01 the reversal', pg_temp.j(pg_temp.rev(1, 1, pg_temp.id('rep1'), 5), 'success'), 'true');
    PERFORM pg_temp.check('R2-01 the former member reversal with the reversal''s key', pg_temp.frevd(1, 1, v_d1, pg_temp.id('ev2'), 5), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 the former member reversal', pg_temp.j(pg_temp.frevd(1, 1, v_d1, pg_temp.id('ev2'), 6), 'success'), 'true');
    PERFORM pg_temp.check('R2-01 a repayment with that reversal''s key', pg_temp.repay(1, 1, 2, '5', 2, 6), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 a waiver with it', pg_temp.waived(1, 1, v_d1, 6), 'ERR:request_key_reused');
    -- 1000 - 100 - 50 - 10 + 100 + 50.
    PERFORM pg_temp.check('R2-01 his account: each operation moved once', pg_temp.bal(2), '990.00');
    PERFORM pg_temp.check('R2-01 the pool never moved', pg_temp.bal(1), '5000.00');

    -- The exact same call is still a replay on every path.
    PERFORM pg_temp.check('R2-01 replay of the repayment', pg_temp.j(pg_temp.repay(1, 1, 2, '100', 2, 1), 'replayed'), 'true');
    PERFORM pg_temp.check('R2-01 replay of the former member payment', pg_temp.j(pg_temp.fpayd(1, 1, v_d1, '50', 2, 2), 'replayed'), 'true');
    PERFORM pg_temp.check('R2-01 replay of her request', pg_temp.j(pg_temp.req(2, 1, '10', 3), 'replayed'), 'true');
    PERFORM pg_temp.check('R2-01 replay of the approval', pg_temp.j(pg_temp.approve(1, 1, v_req, 2, 4), 'replayed'), 'true');
    PERFORM pg_temp.check('R2-01 replay of the reversal', pg_temp.j(pg_temp.rev(1, 1, pg_temp.id('rep1'), 5), 'replayed'), 'true');
    PERFORM pg_temp.check('R2-01 replay of the former member reversal', pg_temp.j(pg_temp.frevd(1, 1, v_d1, pg_temp.id('ev2'), 6), 'replayed'), 'true');
    PERFORM pg_temp.check('R2-01 replays moved nothing', pg_temp.bal(2), '990.00');

    -- A waiver's key, then a payment with it.
    PERFORM pg_temp.check('R2-01 a waiver', pg_temp.j(pg_temp.waived(1, 1, v_d2, 7), 'status'), 'waived');
    PERFORM pg_temp.check('R2-01 the waiver''s key for a payment of the other record', pg_temp.fpayd(1, 1, v_d1, '10', 2, 7), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-01 replay of the waiver', pg_temp.j(pg_temp.waived(1, 1, v_d2, 7), 'replayed'), 'true');

    -- Keys are per household: another household may use the same one.
    PERFORM pg_temp.check('R2-01 key 1 in another household', pg_temp.j(pg_temp.repay(7, 2, 8, '10', 11, 1), 'success'), 'true');
    PERFORM pg_temp.check('R2-01 at the end, every account balances', pg_temp.bal(2) || '/' || pg_temp.bal(11), '990.00/4990.00');
END $$;

-- ── R2-04: no switch to roommates while a former member's record is open ─────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('R2-04 an open record blocks the switch', pg_temp.to_roommates(9, 3), 'ERR:type_change_blocked:former_member_debt');
    PERFORM pg_temp.check('R2-04 the household stays a family',
        (SELECT household_type FROM public.households WHERE id = pg_temp.h(3)), 'family');
    PERFORM pg_temp.check('R2-04 and the record open', pg_temp.state(3), '50.00/0.00/open/true');
    -- Waived: it no longer blocks.
    PERFORM pg_temp.check('R2-04 waived', pg_temp.j(pg_temp.waive(9, 3, 401), 'status'), 'waived');
    PERFORM pg_temp.check('R2-04 then the switch', pg_temp.to_roommates(9, 3), 'roommates');
    -- Paid in full: it no longer blocks either.
    PERFORM pg_temp.check('R2-04 blocked before the payment', pg_temp.to_roommates(10, 4), 'ERR:type_change_blocked:former_member_debt');
    PERFORM pg_temp.check('R2-04 paid in full', pg_temp.j(pg_temp.fpay(10, 4, '40', 41, 402), 'status'), 'settled');
    PERFORM pg_temp.check('R2-04 then the switch', pg_temp.to_roommates(10, 4), 'roommates');
    -- With a wife still a member, every blocker is named.
    PERFORM pg_temp.check('R2-04 a wife and an open record', pg_temp.to_roommates(1, 1),
        'ERR:type_change_blocked:spouse_member,nafaqah_expenses,reimbursements,former_member_debt');
END $$;

-- ── R2-06: a replay after the paying account is deleted ──────────────────────────────────────
DO $$
DECLARE
    v_d1 uuid := pg_temp.debt_of(1, 300);
    v_res text;
    v_req uuid;
BEGIN
    PERFORM pg_temp.keep('r6rep', pg_temp.repay(1, 1, 2, '20', 9, 600));
    PERFORM pg_temp.keep('r6fmd', pg_temp.fpayd(1, 1, v_d1, '20', 9, 601));
    v_req := pg_temp.uid(pg_temp.j(pg_temp.req(3, 1, '15', 602), 'request_id'));
    PERFORM pg_temp.keep('r6app', pg_temp.approve(1, 1, v_req, 9, 603));
    PERFORM pg_temp.check('R2-06 three payments from the spare account', pg_temp.bal(9), '445.00');
    PERFORM pg_temp.check('R2-06 the owner deletes it',
        pg_temp.call(pg_temp.u(1), NULL, format($q$DELETE FROM public.accounts WHERE id = %L RETURNING 'deleted'$q$, pg_temp.a(9))), 'deleted');

    v_res := pg_temp.repay(1, 1, 2, '20', 9, 600);
    PERFORM pg_temp.check('R2-06 the repayment replays', pg_temp.j(v_res, 'replayed'), 'true');
    PERFORM pg_temp.check('R2-06 with its stored answer', pg_temp.j(v_res, 'account_id') || '/' || pg_temp.j(v_res, 'outstanding_after'),
        pg_temp.j(pg_temp.kept('r6rep'), 'account_id') || '/' || pg_temp.j(pg_temp.kept('r6rep'), 'outstanding_after'));
    v_res := pg_temp.fpayd(1, 1, v_d1, '20', 9, 601);
    PERFORM pg_temp.check('R2-06 the former member payment replays', pg_temp.j(v_res, 'replayed'), 'true');
    PERFORM pg_temp.check('R2-06 with its stored answer', pg_temp.j(v_res, 'account_id') || '/' || pg_temp.j(v_res, 'remaining'),
        pg_temp.j(pg_temp.kept('r6fmd'), 'account_id') || '/' || pg_temp.j(pg_temp.kept('r6fmd'), 'remaining'));
    v_res := pg_temp.approve(1, 1, v_req, 9, 603);
    PERFORM pg_temp.check('R2-06 the approval replays', pg_temp.j(v_res, 'replayed'), 'true');
    PERFORM pg_temp.check('R2-06 with its stored account', pg_temp.j(v_res, 'account_id'), pg_temp.a(9)::text);
    -- The same key with another account is still another call.
    PERFORM pg_temp.check('R2-06 the key with another account', pg_temp.repay(1, 1, 2, '20', 2, 600), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-06 the former member key with another account', pg_temp.fpayd(1, 1, v_d1, '20', 2, 601), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R2-06 the approval key with another account', pg_temp.approve(1, 1, v_req, 2, 603), 'ERR:request_key_reused');
    -- Nothing comes back to a deleted account.
    PERFORM pg_temp.check('R2-06 reversing it', pg_temp.rev(1, 1, pg_temp.uid(pg_temp.j(pg_temp.kept('r6rep'), 'reimbursement_id')), 604),
        'ERR:reversal_account_unavailable');
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
    RAISE NOTICE 'PASSED: the Round 2 fixes of tracked repayments (R2-01, R2-04, R2-06).';
END $$;

ROLLBACK;
