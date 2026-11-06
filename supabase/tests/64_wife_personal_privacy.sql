-- ============================================================================
-- Test 64: Who reads a wife's personal purchases (owner decision 2026-11-06)
--
-- Migration: 20261105001300_wife_repayment_debit.sql, section 10d (replaces the transactions read
--            policy of 20261020100000 and the receipts read policy of storage.objects)
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 3;
--       .agents/rules/04-security-and-privacy.md, Family Nafaqah and Receipt Storage Privacy
--
-- Her personal purchases (transactions with nafaqah_class = 'wife_personal') are read only by:
--   * the wife herself (her own);
--   * her husband: the household's Nafaqah provider while he is a current member who is not a wife;
--   * a household admin who is not a wife.
-- The same set that reads her allowance (test 63). A co-wife (even an admin) and an ordinary member
-- read none of those rows: no amount, merchant or note, no nafaqah_spouse_id link, no receipt photo,
-- and nothing summed from them (a per-cycle sum covers only the rows the caller reads). Every
-- other transaction (ordinary household expenses and her wife_reimbursable advances) stays
-- visible to every member, as before. A pool-paid personal purchase (a legacy row: the account
-- guard of 20261101000100 refuses new ones) leaves the pool's history for those who do not read it;
-- the pool's balance stays the same for everyone. Who creates, edits or voids her purchases is
-- unchanged (the write triggers); a caller who cannot read a row cannot pick it to edit it.
--
-- The matrix: the wife (her own, a co-wife's), the husband (an admin, and not an admin), a co-wife,
-- a wife who is an admin, an ordinary member, an admin who is not a wife; with the husband a
-- member, and gone (he left the household, which clears the provider). Every read is as the
-- client makes it (RLS, as PostgREST and Realtime apply it).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- One call as user p_sub: the value, or ERR:<SQLSTATE>:<message>.
CREATE FUNCTION pg_temp.call(p_sub uuid, p_sql text, p_role text DEFAULT 'authenticated')
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_val text;
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
        EXECUTE 'RESET ROLE';
        PERFORM set_config('request.jwt.claims', '', true);
        RETURN 'ERR:' || SQLSTATE || ':' || SQLERRM;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN COALESCE(v_val, 'ok');
END;
$$;
-- A write as user p_sub: the number of rows it changed, or ERR:<SQLSTATE>:<message>.
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
        RETURN 'ERR:' || SQLSTATE || ':' || SQLERRM;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RETURN v_n::text;
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.call(uuid, text, text), pg_temp.write(uuid, text) TO PUBLIC;

CREATE FUNCTION pg_temp.u(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e6400000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e64a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e64b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e64c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.t(int) TO PUBLIC;

CREATE FUNCTION pg_temp.join(p_user int, p_hh int, p_role text, p_fin text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role, is_default)
    VALUES (pg_temp.h(p_hh), pg_temp.u(p_user), p_role, p_fin, true);
    UPDATE public.users SET household_id = pg_temp.h(p_hh), role = p_role, financial_role = p_fin
    WHERE id = pg_temp.u(p_user);
END;
$$;

-- A transaction made by the server (no JWT subject): the triggers check the class as for the API.
CREATE FUNCTION pg_temp.tx(p_n int, p_hh int, p_user int, p_amount numeric, p_merchant text, p_cat text,
                           p_class text DEFAULT NULL, p_wife int DEFAULT NULL, p_account int DEFAULT NULL,
                           p_receipt text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, account_id, receipt_url, notes)
    VALUES (pg_temp.t(p_n), pg_temp.h(p_hh), pg_temp.u(p_user), p_amount, p_merchant, p_cat,
            '2026-11-05 10:00:00+03', 'manual', 'me', p_class,
            CASE WHEN p_wife IS NULL THEN NULL ELSE pg_temp.u(p_wife) END,
            CASE WHEN p_account IS NULL THEN NULL ELSE pg_temp.a(p_account) END, p_receipt,
            'T64 note of ' || p_merchant);
END;
$$;

CREATE TABLE pg_temp.fails (n serial PRIMARY KEY, label text, got text, want text);
CREATE FUNCTION pg_temp.check(p_label text, p_got text, p_want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_got IS DISTINCT FROM p_want THEN
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 240), p_want);
    END IF;
END;
$$;

-- What the caller reads of the transactions table, with a filter.
CREATE FUNCTION pg_temp.n(p_actor int, p_where text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), 'SELECT count(*)::text FROM public.transactions WHERE ' || p_where);
$$;
-- Her personal rows the caller reads (wife p_wife).
CREATE FUNCTION pg_temp.personal_of(p_actor int, p_wife int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.n(p_actor, format('nafaqah_class = %L AND nafaqah_spouse_id = %L', 'wife_personal', pg_temp.u(p_wife)));
$$;
-- The caller's sum of the cycle: what a client total over the cycle comes to.
CREATE FUNCTION pg_temp.cycle_sum(p_actor int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        'SELECT COALESCE(sum(amount), 0)::text FROM public.transactions WHERE cycle_key = ''2026-11''');
$$;
-- Receipt photos the caller reads in the receipts bucket, by path.
CREATE FUNCTION pg_temp.receipt(p_actor int, p_name text) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        format('SELECT count(*)::text FROM storage.objects WHERE bucket_id = %L AND name = %L', 'receipts', p_name));
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider; wife W(2); co-wife W2(3); member K(4); admin C(5) who is
--        not a wife; wife WA(6) who is an admin.
-- F2(2): husband H2(7) a member (not an admin) and provider; wife V(8); primary admin D(9) who is
--        not a wife; wife VA(10) who is an admin; member M(11).
-- Accounts: F1 pool P(1) (5000), W's personal account A(2) (1000); F2 pool P2(3) (3000).
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't64-' || n || '@test.local', jsonb_build_object('display_name', 'T64 User ' || n)
    FROM generate_series(1, 11) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T64 H1', 'T64CODE000000001', 'family', 27),
        (pg_temp.h(2), 'T64 H2', 'T64CODE000000002', 'family', 27);
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'member', 'family_member');
    PERFORM pg_temp.join(6, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(9, 2, 'admin', 'family_member');
    PERFORM pg_temp.join(7, 2, 'member', 'provider');
    PERFORM pg_temp.join(8, 2, 'member', 'spouse');
    PERFORM pg_temp.join(10, 2, 'admin', 'spouse');
    PERFORM pg_temp.join(11, 2, 'member', 'family_member');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(9), nafaqah_provider_user_id = pg_temp.u(7) WHERE id = pg_temp.h(2);

    INSERT INTO public.accounts (id, household_id, owner_user_id, name, account_type, balance, is_shared_pool, is_archived, currency) VALUES
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T64 pool', 'shared_pool', 5000, true, false, 'SAR'),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(2), 'T64 her bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(3), pg_temp.h(2), pg_temp.u(9), 'T64 pool 2', 'shared_pool', 3000, true, false, 'SAR');

    -- A shopping budget for the cycle, so the triggers show what they count.
    INSERT INTO public.budgets (household_id, category_code, cycle_key, month, allocated_amount, spent_amount, is_active)
    VALUES (pg_temp.h(1), 'OPEX-SHOPPING', '2026-11', '2026-11-01', 2000, 0, true);

    -- F1. Ordinary household expenses and her advance (visible to every member), and the wives'
    -- personal purchases.
    PERFORM pg_temp.tx(1, 1, 1, 100, 'T64 Panda', 'OPEX-GROCERY', NULL, NULL, 1);
    PERFORM pg_temp.tx(2, 1, 4, 50, 'T64 Bakery', 'OPEX-SHOPPING', NULL, NULL, NULL, pg_temp.h(1)::text || '/t64_o.jpg');
    PERFORM pg_temp.tx(3, 1, 2, 70, 'T64 Pharmacy', 'OPEX-GROCERY', 'wife_reimbursable', 2);
    PERFORM pg_temp.tx(4, 1, 2, 200, 'T64 Boutique W', 'OPEX-SHOPPING', 'wife_personal', 2, 2, pg_temp.h(1)::text || '/t64_w.jpg');
    PERFORM pg_temp.tx(5, 1, 3, 300, 'T64 Salon W2', 'OPEX-SHOPPING', 'wife_personal', 3, NULL,
        'https://x.supabase.co/storage/v1/object/sign/receipts/' || pg_temp.h(1)::text || '/t64_w2.jpg?token=abc');
    PERFORM pg_temp.tx(6, 1, 6, 400, 'T64 Perfume WA', 'OPEX-SHOPPING', 'wife_personal', 6);
    -- F2.
    PERFORM pg_temp.tx(11, 2, 9, 60, 'T64 Fuel', 'OPEX-FUEL', NULL, NULL, 3);
    PERFORM pg_temp.tx(12, 2, 8, 80, 'T64 Market', 'OPEX-GROCERY', 'wife_reimbursable', 8);
    PERFORM pg_temp.tx(13, 2, 8, 500, 'T64 Abaya V', 'OPEX-SHOPPING', 'wife_personal', 8);
    PERFORM pg_temp.tx(14, 2, 10, 600, 'T64 Gold VA', 'OPEX-SHOPPING', 'wife_personal', 10);

    -- A pool-paid personal purchase of W: a legacy row from before the account guard
    -- (20261101000100 refuses a new one), written as it stood, with the pool debited.
    SET LOCAL session_replication_role = replica;
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, cycle_key,
                                     source, spent_by, nafaqah_class, nafaqah_spouse_id, account_id)
    VALUES (pg_temp.t(7), pg_temp.h(1), pg_temp.u(2), 90, 'T64 Legacy Pool', 'OPEX-SHOPPING', '2026-11-05 11:00:00+03',
            '2026-11', 'manual', 'me', 'wife_personal', pg_temp.u(2), pg_temp.a(1));
    SET LOCAL session_replication_role = origin;
    UPDATE public.accounts SET balance = balance - 90 WHERE id = pg_temp.a(1);

    INSERT INTO storage.objects (bucket_id, name, owner) VALUES
        ('receipts', pg_temp.h(1)::text || '/t64_o.jpg', pg_temp.u(4)),
        ('receipts', pg_temp.h(1)::text || '/t64_w.jpg', pg_temp.u(2)),
        ('receipts', pg_temp.h(1)::text || '/t64_w2.jpg', pg_temp.u(3));
END $$;

-- ── Husband present ─────────────────────────────────────────────────────────────────────────
-- (household, caller, label, personal rows of each wife read, cycle sum)
CREATE TABLE pg_temp.who (hh int, actor int, label text, sees_all boolean, cycle_sum text);
INSERT INTO pg_temp.who VALUES
    (1, 1, 'the husband (an admin)', true, '1210.00'),
    (1, 5, 'an admin who is not a wife', true, '1210.00'),
    (1, 2, 'the wife', false, '510.00'),
    (1, 3, 'a co-wife', false, '520.00'),
    (1, 6, 'a wife who is an admin', false, '620.00'),
    (1, 4, 'an ordinary member', false, '220.00'),
    (2, 7, 'F2 husband (not an admin)', true, '1240.00'),
    (2, 9, 'F2 admin who is not a wife', true, '1240.00'),
    (2, 8, 'F2 wife', false, '640.00'),
    (2, 10, 'F2 wife who is an admin', false, '740.00'),
    (2, 11, 'F2 ordinary member', false, '140.00');

CREATE FUNCTION pg_temp.check_reads(p_when text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v record;
    v_wife int;
    v_n int;
BEGIN
    FOR v IN SELECT * FROM pg_temp.who ORDER BY hh, actor LOOP
        FOR v_wife IN SELECT unnest(CASE WHEN v.hh = 1 THEN ARRAY[2, 3, 6] ELSE ARRAY[8, 10] END) LOOP
            -- W has two personal purchases (one paid from the pool), every other wife one.
            v_n := CASE WHEN v_wife = 2 THEN 2 ELSE 1 END;
            PERFORM pg_temp.check(format('%s: %s reads the personal purchases of wife %s', p_when, v.label, v_wife),
                pg_temp.personal_of(v.actor, v_wife),
                CASE WHEN v.sees_all OR v.actor = v_wife THEN v_n::text ELSE '0' END);
        END LOOP;
        -- Ordinary expenses and her advances: every member reads all of them (regression).
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' reads every other transaction',
            pg_temp.n(v.actor, 'nafaqah_class IS DISTINCT FROM ''wife_personal'''),
            CASE WHEN v.hh = 1 THEN '3' ELSE '2' END);
        -- A sum over the cycle covers what the caller reads: no hidden amount in it.
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' sums the cycle', pg_temp.cycle_sum(v.actor), v.cycle_sum);
        -- The link to a wife: only her advance, unless the caller reads her personal purchases.
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' finds what names a co-wife of the caller',
            pg_temp.n(v.actor, format('nafaqah_spouse_id IS NOT NULL AND nafaqah_spouse_id <> %L', pg_temp.u(v.actor))),
            CASE
                WHEN v.sees_all AND v.hh = 1 THEN '5'
                WHEN v.sees_all THEN '3'
                -- The wife: only co-wives' purchases name someone else, and she reads none.
                WHEN v.actor IN (2, 8) THEN '0'
                -- Anyone else: the wife's advance only.
                ELSE '1'
            END);
        -- Merchants and notes: nothing of hers by text either.
        PERFORM pg_temp.check(p_when || ': ' || v.label || ' finds a co-wife''s merchant or note',
            pg_temp.n(v.actor, format('(merchant LIKE %L OR notes LIKE %L) AND nafaqah_spouse_id IS DISTINCT FROM %L',
                                      'T64 % W%', 'T64 note of T64 % W%', pg_temp.u(v.actor))),
            CASE WHEN v.sees_all AND v.hh = 1 THEN '3' ELSE '0' END);
    END LOOP;

    -- The pool-paid personal purchase: in the pool's history only for those who read it; the
    -- pool's balance the same for every member.
    PERFORM pg_temp.check(p_when || ': the husband reads both pool rows', pg_temp.n(1, format('account_id = %L', pg_temp.a(1))),
        CASE WHEN p_when = 'present' THEN '2' ELSE '0' END);
    PERFORM pg_temp.check(p_when || ': an admin who is not a wife reads both pool rows', pg_temp.n(5, format('account_id = %L', pg_temp.a(1))), '2');
    PERFORM pg_temp.check(p_when || ': the wife reads both pool rows (hers)', pg_temp.n(2, format('account_id = %L', pg_temp.a(1))), '2');
    PERFORM pg_temp.check(p_when || ': a co-wife reads the pool''s household row only', pg_temp.n(3, format('account_id = %L', pg_temp.a(1))), '1');
    PERFORM pg_temp.check(p_when || ': a wife-admin reads the pool''s household row only', pg_temp.n(6, format('account_id = %L', pg_temp.a(1))), '1');
    PERFORM pg_temp.check(p_when || ': a member reads the pool''s household row only', pg_temp.n(4, format('account_id = %L', pg_temp.a(1))), '1');
    PERFORM pg_temp.check(p_when || ': a co-wife reads the pool''s balance',
        pg_temp.call(pg_temp.u(3), format('SELECT balance::text FROM public.accounts WHERE id = %L', pg_temp.a(1))), '4810.00');
    PERFORM pg_temp.check(p_when || ': a member reads the pool''s balance',
        pg_temp.call(pg_temp.u(4), format('SELECT balance::text FROM public.accounts WHERE id = %L', pg_temp.a(1))), '4810.00');
    PERFORM pg_temp.check(p_when || ': an admin reads the pool''s balance',
        pg_temp.call(pg_temp.u(5), format('SELECT balance::text FROM public.accounts WHERE id = %L', pg_temp.a(1))), '4810.00');

    -- Receipt photos: hers (a storage path, and a legacy signed URL) only for those who read the
    -- purchase; an ordinary expense's photo for every member.
    PERFORM pg_temp.check(p_when || ': the wife reads her receipt', pg_temp.receipt(2, pg_temp.h(1)::text || '/t64_w.jpg'), '1');
    PERFORM pg_temp.check(p_when || ': an admin who is not a wife reads her receipt', pg_temp.receipt(5, pg_temp.h(1)::text || '/t64_w.jpg'), '1');
    PERFORM pg_temp.check(p_when || ': a co-wife reads her receipt', pg_temp.receipt(3, pg_temp.h(1)::text || '/t64_w.jpg'), '0');
    PERFORM pg_temp.check(p_when || ': a wife-admin reads her receipt', pg_temp.receipt(6, pg_temp.h(1)::text || '/t64_w.jpg'), '0');
    PERFORM pg_temp.check(p_when || ': a member reads her receipt', pg_temp.receipt(4, pg_temp.h(1)::text || '/t64_w.jpg'), '0');
    PERFORM pg_temp.check(p_when || ': the wife reads the co-wife''s receipt (signed URL)', pg_temp.receipt(2, pg_temp.h(1)::text || '/t64_w2.jpg'), '0');
    PERFORM pg_temp.check(p_when || ': the co-wife reads her own receipt (signed URL)', pg_temp.receipt(3, pg_temp.h(1)::text || '/t64_w2.jpg'), '1');
    PERFORM pg_temp.check(p_when || ': a member lists the folder',
        pg_temp.call(pg_temp.u(4), format('SELECT string_agg(name, '','' ORDER BY name) FROM storage.objects WHERE bucket_id = %L AND name LIKE %L',
                                          'receipts', pg_temp.h(1)::text || '/%')),
        pg_temp.h(1)::text || '/t64_o.jpg');
    PERFORM pg_temp.check(p_when || ': a co-wife reads the ordinary receipt', pg_temp.receipt(3, pg_temp.h(1)::text || '/t64_o.jpg'), '1');
    PERFORM pg_temp.check(p_when || ': a member reads the ordinary receipt', pg_temp.receipt(4, pg_temp.h(1)::text || '/t64_o.jpg'), '1');

    -- The category budget never counted her purchases (as before), and every member reads it.
    PERFORM pg_temp.check(p_when || ': a member reads the shopping budget',
        pg_temp.call(pg_temp.u(4), format('SELECT spent_amount::text FROM public.budgets WHERE household_id = %L AND category_code = %L',
                                          pg_temp.h(1), 'OPEX-SHOPPING')), '50.00');
END;
$$;

DO $$
BEGIN
    PERFORM pg_temp.check_reads('present');
    -- Her own personal account: only she reads its balance (as before).
    PERFORM pg_temp.check('present: the wife reads her account',
        pg_temp.call(pg_temp.u(2), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.a(2))), '1');
    PERFORM pg_temp.check('present: a co-wife reads her account',
        pg_temp.call(pg_temp.u(3), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.a(2))), '0');
    PERFORM pg_temp.check('present: a member reads her account',
        pg_temp.call(pg_temp.u(4), format('SELECT count(*)::text FROM public.accounts WHERE id = %L', pg_temp.a(2))), '0');
END $$;

-- ── Who creates, edits and voids: unchanged ───────────────────────────────────────────────────
DO $$
BEGIN
    -- She records her own and reads it back (the app inserts with RETURNING).
    PERFORM pg_temp.check('the wife records her own and reads it back',
        pg_temp.call(pg_temp.u(2), format(
            'INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id, account_id) '
            'VALUES (%L, %L, 11, %L, %L, %L, %L, %L, %L, %L, %L) RETURNING merchant',
            pg_temp.t(21), pg_temp.h(1), 'T64 New W', 'OPEX-SHOPPING', '2026-11-06 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), pg_temp.a(2))),
        'T64 New W');
    -- The husband and an admin who is not a wife record hers and read it back.
    PERFORM pg_temp.check('the husband records hers and reads it back',
        pg_temp.call(pg_temp.u(1), format(
            'INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id) '
            'VALUES (%L, %L, 12, %L, %L, %L, %L, %L, %L, %L) RETURNING merchant',
            pg_temp.t(22), pg_temp.h(1), 'T64 By H', 'OPEX-SHOPPING', '2026-11-06 10:00+03', 'manual', 'partner', 'wife_personal', pg_temp.u(2))),
        'T64 By H');
    PERFORM pg_temp.check('F2 husband (not an admin) records hers and reads it back',
        pg_temp.call(pg_temp.u(7), format(
            'INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id) '
            'VALUES (%L, %L, 13, %L, %L, %L, %L, %L, %L, %L) RETURNING merchant',
            pg_temp.t(23), pg_temp.h(2), 'T64 By H2', 'OPEX-SHOPPING', '2026-11-06 10:00+03', 'manual', 'partner', 'wife_personal', pg_temp.u(8))),
        'T64 By H2');
    -- A wife who is an admin may still classify a co-wife's (the write rule is unchanged), but
    -- does not read it afterwards.
    PERFORM pg_temp.check('a wife-admin records a co-wife''s (no read back)',
        pg_temp.write(pg_temp.u(6), format(
            'INSERT INTO public.transactions (id, household_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id) '
            'VALUES (%L, %L, 14, %L, %L, %L, %L, %L, %L, %L)',
            pg_temp.t(24), pg_temp.h(1), 'T64 By WA', 'OPEX-SHOPPING', '2026-11-06 10:00+03', 'manual', 'partner', 'wife_personal', pg_temp.u(2))),
        '1');
    PERFORM pg_temp.check('the wife-admin then reads it', pg_temp.n(6, format('id = %L', pg_temp.t(24))), '0');
    PERFORM pg_temp.check('the wife reads what the wife-admin recorded for her', pg_temp.n(2, format('id = %L', pg_temp.t(24))), '1');
    -- A co-wife who is not an admin never classifies another wife's purchase (as before).
    PERFORM pg_temp.check('a co-wife classifies hers',
        left(pg_temp.write(pg_temp.u(3), format(
            'INSERT INTO public.transactions (household_id, amount, merchant, category_code, timestamp, source, spent_by, nafaqah_class, nafaqah_spouse_id) '
            'VALUES (%L, 15, %L, %L, %L, %L, %L, %L, %L)',
            pg_temp.h(1), 'T64 By W2', 'OPEX-SHOPPING', '2026-11-06 10:00+03', 'manual', 'partner', 'wife_personal', pg_temp.u(2))), 9),
        'ERR:42501');
    -- Edits: she edits her own, the husband and an admin who is not a wife edit hers.
    PERFORM pg_temp.check('the wife edits her own', pg_temp.write(pg_temp.u(2), format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'by W', pg_temp.t(4))), '1');
    PERFORM pg_temp.check('the husband edits hers', pg_temp.write(pg_temp.u(1), format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'by H', pg_temp.t(4))), '1');
    PERFORM pg_temp.check('an admin who is not a wife edits hers', pg_temp.write(pg_temp.u(5), format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'by C', pg_temp.t(4))), '1');
    -- Those who do not read it cannot pick it: nothing changes.
    PERFORM pg_temp.check('a wife-admin edits hers', pg_temp.write(pg_temp.u(6), format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'by WA', pg_temp.t(4))), '0');
    PERFORM pg_temp.check('a member edits hers', pg_temp.write(pg_temp.u(4), format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'by K', pg_temp.t(4))), '0');
    PERFORM pg_temp.check('a wife-admin deletes hers', pg_temp.write(pg_temp.u(6), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(4))), '0');
    PERFORM pg_temp.check('her note after them', (SELECT notes FROM public.transactions WHERE id = pg_temp.t(4)), 'by C');
    -- Voids: she voids her own; the husband voids one he recorded for her.
    PERFORM pg_temp.check('the wife voids her own', pg_temp.write(pg_temp.u(2), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(21))), '1');
    PERFORM pg_temp.check('the husband voids hers', pg_temp.write(pg_temp.u(1), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(22))), '1');
    PERFORM pg_temp.check('an admin who is not a wife voids hers', pg_temp.write(pg_temp.u(5), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(24))), '1');
    DELETE FROM public.transactions WHERE id = pg_temp.t(23);
    -- An ordinary expense stays everyone's to read after an edit by its maker.
    PERFORM pg_temp.check('a member edits his own', pg_temp.write(pg_temp.u(4), format('UPDATE public.transactions SET notes = %L WHERE id = %L', 'K', pg_temp.t(2))), '1');
    PERFORM pg_temp.check('a co-wife reads the member''s edit', pg_temp.call(pg_temp.u(3), format('SELECT notes FROM public.transactions WHERE id = %L', pg_temp.t(2))), 'K');
END $$;

-- ── Husband gone (he left the household, which clears the provider) ─────────────────────────
DO $$
BEGIN
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(1);
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(2) AND user_id = pg_temp.u(7);
    PERFORM pg_temp.check('gone: no provider',
        (SELECT string_agg((nafaqah_provider_user_id IS NULL)::text, ',' ORDER BY id) FROM public.households
         WHERE id IN (pg_temp.h(1), pg_temp.h(2))), 'true,true');
END $$;

DELETE FROM pg_temp.who WHERE actor IN (1, 7);
DO $$
BEGIN
    PERFORM pg_temp.check_reads('gone');
    PERFORM pg_temp.check('gone: the husband who left reads nothing', pg_temp.n(1, 'true'), '0');
    PERFORM pg_temp.check('gone: F2 husband who left reads nothing', pg_temp.n(7, 'true'), '0');
END $$;

-- ── The rule stated where it lives ──────────────────────────────────────────────────────────
DO $$
DECLARE
    v_qual text;
BEGIN
    PERFORM pg_temp.check('one read policy on transactions',
        (SELECT string_agg(policyname || '/' || array_to_string(roles, ','), ';') FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'transactions' AND cmd = 'SELECT'),
        'transactions_select_household/authenticated');
    SELECT qual INTO v_qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transactions' AND cmd = 'SELECT';
    PERFORM pg_temp.check('the read policy keeps the household and names her rule',
        (v_qual LIKE '%household_id = ( SELECT get_auth_user_household_id()%'
         AND v_qual LIKE '%wife_personal%'
         AND v_qual LIKE '%nafaqah_spouse_id = ( SELECT auth.uid()%'
         AND v_qual LIKE '%SELECT nafaqah_caller_sees_allowances()%')::text, 'true');
    PERFORM pg_temp.check('the receipts read policy names her rule',
        (SELECT (qual LIKE '%nafaqah_receipt_hidden(name)%')::text FROM pg_policies
         WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'receipts_select_household'), 'true');
    PERFORM pg_temp.check('the receipt helper is STABLE SECURITY DEFINER with a pinned search_path',
        (SELECT (p.provolatile = 's' AND p.prosecdef AND p.proconfig::text LIKE '%search_path=public, pg_temp%')::text
         FROM pg_proc p WHERE p.oid = to_regprocedure('public.nafaqah_receipt_hidden(text)')), 'true');
    PERFORM pg_temp.check('anon runs no receipt helper',
        COALESCE(has_function_privilege('anon', to_regprocedure('public.nafaqah_receipt_hidden(text)'), 'EXECUTE')::text, 'missing'), 'false');
    PERFORM pg_temp.check('an index serves her receipts',
        (SELECT count(*)::text FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'transactions'
         AND indexname = 'idx_transactions_wife_personal_receipt'), '1');
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
    RAISE NOTICE 'PASSED: who reads a wife''s personal purchases.';
END $$;

ROLLBACK;
