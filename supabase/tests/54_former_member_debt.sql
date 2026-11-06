-- ============================================================================
-- Test 54: what the husband owes a wife who deletes her account
--
-- Migration: 20261105001200_account_deletion_former_member_debt.sql
--
-- `DELETE FROM auth.users` stands in for the Auth Admin API, as tests 16 and 39 do.
--
-- Verifies:
--   1. Before the deletion: while her request is scheduled, the creditor (the household's
--      Nafaqah provider, or its admins when it has none) is listed for one 'creditor_owed'
--      email with the outstanding amount, and sees an in-app notice; other members see none.
--      Nothing is listed when nothing is owed, or once the notice is marked sent.
--   2. At the purge: one anonymised record per surviving household where the outstanding
--      amount is above zero, with that amount, and none where it is zero. Pool balances and
--      budgets are exactly equal, and nothing of her (id, email, display name) is left.
--   3. Visibility (review R3-01): the husband reads the record; when he is gone, an admin who is
--      not a wife. Never a member, a wife or another household. No client writes the tables.
--   4. Payments: partial then full (settled), overpayment refused, bad input refused, a
--      replayed request key changes nothing, a closed record takes nothing more. Balances and
--      budgets do not move, as with an ordinary reimbursement.
--   5. Waiver (إبراء): closes as waived with no money moving; replay is a no-op.
--   6. Who (review R3-01): the husband (the provider, an admin or not); when he is gone, an admin
--      who is not a wife; never an admin while he is there, another member, another household or
--      anon. The record must belong to the household named.
--   7. The husband deleting his own account later: the record stays with a surviving
--      household and his id leaves it; a household deleted with him takes the record along.
--   8. Privileges of every new function.
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
AS $$ SELECT ('e5400000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e54a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e54c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e54e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.k(int) TO PUBLIC;

CREATE FUNCTION pg_temp.hh(p_n int, p_type text DEFAULT 'family') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.households (id, name, invite_code, household_type)
    VALUES (pg_temp.h(p_n), 'T54 H' || p_n, 'T54CODE' || lpad(p_n::text, 9, '0'), p_type);
END;
$$;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, true);
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
    WHERE id = pg_temp.u(p_user);
END;
$$;

CREATE FUNCTION pg_temp.acct(p_n int, p_hh int, p_owner int, p_pool boolean, p_balance numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool)
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T54 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE 'bank' END, p_balance, p_pool);
END;
$$;

-- A wife's advance (rule 2), optionally from her own account.
CREATE FUNCTION pg_temp.advance(p_hh int, p_wife int, p_amount numeric, p_account int DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by,
                                     nafaqah_class, nafaqah_spouse_id, account_id)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'T54 Grocer', 'OPEX-GROCERY', now(), 'manual', 'me',
            'wife_reimbursable', pg_temp.u(p_wife), CASE WHEN p_account IS NULL THEN NULL ELSE pg_temp.a(p_account) END);
END;
$$;

-- The account a member pays from (20261105001300: every repayment leaves one): their first
-- personal account in the household, or a random id when they have none (refused before it matters).
CREATE FUNCTION pg_temp.wallet(p_hh int, p_owner int) RETURNS uuid LANGUAGE sql AS $$
    SELECT COALESCE((SELECT a.id FROM public.accounts a
                     WHERE a.household_id = pg_temp.h(p_hh) AND a.owner_user_id = pg_temp.u(p_owner) AND NOT a.is_shared_pool
                     ORDER BY a.id LIMIT 1), gen_random_uuid());
$$;
GRANT EXECUTE ON FUNCTION pg_temp.wallet(int, int) TO PUBLIC;
CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;

-- An ordinary repayment, through today's RPC, from the actor's account.
CREATE FUNCTION pg_temp.repay(p_hh int, p_wife int, p_amount numeric, p_actor int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_res text := pg_temp.svc(format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, %L, %L::uuid, gen_random_uuid())::text',
                                     pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'cash', pg_temp.u(p_actor), pg_temp.wallet(p_hh, p_actor)));
BEGIN
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'repayment refused: %', v_res; END IF;
END;
$$;

CREATE FUNCTION pg_temp.request(p_user int, p_choices text DEFAULT '[]') RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_sess text;
    v_res text;
BEGIN
    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_user), now()) RETURNING id::text INTO v_sess;
    v_res := pg_temp.call(pg_temp.u(p_user), v_sess,
        format('SELECT public.request_account_deletion(%L, %L::jsonb, NULL, %L)::text', 'DELETE', p_choices, 'en'));
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'request for user % refused: %', p_user, v_res;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.req_id(p_user int) RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.account_deletion_requests WHERE user_id = pg_temp.u(p_user) AND status IN ('scheduled', 'processing', 'failed') $$;

-- The whole worker job: claim, prepare, storage, Auth delete, complete.
CREATE FUNCTION pg_temp.purge(p_user int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid := pg_temp.req_id(p_user);
    v_res text;
    v_prepared jsonb;
BEGIN
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_id;
    UPDATE public.households SET deletion_scheduled_for = now() - interval '1 minute' WHERE deletion_requested_by = pg_temp.u(p_user);
    v_res := pg_temp.svc('SELECT count(*)::text FROM public.claim_due_account_deletions(50, 30)');
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'claim failed: %', v_res; END IF;
    v_res := pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'prepare failed: %', v_res; END IF;
    v_prepared := v_res::jsonb;
    IF (v_prepared->>'deferred')::boolean THEN
        RAISE EXCEPTION 'purge of user % deferred', p_user;
    END IF;
    v_res := pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'mark storage failed: %', v_res; END IF;
    DELETE FROM auth.users WHERE id = pg_temp.u(p_user);
    v_res := pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'complete failed: %', v_res; END IF;
    RETURN v_prepared;
END;
$$;

-- Pool balances (every account, personal too) and budget spend of the given households.
CREATE FUNCTION pg_temp.ledger(p_hhs uuid[]) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.household_id = ANY (p_hhs)), '')
        || ' | '
        || COALESCE((SELECT string_agg(b.id::text || '=' || b.spent_amount::text, ',' ORDER BY b.id)
                     FROM public.budgets b WHERE b.household_id = ANY (p_hhs)), '');
$$;

-- Tables in public holding p_needle in any column.
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

-- Payment and waiver through the RPCs, as user p_actor (authenticated, JWT subject).
CREATE FUNCTION pg_temp.pay(p_actor int, p_hh int, p_amount text, p_key int, p_method text DEFAULT 'bank_transfer', p_debt uuid DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L, NULL, %L::uuid)::text',
               pg_temp.h(p_hh), COALESCE(p_debt, pg_temp.debt(p_hh)), p_amount, p_method, pg_temp.k(p_key), pg_temp.wallet(p_hh, p_actor)));
$$;
CREATE FUNCTION pg_temp.waive(p_actor int, p_hh int, p_key int, p_debt uuid DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), NULL,
        format('SELECT public.waive_former_member_debt(%L, %L, %L)::text',
               pg_temp.h(p_hh), COALESCE(p_debt, pg_temp.debt(p_hh)), pg_temp.k(p_key)));
$$;

CREATE FUNCTION pg_temp.state(p_hh int) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(d.original_amount::text || '/' || d.paid_amount::text || '/' || d.status || '/' || (d.closed_at IS NOT NULL)::text, ',')
    FROM public.former_member_debts d WHERE d.household_id = pg_temp.h(p_hh);
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) primary admin and provider, wife W(2), member K(3), co-admin C(4).
-- F2(2): husband H2(5), wife W2(6): her advances are repaid in full.
-- F3(3): primary admin Q(8), husband P(7) a co-admin and the provider, wife V(9), member M(14).
-- F4(4): husband R(10) sole admin, wife S(11).
-- F5(5): no provider: admin A(13), wife Y(12), member B(15).
-- Outsider O(16), admin of their own family household F6(6).
-- F7(7): admin A7(17); the provider PM(18) is a plain member, not an admin; wife Z(19).
DO $$
DECLARE
    v_cycle text;
    v_month date := date_trunc('month', now())::date;
BEGIN
    SELECT cycle_key INTO v_cycle FROM public.get_saudi_cycle_for_timestamp(now(), 27);

    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't54-' || n || '@test.local', jsonb_build_object('display_name', 'T54 User ' || n)
    FROM generate_series(1, 19) AS n;
    UPDATE auth.users SET email = 't54-warda@test.local' WHERE id = pg_temp.u(2);
    UPDATE public.users SET display_name = 'Warda Uniquewife' WHERE id = pg_temp.u(2);
    UPDATE auth.users SET email = 't54-pasha@test.local' WHERE id = pg_temp.u(7);
    UPDATE public.users SET display_name = 'Pasha Uniquehusband' WHERE id = pg_temp.u(7);

    PERFORM pg_temp.hh(1);
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'family_member');
    PERFORM pg_temp.join(4, 1, 'admin', 'family_member');

    PERFORM pg_temp.hh(2);
    PERFORM pg_temp.join(5, 2, 'admin', 'provider');
    PERFORM pg_temp.join(6, 2, 'member', 'spouse');

    PERFORM pg_temp.hh(3);
    PERFORM pg_temp.join(8, 3, 'admin', 'family_member');
    PERFORM pg_temp.join(7, 3, 'admin', 'provider');
    PERFORM pg_temp.join(9, 3, 'member', 'spouse');
    PERFORM pg_temp.join(14, 3, 'member', 'family_member');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(3);

    PERFORM pg_temp.hh(4);
    PERFORM pg_temp.join(10, 4, 'admin', 'provider');
    PERFORM pg_temp.join(11, 4, 'member', 'spouse');

    PERFORM pg_temp.hh(5);
    PERFORM pg_temp.join(13, 5, 'admin', 'family_member');
    PERFORM pg_temp.join(12, 5, 'member', 'spouse');
    PERFORM pg_temp.join(15, 5, 'member', 'family_member');

    PERFORM pg_temp.hh(6);
    PERFORM pg_temp.join(16, 6, 'admin', 'provider');

    PERFORM pg_temp.hh(7);
    PERFORM pg_temp.join(17, 7, 'admin', 'family_member');
    PERFORM pg_temp.join(18, 7, 'member', 'provider');
    PERFORM pg_temp.join(19, 7, 'member', 'spouse');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(18) WHERE id = pg_temp.h(7);

    PERFORM pg_temp.acct(1, 1, 1, true, 1000);   -- F1 pool
    PERFORM pg_temp.acct(2, 1, 2, false, 500);   -- W personal
    PERFORM pg_temp.acct(3, 1, 1, false, 300);   -- H personal
    PERFORM pg_temp.acct(4, 3, 8, true, 700);    -- F3 pool
    PERFORM pg_temp.acct(5, 3, 7, false, 200);   -- P personal
    PERFORM pg_temp.acct(6, 1, 4, false, 500);   -- C personal (20261105001300: payments leave an account)
    PERFORM pg_temp.acct(7, 2, 5, false, 500);   -- O personal
    PERFORM pg_temp.acct(8, 7, 18, false, 500);  -- the F7 provider's personal account
    PERFORM pg_temp.acct(9, 3, 8, false, 100);   -- Q personal

    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key, account_id) VALUES
        ('e54b0000-0000-0000-0000-000000000001', pg_temp.h(1), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL),
        ('e54b0000-0000-0000-0000-000000000003', pg_temp.h(3), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL);

    -- F1: 80 unlinked plus 120 from her own account, 30 repaid: 170 outstanding.
    PERFORM pg_temp.advance(1, 2, 80);
    PERFORM pg_temp.advance(1, 2, 120, 2);
    PERFORM pg_temp.repay(1, 2, 30, 1);
    -- F2: 50 advanced, 50 repaid.
    PERFORM pg_temp.advance(2, 6, 50);
    PERFORM pg_temp.repay(2, 6, 50, 5);
    -- F3: 40. F4: 25. F5: 60, then the provider is cleared.
    PERFORM pg_temp.advance(3, 9, 40);
    PERFORM pg_temp.advance(4, 11, 25);
    PERFORM pg_temp.advance(5, 12, 60);
    UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = pg_temp.h(5);
    -- F7: 15.
    PERFORM pg_temp.advance(7, 19, 15);
END $$;

-- 1. Before the deletion ---------------------------------------------------------------------
DO $$
DECLARE
    v_rows text;
BEGIN
    PERFORM pg_temp.expect('nothing listed before any request',
        pg_temp.svc('SELECT count(*)::text FROM public.list_former_member_debt_notices_due()'), '0');

    PERFORM pg_temp.request(2);
    PERFORM pg_temp.request(6);
    PERFORM pg_temp.request(12);

    v_rows := pg_temp.svc(format($q$SELECT string_agg(user_id::text || ':' || notice || ':' || amount::text || ':' || (request_id IN (%L, %L))::text
                                               || ':' || (scheduled_for > now() + interval '29 days')::text, ',' ORDER BY user_id)
                           FROM public.list_former_member_debt_notices_due()$q$, pg_temp.req_id(2), pg_temp.req_id(12)));
    -- W's husband gets 170; W2 is owed nothing; Y's household has no provider, so its admin A.
    PERFORM pg_temp.expect('creditor notices due', v_rows,
        pg_temp.u(1)::text || ':creditor_owed:170.00:true:true,' || pg_temp.u(13)::text || ':creditor_owed:60.00:true:true');
    PERFORM pg_temp.expect('the locale is not the wife''s',
        pg_temp.svc('SELECT string_agg(DISTINCT COALESCE(locale, ''none''), '','') FROM public.list_former_member_debt_notices_due()'), 'none');

    -- In the app: the husband sees it, with her id, date and amount; nobody else does.
    PERFORM pg_temp.expect('husband sees the notice',
        pg_temp.call(pg_temp.u(1), NULL, format($q$SELECT string_agg(wife_user_id::text || ':' || outstanding::text, ',') FROM public.get_former_member_debt_deletion_notices(%L)$q$, pg_temp.h(1))),
        pg_temp.u(2)::text || ':170.00');
    PERFORM pg_temp.expect('a co-admin is not the creditor while there is a provider',
        pg_temp.call(pg_temp.u(4), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(1))), '0');
    PERFORM pg_temp.expect('a member sees no notice',
        pg_temp.call(pg_temp.u(3), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(1))), '0');
    PERFORM pg_temp.expect('the wife sees no creditor notice',
        pg_temp.call(pg_temp.u(2), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(1))), '0');
    PERFORM pg_temp.expect('another household''s admin is refused',
        pg_temp.call(pg_temp.u(16), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(1))), 'ERR:42501');
    PERFORM pg_temp.expect('no provider: the admins see it',
        pg_temp.call(pg_temp.u(13), NULL, format('SELECT string_agg(outstanding::text, '','') FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(5))), '60.00');
    PERFORM pg_temp.expect('no provider: a member does not',
        pg_temp.call(pg_temp.u(15), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(5))), '0');
    PERFORM pg_temp.expect('the API passes the verified caller',
        pg_temp.svc(format('SELECT string_agg(outstanding::text, '','') FROM public.get_former_member_debt_deletion_notices(%L, %L)', pg_temp.h(1), pg_temp.u(1))), '170.00');
    PERFORM pg_temp.expect('nobody acting is refused',
        pg_temp.svc(format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(1))), 'ERR:42501');

    -- Sent once: the mark is accepted and the row goes.
    PERFORM pg_temp.expect('mark accepted',
        pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', pg_temp.req_id(2), 'creditor_owed')), '');
    PERFORM pg_temp.expect('marked notice not listed again',
        pg_temp.svc(format('SELECT count(*)::text FROM public.list_former_member_debt_notices_due() WHERE request_id = %L', pg_temp.req_id(2))), '0');
    -- A cancelled request lists nothing, and the in-app notice goes with it.
    UPDATE public.account_deletion_requests SET status = 'cancelled', cancelled_at = now() WHERE id = pg_temp.req_id(12);
    PERFORM pg_temp.expect('cancelled request lists nothing',
        pg_temp.svc('SELECT count(*)::text FROM public.list_former_member_debt_notices_due()'), '0');
    PERFORM pg_temp.expect('cancelled request: no in-app notice',
        pg_temp.call(pg_temp.u(13), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(5))), '0');
    RAISE NOTICE 'PASSED: the creditor is told the outstanding amount before the deletion, once, and nobody else is.';
END $$;

-- 2. The purge keeps one anonymised record ----------------------------------------------------
DO $$
DECLARE
    v_before text := pg_temp.ledger(ARRAY[pg_temp.h(1), pg_temp.h(2)]);
    v_res jsonb;
BEGIN
    PERFORM pg_temp.expect('fixture: the budget counts her advances', (SELECT spent_amount::text FROM public.budgets WHERE id = 'e54b0000-0000-0000-0000-000000000001'), '200.00');

    v_res := pg_temp.purge(2);
    PERFORM pg_temp.expect('one record, 170 owed, open', pg_temp.state(1), '170.00/0.00/open/false');
    PERFORM pg_temp.purge(6);
    PERFORM pg_temp.expect('nothing owed: no record', (SELECT count(*)::text FROM public.former_member_debts WHERE household_id = pg_temp.h(2)), '0');
    PERFORM pg_temp.expect('no record anywhere else', (SELECT count(*)::text FROM public.former_member_debts), '1');

    -- W's own account went with her (as before this change); everything else is exactly equal.
    PERFORM pg_temp.expect('pools, accounts and budgets exactly equal',
        pg_temp.ledger(ARRAY[pg_temp.h(1), pg_temp.h(2)]), regexp_replace(v_before, pg_temp.a(2)::text || '=[0-9.]+,', ''));
    PERFORM pg_temp.expect('her ledger is gone as before',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE household_id = pg_temp.h(1)), '0');

    PERFORM pg_temp.expect('her id anywhere', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.expect('her email anywhere', pg_temp.scan('t54-warda@test.local'), '');
    PERFORM pg_temp.expect('her name anywhere', pg_temp.scan('Warda Uniquewife'), '');
    PERFORM pg_temp.expect('the record has no free text and no person',
        (SELECT count(*)::text FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'former_member_debts'
           AND column_name NOT IN ('id', 'household_id', 'original_amount', 'paid_amount', 'status', 'created_at', 'closed_at')), '0');
    PERFORM pg_temp.expect('her notices are gone with her',
        pg_temp.svc('SELECT count(*)::text FROM public.list_former_member_debt_notices_due()'), '0');
    RAISE NOTICE 'PASSED: the purge keeps one anonymised record of what is owed, moves nothing and leaves nothing of her.';
END $$;

-- 3. Visibility and no client writes ---------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.expect('a member does not see the record (R3-01)', pg_temp.call(pg_temp.u(3), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '0');
    PERFORM pg_temp.expect('an admin does not while the husband is there (R3-01)', pg_temp.call(pg_temp.u(4), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '0');
    PERFORM pg_temp.expect('the husband sees it', pg_temp.call(pg_temp.u(1), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '1');
    PERFORM pg_temp.expect('another household does not', pg_temp.call(pg_temp.u(16), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '0');
    PERFORM pg_temp.expect('anon reads nothing', pg_temp.call(NULL, NULL, 'SELECT count(*)::text FROM public.former_member_debts', 'anon'), 'ERR:42501');
    PERFORM pg_temp.expect('client insert refused',
        pg_temp.call(pg_temp.u(1), NULL, format('INSERT INTO public.former_member_debts (household_id, original_amount) VALUES (%L, 5) RETURNING id::text', pg_temp.h(1))), 'ERR:42501');
    PERFORM pg_temp.expect('client update refused',
        pg_temp.call(pg_temp.u(1), NULL, 'UPDATE public.former_member_debts SET paid_amount = original_amount, status = ''settled'', closed_at = now() RETURNING id::text'), 'ERR:42501');
    PERFORM pg_temp.expect('client delete refused',
        pg_temp.call(pg_temp.u(1), NULL, 'DELETE FROM public.former_member_debts RETURNING id::text'), 'ERR:42501');
    PERFORM pg_temp.expect('client event insert refused',
        pg_temp.call(pg_temp.u(1), NULL, format('INSERT INTO public.former_member_debt_events (debt_id, kind, amount, remaining_after, request_key) VALUES (%L, ''waiver'', 1, 0, gen_random_uuid()) RETURNING id::text', pg_temp.debt(1))), 'ERR:42501');
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname IN ('former_member_debts', 'former_member_debt_events')
               AND relnamespace = 'public'::regnamespace AND NOT relrowsecurity) THEN
        RAISE EXCEPTION 'RLS is off on a former member debt table';
    END IF;
    RAISE NOTICE 'PASSED: the husband sees the record, nobody else while he is there, and no client writes it.';
END $$;

-- 4. Payments ------------------------------------------------------------------------------
DO $$
DECLARE
    v_before text := pg_temp.ledger(ARRAY[pg_temp.h(1)]);
    v_tx bigint := (SELECT count(*) FROM public.transactions);
    v_first text;
    v_replay text;
BEGIN
    PERFORM pg_temp.expect('a member may not pay', pg_temp.pay(3, 1, '10', 1), 'ERR:forbidden');
    PERFORM pg_temp.expect('another household may not pay', pg_temp.pay(16, 1, '10', 1), 'ERR:forbidden');
    PERFORM pg_temp.expect('named through another household', pg_temp.pay(16, 6, '10', 1, 'cash', pg_temp.debt(1)), 'ERR:debt_not_found');
    PERFORM pg_temp.expect('anon cannot call it',
        pg_temp.call(NULL, NULL, format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, %L)::text', pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.k(1)), 'anon'), 'ERR:42501');
    PERFORM pg_temp.expect('zero refused', pg_temp.pay(1, 1, '0', 1), 'ERR:invalid_amount');
    PERFORM pg_temp.expect('negative refused', pg_temp.pay(1, 1, '-5', 1), 'ERR:invalid_amount');
    PERFORM pg_temp.expect('sub-halala refused', pg_temp.pay(1, 1, '10.001', 1), 'ERR:invalid_amount');
    PERFORM pg_temp.expect('unknown method refused', pg_temp.pay(1, 1, '10', 1, 'gold'), 'ERR:invalid_payment_method');
    PERFORM pg_temp.expect('no request key refused',
        pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, NULL, NULL, %L::uuid)::text',
            pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.a(3))), 'ERR:request_key_required');
    PERFORM pg_temp.expect('the amount-only signature is not a client''s (R3-03)',
        pg_temp.call(pg_temp.u(1), NULL, format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, %L)::text',
            pg_temp.h(1), pg_temp.debt(1), 'cash', pg_temp.k(1))), 'ERR:42501');
    PERFORM pg_temp.expect('overpayment refused', pg_temp.pay(1, 1, '170.01', 1), 'ERR:overpayment');
    PERFORM pg_temp.expect('nothing recorded by refusals', pg_temp.state(1), '170.00/0.00/open/false');

    v_first := pg_temp.pay(1, 1, '70', 1);
    PERFORM pg_temp.expect('partial payment', (v_first::jsonb ->> 'remaining') || '/' || (v_first::jsonb ->> 'status') || '/' || (v_first::jsonb ->> 'replayed'), '100.00/open/false');
    PERFORM pg_temp.expect('state after partial', pg_temp.state(1), '170.00/70.00/open/false');

    -- The same tap again: the same answer and nothing new.
    v_replay := pg_temp.pay(1, 1, '70', 1);
    PERFORM pg_temp.expect('replay returns the first event', v_replay::jsonb ->> 'event_id', v_first::jsonb ->> 'event_id');
    PERFORM pg_temp.expect('replay flagged', v_replay::jsonb ->> 'replayed', 'true');
    PERFORM pg_temp.expect('replay changes nothing', pg_temp.state(1), '170.00/70.00/open/false');
    PERFORM pg_temp.expect('a request key is not reused for a waiver', pg_temp.waive(1, 1, 1), 'ERR:request_key_reused');

    PERFORM pg_temp.expect('more than what remains refused', pg_temp.pay(1, 1, '100.01', 2), 'ERR:overpayment');
    -- An admin does not pay while the husband is there (review R3-01); he pays the rest.
    PERFORM pg_temp.expect('a co-admin may not pay while the husband is there', pg_temp.pay(4, 1, '100', 9), 'ERR:forbidden');
    PERFORM pg_temp.expect('full payment settles',
        (pg_temp.pay(1, 1, '100', 3)::jsonb ->> 'status'), 'settled');
    PERFORM pg_temp.expect('state after full', pg_temp.state(1), '170.00/170.00/settled/true');
    PERFORM pg_temp.expect('a settled record takes no payment', pg_temp.pay(1, 1, '1', 4), 'ERR:debt_closed');
    PERFORM pg_temp.expect('a settled record cannot be waived', pg_temp.waive(1, 1, 5), 'ERR:debt_closed');
    PERFORM pg_temp.expect('a replay after settling still answers', (pg_temp.pay(1, 1, '100', 3)::jsonb ->> 'replayed'), 'true');

    PERFORM pg_temp.expect('history: two payments with method, actor and remaining',
        (SELECT string_agg(e.kind || ':' || e.amount::text || ':' || e.payment_method || ':' || e.remaining_after::text
                           || ':' || (e.recorded_by = pg_temp.u(1))::text, ',' ORDER BY e.remaining_after DESC)
         FROM public.former_member_debt_events e WHERE e.debt_id = pg_temp.debt(1)),
        'payment:70.00:bank_transfer:100.00:true,payment:100.00:bank_transfer:0.00:true');
    PERFORM pg_temp.expect('the husband reads the history',
        pg_temp.call(pg_temp.u(1), NULL, 'SELECT count(*)::text FROM public.former_member_debt_events'), '2');
    PERFORM pg_temp.expect('a member reads none of it (R3-01)',
        pg_temp.call(pg_temp.u(3), NULL, 'SELECT count(*)::text FROM public.former_member_debt_events'), '0');
    PERFORM pg_temp.expect('another household reads none',
        pg_temp.call(pg_temp.u(16), NULL, 'SELECT count(*)::text FROM public.former_member_debt_events'), '0');

    -- As an ordinary reimbursement (20261105001300): each payer's account went down by what he paid,
    -- nothing else moved, and no budget or transaction.
    PERFORM pg_temp.expect('no budget moved by payments', split_part(pg_temp.ledger(ARRAY[pg_temp.h(1)]), ' | ', 2), split_part(v_before, ' | ', 2));
    PERFORM pg_temp.expect('the payer''s account went down by what he paid', pg_temp.bal(3) || '/' || pg_temp.bal(6), '100.00/500.00');
    PERFORM pg_temp.expect('no other balance moved',
        regexp_replace(regexp_replace(split_part(pg_temp.ledger(ARRAY[pg_temp.h(1)]), ' | ', 1), pg_temp.a(3)::text || '=[0-9.]+', ''), pg_temp.a(6)::text || '=[0-9.]+', ''),
        regexp_replace(regexp_replace(split_part(v_before, ' | ', 1), pg_temp.a(3)::text || '=[0-9.]+', ''), pg_temp.a(6)::text || '=[0-9.]+', ''));
    PERFORM pg_temp.expect('no transaction written',
        (SELECT count(*) FROM public.transactions)::text, v_tx::text);
    RAISE NOTICE 'PASSED: partial then full payment, overpayment refused, a replay changes nothing, no money moves.';
END $$;

-- 5. Waiver, and the husband deleting his own account later -------------------------------------
DO $$
DECLARE
    v_before text;
    v_res text;
BEGIN
    PERFORM pg_temp.request(9);
    PERFORM pg_temp.expect('a co-admin provider is the creditor',
        pg_temp.svc(format('SELECT string_agg(user_id::text || '':'' || amount::text, '','') FROM public.list_former_member_debt_notices_due() WHERE request_id = %L', pg_temp.req_id(9))),
        pg_temp.u(7)::text || ':40.00');
    PERFORM pg_temp.purge(9);
    PERFORM pg_temp.expect('F3 record', pg_temp.state(3), '40.00/0.00/open/false');
    PERFORM pg_temp.expect('the husband pays part', (pg_temp.pay(7, 3, '10', 10, 'cash')::jsonb ->> 'remaining') || '/' || pg_temp.bal(5), '30.00/190.00');
    PERFORM pg_temp.expect('a member may not waive', pg_temp.waive(14, 3, 11), 'ERR:forbidden');
    PERFORM pg_temp.expect('anon cannot waive',
        pg_temp.call(NULL, NULL, format('SELECT public.waive_former_member_debt(%L, %L, %L)::text', pg_temp.h(3), pg_temp.debt(3), pg_temp.k(11)), 'anon'), 'ERR:42501');
    PERFORM pg_temp.expect('another household may not waive', pg_temp.waive(16, 3, 11), 'ERR:forbidden');
    PERFORM pg_temp.expect('the primary admin may not while the husband is there (R3-01)', pg_temp.waive(8, 3, 12), 'ERR:forbidden');
    PERFORM pg_temp.expect('nor read it', pg_temp.call(pg_temp.u(8), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '0');

    -- P (a co-admin, not primary, the husband) deletes his account: the household survives with
    -- the record, and he is gone.
    PERFORM pg_temp.request(7);
    PERFORM pg_temp.purge(7);
    PERFORM pg_temp.expect('the record stays with the household', pg_temp.state(3), '40.00/10.00/open/false');
    PERFORM pg_temp.expect('his payment stays, without him',
        (SELECT string_agg(e.kind || ':' || (e.recorded_by IS NULL)::text, ',' ORDER BY e.kind) FROM public.former_member_debt_events e WHERE e.debt_id = pg_temp.debt(3)),
        'payment:true');
    PERFORM pg_temp.expect('his id anywhere', pg_temp.scan(pg_temp.u(7)::text), '');
    PERFORM pg_temp.expect('his email anywhere', pg_temp.scan('t54-pasha@test.local'), '');
    PERFORM pg_temp.expect('his name anywhere', pg_temp.scan('Pasha Uniquehusband'), '');

    -- The husband gone, the primary admin (not a wife) reads and closes it (review R3-01).
    PERFORM pg_temp.expect('the admin reads it now', pg_temp.call(pg_temp.u(8), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '1');
    PERFORM pg_temp.expect('a member still does not', pg_temp.call(pg_temp.u(14), NULL, 'SELECT count(*)::text FROM public.former_member_debts'), '0');
    v_before := pg_temp.ledger(ARRAY[pg_temp.h(3)]);
    PERFORM pg_temp.expect('a replayed payment key is not a waiver', pg_temp.waive(8, 3, 10), 'ERR:request_key_reused');
    v_res := pg_temp.waive(8, 3, 12);   -- the primary admin records her release
    PERFORM pg_temp.expect('waived', (v_res::jsonb ->> 'status') || '/' || (v_res::jsonb ->> 'remaining') || '/' || (v_res::jsonb ->> 'waived_amount'), 'waived/0.00/30.00');
    PERFORM pg_temp.expect('state after waiver', pg_temp.state(3), '40.00/10.00/waived/true');
    PERFORM pg_temp.expect('waiver replay', (pg_temp.waive(8, 3, 12)::jsonb ->> 'replayed'), 'true');
    PERFORM pg_temp.expect('a waived record takes no payment', pg_temp.pay(8, 3, '1', 13), 'ERR:debt_closed');
    PERFORM pg_temp.expect('waiver moves no money', pg_temp.ledger(ARRAY[pg_temp.h(3)]), v_before);
    PERFORM pg_temp.expect('history keeps payment and waiver',
        (SELECT string_agg(e.kind || ':' || e.amount::text || ':' || COALESCE(e.payment_method, '-') || ':' || e.remaining_after::text, ',' ORDER BY e.created_at, e.kind)
         FROM public.former_member_debt_events e WHERE e.debt_id = pg_temp.debt(3)),
        'payment:10.00:cash:30.00,waiver:30.00:-:0.00');
    PERFORM pg_temp.expect('the waiver is the admin''s',
        (SELECT string_agg(e.kind || ':' || (e.recorded_by IS NULL)::text, ',' ORDER BY e.kind) FROM public.former_member_debt_events e WHERE e.debt_id = pg_temp.debt(3)),
        'payment:true,waiver:false');

    -- R: his wife goes first, then he does, alone in F4: the household goes, the record with it.
    PERFORM pg_temp.request(11);
    PERFORM pg_temp.purge(11);
    PERFORM pg_temp.expect('F4 record', pg_temp.state(4), '25.00/0.00/open/false');
    PERFORM pg_temp.request(10);
    PERFORM pg_temp.purge(10);
    PERFORM pg_temp.expect('household deleted', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(4)), '0');
    PERFORM pg_temp.expect('its record went with it', (SELECT count(*)::text FROM public.former_member_debts WHERE household_id = pg_temp.h(4)), '0');
    RAISE NOTICE 'PASSED: a waiver closes the record with no money moving; the husband''s own deletion follows the household.';
END $$;

-- 5b. A provider who is not an admin -------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.request(19);
    PERFORM pg_temp.expect('the provider is told, though not an admin',
        pg_temp.call(pg_temp.u(18), NULL, format('SELECT string_agg(outstanding::text, '','') FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(7))), '15.00');
    PERFORM pg_temp.expect('the admin is not, while there is a provider',
        pg_temp.call(pg_temp.u(17), NULL, format('SELECT count(*)::text FROM public.get_former_member_debt_deletion_notices(%L)', pg_temp.h(7))), '0');
    PERFORM pg_temp.purge(19);
    PERFORM pg_temp.expect('F7 record', pg_temp.state(7), '15.00/0.00/open/false');
    PERFORM pg_temp.expect('the provider pays', (pg_temp.pay(18, 7, '5', 20, 'cash')::jsonb ->> 'remaining'), '10.00');
    PERFORM pg_temp.expect('an admin may not while he is there (R3-01)', pg_temp.waive(17, 7, 22), 'ERR:forbidden');
    PERFORM pg_temp.expect('the provider waives the rest', (pg_temp.waive(18, 7, 21)::jsonb ->> 'status'), 'waived');
    RAISE NOTICE 'PASSED: the husband closes the record even when he is not an admin.';
END $$;

-- 6. A record exists only when something is owed, and the snapshot never moves the ledger ---------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.former_member_debts WHERE original_amount <= 0) THEN
        RAISE EXCEPTION 'a record with nothing owed';
    END IF;
    BEGIN
        INSERT INTO public.former_member_debts (household_id, original_amount) VALUES (pg_temp.h(1), 0);
        RAISE EXCEPTION 'a zero record was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.former_member_debts SET paid_amount = original_amount + 1 WHERE household_id = pg_temp.h(1);
        RAISE EXCEPTION 'a paid amount above the original was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.former_member_debts SET status = 'open', closed_at = NULL WHERE household_id = pg_temp.h(1);
        RAISE EXCEPTION 'a fully paid record was reopened';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE NOTICE 'PASSED: the table''s checks keep the amounts and the status consistent.';
END $$;

-- 7. Privileges ---------------------------------------------------------------------------
DO $$
DECLARE
    v_call record;
BEGIN
    -- Service only.
    FOR v_call IN
        SELECT * FROM (VALUES
            ('list_former_member_debt_notices_due()', 'SELECT count(*)::text FROM public.list_former_member_debt_notices_due()')
        ) AS t(sig, sql)
    LOOP
        IF has_function_privilege('anon', 'public.' || v_call.sig, 'EXECUTE')
           OR has_function_privilege('authenticated', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client role can execute %', v_call.sig;
        END IF;
        IF NOT has_function_privilege('service_role', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: service_role cannot execute %', v_call.sig;
        END IF;
        PERFORM pg_temp.expect('a subject under service_role on ' || v_call.sig,
            pg_temp.call(pg_temp.u(1), NULL, v_call.sql, 'service_role'), 'ERR:42501');
    END LOOP;
    -- Internal helpers: nobody but their definer.
    FOR v_call IN
        SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
          AND p.proname IN ('account_deletion_snapshot_former_member_debts', 'former_member_debt_creditors',
                            'former_member_debt_outstanding', 'former_member_debt_require_manager',
                            'nafaqah_ledger_husband_id', 'nafaqah_may_manage_ledgers')
    LOOP
        IF has_function_privilege('anon', v_call.sig, 'EXECUTE') OR has_function_privilege('authenticated', v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client role can execute %', v_call.sig;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
        AND proname IN ('account_deletion_snapshot_former_member_debts', 'former_member_debt_creditors',
                        'former_member_debt_outstanding', 'former_member_debt_require_manager',
                        'nafaqah_ledger_husband_id', 'nafaqah_may_manage_ledgers')) <> 6 THEN
        RAISE EXCEPTION 'an internal helper is missing';
    END IF;
    -- Client RPCs: authenticated and the service, never anon; each pins search_path.
    FOR v_call IN
        SELECT * FROM (VALUES
            ('record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid, uuid)'),
            ('waive_former_member_debt(uuid, uuid, uuid, uuid)'),
            ('get_former_member_debt_deletion_notices(uuid, uuid)'),
            ('nafaqah_caller_manages_ledgers()')
        ) AS t(sig)
    LOOP
        IF has_function_privilege('anon', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: anon can execute %', v_call.sig;
        END IF;
        IF NOT has_function_privilege('authenticated', 'public.' || v_call.sig, 'EXECUTE')
           OR NOT has_function_privilege('service_role', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: % not executable by its callers', v_call.sig;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
               AND (p.proname LIKE '%former_member_debt%' OR p.proname = 'prepare_account_purge' OR p.proname = 'mark_account_deletion_notice_sent')
               AND p.prosecdef AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')) THEN
        RAISE EXCEPTION 'a SECURITY DEFINER function without a fixed search_path';
    END IF;
    -- The amount-only payment: the service role only (reviews R1-11, R3-03).
    IF has_function_privilege('anon', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY: the amount-only payment is not the service role''s only';
    END IF;
    -- A pending notice name the mark function did not know before still is refused when unknown.
    PERFORM pg_temp.expect('unknown notice refused',
        pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', gen_random_uuid(), 'creditor_bogus')), 'ERR:22023');
    RAISE NOTICE 'PASSED: privileges of the former member debt functions.';
END $$;

ROLLBACK;
