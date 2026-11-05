-- ============================================================================
-- Test 50: account deletion, release review fixes (single session)
--
-- Migrations: 20261105000300_account_deletion_purge.sql, 20261105000800_account_deletion_operator_request.sql
--
-- `DELETE FROM auth.users` stands in for the Auth Admin API, as tests 16 and 39 do.
--
-- Verifies:
--   1. A household the user left, where only other members' rows name them by id: no copy
--      of their id is left anywhere in public.
--   2. Name and email: on their own kept rows, merchant and item names lose the display name
--      and the email. The email goes everywhere in public, other members' notes included, and
--      only where it is the whole address. A pool handed to another admin loses the display
--      name from its name. Other members' free text keeps the display name.
--   3. Cancel works whenever nothing was deleted yet (stage none), whatever the status:
--      scheduled, processing or failed, for the user and the operator. Once prepared, refused.
--   4. Operator: an address held by two accounts (case-insensitive) is ambiguous; one inquiry
--      reference cannot schedule two people; operator cancel needs a reference that exists.
--   5. The typed word: Arabic-keyboard Urdu and odd spaces still match, after the server fold.
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
AS $$ SELECT ('e5000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e50a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e50c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int) TO PUBLIC;

CREATE FUNCTION pg_temp.hh(p_n int, p_type text DEFAULT 'roommates', p_name text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.households (id, name, invite_code, household_type)
    VALUES (pg_temp.h(p_n), COALESCE(p_name, 'T50 H' || p_n), 'T50CODE' || lpad(p_n::text, 9, '0'), p_type);
END;
$$;

-- p_active: make this the user's active household.
CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text, p_active boolean DEFAULT true, p_default boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, p_default);
    IF p_active THEN
        UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
        WHERE id = pg_temp.u(p_user);
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.acct(p_n int, p_hh int, p_owner int, p_pool boolean, p_balance numeric, p_name text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool)
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), COALESCE(p_name, 'T50 acct ' || p_n),
            CASE WHEN p_pool THEN 'shared_pool' ELSE 'bank' END, p_balance, p_pool);
END;
$$;

CREATE FUNCTION pg_temp.session(p_user int) RETURNS text LANGUAGE sql AS $$
    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_user), now()) RETURNING id::text
$$;

-- Requests through the real RPC, with a fresh session. Returns the result or ERR:<hint>.
CREATE FUNCTION pg_temp.try_request(p_user int, p_word text, p_choices text DEFAULT '[]') RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_user), pg_temp.session(p_user),
        format('SELECT public.request_account_deletion(%L, %L::jsonb, NULL, %L)::text', p_word, p_choices, 'en'))
$$;

CREATE FUNCTION pg_temp.request(p_user int, p_choices text DEFAULT '[]') RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_res text := pg_temp.try_request(p_user, 'DELETE', p_choices);
BEGIN
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'request for user % refused: %', p_user, v_res;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.cancel(p_user int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_user), NULL, 'SELECT (public.cancel_account_deletion()->>''cancelled'')')
$$;

CREATE FUNCTION pg_temp.req_id(p_user int) RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.account_deletion_requests WHERE user_id = pg_temp.u(p_user) AND status IN ('scheduled', 'processing', 'failed') $$;

CREATE FUNCTION pg_temp.make_due(p_user int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid := pg_temp.req_id(p_user);
BEGIN
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_id;
    UPDATE public.households SET deletion_scheduled_for = now() - interval '1 minute' WHERE deletion_requested_by = pg_temp.u(p_user);
    RETURN v_id;
END;
$$;

CREATE FUNCTION pg_temp.claim() RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    v_res text := pg_temp.svc('SELECT count(*)::text FROM public.claim_due_account_deletions(50, 30)');
BEGIN
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'claim failed: %', v_res; END IF;
    RETURN v_res::int;
END;
$$;

CREATE FUNCTION pg_temp.prepare(p_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_res text := pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', p_id));
BEGIN
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'prepare failed: %', v_res; END IF;
    RETURN v_res::jsonb;
END;
$$;

-- The whole worker job: claim, prepare, storage, Auth delete, complete.
CREATE FUNCTION pg_temp.purge(p_user int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid := pg_temp.make_due(p_user);
    v_prepared jsonb;
    v_res text;
BEGIN
    PERFORM pg_temp.claim();
    v_prepared := pg_temp.prepare(v_id);
    IF (v_prepared->>'deferred')::boolean THEN
        RETURN v_prepared;
    END IF;
    v_res := pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'mark storage failed: %', v_res; END IF;
    DELETE FROM auth.users WHERE id = pg_temp.u(p_user);
    v_res := pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'complete failed: %', v_res; END IF;
    RETURN v_prepared;
END;
$$;

-- Tables in public holding p_needle in any column, as "table:rows " in name order.
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

DO $$
BEGIN
    INSERT INTO auth.users (id, email)
    SELECT pg_temp.u(n), 't50-' || n || '@test.local' FROM generate_series(1, 60) AS n;
END $$;

-- 1. An id named only by other members, in a household the user left ------------------------
DO $$
BEGIN
    PERFORM pg_temp.hh(1); PERFORM pg_temp.hh(2);
    PERFORM pg_temp.join(1, 1, 'admin', 'peer');
    PERFORM pg_temp.join(3, 2, 'admin', 'peer');
    -- X (2) was in H2, where only Z (3) wrote a row naming X. Then X left H2 for H1.
    PERFORM pg_temp.join(2, 2, 'member', 'peer');
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, notes, source, spent_by,
                                     beneficiary_type, beneficiary_id, settlement_target_id, line_items)
    VALUES (pg_temp.h(2), pg_temp.u(3), 44, 'T50 shop', 'OPEX-GROCERY', now(),
            'Z note | PaidBy: me | Beneficiary: ' || pg_temp.u(2) || ' | SpentBy: me', 'manual', 'me', 'member', pg_temp.u(2)::text,
            pg_temp.u(2)::text, format('[{"name": "bread", "beneficiary": "%s"}]', pg_temp.u(2))::jsonb);
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(2) AND user_id = pg_temp.u(2);
    PERFORM pg_temp.join(2, 1, 'member', 'peer');

    PERFORM pg_temp.request(2);
    PERFORM pg_temp.expect('purge', (pg_temp.purge(2))->>'prepared', 'true');
    PERFORM pg_temp.expect('no copy of the id anywhere in public', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.expect('Z''s row keeps Z''s words and its tags',
        (SELECT notes || ' / ' || beneficiary_id || ' / ' || settlement_target_id || ' / ' || line_items::text
         FROM public.transactions WHERE household_id = pg_temp.h(2)),
        'Z note | PaidBy: me | Beneficiary: deleted_member | SpentBy: me / deleted_member / deleted_member / [{"name": "bread", "beneficiary": "deleted_member"}]');
    RAISE NOTICE 'PASSED: an id named only by others in a household the user left is replaced.';
END $$;

-- 2. Name and email ------------------------------------------------------------------------------
-- H11: admin A (11), B (12) whose name and email are unique. H12, unrelated: C (13).
DO $$
BEGIN
    UPDATE auth.users SET email = 'Bilal.Unique@test.local' WHERE id = pg_temp.u(12);
    UPDATE public.users SET display_name = 'Bilal Uniqueperson' WHERE id = pg_temp.u(12);
    PERFORM pg_temp.hh(11);
    PERFORM pg_temp.hh(12, 'roommates', 'Flat of bilal.unique@test.local');
    PERFORM pg_temp.hh(13, 'roommates', 'Bilal Uniqueperson fan club');
    PERFORM pg_temp.join(11, 11, 'admin', 'peer');
    PERFORM pg_temp.join(12, 11, 'member', 'peer');
    PERFORM pg_temp.join(13, 12, 'admin', 'peer');
    PERFORM pg_temp.join(14, 13, 'admin', 'peer');
    PERFORM pg_temp.acct(11, 11, 11, true, 1000);
    PERFORM pg_temp.acct(12, 11, 12, true, 300, 'Bilal Uniqueperson savings');
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, notes, source, spent_by, items, line_items) VALUES
        (pg_temp.h(11), pg_temp.u(12), 10, 'BILAL UNIQUEPERSON', 'OPEX-GROCERY', now(), NULL, 'manual', 'me',
         '[{"name": "gift card for Bilal Uniqueperson"}, {"name": "sent to bilal.unique@TEST.local"}, {"name": "tea"}]'::jsonb,
         '[{"name": "card for bilal uniqueperson", "amount": 5}]'::jsonb),
        (pg_temp.h(11), pg_temp.u(12), 11, 'Panda', 'OPEX-GROCERY', now(), NULL, 'manual', 'me', '[]'::jsonb, '[]'::jsonb),
        (pg_temp.h(11), pg_temp.u(11), 20, 'Cafe', 'OPEX-DINING', now(),
         'Dinner with Bilal Uniqueperson, pay back to bilal.unique@test.local', 'manual', 'me', '[]'::jsonb, '[]'::jsonb),
        -- Not B's address: longer ones that contain it, before and after.
        (pg_temp.h(11), pg_temp.u(11), 21, 'Cafe 2', 'OPEX-DINING', now(),
         'ask xbilal.unique@test.local or bilal.unique@test.local.sa', 'manual', 'me', '[]'::jsonb, '[]'::jsonb),
        -- A household B never belonged to.
        (pg_temp.h(12), pg_temp.u(13), 30, 'Shop', 'OPEX-GROCERY', now(),
         'Bilal.Unique@test.local owes me.', 'manual', 'me', '[]'::jsonb, '[]'::jsonb);
    -- Other tables: A's income note.
    INSERT INTO public.income_records (household_id, user_id, account_id, cycle_key, source_type, title, base_amount, net_amount, notes)
    VALUES (pg_temp.h(11), pg_temp.u(11), pg_temp.a(11), public.nafaqah_current_cycle_key(pg_temp.h(11)), 'other', 'T50 income', 5, 5,
            'from BILAL.UNIQUE@test.local');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.request(12);
    PERFORM pg_temp.expect('purge', (pg_temp.purge(12))->>'prepared', 'true');

    PERFORM pg_temp.expect('a longer address that contains the email is not touched',
        (SELECT notes FROM public.transactions WHERE household_id = pg_temp.h(11) AND amount = 21), 'ask xbilal.unique@test.local or bilal.unique@test.local.sa');
    -- That address is not B's, but a scan by substring would find it.
    DELETE FROM public.transactions WHERE household_id = pg_temp.h(11) AND amount = 21;
    PERFORM pg_temp.expect('the email nowhere in public', pg_temp.scan('bilal.unique@test.local'), '');
    PERFORM pg_temp.expect('the display name only in other members'' free text', pg_temp.scan('Uniqueperson'), 'households:1 transactions:1 ');
    PERFORM pg_temp.expect('a household name keeps a display name',
        (SELECT name FROM public.households WHERE id = pg_temp.h(13)), 'Bilal Uniqueperson fan club');

    PERFORM pg_temp.expect('own merchant',
        (SELECT merchant FROM public.transactions WHERE household_id = pg_temp.h(11) AND amount = 10), 'deleted_member');
    PERFORM pg_temp.expect('own item names',
        (SELECT items::text || ' / ' || line_items::text FROM public.transactions WHERE household_id = pg_temp.h(11) AND amount = 10),
        '[{"name": "gift card for deleted_member"}, {"name": "sent to deleted_member"}, {"name": "tea"}] / [{"name": "card for deleted_member", "amount": 5}]');
    PERFORM pg_temp.expect('an own merchant without the name is kept',
        (SELECT merchant FROM public.transactions WHERE household_id = pg_temp.h(11) AND amount = 11), 'Panda');
    PERFORM pg_temp.expect('another member''s note keeps the name, loses the email',
        (SELECT notes FROM public.transactions WHERE household_id = pg_temp.h(11) AND amount = 20),
        'Dinner with Bilal Uniqueperson, pay back to deleted_member');
    PERFORM pg_temp.expect('the email in an unrelated household''s note',
        (SELECT notes FROM public.transactions WHERE household_id = pg_temp.h(12)), 'deleted_member owes me.');
    PERFORM pg_temp.expect('the email in another member''s income note',
        (SELECT notes FROM public.income_records WHERE household_id = pg_temp.h(11) AND title = 'T50 income'), 'from deleted_member');
    PERFORM pg_temp.expect('the email in a household name',
        (SELECT name FROM public.households WHERE id = pg_temp.h(12)), 'Flat of deleted_member');
    PERFORM pg_temp.expect('a pool handed to the admin loses the name',
        (SELECT name || ' / ' || owner_user_id::text || ' / ' || balance::text FROM public.accounts WHERE id = pg_temp.a(12)),
        'deleted_member savings / ' || pg_temp.u(11) || ' / 300.00');
    PERFORM pg_temp.expect('another pool keeps its name',
        (SELECT name FROM public.accounts WHERE id = pg_temp.a(11)), 'T50 acct 11');
    RAISE NOTICE 'PASSED: name and email are replaced exactly where the page says.';
END $$;

-- 3. Cancel while nothing is deleted ---------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    i int;
BEGIN
    PERFORM pg_temp.hh(21, 'family'); PERFORM pg_temp.hh(22); PERFORM pg_temp.hh(23); PERFORM pg_temp.hh(24);
    PERFORM pg_temp.join(21, 21, 'admin', 'provider'); PERFORM pg_temp.join(22, 21, 'member', 'spouse');
    PERFORM pg_temp.acct(21, 21, 21, true, 1000);
    PERFORM pg_temp.join(23, 22, 'admin', 'peer'); PERFORM pg_temp.join(24, 22, 'member', 'peer');
    PERFORM pg_temp.join(25, 23, 'admin', 'peer'); PERFORM pg_temp.join(26, 23, 'member', 'peer');
    PERFORM pg_temp.join(27, 24, 'admin', 'peer'); PERFORM pg_temp.join(28, 24, 'member', 'peer');
    -- Old data, from before trg_enforce_wife_class_account: a wife_personal row debiting the pool.
    ALTER TABLE public.transactions DISABLE TRIGGER trg_enforce_wife_class_account;
    INSERT INTO public.transactions (household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, account_id, nafaqah_class, nafaqah_spouse_id)
    VALUES (pg_temp.h(21), pg_temp.u(22), 40, 'Abaya', 'OPEX-SHOPPING', now(), 'manual', 'me', pg_temp.a(21), 'wife_personal', pg_temp.u(22));
    ALTER TABLE public.transactions ENABLE TRIGGER trg_enforce_wife_class_account;

    -- W (22): five attempts end in failed, and nothing was deleted.
    PERFORM pg_temp.request(22);
    v_id := pg_temp.make_due(22);
    FOR i IN 1..5 LOOP
        UPDATE public.account_deletion_requests SET lease_expires_at = now() - interval '1 minute' WHERE id = v_id AND status = 'processing';
        PERFORM pg_temp.claim();
        PERFORM pg_temp.expect('the invariant refuses',
            pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id)), 'ERR:purge_ledger_invariant');
        PERFORM pg_temp.svc(format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'purge_ledger_invariant'));
    END LOOP;
    PERFORM pg_temp.expect('failed, nothing deleted',
        (SELECT status || '/' || stage FROM public.account_deletion_requests WHERE id = v_id), 'failed/none');
    PERFORM pg_temp.expect('status offers cancel',
        pg_temp.call(pg_temp.u(22), NULL, 'SELECT public.get_account_deletion_status()::text')::jsonb ->> 'can_cancel', 'true');
    PERFORM pg_temp.expect('the user cancels a failed job', pg_temp.cancel(22), 'true');
    PERFORM pg_temp.expect('no longer pending', public.account_deletion_user_pending(pg_temp.u(22))::text, 'false');
    PERFORM pg_temp.expect('a new request is a new one',
        pg_temp.call(pg_temp.u(22), pg_temp.session(22), 'SELECT (public.request_account_deletion(''delete'')->>''already_requested'')'), 'false');
    PERFORM pg_temp.cancel(22);

    -- M (24): claimed, processing, not prepared.
    PERFORM pg_temp.request(24);
    v_id := pg_temp.make_due(24);
    PERFORM pg_temp.claim();
    PERFORM pg_temp.expect('processing, nothing deleted',
        (SELECT status || '/' || stage FROM public.account_deletion_requests WHERE id = v_id), 'processing/none');
    PERFORM pg_temp.expect('the user cancels a claimed job', pg_temp.cancel(24), 'true');
    PERFORM pg_temp.expect('cancelled, lease gone',
        (SELECT status || '/' || (lease_expires_at IS NULL)::text FROM public.account_deletion_requests WHERE id = v_id), 'cancelled/true');
    PERFORM pg_temp.expect('the cancelled job cannot be prepared',
        pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id)), 'ERR:purge_not_allowed');
    PERFORM pg_temp.expect('nothing to claim', pg_temp.claim()::text, '0');

    -- N (26): failed, cancelled by the operator.
    INSERT INTO public.inquiries (type, email, reference, status, source) VALUES ('account_deletion', 't50-26@test.local', 't50ref000026', 'captured', 'web');
    PERFORM pg_temp.request(26);
    v_id := pg_temp.make_due(26);
    PERFORM pg_temp.claim();
    UPDATE public.account_deletion_requests SET status = 'failed', lease_expires_at = NULL WHERE id = v_id;
    PERFORM pg_temp.expect('the operator cancels a failed job',
        pg_temp.svc(format($q$SELECT (public.cancel_account_deletion_by_operator(%L, 't50ref000026', 'dev')->>'cancelled')$q$, pg_temp.u(26))), 'true');

    -- P (28): prepared. Data is gone, so both refuse.
    PERFORM pg_temp.request(28);
    v_id := pg_temp.make_due(28);
    PERFORM pg_temp.claim();
    PERFORM pg_temp.prepare(v_id);
    PERFORM pg_temp.expect('status refuses cancel once prepared',
        pg_temp.call(pg_temp.u(28), NULL, 'SELECT public.get_account_deletion_status()::text')::jsonb ->> 'can_cancel', 'false');
    PERFORM pg_temp.expect('the user cannot cancel once prepared', pg_temp.cancel(28), 'ERR:deletion_in_progress');
    UPDATE public.account_deletion_requests SET status = 'failed' WHERE id = v_id;
    PERFORM pg_temp.expect('nor once prepared and failed', pg_temp.cancel(28), 'ERR:deletion_in_progress');
    PERFORM pg_temp.expect('nor the operator',
        pg_temp.svc(format($q$SELECT (public.cancel_account_deletion_by_operator(%L, 't50ref000026', 'dev')->>'cancelled')$q$, pg_temp.u(28))),
        'ERR:deletion_in_progress');
    RAISE NOTICE 'PASSED: cancel works whenever nothing was deleted, and only then.';
END $$;

-- 4. Operator: ambiguous address, reused reference, cancel reference --------------------------------
DO $$
DECLARE
    v_preview jsonb;
BEGIN
    UPDATE auth.users SET email = 'Dup@T50.local' WHERE id = pg_temp.u(31);
    UPDATE auth.users SET email = 'dup@t50.local' WHERE id = pg_temp.u(32);
    INSERT INTO public.inquiries (type, email, reference, status, source) VALUES
        ('account_deletion', 'dup@t50.local', 't50ref000031', 'captured', 'web'),
        ('account_deletion', 't50-33@test.local', 't50ref000033', 'captured', 'web');

    v_preview := pg_temp.svc($q$SELECT public.get_account_deletion_operator_preview('DUP@t50.local', 't50ref000031')::text$q$)::jsonb;
    PERFORM pg_temp.expect('two accounts share the address: ambiguous', v_preview->>'ambiguous', 'true');
    PERFORM pg_temp.expect('no user id is offered', v_preview->>'user_id', NULL);
    PERFORM pg_temp.expect('one account: not ambiguous',
        pg_temp.svc($q$SELECT (public.get_account_deletion_operator_preview('t50-33@test.local', 't50ref000033')->>'ambiguous')$q$), 'false');

    -- One reference schedules one person.
    PERFORM pg_temp.expect('first use',
        pg_temp.svc(format($q$SELECT (public.schedule_account_deletion_by_operator(%L, 't50ref000033', 'dev')->>'success')$q$, pg_temp.u(33))), 'true');
    PERFORM pg_temp.expect('the same reference for someone else',
        pg_temp.svc(format($q$SELECT (public.schedule_account_deletion_by_operator(%L, 't50ref000033', 'dev')->>'success')$q$, pg_temp.u(34))),
        'ERR:inquiry_reused');
    PERFORM pg_temp.expect('nor by its id',
        pg_temp.svc(format($q$SELECT (public.schedule_account_deletion_by_operator(%L, (SELECT id::text FROM public.inquiries WHERE reference = 't50ref000033'), 'dev')->>'success')$q$, pg_temp.u(34))),
        'ERR:inquiry_reused');
    PERFORM pg_temp.expect('the same person again finds the request',
        pg_temp.svc(format($q$SELECT (public.schedule_account_deletion_by_operator(%L, 't50ref000033', 'dev')->>'already_requested')$q$, pg_temp.u(33))), 'true');

    -- Operator cancel needs a reference that exists.
    PERFORM pg_temp.expect('cancel with an unknown reference',
        pg_temp.svc(format($q$SELECT (public.cancel_account_deletion_by_operator(%L, 'nosuchref', 'dev')->>'cancelled')$q$, pg_temp.u(33))),
        'ERR:inquiry_invalid');
    PERFORM pg_temp.expect('still scheduled', public.account_deletion_user_pending(pg_temp.u(33))::text, 'true');
    PERFORM pg_temp.expect('cancel with the reference',
        pg_temp.svc(format($q$SELECT (public.cancel_account_deletion_by_operator(%L, 't50ref000033', 'dev')->>'cancelled')$q$, pg_temp.u(33))), 'true');
    PERFORM pg_temp.expect('the cancel reference is stored',
        (SELECT operator_cancel_reference FROM public.account_deletion_requests WHERE user_id = pg_temp.u(33)), 't50ref000033');
    RAISE NOTICE 'PASSED: ambiguous addresses, reused references and unknown cancel references are refused.';
END $$;

-- 5. The typed word --------------------------------------------------------------------------------
DO $$
DECLARE
    v_word text;
BEGIN
    PERFORM pg_temp.hh(41);
    PERFORM pg_temp.join(41, 41, 'member', 'peer');
    PERFORM pg_temp.join(42, 41, 'admin', 'peer');
    FOREACH v_word IN ARRAY ARRAY[
        'delete', ' DELETE ', 'حذف',
        -- Urdu as the app shows it: keheh, Farsi yeh, noon ghunna.
        'حذف ' || U&'\06A9' || 'ر' || U&'\06CC\06BA',
        -- The same typed on an Arabic keyboard: kaf, yeh, noon.
        'حذف ' || U&'\0643' || 'ر' || U&'\064A\0646',
        -- Alef maksura for the yeh.
        'حذف ' || U&'\0643' || 'ر' || U&'\0649\0646',
        -- No-break space, and bidi marks, between the words and around them.
        'حذف' || U&'\00A0' || U&'\06A9' || 'ر' || U&'\06CC\06BA',
        U&'\200F' || 'حذف' || U&'\200F' || U&'\06A9' || 'ر' || U&'\06CC\06BA' || U&'\200E',
        'حذف' || U&'\2003\3000' || U&'\0643' || 'ر' || U&'\064A\0646'
    ] LOOP
        PERFORM pg_temp.expect('accepted: ' || v_word,
            (SELECT CASE WHEN r LIKE 'ERR:%' THEN r ELSE r::jsonb ->> 'success' END FROM pg_temp.try_request(41, v_word) AS r), 'true');
        PERFORM pg_temp.cancel(41);
    END LOOP;
    FOREACH v_word IN ARRAY ARRAY['delet', 'حذ', 'حذفكرين', 'remove', '', 'حذف كرين x'] LOOP
        PERFORM pg_temp.expect('refused: ' || v_word, pg_temp.try_request(41, v_word), 'ERR:confirmation_mismatch');
    END LOOP;
    RAISE NOTICE 'PASSED: the typed word matches after folding Arabic-keyboard Urdu and spaces.';
END $$;

ROLLBACK;
