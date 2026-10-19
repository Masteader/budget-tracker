-- ============================================================================
-- Test 13 (audit DB-08 + cycle regression): transactions.cycle_key integrity
--
-- DB-08: trg_populate_transaction_cycle_key fires only on
--        UPDATE OF timestamp, household_id, so a client UPDATE that sets only
--        cycle_key keeps the forged value; update_budget_on_transaction_update
--        then moves the amount out of the real budget cycle (spent_amount drops
--        to 0 - overspending hidden).
-- Regression: exhaustive invariants for get_saudi_cycle_for_timestamp over
--        2026-2029 for every payday 1..31 (contiguous cycles, no gaps/overlap,
--        keys advance one month at a time), Asia/Riyadh midnight boundary,
--        leap years, Dec->Jan rollover, payday 29-31 clamping.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES ('d8000000-0000-0000-0000-000000000001', 'db08-member@test.local');
    INSERT INTO public.households (id, name, invite_code, payday_day)
    VALUES ('d8aa0000-0000-0000-0000-000000000001', 'DB08 Home', 'DB08HOMECODE0001', 27);
    UPDATE public.users SET household_id = 'd8aa0000-0000-0000-0000-000000000001', role = 'member'
    WHERE id = 'd8000000-0000-0000-0000-000000000001';

    INSERT INTO public.budgets (household_id, month, category_code, allocated_amount, cycle_key) VALUES
        ('d8aa0000-0000-0000-0000-000000000001', '2026-11-01', 'OPEX-GROCERY', 1000, '2026-11');
END $$;

-- 1. A client cannot relabel a transaction's cycle to hide spending
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "d8000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);
INSERT INTO public.transactions (id, household_id, user_id, amount, category_code, timestamp)
VALUES ('d8e00000-0000-0000-0000-000000000001', 'd8aa0000-0000-0000-0000-000000000001',
        'd8000000-0000-0000-0000-000000000001', 200, 'OPEX-GROCERY', '2026-11-05 12:00:00+03');
UPDATE public.transactions SET cycle_key = '1999-01' WHERE id = 'd8e00000-0000-0000-0000-000000000001';
RESET ROLE;

DO $$
DECLARE
    v_key text;
    v_spent numeric;
BEGIN
    SELECT cycle_key INTO v_key FROM public.transactions WHERE id = 'd8e00000-0000-0000-0000-000000000001';
    SELECT spent_amount INTO v_spent FROM public.budgets
    WHERE household_id = 'd8aa0000-0000-0000-0000-000000000001' AND cycle_key = '2026-11';
    IF v_key IS DISTINCT FROM '2026-11' OR v_spent <> 200 THEN
        RAISE EXCEPTION 'VULNERABILITY (DB-08): client relabelled cycle_key to % (budget spent now %)', v_key, v_spent;
    END IF;
    RAISE NOTICE 'PASSED: cycle_key is always recomputed from timestamp + household payday.';
END $$;

-- 2. Exhaustive cycle invariants (every payday 1..31, every day 2026-2029)
DO $$
DECLARE
    v_bad int;
BEGIN
    WITH days AS (
        SELECT d::date AS d, p
        FROM generate_series('2026-01-01'::date, '2029-12-31'::date, interval '1 day') d,
             generate_series(1, 31) p
    ), c AS (
        SELECT d, p, (public.get_saudi_cycle_for_timestamp((d + time '12:00') AT TIME ZONE 'Asia/Riyadh', p)).*
        FROM days
    ), l AS (
        SELECT *, lag(cycle_key) OVER w AS pk, lag(cycle_start) OVER w AS ps, lag(cycle_end) OVER w AS pe
        FROM c WINDOW w AS (PARTITION BY p ORDER BY d)
    )
    SELECT count(*) INTO v_bad
    FROM l
    WHERE NOT (cycle_start <= d AND d <= cycle_end)
       OR cycle_key IS NULL
       OR (pk = cycle_key AND (ps <> cycle_start OR pe <> cycle_end))
       OR (pk <> cycle_key AND (cycle_start <> pe + 1
                                OR to_char((pk || '-01')::date + interval '1 month', 'YYYY-MM') <> cycle_key));
    IF v_bad > 0 THEN
        RAISE EXCEPTION 'BUG: % day/payday combinations violate cycle invariants', v_bad;
    END IF;
    RAISE NOTICE 'PASSED: cycles are contiguous, non-overlapping and advance one key per month (payday 1..31, 2026-2029).';
END $$;

-- 3. Boundary cases
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('2026-10-26 20:59:59+00'::timestamptz, 27, '2026-10', '2026-09-27'::date, '2026-10-26'::date), -- 23:59:59 Riyadh on the 26th
            ('2026-10-26 21:00:00+00'::timestamptz, 27, '2026-11', '2026-10-27'::date, '2026-11-26'::date), -- 00:00 Riyadh on the 27th
            ('2026-10-28 12:00:00+03'::timestamptz, 27, '2026-11', '2026-10-27'::date, '2026-11-26'::date),
            ('2026-12-26 21:00:00+00'::timestamptz, 27, '2027-01', '2026-12-27'::date, '2027-01-26'::date), -- Dec -> Jan rollover
            ('2027-01-26 12:00:00+03'::timestamptz, 27, '2027-01', '2026-12-27'::date, '2027-01-26'::date),
            ('2027-02-28 12:00:00+03'::timestamptz, 31, '2027-03', '2027-02-28'::date, '2027-03-30'::date), -- payday 31 in Feb
            ('2027-02-27 12:00:00+03'::timestamptz, 31, '2027-02', '2027-01-31'::date, '2027-02-27'::date),
            ('2028-02-29 12:00:00+03'::timestamptz, 30, '2028-03', '2028-02-29'::date, '2028-03-29'::date), -- leap year
            ('2028-02-28 12:00:00+03'::timestamptz, 30, '2028-02', '2028-01-30'::date, '2028-02-28'::date),
            ('2026-04-30 12:00:00+03'::timestamptz, 31, '2026-05', '2026-04-30'::date, '2026-05-30'::date), -- 30-day month
            ('2026-10-01 00:30:00+03'::timestamptz, 1,  '2026-10', '2026-10-01'::date, '2026-10-31'::date),
            ('2026-09-30 21:30:00+00'::timestamptz, 1,  '2026-10', '2026-10-01'::date, '2026-10-31'::date)  -- UTC Sep 30, Riyadh Oct 1
        ) AS t(ts, payday, exp_key, exp_start, exp_end)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.get_saudi_cycle_for_timestamp(r.ts, r.payday) c
            WHERE c.cycle_key = r.exp_key AND c.cycle_start = r.exp_start AND c.cycle_end = r.exp_end
        ) THEN
            RAISE EXCEPTION 'BUG: cycle for % payday % expected % [% .. %], got %',
                r.ts, r.payday, r.exp_key, r.exp_start, r.exp_end,
                (SELECT row_to_json(c) FROM public.get_saudi_cycle_for_timestamp(r.ts, r.payday) c);
        END IF;
    END LOOP;
    RAISE NOTICE 'PASSED: Riyadh midnight, Dec->Jan, Feb/leap-year and payday 29-31 boundaries.';
END $$;

ROLLBACK;
