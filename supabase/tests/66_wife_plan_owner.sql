-- ============================================================================
-- Test 66: The plan of a wife's personal purchase stays hers after the purchase is gone
--          (owner decision 2026-11-06)
--
-- Migration: 20261105001300_wife_repayment_debit.sql, section 10e (installment_plans.personal_owner_id,
--            its triggers, and the installment_plans policy)
-- Rule: .agents/rules/02-saudi-fintech-and-islamic-compliance.md, family mode rule 3;
--       .agents/rules/04-security-and-privacy.md, Family Nafaqah
--
-- A plan linked to her personal purchase is read by her, her husband (the household's Nafaqah
-- provider while he is a current member who is not a wife) and an admin of the household who is
-- not a wife (test 65). Deleting the purchase clears the link (ON DELETE SET NULL); the plan keeps
-- whose it was (personal_owner_id), so it stays read by the same people and no one else.
--   * The owner is the wife whose personal purchase the plan is linked to, worked out by the
--     database on every insert and every change of the link; no client sets it (no column
--     privilege, and an insert's value is replaced).
--   * It stays when the link is cleared: the purchase deleted, or the plan unlinked by hand.
--   * The plan follows its purchase while linked: a purchase reclassified from wife_personal to an
--     ordinary expense or to her advance (wife_reimbursable) makes its plan household-wide, also
--     after the purchase is deleted later; an ordinary purchase made hers makes it hers; a plan
--     linked again to another purchase takes that purchase's owner.
--   * A deleted person's id leaves the column with them (the BEFORE DELETE ON users path), so the
--     purge's "nothing names them" holds: through the deletion worker's purge and an out-of-band
--     delete alike. The plans stay, owned by nobody, read as the household's (as her purchases are).
--   * When she is no longer a wife of the household (she left), her plans are read like other rows,
--     as her purchases are.
--   * The backfill's helper: a plan made before 001300 (no owner) gets the owner of its purchase.
-- Every read is as the client makes it (RLS, as PostgREST and Realtime apply it).
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
AS $$ SELECT ('e6600000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.h(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e66a0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.t(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e66c0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.p(p_n int) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('e66d0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $$;
GRANT EXECUTE ON FUNCTION pg_temp.u(int), pg_temp.h(int), pg_temp.t(int), pg_temp.p(int) TO PUBLIC;

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

-- F1's people, by the name the checks use.
CREATE TABLE pg_temp.people (n int, name text);
INSERT INTO pg_temp.people VALUES (1, 'H'), (2, 'W'), (3, 'W2'), (4, 'K'), (5, 'C'), (6, 'WA'), (7, 'W3');
-- Who of F1 reads plan p_plan (as the client reads it), by name.
CREATE FUNCTION pg_temp.readers(p_plan int) RETURNS text LANGUAGE sql AS $$
    SELECT COALESCE(string_agg(pp.name, ',' ORDER BY pp.n), '')
    FROM pg_temp.people pp
    WHERE pg_temp.call(pg_temp.u(pp.n), format('SELECT count(*)::text FROM public.installment_plans WHERE id = %L', pg_temp.p(p_plan))) = '1'
      AND EXISTS (SELECT 1 FROM public.users x WHERE x.id = pg_temp.u(pp.n));
$$;
-- The owner kept on plan p_plan, by name ('-' for none), read by the server.
CREATE FUNCTION pg_temp.owner(p_plan int) RETURNS text LANGUAGE sql AS $$
    SELECT pg_temp.call(NULL, format(
        'SELECT COALESCE((SELECT name FROM pg_temp.people WHERE pg_temp.u(n) = p.personal_owner_id), '
        'CASE WHEN p.personal_owner_id IS NULL THEN ''-'' ELSE p.personal_owner_id::text END) '
        'FROM public.installment_plans p WHERE p.id = %L', pg_temp.p(p_plan)), 'postgres');
$$;

-- ── Fixtures ────────────────────────────────────────────────────────────────
-- F1(1): husband H(1) admin and provider; wife W(2); co-wife W2(3); member K(4); admin C(5) who is
--        not a wife; wife WA(6) who is an admin; wife W3(7), deleted out of band later; wife W4(10),
--        purged by the deletion worker later (not among the readers listed).
-- F2(2): admin D(9) and provider; wife V(8).
DO $$
BEGIN
    INSERT INTO auth.users (id, email, raw_user_meta_data)
    SELECT pg_temp.u(n), 't66-' || n || '@test.local', jsonb_build_object('display_name', 'T66 User ' || n)
    FROM generate_series(1, 10) AS n;

    INSERT INTO public.households (id, name, invite_code, household_type, payday_day) VALUES
        (pg_temp.h(1), 'T66 H1', 'T66CODE000000001', 'family', 27),
        (pg_temp.h(2), 'T66 H2', 'T66CODE000000002', 'family', 27);
    PERFORM pg_temp.join(1, 1, 'admin', 'provider');
    PERFORM pg_temp.join(5, 1, 'admin', 'family_member');
    PERFORM pg_temp.join(2, 1, 'member', 'spouse');
    PERFORM pg_temp.join(3, 1, 'member', 'spouse');
    PERFORM pg_temp.join(4, 1, 'member', 'family_member');
    PERFORM pg_temp.join(6, 1, 'admin', 'spouse');
    PERFORM pg_temp.join(7, 1, 'member', 'spouse');
    PERFORM pg_temp.join(10, 1, 'member', 'spouse');
    PERFORM pg_temp.join(9, 2, 'admin', 'provider');
    PERFORM pg_temp.join(8, 2, 'member', 'spouse');
    UPDATE public.households SET owner_user_id = pg_temp.u(1), nafaqah_provider_user_id = pg_temp.u(1) WHERE id = pg_temp.h(1);
    UPDATE public.households SET owner_user_id = pg_temp.u(9), nafaqah_provider_user_id = pg_temp.u(9) WHERE id = pg_temp.h(2);

    -- Purchases (no account), each made by the one whose it is.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, notes) VALUES
        (pg_temp.t(1), pg_temp.h(1), pg_temp.u(2), 1200, 'T66 Boutique', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), 'n'),
        (pg_temp.t(2), pg_temp.h(1), pg_temp.u(3), 900, 'T66 Salon', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(3), 'n'),
        (pg_temp.t(3), pg_temp.h(1), pg_temp.u(1), 2000, 'T66 Electronics', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', NULL, NULL, 'n'),
        (pg_temp.t(4), pg_temp.h(1), pg_temp.u(2), 400, 'T66 Perfume', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), 'n'),
        (pg_temp.t(5), pg_temp.h(1), pg_temp.u(2), 300, 'T66 Shoes', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', NULL, NULL, 'n'),
        (pg_temp.t(6), pg_temp.h(1), pg_temp.u(2), 700, 'T66 Gold', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), 'n'),
        (pg_temp.t(7), pg_temp.h(1), pg_temp.u(7), 500, 'T66 Bag', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(7), 'n'),
        (pg_temp.t(8), pg_temp.h(1), pg_temp.u(7), 650, 'T66 Watch', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(7), 'n'),
        (pg_temp.t(9), pg_temp.h(1), pg_temp.u(2), 350, 'T66 Ring', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(2), 'n'),
        (pg_temp.t(11), pg_temp.h(2), pg_temp.u(8), 800, 'T66 Abaya V', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(8), 'n');
END $$;

-- Plans as the API writes them (the service role), each linked as named.
DO $$
BEGIN
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, original_transaction_id, notes) VALUES
        (pg_temp.p(1), pg_temp.h(1), 'pl1 Boutique', 'Tabby', 1200, 4, 300, 1, '2026-11-05', pg_temp.t(1), 'k'),
        (pg_temp.p(2), pg_temp.h(1), 'pl2 Salon', 'Tamara', 900, 3, 300, 1, '2026-11-05', pg_temp.t(2), 'k'),
        (pg_temp.p(3), pg_temp.h(1), 'pl3 Electronics', 'Bank', 2000, 10, 200, 2, '2026-11-05', pg_temp.t(3), 'k'),
        (pg_temp.p(4), pg_temp.h(1), 'pl4 Perfume', 'Tabby', 400, 4, 100, 1, '2026-11-05', pg_temp.t(4), 'k'),
        (pg_temp.p(5), pg_temp.h(1), 'pl5 Shoes', 'Tabby', 300, 3, 100, 1, '2026-11-05', pg_temp.t(5), 'k'),
        (pg_temp.p(6), pg_temp.h(1), 'pl6 Gold', 'Tabby', 700, 4, 175, 1, '2026-11-05', pg_temp.t(6), 'k'),
        (pg_temp.p(7), pg_temp.h(1), 'pl7 Bag', 'Tabby', 500, 4, 125, 1, '2026-11-05', pg_temp.t(7), 'k'),
        (pg_temp.p(8), pg_temp.h(1), 'pl8 Watch', 'Tabby', 650, 2, 325, 1, '2026-11-05', pg_temp.t(8), 'k'),
        (pg_temp.p(9), pg_temp.h(1), 'pl9 Ring', 'Tabby', 350, 2, 175, 1, '2026-11-05', pg_temp.t(9), 'k'),
        (pg_temp.p(10), pg_temp.h(1), 'pl10 Unlinked', 'Other', 400, 4, 100, 0, '2026-11-05', NULL, 'k'),
        -- Linked to a purchase of another household: no owner here, and read by no member of F1 (test 65).
        (pg_temp.p(11), pg_temp.h(1), 'pl11 Elsewhere', 'Bank', 800, 4, 200, 1, '2026-11-05', pg_temp.t(11), 'k');
END $$;

-- ── Whose each plan is, kept when it is made; no client sets it ──────────────────────────────
DO $$
BEGIN
    -- A member adds an unlinked plan naming a wife as its owner: the database keeps none.
    PERFORM pg_temp.check('a member adds a plan naming her as its owner',
        pg_temp.write(pg_temp.u(4), format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, personal_owner_id) '
            'VALUES (%L, %L, %L, 100, 2, 50, 0, %L)', pg_temp.p(20), pg_temp.h(1), 'pl20 K', pg_temp.u(2))), '1');
    -- The husband adds a plan on her purchase naming nobody: the database keeps her.
    PERFORM pg_temp.check('the husband adds a plan on her purchase naming nobody',
        pg_temp.write(pg_temp.u(1), format(
            'INSERT INTO public.installment_plans (id, household_id, merchant, total_amount, installment_count, monthly_amount, paid_installments, original_transaction_id, personal_owner_id) '
            'VALUES (%L, %L, %L, 1200, 4, 300, 0, %L, NULL)', pg_temp.p(21), pg_temp.h(1), 'pl21 Boutique again', pg_temp.t(1))), '1');

    PERFORM pg_temp.check('the owners kept on the plans',
        (SELECT string_agg(n || '=' || pg_temp.owner(n), ',' ORDER BY n) FROM unnest(ARRAY[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 20, 21]) n),
        '1=W,2=W2,3=-,4=W,5=-,6=W,7=W3,8=W3,9=W,10=-,11=-,20=-,21=W');

    -- No client changes it: not a member on his own plan, not the husband on hers.
    PERFORM pg_temp.check('a member sets the owner of his plan',
        left(pg_temp.write(pg_temp.u(4), format('UPDATE public.installment_plans SET personal_owner_id = %L WHERE id = %L', pg_temp.u(2), pg_temp.p(20))), 9),
        'ERR:42501');
    PERFORM pg_temp.check('the husband clears the owner of her plan',
        left(pg_temp.write(pg_temp.u(1), format('UPDATE public.installment_plans SET personal_owner_id = NULL WHERE id = %L', pg_temp.p(1))), 9),
        'ERR:42501');
    PERFORM pg_temp.check('the owners after them', pg_temp.owner(20) || ',' || pg_temp.owner(1), '-,W');
    -- Read by the same people as her purchase while it is linked (test 65).
    PERFORM pg_temp.check('linked: her plan', pg_temp.readers(1), 'H,W,C');
    PERFORM pg_temp.check('linked: the member''s plan', pg_temp.readers(20), 'H,W,W2,K,C,WA,W3');
END $$;

-- ── Her purchase deleted: the plan stays hers ─────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('she deletes her purchase',
        pg_temp.write(pg_temp.u(2), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(1))), '1');
    PERFORM pg_temp.check('its plans lost their link',
        (SELECT string_agg((original_transaction_id IS NULL)::text, ',' ORDER BY id) FROM public.installment_plans
         WHERE id IN (pg_temp.p(1), pg_temp.p(21))), 'true,true');
    PERFORM pg_temp.check('deleted: the owners stay', pg_temp.owner(1) || ',' || pg_temp.owner(21), 'W,W');
    PERFORM pg_temp.check('deleted: who reads her plan', pg_temp.readers(1), 'H,W,C');
    PERFORM pg_temp.check('deleted: who reads her second plan', pg_temp.readers(21), 'H,W,C');
    -- Nothing of it by amount, shop or note either.
    PERFORM pg_temp.check('deleted: a member finds it by amount',
        pg_temp.call(pg_temp.u(4), 'SELECT count(*)::text FROM public.installment_plans WHERE total_amount = 1200'), '0');
    PERFORM pg_temp.check('deleted: a co-wife finds it by shop',
        pg_temp.call(pg_temp.u(3), 'SELECT count(*)::text FROM public.installment_plans WHERE merchant LIKE ''%Boutique%'''), '0');
    PERFORM pg_temp.check('deleted: a wife-admin sums the plans',
        pg_temp.call(pg_temp.u(6), format('SELECT sum(total_amount)::text FROM public.installment_plans WHERE household_id = %L AND original_transaction_id IS NULL', pg_temp.h(1))),
        '500.00');
    -- Who does not read it cannot pick it.
    PERFORM pg_temp.check('deleted: a member edits it',
        pg_temp.write(pg_temp.u(4), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'K', pg_temp.p(1))), '0');
    PERFORM pg_temp.check('deleted: a wife-admin deletes it',
        pg_temp.write(pg_temp.u(6), format('DELETE FROM public.installment_plans WHERE id = %L', pg_temp.p(1))), '0');
    PERFORM pg_temp.check('deleted: a co-wife deletes it',
        pg_temp.write(pg_temp.u(3), format('DELETE FROM public.installment_plans WHERE id = %L', pg_temp.p(1))), '0');
    PERFORM pg_temp.check('deleted: the plan is still there', (SELECT count(*)::text FROM public.installment_plans WHERE id = pg_temp.p(1) AND notes = 'k'), '1');
    -- She, her husband and an admin who is not a wife still edit it.
    PERFORM pg_temp.check('deleted: she edits it',
        pg_temp.write(pg_temp.u(2), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'W', pg_temp.p(1))), '1');
    PERFORM pg_temp.check('deleted: an admin who is not a wife edits it',
        pg_temp.write(pg_temp.u(5), format('UPDATE public.installment_plans SET notes = %L WHERE id = %L', 'C', pg_temp.p(1))), '1');
    PERFORM pg_temp.check('deleted: still hers after the edits', pg_temp.owner(1), 'W');

    -- Unlinked by hand (the husband clears the link of the co-wife's plan): it stays hers.
    PERFORM pg_temp.check('the husband unlinks her plan',
        pg_temp.write(pg_temp.u(1), format('UPDATE public.installment_plans SET original_transaction_id = NULL WHERE id = %L', pg_temp.p(2))), '1');
    PERFORM pg_temp.check('unlinked: still hers', pg_temp.owner(2), 'W2');
    PERFORM pg_temp.check('unlinked: who reads it', pg_temp.readers(2), 'H,W2,C');
END $$;

-- ── The plan follows its purchase while linked ────────────────────────────────────────────────
DO $$
BEGIN
    -- Hers made an ordinary expense: the plan is everyone's, also after the purchase is deleted.
    PERFORM pg_temp.check('she makes her purchase a household one',
        pg_temp.write(pg_temp.u(2), format('UPDATE public.transactions SET nafaqah_class = NULL, nafaqah_spouse_id = NULL WHERE id = %L', pg_temp.t(4))), '1');
    PERFORM pg_temp.check('reclassified ordinary: no owner', pg_temp.owner(4), '-');
    PERFORM pg_temp.check('reclassified ordinary: who reads it', pg_temp.readers(4), 'H,W,W2,K,C,WA,W3');
    PERFORM pg_temp.check('then she deletes it',
        pg_temp.write(pg_temp.u(2), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(4))), '1');
    PERFORM pg_temp.check('reclassified ordinary, deleted: who reads it', pg_temp.readers(4), 'H,W,W2,K,C,WA,W3');

    -- Hers made her advance (wife_reimbursable, read by every member): the plan is everyone's.
    PERFORM pg_temp.check('she makes it her advance',
        pg_temp.write(pg_temp.u(2), format('UPDATE public.transactions SET nafaqah_class = %L WHERE id = %L', 'wife_reimbursable', pg_temp.t(9))), '1');
    PERFORM pg_temp.check('her advance: no owner', pg_temp.owner(9), '-');
    PERFORM pg_temp.check('her advance: who reads it', pg_temp.readers(9), 'H,W,W2,K,C,WA,W3');

    -- An ordinary purchase made hers: the plan is hers, also after the purchase is deleted.
    PERFORM pg_temp.check('she makes her ordinary purchase personal',
        pg_temp.write(pg_temp.u(2), format('UPDATE public.transactions SET nafaqah_class = %L, nafaqah_spouse_id = %L WHERE id = %L',
                                           'wife_personal', pg_temp.u(2), pg_temp.t(5))), '1');
    PERFORM pg_temp.check('made personal: hers', pg_temp.owner(5), 'W');
    PERFORM pg_temp.check('made personal: who reads it', pg_temp.readers(5), 'H,W,C');
    PERFORM pg_temp.check('then she deletes it too',
        pg_temp.write(pg_temp.u(2), format('DELETE FROM public.transactions WHERE id = %L', pg_temp.t(5))), '1');
    PERFORM pg_temp.check('made personal, deleted: who reads it', pg_temp.readers(5), 'H,W,C');

    -- Her purchase becomes the co-wife's (the server moves it): the plan follows it.
    UPDATE public.transactions SET nafaqah_spouse_id = pg_temp.u(3) WHERE id = pg_temp.t(6);
    PERFORM pg_temp.check('moved to the co-wife: hers', pg_temp.owner(6), 'W2');
    DELETE FROM public.transactions WHERE id = pg_temp.t(6);
    PERFORM pg_temp.check('moved to the co-wife, deleted: who reads it', pg_temp.readers(6), 'H,W2,C');

    -- The husband links the co-wife's unlinked plan to an ordinary purchase: it follows that one.
    PERFORM pg_temp.check('the husband links her plan to an ordinary purchase',
        pg_temp.write(pg_temp.u(1), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(3), pg_temp.p(2))), '1');
    PERFORM pg_temp.check('linked to an ordinary purchase: no owner', pg_temp.owner(2), '-');
    PERFORM pg_temp.check('linked to an ordinary purchase: who reads it', pg_temp.readers(2), 'H,W,W2,K,C,WA,W3');
    -- And an ordinary plan linked to her purchase becomes hers.
    PERFORM pg_temp.check('the husband links the ordinary plan to her purchase',
        pg_temp.write(pg_temp.u(1), format('UPDATE public.installment_plans SET original_transaction_id = %L WHERE id = %L', pg_temp.t(7), pg_temp.p(10))), '1');
    PERFORM pg_temp.check('linked to her purchase: hers', pg_temp.owner(10), 'W3');
    PERFORM pg_temp.check('linked to her purchase: who reads it', pg_temp.readers(10), 'H,C,W3');

    -- Another household's purchase never makes an owner here.
    PERFORM pg_temp.check('another household''s purchase: no owner', pg_temp.owner(11), '-');
END $$;

-- ── The backfill's helper: a plan made before 001300 gets its purchase's owner ─────────────────
DO $$
BEGIN
    PERFORM pg_temp.check('the helper: her purchase',
        pg_temp.call(NULL, format('SELECT public.nafaqah_purchase_personal_owner(%L, %L)::text', pg_temp.t(2), pg_temp.h(1)), 'postgres'),
        pg_temp.u(3)::text);
    PERFORM pg_temp.check('the helper: an ordinary purchase',
        pg_temp.call(NULL, format('SELECT public.nafaqah_purchase_personal_owner(%L, %L)::text', pg_temp.t(3), pg_temp.h(1)), 'postgres'), 'ok');
    PERFORM pg_temp.check('the helper: her advance',
        pg_temp.call(NULL, format('SELECT public.nafaqah_purchase_personal_owner(%L, %L)::text', pg_temp.t(9), pg_temp.h(1)), 'postgres'), 'ok');
    PERFORM pg_temp.check('the helper: another household''s purchase',
        pg_temp.call(NULL, format('SELECT public.nafaqah_purchase_personal_owner(%L, %L)::text', pg_temp.t(11), pg_temp.h(1)), 'postgres'), 'ok');
    PERFORM pg_temp.check('the helper: no purchase',
        pg_temp.call(NULL, format('SELECT public.nafaqah_purchase_personal_owner(NULL, %L)::text', pg_temp.h(1)), 'postgres'), 'ok');
    -- Every linked plan carries what the backfill would give it.
    PERFORM pg_temp.check('every linked plan as the backfill fills it',
        pg_temp.call(NULL, 'SELECT count(*)::text FROM public.installment_plans p WHERE p.original_transaction_id IS NOT NULL '
                           'AND p.personal_owner_id IS DISTINCT FROM public.nafaqah_purchase_personal_owner(p.original_transaction_id, p.household_id)',
                     'postgres'), '0');
END $$;

-- ── She leaves the household: no longer a wife of it, her plans are read like other rows ───────
DO $$
BEGIN
    -- WA's personal purchase and its plan, then she leaves (her purchases become household ones).
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, notes)
    VALUES (pg_temp.t(12), pg_temp.h(1), pg_temp.u(6), 222, 'T66 Scarf', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(6), 'n');
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, original_transaction_id, notes)
    VALUES (pg_temp.p(12), pg_temp.h(1), 'pl12 Scarf', 'Tabby', 222, 2, 111, 1, '2026-11-05', pg_temp.t(12), 'k');
    DELETE FROM public.transactions WHERE id = pg_temp.t(12);
    PERFORM pg_temp.check('before she leaves: who reads her plan', pg_temp.readers(12), 'H,C,WA');
    DELETE FROM public.household_memberships WHERE household_id = pg_temp.h(1) AND user_id = pg_temp.u(6);
    DELETE FROM pg_temp.people WHERE n = 6;
    PERFORM pg_temp.check('after she left: who reads her plan', pg_temp.readers(12), 'H,W,W2,K,C,W3');
END $$;

-- ── The deletion worker purges a wife: her id leaves her plans ────────────────────────────────
-- The worker's whole job, as test 54 runs it: her request, claim, prepare_account_purge (which
-- deletes her personal purchases), storage, the Auth delete, complete.
DO $$
DECLARE
    v_sess text;
    v_req uuid;
    v_res text;
BEGIN
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     spent_by, nafaqah_class, nafaqah_spouse_id, notes) VALUES
        (pg_temp.t(13), pg_temp.h(1), pg_temp.u(10), 480, 'T66 Heels', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(10), 'n'),
        (pg_temp.t(14), pg_temp.h(1), pg_temp.u(10), 260, 'T66 Kohl', 'OPEX-SHOPPING', '2026-11-05 10:00+03', 'manual', 'me', 'wife_personal', pg_temp.u(10), 'n');
    INSERT INTO public.installment_plans (id, household_id, merchant, provider, total_amount, installment_count,
                                          monthly_amount, paid_installments, start_date, original_transaction_id, notes) VALUES
        (pg_temp.p(13), pg_temp.h(1), 'pl13 Heels', 'Tabby', 480, 4, 120, 1, '2026-11-05', pg_temp.t(13), 'k'),
        (pg_temp.p(14), pg_temp.h(1), 'pl14 Kohl', 'Tabby', 260, 2, 130, 1, '2026-11-05', pg_temp.t(14), 'k');
    DELETE FROM public.transactions WHERE id = pg_temp.t(14);
    PERFORM pg_temp.check('before the purge: the plans naming W4',
        pg_temp.call(NULL, format('SELECT count(*)::text FROM public.installment_plans WHERE personal_owner_id = %L', pg_temp.u(10)), 'postgres'), '2');
    PERFORM pg_temp.check('before the purge: a member reads neither', pg_temp.readers(13) || '|' || pg_temp.readers(14), 'H,C|H,C');

    INSERT INTO auth.sessions (user_id, created_at) VALUES (pg_temp.u(10), now()) RETURNING id::text INTO v_sess;
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.u(10), 'session_id', v_sess)::text, true);
    SET LOCAL ROLE authenticated;
    PERFORM public.request_account_deletion('DELETE', '[]'::jsonb, NULL, 'en');
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT id INTO v_req FROM public.account_deletion_requests WHERE user_id = pg_temp.u(10) AND status = 'scheduled';
    UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 minute' WHERE id = v_req;
    v_res := pg_temp.call(NULL, 'SELECT count(*)::text FROM public.claim_due_account_deletions(50, 30)', 'service_role');
    PERFORM pg_temp.check('the worker claims her request', (v_res::int >= 1)::text, 'true');
    v_res := pg_temp.call(NULL, format('SELECT (public.prepare_account_purge(%L) ->> %L)', v_req, 'deferred'), 'service_role');
    PERFORM pg_temp.check('the purge is prepared, not deferred', v_res, 'false');
    PERFORM pg_temp.check('the purge deleted her personal purchase',
        (SELECT count(*)::text FROM public.transactions WHERE id = pg_temp.t(13)), '0');
    PERFORM pg_temp.call(NULL, format('SELECT public.mark_account_purge_storage_done(%L)::text', v_req), 'service_role');
    DELETE FROM auth.users WHERE id = pg_temp.u(10);
    v_res := pg_temp.call(NULL, format('SELECT public.complete_account_purge(%L)::text', v_req), 'service_role');
    PERFORM pg_temp.check('the purge completes', (left(v_res, 4) <> 'ERR:')::text, 'true');

    PERFORM pg_temp.check('purged: no plan names her',
        pg_temp.call(NULL, format('SELECT count(*)::text FROM public.installment_plans WHERE personal_owner_id = %L', pg_temp.u(10)), 'postgres'), '0');
    PERFORM pg_temp.check('purged: her id nowhere in the plans or the transfers',
        (SELECT count(*)::text FROM public.installment_plans p WHERE p::text LIKE '%' || pg_temp.u(10)::text || '%')
        || '|' || (SELECT count(*)::text FROM public.account_transfers x WHERE x::text LIKE '%' || pg_temp.u(10)::text || '%'), '0|0');
    -- The plans stay, with no link and no owner: like her purchases, read as the household's now.
    PERFORM pg_temp.check('purged: her plans stay, unlinked and owned by nobody', pg_temp.owner(13) || ',' || pg_temp.owner(14), '-,-');
END $$;

-- ── A deleted person's id leaves the plans with them ──────────────────────────────────────────
DO $$
BEGIN
    -- W3: one plan of a purchase already deleted (pl8), one still linked (pl10, linked above).
    DELETE FROM public.transactions WHERE id = pg_temp.t(8);
    PERFORM pg_temp.check('before: her plans', pg_temp.owner(8) || ',' || pg_temp.owner(10), 'W3,W3');
    PERFORM pg_temp.check('before: the plans naming her',
        pg_temp.call(NULL, format('SELECT count(*)::text FROM public.installment_plans WHERE personal_owner_id = %L', pg_temp.u(7)), 'postgres'), '3');
    DELETE FROM auth.users WHERE id = pg_temp.u(7);
    DELETE FROM pg_temp.people WHERE n = 7;
    PERFORM pg_temp.check('after: no plan names her',
        pg_temp.call(NULL, format('SELECT count(*)::text FROM public.installment_plans WHERE personal_owner_id = %L', pg_temp.u(7)), 'postgres'), '0');
    PERFORM pg_temp.check('after: her id nowhere in the plans',
        (SELECT count(*)::text FROM public.installment_plans p WHERE p::text LIKE '%' || pg_temp.u(7)::text || '%'), '0');
    PERFORM pg_temp.check('after: the plans stay', (SELECT count(*)::text FROM public.installment_plans WHERE id IN (pg_temp.p(7), pg_temp.p(8), pg_temp.p(10))), '3');
    -- The others' plans keep their owners.
    PERFORM pg_temp.check('after: the others keep theirs', pg_temp.owner(1) || ',' || pg_temp.owner(5) || ',' || pg_temp.owner(6), 'W,W,W2');
END $$;

-- ── The rule stated where it lives ──────────────────────────────────────────────────────────
DO $$
DECLARE
    v_qual text;
BEGIN
    PERFORM pg_temp.check('one policy on installment_plans',
        (SELECT string_agg(cmd || '/' || array_to_string(roles, ','), ';') FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'installment_plans'), 'ALL/authenticated');
    SELECT qual INTO v_qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'installment_plans';
    PERFORM pg_temp.check('the plans policy follows the purchase and keeps her owner',
        (v_qual LIKE '%household_id = ( SELECT get_auth_user_household_id()%'
         AND v_qual LIKE '%t.id = installment_plans.original_transaction_id%'
         AND v_qual LIKE '%ARRAY[personal_owner_id] && ( SELECT nafaqah_caller_hidden_wives()%')::text, 'true');
    PERFORM pg_temp.check('no client writes the owner',
        pg_temp.call(NULL, 'SELECT string_agg(r || ''='' || has_column_privilege(r, ''public.installment_plans'', ''personal_owner_id'', ''UPDATE'')::text, '','' ORDER BY r) '
                           'FROM unnest(ARRAY[''anon'', ''authenticated'']) r', 'postgres'),
        'anon=false,authenticated=false');
    PERFORM pg_temp.check('the owner''s helper and triggers',
        pg_temp.call(NULL, $q$
            SELECT format('%s|%s|%s|%s|%s',
                (SELECT p.prosecdef AND p.provolatile = 's' AND p.proconfig::text LIKE '%search_path=public, pg_temp%'
                 FROM pg_proc p WHERE p.oid = 'public.nafaqah_purchase_personal_owner(uuid, uuid)'::regprocedure),
                has_function_privilege('authenticated', 'public.nafaqah_purchase_personal_owner(uuid, uuid)', 'EXECUTE'),
                has_function_privilege('anon', 'public.nafaqah_purchase_personal_owner(uuid, uuid)', 'EXECUTE'),
                (SELECT string_agg(tgname, ',' ORDER BY tgname) FROM pg_trigger
                 WHERE tgenabled = 'O' AND tgname IN ('trg_installment_plans_personal_owner', 'trg_transactions_plan_owner', 'trg_users_forget_transfer_owner')),
                (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_installment_plans_personal_owner'))
        $q$, 'postgres'),
        't|f|f|trg_installment_plans_personal_owner,trg_transactions_plan_owner,trg_users_forget_transfer_owner|1');
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
    RAISE NOTICE 'PASSED: the plan of her personal purchase stays hers after the purchase is gone, and follows it while linked.';
END $$;

ROLLBACK;
