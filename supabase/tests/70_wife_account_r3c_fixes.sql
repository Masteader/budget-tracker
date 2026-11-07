-- ============================================================================
-- Test 70: The wife account, review R3C (owner decisions 2026-11-07)
--
-- Migration: 20261105001300_wife_repayment_debit.sql, sections 7, 8, 10d and 12
-- Rules: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 2;
--        .agents/rules/04-security-and-privacy.md, Family Nafaqah
--
--   R3C-01  Only someone who may see a wife account (her, its owner, her ledger's managers) updates
--           or deletes a transaction recorded on it. A co-wife admin, an ordinary member, and an
--           admin who is not a wife while the husband is there reach none of those rows: the same
--           answer as for a row they do not read (0 rows), also by a statement that names no row,
--           and her account's balance does not move. The auditor's cases: her 70 SAR advance, 540
--           -> 535 -> 610 by the co-wife admin, and 180 -> -20 by the admin while the husband is
--           there. The balance trigger's own gate refuses the same callers on a path that bypasses
--           the policies (a SECURITY DEFINER function running under their JWT).
-- Every client write is as the client makes it (RLS, as PostgREST applies it). Rolled back.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e7000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e70a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e70b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e70c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.k(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e70d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.t(int), pg_temp.k(int) TO PUBLIC;

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

-- One call as user p_sub (the client, through RLS): the value, or ERR:<hint or SQLSTATE>.
CREATE FUNCTION pg_temp.call(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_val text;
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql INTO v_val;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || CASE WHEN COALESCE(v_hint, '') <> '' THEN v_hint ELSE SQLSTATE END;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
-- A client write as user p_sub: the rows it changed, or ERR:<SQLSTATE>.
CREATE FUNCTION pg_temp.write(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
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
-- The same statement run by a function that bypasses RLS (as a SECURITY DEFINER RPC does) under
-- p_sub's JWT: only the triggers judge it. The rows it changed, or ERR:<SQLSTATE>.
CREATE FUNCTION pg_temp.definer(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_n bigint;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE;
    END;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v_n::text;
END;
$$;
-- A call's whole refusal (SQLSTATE, message and hint), to compare two refusals.
CREATE FUNCTION pg_temp.refusal(p_sub uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_hint text;
BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', p_sub)::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
        RESET ROLE;
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN SQLSTATE || ':' || SQLERRM || ':' || COALESCE(v_hint, '');
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN 'accepted';
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text), pg_temp.write(uuid, text), pg_temp.refusal(uuid, text) TO PUBLIC;

CREATE FUNCTION pg_temp.j(p_res text, p_field text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    IF p_res IS NULL OR p_res LIKE 'ERR:%' THEN RETURN p_res; END IF;
    RETURN p_res::jsonb ->> p_field;
END;
$$;
CREATE FUNCTION pg_temp.wbal() RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.id('WA1') $$;
CREATE FUNCTION pg_temp.bal(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT balance::text FROM public.accounts WHERE id = pg_temp.a(p_n) $$;
CREATE FUNCTION pg_temp.amt(p_n int) RETURNS text LANGUAGE sql
AS $$ SELECT COALESCE((SELECT amount::text FROM public.transactions WHERE id = pg_temp.t(p_n)), 'gone') $$;
CREATE FUNCTION pg_temp.provider(p_user int) RETURNS void LANGUAGE sql AS $$
    UPDATE public.households SET nafaqah_provider_user_id = CASE WHEN p_user = 0 THEN NULL ELSE pg_temp.u(p_user) END
    WHERE id = pg_temp.h(1);
$$;
-- A client edit of one transaction's amount, and a client delete of it.
CREATE FUNCTION pg_temp.edit_sql(p_tx int, p_amount numeric) RETURNS text LANGUAGE sql
AS $$ SELECT format('UPDATE public.transactions SET amount = %s WHERE id = %L', p_amount, pg_temp.t(p_tx)) $$;
CREATE FUNCTION pg_temp.del_sql(p_tx int) RETURNS text LANGUAGE sql
AS $$ SELECT format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(p_tx)) $$;
CREATE FUNCTION pg_temp.edit(p_actor int, p_tx int, p_amount numeric) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.write(pg_temp.u(p_actor), pg_temp.edit_sql(p_tx, p_amount)) $$;
CREATE FUNCTION pg_temp.del(p_actor int, p_tx int) RETURNS text LANGUAGE sql
AS $$ SELECT pg_temp.write(pg_temp.u(p_actor), pg_temp.del_sql(p_tx)) $$;
-- A client write tried and undone: the rows it changed and WA1's balance right after it; then
-- everything it did is rolled back, so each try starts from the same state.
CREATE FUNCTION pg_temp.attempt(p_actor int, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_res text;
BEGIN
    BEGIN
        v_res := pg_temp.write(pg_temp.u(p_actor), p_sql) || '|' || pg_temp.wbal();
        RAISE EXCEPTION 'undo' USING ERRCODE = 'T7000';
    EXCEPTION WHEN SQLSTATE 'T7000' THEN
        NULL;
    END;
    RETURN v_res;
END;
$$;
-- The wife account's balance against its ledger: opening 0 + transfers in - transfers out - spending.
CREATE FUNCTION pg_temp.ledger_equal() RETURNS text LANGUAGE sql AS $$
    SELECT (a.balance = COALESCE((SELECT sum(x.amount) FROM public.account_transfers x WHERE x.to_account_id = a.id), 0)
                       - COALESCE((SELECT sum(x.amount + x.fee) FROM public.account_transfers x WHERE x.from_account_id = a.id), 0)
                       - COALESCE((SELECT sum(t.amount) FROM public.transactions t WHERE t.account_id = a.id), 0))::text
    FROM public.accounts a WHERE a.id = pg_temp.id('WA1');
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin, provider and primary admin; wife W(2); co-wife W2(3); member K(4);
--        admin C(5) who is not a wife; wife WA(6) who is an admin.
-- Accounts: H's bank a(1) 10000; W's bank a(2) 1000; C's bank a(3) 1000; K's bank a(4) 500.
-- WA1: W's wife account, made by H, funded 620 by H. On it, by W: her advance t(11) 70 (the
-- auditor's), her personal purchase t(12) 50; two repayments of 20 into it. WA1 = 620-70-50+40 = 540,
-- as in the auditor's reproduction.
-- Elsewhere: her advance t(13) 40 and her personal purchase t(14) 30 on her own bank; C's own
-- expense t(15) 25 on his bank; K's own expense t(16) 15 on his bank.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't70-' || n || '@test.local', jsonb_build_object('display_name', 'T70 User ' || n)
    FROM generate_series(1, 6) AS n;
    INSERT INTO public.households (id, name, invite_code, household_type, payday_day)
    VALUES (pg_temp.h(1), 'T70 H1', 'T70CODE000000001', 'family', 27);
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default) VALUES
        (pg_temp.h(1), pg_temp.u(1), 'admin', 'provider', true),
        (pg_temp.h(1), pg_temp.u(2), 'member', 'spouse', true),
        (pg_temp.h(1), pg_temp.u(3), 'member', 'spouse', true),
        (pg_temp.h(1), pg_temp.u(4), 'member', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(5), 'admin', 'family_member', true),
        (pg_temp.h(1), pg_temp.u(6), 'admin', 'spouse', true);
    UPDATE public.users u SET household_id = m.household_id, role = m.role, financial_role = m.financial_role
    FROM public.household_memberships m WHERE m.user_id = u.id AND m.household_id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T70 H bank', 'bank', 10000, false, false, 'SAR'),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(2), 'T70 W bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(3), pg_temp.h(1), pg_temp.u(5), 'T70 C bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(4), pg_temp.h(1), pg_temp.u(4), 'T70 K bank', 'bank', 500, false, false, 'SAR');
END $$;

DO $$
DECLARE
    v_res text;
BEGIN
    v_res := pg_temp.call(pg_temp.u(1), format('SELECT public.create_wife_account(%L, %L, %L, NULL)::text', pg_temp.h(1), pg_temp.u(2), 'T70 her card'));
    PERFORM pg_temp.keep('WA1', pg_temp.j(v_res, 'id'));
    PERFORM pg_temp.check('fixture: H funds WA1', pg_temp.call(pg_temp.u(1), format(
        'SELECT (public.transfer_between_accounts(%L, %L, %L, 620, 0, %L) ->> %L)', pg_temp.h(1), pg_temp.a(1), pg_temp.id('WA1'), 'fund', 'notes')), 'fund');
    -- Her purchases, as the app inserts them.
    PERFORM pg_temp.check('fixture: her purchases', pg_temp.write(pg_temp.u(2), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, '
        'nafaqah_class, nafaqah_spouse_id, account_id) VALUES '
        '(%L, %L, %L, 70, %L, %L, %L, %L, %L, %L, %L, %L), (%L, %L, %L, 50, %L, %L, %L, %L, %L, %L, %L, %L), '
        '(%L, %L, %L, 40, %L, %L, %L, %L, %L, %L, %L, %L), (%L, %L, %L, 30, %L, %L, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(11), pg_temp.h(1), pg_temp.u(2), 'T70 advance', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(2), pg_temp.id('WA1'),
        pg_temp.t(12), pg_temp.h(1), pg_temp.u(2), 'T70 personal', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), pg_temp.id('WA1'),
        pg_temp.t(13), pg_temp.h(1), pg_temp.u(2), 'T70 advance own', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(2), pg_temp.a(2),
        pg_temp.t(14), pg_temp.h(1), pg_temp.u(2), 'T70 personal own', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), pg_temp.a(2))), '4');
    PERFORM pg_temp.check('fixture: C''s expense', pg_temp.write(pg_temp.u(5), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, account_id) '
        'VALUES (%L, %L, %L, 25, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(15), pg_temp.h(1), pg_temp.u(5), 'T70 C', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', pg_temp.a(3))), '1');
    PERFORM pg_temp.check('fixture: K''s expense', pg_temp.write(pg_temp.u(4), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, account_id) '
        'VALUES (%L, %L, %L, 15, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(16), pg_temp.h(1), pg_temp.u(4), 'T70 K', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', pg_temp.a(4))), '1');
    -- Two repayments into it (H from his bank).
    FOR i IN 1..2 LOOP
        v_res := pg_temp.call(pg_temp.u(1), format(
            'SELECT public.record_spouse_reimbursement(%L, %L, 20, %L, NULL, NULL, %L::uuid, %L::uuid, %L::uuid)::text',
            pg_temp.h(1), pg_temp.u(2), 'bank_transfer', pg_temp.a(1), pg_temp.k(i), pg_temp.id('WA1')));
        PERFORM pg_temp.keep('R' || i, pg_temp.j(v_res, 'reimbursement_id'));
    END LOOP;
    -- Her pending request of 10 into it.
    v_res := pg_temp.call(pg_temp.u(2), format('SELECT public.request_spouse_reimbursement(%L, 10, %L, %L::uuid, NULL, %L::uuid)::text',
                                               pg_temp.h(1), 'cash', pg_temp.k(3), pg_temp.id('WA1')));
    PERFORM pg_temp.keep('Q1', pg_temp.j(v_res, 'request_id'));
    PERFORM pg_temp.check('fixture: WA1 holds 540', pg_temp.wbal(), '540.00');
    PERFORM pg_temp.check('fixture: two repayments and a request', (pg_temp.id('R1') IS NOT NULL AND pg_temp.id('R2') IS NOT NULL AND pg_temp.id('Q1') IS NOT NULL)::text, 'true');
    PERFORM pg_temp.check('fixture: her advance is read by everyone of F1', (
        SELECT string_agg(pg_temp.call(pg_temp.u(n), format('SELECT count(*)::text FROM public.transactions WHERE id = %L', pg_temp.t(11))), ',' ORDER BY n)
        FROM generate_series(1, 6) AS n), '1,1,1,1,1,1');
    PERFORM pg_temp.check('fixture: WA1 is read by H and W only', (
        SELECT string_agg(pg_temp.call(pg_temp.u(n), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.id('WA1'))), ',' ORDER BY n)
        FROM generate_series(1, 6) AS n), '1,1,0,0,0,0');
END $$;

-- ── R3C-01: who edits or deletes a row on her wife account ───────────────────────────────────
-- The auditor's cases first, each tried and undone (rows|WA1 after it): the co-wife admin WA
-- edited her 70 SAR advance to 75 (540 -> 535) and deleted it (-> 610); the admin C, with the
-- husband there, raised it to 270 when WA1 held 180 (-> -20). Now neither reaches it: 0 rows, as
-- for a row they do not read, and WA1 does not move.
DO $$
BEGIN
    PERFORM pg_temp.check('R3C-01 WA edits her advance on WA1 to 75 (was 1|535.00)', pg_temp.attempt(6, pg_temp.edit_sql(11, 75)), '0|540.00');
    PERFORM pg_temp.check('R3C-01 WA deletes her advance on WA1 (was 1|610.00)', pg_temp.attempt(6, pg_temp.del_sql(11)), '0|540.00');
    PERFORM pg_temp.check('R3C-01 W spends 360 from it', pg_temp.write(pg_temp.u(2), format(
        'INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, spent_by, '
        'nafaqah_class, nafaqah_spouse_id, account_id) VALUES (%L, %L, %L, 360, %L, %L, %L, %L, %L, %L, %L, %L)',
        pg_temp.t(17), pg_temp.h(1), pg_temp.u(2), 'T70 big', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me',
        'wife_personal', pg_temp.u(2), pg_temp.id('WA1'))) || '|' || pg_temp.wbal(), '1|180.00');
    PERFORM pg_temp.check('R3C-01 C (husband there) raises her advance on WA1 to 270 (was 1|-20.00)', pg_temp.attempt(5, pg_temp.edit_sql(11, 270)), '0|180.00');
    PERFORM pg_temp.check('R3C-01 she takes back her 360', pg_temp.del(2, 17) || '|' || pg_temp.wbal(), '1|540.00');
    PERFORM pg_temp.check('R3C-01 WA edits her advance on WA1', pg_temp.edit(6, 11, 75), '0');
    PERFORM pg_temp.check('R3C-01 WA deletes her advance on WA1', pg_temp.del(6, 11), '0');
    PERFORM pg_temp.check('R3C-01 C (husband there) raises her advance on WA1', pg_temp.edit(5, 11, 270), '0');
    PERFORM pg_temp.check('R3C-01 C (husband there) deletes her advance on WA1', pg_temp.del(5, 11), '0');
    PERFORM pg_temp.check('R3C-01 C (husband there) edits her personal purchase on WA1, which he reads', pg_temp.edit(5, 12, 5), '0');
    PERFORM pg_temp.check('R3C-01 C (husband there) deletes her personal purchase on WA1', pg_temp.del(5, 12), '0');
    PERFORM pg_temp.check('R3C-01 K edits her advance on WA1', pg_temp.edit(4, 11, 1), '0');
    PERFORM pg_temp.check('R3C-01 W2 deletes her advance on WA1', pg_temp.del(3, 11), '0');
    PERFORM pg_temp.check('R3C-01 nothing of it moved', pg_temp.wbal() || '|' || pg_temp.amt(11) || '|' || pg_temp.amt(12), '540.00|70.00|50.00');

    -- The answer for a row they do not read (her personal purchase on her own bank) is the same: 0.
    PERFORM pg_temp.check('R3C-01 WA edits a row she does not read: the same answer', pg_temp.edit(6, 14, 1), '0');
    PERFORM pg_temp.check('R3C-01 WA deletes a row she does not read: the same answer', pg_temp.del(6, 14), '0');

    -- Statements that name no row reach none of them either.
    PERFORM pg_temp.check('R3C-01 WA blind update: none of WA1''s rows', pg_temp.write(pg_temp.u(6), 'UPDATE public.transactions SET notes = ''blind'''), '3');
    PERFORM pg_temp.check('R3C-01 WA blind update left WA1''s rows', (SELECT count(*)::text FROM public.transactions WHERE account_id = pg_temp.id('WA1') AND notes = 'blind'), '0');
    PERFORM pg_temp.check('R3C-01 C blind amount update: WA1 does not move', pg_temp.write(pg_temp.u(5), 'UPDATE public.transactions SET amount = amount + 1 WHERE nafaqah_class IS NOT NULL') || '|' || pg_temp.wbal(), '2|540.00');

    -- The general admin right on other rows is unchanged: C edits her advance on her own bank.
    PERFORM pg_temp.check('R3C-01 C still edits her advance on her own bank (rule 04)', pg_temp.edit(5, 13, 40), '1');
    -- (the blind update above took her two rows on her own bank to 41 and 31)
    PERFORM pg_temp.check('R3C-01 and her bank follows', pg_temp.bal(2), (1000 - 40 - 31)::numeric(14, 2)::text);

    -- No one moves another row onto it (WITH CHECK, the spending guard): the answer for any
    -- account not theirs, word for word.
    PERFORM pg_temp.check('R3C-01 C moves his expense onto WA1: the refusal for K''s bank', pg_temp.refusal(pg_temp.u(5), format(
        'UPDATE public.transactions SET account_id = %L WHERE id = %L', pg_temp.id('WA1'), pg_temp.t(15))),
        pg_temp.refusal(pg_temp.u(5), format('UPDATE public.transactions SET account_id = %L WHERE id = %L', pg_temp.a(4), pg_temp.t(15))));

    -- Past the policies (an RPC running as its owner under the caller's JWT), the balance trigger
    -- refuses the same callers.
    PERFORM pg_temp.check('R3C-01 balance trigger: WA edits it past the policies', pg_temp.definer(pg_temp.u(6), format(
        'UPDATE public.transactions SET amount = 75 WHERE id = %L', pg_temp.t(11))), 'ERR:42501');
    PERFORM pg_temp.check('R3C-01 balance trigger: C (husband there) deletes it past the policies', pg_temp.definer(pg_temp.u(5), format(
        'DELETE FROM public.transactions WHERE id = %L', pg_temp.t(11))), 'ERR:42501');
    PERFORM pg_temp.check('R3C-01 balance trigger: C moves her purchase off WA1 past the policies', pg_temp.definer(pg_temp.u(5), format(
        'UPDATE public.transactions SET account_id = NULL WHERE id = %L', pg_temp.t(12))), 'ERR:42501');
    PERFORM pg_temp.check('R3C-01 still nothing moved', pg_temp.wbal() || '|' || pg_temp.amt(11) || '|' || pg_temp.amt(12), '540.00|70.00|50.00');
    PERFORM pg_temp.check('R3C-01 the helper: who may write a row of hers on WA1',
        (SELECT string_agg(public.transaction_personal_account_writable(a, pg_temp.u(2), pg_temp.u(n))::text, ',' ORDER BY n)
         FROM public.accounts a CROSS JOIN generate_series(1, 6) AS n WHERE a.id = pg_temp.id('WA1')),
        'true,true,false,false,false,false');
END $$;

-- Those who see it still edit and delete: she, the owner (her husband), and an admin who is not a
-- wife once the husband is gone; the wife-admin never.
DO $$
BEGIN
    PERFORM pg_temp.check('R3C-01 W edits her advance on WA1', pg_temp.edit(2, 11, 75) || '|' || pg_temp.wbal(), '1|535.00');
    PERFORM pg_temp.check('R3C-01 H (owner) edits it back', pg_temp.edit(1, 11, 70) || '|' || pg_temp.wbal(), '1|540.00');
    PERFORM pg_temp.provider(0);
    PERFORM pg_temp.check('R3C-01 husband gone: C edits her advance on WA1', pg_temp.edit(5, 11, 72) || '|' || pg_temp.wbal(), '1|538.00');
    PERFORM pg_temp.check('R3C-01 husband gone: WA still does not', pg_temp.edit(6, 11, 1) || '|' || pg_temp.wbal(), '0|538.00');
    PERFORM pg_temp.check('R3C-01 husband gone: K still does not', pg_temp.del(4, 11) || '|' || pg_temp.wbal(), '0|538.00');
    PERFORM pg_temp.check('R3C-01 husband gone: the helper', (SELECT string_agg(public.transaction_personal_account_writable(a, pg_temp.u(2), pg_temp.u(n))::text, ',' ORDER BY n)
         FROM public.accounts a CROSS JOIN generate_series(1, 6) AS n WHERE a.id = pg_temp.id('WA1')), 'true,true,false,false,true,false');
    PERFORM pg_temp.provider(1);
    PERFORM pg_temp.check('R3C-01 husband back: C no longer', pg_temp.edit(5, 11, 70) || '|' || pg_temp.wbal(), '0|538.00');
    PERFORM pg_temp.check('R3C-01 H deletes her personal purchase on WA1', pg_temp.del(1, 12) || '|' || pg_temp.wbal(), '1|588.00');
    PERFORM pg_temp.check('R3C-01 WA1 equals its ledger', pg_temp.ledger_equal(), 'true');
END $$;

DO $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(label || ' => got ' || COALESCE(got, 'NULL') || ', expected ' || COALESCE(want, 'NULL'), E'\n' ORDER BY n)
    INTO v_list FROM pg_temp.fails;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION E'Test 70 failed:\n%', v_list;
    END IF;
    RAISE NOTICE 'PASSED: R3C: only who sees her wife account edits or deletes its rows.';
END $$;

ROLLBACK;
