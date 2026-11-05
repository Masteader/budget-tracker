-- ============================================================================
-- Test 49: an expense in an inactive category counts in no budget
--
-- Migration: 20261105001000_inactive_category_budgets.sql
--
-- Owner decision: an expense is filed under its own category even when that
-- category is inactive for the household. It counts in totals and reports, never
-- in a budget, and activating the category with a budget counts the open cycle.
--
--   1. Insert, update and delete of a transaction move spent_amount of active
--      budget rows only (is_active false: toggled off, or archived when the
--      category is replaced). A row with is_active NULL still counts, as the
--      app reads NULL as active.
--   2. recompute_budget_spent recomputes active rows only; inactive rows keep
--      their value.
--   3. wife_personal and settlement rows still reach no budget, and
--      wife_reimbursable rows still reach the category budget, exactly as before.
--   4. A budget row that becomes active (inserted active, or is_active false ->
--      true) for the household's open cycle takes that cycle's spending of its
--      category, by the recompute rule. Rows of other cycles are left as they are.
--   5. The helper is not callable by clients.
--
-- Dates are relative to now(): the open cycle is the one now() falls in.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

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

-- spent_amount of a household's budget row for a category and cycle.
CREATE FUNCTION pg_temp.spent(p_household uuid, p_code text, p_cycle text)
RETURNS text
LANGUAGE sql
AS $$
    SELECT spent_amount::text FROM public.budgets
    WHERE household_id = p_household AND category_code = p_code AND cycle_key = p_cycle;
$$;

CREATE TABLE pg_temp.ctx (k text PRIMARY KEY, v text);

-- 0. Catalog -----------------------------------------------------------------
DO $$
BEGIN
    IF to_regprocedure('public.budget_spent_from_transactions(uuid, text, text)') IS NULL THEN
        RAISE EXCEPTION 'MISSING: public.budget_spent_from_transactions(uuid, text, text)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgrelid = 'public.budgets'::regclass AND tgname = 'trg_budget_activation_counts_open_cycle'
                     AND NOT tgisinternal) THEN
        RAISE EXCEPTION 'MISSING: trigger trg_budget_activation_counts_open_cycle on public.budgets';
    END IF;
    IF has_function_privilege('authenticated', 'public.budget_spent_from_transactions(uuid, text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.budget_spent_from_transactions(uuid, text, text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.budget_activation_counts_open_cycle()', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.recompute_budget_spent(uuid, text[])', 'EXECUTE') THEN
        RAISE EXCEPTION 'clients can execute the budget helpers';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p
               WHERE p.oid IN ('public.budget_spent_from_transactions(uuid, text, text)'::regprocedure,
                               'public.budget_activation_counts_open_cycle()'::regprocedure,
                               'public.recompute_budget_spent(uuid, text[])'::regprocedure,
                               'public.update_budget_on_transaction()'::regprocedure,
                               'public.update_budget_on_transaction_delete()'::regprocedure,
                               'public.update_budget_on_transaction_update()'::regprocedure)
                 AND (NOT p.prosecdef OR p.proconfig IS NULL
                      OR NOT ('search_path=public, pg_temp' = ANY (p.proconfig)))) THEN
        RAISE EXCEPTION 'budget functions must be SECURITY DEFINER with a pinned search_path';
    END IF;
    RAISE NOTICE 'PASSED: helper, activation trigger and privileges.';
END $$;

-- Fixtures ---------------------------------------------------------------------
-- R: a roommates flat (admin A).  F: a family (provider H, wife W).  Both payday 27.
DO $$
DECLARE
    v_r uuid := '49aa0000-0000-0000-0000-000000000001';
    v_f uuid := '49aa0000-0000-0000-0000-000000000002';
    v_a uuid := '49000000-0000-0000-0000-0000000000a1';
    v_h uuid := '49000000-0000-0000-0000-0000000000b1';
    v_w uuid := '49000000-0000-0000-0000-0000000000b2';
    v_k text;
    v_pk text;
BEGIN
    INSERT INTO auth.users (id, email) VALUES
        (v_a, 't49-a@test.local'), (v_h, 't49-h@test.local'), (v_w, 't49-w@test.local');
    INSERT INTO public.households (id, name, invite_code, owner_user_id, payday_day, household_type) VALUES
        (v_r, 'T49 Flat', 'T49FLATCODE00001', v_a, 27, 'roommates'),
        (v_f, 'T49 Family', 'T49FAMILYCODE001', v_h, 27, 'family');
    INSERT INTO public.household_memberships (household_id, user_id, role, financial_role) VALUES
        (v_r, v_a, 'admin', 'peer'),
        (v_f, v_h, 'admin', 'provider'),
        (v_f, v_w, 'member', 'spouse')
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = EXCLUDED.role, financial_role = EXCLUDED.financial_role;
    UPDATE public.households SET nafaqah_provider_user_id = v_h WHERE id = v_f;

    v_k := public.nafaqah_current_cycle_key(v_r);
    -- 45 days back is always an earlier cycle with payday 27.
    SELECT cycle_key INTO v_pk FROM public.get_saudi_cycle_for_timestamp(now() - interval '45 days', 27);
    IF v_k IS NULL OR v_pk IS NULL OR v_k = v_pk THEN
        RAISE EXCEPTION 'fixture: open cycle % and earlier cycle % must differ', v_k, v_pk;
    END IF;
    INSERT INTO pg_temp.ctx VALUES ('r', v_r), ('f', v_f), ('a', v_a), ('h', v_h), ('w', v_w), ('k', v_k), ('pk', v_pk);
END $$;

-- 1. Triggers: inactive rows take nothing, active rows as before ----------------------
DO $$
DECLARE
    v_r uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'r');
    v_a uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'a');
    v_k text := (SELECT v FROM pg_temp.ctx WHERE k = 'k');
    v_m date := to_date(v_k || '-01', 'YYYY-MM-DD');
BEGIN
    -- Housing toggled off (inactive row, as toggle_category_status leaves it), Grocery and
    -- Dining active, Fuel with is_active NULL (read as active by the app).
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active) VALUES
        (v_r, 'OPEX-HOUSING', v_m, v_k, 0, 0, false),
        (v_r, 'OPEX-GROCERY', v_m, v_k, 1000, 0, true),
        (v_r, 'OPEX-DINING', v_m, v_k, 500, 0, true),
        (v_r, 'OPEX-FUEL', v_m, v_k, 300, 0, NULL);

    -- Insert.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000001', v_r, v_a, 2500, 'Ejar', 'OPEX-HOUSING', now(), 'chat'),
        ('49f00000-0000-0000-0000-000000000002', v_r, v_a, 120, 'Panda', 'OPEX-GROCERY', now(), 'chat'),
        ('49f00000-0000-0000-0000-000000000003', v_r, v_a, 40, 'Sasco', 'OPEX-FUEL', now(), 'chat');
    PERFORM pg_temp.expect('insert: inactive Housing takes nothing', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '0.00');
    PERFORM pg_temp.expect('insert: active Grocery counts', pg_temp.spent(v_r, 'OPEX-GROCERY', v_k), '120.00');
    PERFORM pg_temp.expect('insert: NULL is_active still counts', pg_temp.spent(v_r, 'OPEX-FUEL', v_k), '40.00');
    PERFORM pg_temp.expect('insert: the stored row keeps its category',
        (SELECT category_code FROM public.transactions WHERE id = '49f00000-0000-0000-0000-000000000001'), 'OPEX-HOUSING');

    -- Update within the inactive category: nothing moves.
    UPDATE public.transactions SET amount = 2600 WHERE id = '49f00000-0000-0000-0000-000000000001';
    PERFORM pg_temp.expect('update: inactive Housing still nothing', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '0.00');

    -- Update from inactive Housing to active Dining: Dining gains, Housing untouched.
    UPDATE public.transactions SET category_code = 'OPEX-DINING' WHERE id = '49f00000-0000-0000-0000-000000000001';
    PERFORM pg_temp.expect('update in: Dining gains', pg_temp.spent(v_r, 'OPEX-DINING', v_k), '2600.00');
    PERFORM pg_temp.expect('update in: Housing untouched', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '0.00');
    -- And back: Dining gives it back, Housing still takes nothing.
    UPDATE public.transactions SET category_code = 'OPEX-HOUSING' WHERE id = '49f00000-0000-0000-0000-000000000001';
    PERFORM pg_temp.expect('update out: Dining back to 0', pg_temp.spent(v_r, 'OPEX-DINING', v_k), '0.00');
    PERFORM pg_temp.expect('update out: Housing still nothing', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '0.00');

    -- Delete from the inactive category: nothing moves (a set value, so GREATEST(0, ...) masks nothing).
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000004', v_r, v_a, 5, 'Ejar fee', 'OPEX-HOUSING', now(), 'chat');
    UPDATE public.budgets SET spent_amount = 7 WHERE household_id = v_r AND category_code = 'OPEX-HOUSING';
    DELETE FROM public.transactions WHERE id = '49f00000-0000-0000-0000-000000000004';
    PERFORM pg_temp.expect('delete: inactive Housing keeps its value', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '7.00');
    UPDATE public.budgets SET spent_amount = 0 WHERE household_id = v_r AND category_code = 'OPEX-HOUSING';

    -- Toggle-off of Grocery (120 counted): later insert, update and delete leave it frozen.
    UPDATE public.budgets SET is_active = false WHERE household_id = v_r AND category_code = 'OPEX-GROCERY';
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000005', v_r, v_a, 30, 'Tamimi', 'OPEX-GROCERY', now(), 'chat');
    PERFORM pg_temp.expect('toggled off: insert ignored', pg_temp.spent(v_r, 'OPEX-GROCERY', v_k), '120.00');
    UPDATE public.transactions SET amount = 20 WHERE id = '49f00000-0000-0000-0000-000000000002';
    PERFORM pg_temp.expect('toggled off: update ignored', pg_temp.spent(v_r, 'OPEX-GROCERY', v_k), '120.00');
    DELETE FROM public.transactions WHERE id = '49f00000-0000-0000-0000-000000000002';
    PERFORM pg_temp.expect('toggled off: delete ignored', pg_temp.spent(v_r, 'OPEX-GROCERY', v_k), '120.00');

    -- recompute: active rows from their transactions, inactive rows left as they are.
    UPDATE public.budgets SET spent_amount = 999 WHERE household_id = v_r AND category_code = 'OPEX-FUEL';
    PERFORM public.recompute_budget_spent(v_r, ARRAY[v_k]);
    PERFORM pg_temp.expect('recompute: NULL-active Fuel recomputed', pg_temp.spent(v_r, 'OPEX-FUEL', v_k), '40.00');
    PERFORM pg_temp.expect('recompute: Dining recomputed', pg_temp.spent(v_r, 'OPEX-DINING', v_k), '0.00');
    PERFORM pg_temp.expect('recompute: inactive Housing not given its 2600', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '0.00');
    PERFORM pg_temp.expect('recompute: inactive Grocery keeps 120', pg_temp.spent(v_r, 'OPEX-GROCERY', v_k), '120.00');
    RAISE NOTICE 'PASSED: insert / update / delete / recompute skip inactive rows, active rows unchanged.';
END $$;

-- 2. Archived (replaced) category -----------------------------------------------
DO $$
DECLARE
    v_r uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'r');
    v_a uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'a');
    v_k text := (SELECT v FROM pg_temp.ctx WHERE k = 'k');
    v_m date := to_date(v_k || '-01', 'YYYY-MM-DD');
    v_new text;
BEGIN
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active)
    VALUES (v_r, 'OPEX-UTILITIES', v_m, v_k, 500, 0, true);
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000011', v_r, v_a, 80, 'SEC', 'OPEX-UTILITIES', now(), 'chat');
    PERFORM pg_temp.expect('before archive: Utilities counts', pg_temp.spent(v_r, 'OPEX-UTILITIES', v_k), '80.00');

    -- What the API's "Replace & Archive" (salary_cycle.replace_household_category) writes: the old
    -- category off in the settings and its open-cycle row inactive, a new custom category with an
    -- active budget. (The SQL function of the same name cannot run on this chain: its
    -- ON CONFLICT (code) has no matching constraint.) archive_category_for_household turns every
    -- row of the category off the same way.
    v_new := 'CUSTOM-BILLS-T49';
    INSERT INTO public.household_category_settings (household_id, category_code, is_active)
    VALUES (v_r, 'OPEX-UTILITIES', false);
    UPDATE public.budgets SET is_active = false
    WHERE household_id = v_r AND category_code = 'OPEX-UTILITIES' AND cycle_key = v_k;
    INSERT INTO public.cost_control_codes (code, category, keywords, is_system, household_id) VALUES (v_new, 'Bills T49', '{}', false, v_r);
    INSERT INTO public.household_category_settings (household_id, category_code, is_active) VALUES (v_r, v_new, true);
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active)
    VALUES (v_r, v_new, v_m, v_k, 500, 0, true);
    PERFORM pg_temp.expect('archived row is inactive',
        (SELECT is_active::text FROM public.budgets WHERE household_id = v_r AND category_code = 'OPEX-UTILITIES'), 'false');
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000012', v_r, v_a, 60, 'Mobily', 'OPEX-UTILITIES', now(), 'chat'),
        ('49f00000-0000-0000-0000-000000000013', v_r, v_a, 25, 'STC', v_new, now(), 'chat');
    PERFORM pg_temp.expect('archived: new Utilities expense ignored', pg_temp.spent(v_r, 'OPEX-UTILITIES', v_k), '80.00');
    DELETE FROM public.transactions WHERE id = '49f00000-0000-0000-0000-000000000011';
    PERFORM pg_temp.expect('archived: delete ignored', pg_temp.spent(v_r, 'OPEX-UTILITIES', v_k), '80.00');
    PERFORM pg_temp.expect('replacement counts its own', pg_temp.spent(v_r, v_new, v_k), '25.00');
    UPDATE public.transactions SET amount = 90 WHERE id = '49f00000-0000-0000-0000-000000000012';
    PERFORM pg_temp.expect('archived: update ignored', pg_temp.spent(v_r, 'OPEX-UTILITIES', v_k), '80.00');
    PERFORM public.recompute_budget_spent(v_r, ARRAY[v_k]);
    PERFORM pg_temp.expect('archived: recompute leaves it', pg_temp.spent(v_r, 'OPEX-UTILITIES', v_k), '80.00');
    PERFORM pg_temp.expect('replacement after recompute', pg_temp.spent(v_r, v_new, v_k), '25.00');
    RAISE NOTICE 'PASSED: an archived (replaced) category''s row takes nothing.';
END $$;

-- 3. Wife classes and settlements: exactly as before -----------------------------
DO $$
DECLARE
    v_f uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'f');
    v_h uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'h');
    v_w uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'w');
    v_k text := (SELECT v FROM pg_temp.ctx WHERE k = 'k');
    v_m date := to_date(v_k || '-01', 'YYYY-MM-DD');
BEGIN
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active) VALUES
        (v_f, 'OPEX-SHOPPING', v_m, v_k, 1000, 0, true),
        (v_f, 'OPEX-GROCERY', v_m, v_k, 1000, 0, true),
        (v_f, 'OPEX-DINING', v_m, v_k, 500, 0, true),
        (v_f, 'OPEX-HEALTH', v_m, v_k, 0, 0, false);
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     nafaqah_class, nafaqah_spouse_id, is_settlement) VALUES
        ('49f00000-0000-0000-0000-000000000021', v_f, v_w, 100, 'Abaya', 'OPEX-SHOPPING', now(), 'manual', 'wife_personal', v_w, false),
        ('49f00000-0000-0000-0000-000000000022', v_f, v_w, 300, 'Panda', 'OPEX-GROCERY', now(), 'manual', 'wife_reimbursable', v_w, false),
        ('49f00000-0000-0000-0000-000000000023', v_f, v_h, 150, 'Settlement', 'OPEX-DINING', now(), 'manual', NULL, NULL, true),
        ('49f00000-0000-0000-0000-000000000024', v_f, v_h, 60, 'Dinner', 'OPEX-DINING', now(), 'manual', NULL, NULL, false),
        ('49f00000-0000-0000-0000-000000000025', v_f, v_w, 70, 'Nahdi', 'OPEX-HEALTH', now(), 'manual', 'wife_reimbursable', v_w, false);
    PERFORM pg_temp.expect('wife_personal reaches no budget', pg_temp.spent(v_f, 'OPEX-SHOPPING', v_k), '0.00');
    PERFORM pg_temp.expect('wife_reimbursable reaches the category budget', pg_temp.spent(v_f, 'OPEX-GROCERY', v_k), '300.00');
    PERFORM pg_temp.expect('settlement reaches no budget', pg_temp.spent(v_f, 'OPEX-DINING', v_k), '60.00');
    PERFORM pg_temp.expect('wife_reimbursable in an inactive category: no budget', pg_temp.spent(v_f, 'OPEX-HEALTH', v_k), '0.00');

    -- Edits keep the same handling.
    UPDATE public.transactions SET amount = 120 WHERE id = '49f00000-0000-0000-0000-000000000021';
    PERFORM pg_temp.expect('wife_personal edit: no budget', pg_temp.spent(v_f, 'OPEX-SHOPPING', v_k), '0.00');
    UPDATE public.transactions SET amount = 250 WHERE id = '49f00000-0000-0000-0000-000000000022';
    PERFORM pg_temp.expect('wife_reimbursable edit follows', pg_temp.spent(v_f, 'OPEX-GROCERY', v_k), '250.00');
    UPDATE public.transactions SET is_settlement = true WHERE id = '49f00000-0000-0000-0000-000000000024';
    PERFORM pg_temp.expect('row turned into a settlement moves out', pg_temp.spent(v_f, 'OPEX-DINING', v_k), '0.00');
    UPDATE public.transactions SET is_settlement = false WHERE id = '49f00000-0000-0000-0000-000000000024';
    PERFORM pg_temp.expect('and back in', pg_temp.spent(v_f, 'OPEX-DINING', v_k), '60.00');
    DELETE FROM public.transactions WHERE id = '49f00000-0000-0000-0000-000000000023';
    PERFORM pg_temp.expect('settlement delete changes nothing', pg_temp.spent(v_f, 'OPEX-DINING', v_k), '60.00');
    PERFORM public.recompute_budget_spent(v_f, ARRAY[v_k]);
    PERFORM pg_temp.expect('recompute agrees (shopping)', pg_temp.spent(v_f, 'OPEX-SHOPPING', v_k), '0.00');
    PERFORM pg_temp.expect('recompute agrees (grocery)', pg_temp.spent(v_f, 'OPEX-GROCERY', v_k), '250.00');
    PERFORM pg_temp.expect('recompute agrees (dining)', pg_temp.spent(v_f, 'OPEX-DINING', v_k), '60.00');
    PERFORM pg_temp.expect('recompute leaves inactive health', pg_temp.spent(v_f, 'OPEX-HEALTH', v_k), '0.00');

    -- Activating Health counts the wife advance (as an active Health budget would have), never wife_personal.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source,
                                     nafaqah_class, nafaqah_spouse_id) VALUES
        ('49f00000-0000-0000-0000-000000000026', v_f, v_w, 35, 'Dawaa', 'OPEX-HEALTH', now(), 'manual', 'wife_personal', v_w);
    UPDATE public.budgets SET is_active = true WHERE household_id = v_f AND category_code = 'OPEX-HEALTH';
    PERFORM pg_temp.expect('activation: wife_reimbursable in, wife_personal out', pg_temp.spent(v_f, 'OPEX-HEALTH', v_k), '70.00');
    RAISE NOTICE 'PASSED: wife classes and settlements keep their handling.';
END $$;

-- 4. Activation counts the open cycle only -------------------------------------------
DO $$
DECLARE
    v_r uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'r');
    v_a uuid := (SELECT v FROM pg_temp.ctx WHERE k = 'a');
    v_k text := (SELECT v FROM pg_temp.ctx WHERE k = 'k');
    v_pk text := (SELECT v FROM pg_temp.ctx WHERE k = 'pk');
    v_m date := to_date(v_k || '-01', 'YYYY-MM-DD');
    v_pm date := to_date(v_pk || '-01', 'YYYY-MM-DD');
BEGIN
    -- Housing: 2600 in the open cycle (section 1); an inactive earlier-cycle row and a
    -- 1000 expense of that cycle.
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active)
    VALUES (v_r, 'OPEX-HOUSING', v_pm, v_pk, 0, 0, false);
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000031', v_r, v_a, 1000, 'Ejar (earlier)', 'OPEX-HOUSING', now() - interval '45 days', 'chat');
    PERFORM pg_temp.expect('earlier expense lands in the earlier cycle',
        (SELECT cycle_key FROM public.transactions WHERE id = '49f00000-0000-0000-0000-000000000031'), v_pk);

    -- The admin activates Housing and gives it a budget (toggle flips every row of the category).
    UPDATE public.budgets SET is_active = true WHERE household_id = v_r AND category_code = 'OPEX-HOUSING';
    UPDATE public.budgets SET allocated_amount = 3000 WHERE household_id = v_r AND category_code = 'OPEX-HOUSING' AND cycle_key = v_k;
    PERFORM pg_temp.expect('activation: the open cycle counts the rent', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '2600.00');
    PERFORM pg_temp.expect('activation: the earlier cycle stays as it was', pg_temp.spent(v_r, 'OPEX-HOUSING', v_pk), '0.00');
    -- From now on the triggers count it.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000032', v_r, v_a, 100, 'Maintenance', 'OPEX-HOUSING', now(), 'chat');
    PERFORM pg_temp.expect('after activation the trigger counts', pg_temp.spent(v_r, 'OPEX-HOUSING', v_k), '2700.00');

    -- A row already active is not recomputed by a no-op is_active write.
    UPDATE public.budgets SET spent_amount = 11 WHERE household_id = v_r AND category_code = 'OPEX-DINING';
    UPDATE public.budgets SET is_active = true WHERE household_id = v_r AND category_code = 'OPEX-DINING';
    PERFORM pg_temp.expect('active -> active: untouched', pg_temp.spent(v_r, 'OPEX-DINING', v_k), '11.00');
    -- Deactivating does not recompute either.
    UPDATE public.budgets SET is_active = false WHERE household_id = v_r AND category_code = 'OPEX-DINING';
    PERFORM pg_temp.expect('active -> inactive: untouched', pg_temp.spent(v_r, 'OPEX-DINING', v_k), '11.00');

    -- A new budget row for a category with spending (Charity, never budgeted): the client's 0 is
    -- replaced by the open cycle's spending; an earlier-cycle insert keeps what it was given.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source, is_settlement) VALUES
        ('49f00000-0000-0000-0000-000000000033', v_r, v_a, 300, 'Ehsan', 'OPEX-CHARITY', now(), 'chat', false),
        ('49f00000-0000-0000-0000-000000000034', v_r, v_a, 200, 'Ehsan (earlier)', 'OPEX-CHARITY', now() - interval '45 days', 'chat', false),
        ('49f00000-0000-0000-0000-000000000035', v_r, v_a, 50, 'Settlement', 'OPEX-CHARITY', now(), 'manual', true);
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active) VALUES
        (v_r, 'OPEX-CHARITY', v_m, v_k, 400, 0, true),
        (v_r, 'OPEX-CHARITY', v_pm, v_pk, 400, 0, true);
    PERFORM pg_temp.expect('new open-cycle row counts the cycle (settlement out)', pg_temp.spent(v_r, 'OPEX-CHARITY', v_k), '300.00');
    PERFORM pg_temp.expect('new earlier-cycle row as given', pg_temp.spent(v_r, 'OPEX-CHARITY', v_pk), '0.00');
    -- An inactive insert is not recomputed.
    INSERT INTO public.transactions (id, household_id, user_id, amount, merchant, category_code, timestamp, source) VALUES
        ('49f00000-0000-0000-0000-000000000036', v_r, v_a, 90, 'Takaful', 'OPEX-INSURANCE', now(), 'chat');
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active)
    VALUES (v_r, 'OPEX-INSURANCE', v_m, v_k, 0, 0, false);
    PERFORM pg_temp.expect('inactive insert takes nothing', pg_temp.spent(v_r, 'OPEX-INSURANCE', v_k), '0.00');
    -- Upsert that re-activates (ON CONFLICT DO UPDATE SET is_active), as PostgREST upserts do.
    INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount, is_active)
    VALUES (v_r, 'OPEX-INSURANCE', v_m, v_k, 250, 0, true)
    ON CONFLICT (household_id, month, category_code)
    DO UPDATE SET allocated_amount = EXCLUDED.allocated_amount, is_active = EXCLUDED.is_active;
    PERFORM pg_temp.expect('upsert re-activation counts the cycle', pg_temp.spent(v_r, 'OPEX-INSURANCE', v_k), '90.00');
    RAISE NOTICE 'PASSED: activation counts the open cycle of the category, other cycles untouched.';
END $$;

ROLLBACK;
