-- ============================================================================
-- Test 68: The wife account (owner decisions 2026-11-06, superseding "her account is never
--          credited")
--
-- Migration: 20261105001300_wife_repayment_debit.sql, sections 3b, 5 to 8, 10 and 12
-- Rules: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2;
--        .agents/rules/04-security-and-privacy.md, Family Nafaqah
--
-- An account of kind 'wife': personal, in SAR, owned by the husband (the household's provider
-- while he is a current member who is not a wife) and assigned to one wife of the household.
--   1. Created and assigned only by her husband; never by a client's own insert or update; assigned
--      again only before it has history; archived by its owner.
--   2. Seen (row, balance, transfers) by her, its owner and her ledger's managers (her husband; when
--      he is gone, an admin who is not a wife): never by a co-wife, a wife-admin, a member, or an
--      admin who is not a wife while the husband is there; not even that it exists.
--   3. Spent from only by her (her personal purchases and her advances); the husband funds it and
--      does not spend from it; nothing is transferred out of it.
--   4. Every repayment credits one of her wife accounts, exactly the amount, in the same transfer
--      that debits his account; budgets and her allowance do not move. Her request names one of
--      hers; the approval uses it, or another of hers he picks, never an account that is not hers.
--      With none: wife_account_required.
--   5. A reversal takes it back out of her wife account: refused when it no longer holds the amount
--      (wife_account_insufficient_funds) or is archived (reversal_account_unavailable).
--   6. A client cannot delete a wife account a repayment used (account_has_repayments).
--   7. Her purge archives her wife accounts, which stay his with their balance and history and name
--      nobody; a former member's payment then credits nothing. His purge passes his wife accounts to
--      the household's primary admin, or to her when that admin is a co-wife. Both keep the ledger
--      equality (the purge raises otherwise) and every balance.
-- Every client read and write is as the client makes it (RLS, as PostgREST applies it).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- One call as user p_sub: the value, or ERR:<hint or SQLSTATE>.
CREATE FUNCTION pg_temp.call(p_sub uuid, p_sql text, p_role text DEFAULT 'authenticated')
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
-- A write as user p_sub: the rows it changed, or ERR:<SQLSTATE>.
CREATE FUNCTION pg_temp.write(p_sub uuid, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_n bigint;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v_n::text;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text), pg_temp.write(uuid, text) TO PUBLIC;
-- A write's whole refusal (SQLSTATE and message), to compare two refusals.
CREATE FUNCTION pg_temp.msg(p_actor int, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.u(p_actor))::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN SQLSTATE || ':' || SQLERRM;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN 'written';
END;
$$;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e6800000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e68a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e68b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e68c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e68d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.t(int), pg_temp.k(int) TO PUBLIC;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, true);
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
    WHERE id = pg_temp.u(p_user);
END;
$$;

CREATE TABLE pg_temp.fails (n serial PRIMARY KEY, label text, got text, want text);
CREATE FUNCTION pg_temp.check(p_label text, p_got text, p_want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 300), p_want);
    END IF;
END;
$$;

CREATE TABLE pg_temp.snap (label text PRIMARY KEY, val text);
GRANT ALL ON pg_temp.snap TO PUBLIC;
CREATE FUNCTION pg_temp.keep(p_label text, p_val text) RETURNS void LANGUAGE sql
AS $$ INSERT INTO pg_temp.snap VALUES (p_label, p_val) ON CONFLICT (label) DO UPDATE SET val = EXCLUDED.val $$;
CREATE FUNCTION pg_temp.id(p_label text) RETURNS uuid LANGUAGE sql
AS $$ SELECT CASE WHEN val ~ '^[0-9a-f-]{36}$' THEN val::uuid END FROM pg_temp.snap WHERE label = p_label $$;
GRANT EXECUTE ON FUNCTION pg_temp.id(text) TO PUBLIC;
CREATE FUNCTION pg_temp.j(p_res text, p_field text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    IF p_res IS NULL OR p_res LIKE 'ERR:%' THEN RETURN p_res; END IF;
    RETURN p_res::jsonb ->> p_field;
END;
$$;
-- A balance by account number or by a wife account's label.
CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;
CREATE FUNCTION pg_temp.wbal(p_label text) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.id(p_label) $$;

-- F1's people, by the name the checks use.
CREATE TABLE pg_temp.people (n int, name text);
INSERT INTO pg_temp.people VALUES (1, 'H'), (2, 'W'), (3, 'W2'), (4, 'K'), (5, 'C'), (6, 'WA');
-- Which wife accounts (by label) the caller reads, as the client reads them.
CREATE FUNCTION pg_temp.vis(p_actor int) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(s.label, ',' ORDER BY s.label), '')
    FROM pg_temp.snap s
    WHERE s.label IN ('WA1', 'WA2', 'WA3', 'WA4', 'WC', 'VA', 'ZA')
      AND pg_temp.call(pg_temp.u(p_actor), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', s.val)) = '1';
$$;
-- Who of F1 reads the transfer labelled p_notes (as the client reads it), by name.
CREATE FUNCTION pg_temp.treaders(p_notes text) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(pp.name, ',' ORDER BY pp.n), '')
    FROM pg_temp.people pp
    WHERE pg_temp.call(pg_temp.u(pp.n), format('SELECT count(*)::text FROM public.account_transfers WHERE notes = %L', p_notes)) = '1';
$$;
-- Who of F1 reads a transfer by id.
CREATE FUNCTION pg_temp.xreaders(p_id uuid) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(pp.name, ',' ORDER BY pp.n), '')
    FROM pg_temp.people pp
    WHERE pg_temp.call(pg_temp.u(pp.n), format('SELECT count(*)::text FROM public.account_transfers WHERE id = %L', p_id)) = '1';
$$;

-- The client's calls.
CREATE FUNCTION pg_temp.create(p_actor int, p_hh int, p_wife int, p_name text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format('SELECT public.create_wife_account(%L, %L, %L, NULL)::text',
                                                   pg_temp.h(p_hh), pg_temp.u(p_wife), p_name));
$$;
CREATE FUNCTION pg_temp.assign(p_actor int, p_label text, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format('SELECT public.assign_wife_account(%L, %L, %L, NULL)::text',
                                                   pg_temp.h(1), pg_temp.id(p_label), pg_temp.u(p_wife)));
$$;
CREATE FUNCTION pg_temp.archive(p_actor int, p_hh int, p_label text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format('SELECT public.archive_wife_account(%L, %L, NULL)::text',
                                                   pg_temp.h(p_hh), pg_temp.id(p_label)));
$$;
-- A transfer as the client makes it (transfer_between_accounts as p_actor), labelled in its notes.
CREATE FUNCTION pg_temp.move(p_actor int, p_hh int, p_from uuid, p_to uuid, p_amount numeric, p_label text)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format(
        'SELECT (public.transfer_between_accounts(%L, %L, %L, %s, 0, %L) ->> %L)',
        pg_temp.h(p_hh), p_from, p_to, p_amount, p_label, 'notes'));
$$;
-- A purchase as the client records it: the rows it wrote or ERR:<SQLSTATE>.
CREATE FUNCTION pg_temp.spend(p_actor int, p_hh int, p_id int, p_account uuid, p_amount numeric, p_class text, p_wife int)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.write(pg_temp.u(p_actor), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, '
        'nafaqah_class, nafaqah_spouse_id, account_id) VALUES (%L, %L, %L, %s, %L, %L, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(p_id), pg_temp.h(p_hh), pg_temp.u(p_actor), p_amount, 'T68 shop ' || p_id, 'OPEX-SHOPPING',
        '2026-11-05 10:00+03', 'manual', 'me', p_class, CASE WHEN p_wife = 0 THEN NULL ELSE pg_temp.u(p_wife) END, p_account));
$$;
CREATE FUNCTION pg_temp.repay(p_actor int, p_hh int, p_wife int, p_amount text, p_account uuid, p_wife_account uuid, p_key int)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid, %L::uuid)::text',
               pg_temp.h(p_hh), pg_temp.u(p_wife), p_amount, 'bank_transfer', p_account, pg_temp.k(p_key), p_wife_account));
$$;
CREATE FUNCTION pg_temp.ask(p_actor int, p_amount text, p_wife_account uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.request_spouse_reimbursement(%L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(1), p_amount, 'cash', pg_temp.k(p_key), p_wife_account));
$$;
CREATE FUNCTION pg_temp.approve(p_actor int, p_request uuid, p_account uuid, p_wife_account uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.approve_spouse_reimbursement_request(%L, %L, %L::uuid, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(1), p_request, p_account, pg_temp.k(p_key), p_wife_account));
$$;
CREATE FUNCTION pg_temp.rev(p_actor int, p_row uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.reverse_spouse_reimbursement(%L, %L, %L::uuid, NULL)::text', pg_temp.h(1), p_row, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.provider(p_user int) RETURNS void LANGUAGE sql AS $$
    UPDATE public.households SET nafaqah_provider_user_id = CASE WHEN p_user = 0 THEN NULL ELSE pg_temp.u(p_user) END
    WHERE id = pg_temp.h(1);
$$;
-- F1's budgets and her allowance figures, which no repayment moves.
CREATE FUNCTION pg_temp.budgets() RETURNS text LANGUAGE sql
AS $$ SELECT COALESCE(sum(spent_amount), 0)::text || '/' || COALESCE(sum(allocated_amount), 0)::text FROM public.budgets WHERE household_id = pg_temp.h(1) $$;
CREATE FUNCTION pg_temp.allowance() RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(1), format('SELECT (public.get_member_allowance_status(%L, %L, %L, NULL) - %L - %L)::text',
                                             pg_temp.h(1), pg_temp.u(2), '2026-11', 'household_id', 'member_user_id'));
$$;
-- The repayment transfer a ledger row moved its money with: from|to|purpose|amount.
CREATE FUNCTION pg_temp.moved(p_row text) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(t.from_account_id::text, '-') || '|' || COALESCE(t.to_account_id::text, '-') || '|' || t.purpose || '|' || t.amount
    FROM public.spouse_reimbursements r JOIN public.account_transfers t ON t.id = r.transfer_id
    WHERE r.id = (p_row::jsonb ->> 'reimbursement_id')::uuid;
$$;
-- Every table of public naming p_needle anywhere in a row.
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
-- The deletion worker's purge of user p_user, up to the Auth delete. Returns prepare's answer.
CREATE FUNCTION pg_temp.purge(p_user int) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_sess text;
    v_req uuid;
    v_res text;
BEGIN
    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_user), now()) RETURNING id::text INTO v_sess;
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.u(p_user), 'session_id', v_sess)::text, true);
    SET LOCAL ROLE authenticated;
    PERFORM public.request_account_deletion('DELETE', '[]'::jsonb, NULL, 'en');
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT id INTO v_req FROM public.account_deletion_requests WHERE user_id = pg_temp.u(p_user) AND status = 'scheduled';
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_req;
    v_res := pg_temp.call(NULL, 'SELECT count(*)::text FROM public.claim_due_account_deletions(50, 30)', 'service_role');
    v_res := pg_temp.call(NULL, format('SELECT public.prepare_account_purge(%L)::text', v_req), 'service_role');
    PERFORM pg_temp.keep('purge' || p_user, v_req::text);
    RETURN v_res;
END;
$$;
CREATE FUNCTION pg_temp.complete(p_user int) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_res text;
BEGIN
    PERFORM pg_temp.call(NULL, format('SELECT public.mark_account_purge_storage_done(%L)::text', pg_temp.id('purge' || p_user)), 'service_role');
    DELETE FROM auth.users WHERE id = pg_temp.u(p_user);
    v_res := pg_temp.call(NULL, format('SELECT public.complete_account_purge(%L)::text', pg_temp.id('purge' || p_user)), 'service_role');
    RETURN (left(v_res, 4) <> 'ERR:')::text;
END;
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin, provider and primary admin; wife W(2); co-wife W2(3); member K(4);
--        admin C(5) who is not a wife; wife WA(6) who is an admin (she has no wife account).
-- F2(2): primary admin D(7) who is not a wife; husband H2(8), a member and the provider; wife V(9).
-- F3(3): primary admin Y(10), a wife; husband H3(11), a member and the provider; wife Z(12).
-- Accounts: F1 pool P a(1) 5000 (H's), W's own bank a(2) 1000, H's bank a(3) 3000, K's bank a(4)
--           500, W2's bank a(5) 800, C's bank a(6) 1000; F2 H2's bank a(7) 2000, D's bank a(9) 100;
--           F3 H3's bank a(8) 2000.
-- Her advances: W 600 (from her own bank), WA 40, V 300, Z 300.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't68-' || n || '@test.local', jsonb_build_object('display_name', 'T68 User ' || n)
    FROM generate_series(1, 12) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T68 H1', 'T68CODE000000001', 'family', 27),
        (pg_temp.h(2), 'T68 H2', 'T68CODE000000002', 'family', 27),
        (pg_temp.h(3), 'T68 H3', 'T68CODE000000003', 'family', 27);
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'member', 'family_member');
    PERFORM pg_temp.join(6, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(7, 2, 'admin', 'family_member');
    PERFORM pg_temp.join(8, 2, 'member', 'provider');
    PERFORM pg_temp.join(9, 2, 'member', 'spouse');
    PERFORM pg_temp.join(10, 3, 'admin', 'spouse');
    PERFORM pg_temp.join(11, 3, 'member', 'provider');
    PERFORM pg_temp.join(12, 3, 'member', 'spouse');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(7), nafaqah_provider_user_id = pg_temp.u(8) WHERE id = pg_temp.h(2);
    UPDATE public.households SET owner_user_id = pg_temp.u(10), nafaqah_provider_user_id = pg_temp.u(11) WHERE id = pg_temp.h(3);

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T68 pool', 'shared_pool', 5000, true, false, 'SAR'),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(2), 'T68 W bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(3), pg_temp.h(1), pg_temp.u(1), 'T68 H bank', 'bank', 3000, false, false, 'SAR'),
        (pg_temp.a(4), pg_temp.h(1), pg_temp.u(4), 'T68 K bank', 'bank', 500, false, false, 'SAR'),
        (pg_temp.a(5), pg_temp.h(1), pg_temp.u(3), 'T68 W2 bank', 'bank', 800, false, false, 'SAR'),
        (pg_temp.a(6), pg_temp.h(1), pg_temp.u(5), 'T68 C bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(7), pg_temp.h(2), pg_temp.u(8), 'T68 H2 bank', 'bank', 2000, false, false, 'SAR'),
        (pg_temp.a(9), pg_temp.h(2), pg_temp.u(7), 'T68 D bank', 'bank', 100, false, false, 'SAR'),
        (pg_temp.a(8), pg_temp.h(3), pg_temp.u(11), 'T68 H3 bank', 'bank', 2000, false, false, 'SAR');
    INSERT INTO public.budgets (household_id, category_code, cycle_key, month, allocated_amount, spent_amount, is_active) VALUES
        (pg_temp.h(1), 'OPEX-SHOPPING', '2026-11', '2026-11-01', 2000, 0, true),
        (pg_temp.h(1), 'OPEX-GROCERY', '2026-11', '2026-11-01', 2000, 0, true);
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, account_id) VALUES
        (pg_temp.t(1), pg_temp.h(1), pg_temp.u(2), 600, 'T68 Grocer W', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(2), pg_temp.a(2)),
        (pg_temp.t(2), pg_temp.h(1), pg_temp.u(6), 40, 'T68 Taxi WA', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(6), NULL),
        (pg_temp.t(3), pg_temp.h(2), pg_temp.u(9), 300, 'T68 Grocer V', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(9), NULL),
        (pg_temp.t(4), pg_temp.h(3), pg_temp.u(12), 300, 'T68 Grocer Z', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(12), NULL);
END $$;

-- ── 1. Creation and assignment ───────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.create(1, 1, 2, 'T68 User 2 card');
    PERFORM pg_temp.keep('WA1', pg_temp.j(v_res, 'id'));
    PERFORM pg_temp.check('H creates her wife account', pg_temp.j(v_res, 'account_type') || '|' || pg_temp.j(v_res, 'owner_user_id')
                          || '|' || pg_temp.j(v_res, 'assigned_wife_id') || '|' || pg_temp.j(v_res, 'balance') || '|' || pg_temp.j(v_res, 'currency'),
                          'wife|' || pg_temp.u(1) || '|' || pg_temp.u(2) || '|0.00|SAR');
    PERFORM pg_temp.check('it is a personal account', (SELECT (NOT is_shared_pool AND NOT is_archived)::text FROM public.accounts WHERE id = pg_temp.id('WA1')), 'true');
    PERFORM pg_temp.keep('WA2', pg_temp.j(pg_temp.create(1, 1, 2, 'wa2'), 'id'));
    PERFORM pg_temp.keep('WC', pg_temp.j(pg_temp.create(1, 1, 3, 'wc'), 'id'));
    PERFORM pg_temp.check('three made', (SELECT count(*)::text FROM public.accounts WHERE household_id = pg_temp.h(1) AND account_type = 'wife'), '3');

    -- Only her husband.
    PERFORM pg_temp.check('an admin who is not a wife, husband present', pg_temp.create(5, 1, 2, 'x'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('the wife herself', pg_temp.create(2, 1, 2, 'x'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('a wife-admin', pg_temp.create(6, 1, 2, 'x'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('a member', pg_temp.create(4, 1, 2, 'x'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('a stranger', pg_temp.create(7, 1, 2, 'x'), 'ERR:42501');
    PERFORM pg_temp.check('for a member who is not a wife', pg_temp.create(1, 1, 4, 'x'), 'ERR:not_a_wife');
    PERFORM pg_temp.check('for a wife of another household', pg_temp.create(1, 1, 9, 'x'), 'ERR:not_a_wife');
    PERFORM pg_temp.check('a blank name', pg_temp.create(1, 1, 2, '   '), 'ERR:invalid_name');
    PERFORM pg_temp.check('a name of 61', pg_temp.create(1, 1, 2, repeat('x', 61)), 'ERR:invalid_name');
    PERFORM pg_temp.check('nothing more made', (SELECT count(*)::text FROM public.accounts WHERE household_id = pg_temp.h(1) AND account_type = 'wife'), '3');
    PERFORM pg_temp.check('F2: the primary admin while the husband is there', pg_temp.create(7, 2, 9, 'x'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.keep('VA', pg_temp.j(pg_temp.create(8, 2, 9, 'va'), 'id'));
    PERFORM pg_temp.keep('ZA', pg_temp.j(pg_temp.create(11, 3, 12, 'za'), 'id'));
    PERFORM pg_temp.check('F2 and F3 made', (SELECT count(*)::text FROM public.accounts WHERE id IN (pg_temp.id('VA'), pg_temp.id('ZA'))), '2');

    -- Never by a client's own insert or update.
    PERFORM pg_temp.check('a client inserts a wife account', pg_temp.write(pg_temp.u(1), format(
        'INSERT INTO public.accounts (household_id, owner_user_id, name, account_type, is_shared_pool) VALUES (%L, %L, %L, %L, false)',
        pg_temp.h(1), pg_temp.u(1), 'x', 'wife')), 'ERR:42501');
    PERFORM pg_temp.check('a client assigns its own account to her', pg_temp.write(pg_temp.u(1), format(
        'INSERT INTO public.accounts (household_id, owner_user_id, name, account_type, is_shared_pool, assigned_wife_id) VALUES (%L, %L, %L, %L, false, %L)',
        pg_temp.h(1), pg_temp.u(1), 'x', 'bank', pg_temp.u(2))), 'ERR:42501');
    PERFORM pg_temp.check('the owner turns it into a bank', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.accounts SET account_type = %L WHERE id = %L', 'bank', pg_temp.id('WA1'))), 'ERR:42501');
    PERFORM pg_temp.check('the owner turns his bank into one', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.accounts SET account_type = %L WHERE id = %L', 'wife', pg_temp.a(3))), 'ERR:42501');
    PERFORM pg_temp.check('the owner reassigns it by hand', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.accounts SET assigned_wife_id = %L WHERE id = %L', pg_temp.u(3), pg_temp.id('WA1'))), 'ERR:42501');
    PERFORM pg_temp.check('the owner takes it out of SAR', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.accounts SET currency = %L WHERE id = %L', 'USD', pg_temp.id('WA1'))), 'ERR:23514');
    PERFORM pg_temp.check('the owner names it', pg_temp.write(pg_temp.u(1), format(
        'UPDATE public.accounts SET name = %L WHERE id = %L', 'wa2 renamed', pg_temp.id('WA2'))), '1');
    PERFORM pg_temp.check('she does not name it', pg_temp.write(pg_temp.u(2), format(
        'UPDATE public.accounts SET name = %L WHERE id = %L', 'mine', pg_temp.id('WA2'))), '0');

    -- Assigned again only by him, only to a wife, only before it has history.
    PERFORM pg_temp.check('H reassigns a new one', pg_temp.j(pg_temp.assign(1, 'WA2', 3), 'changed'), 'true');
    PERFORM pg_temp.check('now W2''s', (SELECT assigned_wife_id::text FROM public.accounts WHERE id = pg_temp.id('WA2')), pg_temp.u(3)::text);
    PERFORM pg_temp.check('and back', pg_temp.j(pg_temp.assign(1, 'WA2', 2), 'changed'), 'true');
    PERFORM pg_temp.check('the same again changes nothing', pg_temp.j(pg_temp.assign(1, 'WA2', 2), 'changed'), 'false');
    PERFORM pg_temp.check('C, husband present, does not see it', pg_temp.assign(5, 'WA2', 3), 'ERR:account_not_found');
    PERFORM pg_temp.check('W2 does not see it', pg_temp.assign(3, 'WA2', 3), 'ERR:account_not_found');
    PERFORM pg_temp.check('W sees it but does not assign', pg_temp.assign(2, 'WA2', 3), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('to a member', pg_temp.assign(1, 'WA2', 4), 'ERR:not_a_wife');
END $$;

-- ── 2. Who sees it ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    -- Funded by H, from his bank and from the pool; an ordinary transfer for comparison.
    PERFORM pg_temp.check('H funds WA1 from his bank', pg_temp.move(1, 1, pg_temp.a(3), pg_temp.id('WA1'), 200, 'x01'), 'x01');
    PERFORM pg_temp.check('H funds WA1 from the pool', pg_temp.move(1, 1, pg_temp.a(1), pg_temp.id('WA1'), 100, 'x02'), 'x02');
    PERFORM pg_temp.check('H funds WC', pg_temp.move(1, 1, pg_temp.a(3), pg_temp.id('WC'), 50, 'x04'), 'x04');
    PERFORM pg_temp.check('K pays the pool', pg_temp.move(4, 1, pg_temp.a(4), pg_temp.a(1), 10, 'x03'), 'x03');
    PERFORM pg_temp.check('WA1 holds 300', pg_temp.wbal('WA1'), '300.00');
    PERFORM pg_temp.check('the rows are marked', (SELECT string_agg(notes || '=' || touches_wife_account, ',' ORDER BY notes)
                                                  FROM public.account_transfers WHERE household_id = pg_temp.h(1)),
                          'x01=true,x02=true,x03=false,x04=true');
    PERFORM pg_temp.check('her id is on her account''s rows', (SELECT string_agg(notes, ',' ORDER BY notes) FROM public.account_transfers
                                                               WHERE household_id = pg_temp.h(1) AND pg_temp.u(2) = ANY (personal_owner_ids)), 'x01,x02');

    -- Husband present.
    PERFORM pg_temp.check('present: H', pg_temp.vis(1), 'WA1,WA2,WC');
    PERFORM pg_temp.check('present: W (hers only)', pg_temp.vis(2), 'WA1,WA2');
    PERFORM pg_temp.check('present: W2 (hers only)', pg_temp.vis(3), 'WC');
    PERFORM pg_temp.check('present: K', pg_temp.vis(4), '');
    PERFORM pg_temp.check('present: C, an admin who is not a wife', pg_temp.vis(5), '');
    PERFORM pg_temp.check('present: WA, a wife-admin', pg_temp.vis(6), '');
    PERFORM pg_temp.check('present: W reads its balance', pg_temp.call(pg_temp.u(2), format('SELECT balance::text FROM public.accounts WHERE id = %L', pg_temp.id('WA1'))), '300.00');
    PERFORM pg_temp.check('present: x01 (his bank to hers)', pg_temp.treaders('x01'), 'H,W');
    PERFORM pg_temp.check('present: x02 (the pool to hers)', pg_temp.treaders('x02'), 'H,W');
    PERFORM pg_temp.check('present: x04 (to the co-wife''s)', pg_temp.treaders('x04'), 'H,W2');
    PERFORM pg_temp.check('present: x03 (ordinary)', pg_temp.treaders('x03'), 'H,W,W2,K,C,WA');
    -- Not even that it exists: a transfer into it is answered as into no account.
    PERFORM pg_temp.check('W2 pays into WA1', pg_temp.move(3, 1, pg_temp.a(5), pg_temp.id('WA1'), 1, 'y'), 'ERR:P0002');
    PERFORM pg_temp.check('W2 pays into nothing', pg_temp.move(3, 1, pg_temp.a(5), gen_random_uuid(), 1, 'y'), 'ERR:P0002');
    PERFORM pg_temp.check('K pays into WA1', pg_temp.move(4, 1, pg_temp.a(4), pg_temp.id('WA1'), 1, 'y'), 'ERR:P0002');
    PERFORM pg_temp.check('C pays into WA1', pg_temp.move(5, 1, pg_temp.a(6), pg_temp.id('WA1'), 1, 'y'), 'ERR:P0002');
    PERFORM pg_temp.check('K spends from WA1', pg_temp.spend(4, 1, 90, pg_temp.id('WA1'), 1, NULL, 0), 'ERR:42501');
    PERFORM pg_temp.check('K spending from WA1 is told what any account not his tells',
        pg_temp.msg(4, format('INSERT INTO public.transactions (household_id, user_id, amount, category_code, account_id) VALUES (%L, %L, 1, %L, %L)',
                              pg_temp.h(1), pg_temp.u(4), 'OPEX-SHOPPING', pg_temp.id('WA1'))),
        pg_temp.msg(4, format('INSERT INTO public.transactions (household_id, user_id, amount, category_code, account_id) VALUES (%L, %L, 1, %L, %L)',
                              pg_temp.h(1), pg_temp.u(4), 'OPEX-SHOPPING', pg_temp.a(5))));

    -- Husband gone (he left, or was never named): the admins who are not wives, and still the owner.
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('gone: H (its owner)', pg_temp.vis(1), 'WA1,WA2,WC');
    PERFORM pg_temp.check('gone: W', pg_temp.vis(2), 'WA1,WA2');
    PERFORM pg_temp.check('gone: W2', pg_temp.vis(3), 'WC');
    PERFORM pg_temp.check('gone: K', pg_temp.vis(4), '');
    PERFORM pg_temp.check('gone: C', pg_temp.vis(5), 'WA1,WA2,WC');
    PERFORM pg_temp.check('gone: WA', pg_temp.vis(6), '');
    PERFORM pg_temp.check('gone: x01', pg_temp.treaders('x01'), 'H,W,C');
    PERFORM pg_temp.check('gone: x04', pg_temp.treaders('x04'), 'H,W2,C');
    -- Replaced (the member K is the provider now): the new husband, and still the owner.
    PERFORM pg_temp.provider(4);
    PERFORM pg_temp.check('replaced: H (its owner)', pg_temp.vis(1), 'WA1,WA2,WC');
    PERFORM pg_temp.check('replaced: K (her husband now)', pg_temp.vis(4), 'WA1,WA2,WC');
    PERFORM pg_temp.check('replaced: C', pg_temp.vis(5), '');
    PERFORM pg_temp.check('replaced: W2', pg_temp.vis(3), 'WC');
    PERFORM pg_temp.check('replaced: x01', pg_temp.treaders('x01'), 'H,W,K');
    PERFORM pg_temp.check('replaced: the owner still funds it', pg_temp.move(1, 1, pg_temp.a(3), pg_temp.id('WC'), 5, 'x05'), 'x05');
    PERFORM pg_temp.check('replaced: a new husband creates one', pg_temp.create(1, 1, 2, 'x'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.provider(1);
END $$;

-- ── 3. Using it ───────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('W buys for herself from WA1', pg_temp.spend(2, 1, 20, pg_temp.id('WA1'), 50, 'wife_personal', 2), '1');
    PERFORM pg_temp.check('W advances from WA1', pg_temp.spend(2, 1, 21, pg_temp.id('WA1'), 30, 'wife_reimbursable', 2), '1');
    PERFORM pg_temp.check('WA1: 300 - 50 - 30', pg_temp.wbal('WA1'), '220.00');
    PERFORM pg_temp.check('W spends on something else from it', pg_temp.spend(2, 1, 22, pg_temp.id('WA1'), 5, NULL, 0), 'ERR:42501');
    PERFORM pg_temp.check('H spends from it', pg_temp.spend(1, 1, 23, pg_temp.id('WA1'), 5, NULL, 0), 'ERR:42501');
    PERFORM pg_temp.check('H buys her something from it', pg_temp.spend(1, 1, 24, pg_temp.id('WA1'), 5, 'wife_personal', 2), 'ERR:42501');
    PERFORM pg_temp.check('W2 spends from it', pg_temp.spend(3, 1, 25, pg_temp.id('WA1'), 5, 'wife_personal', 3), 'ERR:23514');
    PERFORM pg_temp.check('W spends from the co-wife''s', pg_temp.spend(2, 1, 26, pg_temp.id('WC'), 5, 'wife_personal', 2), 'ERR:23514');
    PERFORM pg_temp.check('C spends from it', pg_temp.spend(5, 1, 27, pg_temp.id('WA1'), 5, NULL, 0), 'ERR:42501');
    PERFORM pg_temp.check('W unclassifies her purchase on it', pg_temp.write(pg_temp.u(2), format(
        'UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(20))), 'ERR:42501');
    PERFORM pg_temp.check('W moves her purchase onto the co-wife''s', pg_temp.write(pg_temp.u(2), format(
        'UPDATE public.transactions SET account_id = %L WHERE id = %L', pg_temp.id('WC'), pg_temp.t(20))), 'ERR:23514');
    PERFORM pg_temp.check('WA1 unchanged', pg_temp.wbal('WA1'), '220.00');
    -- Nothing leaves it by a transfer; only its owner or her ledger's managers fund it.
    PERFORM pg_temp.check('W takes it out', pg_temp.move(2, 1, pg_temp.id('WA1'), pg_temp.a(2), 10, 'y'), 'ERR:wife_account_no_transfer_out');
    PERFORM pg_temp.check('H takes it out', pg_temp.move(1, 1, pg_temp.id('WA1'), pg_temp.a(3), 10, 'y'), 'ERR:wife_account_no_transfer_out');
    PERFORM pg_temp.check('W tops it up from her own bank', pg_temp.move(2, 1, pg_temp.a(2), pg_temp.id('WA1'), 10, 'y'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('nothing moved', pg_temp.wbal('WA1') || '|' || pg_temp.bal(2) || '|' || pg_temp.bal(3), '220.00|400.00|2745.00');
END $$;

-- ── 4. A repayment credits her wife account ──────────────────────────────────────────────────
DO $$
DECLARE
    v_res text;
    v_budgets text := pg_temp.budgets();
    v_allowance text := pg_temp.allowance();
    v_n text := (SELECT count(*)::text FROM public.transactions WHERE household_id = pg_temp.h(1));
BEGIN
    -- Owed to W: 600 + 30 = 630.
    v_res := pg_temp.repay(1, 1, 2, '100', pg_temp.a(3), pg_temp.id('WA1'), 1);
    PERFORM pg_temp.keep('r1', v_res);
    PERFORM pg_temp.check('the repayment answers its accounts', pg_temp.j(v_res, 'account_id') || '|' || pg_temp.j(v_res, 'wife_account_id')
                          || '|' || pg_temp.j(v_res, 'outstanding_before') || '|' || pg_temp.j(v_res, 'outstanding_after'),
                          pg_temp.a(3) || '|' || pg_temp.id('WA1') || '|630.00|530.00');
    PERFORM pg_temp.check('his bank: exactly 100 less', pg_temp.bal(3), '2645.00');
    PERFORM pg_temp.check('WA1: exactly 100 more', pg_temp.wbal('WA1'), '320.00');
    PERFORM pg_temp.check('one transfer, his to hers', pg_temp.moved(v_res), pg_temp.a(3) || '|' || pg_temp.id('WA1') || '|wife_repayment|100.00');
    PERFORM pg_temp.check('her own bank is never credited', pg_temp.bal(2), '400.00');
    PERFORM pg_temp.check('budgets unchanged', pg_temp.budgets(), v_budgets);
    PERFORM pg_temp.check('her allowance unchanged', pg_temp.allowance(), v_allowance);
    PERFORM pg_temp.check('no transaction', (SELECT count(*)::text FROM public.transactions WHERE household_id = pg_temp.h(1)), v_n);
    PERFORM pg_temp.check('the row keeps it', (SELECT wife_account_id::text FROM public.spouse_reimbursements
                                               WHERE id = (v_res::jsonb ->> 'reimbursement_id')::uuid), pg_temp.id('WA1')::text);
    PERFORM pg_temp.check('W reads the line', pg_temp.call(pg_temp.u(2), format('SELECT count(*)::text FROM public.account_transfers WHERE id = %L',
                          (SELECT transfer_id FROM public.spouse_reimbursements WHERE id = (v_res::jsonb ->> 'reimbursement_id')::uuid))), '1');
    PERFORM pg_temp.check('who reads the line', pg_temp.xreaders((SELECT transfer_id FROM public.spouse_reimbursements
                                                                  WHERE id = (v_res::jsonb ->> 'reimbursement_id')::uuid)), 'H,W');

    -- Replays: the same tap answers the same and moves nothing; another wife account is another call.
    v_res := pg_temp.repay(1, 1, 2, '100', pg_temp.a(3), pg_temp.id('WA1'), 1);
    PERFORM pg_temp.check('replayed', pg_temp.j(v_res, 'replayed') || '|' || pg_temp.j(v_res, 'wife_account_id'), 'true|' || pg_temp.id('WA1'));
    PERFORM pg_temp.check('replay moved nothing', pg_temp.bal(3) || '|' || pg_temp.wbal('WA1'), '2645.00|320.00');
    PERFORM pg_temp.check('the key into another wife account', pg_temp.repay(1, 1, 2, '100', pg_temp.a(3), pg_temp.id('WA2'), 1), 'ERR:request_key_reused');

    -- Never an account that is not hers.
    PERFORM pg_temp.check('into the co-wife''s', pg_temp.repay(1, 1, 2, '10', pg_temp.a(3), pg_temp.id('WC'), 2), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('into her own bank', pg_temp.repay(1, 1, 2, '10', pg_temp.a(3), pg_temp.a(2), 2), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('into his own bank', pg_temp.repay(1, 1, 2, '10', pg_temp.a(3), pg_temp.a(3), 2), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('into no account', pg_temp.repay(1, 1, 2, '10', pg_temp.a(3), NULL, 2), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('into nothing', pg_temp.repay(1, 1, 2, '10', pg_temp.a(3), gen_random_uuid(), 2), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('a wife with none', pg_temp.repay(1, 1, 6, '10', pg_temp.a(3), NULL, 2), 'ERR:wife_account_required');
    PERFORM pg_temp.check('a wife with none, naming W''s', pg_temp.repay(1, 1, 6, '10', pg_temp.a(3), pg_temp.id('WA1'), 2), 'ERR:wife_account_required');
    PERFORM pg_temp.check('paid from a wife account', pg_temp.repay(1, 1, 2, '10', pg_temp.id('WA2'), pg_temp.id('WA1'), 2), 'ERR:account_unavailable');
    PERFORM pg_temp.check('C, husband present', pg_temp.repay(5, 1, 2, '10', pg_temp.a(6), pg_temp.id('WA1'), 2), 'ERR:forbidden');
    PERFORM pg_temp.check('W records her own', pg_temp.repay(2, 1, 2, '10', pg_temp.a(2), pg_temp.id('WA1'), 2), 'ERR:wife_must_request');
    PERFORM pg_temp.check('nothing moved by the refusals', pg_temp.bal(3) || '|' || pg_temp.wbal('WA1') || '|' || pg_temp.wbal('WA2') || '|' || pg_temp.wbal('WC'),
                          '2645.00|320.00|0.00|55.00');

    -- From the pool (he is an admin), into WA2.
    v_res := pg_temp.repay(1, 1, 2, '50', pg_temp.a(1), pg_temp.id('WA2'), 3);
    PERFORM pg_temp.check('the pool: exactly 50 less', pg_temp.bal(1), '4860.00');
    PERFORM pg_temp.check('WA2: exactly 50 more', pg_temp.wbal('WA2'), '50.00');
    PERFORM pg_temp.check('pool line readers', pg_temp.xreaders((SELECT transfer_id FROM public.spouse_reimbursements
                                                                 WHERE id = (v_res::jsonb ->> 'reimbursement_id')::uuid)), 'H,W');
    PERFORM pg_temp.check('budgets still unchanged', pg_temp.budgets(), v_budgets);
END $$;

-- ── 5. Her request names one of hers; the approval uses it ────────────────────────────────────
DO $$
DECLARE
    v_res text;
BEGIN
    -- Owed now: 630 - 100 - 50 = 480.
    v_res := pg_temp.ask(2, '60', pg_temp.id('WA2'), 10);
    PERFORM pg_temp.keep('q1', pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('her request names WA2', pg_temp.j(v_res, 'status') || '|' || pg_temp.j(v_res, 'wife_account_id'), 'pending|' || pg_temp.id('WA2'));
    PERFORM pg_temp.check('a request moves nothing', pg_temp.wbal('WA2'), '50.00');
    PERFORM pg_temp.check('into the co-wife''s', pg_temp.ask(2, '10', pg_temp.id('WC'), 11), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('into her own bank', pg_temp.ask(2, '10', pg_temp.a(2), 11), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('into none', pg_temp.ask(2, '10', NULL, 11), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('a wife with none asks', pg_temp.ask(6, '10', NULL, 11), 'ERR:wife_account_required');
    PERFORM pg_temp.check('the same key, another account', pg_temp.ask(2, '60', pg_temp.id('WA1'), 10), 'ERR:request_key_reused');
    PERFORM pg_temp.check('the same key, the same', pg_temp.j(pg_temp.ask(2, '60', pg_temp.id('WA2'), 10), 'replayed'), 'true');

    -- Approved as she said.
    v_res := pg_temp.approve(1, pg_temp.id('q1'), pg_temp.a(3), NULL, 12);
    PERFORM pg_temp.check('approved into WA2', pg_temp.j(v_res, 'wife_account_id'), pg_temp.id('WA2')::text);
    PERFORM pg_temp.check('his bank -60, WA2 +60', pg_temp.bal(3) || '|' || pg_temp.wbal('WA2'), '2585.00|110.00');
    PERFORM pg_temp.check('one transfer', pg_temp.moved(v_res), pg_temp.a(3) || '|' || pg_temp.id('WA2') || '|wife_repayment|60.00');
    PERFORM pg_temp.check('approval replay', pg_temp.j(pg_temp.approve(1, pg_temp.id('q1'), pg_temp.a(3), NULL, 12), 'replayed'), 'true');
    PERFORM pg_temp.check('approval replay naming the same', pg_temp.j(pg_temp.approve(1, pg_temp.id('q1'), pg_temp.a(3), pg_temp.id('WA2'), 12), 'replayed'), 'true');
    PERFORM pg_temp.check('approval key, another wife account', pg_temp.approve(1, pg_temp.id('q1'), pg_temp.a(3), pg_temp.id('WA1'), 12), 'ERR:request_key_reused');

    -- He switches it to another of hers.
    PERFORM pg_temp.keep('q2', pg_temp.j(pg_temp.ask(2, '40', pg_temp.id('WA2'), 13), 'request_id'));
    PERFORM pg_temp.check('he switches to the co-wife''s', pg_temp.approve(1, pg_temp.id('q2'), pg_temp.a(3), pg_temp.id('WC'), 14), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('he switches to his bank', pg_temp.approve(1, pg_temp.id('q2'), pg_temp.a(3), pg_temp.a(3), 14), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('he switches to her own bank', pg_temp.approve(1, pg_temp.id('q2'), pg_temp.a(3), pg_temp.a(2), 14), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('still pending', (SELECT count(*)::text FROM public.spouse_reimbursement_request_outcomes WHERE request_id = pg_temp.id('q2')), '0');
    v_res := pg_temp.approve(1, pg_temp.id('q2'), pg_temp.a(3), pg_temp.id('WA1'), 14);
    PERFORM pg_temp.check('he switches to WA1', pg_temp.j(v_res, 'wife_account_id'), pg_temp.id('WA1')::text);
    PERFORM pg_temp.check('his bank -40, WA1 +40, WA2 the same', pg_temp.bal(3) || '|' || pg_temp.wbal('WA1') || '|' || pg_temp.wbal('WA2'),
                          '2545.00|360.00|110.00');
    -- A wife account archived after her request: he picks another of hers.
    PERFORM pg_temp.keep('WA3', pg_temp.j(pg_temp.create(1, 1, 2, 'wa3'), 'id'));
    PERFORM pg_temp.keep('q3', pg_temp.j(pg_temp.ask(2, '5', pg_temp.id('WA3'), 15), 'request_id'));
    PERFORM pg_temp.check('a pending request is history', pg_temp.assign(1, 'WA3', 3), 'ERR:wife_account_has_history');
    -- Her purchase alone is history too (no transfer, no request on it).
    PERFORM pg_temp.keep('WA5', pg_temp.j(pg_temp.create(1, 1, 2, 'wa5'), 'id'));
    PERFORM pg_temp.check('she spends from a new one', pg_temp.spend(2, 1, 32, pg_temp.id('WA5'), 1, 'wife_personal', 2), '1');
    PERFORM pg_temp.check('a purchase is history', pg_temp.assign(1, 'WA5', 3), 'ERR:wife_account_has_history');
    PERFORM pg_temp.check('a transfer is history', pg_temp.assign(1, 'WA1', 3), 'ERR:wife_account_has_history');
    PERFORM pg_temp.check('he archives WA3', pg_temp.j(pg_temp.archive(1, 1, 'WA3'), 'is_archived'), 'true');
    PERFORM pg_temp.check('her choice is archived', pg_temp.approve(1, pg_temp.id('q3'), pg_temp.a(3), NULL, 16), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('he picks WA2', pg_temp.j(pg_temp.approve(1, pg_temp.id('q3'), pg_temp.a(3), pg_temp.id('WA2'), 16), 'wife_account_id'), pg_temp.id('WA2')::text);
    PERFORM pg_temp.check('WA2 +5', pg_temp.wbal('WA2'), '115.00');
    -- Approving is the husband's, as before.
    PERFORM pg_temp.keep('q4', pg_temp.j(pg_temp.ask(2, '1', pg_temp.id('WA2'), 17), 'request_id'));
    PERFORM pg_temp.check('C approves, husband present', pg_temp.approve(5, pg_temp.id('q4'), pg_temp.a(6), NULL, 18), 'ERR:forbidden');
    PERFORM pg_temp.check('W approves her own', pg_temp.approve(2, pg_temp.id('q4'), pg_temp.a(2), NULL, 18), 'ERR:forbidden');
END $$;

-- ── 6. A reversal takes it back out of her wife account ───────────────────────────────────────
DO $$
DECLARE
    v_res text;
    v_r1 uuid := (SELECT (val::jsonb ->> 'reimbursement_id')::uuid FROM pg_temp.snap WHERE label = 'r1');
    v_owed text;
BEGIN
    v_owed := pg_temp.call(pg_temp.u(1), format('SELECT (public.get_spouse_reimbursement_balance(%L, %L, NULL) ->> %L)', pg_temp.h(1), pg_temp.u(2), 'outstanding'));
    v_res := pg_temp.rev(1, v_r1, 20);
    PERFORM pg_temp.check('reversed', pg_temp.j(v_res, 'kind') || '|' || pg_temp.j(v_res, 'wife_account_id'), 'reversal|' || pg_temp.id('WA1'));
    PERFORM pg_temp.check('WA1 -100, his bank +100', pg_temp.wbal('WA1') || '|' || pg_temp.bal(3), '260.00|2640.00');
    PERFORM pg_temp.check('one transfer back, hers to his', pg_temp.moved(v_res), pg_temp.id('WA1') || '|' || pg_temp.a(3) || '|wife_repayment_reversal|100.00');
    PERFORM pg_temp.check('owed again', pg_temp.call(pg_temp.u(1), format('SELECT (public.get_spouse_reimbursement_balance(%L, %L, NULL) ->> %L)', pg_temp.h(1), pg_temp.u(2), 'outstanding')),
                          (v_owed::numeric + 100)::numeric(14, 2)::text);
    PERFORM pg_temp.check('W reads the reversal line', pg_temp.xreaders((SELECT transfer_id FROM public.spouse_reimbursements
                                                                         WHERE id = (v_res::jsonb ->> 'reimbursement_id')::uuid)), 'H,W');
    PERFORM pg_temp.check('reversal replay', pg_temp.j(pg_temp.rev(1, v_r1, 20), 'replayed'), 'true');
    PERFORM pg_temp.check('replay moved nothing', pg_temp.wbal('WA1') || '|' || pg_temp.bal(3), '260.00|2640.00');

    -- She spent it: refused, nothing moves.
    v_res := pg_temp.repay(1, 1, 2, '200', pg_temp.a(3), pg_temp.id('WA2'), 21);
    PERFORM pg_temp.keep('r21', v_res);
    PERFORM pg_temp.check('WA2 holds 315', pg_temp.wbal('WA2'), '315.00');
    PERFORM pg_temp.check('she spends 300 of it', pg_temp.spend(2, 1, 30, pg_temp.id('WA2'), 300, 'wife_personal', 2), '1');
    PERFORM pg_temp.check('reversal of 200 from 15', pg_temp.rev(1, (v_res::jsonb ->> 'reimbursement_id')::uuid, 22), 'ERR:wife_account_insufficient_funds');
    PERFORM pg_temp.check('nothing moved', pg_temp.wbal('WA2') || '|' || pg_temp.bal(3) || '|'
                          || (SELECT count(*) FROM public.spouse_reimbursements WHERE reverses_id = (v_res::jsonb ->> 'reimbursement_id')::uuid),
                          '15.00|2440.00|0');
    PERFORM pg_temp.check('the key was not used', (SELECT count(*)::text FROM public.nafaqah_request_keys WHERE request_key = pg_temp.k(22)), '0');

    -- Archived: refused as for any archived account.
    PERFORM pg_temp.keep('WA4', pg_temp.j(pg_temp.create(1, 1, 2, 'wa4'), 'id'));
    v_res := pg_temp.repay(1, 1, 2, '30', pg_temp.a(3), pg_temp.id('WA4'), 23);
    PERFORM pg_temp.check('WA4 +30', pg_temp.wbal('WA4'), '30.00');
    PERFORM pg_temp.check('W does not archive it', pg_temp.archive(2, 1, 'WA4'), 'ERR:wife_account_forbidden');
    PERFORM pg_temp.check('K does not see it', pg_temp.archive(4, 1, 'WA4'), 'ERR:account_not_found');
    PERFORM pg_temp.check('H archives it', pg_temp.j(pg_temp.archive(1, 1, 'WA4'), 'changed'), 'true');
    PERFORM pg_temp.check('the reversal refused', pg_temp.rev(1, (v_res::jsonb ->> 'reimbursement_id')::uuid, 24), 'ERR:reversal_account_unavailable');
    PERFORM pg_temp.check('nothing moved', pg_temp.wbal('WA4') || '|' || pg_temp.bal(3), '30.00|2410.00');
    PERFORM pg_temp.check('archived: no repayment into it', pg_temp.repay(1, 1, 2, '1', pg_temp.a(3), pg_temp.id('WA4'), 25), 'ERR:wife_account_invalid');
    PERFORM pg_temp.check('archived: she does not spend it', pg_temp.spend(2, 1, 31, pg_temp.id('WA4'), 1, 'wife_personal', 2), 'ERR:23514');
    PERFORM pg_temp.check('archived: he does not fund it', pg_temp.move(1, 1, pg_temp.a(3), pg_temp.id('WA4'), 1, 'y'), 'ERR:account_unavailable');
    PERFORM pg_temp.check('archived: she still reads it', pg_temp.vis(2), 'WA1,WA2,WA3,WA4');
END $$;

-- ── 7. No client deletes a wife account a repayment used ──────────────────────────────────────
DO $$
DECLARE
    v_id uuid;
BEGIN
    PERFORM pg_temp.check('H deletes WA1', pg_temp.write(pg_temp.u(1), format('DELETE FROM public.accounts WHERE id = %L', pg_temp.id('WA1'))), 'ERR:23503');
    PERFORM pg_temp.check('W deletes WA1', pg_temp.write(pg_temp.u(2), format('DELETE FROM public.accounts WHERE id = %L', pg_temp.id('WA1'))), '0');
    v_id := (pg_temp.create(1, 1, 2, 'fresh')::jsonb ->> 'id')::uuid;
    PERFORM pg_temp.check('a new one with no history goes', pg_temp.write(pg_temp.u(1), format('DELETE FROM public.accounts WHERE id = %L', v_id)), '1');
END $$;

-- ── 8. Her purge: archived, his, naming nobody; a former member's payment credits nothing ──────
DO $$
DECLARE
    v_before text := (SELECT string_agg(id || '=' || balance || ':' || owner_user_id, ',' ORDER BY id) FROM public.accounts WHERE household_id = pg_temp.h(1));
    v_res text;
    v_debt uuid;
BEGIN
    PERFORM pg_temp.check('her purchases on them exist', (SELECT count(*)::text FROM public.transactions WHERE nafaqah_spouse_id = pg_temp.u(2)
                                                          AND nafaqah_class = 'wife_personal' AND account_id IS NOT NULL), '3');
    v_res := pg_temp.purge(2);
    PERFORM pg_temp.check('her purge is prepared (the ledger invariant held)', pg_temp.j(v_res, 'prepared') || '|' || pg_temp.j(v_res, 'deferred'), 'true|false');
    DELETE FROM pg_temp.people WHERE n = 2;
    PERFORM pg_temp.check('every balance and owner of F1 is as it was (her own bank gone)',
        (SELECT string_agg(id || '=' || balance || ':' || owner_user_id, ',' ORDER BY id) FROM public.accounts WHERE household_id = pg_temp.h(1)),
        (SELECT string_agg(x, ',' ORDER BY x) FROM unnest(string_to_array(v_before, ',')) x WHERE x NOT LIKE pg_temp.a(2) || '=%'));
    PERFORM pg_temp.check('her wife accounts: archived, his, naming nobody',
        (SELECT string_agg(is_archived || ':' || owner_user_id || ':' || COALESCE(assigned_wife_id::text, '-'), ',')
         FROM (SELECT DISTINCT is_archived, owner_user_id, assigned_wife_id FROM public.accounts
               WHERE id IN (pg_temp.id('WA1'), pg_temp.id('WA2'), pg_temp.id('WA3'), pg_temp.id('WA4'))) s),
        'true:' || pg_temp.u(1) || ':-');
    PERFORM pg_temp.check('her name left its name', (SELECT name FROM public.accounts WHERE id = pg_temp.id('WA1')), 'deleted_member card');
    PERFORM pg_temp.check('her purchases went', (SELECT count(*)::text FROM public.transactions WHERE id IN (pg_temp.t(20), pg_temp.t(30))), '0');
    PERFORM pg_temp.check('H reads them', pg_temp.vis(1), 'WA1,WA2,WA3,WA4,WC');
    PERFORM pg_temp.check('W2 reads none of hers', pg_temp.vis(3), 'WC');
    PERFORM pg_temp.check('C reads none (husband present)', pg_temp.vis(5), '');
    PERFORM pg_temp.check('K reads none', pg_temp.vis(4), '');
    PERFORM pg_temp.check('WA reads none', pg_temp.vis(6), '');
    PERFORM pg_temp.check('x01 now', pg_temp.treaders('x01'), 'H');
    -- Gone: the admins who are not wives read a former wife's account, still not a wife or a member.
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('husband gone: C', pg_temp.vis(5), 'WA1,WA2,WA3,WA4,WC');
    PERFORM pg_temp.check('husband gone: WA', pg_temp.vis(6), '');
    PERFORM pg_temp.provider(1);

    -- What he still owed her is a former member's record; its payment credits nothing.
    SELECT id INTO v_debt FROM public.former_member_debts WHERE household_id = pg_temp.h(1);
    PERFORM pg_temp.check('a record was kept', (v_debt IS NOT NULL)::text, 'true');
    v_res := pg_temp.call(pg_temp.u(1), format('SELECT public.record_former_member_debt_payment(%L, %L, 10, %L, %L::uuid, NULL, %L::uuid)::text',
                                               pg_temp.h(1), v_debt, 'cash', pg_temp.k(40), pg_temp.a(3)));
    PERFORM pg_temp.check('its payment leaves his bank for no account',
        (SELECT COALESCE(from_account_id::text, '-') || '|' || COALESCE(to_account_id::text, '-') || '|' || purpose
         FROM public.account_transfers WHERE id = (v_res::jsonb ->> 'transfer_id')::uuid),
        pg_temp.a(3) || '|-|former_member_payment');
    PERFORM pg_temp.check('no wife account moved', pg_temp.wbal('WA1') || '|' || pg_temp.wbal('WA2') || '|' || pg_temp.wbal('WA4'), '260.00|15.00|30.00');

    PERFORM pg_temp.check('her Auth delete completes', pg_temp.complete(2), 'true');
    PERFORM pg_temp.check('her id nowhere', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.check('her name nowhere', pg_temp.scan('T68 User 2'), '');
    PERFORM pg_temp.check('the balances stay', pg_temp.wbal('WA1') || '|' || pg_temp.wbal('WA2') || '|' || pg_temp.wbal('WA4'), '260.00|15.00|30.00');
    PERFORM pg_temp.check('x01 still his', pg_temp.treaders('x01'), 'H');
END $$;

-- ── 9. His purge: to the primary admin, or to her when that admin is a co-wife ────────────────
DO $$
DECLARE
    v_res text;
    v_va text;
    v_za text;
    v_tx uuid;
BEGIN
    -- F2: H2 funds and repays into V's account; she spends some.
    PERFORM pg_temp.check('H2 funds VA', pg_temp.move(8, 2, pg_temp.a(7), pg_temp.id('VA'), 500, 'f2x'), 'f2x');
    PERFORM pg_temp.check('V spends 20', pg_temp.spend(9, 2, 40, pg_temp.id('VA'), 20, 'wife_personal', 9), '1');
    v_res := pg_temp.call(pg_temp.u(8), format('SELECT public.record_spouse_reimbursement(%L, %L, 100, %L, NULL, NULL, %L::uuid, %L::uuid, %L::uuid)::text',
                                               pg_temp.h(2), pg_temp.u(9), 'cash', pg_temp.a(7), pg_temp.k(50), pg_temp.id('VA')));
    PERFORM pg_temp.check('F2 repayment into VA', pg_temp.wbal('VA') || '|' || pg_temp.bal(7), '580.00|1400.00');
    v_tx := (SELECT id FROM public.account_transfers WHERE notes = 'f2x');
    PERFORM pg_temp.check('D does not read VA while H2 is there', pg_temp.call(pg_temp.u(7), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('VA'))), '0');
    -- F3: H3 funds Z's account.
    PERFORM pg_temp.check('H3 funds ZA', pg_temp.move(11, 3, pg_temp.a(8), pg_temp.id('ZA'), 300, 'f3x'), 'f3x');
    v_va := pg_temp.wbal('VA');
    v_za := pg_temp.wbal('ZA');

    v_res := pg_temp.purge(8);
    PERFORM pg_temp.check('his purge is prepared (the ledger invariant held)', pg_temp.j(v_res, 'prepared') || '|' || pg_temp.j(v_res, 'deferred'), 'true|false');
    PERFORM pg_temp.check('VA passed to the primary admin', (SELECT owner_user_id::text || '|' || assigned_wife_id || '|' || is_archived || '|' || balance
                                                             FROM public.accounts WHERE id = pg_temp.id('VA')),
                          pg_temp.u(7) || '|' || pg_temp.u(9) || '|false|' || v_va);
    PERFORM pg_temp.check('its funding row stays', (SELECT count(*)::text FROM public.account_transfers WHERE id = v_tx), '1');
    PERFORM pg_temp.check('D reads VA and its history', pg_temp.call(pg_temp.u(7), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('VA')))
                          || '|' || pg_temp.call(pg_temp.u(7), format('SELECT count(*)::text FROM public.account_transfers WHERE id = %L', v_tx)), '1|1');
    -- With no provider left a family records no classified expense (rule 3): D names one, himself.
    PERFORM pg_temp.check('no provider: she cannot classify yet', pg_temp.spend(9, 2, 41, pg_temp.id('VA'), 30, 'wife_personal', 9), 'ERR:23514');
    UPDATE public.households SET nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);
    PERFORM pg_temp.check('V reads it and spends from it', pg_temp.spend(9, 2, 41, pg_temp.id('VA'), 30, 'wife_personal', 9), '1');
    PERFORM pg_temp.check('VA after her purchase', pg_temp.wbal('VA'), (v_va::numeric - 30)::numeric(14, 2)::text);
    PERFORM pg_temp.check('his Auth delete completes', pg_temp.complete(8), 'true');
    PERFORM pg_temp.check('his id nowhere', pg_temp.scan(pg_temp.u(8)::text), '');
    PERFORM pg_temp.check('D still reads its history', pg_temp.call(pg_temp.u(7), format('SELECT count(*)::text FROM public.account_transfers WHERE id = %L', v_tx)), '1');

    v_res := pg_temp.purge(11);
    PERFORM pg_temp.check('F3 purge prepared', pg_temp.j(v_res, 'prepared') || '|' || pg_temp.j(v_res, 'deferred'), 'true|false');
    PERFORM pg_temp.check('ZA passed to her, not to the co-wife who is primary admin',
                          (SELECT owner_user_id::text || '|' || assigned_wife_id || '|' || balance FROM public.accounts WHERE id = pg_temp.id('ZA')),
                          pg_temp.u(12) || '|' || pg_temp.u(12) || '|' || v_za);
    PERFORM pg_temp.check('Y does not read ZA', pg_temp.call(pg_temp.u(10), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('ZA'))), '0');
    PERFORM pg_temp.check('Y does not read its funding', pg_temp.call(pg_temp.u(10), 'SELECT count(*)::text FROM public.account_transfers WHERE notes = ''f3x'''), '0');
    PERFORM pg_temp.check('Z reads it', pg_temp.call(pg_temp.u(12), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('ZA'))), '1');
    PERFORM pg_temp.check('F3 Auth delete', pg_temp.complete(11), 'true');
END $$;

-- ── 10. Privileges and objects ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('clients call the three RPCs, anon none',
        (SELECT string_agg(has_function_privilege('authenticated', s, 'EXECUTE') || '/' || has_function_privilege('anon', s, 'EXECUTE'), ',')
         FROM unnest(ARRAY['public.create_wife_account(uuid, uuid, text, uuid)', 'public.assign_wife_account(uuid, uuid, uuid, uuid)',
                           'public.archive_wife_account(uuid, uuid, uuid)']) s),
        'true/false,true/false,true/false');
    PERFORM pg_temp.check('nobody calls the money helpers',
        (SELECT string_agg((has_function_privilege('authenticated', s, 'EXECUTE') OR has_function_privilege('service_role', s, 'EXECUTE'))::text, ',')
         FROM unnest(ARRAY['public.nafaqah_repayment_transfer(uuid, uuid, uuid, uuid, numeric, text)',
                           'public.nafaqah_repayment_lock(uuid, uuid, uuid, uuid, uuid)',
                           'public.nafaqah_require_wife_account(uuid, uuid, uuid)']) s),
        'false,false,false');
    PERFORM pg_temp.check('no client calls the visibility helper',
        has_function_privilege('authenticated', 'public.nafaqah_may_see_wife_account(uuid, uuid, uuid, uuid)', 'EXECUTE')::text, 'false');
    PERFORM pg_temp.check('the triggers', (SELECT count(*)::text FROM pg_trigger WHERE tgenabled = 'O'
                                           AND tgname IN ('trg_accounts_wife_account_guard', 'trg_wife_account_spending')), '2');
    PERFORM pg_temp.check('no client writes assigned_wife_id',
        has_column_privilege('authenticated', 'public.accounts', 'assigned_wife_id', 'UPDATE')::text, 'false');
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
    RAISE NOTICE 'PASSED: the wife account: who makes, sees and uses it; repayments credit it; reversals; both purges.';
END $$;

ROLLBACK;
