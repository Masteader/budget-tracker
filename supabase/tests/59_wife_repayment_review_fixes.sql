-- ============================================================================
-- Test 59: Round 1 review fixes of tracked repayments (owner decisions 2026-11-06)
--
-- Migrations: 20261105001200_account_deletion_former_member_debt.sql,
--             20261105001300_wife_repayment_debit.sql
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2
--
-- Verifies, one finding each (every check is collected, so a failing run lists them all):
--   R1-01  Only the husband (when he is gone, a household admin who is not a wife: review R3-01,
--          test 62) records, approves, declines, pays a former member's record, waives it or
--          reverses; a wife never does, even as an admin, for a co-wife or a former member; a
--          wife never pays from a pool. Where an admin acts below, the husband is gone (the
--          provider cleared for that step).
--   R1-03  A repayment, an approval or a smaller advance that leaves her pending requests above
--          what is owed closes the ones that no longer fit ('already_repaid', nothing moves):
--          kept oldest first while they fit, so the most recent close first and a later one that
--          still fits stays. Pending total <= owed after every step.
--   R1-04  The same key with a different amount, account, actor or kind: request_key_reused.
--   R1-05  A replay answers the stored outstanding_before / outstanding_after.
--   R1-07  (superseded by review R3B-06, test 67: only her ledger's manager reverses, a personal
--          account's repayment as its owner) A personal-account repayment is reversed by the account's owner while he is a member
--          and not a wife, whatever his role now; a pool repayment by the husband if he is an
--          admin (an admin who is not a wife when he is gone: review R3-01).
--   R1-08  The ledger records who actually paid; the purge still anonymises a deleted payer.
--   R1-13  Each debit and credit is labelled on the transfer row (purpose), which the account's
--          members read; a former member's line carries no text of hers.
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
AS $$ SELECT ('e5900000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e59a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e59c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e59e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
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
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T59 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE p_type END, p_balance, p_pool, false, 'SAR');
END;
$$;

CREATE FUNCTION pg_temp.advance(p_hh int, p_wife int, p_amount numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'T59 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me',
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

-- Her wife account in household p_hh (20261105001300, section 12): every repayment to her credits
-- one, and her request names one. Made for every wife of the fixtures, owned by the husband.
CREATE FUNCTION pg_temp.wa(p_hh int, p_wife int) RETURNS uuid LANGUAGE sql AS $$
    SELECT id FROM public.accounts
    WHERE household_id = pg_temp.h(p_hh) AND account_type = 'wife' AND assigned_wife_id = pg_temp.u(p_wife)
    ORDER BY is_archived, created_at, id LIMIT 1
$$;
-- The calls, as user p_actor (authenticated). Account 0 = none.
CREATE FUNCTION pg_temp.req(p_actor int, p_hh int, p_amount text, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.request_spouse_reimbursement(%L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(p_hh), p_amount, 'cash', pg_temp.k(p_key), pg_temp.wa(p_hh, p_actor)));
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
        format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid, %L::uuid)::text',
               pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'bank_transfer',
               CASE WHEN p_account = 0 THEN NULL ELSE pg_temp.a(p_account) END, pg_temp.k(p_key), pg_temp.wa(p_hh, p_wife)));
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

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): primary admin A(5); the husband H(1) is the provider and NOT an admin; wife W1(2);
--        wife W2(3) is also an admin; co-admin C(4); member K(6). A former member's record of 300.
-- F2(2): husband H2(7) admin and provider, wife W(8), co-admin C2(9). A former member's record of 200.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't59-' || n || '@test.local', jsonb_build_object('display_name', 'T59 User ' || n)
    FROM generate_series(1, 9) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type) VALUES
        (pg_temp.h(1), 'T59 H1', 'T59CODE000000001', 'family'),
        (pg_temp.h(2), 'T59 H2', 'T59CODE000000002', 'family');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(1, 1, 'member', 'provider');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(4, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(6, 1, 'member', 'family_member');
    PERFORM pg_temp.join(7, 2, 'admin', 'provider');
    PERFORM pg_temp.join(8, 2, 'member', 'spouse');
    PERFORM pg_temp.join(9, 2, 'admin', 'family_member');
    UPDATE public.households SET owner_user_id = pg_temp.u(5), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(7), nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);

    PERFORM pg_temp.acct(1, 1, 5, true, 5000);    -- F1 pool
    PERFORM pg_temp.acct(2, 1, 1, false, 1000);   -- H
    PERFORM pg_temp.acct(3, 1, 3, false, 1000);   -- W2 (wife and admin)
    PERFORM pg_temp.acct(4, 1, 2, false, 1000);   -- W1
    PERFORM pg_temp.acct(5, 1, 4, false, 1000);   -- C
    PERFORM pg_temp.acct(6, 1, 5, false, 1000);   -- A
    PERFORM pg_temp.acct(11, 2, 7, false, 5000);  -- H2
    PERFORM pg_temp.acct(12, 2, 7, false, 5000);  -- H2, a second account
    PERFORM pg_temp.acct(13, 2, 9, false, 5000);  -- C2
    PERFORM pg_temp.acct(14, 2, 7, true, 5000);   -- F2 pool

    PERFORM pg_temp.advance(1, 2, 600);
    PERFORM pg_temp.advance(1, 3, 100);
    PERFORM pg_temp.advance(2, 8, 600);
    INSERT INTO public.former_member_debts (household_id, original_amount) VALUES (pg_temp.h(1), 300), (pg_temp.h(2), 200);
END $$;

-- A wife account for every wife of the fixtures (20261105001300, section 12), owned by her husband
-- (the provider; else the primary admin), empty.
INSERT INTO public.accounts (household_id, owner_user_id, name, account_type, balance, is_shared_pool, assigned_wife_id)
SELECT m.household_id,
       COALESCE((SELECT p.user_id FROM public.household_memberships p
                 WHERE p.household_id = m.household_id AND p.user_id = h.nafaqah_provider_user_id),
                h.owner_user_id, m.user_id),
       'Her account', 'wife', 0, false, m.user_id
FROM public.household_memberships m
JOIN public.households h ON h.id = m.household_id
WHERE m.financial_role = 'spouse' AND h.id::text LIKE 'e59a%'
  AND NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.assigned_wife_id = m.user_id AND a.household_id = m.household_id);

-- ── R1-01: a wife never repays, approves, declines, pays a former member or reverses ─────────
DO $$
DECLARE
    v_res text;
    v_req uuid;
BEGIN
    PERFORM pg_temp.check('R1-01 wife-admin repays her co-wife from a pool', pg_temp.repay(3, 1, 2, '10', 1, 101), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 wife-admin repays her co-wife from her own account', pg_temp.repay(3, 1, 2, '10', 3, 102), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 the pool did not move', pg_temp.bal(1), '5000.00');
    PERFORM pg_temp.check('R1-01 her account did not move', pg_temp.bal(3), '1000.00');

    v_req := pg_temp.uid(pg_temp.j(pg_temp.req(2, 1, '20', 103), 'request_id'));
    PERFORM pg_temp.keep('w1_req', v_req::text);
    PERFORM pg_temp.check('R1-01 wife-admin approves her co-wife''s request from a pool', pg_temp.approve(3, 1, v_req, 1, 104), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 wife-admin approves it from her own account', pg_temp.approve(3, 1, v_req, 3, 105), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 wife-admin declines her co-wife''s request', pg_temp.decline(3, 1, v_req, 'no'), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 the request is still pending', pg_temp.outcome(v_req), 'pending');

    PERFORM pg_temp.check('R1-01 wife-admin pays a former member from a pool', pg_temp.fpay(3, 1, '10', 1, 106), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 wife-admin pays a former member from her own account', pg_temp.fpay(3, 1, '10', 3, 107), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 wife-admin records a former member''s waiver', pg_temp.waive(3, 1, 108), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 the record did not change', pg_temp.state(1), '300.00/0.00/open/true');
    PERFORM pg_temp.check('R1-01 the pool still did not move', pg_temp.bal(1), '5000.00');

    -- The account helper itself: a wife never pays from a pool, whatever her role.
    PERFORM pg_temp.check('R1-01 a pool is never a wife''s to pay from',
        pg_temp.raw(format('SELECT public.nafaqah_repayment_lock_account(%L, %L, %L)::text', pg_temp.h(1), pg_temp.u(3), pg_temp.a(1))),
        'ERR:account_forbidden');

    -- Those who may still do it: the husband; while he is there, no admin (review R3-01).
    v_res := pg_temp.repay(1, 1, 2, '10', 2, 111);   -- H, not an admin, from his own
    PERFORM pg_temp.check('R1-01 the husband pays from his own account', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('pH', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('R3-01 a non-wife admin, while the husband is there', pg_temp.repay(5, 1, 2, '10', 1, 109), 'ERR:forbidden');
    -- The husband gone (the provider cleared until the R1-07 section): the admins who are not wives.
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(1);
    v_res := pg_temp.repay(5, 1, 2, '10', 1, 110);   -- A, from the pool
    PERFORM pg_temp.check('R1-01 a non-wife admin pays from a pool', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('pA', pg_temp.j(v_res, 'reimbursement_id'));
    v_res := pg_temp.repay(4, 1, 2, '10', 5, 112);   -- C, co-admin, from his own
    PERFORM pg_temp.check('R1-01 a co-admin pays from his own account', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('pC', pg_temp.j(v_res, 'reimbursement_id'));

    PERFORM pg_temp.check('R1-01 wife-admin reverses a pool repayment', pg_temp.rev(3, 1, pg_temp.id('pA'), 113), 'ERR:forbidden');
    PERFORM pg_temp.check('R1-01 the pool keeps the repayment', pg_temp.bal(1), '4990.00');
END $$;

-- ── R1-08: the ledger records who actually paid ───────────────────────────────────────────────
DO $$
DECLARE
    v_res text;
    v_req uuid;
BEGIN
    PERFORM pg_temp.check('R1-08 the admin who paid from the pool', pg_temp.payer(pg_temp.id('pA')), pg_temp.u(5)::text);
    PERFORM pg_temp.check('R1-08 the husband who paid', pg_temp.payer(pg_temp.id('pH')), pg_temp.u(1)::text);
    PERFORM pg_temp.check('R1-08 the co-admin who paid', pg_temp.payer(pg_temp.id('pC')), pg_temp.u(4)::text);
    PERFORM pg_temp.check('R1-08 the answer names the payer', pg_temp.j(pg_temp.repay(4, 1, 2, '10', 5, 112), 'paid_by_user_id'), pg_temp.u(4)::text);

    v_req := pg_temp.uid(pg_temp.j(pg_temp.req(2, 1, '15', 114), 'request_id'));
    v_res := pg_temp.approve(4, 1, v_req, 5, 115);
    PERFORM pg_temp.keep('apC', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('R1-08 the co-admin who approved and paid', pg_temp.payer(pg_temp.id('apC')), pg_temp.u(4)::text);

    -- A former member's payment by C, before he loses his admin rights below.
    v_res := pg_temp.fpay(4, 1, '20', 5, 117);
    PERFORM pg_temp.check('R1-08 a co-admin pays a former member''s record', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.keep('fC', pg_temp.j(v_res, 'event_id'));
END $$;

-- ── R1-07, as review R3B-06 left it: the owner of the account reverses, while he manages her ledger
DO $$
DECLARE
    v_res text;
BEGIN
    -- The husband is back (the provider again) and C a member: C no longer manages her ledger, so
    -- he does not reverse even his own repayment (review R3B-06, superseding R1-07).
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.household_memberships SET role = 'member' WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(4);
    PERFORM pg_temp.check('R3B-06 a former co-admin does not reverse his own repayment', pg_temp.rev(4, 1, pg_temp.id('pC'), 120), 'ERR:forbidden');
    PERFORM pg_temp.check('R3B-06 nor his former-member payment', pg_temp.frev(4, 1, pg_temp.id('fC'), 121), 'ERR:forbidden');
    PERFORM pg_temp.check('R3B-06 his account unchanged', pg_temp.bal(5), '955.00');
    -- Managing it again (the husband gone, C an admin), he reverses his own.
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(1);
    UPDATE public.household_memberships SET role = 'admin' WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(4);
    v_res := pg_temp.rev(4, 1, pg_temp.id('pC'), 128);
    PERFORM pg_temp.check('R1-07 a former co-admin reverses his own repayment', pg_temp.j(v_res, 'kind'), 'reversal');
    PERFORM pg_temp.check('R1-07 his account is credited back', pg_temp.bal(5), '965.00');
    PERFORM pg_temp.check('R1-08 the reversal names the original payer',
        pg_temp.payer(CASE WHEN v_res LIKE 'ERR:%' THEN NULL ELSE pg_temp.uid(pg_temp.j(v_res, 'reimbursement_id')) END), pg_temp.u(4)::text);
    v_res := pg_temp.frev(4, 1, pg_temp.id('fC'), 129);
    PERFORM pg_temp.check('R1-07 a former co-admin reverses his former-member payment', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.check('R1-07 the record is whole again', pg_temp.state(1), '300.00/0.00/open/true');
    PERFORM pg_temp.check('R1-07 and his account too', pg_temp.bal(5), '985.00');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.household_memberships SET role = 'member' WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(4);

    -- The husband, once someone else is the provider: not even his own (review R3B-06); as the
    -- provider again, he reverses it.
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(6) WHERE id = pg_temp.h(1);
    PERFORM pg_temp.check('R3B-06 a former husband does not reverse his own repayment', pg_temp.rev(1, 1, pg_temp.id('pH'), 122), 'ERR:forbidden');
    PERFORM pg_temp.check('R3B-06 his account unchanged', pg_temp.bal(2), '990.00');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    v_res := pg_temp.rev(1, 1, pg_temp.id('pH'), 130);
    PERFORM pg_temp.check('R1-07 the husband reverses his own repayment', pg_temp.j(v_res, 'kind'), 'reversal');
    PERFORM pg_temp.check('R1-07 his account is credited back', pg_temp.bal(2), '1000.00');

    -- A pool repayment: the husband if he is an admin (review R3-01); never a member, never
    -- another's account, and no other admin while he is there.
    PERFORM pg_temp.check('R1-07 a non-admin husband cannot reverse a pool repayment', pg_temp.rev(1, 1, pg_temp.id('pA'), 123), 'ERR:account_forbidden');
    PERFORM pg_temp.check('R3B-06 an admin cannot reverse another''s personal repayment', pg_temp.rev(5, 1, pg_temp.id('apC'), 124), 'ERR:forbidden');
    UPDATE public.household_memberships SET role = 'admin' WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(6);
    PERFORM pg_temp.check('R3-01 another admin, while the husband is there', pg_temp.rev(6, 1, pg_temp.id('pA'), 125), 'ERR:forbidden');
    UPDATE public.household_memberships SET role = 'admin' WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(1);
    v_res := pg_temp.rev(1, 1, pg_temp.id('pA'), 127);
    PERFORM pg_temp.check('R1-07 the husband, an admin now, reverses a pool repayment', pg_temp.j(v_res, 'kind'), 'reversal');
    PERFORM pg_temp.check('R1-07 the pool is credited back', pg_temp.bal(1), '5000.00');
    PERFORM pg_temp.check('R1-07 a wife is never the one to reverse', pg_temp.rev(2, 1, pg_temp.id('apC'), 126), 'ERR:forbidden');
END $$;

-- ── R1-03: pending requests that no longer fit close as 'already_repaid' ──────────────────────
DO $$
DECLARE
    v_q1 uuid;
    v_q2 uuid;
    v_q3 uuid;
    v_res text;
BEGIN
    v_q1 := pg_temp.uid(pg_temp.j(pg_temp.req(8, 2, '100', 201), 'request_id'));
    v_q2 := pg_temp.uid(pg_temp.j(pg_temp.req(8, 2, '80', 202), 'request_id'));
    v_q3 := pg_temp.uid(pg_temp.j(pg_temp.req(8, 2, '50', 203), 'request_id'));
    PERFORM pg_temp.check('R1-03 three requests pending', pg_temp.pending(2, 8), '230.00');

    -- 600 owed; he repays 450 directly: 150 left. Oldest first while they fit: 100 stays, 80 no
    -- longer fits and closes, 50 still fits and stays.
    v_res := pg_temp.repay(7, 2, 8, '450', 11, 204);
    PERFORM pg_temp.check('R1-03 the direct repayment went through', pg_temp.j(v_res, 'outstanding_after'), '150.00');
    PERFORM pg_temp.check('R1-03 the oldest request still fits', pg_temp.outcome(v_q1), 'pending');
    PERFORM pg_temp.check('R1-03 the one that no longer fits is closed', pg_temp.outcome(v_q2), 'already_repaid/-');
    PERFORM pg_temp.check('R1-03 a later one that still fits stays', pg_temp.outcome(v_q3), 'pending');
    PERFORM pg_temp.check('R1-03 pending is within what is owed', pg_temp.pending(2, 8), '150.00');
    PERFORM pg_temp.check('R1-03 nothing moved for the closed one', pg_temp.bal(11), '4550.00');
    PERFORM pg_temp.check('R1-03 invariant after a repayment', pg_temp.over(), 'none');
    PERFORM pg_temp.check('R1-03 she cannot cancel a closed one', pg_temp.cancel(8, 2, v_q2), 'ERR:request_not_pending');
    PERFORM pg_temp.check('R1-03 her retry sees it closed', pg_temp.j(pg_temp.req(8, 2, '80', 202), 'status'), 'already_repaid');

    -- An approval: 50 paid, 100 owed, the 100 request still fits.
    v_res := pg_temp.approve(7, 2, v_q3, 11, 205);
    PERFORM pg_temp.check('R1-03 the approval went through', pg_temp.j(v_res, 'outstanding_after'), '100.00');
    PERFORM pg_temp.check('R1-03 the remaining request still fits', pg_temp.outcome(v_q1), 'pending');
    PERFORM pg_temp.check('R1-03 invariant after an approval', pg_temp.over(), 'none');

    -- A smaller advance: 570 advanced, 500 repaid, 70 owed: the 100 request no longer fits.
    BEGIN
        UPDATE public.transactions SET amount = amount - 30
        WHERE household_id = pg_temp.h(2) AND nafaqah_spouse_id = pg_temp.u(8) AND nafaqah_class = 'wife_reimbursable';
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.check('R1-03 the advance edit', SQLERRM, 'ok');
    END;
    PERFORM pg_temp.check('R1-03 owed after the smaller advance', pg_temp.owed(2, 8), '70.00');
    PERFORM pg_temp.check('R1-03 the request is closed by the edit', pg_temp.outcome(v_q1), 'already_repaid/-');
    PERFORM pg_temp.check('R1-03 nothing pending', pg_temp.pending(2, 8), '0.00');
    PERFORM pg_temp.check('R1-03 invariant after an advance edit', pg_temp.over(), 'none');
    PERFORM pg_temp.check('R1-03 still nothing moved for them', pg_temp.bal(11), '4500.00');
END $$;

-- ── R1-04 and R1-05: a replay is the same call, and answers what it answered ─────────────────
DO $$
DECLARE
    v_first text;
    v_rev text;
    v_res text;
    v_req uuid;
    v_ev text;
BEGIN
    -- "Another actor" needs two people allowed to act: the F2 husband gone for this section (review
    -- R3-01), H2 and C2 are both admins who are not wives.
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(2);
    v_first := pg_temp.repay(7, 2, 8, '10', 11, 210);
    PERFORM pg_temp.check('R1-04 a repayment', pg_temp.j(v_first, 'success'), 'true');
    PERFORM pg_temp.check('R1-04 same key, another amount', pg_temp.repay(7, 2, 8, '20', 11, 210), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 same key, another account', pg_temp.repay(7, 2, 8, '10', 12, 210), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 same key, another actor', pg_temp.repay(9, 2, 8, '10', 13, 210), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 the same call replays', pg_temp.j(pg_temp.repay(7, 2, 8, '10', 11, 210), 'replayed'), 'true');
    PERFORM pg_temp.check('R1-04 nothing moved twice', pg_temp.bal(11), '4490.00');

    v_req := pg_temp.uid(pg_temp.j(pg_temp.req(8, 2, '5', 211), 'request_id'));
    PERFORM pg_temp.check('R1-04 a request replayed with another amount', pg_temp.req(8, 2, '6', 211), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 an approval', pg_temp.j(pg_temp.approve(7, 2, v_req, 11, 212), 'success'), 'true');
    PERFORM pg_temp.check('R1-04 approval replayed from another account', pg_temp.approve(7, 2, v_req, 12, 212), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 approval replayed by another actor', pg_temp.approve(9, 2, v_req, 13, 212), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 an approval''s key used for a direct repayment', pg_temp.repay(7, 2, 8, '5', 11, 212), 'ERR:request_key_reused');

    v_rev := pg_temp.rev(7, 2, pg_temp.uid(pg_temp.j(v_first, 'reimbursement_id')), 213);
    PERFORM pg_temp.check('R1-04 a reversal', pg_temp.j(v_rev, 'kind'), 'reversal');
    PERFORM pg_temp.check('R1-04 reversal replayed by another actor', pg_temp.rev(9, 2, pg_temp.uid(pg_temp.j(v_first, 'reimbursement_id')), 213), 'ERR:request_key_reused');

    v_res := pg_temp.fpay(7, 2, '50', 11, 220);
    v_ev := pg_temp.j(v_res, 'event_id');
    PERFORM pg_temp.check('R1-04 a former member payment', pg_temp.j(v_res, 'success'), 'true');
    PERFORM pg_temp.check('R1-04 its key with another amount', pg_temp.fpay(7, 2, '60', 11, 220), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 its key with another account', pg_temp.fpay(7, 2, '50', 12, 220), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 its key by another actor', pg_temp.fpay(9, 2, '50', 13, 220), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 the same payment replays', pg_temp.j(pg_temp.fpay(7, 2, '50', 11, 220), 'replayed'), 'true');
    PERFORM pg_temp.check('R1-04 a former member reversal', pg_temp.j(pg_temp.frev(7, 2, pg_temp.uid(v_ev), 221), 'success'), 'true');
    PERFORM pg_temp.check('R1-04 its key by another actor', pg_temp.frev(9, 2, pg_temp.uid(v_ev), 221), 'ERR:request_key_reused');
    PERFORM pg_temp.keep('fmd_pay_transfer', pg_temp.j(v_res, 'transfer_id'));
    PERFORM pg_temp.keep('fmd_rev_transfer', pg_temp.j(pg_temp.frev(7, 2, pg_temp.uid(v_ev), 221), 'transfer_id'));

    -- R1-05: what the first call answered, whatever happened since.
    v_first := pg_temp.repay(7, 2, 8, '7', 11, 230);
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);
    PERFORM pg_temp.advance(2, 8, 50);
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(2);
    v_res := pg_temp.repay(7, 2, 8, '7', 11, 230);
    PERFORM pg_temp.check('R1-05 replay: outstanding before as first answered', pg_temp.j(v_res, 'outstanding_before'), pg_temp.j(v_first, 'outstanding_before'));
    PERFORM pg_temp.check('R1-05 replay: outstanding after as first answered', pg_temp.j(v_res, 'outstanding_after'), pg_temp.j(v_first, 'outstanding_after'));
    v_rev := pg_temp.rev(7, 2, pg_temp.uid(pg_temp.j(v_first, 'reimbursement_id')), 231);
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);
    PERFORM pg_temp.advance(2, 8, 20);
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(2);
    v_res := pg_temp.rev(7, 2, pg_temp.uid(pg_temp.j(v_first, 'reimbursement_id')), 231);
    PERFORM pg_temp.check('R1-05 reversal replay: before as first answered', pg_temp.j(v_res, 'outstanding_before'), pg_temp.j(v_rev, 'outstanding_before'));
    PERFORM pg_temp.check('R1-05 reversal replay: after as first answered', pg_temp.j(v_res, 'outstanding_after'), pg_temp.j(v_rev, 'outstanding_after'));

    -- R1-13: each money movement is labelled on its transfer row.
    PERFORM pg_temp.check('R1-13 a repayment debit', pg_temp.purpose(pg_temp.j(v_first, 'transfer_id')), 'wife_repayment/-');
    PERFORM pg_temp.check('R1-13 a reversal credit', pg_temp.purpose(pg_temp.j(v_rev, 'transfer_id')), 'wife_repayment_reversal/-');
    PERFORM pg_temp.check('R1-13 a former member payment, no text', pg_temp.purpose(pg_temp.kept('fmd_pay_transfer')), 'former_member_payment/-');
    PERFORM pg_temp.check('R1-13 its reversal, no text', pg_temp.purpose(pg_temp.kept('fmd_rev_transfer')), 'former_member_payment_reversal/-');
    PERFORM pg_temp.check('R1-13 the owner reads them in his account''s history',
        pg_temp.call(pg_temp.u(7), NULL, format(
            'SELECT count(*)::text FROM public.account_transfers WHERE (from_account_id = %L OR to_account_id = %L) AND purpose IS NOT NULL',
            pg_temp.a(11), pg_temp.a(11))),
        '9');

    -- Another admin with the very same call from the same pool: still not his to replay.
    PERFORM pg_temp.check('R1-04 a pool repayment', pg_temp.j(pg_temp.repay(7, 2, 8, '3', 14, 240), 'success'), 'true');
    PERFORM pg_temp.check('R1-04 its key, same pool and amount, another admin', pg_temp.repay(9, 2, 8, '3', 14, 240), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 a former member payment from the pool', pg_temp.j(pg_temp.fpay(7, 2, '4', 14, 241), 'success'), 'true');
    PERFORM pg_temp.check('R1-04 its key, same pool and amount, another admin', pg_temp.fpay(9, 2, '4', 14, 241), 'ERR:request_key_reused');
    PERFORM pg_temp.check('R1-04 the pool moved once each', pg_temp.bal(14), '4993.00');

    -- The waiver: the same key by another actor.
    PERFORM pg_temp.check('R1-04 a waiver', pg_temp.j(pg_temp.waive(7, 2, 222), 'status'), 'waived');
    PERFORM pg_temp.check('R1-04 its key by another actor', pg_temp.waive(9, 2, 222), 'ERR:request_key_reused');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);
END $$;

-- ── R1-08: a deleted payer leaves no id behind ───────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('R1-08 rows paid by C before his deletion',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE paid_by_user_id = pg_temp.u(4)), '3');
    PERFORM pg_temp.purge(4);
    PERFORM pg_temp.check('R1-08 rows paid by C after it', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE paid_by_user_id = pg_temp.u(4)), '0');
    PERFORM pg_temp.check('R1-08 the rows stay, with no payer', pg_temp.payer(pg_temp.id('apC')), 'none');
    PERFORM pg_temp.check('R1-08 the approval is still there',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE id = pg_temp.id('apC')), '1');
    PERFORM pg_temp.check('R1-03 invariant at the end', pg_temp.over(), 'none');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.check('R1-08 purge of a payer', SQLERRM, 'ok');
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
    RAISE NOTICE 'PASSED: the Round 1 fixes of tracked repayments (R1-01, R1-03, R1-04, R1-05, R1-07, R1-08, R1-13).';
END $$;

ROLLBACK;
