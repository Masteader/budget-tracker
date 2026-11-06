-- ============================================================================
-- Test 65: Who reads the transfers of a wife's personal account, and the installment plans of her
--          personal purchases (owner decision 2026-11-06)
--
-- Migration: 20261105001300_wife_repayment_debit.sql, section 10e (replaces the read policy of
--            account_transfers and the USING half of the installment_plans policy of
--            20261020100000)
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 3;
--       .agents/rules/04-security-and-privacy.md, Family Nafaqah
--
-- Read by the same people who read her personal purchases (test 64): she herself, her husband
-- (the household's Nafaqah provider while he is a current member who is not a wife) and a
-- household admin who is not a wife. A co-wife (even an admin) and an ordinary member read none.
--   * account_transfers: a row with either side a personal (not shared) account owned by a wife
--     of the household. She reads the rows of her own accounts, a transfer between two wives'
--     accounts included. The other side's balance is unchanged and read as before (a pool's
--     balance by every member); only the row leaves its history for the others. A repayment
--     (from his account or a pool to no account) never involves her account and stays as it is.
--     Whose accounts a transfer touched is kept on the row (personal_owner_ids, set on insert), so
--     a row stays hers after her account is deleted; a deleted person's id leaves it.
--   * installment_plans: a plan linked (original_transaction_id) to a personal purchase is read
--     by whoever reads that purchase; its schedule (next_due_at) and its payments
--     (paid_installments) are columns of the plan. A caller who cannot read a plan cannot pick it
--     to edit or delete it.
-- Every other transfer and plan stays visible to every member of the household.
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
AS $$ SELECT ('e6500000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e65a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.a(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e65b0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e65c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.p(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e65d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.a(int), pg_temp.t(int), pg_temp.p(int) TO PUBLIC;

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
        INSERT INTO pg_temp.fails (label, got, want) VALUES (p_label, left(p_got, 240), p_want);
    END IF;
END;
$$;

-- A transfer as the client makes it (transfer_between_accounts as user p_actor), labelled p_label
-- in its notes. Returns what the function answered the one who made it.
CREATE FUNCTION pg_temp.move(p_actor int, p_hh int, p_from int, p_to int, p_amount numeric, p_label text)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format(
        'SELECT (public.transfer_between_accounts(%L, %L, %L, %s, 0, %L) ->> %L)',
        pg_temp.h(p_hh), pg_temp.a(p_from), pg_temp.a(p_to), p_amount, p_label, 'notes'));
$$;
-- The transfers of the caller's household the caller reads, by label.
CREATE FUNCTION pg_temp.transfers(p_actor int, p_where text DEFAULT 'true') RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        'SELECT COALESCE(string_agg(notes, '','' ORDER BY notes), '''') FROM public.account_transfers WHERE ' || p_where);
$$;
-- An account's history as the app reads it (AccountService.listMovements), by label.
CREATE FUNCTION pg_temp.history(p_actor int, p_hh int, p_account int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.transfers(p_actor, format('household_id = %L AND (from_account_id = %L OR to_account_id = %L)',
                                             pg_temp.h(p_hh), pg_temp.a(p_account), pg_temp.a(p_account)));
$$;
-- The installment plans the caller reads, by merchant.
CREATE FUNCTION pg_temp.plans(p_actor int, p_where text DEFAULT 'true') RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor),
        'SELECT COALESCE(string_agg(merchant, '','' ORDER BY merchant), '''') FROM public.installment_plans WHERE ' || p_where);
$$;
CREATE FUNCTION pg_temp.balance(p_actor int, p_account int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(pg_temp.u(p_actor), format('SELECT balance::text FROM public.accounts WHERE id = %L', pg_temp.a(p_account)));
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider; wife W(2); co-wife W2(3); member K(4); admin C(5) who is
--        not a wife; wife WA(6) who is an admin.
-- F2(2): husband H2(7) a member (not an admin) and provider; wife V(8); primary admin D(9) who is
--        not a wife; wife VA(10) who is an admin; member M(11).
-- Accounts: F1 pool P(1) 5000, a second pool P'(8) 0 that the wife-admin owns (a pool is
--           everyone's, whoever owns it), W's bank A(2) 1000 and cash A(4) 200, W2's bank A(5) 800,
--           H's own A(6) 3000, K's own A(7) 500;
--           F2 pool P2(3) 3000, V's bank A(9) 400, H2's own A(10) 1000.
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't65-' || n || '@test.local', jsonb_build_object('display_name', 'T65 User ' || n)
    FROM generate_series(1, 11) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T65 H1', 'T65CODE000000001', 'family', 27),
        (pg_temp.h(2), 'T65 H2', 'T65CODE000000002', 'family', 27);
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
        (pg_temp.a(1), pg_temp.h(1), pg_temp.u(1), 'T65 pool', 'shared_pool', 5000, true, false, 'SAR'),
        (pg_temp.a(8), pg_temp.h(1), pg_temp.u(6), 'T65 pool 2', 'shared_pool', 0, true, false, 'SAR'),
        (pg_temp.a(2), pg_temp.h(1), pg_temp.u(2), 'T65 her bank', 'bank', 1000, false, false, 'SAR'),
        (pg_temp.a(4), pg_temp.h(1), pg_temp.u(2), 'T65 her cash', 'cash', 200, false, false, 'SAR'),
        (pg_temp.a(5), pg_temp.h(1), pg_temp.u(3), 'T65 co-wife bank', 'bank', 800, false, false, 'SAR'),
        (pg_temp.a(6), pg_temp.h(1), pg_temp.u(1), 'T65 his bank', 'bank', 3000, false, false, 'SAR'),
        (pg_temp.a(7), pg_temp.h(1), pg_temp.u(4), 'T65 member bank', 'bank', 500, false, false, 'SAR'),
        (pg_temp.a(3), pg_temp.h(2), pg_temp.u(9), 'T65 pool F2', 'shared_pool', 3000, true, false, 'SAR'),
        (pg_temp.a(9), pg_temp.h(2), pg_temp.u(8), 'T65 V bank', 'bank', 400, false, false, 'SAR'),
        (pg_temp.a(10), pg_temp.h(2), pg_temp.u(7), 'T65 H2 bank', 'bank', 1000, false, false, 'SAR');
END $$;

-- The transfers, each made by who may make it, through the client's RPC. Its maker gets its answer.
DO $$
BEGIN
    -- Hers (W's accounts 2 and 4).
    PERFORM pg_temp.check('W pays into the pool', pg_temp.move(2, 1, 2, 1, 100, 'x01 her bank to pool'), 'x01 her bank to pool');
    PERFORM pg_temp.check('H pays her from the pool', pg_temp.move(1, 1, 1, 2, 250, 'x02 pool to her bank'), 'x02 pool to her bank');
    PERFORM pg_temp.check('W moves between her two accounts', pg_temp.move(2, 1, 2, 4, 50, 'x03 her bank to her cash'), 'x03 her bank to her cash');
    PERFORM pg_temp.check('H gives her money', pg_temp.move(1, 1, 6, 2, 120, 'x09 his bank to her bank'), 'x09 his bank to her bank');
    -- The co-wife's (W2's account 5), and one between the two wives.
    PERFORM pg_temp.check('W2 pays into the pool', pg_temp.move(3, 1, 5, 1, 70, 'x04 co-wife bank to pool'), 'x04 co-wife bank to pool');
    PERFORM pg_temp.check('W2 sends W money', pg_temp.move(3, 1, 5, 2, 30, 'x08 co-wife bank to her bank'), 'x08 co-wife bank to her bank');
    -- A member sends her money: it involves her account, so he does not read it afterwards
    -- (ordinary members read nothing of them); his balance still shows it.
    PERFORM pg_temp.check('K sends W money', pg_temp.move(4, 1, 7, 2, 40, 'x11 member bank to her bank'), 'x11 member bank to her bank');
    -- Ordinary transfers, read by every member.
    PERFORM pg_temp.check('H pays into the pool', pg_temp.move(1, 1, 6, 1, 300, 'x05 his bank to pool'), 'x05 his bank to pool');
    PERFORM pg_temp.check('K pays into the pool', pg_temp.move(4, 1, 7, 1, 40, 'x06 member bank to pool'), 'x06 member bank to pool');
    PERFORM pg_temp.check('H moves between pools', pg_temp.move(1, 1, 1, 8, 500, 'x07 pool to pool 2'), 'x07 pool to pool 2');
    -- F2.
    PERFORM pg_temp.check('V pays into the pool', pg_temp.move(8, 2, 9, 3, 60, 'y01 V bank to pool'), 'y01 V bank to pool');
    PERFORM pg_temp.check('D pays H2 from the pool', pg_temp.move(9, 2, 3, 10, 90, 'y02 pool to H2 bank'), 'y02 pool to H2 bank');

    -- A repayment to W (his account to no account) and its reversal (no account to his), as the
    -- Nafaqah RPCs write them: they never involve her account.
    INSERT INTO public.account_transfers (household_id, user_id, from_account_id, to_account_id, amount, fee, notes, purpose)
    VALUES (pg_temp.h(1), pg_temp.u(1), pg_temp.a(6), NULL, 25, 0, 'x10 repayment', 'wife_repayment'),
           (pg_temp.h(1), pg_temp.u(1), NULL, pg_temp.a(6), 25, 0, 'x12 repayment reversed', 'wife_repayment_reversal');

    -- Purchases and the plans linked to them.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, notes) VALUES
        (pg_temp.t(1), pg_temp.h(1), pg_temp.u(2), 1200, 'T65 Boutique W', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), 'n'),
        (pg_temp.t(2), pg_temp.h(1), pg_temp.u(3), 900, 'T65 Salon W2', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(3), 'n'),
        (pg_temp.t(3), pg_temp.h(1), pg_temp.u(1), 2000, 'T65 Electronics', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', NULL, NULL, 'n'),
        (pg_temp.t(4), pg_temp.h(1), pg_temp.u(2), 600, 'T65 Pharmacy', 'OPEX-GROCERY', '2026-11-05 10:00+03', 'manual', 'me', 'wife_reimbursable', pg_temp.u(2), 'n'),
        (pg_temp.t(6), pg_temp.h(1), pg_temp.u(6), 700, 'T65 Gold WA', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(6), 'n'),
        (pg_temp.t(11), pg_temp.h(2), pg_temp.u(8), 800, 'T65 Abaya V', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(8), 'n');
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, original_transaction_id, notes) VALUES
        (pg_temp.p(1), pg_temp.h(1), 'pl1 Boutique W', 'Tabby', 1200, 4, 300, 1, '2026-11-05', pg_temp.t(1), 'k'),
        (pg_temp.p(2), pg_temp.h(1), 'pl2 Salon W2', 'Tamara', 900, 3, 300, 1, '2026-11-05', pg_temp.t(2), 'k'),
        (pg_temp.p(3), pg_temp.h(1), 'pl3 Electronics', 'Bank', 2000, 10, 200, 2, '2026-11-05', pg_temp.t(3), 'k'),
        (pg_temp.p(4), pg_temp.h(1), 'pl4 Unlinked', 'Other', 400, 4, 100, 0, '2026-11-05', NULL, 'k'),
        (pg_temp.p(5), pg_temp.h(1), 'pl5 Pharmacy advance', 'Tabby', 600, 4, 150, 1, '2026-11-05', pg_temp.t(4), 'k'),
        (pg_temp.p(6), pg_temp.h(1), 'pl6 Gold WA', 'Tabby', 700, 4, 175, 1, '2026-11-05', pg_temp.t(6), 'k'),
        -- Linked to a purchase of another household (no client read of it): read by no member of F1.
        (pg_temp.p(7), pg_temp.h(1), 'pl7 Elsewhere', 'Bank', 500, 5, 100, 1, '2026-11-05', pg_temp.t(11), 'k'),
        (pg_temp.p(11), pg_temp.h(2), 'pl11 Abaya V', 'Tabby', 800, 4, 200, 1, '2026-11-05', pg_temp.t(11), 'k'),
        (pg_temp.p(12), pg_temp.h(2), 'pl12 Unlinked F2', 'Other', 100, 2, 50, 0, '2026-11-05', NULL, 'k');
END $$;

-- ── Who reads what ──────────────────────────────────────────────────────────────────────────
-- (household, caller, label, reads everything of every wife)
CREATE TABLE pg_temp.who (hh int, actor int, label text, sees_all boolean);
INSERT INTO pg_temp.who VALUES
    (1, 1, 'the husband (an admin)', true),
    (1, 5, 'an admin who is not a wife', true),
    (1, 2, 'the wife', false),
    (1, 3, 'a co-wife', false),
    (1, 6, 'a wife who is an admin', false),
    (1, 4, 'an ordinary member', false),
    (2, 7, 'F2 husband (not an admin)', true),
    (2, 9, 'F2 admin who is not a wife', true),
    (2, 8, 'F2 wife', false),
    (2, 10, 'F2 wife who is an admin', false),
    (2, 11, 'F2 ordinary member', false);

CREATE FUNCTION pg_temp.expected_transfers(p_hh int, p_actor int, p_all boolean) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(l, ',' ORDER BY l) FROM unnest(
        CASE WHEN p_hh = 1 THEN
            ARRAY['x05 his bank to pool', 'x06 member bank to pool', 'x07 pool to pool 2', 'x10 repayment',
                  'x12 repayment reversed']
            -- W's accounts: hers, and the husband's and the admins'.
            || CASE WHEN p_all OR p_actor = 2 THEN ARRAY['x01 her bank to pool', 'x02 pool to her bank',
                   'x03 her bank to her cash', 'x09 his bank to her bank', 'x11 member bank to her bank'] ELSE '{}' END
            -- W2's account: hers, and the husband's and the admins'.
            || CASE WHEN p_all OR p_actor = 3 THEN ARRAY['x04 co-wife bank to pool'] ELSE '{}' END
            -- Between the two wives: each of them, and the husband and the admins.
            || CASE WHEN p_all OR p_actor IN (2, 3) THEN ARRAY['x08 co-wife bank to her bank'] ELSE '{}' END
        ELSE
            ARRAY['y02 pool to H2 bank']
            || CASE WHEN p_all OR p_actor = 8 THEN ARRAY['y01 V bank to pool'] ELSE '{}' END
        END) AS l;
$$;

CREATE FUNCTION pg_temp.expected_plans(p_hh int, p_actor int, p_all boolean) RETURNS text LANGUAGE sql AS $$
    SELECT string_agg(l, ',' ORDER BY l) FROM unnest(
        CASE WHEN p_hh = 1 THEN
            -- An ordinary purchase's plan, an unlinked one, and one of her advance: every member.
            ARRAY['pl3 Electronics', 'pl4 Unlinked', 'pl5 Pharmacy advance']
            || CASE WHEN p_all OR p_actor = 2 THEN ARRAY['pl1 Boutique W'] ELSE '{}' END
            || CASE WHEN p_all OR p_actor = 3 THEN ARRAY['pl2 Salon W2'] ELSE '{}' END
            || CASE WHEN p_all OR p_actor = 6 THEN ARRAY['pl6 Gold WA'] ELSE '{}' END
        ELSE
            ARRAY['pl12 Unlinked F2']
            || CASE WHEN p_all OR p_actor = 8 THEN ARRAY['pl11 Abaya V'] ELSE '{}' END
        END) AS l;
$$;

CREATE FUNCTION pg_temp.check_reads(p_when text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v record;
BEGIN
    FOR v IN SELECT * FROM pg_temp.who ORDER BY hh, actor LOOP
        PERFORM pg_temp.check(format('%s: %s reads the transfers', p_when, v.label),
            pg_temp.transfers(v.actor), pg_temp.expected_transfers(v.hh, v.actor, v.sees_all));
        PERFORM pg_temp.check(format('%s: %s reads the installment plans', p_when, v.label),
            pg_temp.plans(v.actor), pg_temp.expected_plans(v.hh, v.actor, v.sees_all));
        -- Nothing of hers by amount, account or note either.
        IF NOT v.sees_all AND v.hh = 1 AND v.actor NOT IN (2, 3) THEN
            PERFORM pg_temp.check(format('%s: %s finds a transfer of a wife''s account by account', p_when, v.label),
                pg_temp.call(pg_temp.u(v.actor), format(
                    'SELECT count(*)::text FROM public.account_transfers WHERE from_account_id IN (%L, %L, %L) OR to_account_id IN (%L, %L, %L)',
                    pg_temp.a(2), pg_temp.a(4), pg_temp.a(5), pg_temp.a(2), pg_temp.a(4), pg_temp.a(5))), '0');
            PERFORM pg_temp.check(format('%s: %s sums the transfers', p_when, v.label),
                pg_temp.call(pg_temp.u(v.actor), 'SELECT sum(amount)::text FROM public.account_transfers'), '890.00');
            PERFORM pg_temp.check(format('%s: %s finds a plan of a co-wife by amount', p_when, v.label),
                pg_temp.call(pg_temp.u(v.actor), format(
                    'SELECT count(*)::text FROM public.installment_plans WHERE total_amount IN (1200, 900, %s)',
                    CASE WHEN v.actor = 6 THEN 900 ELSE 700 END)),
                '0');
        END IF;
    END LOOP;

    -- The pool's history: only what the caller reads; its balance the same for every member.
    PERFORM pg_temp.check(p_when || ': an admin who is not a wife reads the pool''s history', pg_temp.history(5, 1, 1),
        'x01 her bank to pool,x02 pool to her bank,x04 co-wife bank to pool,x05 his bank to pool,x06 member bank to pool,x07 pool to pool 2');
    PERFORM pg_temp.check(p_when || ': the wife reads the pool''s history', pg_temp.history(2, 1, 1),
        'x01 her bank to pool,x02 pool to her bank,x05 his bank to pool,x06 member bank to pool,x07 pool to pool 2');
    PERFORM pg_temp.check(p_when || ': a co-wife reads the pool''s history', pg_temp.history(3, 1, 1),
        'x04 co-wife bank to pool,x05 his bank to pool,x06 member bank to pool,x07 pool to pool 2');
    PERFORM pg_temp.check(p_when || ': a wife-admin reads the pool''s history', pg_temp.history(6, 1, 1),
        'x05 his bank to pool,x06 member bank to pool,x07 pool to pool 2');
    PERFORM pg_temp.check(p_when || ': a member reads the pool''s history', pg_temp.history(4, 1, 1),
        'x05 his bank to pool,x06 member bank to pool,x07 pool to pool 2');
    -- 5000 + 100 - 250 + 70 + 300 + 40 - 500.
    PERFORM pg_temp.check(p_when || ': a co-wife reads the pool''s balance', pg_temp.balance(3, 1), '4760.00');
    PERFORM pg_temp.check(p_when || ': a wife-admin reads the pool''s balance', pg_temp.balance(6, 1), '4760.00');
    PERFORM pg_temp.check(p_when || ': a member reads the pool''s balance', pg_temp.balance(4, 1), '4760.00');
    PERFORM pg_temp.check(p_when || ': an admin reads the pool''s balance', pg_temp.balance(5, 1), '4760.00');
    PERFORM pg_temp.check(p_when || ': a member reads the second pool''s balance', pg_temp.balance(4, 8), '500.00');
    PERFORM pg_temp.check(p_when || ': F2 member reads the pool''s balance', pg_temp.balance(11, 3), '2970.00');
    -- The member's own account: its balance shows what he sent her, the row does not.
    PERFORM pg_temp.check(p_when || ': the member reads his balance', pg_temp.balance(4, 7), '420.00');
    PERFORM pg_temp.check(p_when || ': the member reads his history', pg_temp.history(4, 1, 7), 'x06 member bank to pool');
    -- Her accounts' balances: only she reads them (as before).
    PERFORM pg_temp.check(p_when || ': the wife reads her bank', pg_temp.balance(2, 2), '1290.00');
    PERFORM pg_temp.check(p_when || ': the wife reads her bank''s history', pg_temp.history(2, 1, 2),
        'x01 her bank to pool,x02 pool to her bank,x03 her bank to her cash,x08 co-wife bank to her bank,x09 his bank to her bank,x11 member bank to her bank');
    PERFORM pg_temp.check(p_when || ': the co-wife reads her own bank''s history', pg_temp.history(3, 1, 5),
        'x04 co-wife bank to pool,x08 co-wife bank to her bank');
    PERFORM pg_temp.check(p_when || ': a co-wife reads the wife''s bank''s history', pg_temp.history(3, 1, 2),
        'x08 co-wife bank to her bank');
END;
$$;

DO $$
BEGIN
    PERFORM pg_temp.check_reads('present');
    -- The husband reads her accounts' rows, not her account itself (as before).
    PERFORM pg_temp.check('present: the husband reads her bank''s history', pg_temp.history(1, 1, 2),
        'x01 her bank to pool,x02 pool to her bank,x03 her bank to her cash,x08 co-wife bank to her bank,x09 his bank to her bank,x11 member bank to her bank');
    PERFORM pg_temp.check('present: the husband reads her bank', pg_temp.balance(1, 2), 'ok');
    PERFORM pg_temp.check('present: F2 husband (not an admin) reads V''s transfer', pg_temp.history(7, 2, 9), 'y01 V bank to pool');
END $$;

-- ── Writes: a plan the caller does not read cannot be picked ─────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('a co-wife edits her plan', pg_temp.write(pg_temp.u(3), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'W2', pg_temp.p(1))), '0');
    PERFORM pg_temp.check('a wife-admin edits her plan', pg_temp.write(pg_temp.u(6), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'WA', pg_temp.p(1))), '0');
    PERFORM pg_temp.check('a wife-admin deletes her plan', pg_temp.write(pg_temp.u(6), format('DELETE FROM public.installment_plans WHERE id = %L', pg_temp.p(1))), '0');
    PERFORM pg_temp.check('a member edits every plan he can', pg_temp.write(pg_temp.u(4), 'UPDATE public.installment_plans SET notes = ''K'''), '3');
    PERFORM pg_temp.check('the plans after them',
        (SELECT string_agg(merchant || '=' || notes, ',' ORDER BY merchant) FROM public.installment_plans WHERE household_id = pg_temp.h(1)),
        'pl1 Boutique W=k,pl2 Salon W2=k,pl3 Electronics=K,pl4 Unlinked=K,pl5 Pharmacy advance=K,pl6 Gold WA=k,pl7 Elsewhere=k');
    -- She, the husband and an admin who is not a wife edit hers.
    PERFORM pg_temp.check('the wife edits her plan', pg_temp.write(pg_temp.u(2), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'W', pg_temp.p(1))), '1');
    PERFORM pg_temp.check('the husband edits her plan', pg_temp.write(pg_temp.u(1), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'H', pg_temp.p(1))), '1');
    PERFORM pg_temp.check('an admin who is not a wife edits her plan', pg_temp.write(pg_temp.u(5), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'C', pg_temp.p(1))), '1');
    -- A member still adds a plan of his own and reads it back (the app's insert returns the row).
    PERFORM pg_temp.check('a member adds a plan and reads it back',
        pg_temp.call(pg_temp.u(4), format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments) '
            'VALUES (%L, %L, %L, 100, 2, 50, 0) RETURNING merchant', pg_temp.p(20), pg_temp.h(1), 'pl20 K')), 'pl20 K');
    DELETE FROM public.installment_plans WHERE id = pg_temp.p(20);
END $$;

-- A delete of every plan the member can (no filter at all), undone afterwards: hers stay.
DO $$
DECLARE
    v text;
BEGIN
    BEGIN
        v := pg_temp.write(pg_temp.u(4), 'DELETE FROM public.installment_plans');
        v := v || '|' || (SELECT string_agg(merchant, ',' ORDER BY merchant) FROM public.installment_plans WHERE household_id = pg_temp.h(1));
        RAISE EXCEPTION 'undo %', v;
    EXCEPTION WHEN raise_exception THEN
        PERFORM pg_temp.check('a member deletes every plan he can', SQLERRM, 'undo 3|pl1 Boutique W,pl2 Salon W2,pl6 Gold WA,pl7 Elsewhere');
    END;
END $$;

-- ── The plan follows its purchase ──────────────────────────────────────────────────────────
DO $$
BEGIN
    -- W2's purchase becomes a household expense (W2 reclassifies it): its plan is everyone's.
    PERFORM pg_temp.check('W2 makes her purchase a household one',
        pg_temp.write(pg_temp.u(3), format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(2))), '1');
    PERFORM pg_temp.check('the member then reads its plan', pg_temp.plans(4, format('id = %L', pg_temp.p(2))), 'pl2 Salon W2');
    PERFORM pg_temp.check('the wife then reads its plan', pg_temp.plans(2, format('id = %L', pg_temp.p(2))), 'pl2 Salon W2');
    -- And back.
    PERFORM pg_temp.check('W2 makes it personal again',
        pg_temp.write(pg_temp.u(3), format('UPDATE public.transactions SET nafaqah_class = %L, nafaqah_spouse_id = %L WHERE id = %L',
                                           'wife_personal', pg_temp.u(3), pg_temp.t(2))), '1');
    PERFORM pg_temp.check('the member no longer reads its plan', pg_temp.plans(4, format('id = %L', pg_temp.p(2))), '');
END $$;

-- ── What the caller's helpers return: who the wives are, nothing of their accounts ─────────────
DO $$
BEGIN
    PERFORM pg_temp.check('a member: every wife',
        pg_temp.call(pg_temp.u(4), 'SELECT public.nafaqah_caller_hidden_wives()::text'),
        format('{%s,%s,%s}', pg_temp.u(2), pg_temp.u(3), pg_temp.u(6)));
    PERFORM pg_temp.check('the wife: her co-wives',
        pg_temp.call(pg_temp.u(2), 'SELECT public.nafaqah_caller_hidden_wives()::text'),
        format('{%s,%s}', pg_temp.u(3), pg_temp.u(6)));
    PERFORM pg_temp.check('the husband: none', pg_temp.call(pg_temp.u(1), 'SELECT public.nafaqah_caller_hidden_wives()::text'), '{}');
    PERFORM pg_temp.check('an admin who is not a wife: none', pg_temp.call(pg_temp.u(5), 'SELECT public.nafaqah_caller_hidden_wives()::text'), '{}');
    PERFORM pg_temp.check('the wife is a wife', pg_temp.call(pg_temp.u(2), 'SELECT public.nafaqah_caller_wife_id()::text'), pg_temp.u(2)::text);
    PERFORM pg_temp.check('a member is no wife', pg_temp.call(pg_temp.u(4), 'SELECT public.nafaqah_caller_wife_id()::text'), 'ok');
    PERFORM pg_temp.check('anon runs no transfer helper',
        pg_temp.call(NULL, 'SELECT public.nafaqah_caller_hidden_wives()::text', 'anon'),
        'ERR:42501:permission denied for function nafaqah_caller_hidden_wives');
    -- Whose accounts each transfer touched, kept when it was made.
    PERFORM pg_temp.check('the owners kept on her transfers',
        pg_temp.call(NULL, format(
            'SELECT string_agg(notes || ''='' || COALESCE(array_length(personal_owner_ids, 1), 0)::text, '','' ORDER BY notes) '
            'FROM public.account_transfers WHERE household_id = %L AND notes IN (%L, %L, %L, %L)',
            pg_temp.h(1), 'x01 her bank to pool', 'x03 her bank to her cash', 'x08 co-wife bank to her bank', 'x07 pool to pool 2'),
            'postgres'),
        'x01 her bank to pool=1,x03 her bank to her cash=1,x07 pool to pool 2=0,x08 co-wife bank to her bank=2');
END $$;

-- ── Her account deleted later: the rows stay hers ───────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('the wife deletes her cash account',
        pg_temp.write(pg_temp.u(2), format('DELETE FROM public.accounts WHERE id = %L', pg_temp.a(4))), '1');
    PERFORM pg_temp.check('the transfer to it lost its side',
        (SELECT (to_account_id IS NULL)::text FROM public.account_transfers WHERE notes = 'x03 her bank to her cash'), 'true');
    PERFORM pg_temp.check('a co-wife still does not read it',
        pg_temp.transfers(3, format('notes = %L', 'x03 her bank to her cash')), '');
    PERFORM pg_temp.check('a member still does not read it',
        pg_temp.transfers(4, format('notes = %L', 'x03 her bank to her cash')), '');
    PERFORM pg_temp.check('she still reads it',
        pg_temp.transfers(2, format('notes = %L', 'x03 her bank to her cash')), 'x03 her bank to her cash');
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
    PERFORM pg_temp.check('gone: the husband who left reads no transfer', pg_temp.transfers(1), '');
    PERFORM pg_temp.check('gone: the husband who left reads no plan', pg_temp.plans(1), '');
    PERFORM pg_temp.check('gone: F2 husband who left reads no transfer', pg_temp.transfers(7), '');
END $$;

-- ── A deleted person's id leaves the owners kept on transfers ───────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('before: the member is an owner of two transfers',
        (SELECT count(*)::text FROM public.account_transfers WHERE pg_temp.u(4) = ANY (personal_owner_ids)), '2');
    DELETE FROM auth.users WHERE id = pg_temp.u(4);
    PERFORM pg_temp.check('after: his id is nowhere in them',
        (SELECT count(*)::text FROM public.account_transfers WHERE pg_temp.u(4) = ANY (personal_owner_ids)), '0');
    PERFORM pg_temp.check('after: the transfer he sent her is still hers',
        (SELECT (personal_owner_ids = ARRAY[pg_temp.u(2)])::text FROM public.account_transfers WHERE notes = 'x11 member bank to her bank'), 'true');
    PERFORM pg_temp.check('after: a co-wife still does not read it',
        pg_temp.transfers(3, format('notes = %L', 'x11 member bank to her bank')), '');
END $$;

-- ── The rule stated where it lives ──────────────────────────────────────────────────────────
DO $$
DECLARE
    v_qual text;
BEGIN
    PERFORM pg_temp.check('one read policy on account_transfers',
        (SELECT string_agg(policyname || '/' || cmd || '/' || array_to_string(roles, ','), ';') FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'account_transfers'),
        'transfers_select_household/SELECT/authenticated');
    SELECT qual INTO v_qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'account_transfers';
    PERFORM pg_temp.check('the transfers policy keeps the household and names her rule',
        (v_qual LIKE '%household_id = ( SELECT get_auth_user_household_id()%'
         AND v_qual LIKE '%personal_owner_ids && ( SELECT nafaqah_caller_hidden_wives()%'
         AND v_qual LIKE '%SELECT nafaqah_caller_wife_id()%')::text, 'true');
    PERFORM pg_temp.check('one policy on installment_plans',
        (SELECT string_agg(cmd || '/' || array_to_string(roles, ','), ';') FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'installment_plans'), 'ALL/authenticated');
    SELECT qual INTO v_qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'installment_plans';
    PERFORM pg_temp.check('the plans policy keeps the household and follows the purchase',
        (v_qual LIKE '%household_id = ( SELECT get_auth_user_household_id()%'
         AND v_qual LIKE '%original_transaction_id IS NULL%'
         AND v_qual LIKE '%FROM transactions t%'
         AND v_qual LIKE '%t.id = installment_plans.original_transaction_id%')::text, 'true');
    PERFORM pg_temp.check('the plans write check is the household''s',
        (SELECT with_check FROM pg_policies WHERE schemaname = 'public' AND tablename = 'installment_plans'),
        '(household_id = ( SELECT get_auth_user_household_id() AS get_auth_user_household_id))');
    PERFORM pg_temp.check('the transfer helpers are STABLE SECURITY DEFINER with a pinned search_path',
        (SELECT string_agg(p.proname || '=' || (p.provolatile = 's' AND p.prosecdef
                                                 AND p.proconfig::text LIKE '%search_path=public, pg_temp%')::text, ',' ORDER BY p.proname)
         FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname IN ('nafaqah_caller_hidden_wives', 'nafaqah_caller_wife_id', 'nafaqah_personal_owners_of')),
        'nafaqah_caller_hidden_wives=true,nafaqah_caller_wife_id=true,nafaqah_personal_owners_of=true');
    PERFORM pg_temp.check('the policy runs the caller''s helpers as the caller; anon none; the rest internal',
        (SELECT string_agg(r || ':' || f || '=' || COALESCE(has_function_privilege(r, to_regprocedure('public.' || f), 'EXECUTE')::text, 'missing'), ',' ORDER BY r, f)
         FROM unnest(ARRAY['authenticated', 'anon']) r,
              unnest(ARRAY['nafaqah_caller_hidden_wives()', 'nafaqah_caller_wife_id()', 'nafaqah_personal_owners_of(uuid, uuid)',
                           'nafaqah_transfer_personal_owners()', 'nafaqah_forget_transfer_owner()']) f),
        'anon:nafaqah_caller_hidden_wives()=false,anon:nafaqah_caller_wife_id()=false,anon:nafaqah_forget_transfer_owner()=false,'
        'anon:nafaqah_personal_owners_of(uuid, uuid)=false,anon:nafaqah_transfer_personal_owners()=false,'
        'authenticated:nafaqah_caller_hidden_wives()=true,authenticated:nafaqah_caller_wife_id()=true,'
        'authenticated:nafaqah_forget_transfer_owner()=false,'
        'authenticated:nafaqah_personal_owners_of(uuid, uuid)=false,authenticated:nafaqah_transfer_personal_owners()=false');
    PERFORM pg_temp.check('every transfer carries its owners, set on insert',
        (SELECT format('%s|%s|%s', a.attnotnull, pg_get_expr(d.adbin, d.adrelid),
                       (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.account_transfers'::regclass
                        AND tgname = 'trg_account_transfers_personal_owners' AND tgenabled = 'O')
                       + (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.users'::regclass
                          AND tgname = 'trg_users_forget_transfer_owner' AND tgenabled = 'O'))
         FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE a.attrelid = 'public.account_transfers'::regclass AND a.attname = 'personal_owner_ids'),
        't|''{}''::uuid[]|2');
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
    RAISE NOTICE 'PASSED: who reads the transfers of a wife''s personal account and the plans of her personal purchases.';
END $$;

ROLLBACK;
