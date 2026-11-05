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
-- can select templates. Live has no templates table: this query then shows inquiries only.
SELECT t.relname AS table_name, r.rolname AS role,
       has_table_privilege(r.rolname, t.oid, 'SELECT') AS can_select,
       has_table_privilege(r.rolname, t.oid, 'INSERT') AS can_insert,
       has_table_privilege(r.rolname, t.oid, 'UPDATE') AS can_update,
       has_table_privilege(r.rolname, t.oid, 'DELETE') AS can_delete,
       has_table_privilege(r.rolname, t.oid, 'TRUNCATE') AS can_truncate
FROM pg_class t
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
WHERE t.oid IN (to_regclass('public.inquiries'), to_regclass('public.cost_control_templates'))
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


-- ── 4. What the account deletion design assumes about this database ────────────
-- Run before applying the 20261105 migrations, and 4d again after them.

-- 4a. Sign-in providers. Expect only 'email'. Any other provider breaks the assumption that
-- a typed password re-authenticates the user; an Apple sign-in would also need token
-- revocation at deletion. Stop and ask.
SELECT provider, count(*) AS identities
FROM auth.identities
GROUP BY provider
ORDER BY provider;

-- 4b. The recent-login check reads auth.sessions from a SECURITY DEFINER function owned by
-- whoever applies the migrations, and the purge reads auth.users the same way. Expect both
-- owner columns true. If either is false, requests or purges fail.
SELECT
    has_table_privilege('postgres', 'auth.sessions', 'SELECT') AS owner_reads_sessions,
    has_table_privilege('postgres', 'auth.users', 'SELECT') AS owner_reads_users,
    (SELECT count(*) FROM information_schema.columns
     WHERE table_schema = 'auth' AND table_name = 'sessions'
       AND column_name IN ('id', 'user_id', 'created_at')) AS session_columns_expect_3;

-- 4c. Foreign keys from storage.objects to auth.users, which can make the Auth Admin delete
-- fail or change what it leaves behind. Each row is worth reading before enabling the worker:
-- on_delete tells whether a deleted user's objects block the delete. The worker removes the
-- files through the Storage API first, but only those it queued.
SELECT c.conname, a.attname AS column_name,
       CASE c.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE'
                          WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END AS on_delete
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
WHERE c.contype = 'f'
  AND c.conrelid = 'storage.objects'::regclass
  AND c.confrelid = 'auth.users'::regclass;

-- 4d. Foreign key actions the purge relies on. The migration chain, not schema.sql, is the
-- truth, so live may differ. Every row returned is a mismatch: a missing or different action.
-- Before the migrations, expect exactly the four that 20261105000000 changes, plus
-- households.deletion_requested_by, which 20261105000100 adds. After them, expect no rows.
-- invite_attempt_log.user_id is not listed: the migration chain gives it no foreign key, and
-- the purge deletes those rows itself.
WITH expected(table_name, column_name, on_delete) AS (VALUES
    ('public.users', 'id', 'CASCADE'),
    ('public.api_quota', 'user_id', 'CASCADE'),
    ('public.transactions', 'user_id', 'SET NULL'),
    ('public.transactions', 'account_id', 'SET NULL'),
    ('public.transactions', 'nafaqah_spouse_id', 'SET NULL'),
    ('public.income_records', 'user_id', 'SET NULL'),
    ('public.income_records', 'account_id', 'RESTRICT'),
    ('public.account_transfers', 'user_id', 'SET NULL'),
    ('public.account_transfers', 'from_account_id', 'SET NULL'),
    ('public.account_transfers', 'to_account_id', 'SET NULL'),
    ('public.accounts', 'owner_user_id', 'CASCADE'),
    ('public.budgets', 'account_id', 'SET NULL'),
    ('public.households', 'owner_user_id', 'SET NULL'),
    ('public.households', 'nafaqah_provider_user_id', 'SET NULL'),
    ('public.households', 'deletion_requested_by', 'SET NULL'),
    ('public.household_memberships', 'user_id', 'CASCADE'),
    ('public.member_allowances', 'member_user_id', 'CASCADE'),
    ('public.member_allowances', 'set_by', 'SET NULL'),
    ('public.spouse_reimbursements', 'wife_user_id', 'CASCADE'),
    ('public.spouse_reimbursements', 'paid_by_user_id', 'SET NULL'),
    ('public.spouse_reimbursements', 'recorded_by', 'SET NULL'),
    ('public.household_dependents', 'linked_user_id', 'SET NULL'),
    ('public.household_invites', 'created_by', 'SET NULL'),
    ('public.household_invites', 'used_by', 'CASCADE')
), actual AS (
    SELECT c.conrelid, a.attname::text AS column_name,
           CASE c.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE'
                              WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END AS on_delete
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND array_length(c.conkey, 1) = 1
)
SELECT e.table_name, e.column_name, e.on_delete AS expected, x.on_delete AS actual
FROM expected e
LEFT JOIN actual x ON x.conrelid = to_regclass(e.table_name) AND x.column_name = e.column_name
WHERE x.on_delete IS DISTINCT FROM e.on_delete
ORDER BY 1, 2;

-- 4e. Rows that already have no creator. They get the "Deleted member" label too, though no
-- deletion happened, so a large count means existing households will see that label on old
-- rows the day the app ships. Counts only.
SELECT
    (SELECT count(*) FROM public.transactions WHERE user_id IS NULL) AS transactions_no_creator,
    (SELECT count(*) FROM public.transactions) AS transactions_total,
    (SELECT count(DISTINCT household_id) FROM public.transactions WHERE user_id IS NULL) AS households_affected;


-- ── 5. Which of the 2026102* to 202611* migrations this database has ──────────
-- Live has drifted from the migration chain: read-only checks on 2026-11-05 found no
-- cost_control_templates table and neither function of 20261026120000. Run this first,
-- before any of the 20261105 batch, to measure the gap. It only reads. Applying an older
-- migration that is missing is a separate decision for the owner, not part of this rollout.
--
-- One row per migration. The objects are what each file creates: tables, views, functions,
-- policies, triggers, indexes, added or renamed columns, added constraints and enum values,
-- listed from the files on 2026-11-05. in_full_chain says whether the object still exists
-- after a clean rebuild of the whole chain: false means a later migration removed it on
-- purpose, so its absence here is expected.
--
--   expected       objects that exist after the whole chain
--   present_here   how many of those exist on this database
--   missing_here   which of those are missing. Before the 20261105 batch, expect all of its
--                  objects listed here. Elsewhere, a file with most of its objects missing was
--                  probably never applied.
--   removed_later_but_present  objects a later migration removes, still here. A hint that
--                  the later migration did not run.
--
-- Limits: a function is checked by name only, and a CREATE OR REPLACE of a function that
-- already existed proves nothing, so tables, columns, policies and indexes are the better
-- evidence. Three files create none of these and cannot be detected here:
-- 20261020070000_audit_definer_search_path_and_household_insert,
-- 20261020080000_audit_receipts_bucket_limits and 20261020500000_review_lock_financial_role.
-- Compare their function definitions and grants by hand if it matters.
WITH created(migration, kind, object_name, on_table, in_full_chain) AS (VALUES
    ('20261020005000_preflight_live_alignment', 'column', 'rollover_rule', 'households', True),
    ('20261020010000_audit_invites_rls_and_targeted_claims', 'function', 'validate_invite_target_member', NULL, True),
    ('20261020010000_audit_invites_rls_and_targeted_claims', 'function', 'join_household_by_code', NULL, True),
    ('20261020010000_audit_invites_rls_and_targeted_claims', 'function', 'claim_household_role_invite', NULL, True),
    ('20261020010000_audit_invites_rls_and_targeted_claims', 'trigger', 'trg_validate_invite_target_member', 'household_invites', True),
    ('20261020020000_audit_membership_policy_recursion', 'function', 'is_household_admin', NULL, True),
    ('20261020020000_audit_membership_policy_recursion', 'function', 'get_auth_user_household_id', NULL, True),
    ('20261020020000_audit_membership_policy_recursion', 'function', 'get_auth_user_role', NULL, True),
    ('20261020020000_audit_membership_policy_recursion', 'policy', 'memberships_select_own_or_admin', 'household_memberships', True),
    ('20261020030000_audit_reallocate_budget_authz', 'function', 'reallocate_budget', NULL, True),
    ('20261020040000_audit_cost_control_codes_policies', 'policy', 'cost_control_codes_insert', 'cost_control_codes', True),
    ('20261020040000_audit_cost_control_codes_policies', 'policy', 'cost_control_codes_update', 'cost_control_codes', True),
    ('20261020050000_audit_ledger_precision_and_income_append_only', 'function', 'transfer_between_accounts', NULL, True),
    ('20261020050000_audit_ledger_precision_and_income_append_only', 'function', 'record_income', NULL, True),
    ('20261020060000_audit_transaction_cycle_key_integrity', 'trigger', 'trg_populate_transaction_cycle_key', 'transactions', True),
    ('20261020090000_audit_sole_admin_account_deletion', 'function', 'handover_households_on_user_delete', NULL, True),
    ('20261020090000_audit_sole_admin_account_deletion', 'trigger', 'trg_handover_households_on_user_delete', 'users', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'transactions_select_household', 'transactions', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'transactions_insert_household', 'transactions', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'transactions_update_household', 'transactions', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'transactions_delete_household', 'transactions', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'budgets_select_household', 'budgets', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'budgets_insert_admin', 'budgets', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'budgets_update_admin', 'budgets', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'accounts_select', 'accounts', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'accounts_insert_personal', 'accounts', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'accounts_insert_shared', 'accounts', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'accounts_update_personal', 'accounts', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'accounts_update_shared', 'accounts', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'accounts_delete_admin_or_owner', 'accounts', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'transfers_select_household', 'account_transfers', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'income_select_household', 'income_records', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'households_select_own', 'households', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'households_update_admin', 'households', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'users_select_household', 'users', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'users_insert_own', 'users', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'users_update_own_profile', 'users', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'invites_select_household', 'household_invites', False),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'invites_insert_household', 'household_invites', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'invites_delete_admin', 'household_invites', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'cost_control_codes_select', 'cost_control_codes', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'household_category_settings_all', 'household_category_settings', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'dependents_select_household', 'household_dependents', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'dependents_delete_household', 'household_dependents', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'dependents_insert_household', 'household_dependents', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'dependents_update_household', 'household_dependents', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'Allow household members full access to installment_plans', 'installment_plans', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'receipts_insert_household', 'storage.objects', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'receipts_select_household', 'storage.objects', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'policy', 'receipts_delete_household', 'storage.objects', True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_transactions_reallocated_from_budget', NULL, True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_household_invites_household', NULL, True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_household_invites_created_by', NULL, True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_household_invites_used_by', NULL, True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_account_transfers_user', NULL, True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_income_records_user', NULL, True),
    ('20261020100000_audit_rls_initplan_and_fk_indexes', 'index', 'idx_invite_attempt_log_user_time', NULL, True),
    ('20261020200000_remove_sms_artifacts', 'constraint', 'transactions_source_check', 'transactions', True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'table', 'member_allowances', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'table', 'spouse_reimbursements', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'nafaqah_is_spouse_member', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'nafaqah_husband_id', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'validate_transaction_nafaqah_class', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'nafaqah_resolve_actor', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'nafaqah_require_member', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'nafaqah_current_cycle_key', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'get_member_allowance_status', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'set_member_allowance', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'get_spouse_reimbursement_balance', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'function', 'record_spouse_reimbursement', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'policy', 'member_allowances_select_household', 'member_allowances', True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'policy', 'spouse_reimbursements_select_household', 'spouse_reimbursements', True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'trigger', 'trg_validate_transaction_nafaqah_class', 'transactions', True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_transactions_nafaqah_spouse', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_member_allowances_member', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_member_allowances_set_by', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_spouse_reimbursements_household_wife', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_spouse_reimbursements_wife', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_spouse_reimbursements_paid_by', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'index', 'idx_spouse_reimbursements_recorded_by', NULL, True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'column', 'nafaqah_class', 'transactions', True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'column', 'nafaqah_spouse_id', 'transactions', True),
    ('20261020300000_nafaqah_wife_allowance_and_reimbursements', 'constraint', 'transactions_nafaqah_class_check', 'transactions', True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'household_resolve_actor', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'household_member_role', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'household_primary_admin_id', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'protect_primary_admin_membership', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'maintain_household_primary_admin', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'get_household_members', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'household_apply_role', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'household_require_admin', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'promote_member_to_admin', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'revoke_admin', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'transfer_primary_admin', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'set_member_role', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'remove_member', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'get_user_households', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'bind_transaction_creator', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'enforce_transaction_write_permission', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'transaction_account_matches', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'transaction_personal_account_writable', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'update_account_balance_on_transaction', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'transfer_between_accounts', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'function', 'nafaqah_husband_id', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'policy', 'transactions_insert_household', 'transactions', True),
    ('20261020400000_admin_permissions_and_co_admins', 'policy', 'transactions_update_household', 'transactions', True),
    ('20261020400000_admin_permissions_and_co_admins', 'policy', 'transactions_delete_household', 'transactions', True),
    ('20261020400000_admin_permissions_and_co_admins', 'trigger', 'trg_protect_primary_admin', 'household_memberships', True),
    ('20261020400000_admin_permissions_and_co_admins', 'trigger', 'trg_maintain_primary_admin', 'household_memberships', True),
    ('20261020400000_admin_permissions_and_co_admins', 'trigger', 'trg_bind_transaction_creator', 'transactions', True),
    ('20261020400000_admin_permissions_and_co_admins', 'trigger', 'trg_enforce_transaction_write_permission', 'transactions', True),
    ('20261020400000_admin_permissions_and_co_admins', 'index', 'idx_households_owner_user_id', NULL, True),
    ('20261020400000_admin_permissions_and_co_admins', 'column', 'owner_user_id', 'households', True),
    ('20261020600000_e2e_helper_rpcs_and_sub_category_visibility', 'policy', 'cost_control_sub_categories_select_visible_parent', 'cost_control_sub_categories', False),
    ('20261020700000_fable_db_hardening', 'function', 'reallocate_budget', NULL, True),
    ('20261020700000_fable_db_hardening', 'constraint', 'household_invites_created_by_fkey', 'household_invites', True),
    ('20261020700000_fable_db_hardening', 'constraint', 'household_invites_used_by_fkey', 'household_invites', True),
    ('20261020750000_installment_pay_atomic', 'function', 'pay_installment_plan', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'household_member_financial_role', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'household_default_financial_role', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'membership_financial_role_rules', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'membership_financial_role_cache', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'clear_nafaqah_provider_on_membership_end', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'households_nafaqah_provider_rules', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'nafaqah_is_spouse_member', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'nafaqah_husband_id', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'validate_transaction_nafaqah_class', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'get_household_members', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'sync_user_household_membership', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'switch_active_household', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'create_household_and_claim', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'join_household_by_code', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'claim_household_role_invite', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'refuse_invite_claim_by_member', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'set_nafaqah_provider', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'transfer_primary_admin', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'guard_wife_reimbursable_ledger', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'update_budget_on_transaction', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'update_budget_on_transaction_delete', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'update_budget_on_transaction_update', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'recompute_budget_spent', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'rekey_household_cycles', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'function', 'rekey_cycles_on_payday_change', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'policy', 'invites_select_admin', 'household_invites', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_membership_financial_role_rules', 'household_memberships', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_membership_financial_role_cache', 'household_memberships', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_clear_nafaqah_provider', 'household_memberships', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_households_nafaqah_provider', 'households', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_refuse_invite_claim_by_member', 'household_invites', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_wife_ledger_guard', 'transactions', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'trigger', 'trg_rekey_cycles_on_payday_change', 'households', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'index', 'idx_households_nafaqah_provider', NULL, True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'column', 'financial_role', 'household_memberships', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'constraint', 'household_memberships_financial_role_check', 'household_memberships', True),
    ('20261020800000_household_roles_and_nafaqah_integrity', 'column', 'nafaqah_provider_user_id', 'households', True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'household_financial_role_allowed', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'household_default_financial_role', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'membership_financial_role_rules', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'households_nafaqah_provider_rules', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'maintain_household_primary_admin', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'nafaqah_husband_id', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'validate_transaction_nafaqah_class', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'guard_wife_reimbursable_ledger', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'remove_nafaqah_ledger_on_membership_end', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'update_budget_on_transaction', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'update_budget_on_transaction_delete', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'update_budget_on_transaction_update', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'create_household_and_claim', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'join_household_by_code', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'claim_household_role_invite', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'set_nafaqah_provider', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'transfer_primary_admin', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'set_household_type', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'set_member_financial_role', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'function', 'pay_installment_plan', NULL, True),
    ('20261020900000_household_type_and_round2_fixes', 'trigger', 'trg_membership_financial_role_rules', 'household_memberships', True),
    ('20261020900000_household_type_and_round2_fixes', 'trigger', 'trg_households_nafaqah_provider', 'households', True),
    ('20261020900000_household_type_and_round2_fixes', 'trigger', 'trg_remove_nafaqah_ledger_on_membership_end', 'household_memberships', True),
    ('20261020900000_household_type_and_round2_fixes', 'column', 'household_type', 'households', True),
    ('20261020900000_household_type_and_round2_fixes', 'constraint', 'households_household_type_check', 'households', True),
    ('20261020900000_household_type_and_round2_fixes', 'constraint', 'installment_plans_paid_installments_range', 'installment_plans', True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'function', 'installment_next_due_at', NULL, True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'function', 'installment_plans_schedule', NULL, True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'function', 'pay_installment_plan', NULL, True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'trigger', 'trg_installment_plans_schedule', 'installment_plans', True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'index', 'idx_installment_plans_next_due', NULL, True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'column', 'frequency', 'installment_plans', True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'column', 'next_due_at', 'installment_plans', True),
    ('20261021000000_saudi_taxonomy_and_bnpl_schedule', 'constraint', 'installment_plans_frequency_check', 'installment_plans', True),
    ('20261024000000_create_inquiries_table', 'table', 'inquiries', NULL, True),
    ('20261024000000_create_inquiries_table', 'policy', 'Allow anonymous and authenticated insert into inquiries', 'inquiries', False),
    ('20261024000000_create_inquiries_table', 'index', 'idx_inquiries_email_type', NULL, True),
    ('20261024000000_create_inquiries_table', 'index', 'idx_inquiries_created_at', NULL, True),
    ('20261024000000_create_inquiries_table', 'index', 'idx_inquiries_reference', NULL, True),
    ('20261026000000_add_savings_account_type', 'constraint', 'accounts_account_type_check', 'accounts', True),
    ('20261026120000_household_autonomous_taxonomy', 'table', 'cost_control_templates', NULL, True),
    ('20261026120000_household_autonomous_taxonomy', 'function', 'replace_household_category', NULL, True),
    ('20261026120000_household_autonomous_taxonomy', 'function', 'seed_household_default_taxonomy', NULL, True),
    ('20261026120000_household_autonomous_taxonomy', 'policy', 'cost_control_templates_select', 'cost_control_templates', True),
    ('20261026120000_household_autonomous_taxonomy', 'policy', 'cost_control_sub_categories_select_autonomous', 'cost_control_sub_categories', False),
    ('20261026120000_household_autonomous_taxonomy', 'policy', 'cost_control_sub_categories_insert', 'cost_control_sub_categories', False),
    ('20261026120000_household_autonomous_taxonomy', 'policy', 'cost_control_sub_categories_update', 'cost_control_sub_categories', False),
    ('20261026120000_household_autonomous_taxonomy', 'policy', 'cost_control_sub_categories_delete', 'cost_control_sub_categories', False),
    ('20261026120000_household_autonomous_taxonomy', 'index', 'idx_sub_categories_hh_parent', NULL, True),
    ('20261026120000_household_autonomous_taxonomy', 'column', 'household_id', 'cost_control_sub_categories', True),
    ('20261101000000_nafaqah_wife_no_account', 'constraint', 'transactions_wife_class_no_account', 'transactions', False),
    ('20261101000100_nafaqah_wife_account_owner_guard', 'function', 'enforce_wife_class_account', NULL, True),
    ('20261101000100_nafaqah_wife_account_owner_guard', 'trigger', 'trg_enforce_wife_class_account', 'transactions', True),
    ('20261102000000_cleanup_database_jargon_and_zombie_columns', 'column', 'notes', 'transactions', True),
    ('20261102010000_void_income_record_rpc', 'function', 'void_income_record', NULL, True),
    ('20261105000000_account_deletion_ledger_fks', 'function', 'handover_households_on_user_delete', NULL, True),
    ('20261105000000_account_deletion_ledger_fks', 'constraint', 'income_records_user_id_fkey', 'income_records', True),
    ('20261105000000_account_deletion_ledger_fks', 'constraint', 'account_transfers_user_id_fkey', 'account_transfers', True),
    ('20261105000000_account_deletion_ledger_fks', 'constraint', 'account_transfers_from_account_id_fkey', 'account_transfers', True),
    ('20261105000000_account_deletion_ledger_fks', 'constraint', 'account_transfers_to_account_id_fkey', 'account_transfers', True),
    ('20261105000100_account_deletion_schema', 'table', 'account_deletion_requests', NULL, True),
    ('20261105000100_account_deletion_schema', 'table', 'account_deletion_storage_queue', NULL, True),
    ('20261105000100_account_deletion_schema', 'table', 'account_deletion_worker_runs', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'account_deletion_user_pending', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'account_deletion_guard_membership', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'account_deletion_guard_invite', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'account_deletion_guard_provider', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'account_deletion_clear_marks_on_membership_end', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'handover_households_on_user_delete', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'maintain_household_primary_admin', NULL, True),
    ('20261105000100_account_deletion_schema', 'function', 'transfer_primary_admin', NULL, True),
    ('20261105000100_account_deletion_schema', 'trigger', 'trg_account_deletion_guard_membership', 'household_memberships', True),
    ('20261105000100_account_deletion_schema', 'trigger', 'trg_account_deletion_guard_invite', 'household_invites', True),
    ('20261105000100_account_deletion_schema', 'trigger', 'trg_account_deletion_guard_provider', 'households', True),
    ('20261105000100_account_deletion_schema', 'trigger', 'trg_account_deletion_clear_marks', 'household_memberships', True),
    ('20261105000100_account_deletion_schema', 'index', 'uq_account_deletion_requests_active_user', NULL, True),
    ('20261105000100_account_deletion_schema', 'index', 'idx_account_deletion_requests_user', NULL, True),
    ('20261105000100_account_deletion_schema', 'index', 'idx_account_deletion_requests_due', NULL, True),
    ('20261105000100_account_deletion_schema', 'index', 'idx_households_deletion_requested_by', NULL, True),
    ('20261105000100_account_deletion_schema', 'column', 'deletion_requested_at', 'households', True),
    ('20261105000100_account_deletion_schema', 'column', 'deletion_scheduled_for', 'households', True),
    ('20261105000100_account_deletion_schema', 'column', 'deletion_requested_by', 'households', True),
    ('20261105000100_account_deletion_schema', 'constraint', 'inquiries_type_check', 'inquiries', True),
    ('20261105000200_account_deletion_rpcs', 'function', 'account_deletion_recent_login_ok', NULL, True),
    ('20261105000200_account_deletion_rpcs', 'function', 'account_deletion_household_positions', NULL, True),
    ('20261105000200_account_deletion_rpcs', 'function', 'account_deletion_status_json', NULL, True),
    ('20261105000200_account_deletion_rpcs', 'function', 'get_account_deletion_status', NULL, True),
    ('20261105000200_account_deletion_rpcs', 'function', 'get_account_deletion_preflight', NULL, True),
    ('20261105000200_account_deletion_rpcs', 'function', 'request_account_deletion', NULL, True),
    ('20261105000200_account_deletion_rpcs', 'function', 'cancel_account_deletion', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'account_deletion_require_service', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'account_deletion_repoint_active_household', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'account_deletion_note_token', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'account_deletion_scrub_own_note', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'account_deletion_scrub_other_note', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'account_deletion_scrub_items', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'claim_due_account_deletions', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'prepare_account_purge', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'list_account_purge_storage', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'mark_account_purge_storage_done', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'complete_account_purge', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'record_account_purge_failure', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'list_account_deletion_notices_due', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'mark_account_deletion_notice_sent', NULL, True),
    ('20261105000300_account_deletion_purge', 'function', 'record_account_deletion_worker_run', NULL, True),
    ('20261105000400_account_deletion_worker_support', 'function', 'get_account_deletion_queue_summary', NULL, True),
    ('20261105000400_account_deletion_worker_support', 'function', 'list_account_deletion_alerts_due', NULL, True),
    ('20261105000400_account_deletion_worker_support', 'function', 'purge_expired_account_deletion_inquiries', NULL, True),
    ('20261105000400_account_deletion_worker_support', 'function', 'list_account_deletion_notices_due', NULL, True),
    ('20261105000400_account_deletion_worker_support', 'function', 'mark_account_deletion_notice_sent', NULL, True),
    ('20261105000500_void_income_single_subtraction', 'function', 'void_income_record', NULL, True),
    ('20261105000600_limit_anonymous_contact_form', 'policy', 'cost_control_templates_select', 'cost_control_templates', True),
    ('20261105000700_sub_categories_household_scope', 'policy', 'cost_control_sub_categories_select_scoped', 'cost_control_sub_categories', True),
    ('20261105000800_account_deletion_operator_request', 'function', 'account_deletion_schedule', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'account_deletion_cancel', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'request_account_deletion', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'cancel_account_deletion', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'account_deletion_require_operator_handle', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'get_account_deletion_operator_preview', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'schedule_account_deletion_by_operator', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'cancel_account_deletion_by_operator', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'function', 'complete_account_purge', NULL, True),
    ('20261105000800_account_deletion_operator_request', 'column', 'initiated_by', 'account_deletion_requests', True),
    ('20261105000800_account_deletion_operator_request', 'column', 'operator_inquiry_reference', 'account_deletion_requests', True),
    ('20261105000800_account_deletion_operator_request', 'column', 'operator_verified_by', 'account_deletion_requests', True),
    ('20261105000800_account_deletion_operator_request', 'column', 'operator_cancelled_by', 'account_deletion_requests', True),
    ('20261105000800_account_deletion_operator_request', 'column', 'operator_cancel_reference', 'account_deletion_requests', True),
    ('20261105000800_account_deletion_operator_request', 'constraint', 'account_deletion_requests_operator_recorded', 'account_deletion_requests', True),
    ('20261105000800_account_deletion_operator_request', 'constraint', 'account_deletion_requests_user_has_no_operator', 'account_deletion_requests', True),
    ('20261105000900_account_deletion_notice_windows', 'function', 'list_account_deletion_notices_due', NULL, True),
    ('20261105001000_inactive_category_budgets', 'function', 'budget_spent_from_transactions', NULL, True),
    ('20261105001000_inactive_category_budgets', 'function', 'budget_activation_counts_open_cycle', NULL, True),
    ('20261105001000_inactive_category_budgets', 'trigger', 'trg_budget_activation_counts_open_cycle', 'budgets', True)
), checked AS (
    SELECT c.*,
           CASE c.kind
               WHEN 'table' THEN to_regclass('public.' || c.object_name) IS NOT NULL
               WHEN 'view' THEN to_regclass('public.' || c.object_name) IS NOT NULL
               WHEN 'index' THEN to_regclass('public.' || c.object_name) IS NOT NULL
               WHEN 'function' THEN EXISTS (SELECT 1 FROM pg_proc p
                                            WHERE p.pronamespace = 'public'::regnamespace AND p.proname = c.object_name)
               WHEN 'policy' THEN EXISTS (SELECT 1 FROM pg_policies p
                                          WHERE p.schemaname || '.' || p.tablename
                                                = CASE WHEN c.on_table LIKE '%.%' THEN c.on_table ELSE 'public.' || c.on_table END
                                            AND p.policyname = c.object_name)
               WHEN 'trigger' THEN EXISTS (SELECT 1 FROM pg_trigger t
                                           WHERE t.tgrelid = to_regclass(CASE WHEN c.on_table LIKE '%.%' THEN c.on_table
                                                                              ELSE 'public.' || c.on_table END)
                                             AND t.tgname = c.object_name AND NOT t.tgisinternal)
               WHEN 'column' THEN EXISTS (SELECT 1 FROM information_schema.columns k
                                          WHERE k.table_schema = 'public' AND k.table_name = c.on_table
                                            AND k.column_name = c.object_name)
               WHEN 'constraint' THEN EXISTS (SELECT 1 FROM pg_constraint k
                                              WHERE k.conrelid = to_regclass('public.' || c.on_table)
                                                AND k.conname = c.object_name)
               WHEN 'enum_value' THEN EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                                              WHERE t.typname = c.on_table AND e.enumlabel = c.object_name)
           END AS present
    FROM created c
)
SELECT migration,
       count(*) FILTER (WHERE in_full_chain) AS expected,
       count(*) FILTER (WHERE in_full_chain AND present) AS present_here,
       string_agg(kind || ' ' || COALESCE(on_table || '.', '') || object_name, ', ' ORDER BY kind, object_name)
           FILTER (WHERE in_full_chain AND NOT present) AS missing_here,
       string_agg(kind || ' ' || COALESCE(on_table || '.', '') || object_name, ', ' ORDER BY kind, object_name)
           FILTER (WHERE NOT in_full_chain AND present) AS removed_later_but_present
FROM checked
GROUP BY migration
ORDER BY migration;
