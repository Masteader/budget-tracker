-- ============================================================================
-- Account deletion branch: read-only checks for the live database.
--
-- Every statement here only reads. Run one section at a time in the SQL Editor, with
-- explicit user approval, and never as part of a migration. Each section says what a
-- bad result means.
-- ============================================================================


-- ── 1. void_income_record subtracted income twice (fixed by 20261105000500) ─────

-- 1a. Does the bug exist on this database? It does when both are true.
SELECT
    EXISTS (SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = 'public.income_records'::regclass
              AND t.tgname = 'trg_adjust_account_balance_on_income_change'
              AND t.tgenabled <> 'D') AS delete_trigger_subtracts,
    COALESCE(pg_get_functiondef(to_regprocedure('public.void_income_record(uuid)')) ~* 'UPDATE\s+public\.accounts', false)
        AS rpc_subtracts_too;

-- 1b. Was it ever called? Needs the pg_stat_statements extension, and only counts since
-- its last reset. Zero calls here does not prove none ever happened. API logs in the
-- Supabase dashboard also show POST /rest/v1/rpc/void_income_record, for their retention.
SELECT calls, left(query, 80) AS query
FROM pg_stat_statements
WHERE query ILIKE '%void_income_record%';

-- 1c. Accounts worth a closer look. This is a hint, not a finding, and it cannot say how
-- much was lost:
--   * A voided row is deleted, so a double subtraction leaves no record of its amount.
--   * There is no stored opening balance. implied_opening is what the opening balance would
--     have to be for today's balance to add up, and a negative one looks wrong.
--   * Manual edits (reconcile_account_balance), older direct updates and deleted members'
--     rows also move this figure, so a negative value has other explanations, and a double
--     subtraction on an account with a large real opening balance does not show at all.
-- Repair is the owner's decision. Nothing here changes a balance.
SELECT a.id, a.household_id, a.name, a.is_shared_pool, a.balance,
       COALESCE(i.income, 0) AS income,
       COALESCE(t.spent, 0) AS spent,
       COALESCE(x_in.amount, 0) AS transfers_in,
       COALESCE(x_out.amount, 0) AS transfers_out_with_fees,
       a.balance - COALESCE(i.income, 0) + COALESCE(t.spent, 0)
                 - COALESCE(x_in.amount, 0) + COALESCE(x_out.amount, 0) AS implied_opening
FROM public.accounts a
LEFT JOIN (SELECT account_id, sum(net_amount) AS income FROM public.income_records GROUP BY 1) i ON i.account_id = a.id
LEFT JOIN (SELECT account_id, sum(amount) AS spent FROM public.transactions WHERE account_id IS NOT NULL GROUP BY 1) t ON t.account_id = a.id
LEFT JOIN (SELECT to_account_id AS id, sum(amount) AS amount FROM public.account_transfers GROUP BY 1) x_in ON x_in.id = a.id
LEFT JOIN (SELECT from_account_id AS id, sum(amount + fee) AS amount FROM public.account_transfers GROUP BY 1) x_out ON x_out.id = a.id
WHERE a.balance - COALESCE(i.income, 0) + COALESCE(t.spent, 0)
                - COALESCE(x_in.amount, 0) + COALESCE(x_out.amount, 0) < 0
ORDER BY implied_opening ASC;
