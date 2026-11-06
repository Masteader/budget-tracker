-- ============================================================================
-- Test 67: Round 3 follow-up (R3B) fixes: who writes what they cannot read, repayment transfers,
--          reversals, a deleted wife's plans, receipts (owner decisions 2026-11-06)
--
-- Migration: 20261105001300_wife_repayment_debit.sql (sections 8, 9, 10, 10d, 10e and 10f)
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rules 2 and 3;
--       .agents/rules/04-security-and-privacy.md, RLS and Family Nafaqah
--
-- One finding each (every check is collected, so a failing run lists them all):
--   R3B-01  A caller who cannot read a row cannot update or delete it: the UPDATE and DELETE
--           policies of transactions carry the read test (USING, and the new row in WITH CHECK),
--           also for a statement that reads no column (UPDATE ... WHERE true, DELETE with no WHERE,
--           as supabase-js .update() / .delete() with no filter and return=minimal send them).
--           The other tables whose read was restricted: installment_plans (FOR ALL), receipt photos
--           (storage DELETE; no UPDATE policy), and the ledger, request, outcome, former member,
--           allowance and transfer tables, which no client writes at all.
--   R3B-02  A repayment's transfer rows (a repayment to the wife, its reversal, a former member's
--           payment and its reversal) are read by the wife whose ledger it is (wife repayments),
--           that ledger's managers, and the owner of the personal account the money left or
--           returned to (his own rows only). Pool lines too: nobody else.
--   R3B-03  The installment_plans read test looks nothing up per plan: no transactions scan.
--   R3B-04  nafaqah_receipt_hidden answers the same for a path that is no object and for a photo
--           the caller does not read; a non-member gets the same answer; checked first.
--   R3B-05  A plan is never created or linked again to a purchase the caller does not read: the
--           refusal is the same as for an id of nothing and for another household's purchase.
--   R3B-06  A personal account's repayment is reversed only by its owner while he is a ledger
--           manager (the husband, or an admin who is not a wife when he is gone): a replaced
--           husband or a demoted admin no longer reverses, even his own. A pool's as before.
--   R3B-08  A wife's advance (wife_reimbursable) is re-attributed (its wife or class changed) only
--           by her (clearing her own) or her ledger's managers; never by a wife-admin or another
--           admin while the husband is there.
--   Item 4  A deleted wife's personal plans stay read only by her husband and the admins who are
--           not wives, through the purge and after, with nothing of hers left on them.
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
-- A write as user p_sub (or the service role when p_sub is NULL): the rows it changed, or
-- ERR:<SQLSTATE>:<message> (the whole message, to compare two refusals).
CREATE FUNCTION pg_temp.write(p_sub uuid, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_n bigint;
    v_role text := CASE WHEN p_sub IS NULL THEN 'service_role' ELSE 'authenticated' END;
    v_claims jsonb := jsonb_build_object('role', CASE WHEN p_sub IS NULL THEN 'service_role' ELSE 'authenticated' END);
BEGIN
    IF p_sub IS NOT NULL THEN
        v_claims := v_claims || jsonb_build_object('sub', p_sub);
    END IF;
    PERFORM set_config('request.jwt.claims', v_claims::text, true);
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE || ':' || SQLERRM;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v_n::text;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text), pg_temp.write(uuid, text) TO PUBLIC;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e6700000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e67a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e67b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e67c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.p(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e67d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e67e0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.t(int), pg_temp.p(int), pg_temp.k(int) TO PUBLIC;

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
CREATE FUNCTION pg_temp.keep(p_label text, p_val text) RETURNS void LANGUAGE sql
AS $$ INSERT INTO pg_temp.snap VALUES (p_label, p_val) ON CONFLICT (label) DO UPDATE SET val = EXCLUDED.val $$;
CREATE FUNCTION pg_temp.id(p_label text) RETURNS uuid LANGUAGE sql
AS $$ SELECT CASE WHEN val ~ '^[0-9a-f-]{36}$' THEN val::uuid END FROM pg_temp.snap WHERE label = p_label $$;
CREATE FUNCTION pg_temp.j(p_res text, p_field text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    IF p_res IS NULL OR p_res LIKE 'ERR:%' THEN RETURN p_res; END IF;
    RETURN p_res::jsonb ->> p_field;
END;
$$;
CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;

-- F1's people, by the name the checks use (W5 until her purge).
CREATE TABLE pg_temp.people (n int, name text);
INSERT INTO pg_temp.people VALUES (1, 'H'), (2, 'W'), (3, 'W2'), (4, 'K'), (5, 'C'), (6, 'WA'), (7, 'W5');
-- Who of F1 reads the row of p_table with id p_id (as the client reads it), by name.
CREATE FUNCTION pg_temp.readers(p_table text, p_id uuid) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(pp.name, ',' ORDER BY pp.n), '')
    FROM pg_temp.people pp
    WHERE pg_temp.call(pg_temp.u(pp.n), format('SELECT count(*)::text FROM public.%I WHERE id = %L', p_table, p_id)) = '1';
$$;
-- The transfer row a ledger row moved its money with.
CREATE FUNCTION pg_temp.xfer(p_label text) RETURNS uuid LANGUAGE sql AS $$
    SELECT COALESCE((SELECT transfer_id FROM public.spouse_reimbursements WHERE id = pg_temp.id(p_label)),
                    (SELECT transfer_id FROM public.former_member_debt_events WHERE id = pg_temp.id(p_label)));
$$;

-- What a caller must never reach: every personal purchase (wife_personal) of a wife other than the
-- caller (a reclassification of one shows here, so does the budget it would move), her receipt
-- photo and the plans of another wife; for H and C (who read them all) the same signature, so a
-- check of theirs only proves nothing else moved. The budgets are not in it: an admin's edit of a
-- row she reads moves them as always.
CREATE FUNCTION pg_temp.hidden_sig(p_actor int) RETURNS text LANGUAGE sql AS $$
    SELECT md5(
        COALESCE((SELECT string_agg(t.id || ':' || COALESCE(t.notes, '-') || ':' || COALESCE(t.nafaqah_class, '-') || ':'
                                    || COALESCE(t.nafaqah_spouse_id::text, '-') || ':' || t.amount || ':' || COALESCE(t.merchant, '-'),
                                    ',' ORDER BY t.id)
                  FROM public.transactions t
                  WHERE t.household_id = pg_temp.h(1) AND t.nafaqah_class = 'wife_personal'
                    AND t.nafaqah_spouse_id IS DISTINCT FROM pg_temp.u(p_actor)), '')
        || '|' || COALESCE((SELECT string_agg(o.name || ':' || COALESCE(o.metadata::text, '-'), ',' ORDER BY o.name) FROM storage.objects o
                            WHERE o.bucket_id = 'receipts' AND o.name LIKE '%t67_w%'), '')
        || '|' || COALESCE((SELECT string_agg(p.id || ':' || COALESCE(p.notes, '-') || ':' || COALESCE(p.original_transaction_id::text, '-'),
                                              ',' ORDER BY p.id)
                            FROM public.installment_plans p WHERE p.personal_owner_id IS DISTINCT FROM pg_temp.u(p_actor)
                              AND p.personal_owner_id IS NOT NULL), ''));
$$;
-- A write as p_actor, undone at once: '<rows or ERR:SQLSTATE>|same' when nothing hidden from the
-- caller moved, '|changed' otherwise.
CREATE FUNCTION pg_temp.attempt(p_actor int, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_before text := pg_temp.hidden_sig(p_actor);
    v_res text;
    v_detail text;
BEGIN
    BEGIN
        v_res := pg_temp.write(pg_temp.u(p_actor), p_sql);
        IF v_res LIKE 'ERR:%' THEN
            v_res := left(v_res, 9);
        END IF;
        RAISE EXCEPTION 'undo' USING DETAIL = v_res || '|' ||
            CASE WHEN pg_temp.hidden_sig(p_actor) = v_before THEN 'same' ELSE 'changed' END;
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
        RETURN v_detail;
    END;
END;
$$;

-- The calls, as user p_actor (authenticated).
CREATE FUNCTION pg_temp.repay(p_actor int, p_wife int, p_amount text, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.record_spouse_reimbursement(%L, %L, %s, %L, NULL, NULL, %L::uuid, %L::uuid)::text',
               pg_temp.h(1), pg_temp.u(p_wife), p_amount, 'bank_transfer', pg_temp.a(p_account), pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.rev(p_actor int, p_row uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.reverse_spouse_reimbursement(%L, %L, %L::uuid, NULL)::text', pg_temp.h(1), p_row, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.debt() RETURNS uuid LANGUAGE sql
AS $$ SELECT id FROM public.former_member_debts WHERE household_id = pg_temp.h(1) $$;
GRANT EXECUTE ON FUNCTION pg_temp.debt() TO PUBLIC;
CREATE FUNCTION pg_temp.fpay(p_actor int, p_amount text, p_account int, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.record_former_member_debt_payment(%L, %L, %s, %L, %L::uuid, NULL, %L::uuid)::text',
               pg_temp.h(1), pg_temp.debt(), p_amount, 'cash', pg_temp.k(p_key), pg_temp.a(p_account)));
$$;
CREATE FUNCTION pg_temp.frev(p_actor int, p_event uuid, p_key int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT public.reverse_former_member_debt_payment(%L, %L, %L, %L::uuid, NULL)::text',
               pg_temp.h(1), pg_temp.debt(), p_event, pg_temp.k(p_key)));
$$;
CREATE FUNCTION pg_temp.provider(p_user int) RETURNS void LANGUAGE sql AS $$
    UPDATE public.households SET nafaqah_provider_user_id = CASE WHEN p_user = 0 THEN NULL ELSE pg_temp.u(p_user) END
    WHERE id = pg_temp.h(1);
$$;
CREATE FUNCTION pg_temp.role(p_user int, p_role text) RETURNS void LANGUAGE sql AS $$
    UPDATE public.household_memberships SET role = p_role WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(p_user);
$$;
-- The receipt helper as p_actor, on a path of F1's folder.
CREATE FUNCTION pg_temp.hidden(p_actor int, p_file text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format('SELECT public.nafaqah_receipt_hidden(%L)::text', pg_temp.h(1)::text || '/' || p_file));
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

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider; wife W(2); co-wife W2(3); member K(4); admin C(5) who is
--        not a wife; wife WA(6) who is an admin; wife W5(7), purged by the deletion worker later.
-- F2(2): admin D(9) and provider; wife V(10).
-- Accounts: F1 pool P(1) 5000 (owned by H), W's bank A(2) 1000, K's bank A(3) 1000, H's bank A(4)
--           3000, W2's bank A(5) 1000, C's bank A(6) 2000.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't67-' || n || '@test.local', jsonb_build_object('display_name', 'T67 User ' || n)
    FROM generate_series(1, 10) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T67 H1', 'T67CODE000000001', 'family', 27),
        (pg_temp.h(2), 'T67 H2', 'T67CODE000000002', 'family', 27);
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'member', 'family_member');
    PERFORM pg_temp.join(6, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(7, 1, 'member', 'spouse');
    PERFORM pg_temp.join(9, 2, 'admin', 'provider');
    PERFORM pg_temp.join(10, 2, 'member', 'spouse');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(9), nafaqah_provider_user_id = pg_temp.u(9) WHERE id = pg_temp.h(2);

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T67 pool', 'shared_pool', 5000, true, false, 'SAR'),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(2), 'T67 W bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(3), pg_temp.h(1), pg_temp.u(4), 'T67 K bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(4), pg_temp.h(1), pg_temp.u(1), 'T67 H bank', 'bank', 3000, false, false, 'SAR'),
        (pg_temp.a(5), pg_temp.h(1), pg_temp.u(3), 'T67 W2 bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(6), pg_temp.h(1), pg_temp.u(5), 'T67 C bank', 'bank', 2000, false, false, 'SAR');
    INSERT INTO public.budgets (household_id, category_code, cycle_key, month, allocated_amount, spent_amount, is_active) VALUES
        (pg_temp.h(1), 'OPEX-SHOPPING', '2026-11', '2026-11-01', 2000, 0, true),
        (pg_temp.h(1), 'OPEX-GROCERY', '2026-11', '2026-11-01', 2000, 0, true);

    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, account_id, receipt_url, notes) VALUES
        (pg_temp.t(1), pg_temp.h(1), pg_temp.u(1), 100, 'T67 Panda', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', NULL, NULL, pg_temp.a(1), pg_temp.h(1)::text || '/t67_o.jpg', 'n'),
        (pg_temp.t(2), pg_temp.h(1), pg_temp.u(2), 300, 'T67 Pharmacy', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(2), NULL, NULL, 'n'),
        (pg_temp.t(3), pg_temp.h(1), pg_temp.u(2), 200, 'T67 Boutique W', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), pg_temp.a(2), pg_temp.h(1)::text || '/t67_w.jpg', 'n'),
        (pg_temp.t(4), pg_temp.h(1), pg_temp.u(1), 150, 'T67 Gift for W', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), NULL, NULL, 'n'),
        (pg_temp.t(5), pg_temp.h(1), pg_temp.u(3), 300, 'T67 Salon W2', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(3), NULL, NULL, 'n'),
        (pg_temp.t(6), pg_temp.h(1), pg_temp.u(6), 400, 'T67 Perfume WA', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(6), NULL, NULL, 'n'),
        (pg_temp.t(7), pg_temp.h(1), pg_temp.u(7), 120, 'T67 Bag W5', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(7), NULL, NULL, 'n'),
        (pg_temp.t(8), pg_temp.h(1), pg_temp.u(7), 80, 'T67 Kohl W5', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(7), NULL, NULL, 'n'),
        (pg_temp.t(9), pg_temp.h(1), pg_temp.u(7), 100, 'T67 Grocer W5', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(7), NULL, NULL, 'n'),
        (pg_temp.t(10), pg_temp.h(1), pg_temp.u(6), 50, 'T67 Bakery WA', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', NULL, NULL, NULL, NULL, 'n'),
        (pg_temp.t(12), pg_temp.h(1), pg_temp.u(6), 40, 'T67 Taxi WA', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(6), NULL, NULL, 'n'),
        (pg_temp.t(11), pg_temp.h(2), pg_temp.u(10), 90, 'T67 Abaya V', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(10), NULL, NULL, 'n');

    INSERT INTO storage.objects (bucket_id, name, owner) VALUES
        ('receipts', pg_temp.h(1)::text || '/t67_o.jpg', pg_temp.u(1)),
        ('receipts', pg_temp.h(1)::text || '/t67_w.jpg', pg_temp.u(2));

    -- Plans as the API writes them (the service role).
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, original_transaction_id, notes) VALUES
        (pg_temp.p(1), pg_temp.h(1), 'pl1 Boutique W', 'Tabby', 200, 4, 50, 1, '2026-11-05', pg_temp.t(3), 'k'),
        (pg_temp.p(2), pg_temp.h(1), 'pl2 Panda', 'Tabby', 100, 4, 25, 1, '2026-11-05', pg_temp.t(1), 'k'),
        (pg_temp.p(3), pg_temp.h(1), 'pl3 Unlinked', 'Other', 400, 4, 100, 0, '2026-11-05', NULL, 'k'),
        (pg_temp.p(4), pg_temp.h(1), 'pl4 Bag W5', 'Tabby', 120, 4, 30, 1, '2026-11-05', pg_temp.t(7), 'k'),
        (pg_temp.p(5), pg_temp.h(1), 'pl5 Kohl W5', 'Tabby', 80, 2, 40, 1, '2026-11-05', pg_temp.t(8), 'k');
    -- Her purchase deleted: the plan keeps her (test 66).
    DELETE FROM public.transactions WHERE id = pg_temp.t(8);
END $$;

-- ── R3B-01: transactions: a caller who cannot read a row neither updates nor deletes it ─────────
DO $$
BEGIN
    PERFORM pg_temp.check('baseline: the wife-admin reads 6 of F1''s 10 rows',
        pg_temp.call(pg_temp.u(6), format('SELECT count(*)::text FROM public.transactions WHERE household_id = %L', pg_temp.h(1))), '6');
    -- The wife-admin: an admin edits any row of the household, but none she does not read.
    PERFORM pg_temp.check('wife-admin: blind UPDATE ... WHERE true',
        pg_temp.attempt(6, 'UPDATE public.transactions SET notes = ''blind'' WHERE true'), '6|same');
    PERFORM pg_temp.check('wife-admin: blind UPDATE, no WHERE',
        pg_temp.attempt(6, 'UPDATE public.transactions SET merchant = ''blind'''), '6|same');
    PERFORM pg_temp.check('wife-admin: blind DELETE',
        pg_temp.attempt(6, 'DELETE FROM public.transactions'), '6|same');
    PERFORM pg_temp.check('wife-admin: blind DELETE ... WHERE true',
        pg_temp.attempt(6, 'DELETE FROM public.transactions WHERE true'), '6|same');
    -- A blind reclassification: it would also re-attribute W's advance (R3B-08), so it is refused whole.
    PERFORM pg_temp.check('wife-admin: blind reclassification',
        pg_temp.attempt(6, 'UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL'), 'ERR:42501|same');
    PERFORM pg_temp.check('wife-admin: blind amount change',
        pg_temp.attempt(6, 'UPDATE public.transactions SET amount = amount + 1'), '6|same');
    -- By id, as before (the WHERE reads the row, so the read rule already applied).
    PERFORM pg_temp.check('wife-admin: update of her purchase by id',
        pg_temp.attempt(6, format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'x', pg_temp.t(3))), '0|same');
    PERFORM pg_temp.check('wife-admin: delete of her purchase by id',
        pg_temp.attempt(6, format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(4))), '0|same');
    -- The new row must be one she reads (WITH CHECK): she cannot make a row a co-wife's purchase.
    PERFORM pg_temp.check('wife-admin: her row made W''s personal purchase',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_class = %L, nafaqah_spouse_id = %L WHERE id = %L',
                                  'wife_personal', pg_temp.u(2), pg_temp.t(10))), 'ERR:42501|same');
    -- Her own personal purchase she reads.
    PERFORM pg_temp.check('wife-admin: her row made her own personal purchase',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_class = %L, nafaqah_spouse_id = %L WHERE id = %L',
                                  'wife_personal', pg_temp.u(6), pg_temp.t(10))), '1|same');

    -- A co-wife, a member and the wife herself (not admins): refused for others' rows, as before.
    PERFORM pg_temp.check('co-wife: blind UPDATE', pg_temp.attempt(3, 'UPDATE public.transactions SET notes = ''blind'' WHERE true'), 'ERR:42501|same');
    PERFORM pg_temp.check('co-wife: blind DELETE', pg_temp.attempt(3, 'DELETE FROM public.transactions'), 'ERR:42501|same');
    PERFORM pg_temp.check('member: blind UPDATE', pg_temp.attempt(4, 'UPDATE public.transactions SET notes = ''blind'' WHERE true'), 'ERR:42501|same');
    PERFORM pg_temp.check('member: blind reclassification',
        pg_temp.attempt(4, 'UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL'), 'ERR:42501|same');
    PERFORM pg_temp.check('co-wife: her own rows', pg_temp.attempt(3, format('UPDATE public.transactions SET notes = %L WHERE user_id = %L', 'own', pg_temp.u(3))), '1|same');
    -- Those who read every row edit them as before.
    PERFORM pg_temp.check('husband: blind UPDATE reaches every row', pg_temp.attempt(1, 'UPDATE public.transactions SET notes = ''blind'' WHERE true'), '10|changed');
    PERFORM pg_temp.check('admin who is not a wife: blind UPDATE reaches every row', pg_temp.attempt(5, 'UPDATE public.transactions SET notes = ''blind'' WHERE true'), '10|changed');
    PERFORM pg_temp.check('the wife: her own purchase', pg_temp.attempt(2, format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'mine', pg_temp.t(3))), '1|same');
    PERFORM pg_temp.check('the wife: deletes her own purchase', pg_temp.attempt(2, format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(3))), '1|same');
    -- Nothing moved: the rows, and the budgets (her purchases never reached them).
    PERFORM pg_temp.check('rows of F1 after the attempts', (SELECT count(*)::text FROM public.transactions WHERE household_id = pg_temp.h(1)), '10');
    PERFORM pg_temp.check('budgets after the attempts',
        (SELECT string_agg(category_code || '=' || spent_amount, ',' ORDER BY category_code) FROM public.budgets WHERE household_id = pg_temp.h(1)),
        'OPEX-GROCERY=590.00,OPEX-SHOPPING=0.00');
    -- A blind reclassification that left her advance alone still reaches no purchase of hers.
    PERFORM pg_temp.check('wife-admin: blind declassification of personal purchases',
        pg_temp.attempt(6, 'UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE true AND nafaqah_class IS DISTINCT FROM ''wife_reimbursable'''),
        '3|same');
END $$;

-- ── R3B-08: her advance is re-attributed only by her or her ledger's managers ─────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('wife-admin moves W''s advance to herself',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_spouse_id = %L WHERE id = %L', pg_temp.u(6), pg_temp.t(2))), 'ERR:42501|same');
    PERFORM pg_temp.check('wife-admin clears W''s advance',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(2))), 'ERR:42501|same');
    PERFORM pg_temp.check('wife-admin makes W''s advance W''s personal purchase',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_class = %L WHERE id = %L', 'wife_personal', pg_temp.t(2))), 'ERR:42501|same');
    PERFORM pg_temp.check('admin who is not a wife (the husband there) moves W''s advance',
        pg_temp.attempt(5, format('UPDATE public.transactions SET nafaqah_spouse_id = %L WHERE id = %L', pg_temp.u(3), pg_temp.t(2))), 'ERR:42501|same');
    PERFORM pg_temp.check('co-wife clears W''s advance',
        pg_temp.attempt(3, format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(2))), 'ERR:42501|same');
    -- What stays: other edits of her advance by an admin, her own clearing, the husband.
    -- An edit that sends her advance's class and wife unchanged (as an app's whole-row save does).
    PERFORM pg_temp.check('wife-admin edits the amount of W''s advance, class and wife sent unchanged',
        pg_temp.attempt(6, format('UPDATE public.transactions SET amount = 301, nafaqah_class = %L, nafaqah_spouse_id = %L WHERE id = %L',
                                  'wife_reimbursable', pg_temp.u(2), pg_temp.t(2))), '1|same');
    PERFORM pg_temp.check('wife-admin edits the note of W''s advance',
        pg_temp.attempt(6, format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'n2', pg_temp.t(2))), '1|same');
    PERFORM pg_temp.check('wife-admin hands her own advance to a co-wife',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_spouse_id = %L WHERE id = %L', pg_temp.u(2), pg_temp.t(12))), 'ERR:42501|same');
    PERFORM pg_temp.check('wife-admin clears her own advance',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(12))), '1|same');
    PERFORM pg_temp.check('the wife clears her own advance',
        pg_temp.attempt(2, format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(2))), '1|same');
    PERFORM pg_temp.check('the husband moves her advance to the co-wife',
        pg_temp.attempt(1, format('UPDATE public.transactions SET nafaqah_spouse_id = %L WHERE id = %L', pg_temp.u(3), pg_temp.t(2))), '1|same');
    -- The husband gone: an admin who is not a wife manages her ledger, a wife-admin still not.
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('gone: the admin who is not a wife clears her advance',
        pg_temp.attempt(5, format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(2))), '1|same');
    PERFORM pg_temp.check('gone: the wife-admin still not',
        pg_temp.attempt(6, format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(2))), 'ERR:42501|same');
    PERFORM pg_temp.provider(1);
    PERFORM pg_temp.check('W''s advance unchanged',
        (SELECT nafaqah_class || '/' || (nafaqah_spouse_id = pg_temp.u(2))::text FROM public.transactions WHERE id = pg_temp.t(2)), 'wife_reimbursable/true');
END $$;

-- ── R3B-01: the other tables whose read was restricted ─────────────────────────────────────────
DO $$
DECLARE
    v_t text;
BEGIN
    -- Installment plans (FOR ALL): the hidden plans are no target.
    PERFORM pg_temp.check('wife-admin: blind plan update',
        pg_temp.attempt(6, 'UPDATE public.installment_plans SET notes = ''blind'' WHERE true'), '2|same');
    PERFORM pg_temp.check('wife-admin: blind plan unlink',
        pg_temp.attempt(6, 'UPDATE public.installment_plans SET original_transaction_id = NULL'), '2|same');
    PERFORM pg_temp.check('wife-admin: blind plan delete', pg_temp.attempt(6, 'DELETE FROM public.installment_plans'), '2|same');
    PERFORM pg_temp.check('member: blind plan delete', pg_temp.attempt(4, 'DELETE FROM public.installment_plans WHERE true'), '2|same');
    -- Receipt photos: her photo is no target of a delete; no client updates a receipt at all.
    PERFORM pg_temp.check('wife-admin: blind receipt delete', pg_temp.attempt(6, 'DELETE FROM storage.objects'), '1|same');
    PERFORM pg_temp.check('member: blind receipt delete',
        pg_temp.attempt(4, 'DELETE FROM storage.objects WHERE bucket_id = ''receipts'''), '1|same');
    PERFORM pg_temp.check('wife-admin: blind receipt update', pg_temp.attempt(6, 'UPDATE storage.objects SET metadata = ''{}'''), '0|same');
    PERFORM pg_temp.check('the wife deletes her own photo',
        pg_temp.attempt(2, format('DELETE FROM storage.objects WHERE name = %L', pg_temp.h(1)::text || '/t67_w.jpg')), '1|changed');
    PERFORM pg_temp.check('the husband deletes her photo',
        pg_temp.attempt(1, format('DELETE FROM storage.objects WHERE name = %L', pg_temp.h(1)::text || '/t67_w.jpg')), '1|changed');
    -- The ledger, requests, outcomes, former member records, allowances and transfers: no client
    -- writes them at all.
    FOREACH v_t IN ARRAY ARRAY['account_transfers', 'spouse_reimbursements', 'spouse_reimbursement_requests',
                               'spouse_reimbursement_request_outcomes', 'former_member_debts', 'former_member_debt_events',
                               'member_allowances'] LOOP
        PERFORM pg_temp.check('wife-admin: blind delete of ' || v_t, pg_temp.attempt(6, format('DELETE FROM public.%I', v_t)), 'ERR:42501|same');
        PERFORM pg_temp.check('admin who is not a wife: blind delete of ' || v_t, pg_temp.attempt(5, format('DELETE FROM public.%I WHERE true', v_t)), 'ERR:42501|same');
        PERFORM pg_temp.check('client UPDATE or DELETE privilege on ' || v_t,
            (has_table_privilege('authenticated', 'public.' || v_t, 'UPDATE') OR has_table_privilege('authenticated', 'public.' || v_t, 'DELETE')
             OR has_table_privilege('anon', 'public.' || v_t, 'UPDATE') OR has_table_privilege('anon', 'public.' || v_t, 'DELETE'))::text, 'false');
    END LOOP;
    PERFORM pg_temp.check('wife-admin: blind update of the ledger',
        pg_temp.attempt(6, 'UPDATE public.spouse_reimbursements SET notes = ''x'''), 'ERR:42501|same');
    PERFORM pg_temp.check('wife-admin: blind update of the transfers',
        pg_temp.attempt(6, 'UPDATE public.account_transfers SET notes = ''x'' WHERE true'), 'ERR:42501|same');
    PERFORM pg_temp.check('wife-admin: blind update of the allowances',
        pg_temp.attempt(6, 'UPDATE public.member_allowances SET amount = 0'), 'ERR:42501|same');
END $$;

-- ── R3B-05: a plan is never linked to a purchase the caller does not read ─────────────────────
DO $$
DECLARE
    v_hidden text;
    v_nothing text;
    v_elsewhere text;
BEGIN
    v_hidden := pg_temp.write(pg_temp.u(6), format(
        'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, original_transaction_id) '
        'VALUES (%L, %L, %L, 200, 4, 50, 0, %L)', pg_temp.p(20), pg_temp.h(1), 'pl20 WA', pg_temp.t(3)));
    v_nothing := pg_temp.write(pg_temp.u(6), format(
        'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, original_transaction_id) '
        'VALUES (%L, %L, %L, 200, 4, 50, 0, %L)', pg_temp.p(21), pg_temp.h(1), 'pl21 WA', pg_temp.t(99)));
    v_elsewhere := pg_temp.write(pg_temp.u(6), format(
        'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, original_transaction_id) '
        'VALUES (%L, %L, %L, 200, 4, 50, 0, %L)', pg_temp.p(22), pg_temp.h(1), 'pl22 WA', pg_temp.t(11)));
    PERFORM pg_temp.check('wife-admin links a new plan to W''s purchase', left(v_hidden, 9), 'ERR:42501');
    PERFORM pg_temp.check('the same refusal as an id of nothing', v_nothing, v_hidden);
    PERFORM pg_temp.check('the same refusal as another household''s purchase', v_elsewhere, v_hidden);
    PERFORM pg_temp.check('no plan was made', (SELECT count(*)::text FROM public.installment_plans WHERE id IN (pg_temp.p(20), pg_temp.p(21), pg_temp.p(22))), '0');

    -- Linking a plan she reads again: the same refusals.
    PERFORM pg_temp.check('co-wife adds an unlinked plan',
        pg_temp.write(pg_temp.u(3), format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments) '
            'VALUES (%L, %L, %L, 100, 2, 50, 0)', pg_temp.p(23), pg_temp.h(1), 'pl23 W2')), '1');
    PERFORM pg_temp.check('co-wife links it to W''s purchase',
        pg_temp.write(pg_temp.u(3), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(3), pg_temp.p(23))), v_hidden);
    PERFORM pg_temp.check('co-wife links it to an id of nothing',
        pg_temp.write(pg_temp.u(3), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(98), pg_temp.p(23))), v_hidden);
    PERFORM pg_temp.check('co-wife links it to another household''s purchase',
        pg_temp.write(pg_temp.u(3), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(11), pg_temp.p(23))), v_hidden);
    PERFORM pg_temp.check('co-wife links it to her own purchase',
        pg_temp.write(pg_temp.u(3), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(5), pg_temp.p(23))), '1');
    PERFORM pg_temp.check('then hers', (SELECT (personal_owner_id = pg_temp.u(3))::text FROM public.installment_plans WHERE id = pg_temp.p(23)), 'true');
    -- Who reads her purchase links to it.
    PERFORM pg_temp.check('the husband links a plan to W''s purchase',
        pg_temp.write(pg_temp.u(1), format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, original_transaction_id) '
            'VALUES (%L, %L, %L, 200, 4, 50, 0, %L)', pg_temp.p(24), pg_temp.h(1), 'pl24 H', pg_temp.t(3))), '1');
    -- The server never links a plan to another household's purchase either.
    PERFORM pg_temp.check('the service role links a plan to another household''s purchase',
        left(pg_temp.write(NULL, format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, original_transaction_id) '
            'VALUES (%L, %L, %L, 200, 4, 50, 0, %L)', pg_temp.p(25), pg_temp.h(1), 'pl25 svc', pg_temp.t(11))), 9), 'ERR:P0002');
    PERFORM pg_temp.check('the service role links one again to another household''s purchase',
        left(pg_temp.write(NULL, format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(11), pg_temp.p(3))), 9), 'ERR:P0002');
    DELETE FROM public.installment_plans WHERE id IN (pg_temp.p(23), pg_temp.p(24));
END $$;

-- ── R3B-04: the receipt helper is no path oracle ──────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('wife-admin: her photo', pg_temp.hidden(6, 't67_w.jpg'), 'true');
    PERFORM pg_temp.check('wife-admin: a path of nothing, the same answer', pg_temp.hidden(6, 't67_nope.jpg'), pg_temp.hidden(6, 't67_w.jpg'));
    PERFORM pg_temp.check('member: a path of nothing, the same answer', pg_temp.hidden(4, 't67_nope.jpg'), pg_temp.hidden(4, 't67_w.jpg'));
    PERFORM pg_temp.check('co-wife: a path of nothing, the same answer', pg_temp.hidden(3, 't67_nope.jpg'), pg_temp.hidden(3, 't67_w.jpg'));
    -- Not a member of the folder's household: the same answer for both, checked before anything.
    PERFORM pg_temp.check('another household''s member: her photo', pg_temp.hidden(10, 't67_w.jpg'), 'true');
    PERFORM pg_temp.check('another household''s member: a path of nothing', pg_temp.hidden(10, 't67_nope.jpg'), 'true');
    PERFORM pg_temp.check('another household''s member: an ordinary photo', pg_temp.hidden(10, 't67_o.jpg'), 'true');
    -- Who reads it: never hidden.
    PERFORM pg_temp.check('the husband: her photo', pg_temp.hidden(1, 't67_w.jpg'), 'false');
    PERFORM pg_temp.check('the husband: a path of nothing', pg_temp.hidden(1, 't67_nope.jpg'), 'false');
    PERFORM pg_temp.check('the wife: her photo', pg_temp.hidden(2, 't67_w.jpg'), 'false');
    PERFORM pg_temp.check('wife-admin: the ordinary photo', pg_temp.hidden(6, 't67_o.jpg'), 'false');
    -- The listing, as before.
    PERFORM pg_temp.check('wife-admin lists the folder',
        pg_temp.call(pg_temp.u(6), format('SELECT string_agg(name, '','' ORDER BY name) FROM storage.objects WHERE bucket_id = %L', 'receipts')),
        pg_temp.h(1)::text || '/t67_o.jpg');
    PERFORM pg_temp.check('the husband lists the folder',
        pg_temp.call(pg_temp.u(1), format('SELECT count(*)::text FROM storage.objects WHERE bucket_id = %L', 'receipts')), '2');
END $$;

-- ── R3B-03: the plans read test looks nothing up per plan ─────────────────────────────────────
DO $$
DECLARE
    v_plan text := '';
    v_line text;
BEGIN
    PERFORM pg_temp.check('the plans read test names no transactions',
        (SELECT (qual NOT LIKE '%transactions%')::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'installment_plans'), 'true');
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.u(3))::text, true);
    SET LOCAL ROLE authenticated;
    FOR v_line IN EXECUTE format('EXPLAIN (COSTS OFF) SELECT * FROM public.installment_plans WHERE household_id = %L AND status = %L',
                                 pg_temp.h(1), 'ACTIVE') LOOP
        v_plan := v_plan || ' ' || v_line;
    END LOOP;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM pg_temp.check('the plan list reads no transactions', (v_plan NOT LIKE '%transactions%')::text, 'true');
END $$;

-- ── R3B-02: the transfer rows of a repayment ──────────────────────────────────────────────────
DO $$
DECLARE
    v_res text;
BEGIN
    -- The husband repays W from his bank and from the pool, and reverses the pool's.
    v_res := pg_temp.repay(1, 2, '70', 4, 1);
    PERFORM pg_temp.keep('rA', pg_temp.j(v_res, 'reimbursement_id'));
    v_res := pg_temp.repay(1, 2, '30', 1, 2);
    PERFORM pg_temp.keep('rB', pg_temp.j(v_res, 'reimbursement_id'));
    v_res := pg_temp.rev(1, pg_temp.id('rB'), 3);
    PERFORM pg_temp.keep('rC', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('setup: three ledger rows', (SELECT count(*)::text FROM public.spouse_reimbursements WHERE id IN (pg_temp.id('rA'), pg_temp.id('rB'), pg_temp.id('rC'))), '3');
    -- Ordinary transfers: W to K, K to the pool.
    PERFORM pg_temp.call(pg_temp.u(2), format('SELECT public.transfer_between_accounts(%L, %L, %L, 50, 0, %L)::text', pg_temp.h(1), pg_temp.a(2), pg_temp.a(3), 'W to K'));
    PERFORM pg_temp.call(pg_temp.u(4), format('SELECT public.transfer_between_accounts(%L, %L, %L, 20, 0, %L)::text', pg_temp.h(1), pg_temp.a(3), pg_temp.a(1), 'K to pool'));
    PERFORM pg_temp.keep('xWK', (SELECT id::text FROM public.account_transfers WHERE from_account_id = pg_temp.a(2) AND to_account_id = pg_temp.a(3)));
    PERFORM pg_temp.keep('xKP', (SELECT id::text FROM public.account_transfers WHERE from_account_id = pg_temp.a(3) AND to_account_id = pg_temp.a(1)));

    -- Husband present: she and he (her ledger's manager, and the owner of his bank) read them.
    PERFORM pg_temp.check('present: the repayment from his bank', pg_temp.readers('account_transfers', pg_temp.xfer('rA')), 'H,W');
    PERFORM pg_temp.check('present: the repayment from the pool', pg_temp.readers('account_transfers', pg_temp.xfer('rB')), 'H,W');
    PERFORM pg_temp.check('present: the pool''s reversal', pg_temp.readers('account_transfers', pg_temp.xfer('rC')), 'H,W');
    PERFORM pg_temp.check('present: a member finds them by purpose',
        pg_temp.call(pg_temp.u(4), 'SELECT count(*)::text FROM public.account_transfers WHERE purpose IS NOT NULL'), '0');
    PERFORM pg_temp.check('present: a wife-admin sums the pool''s lines',
        pg_temp.call(pg_temp.u(6), format('SELECT COALESCE(sum(amount), 0)::text FROM public.account_transfers WHERE from_account_id = %L OR to_account_id = %L', pg_temp.a(1), pg_temp.a(1))),
        '20.00');
    -- Ordinary transfers as before.
    PERFORM pg_temp.check('present: W to K', pg_temp.readers('account_transfers', pg_temp.id('xWK')), 'H,W,K,C');
    PERFORM pg_temp.check('present: K to the pool', pg_temp.readers('account_transfers', pg_temp.id('xKP')), 'H,W,W2,K,C,WA,W5');
    -- The pool's balance is still read by every member.
    PERFORM pg_temp.check('present: the pool''s balance for a member',
        pg_temp.call(pg_temp.u(4), format('SELECT balance::text FROM public.accounts WHERE id = %L', pg_temp.a(1))), '4920.00');

    -- Replaced by K: the new husband and she; H keeps his own bank's row, and nothing of her ledger.
    PERFORM pg_temp.provider(4);
    PERFORM pg_temp.check('replaced: the repayment from his bank', pg_temp.readers('account_transfers', pg_temp.xfer('rA')), 'H,W,K');
    PERFORM pg_temp.check('replaced: the repayment from the pool', pg_temp.readers('account_transfers', pg_temp.xfer('rB')), 'W,K');
    PERFORM pg_temp.check('replaced: the pool''s reversal', pg_temp.readers('account_transfers', pg_temp.xfer('rC')), 'W,K');
    PERFORM pg_temp.check('replaced: H reads none of her ledger',
        pg_temp.call(pg_temp.u(1), 'SELECT count(*)::text FROM public.spouse_reimbursements'), '0');
    -- Husband gone: the admins who are not wives.
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('gone: the repayment from his bank', pg_temp.readers('account_transfers', pg_temp.xfer('rA')), 'H,W,C');
    PERFORM pg_temp.check('gone: the repayment from the pool', pg_temp.readers('account_transfers', pg_temp.xfer('rB')), 'H,W,C');
    PERFORM pg_temp.provider(1);
END $$;

-- ── R3B-06: a personal repayment is reversed by its owner only while he manages her ledger ─────
DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.repay(1, 2, '10', 4, 10);
    PERFORM pg_temp.keep('rD', pg_temp.j(v_res, 'reimbursement_id'));
    -- Replaced husband: not even his own.
    PERFORM pg_temp.provider(4);
    PERFORM pg_temp.check('replaced: H reverses his own repayment', pg_temp.rev(1, pg_temp.id('rD'), 11), 'ERR:forbidden');
    PERFORM pg_temp.check('replaced: nor the new husband (not his account)', pg_temp.rev(4, pg_temp.id('rD'), 12), 'ERR:account_forbidden');
    PERFORM pg_temp.check('replaced: his bank unchanged', pg_temp.bal(4), '2920.00');
    PERFORM pg_temp.provider(1);
    -- The husband himself, as before.
    PERFORM pg_temp.check('present: H reverses his own repayment', pg_temp.j(pg_temp.rev(1, pg_temp.id('rD'), 13), 'kind'), 'reversal');
    PERFORM pg_temp.check('present: his bank credited back', pg_temp.bal(4), '2930.00');

    -- Demoted admin: C repaid while the husband was gone.
    PERFORM pg_temp.provider(0);
    v_res := pg_temp.repay(5, 2, '15', 6, 20);
    PERFORM pg_temp.keep('rE', pg_temp.j(v_res, 'reimbursement_id'));
    PERFORM pg_temp.check('gone: C repaid', pg_temp.bal(6), '1985.00');
    PERFORM pg_temp.provider(1);
    PERFORM pg_temp.check('husband back: C reverses his own', pg_temp.rev(5, pg_temp.id('rE'), 21), 'ERR:forbidden');
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.role(5, 'member');
    PERFORM pg_temp.check('gone, C a member: C reverses his own', pg_temp.rev(5, pg_temp.id('rE'), 22), 'ERR:forbidden');
    PERFORM pg_temp.check('C''s bank unchanged', pg_temp.bal(6), '1985.00');
    PERFORM pg_temp.role(5, 'admin');
    PERFORM pg_temp.check('gone, C an admin: C reverses his own', pg_temp.j(pg_temp.rev(5, pg_temp.id('rE'), 23), 'kind'), 'reversal');
    PERFORM pg_temp.check('C''s bank credited back', pg_temp.bal(6), '2000.00');
    PERFORM pg_temp.provider(1);
    -- A pool's repayment, as before: the husband who is an admin.
    v_res := pg_temp.repay(1, 2, '5', 1, 30);
    PERFORM pg_temp.check('present: H reverses a pool repayment', pg_temp.j(pg_temp.rev(1, pg_temp.j(v_res, 'reimbursement_id')::uuid, 31), 'kind'), 'reversal');
    -- Never a wife, never a member.
    PERFORM pg_temp.check('a wife-admin reverses', pg_temp.rev(6, pg_temp.id('rA'), 32), 'ERR:forbidden');
    PERFORM pg_temp.check('a member reverses', pg_temp.rev(4, pg_temp.id('rA'), 33), 'ERR:forbidden');
END $$;

-- ── Item 4: a deleted wife's personal plans stay hidden ───────────────────────────────────────
DO $$
DECLARE
    v_sess text;
    v_req uuid;
    v_res text;
BEGIN
    PERFORM pg_temp.check('before: her linked plan', pg_temp.readers('installment_plans', pg_temp.p(4)), 'H,C,W5');
    PERFORM pg_temp.check('before: her plan whose purchase was deleted', pg_temp.readers('installment_plans', pg_temp.p(5)), 'H,C,W5');

    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(7), now()) RETURNING id::text INTO v_sess;
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.u(7), 'session_id', v_sess)::text, true);
    SET LOCAL ROLE authenticated;
    PERFORM public.request_account_deletion('DELETE', '[]'::jsonb, NULL, 'en');
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT id INTO v_req FROM public.account_deletion_requests WHERE user_id = pg_temp.u(7) AND status = 'scheduled';
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_req;
    v_res := pg_temp.call(NULL, 'SELECT count(*)::text FROM public.claim_due_account_deletions(50, 30)', 'service_role');
    v_res := pg_temp.call(NULL, format('SELECT (public.prepare_account_purge(%L) ->> %L)', v_req, 'deferred'), 'service_role');
    PERFORM pg_temp.check('the purge is prepared', v_res, 'false');
    DELETE FROM pg_temp.people WHERE n = 7;
    -- Prepared (she is no member any more): still only her husband and the admins who are not wives.
    PERFORM pg_temp.check('prepared: her linked plan', pg_temp.readers('installment_plans', pg_temp.p(4)), 'H,C');
    PERFORM pg_temp.check('prepared: her other plan', pg_temp.readers('installment_plans', pg_temp.p(5)), 'H,C');
    PERFORM pg_temp.check('prepared: her id on no plan',
        (SELECT count(*)::text FROM public.installment_plans p WHERE p::text LIKE '%' || pg_temp.u(7)::text || '%'), '0');
    PERFORM pg_temp.call(NULL, format('SELECT public.mark_account_purge_storage_done(%L)::text', v_req), 'service_role');
    DELETE FROM auth.users WHERE id = pg_temp.u(7);
    v_res := pg_temp.call(NULL, format('SELECT public.complete_account_purge(%L)::text', v_req), 'service_role');
    PERFORM pg_temp.check('the purge completes', (left(v_res, 4) <> 'ERR:')::text, 'true');

    PERFORM pg_temp.check('purged: her linked plan', pg_temp.readers('installment_plans', pg_temp.p(4)), 'H,C');
    PERFORM pg_temp.check('purged: her other plan', pg_temp.readers('installment_plans', pg_temp.p(5)), 'H,C');
    PERFORM pg_temp.check('purged: a member finds them by shop',
        pg_temp.call(pg_temp.u(4), 'SELECT count(*)::text FROM public.installment_plans WHERE merchant LIKE ''%W5%'''), '0');
    PERFORM pg_temp.check('purged: a wife-admin sums them',
        pg_temp.call(pg_temp.u(6), format('SELECT COALESCE(sum(total_amount), 0)::text FROM public.installment_plans WHERE id IN (%L, %L)', pg_temp.p(4), pg_temp.p(5))), '0');
    -- Nothing of hers on them, nor anywhere in public.
    PERFORM pg_temp.check('purged: her id on no plan',
        (SELECT count(*)::text FROM public.installment_plans p WHERE p::text LIKE '%' || pg_temp.u(7)::text || '%'), '0');
    PERFORM pg_temp.check('purged: her id nowhere', pg_temp.scan(pg_temp.u(7)::text), '');
    PERFORM pg_temp.check('purged: her address nowhere', pg_temp.scan('t67-7@test.local'), '');
    PERFORM pg_temp.check('purged: her name nowhere', pg_temp.scan('T67 User 7'), '');
    -- Husband gone, or replaced: the readers follow the rule (the admins who are not wives, the husband).
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('purged, husband gone', pg_temp.readers('installment_plans', pg_temp.p(5)), 'H,C');
    PERFORM pg_temp.provider(4);
    PERFORM pg_temp.check('purged, a new husband', pg_temp.readers('installment_plans', pg_temp.p(5)), 'H,K,C');
    PERFORM pg_temp.provider(1);
    -- Nobody unhides it: a client cannot touch the mark.
    PERFORM pg_temp.check('no client writes the mark',
        pg_temp.call(NULL, 'SELECT (has_column_privilege(''authenticated'', ''public.installment_plans'', ''former_member_personal'', ''UPDATE'') '
                           'OR has_column_privilege(''anon'', ''public.installment_plans'', ''former_member_personal'', ''UPDATE''))::text', 'postgres'),
        'false');
    PERFORM pg_temp.check('a client''s new plan is never marked',
        pg_temp.write(pg_temp.u(4), format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, former_member_personal) '
            'VALUES (%L, %L, %L, 100, 2, 50, 0, true)', pg_temp.p(26), pg_temp.h(1), 'pl26 K')), '1');
    PERFORM pg_temp.check('read by everyone', pg_temp.readers('installment_plans', pg_temp.p(26)), 'H,W,W2,K,C,WA');
    -- Linked to an ordinary purchase again, it follows that purchase (the husband relinks it).
    PERFORM pg_temp.check('the husband links her old plan to an ordinary purchase',
        pg_temp.write(pg_temp.u(1), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(1), pg_temp.p(5))), '1');
    PERFORM pg_temp.check('then everyone''s', pg_temp.readers('installment_plans', pg_temp.p(5)), 'H,W,W2,K,C,WA');
END $$;

-- ── R3B-02 and R3B-06 on a former member's record ─────────────────────────────────────────────
DO $$
DECLARE
    v_res text;
BEGIN
    PERFORM pg_temp.check('her record', (SELECT original_amount::text || '/' || status FROM public.former_member_debts WHERE household_id = pg_temp.h(1)), '100.00/open');
    v_res := pg_temp.fpay(1, '20', 4, 40);
    PERFORM pg_temp.keep('f1', pg_temp.j(v_res, 'event_id'));
    v_res := pg_temp.fpay(1, '10', 1, 41);
    PERFORM pg_temp.keep('f2', pg_temp.j(v_res, 'event_id'));
    PERFORM pg_temp.check('present: the payment from his bank', pg_temp.readers('account_transfers', pg_temp.xfer('f1')), 'H');
    PERFORM pg_temp.check('present: the payment from the pool', pg_temp.readers('account_transfers', pg_temp.xfer('f2')), 'H');
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('gone: the payment from his bank', pg_temp.readers('account_transfers', pg_temp.xfer('f1')), 'H,C');
    PERFORM pg_temp.check('gone: the payment from the pool', pg_temp.readers('account_transfers', pg_temp.xfer('f2')), 'H,C');
    PERFORM pg_temp.provider(4);
    PERFORM pg_temp.check('replaced: the payment from his bank', pg_temp.readers('account_transfers', pg_temp.xfer('f1')), 'H,K');
    PERFORM pg_temp.check('replaced: the payment from the pool', pg_temp.readers('account_transfers', pg_temp.xfer('f2')), 'K');
    -- Replaced: he no longer reverses his own payment.
    PERFORM pg_temp.check('replaced: H reverses his own payment of the record', pg_temp.frev(1, pg_temp.id('f1'), 42), 'ERR:forbidden');
    PERFORM pg_temp.provider(1);
    PERFORM pg_temp.check('present: H reverses it', pg_temp.j(pg_temp.frev(1, pg_temp.id('f1'), 43), 'success'), 'true');
    PERFORM pg_temp.keep('f3', pg_temp.j(pg_temp.frev(1, pg_temp.id('f1'), 43), 'event_id'));
    PERFORM pg_temp.check('present: the reversal''s row', pg_temp.readers('account_transfers', pg_temp.xfer('f3')), 'H');
END $$;

-- ── Every repayment still debits an app account and credits none of hers ──────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('her accounts were never credited by a repayment',
        (SELECT count(*)::text FROM public.account_transfers t WHERE t.purpose IS NOT NULL
         AND (t.to_account_id = pg_temp.a(2) OR t.from_account_id = pg_temp.a(2))), '0');
    PERFORM pg_temp.check('the budgets never moved for a repayment',
        (SELECT string_agg(category_code || '=' || spent_amount, ',' ORDER BY category_code) FROM public.budgets WHERE household_id = pg_temp.h(1)),
        'OPEX-GROCERY=590.00,OPEX-SHOPPING=0.00');
END $$;

-- ── R3B-08: the system's own cascade is no client edit ─────────────────────────────────────────
-- An admin who is not a wife removes the co-wife while the husband is there: her leaving makes her
-- advances household expenses (the membership trigger), which the advance guard lets through.
DO $$
BEGIN
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, notes)
    VALUES (pg_temp.t(13), pg_temp.h(1), pg_temp.u(3), 25, 'T67 Bread W2', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me',
            'wife_reimbursable', pg_temp.u(3), 'n');
    PERFORM pg_temp.check('the admin removes the co-wife',
        (left(pg_temp.call(pg_temp.u(5), format('SELECT public.remove_member(%L)::text', pg_temp.u(3))), 4) <> 'ERR:')::text, 'true');
    PERFORM pg_temp.check('her advance is the household''s now',
        (SELECT (nafaqah_class IS NULL AND nafaqah_spouse_id IS NULL)::text FROM public.transactions WHERE id = pg_temp.t(13)), 'true');
END $$;

-- ── The rules stated where they live ──────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('the transactions update policy reads as the read policy',
        (SELECT (qual LIKE '%wife_personal%' AND qual LIKE '%nafaqah_caller_sees_allowances%'
                 AND with_check LIKE '%wife_personal%' AND with_check LIKE '%nafaqah_caller_sees_allowances%')::text
         FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transactions' AND policyname = 'transactions_update_household'), 'true');
    PERFORM pg_temp.check('the transactions delete policy reads as the read policy',
        (SELECT (qual LIKE '%wife_personal%' AND qual LIKE '%nafaqah_caller_sees_allowances%')::text
         FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transactions' AND policyname = 'transactions_delete_household'), 'true');
    PERFORM pg_temp.check('the receipts delete policy hides her photo',
        (SELECT (qual LIKE '%nafaqah_receipt_hidden(name)%')::text FROM pg_policies
         WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'receipts_delete_household'), 'true');
    PERFORM pg_temp.check('the transfers policy names the repayments'' readers',
        (SELECT (qual LIKE '%purpose%' AND qual LIKE '%nafaqah_caller_manages_ledgers%')::text FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'account_transfers'), 'true');
    PERFORM pg_temp.check('the plans insert check reads the purchase',
        (SELECT (with_check LIKE '%t.id = installment_plans.original_transaction_id%')::text FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'installment_plans'), 'true');
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
    RAISE NOTICE 'PASSED: R3B write paths, repayment transfers, reversals, a deleted wife''s plans and receipts.';
END $$;

ROLLBACK;
