-- ============================================================================
-- Test 39: service-only account purge
--
-- Migration: 20261105000300_account_deletion_purge.sql
--
-- `DELETE FROM auth.users` stands in for the Auth Admin API, as test 16 does.
--
-- Verifies:
--   1. Member purge: surviving pool balances and every surviving budget's spent_amount
--      are exactly equal before and after. Preserved rows have a NULL creator, spent_by
--      unchanged, free text scrubbed, receipts queued. No email, display name or user
--      id remains anywhere in public. B keeps nothing but the other household keeps B's
--      rows too.
--   2. Wife purge: her wife_personal rows go first so no budget moves; wife_reimbursable
--      is declassified without moving anything.
--   3. Household deletion: data gone, members keep logins, household_id repoints with
--      the right role and financial_role, a member with no other household gets NULL,
--      the household's receipts folder is queued as a prefix.
--   4. Co-admin purge: the household survives and their pool is re-owned.
--   5. Late-surfaced household: deferred 7 days and marked, then deleted.
--   6. Idempotency: prepare twice is a no-op, complete repeated is safe, complete
--      refuses while the auth user exists, storage cannot be marked before prepare.
--   7. Refusals and leases: not-due and cancelled refused, lease expiry reclaims, a
--      held lease is skipped, backoff, then failed after 5 attempts.
--   8. Ledger invariant: a row whose delete would credit a pool aborts the purge.
--   9. Notices and the worker heartbeat.
--  10. Privileges: authenticated and anon get 42501 on every purge function, and each
--      refuses a caller with a JWT subject even under the service role.
--  11. Out-of-band auth.users deletion during grace: never deletes a household, and the
--      purge then completes on what is left.
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
AS $$ SELECT ('e3900000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e39a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e39c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int) TO PUBLIC;

CREATE FUNCTION pg_temp.hh(p_n int, p_type text DEFAULT 'roommates') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.households (id, name, invite_code, household_type)
    VALUES (pg_temp.h(p_n), 'T39 H' || p_n, 'T39CODE' || lpad(p_n::text, 9, '0'), p_type);
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

CREATE FUNCTION pg_temp.acct(p_n int, p_hh int, p_owner int, p_pool boolean, p_balance numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool)
    VALUES (pg_temp.a(p_n), pg_temp.h(p_hh), pg_temp.u(p_owner), 'T39 acct ' || p_n,
            CASE WHEN p_pool THEN 'shared_pool' ELSE 'bank' END, p_balance, p_pool);
END;
$$;

-- Requests through the real RPC, with a fresh session.
CREATE FUNCTION pg_temp.request(p_user int, p_choices text DEFAULT '[]', p_reason text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_sess text;
    v_res text;
BEGIN
    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(p_user), now()) RETURNING id::text INTO v_sess;
    v_res := pg_temp.call(pg_temp.u(p_user), v_sess,
        format('SELECT public.request_account_deletion(%L, %L::jsonb, %L, %L)::text', 'DELETE', p_choices, p_reason, 'en'));
    IF v_res LIKE 'ERR:%' THEN
        RAISE EXCEPTION 'request for user % refused: %', p_user, v_res;
    END IF;
END;
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

-- Moves a request and its marks together, as the purge keeps them.
CREATE FUNCTION pg_temp.set_date(p_user int, p_date timestamptz) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE public.account_deletion_requests SET scheduled_for = p_date WHERE id = pg_temp.req_id(p_user);
    UPDATE public.households SET deletion_scheduled_for = p_date WHERE deletion_requested_by = pg_temp.u(p_user);
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

-- Pool balances and budget spend of the given households, row by row.
CREATE FUNCTION pg_temp.ledger(p_hhs uuid[]) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE((SELECT string_agg(a.id::text || '=' || a.balance::text, ',' ORDER BY a.id)
                     FROM public.accounts a WHERE a.is_shared_pool AND a.household_id = ANY (p_hhs)), '')
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
    FOR v_t IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r' LOOP
        EXECUTE format('SELECT count(*) FROM public.%I x WHERE x::text ILIKE %L', v_t.relname, '%' || p_needle || '%') INTO v_n;
        IF v_n > 0 THEN
            v_found := v_found || v_t.relname || ':' || v_n || ' ';
        END IF;
    END LOOP;
    RETURN v_found;
END;
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- Roommates R(1): admin A(1), member B(2), member C(3). Second household S(2): admin Z(4), B too.
-- Family F(3): husband H(5), wife W(6), member K(7).
-- Doomed D(4): primary X(8), Y(9, also an admin of E(5)), lone member N(11). E(5): admin V(10).
-- T(6): primary P(13), co-admin Q(12).
-- L(7): primary O(15), co-admin G(14), member J(16).
DO $$
DECLARE
    v_cycle text;
    v_month date := date_trunc('month', now())::date;
BEGIN
    SELECT cycle_key INTO v_cycle FROM public.get_saudi_cycle_for_timestamp(now(), 27);

    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't39-' || n || '@test.local', jsonb_build_object('display_name', 'T39 User ' || n)
    FROM generate_series(1, 40) AS n;
    UPDATE auth.users SET email = 't39-bilal@test.local' WHERE id = pg_temp.u(2);
    UPDATE public.users SET display_name = 'Bilal Uniqueperson' WHERE id = pg_temp.u(2);
    UPDATE auth.users SET email = 't39-wafa@test.local' WHERE id = pg_temp.u(6);
    UPDATE public.users SET display_name = 'Wafa Uniqueperson' WHERE id = pg_temp.u(6);

    PERFORM pg_temp.hh(1); PERFORM pg_temp.hh(2);
    PERFORM pg_temp.join(1, 1, 'admin', 'peer');
    PERFORM pg_temp.join(2, 1, 'member', 'peer');
    PERFORM pg_temp.join(3, 1, 'member', 'peer');
    PERFORM pg_temp.join(4, 2, 'admin', 'peer');
    PERFORM pg_temp.join(2, 2, 'member', 'peer', false, false);

    PERFORM pg_temp.hh(3, 'family');
    PERFORM pg_temp.join(5, 3, 'admin', 'provider');
    PERFORM pg_temp.join(6, 3, 'member', 'spouse');
    PERFORM pg_temp.join(7, 3, 'member', 'family_member');

    PERFORM pg_temp.hh(4); PERFORM pg_temp.hh(5, 'family');
    PERFORM pg_temp.join(8, 4, 'admin', 'peer');
    PERFORM pg_temp.join(10, 5, 'admin', 'provider');
    -- Y is active in the doomed household, with E as a later, non-default membership.
    PERFORM pg_temp.join(9, 4, 'member', 'peer', true, true);
    PERFORM pg_temp.join(9, 5, 'admin', 'family_member', false, false);
    PERFORM pg_temp.join(11, 4, 'member', 'peer');

    PERFORM pg_temp.hh(6);
    PERFORM pg_temp.join(13, 6, 'admin', 'peer');
    PERFORM pg_temp.join(12, 6, 'admin', 'peer');

    PERFORM pg_temp.hh(7);
    PERFORM pg_temp.join(15, 7, 'admin', 'peer');
    PERFORM pg_temp.join(14, 7, 'admin', 'peer');
    PERFORM pg_temp.join(16, 7, 'member', 'peer');

    -- R: pool owned by A, B's pool owned by B too; personals.
    PERFORM pg_temp.acct(1, 1, 1, true, 1000);
    PERFORM pg_temp.acct(2, 1, 2, true, 400);    -- a pool B created
    PERFORM pg_temp.acct(3, 1, 2, false, 90);    -- B personal
    PERFORM pg_temp.acct(4, 1, 2, false, 10);    -- B second personal
    PERFORM pg_temp.acct(5, 1, 1, false, 70);    -- A personal
    PERFORM pg_temp.acct(6, 2, 4, true, 600);    -- S pool
    PERFORM pg_temp.acct(7, 2, 2, false, 30);    -- B personal in S
    PERFORM pg_temp.acct(8, 3, 5, true, 800);    -- F pool
    PERFORM pg_temp.acct(9, 3, 6, false, 50);    -- W personal
    PERFORM pg_temp.acct(10, 4, 8, true, 200);   -- D pool
    PERFORM pg_temp.acct(11, 4, 11, false, 20);  -- N personal in D
    PERFORM pg_temp.acct(12, 6, 12, true, 150);  -- pool owned by co-admin Q
    PERFORM pg_temp.acct(13, 6, 12, false, 15);  -- Q personal

    INSERT INTO public.budgets (id, household_id, month, category_code, allocated_amount, cycle_key, account_id) VALUES
        ('e39b0000-0000-0000-0000-000000000001', pg_temp.h(1), v_month, 'OPEX-GROCERY', 1000, v_cycle, pg_temp.a(3)),
        ('e39b0000-0000-0000-0000-000000000002', pg_temp.h(1), v_month, 'OPEX-DINING', 500, v_cycle, pg_temp.a(1)),
        ('e39b0000-0000-0000-0000-000000000003', pg_temp.h(2), v_month, 'OPEX-GROCERY', 500, v_cycle, NULL),
        ('e39b0000-0000-0000-0000-000000000004', pg_temp.h(3), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL),
        ('e39b0000-0000-0000-0000-000000000005', pg_temp.h(4), v_month, 'OPEX-GROCERY', 900, v_cycle, NULL),
        -- The category of the wife's personal purchase: it must stay at zero.
        ('e39b0000-0000-0000-0000-000000000006', pg_temp.h(3), v_month, 'OPEX-SHOPPING', 300, v_cycle, NULL);

    -- B's rows in R. spent_by is not a name and must survive untouched.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, notes, source,
                                     receipt_url, spent_by, account_id, line_items, beneficiary_type, beneficiary_id) VALUES
        ('e39d0000-0000-0000-0000-000000000001', pg_temp.h(1), pg_temp.u(2), 100, 'T39 Panda', 'OPEX-GROCERY', now(),
         'Bought for Bilal Uniqueperson t39-bilal@test.local | PaidBy: me | Beneficiary: both | SpentBy: partner', 'manual',
         pg_temp.h(1) || '/receipt-b1.jpg', 'partner', pg_temp.a(1),
         format('[{"name": "milk", "beneficiary": "%s"}, {"name": "eggs", "beneficiary": "both"}]', pg_temp.u(3))::jsonb,
         'household', 'household'),
        ('e39d0000-0000-0000-0000-000000000002', pg_temp.h(1), pg_temp.u(2), 20, 'T39 Cafe', 'OPEX-DINING', now(),
         'Chat: lunch with Bilal Uniqueperson', 'chat',
         'https://x.supabase.co/storage/v1/object/public/receipts/' || pg_temp.h(1) || '/receipt-b2.jpg?token=abc', 'me', pg_temp.a(3),
         '[]'::jsonb, NULL, NULL),
        -- A receipt_url pointing into another household's folder must never be queued.
        ('e39d0000-0000-0000-0000-000000000003', pg_temp.h(1), pg_temp.u(2), 5, 'T39 Sneaky', 'OPEX-DINING', now(),
         NULL, 'manual', pg_temp.h(2) || '/not-yours.jpg', 'both', NULL, '[]'::jsonb, NULL, NULL),
        ('e39d0000-0000-0000-0000-000000000004', pg_temp.h(1), pg_temp.u(2), 6, 'T39 Traversal', 'OPEX-DINING', now(),
         NULL, 'manual', pg_temp.h(1) || '/../' || pg_temp.h(2) || '/x.jpg', 'both', NULL, '[]'::jsonb, NULL, NULL),
        -- A settlement B paid.
        ('e39d0000-0000-0000-0000-000000000005', pg_temp.h(1), pg_temp.u(2), 30, NULL, 'OPEX-MISC', now(),
         'Settlement | PaidBy: ' || pg_temp.u(2) || ' | Recipient: ' || pg_temp.u(1) || ' | Method: cash | thanks Bilal Uniqueperson',
         'manual', NULL, 'me', NULL, '[]'::jsonb, 'member', pg_temp.u(1)::text),
        -- Other members' rows that name B or B's linked dependent.
        ('e39d0000-0000-0000-0000-000000000006', pg_temp.h(1), pg_temp.u(1), 40, 'T39 Shop', 'OPEX-GROCERY', now(),
         'A note by A | PaidBy: me | Beneficiary: ' || pg_temp.u(2) || ' | SpentBy: me', 'manual', pg_temp.h(1) || '/receipt-a.jpg', 'me', pg_temp.a(1),
         format('[{"name": "bread", "beneficiary": "%s"}, {"name": "tea", "beneficiary": "T39 Claimed Child"}, {"name": "jam", "beneficiary": "%s"}]',
                pg_temp.u(2), pg_temp.u(3))::jsonb,
         'member', pg_temp.u(2)::text),
        ('e39d0000-0000-0000-0000-000000000007', pg_temp.h(1), pg_temp.u(1), 50, NULL, 'OPEX-MISC', now(),
         'Settlement | PaidBy: ' || pg_temp.u(1) || ' | Recipient: ' || pg_temp.u(2) || ' | Method: bank',
         'manual', NULL, 'me', NULL, '[]'::jsonb, 'member', pg_temp.u(2)::text);
    UPDATE public.transactions SET is_settlement = true, settlement_target_id = pg_temp.u(2)::text
    WHERE id = 'e39d0000-0000-0000-0000-000000000007';
    UPDATE public.transactions SET is_settlement = true, settlement_target_id = pg_temp.u(1)::text
    WHERE id = 'e39d0000-0000-0000-0000-000000000005';
    -- B's row in the second household, in which B stays a member until the purge.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, notes, source, spent_by, account_id) VALUES
        ('e39d0000-0000-0000-0000-000000000008', pg_temp.h(2), pg_temp.u(2), 11, 'T39 S shop', 'OPEX-GROCERY', now(), 'S note by Bilal Uniqueperson', 'manual', 'me', pg_temp.a(6));

    -- B: income and transfers, direct rows with the balances they would have produced.
    INSERT INTO public.income_records (id, household_id, user_id, account_id, cycle_key, source_type, title, base_amount, net_amount, notes) VALUES
        ('e39e0000-0000-0000-0000-000000000001', pg_temp.h(1), pg_temp.u(2), pg_temp.a(1), v_cycle, 'salary', 'Bilal Uniqueperson salary', 200, 200, 'for t39-bilal@test.local'),
        ('e39e0000-0000-0000-0000-000000000002', pg_temp.h(1), pg_temp.u(2), pg_temp.a(3), v_cycle, 'salary', 'B personal income', 50, 50, 'private'),
        ('e39e0000-0000-0000-0000-000000000003', pg_temp.h(1), pg_temp.u(1), pg_temp.a(3), v_cycle, 'other', 'A paid into B personal', 5, 5, NULL),
        ('e39e0000-0000-0000-0000-000000000004', pg_temp.h(1), pg_temp.u(2), pg_temp.a(2), v_cycle, 'salary', 'B income into own pool', 60, 60, 'own pool');
    INSERT INTO public.account_transfers (id, household_id, user_id, from_account_id, to_account_id, amount, notes) VALUES
        ('e39f0000-0000-0000-0000-000000000001', pg_temp.h(1), pg_temp.u(2), pg_temp.a(3), pg_temp.a(1), 40, 'from Bilal Uniqueperson'),
        ('e39f0000-0000-0000-0000-000000000002', pg_temp.h(1), pg_temp.u(1), pg_temp.a(1), pg_temp.a(3), 15, 'A to B, for Bilal Uniqueperson'),
        ('e39f0000-0000-0000-0000-000000000003', pg_temp.h(1), pg_temp.u(2), pg_temp.a(3), pg_temp.a(4), 5, 'own'),
        ('e39f0000-0000-0000-0000-000000000004', pg_temp.h(1), pg_temp.u(1), pg_temp.a(1), pg_temp.a(5), 9, 'A to A personal');

    -- Dependents and invites.
    INSERT INTO public.household_dependents (id, household_id, name, linked_user_id) VALUES
        ('e3910000-0000-0000-0000-000000000001', pg_temp.h(1), 'T39 Claimed Child', pg_temp.u(2)),
        ('e3910000-0000-0000-0000-000000000002', pg_temp.h(1), 'T39 Unclaimed Child', NULL);
    INSERT INTO public.household_invites (id, household_id, invite_code, role, created_by, expires_at, used_by, target_member_id) VALUES
        ('e3920000-0000-0000-0000-000000000001', pg_temp.h(1), 'T39INV01', 'peer', pg_temp.u(2), now() + interval '7 days', NULL, NULL),
        ('e3920000-0000-0000-0000-000000000002', pg_temp.h(1), 'T39INV02', 'peer', pg_temp.u(1), now() + interval '7 days', NULL,
         'e3910000-0000-0000-0000-000000000001');

    -- Inquiries, by email and by the app's name marker.
    INSERT INTO public.inquiries (type, email, name, message, reference) VALUES
        ('support', 't39-bilal@test.local', 'Bilal', 'hello', 'T39-INQ-1'),
        ('support', pg_temp.u(2) || '@auth.internal', 'User ' || pg_temp.u(2), 'hello', 'T39-INQ-2'),
        ('support', 'someone-else@test.local', 'Someone', 'hello', 'T39-INQ-3');

    INSERT INTO public.invite_attempt_log (user_id, success) VALUES (pg_temp.u(2), false);

    -- An instalment B created.
    INSERT INTO public.installment_plans (household_id, merchant, total_amount, monthly_amount, installment_count, category_code, original_transaction_id, notes, start_date, provider)
    VALUES (pg_temp.h(1), 'T39 BNPL', 100, 25, 4, 'OPEX-MISC', 'e39d0000-0000-0000-0000-000000000001', 'plan by Bilal Uniqueperson', now()::date, 'Tabby');

    -- Family F: the wife's rows.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, notes, source, spent_by, nafaqah_class, nafaqah_spouse_id, account_id) VALUES
        ('e39d0000-0000-0000-0000-000000000011', pg_temp.h(3), pg_temp.u(6), 70, 'T39 Perfume', 'OPEX-SHOPPING', now(), 'mine, Wafa Uniqueperson', 'manual', 'me', 'wife_personal', pg_temp.u(6), pg_temp.a(9)),
        ('e39d0000-0000-0000-0000-000000000012', pg_temp.h(3), pg_temp.u(6), 80, 'T39 Grocer', 'OPEX-GROCERY', now(), 'groceries, Wafa Uniqueperson', 'manual', 'me', 'wife_reimbursable', pg_temp.u(6), NULL),
        ('e39d0000-0000-0000-0000-000000000013', pg_temp.h(3), pg_temp.u(5), 25, 'T39 Family', 'OPEX-GROCERY', now(), NULL, 'manual', 'me', NULL, NULL, pg_temp.a(8));
    INSERT INTO public.member_allowances (household_id, member_user_id, cycle_key, amount, set_by)
    VALUES (pg_temp.h(3), pg_temp.u(6), v_cycle, 300, pg_temp.u(5));
    INSERT INTO public.spouse_reimbursements (household_id, wife_user_id, amount, payment_method, notes, paid_by_user_id, recorded_by)
    VALUES (pg_temp.h(3), pg_temp.u(6), 10, 'cash', 'to Wafa Uniqueperson', pg_temp.u(5), pg_temp.u(5));

    -- D, the doomed household, has everything the RESTRICT and last-admin races need.
    INSERT INTO public.income_records (household_id, user_id, account_id, cycle_key, source_type, title, base_amount, net_amount) VALUES
        (pg_temp.h(4), pg_temp.u(11), pg_temp.a(10), v_cycle, 'salary', 'N income', 10, 10),
        (pg_temp.h(4), pg_temp.u(11), pg_temp.a(11), v_cycle, 'salary', 'N personal income', 10, 10);
    INSERT INTO public.account_transfers (household_id, user_id, from_account_id, to_account_id, amount) VALUES
        (pg_temp.h(4), pg_temp.u(11), pg_temp.a(11), pg_temp.a(10), 5);
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, account_id, receipt_url) VALUES
        ('e39d0000-0000-0000-0000-000000000021', pg_temp.h(4), pg_temp.u(11), 12, 'T39 D shop', 'OPEX-GROCERY', now(), 'manual', 'me', pg_temp.a(10), pg_temp.h(4) || '/d.jpg');

    INSERT INTO public.api_quota (user_id, bucket, window_start, count)
    VALUES (pg_temp.u(2), 't39', now(), 1);
END $$;

-- 7a. Refused before due, and when cancelled --------------------------------------------
DO $$
DECLARE
    v_id uuid;
BEGIN
    PERFORM pg_temp.request(20);
    v_id := pg_temp.req_id(20);
    PERFORM pg_temp.expect('not due: nothing claimed', pg_temp.claim()::text, '0');
    PERFORM pg_temp.expect('prepare before due',
        pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id)), 'ERR:purge_not_allowed');
    PERFORM pg_temp.expect('prepare on an unknown request',
        pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', gen_random_uuid())), 'ERR:request_not_found');

    -- Due but never claimed: still refused, the lease is the gate.
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.expect('prepare without a claim',
        pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id)), 'ERR:purge_not_allowed');

    -- Cancelled in time.
    PERFORM pg_temp.call(pg_temp.u(20), NULL, 'SELECT public.cancel_account_deletion()::text');
    PERFORM pg_temp.expect('cancelled: nothing claimed', pg_temp.claim()::text, '0');
    PERFORM pg_temp.expect('prepare after cancel',
        pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id)), 'ERR:purge_not_allowed');
    PERFORM pg_temp.expect('the user is intact',
        (SELECT count(*)::text FROM public.users WHERE id = pg_temp.u(20) AND display_name = 'T39 User 20'), '1');
    RAISE NOTICE 'PASSED: not-due, unclaimed and cancelled requests are refused.';
END $$;

-- 1. Member purge: B ---------------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    v_before text;
    v_after text;
    v_tx public.transactions%ROWTYPE;
    v_res text;
    v_keep_hhs uuid[] := ARRAY[pg_temp.h(1), pg_temp.h(2), pg_temp.h(3), pg_temp.h(5), pg_temp.h(6), pg_temp.h(7)];
    v_spent_by text;
    v_queue text;
BEGIN
    v_before := pg_temp.ledger(v_keep_hhs);
    SELECT string_agg(id::text || spent_by, ',' ORDER BY id) INTO v_spent_by FROM public.transactions WHERE household_id = pg_temp.h(1);

    PERFORM pg_temp.request(2, '[]', 'T39 reason from Bilal Uniqueperson');
    v_id := pg_temp.make_due(2);
    PERFORM pg_temp.expect('claimed', pg_temp.claim()::text, '1');
    PERFORM pg_temp.expect('cancel is refused once claimed',
        pg_temp.call(pg_temp.u(2), NULL, 'SELECT public.cancel_account_deletion()::text'), 'ERR:deletion_in_progress');
    PERFORM pg_temp.expect('storage cannot be marked before prepare',
        pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id)), 'ERR:purge_stage_invalid');

    PERFORM pg_temp.expect('prepare result', (pg_temp.prepare(v_id))->>'prepared', 'true');
    PERFORM pg_temp.expect('stage after prepare',
        (SELECT stage FROM public.account_deletion_requests WHERE id = v_id), 'db_prepared');
    PERFORM pg_temp.expect('ledger unchanged after prepare', pg_temp.ledger(v_keep_hhs), v_before);

    -- 6. Prepare twice is a no-op.
    PERFORM pg_temp.expect('second prepare', (pg_temp.prepare(v_id))->>'already_prepared', 'true');
    PERFORM pg_temp.expect('ledger unchanged after second prepare', pg_temp.ledger(v_keep_hhs), v_before);

    -- Storage: exactly B's own receipts in R; nothing from A, no foreign or traversal paths.
    v_res := pg_temp.svc(format(
        $q$SELECT string_agg(bucket || ':' || path || ':' || is_prefix::text, ',' ORDER BY path)
           FROM public.list_account_purge_storage(%L)$q$, v_id));
    PERFORM pg_temp.expect('storage queue paths', v_res,
        'receipts:' || pg_temp.h(1) || '/receipt-b1.jpg:false,receipts:' || pg_temp.h(1) || '/receipt-b2.jpg:false');
    PERFORM pg_temp.expect('A''s receipt is kept',
        (SELECT receipt_url FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000006'), pg_temp.h(1) || '/receipt-a.jpg');

    -- 6. Complete refuses before storage and while the auth user exists.
    PERFORM pg_temp.expect('complete before storage',
        pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id)), 'ERR:purge_stage_invalid');
    v_res := pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'mark storage: %', v_res; END IF;
    v_res := pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'mark storage is not repeatable: %', v_res; END IF;
    PERFORM pg_temp.expect('queue emptied after storage',
        (SELECT count(*)::text FROM public.account_deletion_storage_queue WHERE request_id = v_id), '0');
    PERFORM pg_temp.expect('complete while the auth user exists',
        pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id)), 'ERR:auth_user_still_exists');

    -- The Auth Admin API deletes the user.
    DELETE FROM auth.users WHERE id = pg_temp.u(2);

    v_res := pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'complete: %', v_res; END IF;
    v_res := pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'complete is not repeatable: %', v_res; END IF;
    PERFORM pg_temp.expect('tombstone has no identifiers',
        (SELECT status || '/' || COALESCE(user_id::text, 'null') || '/' || COALESCE(reason, 'null') FROM public.account_deletion_requests WHERE id = v_id),
        'completed/null/null');

    -- Invariant: not one surviving pool balance or budget spend moved.
    v_after := pg_temp.ledger(v_keep_hhs);
    PERFORM pg_temp.expect('surviving ledgers exactly equal', v_after, v_before);

    -- B's pool in R stays, owned by the admin.
    PERFORM pg_temp.expect('B''s pool re-owned by A',
        (SELECT owner_user_id::text || '/' || balance::text FROM public.accounts WHERE id = pg_temp.a(2)), pg_temp.u(1) || '/400.00');
    PERFORM pg_temp.expect('income into B''s pool kept',
        (SELECT count(*)::text FROM public.income_records WHERE id = 'e39e0000-0000-0000-0000-000000000004' AND user_id IS NULL AND notes IS NULL), '1');
    PERFORM pg_temp.expect('B''s personal accounts gone',
        (SELECT count(*)::text FROM public.accounts WHERE id IN (pg_temp.a(3), pg_temp.a(4), pg_temp.a(7))), '0');

    -- Preserved rows.
    SELECT * INTO v_tx FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000001';
    PERFORM pg_temp.expect('creator NULL', v_tx.user_id::text, NULL);
    PERFORM pg_temp.expect('spent_by untouched', v_tx.spent_by, 'partner');
    PERFORM pg_temp.expect('note keeps only the attribution tail', v_tx.notes, '| PaidBy: me | Beneficiary: both | SpentBy: partner');
    PERFORM pg_temp.expect('receipt_url cleared', v_tx.receipt_url, NULL);
    PERFORM pg_temp.expect('pool debit stays on the pool', v_tx.account_id::text, pg_temp.a(1)::text);
    PERFORM pg_temp.expect('merchant and amount kept', v_tx.merchant || '/' || v_tx.amount::text, 'T39 Panda/100.00');
    SELECT * INTO v_tx FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000002';
    PERFORM pg_temp.expect('a note with no tags is cleared', v_tx.notes, NULL);
    PERFORM pg_temp.expect('row off a deleted account is unlinked', v_tx.account_id::text, NULL);
    PERFORM pg_temp.expect('settlement head kept with the id replaced',
        (SELECT notes FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000005'),
        'Settlement | PaidBy: deleted_member | Recipient: ' || pg_temp.u(1) || ' | Method: cash');

    -- Other members' rows no longer name B or B's linked dependent; A's words stay.
    SELECT * INTO v_tx FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000006';
    PERFORM pg_temp.expect('A''s note keeps its words', v_tx.notes, 'A note by A | PaidBy: me | Beneficiary: deleted_member | SpentBy: me');
    PERFORM pg_temp.expect('beneficiary sentinel', v_tx.beneficiary_id, 'deleted_member');
    PERFORM pg_temp.expect('A is still the creator', v_tx.user_id::text, pg_temp.u(1)::text);
    PERFORM pg_temp.expect('line items: id, claimed name, other member',
        v_tx.line_items::text,
        format('[{"name": "bread", "beneficiary": "deleted_member"}, {"name": "tea", "beneficiary": "deleted_member"}, {"name": "jam", "beneficiary": "%s"}]', pg_temp.u(3)));
    SELECT * INTO v_tx FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000007';
    PERFORM pg_temp.expect('settlement target sentinel', v_tx.settlement_target_id, 'deleted_member');
    PERFORM pg_temp.expect('settlement recipient replaced in A''s note', v_tx.notes,
        'Settlement | PaidBy: ' || pg_temp.u(1) || ' | Recipient: deleted_member | Method: bank');

    -- Income and transfers.
    PERFORM pg_temp.expect('pool income kept and scrubbed',
        (SELECT user_id::text || '|' || notes || '|' || title FROM public.income_records WHERE id = 'e39e0000-0000-0000-0000-000000000001'), NULL);
    PERFORM pg_temp.expect('pool income row',
        (SELECT (user_id IS NULL)::text || '/' || (notes IS NULL)::text || '/' || title || '/' || net_amount::text
         FROM public.income_records WHERE id = 'e39e0000-0000-0000-0000-000000000001'), 'true/true/salary/200.00');
    PERFORM pg_temp.expect('income into B''s personal account gone, whoever recorded it',
        (SELECT count(*)::text FROM public.income_records WHERE id IN ('e39e0000-0000-0000-0000-000000000002', 'e39e0000-0000-0000-0000-000000000003')), '0');
    PERFORM pg_temp.expect('B personal->pool transfer',
        (SELECT (user_id IS NULL)::text || '/' || (from_account_id IS NULL)::text || '/' || to_account_id::text || '/' || (notes IS NULL)::text
         FROM public.account_transfers WHERE id = 'e39f0000-0000-0000-0000-000000000001'), 'true/true/' || pg_temp.a(1) || '/true');
    PERFORM pg_temp.expect('A pool->B personal transfer keeps A, loses the note',
        (SELECT user_id::text || '/' || from_account_id::text || '/' || (to_account_id IS NULL)::text || '/' || (notes IS NULL)::text
         FROM public.account_transfers WHERE id = 'e39f0000-0000-0000-0000-000000000002'), pg_temp.u(1) || '/' || pg_temp.a(1) || '/true/true');
    PERFORM pg_temp.expect('transfer between B''s own accounts gone',
        (SELECT count(*)::text FROM public.account_transfers WHERE id = 'e39f0000-0000-0000-0000-000000000003'), '0');
    PERFORM pg_temp.expect('A''s own transfer note untouched',
        (SELECT notes FROM public.account_transfers WHERE id = 'e39f0000-0000-0000-0000-000000000004'), 'A to A personal');

    -- Dependents, invites, instalments, inquiries.
    PERFORM pg_temp.expect('linked dependent gone, unlinked stays',
        (SELECT string_agg(name, ',') FROM public.household_dependents WHERE household_id = pg_temp.h(1)), 'T39 Unclaimed Child');
    PERFORM pg_temp.expect('targeted invite gone with the dependent',
        (SELECT count(*)::text FROM public.household_invites WHERE invite_code = 'T39INV02'), '0');
    PERFORM pg_temp.expect('B''s open invite stays, creator NULL',
        (SELECT (created_by IS NULL)::text FROM public.household_invites WHERE invite_code = 'T39INV01'), 'true');
    PERFORM pg_temp.expect('instalment note scrubbed, plan kept',
        (SELECT (notes IS NULL)::text FROM public.installment_plans WHERE merchant = 'T39 BNPL'), 'true');
    PERFORM pg_temp.expect('budget funded by B''s account falls back to NULL',
        (SELECT account_id::text FROM public.budgets WHERE id = 'e39b0000-0000-0000-0000-000000000001'), NULL);
    PERFORM pg_temp.expect('B''s inquiries gone, others stay',
        (SELECT string_agg(reference, ',' ORDER BY reference) FROM public.inquiries WHERE reference LIKE 'T39-INQ-%'), 'T39-INQ-3');

    -- Nothing of B anywhere in public.
    PERFORM pg_temp.expect('email anywhere', pg_temp.scan('t39-bilal@test.local'), '');
    PERFORM pg_temp.expect('display name anywhere', pg_temp.scan('Uniqueperson Bilal'), '');
    PERFORM pg_temp.expect('display name anywhere', pg_temp.scan('Bilal Uniqueperson'), '');
    PERFORM pg_temp.expect('reason anywhere', pg_temp.scan('T39 reason'), '');
    PERFORM pg_temp.expect('user id anywhere', pg_temp.scan(pg_temp.u(2)::text), '');
    PERFORM pg_temp.expect('claimed dependent name anywhere', pg_temp.scan('T39 Claimed Child'), '');

    -- The other members are unaffected.
    PERFORM pg_temp.expect('A keeps their role',
        (SELECT role FROM public.household_memberships WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(1)), 'admin');
    PERFORM pg_temp.expect('second household keeps B''s row with a NULL creator',
        (SELECT (user_id IS NULL)::text || '/' || (notes IS NULL)::text FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000008'), 'true/true');
    RAISE NOTICE 'PASSED: member purge leaves surviving ledgers exactly equal and nothing of the member in public.';
END $$;

-- 2. Wife purge: W -----------------------------------------------------------------------
DO $$
DECLARE
    v_before text := pg_temp.ledger(ARRAY[pg_temp.h(3)]);
    v_spent numeric;
BEGIN
    SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = 'e39b0000-0000-0000-0000-000000000004';
    PERFORM pg_temp.expect('fixture: budget counts reimbursable and husband rows, not personal', v_spent::text, '105.00');

    PERFORM pg_temp.request(6);
    PERFORM pg_temp.purge(6);

    PERFORM pg_temp.expect('budget and pool exactly equal after purging the wife', pg_temp.ledger(ARRAY[pg_temp.h(3)]), v_before);
    PERFORM pg_temp.expect('her personal purchase never reached the category budget',
        (SELECT spent_amount::text FROM public.budgets WHERE id = 'e39b0000-0000-0000-0000-000000000006'), '0.00');
    PERFORM pg_temp.expect('wife_personal row deleted',
        (SELECT count(*)::text FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000011'), '0');
    PERFORM pg_temp.expect('wife_reimbursable row kept, declassified, creator NULL',
        (SELECT (nafaqah_class IS NULL)::text || '/' || (nafaqah_spouse_id IS NULL)::text || '/' || (user_id IS NULL)::text || '/' || amount::text
         FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000012'), 'true/true/true/80.00');
    PERFORM pg_temp.expect('allowance gone',
        (SELECT count(*)::text FROM public.member_allowances WHERE household_id = pg_temp.h(3)), '0');
    PERFORM pg_temp.expect('reimbursement ledger gone',
        (SELECT count(*)::text FROM public.spouse_reimbursements WHERE household_id = pg_temp.h(3)), '0');
    PERFORM pg_temp.expect('husband still provider and admin',
        (SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = pg_temp.h(3)), pg_temp.u(5)::text);
    PERFORM pg_temp.expect('wife name anywhere', pg_temp.scan('Wafa Uniqueperson'), '');
    PERFORM pg_temp.expect('wife email anywhere', pg_temp.scan('t39-wafa@test.local'), '');
    RAISE NOTICE 'PASSED: purging the wife moves no budget and removes her ledger.';
END $$;

-- 3. Household deleted: X chose delete -----------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    v_keep text := pg_temp.ledger(ARRAY[pg_temp.h(5)]);
    v_res jsonb;
    v_paths text;
BEGIN
    PERFORM pg_temp.request(8, format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(4)));
    v_id := pg_temp.make_due(8);
    PERFORM pg_temp.claim();
    v_res := pg_temp.prepare(v_id);
    PERFORM pg_temp.expect('prepared', v_res->>'prepared', 'true');

    v_paths := pg_temp.svc(format(
        $q$SELECT string_agg(bucket || ':' || path || ':' || is_prefix::text, ',') FROM public.list_account_purge_storage(%L)$q$, v_id));
    PERFORM pg_temp.expect('household folder queued as a prefix', v_paths, 'receipts:' || pg_temp.h(4) || '/:true');

    PERFORM pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    DELETE FROM auth.users WHERE id = pg_temp.u(8);
    PERFORM pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));

    PERFORM pg_temp.expect('household gone', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(4)), '0');
    PERFORM pg_temp.expect('accounts gone, including another member''s personal one',
        (SELECT count(*)::text FROM public.accounts WHERE id IN (pg_temp.a(10), pg_temp.a(11))), '0');
    PERFORM pg_temp.expect('rows gone', (SELECT count(*)::text FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000021'), '0');
    PERFORM pg_temp.expect('budgets gone', (SELECT count(*)::text FROM public.budgets WHERE household_id = pg_temp.h(4)), '0');

    -- Y keeps the login and moves to E with E's role and financial role.
    PERFORM pg_temp.expect('member with another household repoints with the right roles',
        (SELECT household_id::text || '/' || role || '/' || financial_role FROM public.users WHERE id = pg_temp.u(9)),
        pg_temp.h(5) || '/admin/family_member');
    PERFORM pg_temp.expect('that membership is now the default',
        (SELECT is_default::text FROM public.household_memberships WHERE user_id = pg_temp.u(9) AND household_id = pg_temp.h(5)), 'true');
    -- N keeps the login with no household.
    PERFORM pg_temp.expect('member with no other household gets NULL',
        (SELECT COALESCE(household_id::text, 'null') || '/' || role FROM public.users WHERE id = pg_temp.u(11)), 'null/member');
    PERFORM pg_temp.expect('N''s auth row is untouched',
        (SELECT count(*)::text FROM auth.users WHERE id = pg_temp.u(11)), '1');
    PERFORM pg_temp.expect('E''s ledger is untouched', pg_temp.ledger(ARRAY[pg_temp.h(5)]), v_keep);
    RAISE NOTICE 'PASSED: a marked household is deleted; members keep logins and repoint correctly.';
END $$;

-- 4. Co-admin: Q leaves, T survives ---------------------------------------------------------
DO $$
DECLARE
    v_before text;
BEGIN
    v_before := pg_temp.ledger(ARRAY[pg_temp.h(6)]);
    PERFORM pg_temp.request(12);
    PERFORM pg_temp.expect('co-admin prepares without deferring', (pg_temp.purge(12))->>'prepared', 'true');
    PERFORM pg_temp.expect('household survives', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(6)), '1');
    PERFORM pg_temp.expect('primary admin unchanged', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(6)), pg_temp.u(13)::text);
    PERFORM pg_temp.expect('co-admin''s pool re-owned, balance kept',
        (SELECT owner_user_id::text || '/' || balance::text FROM public.accounts WHERE id = pg_temp.a(12)), pg_temp.u(13) || '/150.00');
    PERFORM pg_temp.expect('co-admin''s personal gone', (SELECT count(*)::text FROM public.accounts WHERE id = pg_temp.a(13)), '0');
    PERFORM pg_temp.expect('ledger equal', pg_temp.ledger(ARRAY[pg_temp.h(6)]), v_before);
    RAISE NOTICE 'PASSED: a non-primary co-admin leaves and the household survives.';
END $$;

-- 5. Late-surfaced: G was a co-admin, then the primary left --------------------------------
DO $$
DECLARE
    v_id uuid;
    v_res jsonb;
    v_due timestamptz := now() + interval '7 days';
BEGIN
    PERFORM pg_temp.request(14);
    v_id := pg_temp.req_id(14);
    -- O, the primary, leaves. G is pending but is the only other admin, so G inherits.
    PERFORM pg_temp.call(pg_temp.u(15), NULL, 'SELECT public.switch_active_household(' || quote_literal(pg_temp.h(7)) || ')::text');
    PERFORM pg_temp.call(pg_temp.u(15), NULL, 'SELECT public.leave_household()::text');
    PERFORM pg_temp.expect('G became primary', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(7)), pg_temp.u(14)::text);

    v_id := pg_temp.make_due(14);
    PERFORM pg_temp.claim();
    v_res := pg_temp.prepare(v_id);
    PERFORM pg_temp.expect('deferred', v_res->>'deferred', 'true');
    PERFORM pg_temp.expect('household not deleted silently', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(7)), '1');
    PERFORM pg_temp.expect('household marked 7 days out',
        (SELECT (deletion_requested_by = pg_temp.u(14) AND deletion_scheduled_for = v_due AND deletion_requested_at IS NOT NULL)::text
         FROM public.households WHERE id = pg_temp.h(7)), 'true');
    PERFORM pg_temp.expect('request extended and back to scheduled, nothing purged',
        (SELECT status || '/' || stage || '/' || (scheduled_for = v_due)::text || '/' || attempts::text FROM public.account_deletion_requests WHERE id = v_id),
        'scheduled/none/true/0');
    PERFORM pg_temp.expect('G''s membership is intact',
        (SELECT role FROM public.household_memberships WHERE household_id = pg_temp.h(7) AND user_id = pg_temp.u(14)), 'admin');
    PERFORM pg_temp.expect('marked household refuses joins',
        pg_temp.call(pg_temp.u(21), NULL, format('SELECT public.join_household_by_code(%L)::text', 'T39CODE000000007')), 'ERR:household_pending_deletion');
    -- G can still cancel during those 7 days.
    PERFORM pg_temp.expect('G can cancel in the notice period',
        pg_temp.call(pg_temp.u(14), NULL, 'SELECT public.get_account_deletion_status()::text')::jsonb ->> 'can_cancel', 'true');

    -- 7 days later: applies the "still administers" rule.
    v_res := pg_temp.purge(14);
    PERFORM pg_temp.expect('second run deletes', v_res->>'prepared', 'true');
    PERFORM pg_temp.expect('household deleted after the notice', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(7)), '0');
    PERFORM pg_temp.expect('J keeps the login with no household',
        (SELECT COALESCE(household_id::text, 'null') FROM public.users WHERE id = pg_temp.u(16)), 'null');
    RAISE NOTICE 'PASSED: a late-surfaced household gets 7 days'' notice, then is deleted.';
END $$;

-- 7b. Leases and backoff ----------------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    v_res jsonb;
BEGIN
    PERFORM pg_temp.request(22);
    v_id := pg_temp.make_due(22);
    PERFORM pg_temp.expect('claim', pg_temp.claim()::text, '1');
    PERFORM pg_temp.expect('held lease is skipped', pg_temp.claim()::text, '0');
    PERFORM pg_temp.expect('attempts counted', (SELECT attempts::text FROM public.account_deletion_requests WHERE id = v_id), '1');

    -- The worker died: the lease expires and the job is reclaimed.
    UPDATE public.account_deletion_requests SET lease_expires_at = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.expect('expired lease reclaimed', pg_temp.claim()::text, '1');
    PERFORM pg_temp.expect('attempts after the reclaim', (SELECT attempts::text FROM public.account_deletion_requests WHERE id = v_id), '2');

    -- Failure backs off exponentially and keeps the job in progress.
    v_res := pg_temp.svc(format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'storage_error'))::jsonb;
    PERFORM pg_temp.expect('still processing', v_res->>'status', 'processing');
    PERFORM pg_temp.expect('backoff of 2 hours after attempt 2',
        ((SELECT lease_expires_at FROM public.account_deletion_requests WHERE id = v_id) = now() + interval '2 hours')::text, 'true');
    PERFORM pg_temp.expect('error code stored', (SELECT last_error_code FROM public.account_deletion_requests WHERE id = v_id), 'storage_error');
    PERFORM pg_temp.expect('backing off is not claimable', pg_temp.claim()::text, '0');

    -- Raw text never lands in last_error_code.
    v_res := pg_temp.svc(format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'HTTP 500 for bilal@test.local'))::jsonb;
    PERFORM pg_temp.expect('non-code error text refused',
        (SELECT last_error_code FROM public.account_deletion_requests WHERE id = v_id), 'unknown_error');

    -- Attempts 3, 4 back off; 5 is terminal.
    UPDATE public.account_deletion_requests SET lease_expires_at = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.claim();
    v_res := pg_temp.svc(format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'auth_error'))::jsonb;
    PERFORM pg_temp.expect('attempt 3 still processing', v_res->>'status', 'processing');
    UPDATE public.account_deletion_requests SET lease_expires_at = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.claim();
    v_res := pg_temp.svc(format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'auth_error'))::jsonb;
    PERFORM pg_temp.expect('attempt 4 still processing', v_res->>'status', 'processing');
    UPDATE public.account_deletion_requests SET lease_expires_at = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.claim();
    v_res := pg_temp.svc(format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'auth_error'))::jsonb;
    PERFORM pg_temp.expect('attempt 5 is terminal', v_res->>'status', 'failed');
    PERFORM pg_temp.expect('failed is not claimable', pg_temp.claim()::text, '0');
    PERFORM pg_temp.expect('a failed user stays pending', public.account_deletion_user_pending(pg_temp.u(22))::text, 'true');
    PERFORM pg_temp.expect('failed cannot be cancelled',
        pg_temp.call(pg_temp.u(22), NULL, 'SELECT public.cancel_account_deletion()::text'), 'ERR:deletion_in_progress');

    -- A worker that dies five times without recording anything also ends up failed.
    PERFORM pg_temp.request(23);
    v_id := pg_temp.make_due(23);
    UPDATE public.account_deletion_requests SET status = 'processing', attempts = 5, lease_expires_at = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.expect('crash-looping job not claimed', pg_temp.claim()::text, '0');
    PERFORM pg_temp.expect('crash-looping job failed', (SELECT status FROM public.account_deletion_requests WHERE id = v_id), 'failed');
    RAISE NOTICE 'PASSED: lease expiry reclaims, a held lease is skipped, backoff, then failed after 5.';
END $$;

-- 8. Ledger invariant ---------------------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    v_res text;
    v_before text;
BEGIN
    -- Old data: a wife_personal row debited a pool, from before trg_enforce_wife_class_account.
    PERFORM pg_temp.hh(8, 'family');
    PERFORM pg_temp.join(24, 8, 'admin', 'provider');
    PERFORM pg_temp.join(25, 8, 'member', 'spouse');
    PERFORM pg_temp.acct(20, 8, 24, true, 500);
    ALTER TABLE public.transactions DISABLE TRIGGER trg_enforce_wife_class_account;
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id, account_id) VALUES
        ('e39d0000-0000-0000-0000-000000000031', pg_temp.h(8), pg_temp.u(25), 40, 'T39 Legacy', 'OPEX-SHOPPING', now(), 'manual', 'me', 'wife_personal', pg_temp.u(25), pg_temp.a(20));
    ALTER TABLE public.transactions ENABLE TRIGGER trg_enforce_wife_class_account;
    v_before := pg_temp.ledger(ARRAY[pg_temp.h(8)]);

    PERFORM pg_temp.request(25);
    v_id := pg_temp.make_due(25);
    PERFORM pg_temp.claim();
    v_res := pg_temp.svc(format('SELECT public.prepare_account_purge(%L)::text', v_id));
    PERFORM pg_temp.expect('prepare aborts instead of moving a pool', v_res, 'ERR:purge_ledger_invariant');
    PERFORM pg_temp.expect('nothing moved', pg_temp.ledger(ARRAY[pg_temp.h(8)]), v_before);
    PERFORM pg_temp.expect('nothing purged',
        (SELECT stage FROM public.account_deletion_requests WHERE id = v_id), 'none');
    PERFORM pg_temp.expect('the row is still there',
        (SELECT count(*)::text FROM public.transactions WHERE id = 'e39d0000-0000-0000-0000-000000000031'), '1');
    RAISE NOTICE 'PASSED: a purge that would move a surviving pool aborts with nothing changed.';
END $$;

-- 9. Notices and heartbeat -------------------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    v_due text;
    v_res text;
BEGIN
    -- 26 is primary of household 9 with member 27, chose delete; 12 days out: only the member's first notice.
    PERFORM pg_temp.hh(9);
    PERFORM pg_temp.join(26, 9, 'admin', 'peer');
    PERFORM pg_temp.join(27, 9, 'member', 'peer');
    PERFORM pg_temp.request(26, format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(9)));
    v_id := pg_temp.req_id(26);
    PERFORM pg_temp.set_date(26, now() + interval '12 days');

    v_due := pg_temp.svc(format(
        $q$SELECT string_agg(user_id::text || ':' || notice || ':' || locale, ',' ORDER BY notice, user_id)
           FROM public.list_account_deletion_notices_due() WHERE request_id = %L$q$, v_id));
    PERFORM pg_temp.expect('member told when marked', v_due, pg_temp.u(27) || ':member_marked:en');
    PERFORM pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', v_id, 'member_marked'));
    v_due := pg_temp.svc(format('SELECT count(*)::text FROM public.list_account_deletion_notices_due() WHERE request_id = %L', v_id));
    PERFORM pg_temp.expect('nothing due after sending', v_due, '0');

    -- T-7.
    PERFORM pg_temp.set_date(26, now() + interval '6 days');
    v_due := pg_temp.svc(format(
        $q$SELECT string_agg(user_id::text || ':' || notice, ',' ORDER BY notice, user_id)
           FROM public.list_account_deletion_notices_due() WHERE request_id = %L$q$, v_id));
    PERFORM pg_temp.expect('T-7 for holder and member', v_due, pg_temp.u(26) || ':holder_t7,' || pg_temp.u(27) || ':member_t7');
    PERFORM pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', v_id, 'holder_t7'));
    PERFORM pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', v_id, 'member_t7'));

    -- T-1, holder only.
    PERFORM pg_temp.set_date(26, now() + interval '12 hours');
    v_due := pg_temp.svc(format(
        $q$SELECT string_agg(user_id::text || ':' || notice, ',') FROM public.list_account_deletion_notices_due() WHERE request_id = %L$q$, v_id));
    PERFORM pg_temp.expect('T-1 for the holder', v_due, pg_temp.u(26) || ':holder_t1');
    PERFORM pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', v_id, 'holder_t1'));

    -- A mark made inside the last 7 days: its first notice is enough, no T-7 an hour later.
    PERFORM pg_temp.hh(11);
    PERFORM pg_temp.join(28, 11, 'admin', 'peer');
    PERFORM pg_temp.join(29, 11, 'member', 'peer');
    PERFORM pg_temp.request(28, format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(11)));
    PERFORM pg_temp.set_date(28, now() + interval '5 days');
    v_due := pg_temp.svc(format(
        $q$SELECT string_agg(user_id::text || ':' || notice, ',' ORDER BY notice, user_id)
           FROM public.list_account_deletion_notices_due() WHERE request_id = %L$q$, pg_temp.req_id(28)));
    PERFORM pg_temp.expect('holder T-7 and the member''s first notice', v_due,
        pg_temp.u(28) || ':holder_t7,' || pg_temp.u(29) || ':member_marked');
    PERFORM pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', pg_temp.req_id(28), 'holder_t7'));
    PERFORM pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', pg_temp.req_id(28), 'member_marked'));
    v_due := pg_temp.svc(format('SELECT count(*)::text FROM public.list_account_deletion_notices_due() WHERE request_id = %L', pg_temp.req_id(28)));
    PERFORM pg_temp.expect('no second member notice', v_due, '0');

    -- Completion, once the job is under way and while the auth user still exists.
    v_id := pg_temp.make_due(26);
    PERFORM pg_temp.claim();
    PERFORM pg_temp.prepare(v_id);
    v_due := pg_temp.svc(format(
        $q$SELECT string_agg(user_id::text || ':' || notice, ',') FROM public.list_account_deletion_notices_due() WHERE request_id = %L$q$, v_id));
    PERFORM pg_temp.expect('completion notice due after prepare', v_due, pg_temp.u(26) || ':holder_completion');

    PERFORM pg_temp.expect('an unknown notice is refused',
        pg_temp.svc(format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', v_id, 'nonsense')), 'ERR:22023');

    v_res := pg_temp.svc($q$SELECT public.record_account_deletion_worker_run(now() - interval '1 minute', 3, 2, 1)::text$q$);
    IF v_res LIKE 'ERR:%' THEN RAISE EXCEPTION 'heartbeat: %', v_res; END IF;
    PERFORM pg_temp.expect('heartbeat stored',
        (SELECT claimed::text || '/' || completed::text || '/' || failed::text FROM public.account_deletion_worker_runs ORDER BY finished_at DESC LIMIT 1), '3/2/1');
    RAISE NOTICE 'PASSED: notices come due in order and once each; the worker heartbeat is stored.';
END $$;

-- 10. Privileges -------------------------------------------------------------------------------------
DO $$
DECLARE
    v_call record;
    v_id uuid := gen_random_uuid();
BEGIN
    FOR v_call IN
        SELECT * FROM (VALUES
            ('claim_due_account_deletions(integer, integer)', 'SELECT count(*)::text FROM public.claim_due_account_deletions(1, 1)'),
            ('prepare_account_purge(uuid)', format('SELECT public.prepare_account_purge(%L)::text', v_id)),
            ('list_account_purge_storage(uuid)', format('SELECT count(*)::text FROM public.list_account_purge_storage(%L)', v_id)),
            ('mark_account_purge_storage_done(uuid)', format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id)),
            ('complete_account_purge(uuid)', format('SELECT public.complete_account_purge(%L)::text', v_id)),
            ('record_account_purge_failure(uuid, text)', format('SELECT public.record_account_purge_failure(%L, %L)::text', v_id, 'x')),
            ('list_account_deletion_notices_due()', 'SELECT count(*)::text FROM public.list_account_deletion_notices_due()'),
            ('mark_account_deletion_notice_sent(uuid, text)', format('SELECT public.mark_account_deletion_notice_sent(%L, %L)::text', v_id, 'holder_t7')),
            ('record_account_deletion_worker_run(timestamp with time zone, integer, integer, integer)', 'SELECT public.record_account_deletion_worker_run(now(), 0, 0, 0)::text')
        ) AS t(sig, sql)
    LOOP
        IF has_function_privilege('anon', 'public.' || v_call.sig, 'EXECUTE')
           OR has_function_privilege('authenticated', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'VULNERABILITY: a client role can execute %', v_call.sig;
        END IF;
        IF NOT has_function_privilege('service_role', 'public.' || v_call.sig, 'EXECUTE') THEN
            RAISE EXCEPTION 'REGRESSION: service_role cannot execute %', v_call.sig;
        END IF;
        PERFORM pg_temp.expect('authenticated on ' || v_call.sig, pg_temp.call(pg_temp.u(1), NULL, v_call.sql), 'ERR:42501');
        PERFORM pg_temp.expect('anon on ' || v_call.sig, pg_temp.call(NULL, NULL, v_call.sql, 'anon'), 'ERR:42501');
        -- The body refuses too: service_role privileges with a user JWT subject.
        PERFORM pg_temp.expect('a subject under service_role on ' || v_call.sig,
            pg_temp.call(pg_temp.u(1), NULL, v_call.sql, 'service_role'), 'ERR:42501');
    END LOOP;

    IF has_function_privilege('authenticated', 'public.account_deletion_repoint_active_household(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.account_deletion_repoint_active_household(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'VULNERABILITY: the repoint helper is client-callable';
    END IF;
    RAISE NOTICE 'PASSED: authenticated and anon get 42501 on every purge function; a JWT subject is refused.';
END $$;

-- 11. Out-of-band deletion during grace -----------------------------------------------------------------
DO $$
DECLARE
    v_id uuid;
    v_res jsonb;
BEGIN
    PERFORM pg_temp.hh(10);
    PERFORM pg_temp.join(30, 10, 'admin', 'peer');
    PERFORM pg_temp.join(31, 10, 'member', 'peer');
    PERFORM pg_temp.acct(30, 10, 30, true, 250);
    PERFORM pg_temp.request(30, format('[{"household_id": "%s", "action": "delete"}]', pg_temp.h(10)));
    v_id := pg_temp.req_id(30);

    -- Someone clicks delete in the dashboard during grace.
    DELETE FROM auth.users WHERE id = pg_temp.u(30);
    PERFORM pg_temp.expect('household survives', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(10)), '1');
    PERFORM pg_temp.expect('the mark is gone with them', (SELECT deletion_scheduled_for::text FROM public.households WHERE id = pg_temp.h(10)), NULL);
    PERFORM pg_temp.expect('handover to the member', (SELECT owner_user_id::text FROM public.households WHERE id = pg_temp.h(10)), pg_temp.u(31)::text);
    PERFORM pg_temp.expect('pool kept', (SELECT owner_user_id::text || '/' || balance::text FROM public.accounts WHERE id = pg_temp.a(30)), pg_temp.u(31) || '/250.00');

    -- The job still runs to completion on what is left.
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_id;
    PERFORM pg_temp.claim();
    v_res := pg_temp.prepare(v_id);
    PERFORM pg_temp.expect('prepare with no user', v_res->>'prepared', 'true');
    PERFORM pg_temp.svc(format('SELECT public.mark_account_purge_storage_done(%L)::text', v_id));
    PERFORM pg_temp.svc(format('SELECT public.complete_account_purge(%L)::text', v_id));
    PERFORM pg_temp.expect('completed', (SELECT status FROM public.account_deletion_requests WHERE id = v_id), 'completed');
    PERFORM pg_temp.expect('household still survives', (SELECT count(*)::text FROM public.households WHERE id = pg_temp.h(10)), '1');
    RAISE NOTICE 'PASSED: out-of-band deletion never deletes a household and the job still completes.';
END $$;

ROLLBACK;
