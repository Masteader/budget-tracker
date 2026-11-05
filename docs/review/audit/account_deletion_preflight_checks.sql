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


-- ── 2. Anonymous access to inquiries and templates (fixed by 20261105000600) ─────

-- 2a. Every row is a finding: a policy naming anon or PUBLIC on these tables.
SELECT tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('inquiries', 'cost_control_templates')
  AND NOT (roles <@ ARRAY['authenticated', 'service_role']::name[]);

-- 2b. What each client role can do. After the fix: all false, except that authenticated
-- can select templates.
SELECT t.relname AS table_name, r.rolname AS role,
       has_table_privilege(r.rolname, t.oid, 'SELECT') AS can_select,
       has_table_privilege(r.rolname, t.oid, 'INSERT') AS can_insert,
       has_table_privilege(r.rolname, t.oid, 'UPDATE') AS can_update,
       has_table_privilege(r.rolname, t.oid, 'DELETE') AS can_delete,
       has_table_privilege(r.rolname, t.oid, 'TRUNCATE') AS can_truncate
FROM pg_class t
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
WHERE t.oid IN ('public.inquiries'::regclass, 'public.cost_control_templates'::regclass)
ORDER BY 1, 2;

-- 2c. Who can call the two RPCs. After the fix: both false for both.
SELECT p.oid::regprocedure AS function_name,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('replace_household_category', 'seed_household_default_taxonomy');

-- 2d. Did anyone use the anonymous door? Rows the backend wrote have a reference of 12 hex
-- characters and a source of web, landing or app. Anything else came from somewhere else.
SELECT source, type, count(*), min(created_at) AS first_seen, max(created_at) AS last_seen
FROM public.inquiries
WHERE reference !~ '^[0-9a-f]{12}$' OR source NOT IN ('web', 'landing', 'app')
GROUP BY 1, 2;


-- ── 3. Cross-household sub-category reads and client writes (fixed by 20261105000700) ──

-- 3a. Does the bug exist? It does when this returns the _select_autonomous policy, or any
-- policy that is not for SELECT.
SELECT policyname, cmd, roles, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'cost_control_sub_categories';

-- 3b. What clients can do. After the fix: anon nothing, authenticated select only.
SELECT r.rolname AS role,
       has_table_privilege(r.rolname, 'public.cost_control_sub_categories', 'SELECT') AS can_select,
       has_table_privilege(r.rolname, 'public.cost_control_sub_categories', 'INSERT') AS can_insert,
       has_table_privilege(r.rolname, 'public.cost_control_sub_categories', 'UPDATE') AS can_update,
       has_table_privilege(r.rolname, 'public.cost_control_sub_categories', 'DELETE') AS can_delete
FROM (VALUES ('anon'), ('authenticated')) AS r(rolname);

-- 3c. How many names were exposed. Counts only, because the names are private:
--   custom_parent: NULL-household rows under another household's custom category.
--   old_api_name: NULL-household 'sub-' rows under a system category. The fix hides these
--     from clients. Check the code before relying on the count: a row may be seeded on live
--     under a 'sub-' code that the repo does not have, which would then be hidden too.
SELECT
    count(*) FILTER (WHERE c.household_id IS NOT NULL) AS custom_parent,
    count(*) FILTER (WHERE c.household_id IS NULL AND s.sub_code LIKE 'sub-%') AS old_api_name,
    count(*) FILTER (WHERE c.household_id IS NULL AND s.sub_code NOT LIKE 'sub-%') AS catalog
FROM public.cost_control_sub_categories s
LEFT JOIN public.cost_control_codes c ON c.code = s.parent_code
WHERE s.household_id IS NULL;
