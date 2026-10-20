# Live database pre-flight for the 20261020 audit batch

Date: 2026-10-20 · Branch: `audit/claude-comprehensive-review` (from `8971d4a`) · Related: [`db.md`](db.md) (DB-15), [`MASTER_AUDIT_REPORT.md`](MASTER_AUDIT_REPORT.md) §6.2

This document covers the 13 new migrations (`supabase/migrations/20261020010000_*` to `20261020400000_*`) and one pre-flight migration added by this review (`20261020005000_preflight_live_alignment.sql`). It answers four questions before the owner applies them to the live Supabase project:

- How does live differ from the repository?
- Do the migrations apply cleanly to a faithful copy of live?
- Does the database test suite pass there?
- In what order, and how, should the files be applied?

Live was only read. Access was a read-only Management API role (`read_only=true`, connected as `supabase_read_only_user`) that ran catalog queries and aggregate `count(*)` queries. No DDL or DML was sent, no row was copied, and nothing was written to live.

## 1. Verdict

> **Status (2026-10-20): applied to live.** Backup taken (read-only JSON export of all `public` tables and `storage.buckets`), part A matched §4, the 14 files ran in order without error, part B matched §7, and the versions were recorded in `supabase_migrations.schema_migrations` (§5.3).

**Safe to apply: yes**, under these conditions:

1. Apply the 14 files one at a time, in the order of §5, starting with the pre-flight migration.
2. Deploy the backend (ai_service) only after the last file. Release the new app build after that.

Why it is safe:

- **Everything applied cleanly.** All 14 files applied without error to a replica of live built from live's own catalog. That replica:
  - matches live on every table, column, constraint, index, policy, function body, EXECUTE grant, trigger, table and column grant, bucket setting and realtime table;
  - was owned by a non-superuser `BYPASSRLS` role, as live's `postgres` is;
  - held synthetic data that matches 49 of live's 50 aggregate counts. The one exception is the row count of the backup table (D8), which no migration reads.
- **All tests passed.** The full DB suite passes on the migrated replica: **20/20** with live-shaped data, **20/20** on an empty replica, and **20/20** on a repo rebuild.
- **No money moves.** Budget `spent_amount` totals and account balances are identical before and after.
- **No existing row breaks a new constraint.** See the counts in §4.
- **No privilege is missing.** Live's `postgres` owns every object the batch alters. It may create policies on `storage.objects` (`supautils.policy_grants` includes it) and may `UPDATE storage.buckets`. The storage triggers fire only on the bucket `name` and lifecycle columns, which the batch does not touch.
- **There is a tested rollback.** [`../rollback/20261020_audit_batch_rollback_snapshot.sql`](../rollback/20261020_audit_batch_rollback_snapshot.sql) returns the replica's catalog exactly to live's pre-batch state. Re-applying the batch afterwards passes 20/20 again.

The first replica run found one problem, now fixed. Test 14 (catalog guardrails) failed because live has functions in `public` that `anon` can execute and the repository does not:

- the `unaccent` extension functions (live installs the extension into `public`);
- `rls_auto_enable()`, the function behind the platform's `ensure_rls` event trigger.

The fix is in §6. With it, the result is 20/20.

Known consequences, all expected:

- **Legacy transactions become admin-only.** All **14** live transactions have no recorded creator (`user_id IS NULL`). After `20261020400000` only household admins can edit or delete them. The owner decided on 2026-10-20 to keep this. One non-admin member (a `family_member` in a household with an admin) loses the ability to edit those legacy rows.
- **One household has no primary admin.** One household has no members at all. It gets no primary admin (`owner_user_id` stays `NULL`). The other 3 get their single admin.
- **SMS labels change.** The 10 `source = 'sms'` rows are relabelled to 8 `chat` and 2 `receipt_scan`, with 0 `manual`. Only the label changes: no amount or budget is touched, and the app already displayed these rows this way.
- **Existing receipts are not rechecked.** Two existing receipt objects (`text/plain`, `application/octet-stream`) do not match the new bucket MIME list. Bucket limits apply only to new uploads, so they stay readable.

## 2. Method

| Step | What | Tool (all in this repo or reproducible) |
|---|---|---|
| Live inventory | `schema_migrations`; for `public`: tables, columns (type, default, nullability, generated), constraints (`pg_get_constraintdef`), indexes (`pg_get_indexdef`), RLS flags, `pg_policies` (`public`, `storage`), functions (`pg_get_functiondef`, `SECURITY DEFINER`, `proconfig`, EXECUTE for anon/authenticated/service_role), triggers (`public` + `auth.users`), views, types, table and column ACLs, owners, default ACLs, `storage.buckets`, publications, extensions, event triggers, supautils settings | Read-only catalog SELECTs |
| Repo baseline | Stubs + `schema.sql` + `seed.sql` + every migration before `20261020`, then the same inventory | `run_tests.py --psql --rebuild --stop-before 20261020005000 --no-tests --db bt_repo_baseline` |
| Diff | Keyed comparison (table, column, constraint name, policy, function signature, …) | §3 |
| Replica | DDL generated from the live inventory, applied after `supabase/tests/00_local_supabase_stubs.sql`; public objects owned by a non-superuser `BYPASSRLS` role standing in for live `postgres` (member of anon/authenticated/service_role); live's `ensure_rls` event trigger and `unaccent`-in-`public` reproduced | Diff against live afterwards: only platform-only rows differ (§3.4) |
| Live-shaped data | Invented rows matching every aggregate in §4 except the backup table's row count (4 households including the orphan, 14 creator-less transactions with the same `sms` note buckets, 39 receipt objects, …) | No live rows copied |
| Apply + test | Each file applied as the owner role (`SET ROLE`), then `run_tests.py --psql --db <replica>`; also `run_tests.py --psql --apply-from 20261020005000 --db <replica>` | §6 |

Local server: PostgreSQL 16.15. Live: PostgreSQL 17.6. Nothing in the batch depends on the version. The only catalog difference is the PG17 `MAINTAIN` table privilege, which is ignored in the diff.

## 3. Live vs repository drift

Classification:

- **(a)** affects one of the 14 files;
- **(b)** harmless drift;
- **(c)** live has something the repository lacks and must capture.

### 3.1 Schema objects

| # | Drift (live vs repo baseline before `20261020`) | Class | Effect on the batch / action |
|---|---|---|---|
| D1 | `public.reallocate_budget(uuid,uuid,numeric)` **does not exist on live**, although `schema.sql` defines it. Today ai_service falls back to a two-step update (`ai_service/supabase_client.py:276`). | (a) `20261020030000` | `CREATE OR REPLACE` creates it with the admin/service-role checks. Its REVOKE/GRANT run after the create. Verified. |
| D2 | `household_invites` already has RLS **enabled** on live. | (a) `20261020010000` §1 | `ENABLE ROW LEVEL SECURITY` is a no-op. The rest of the file applies. |
| D3 | `memberships_admin_manage` (the recursive policy, DB-02) **is absent** on live. | (a) `20261020020000` §2 | `DROP POLICY IF EXISTS` is a no-op. The recursion was never live. |
| D4 | `cost_control_codes_insert` / `_update` / `_delete` policies **are absent** on live (only `_select` exists), so clients cannot write custom categories today. | (a) `20261020040000` | Creates the admin-only insert/update policies. Household admins gain the intended ability. |
| D5 | `transactions` has **no CHECK on `source`** on live (the repo has one that includes `sms`). Live labels: `sms` 10, `chat` 3, `receipt_scan` 1. | (a) `20261020200000` | The DO-loop finds nothing to drop, then adds `transactions_source_check (chat, receipt_scan, manual)`. All 14 rows satisfy it after the relabel. |
| D6 | `transactions_spent_by_check` (`me`/`partner`/`both`) **is absent** on live. All 14 live rows are valid. | (b) | Not touched by the batch. Deliberately not added in the pre-flight: the receipt scanner forwards the model's `spent_by` lower-cased, and today live accepts any value. Add it only after the API normalises `spent_by`. |
| D7 | `households.rollover_rule text DEFAULT 'accumulate'` **exists only on live**. All 4 rows are `accumulate`. ai_service reads and writes it (`get_/set_household_rollover_rule`) and treats unknown values as `send_to_savings`. | (c) | **Captured** by `20261020005000` (`ADD COLUMN IF NOT EXISTS`, same default; a no-op on live). `20261020400000` builds its column-list `UPDATE` grant from the live column list, so `rollover_rule` stays client-updatable for admins as today. The default `accumulate` is not a value the app recognises; whether to change it is a product decision. |
| D8 | `public.budgets_spent_backup_20261019` **exists only on live**: 24 rows, RLS on, no policies. It was created by `supabase/backups/backup_budgets_spent_amount.sql`. | (b) | Not captured: it is a one-off backup. RLS hides its rows from clients. Drop it once the 2026-10-19 recompute is confirmed (owner). |
| D9 | `public.rls_auto_enable()` + event trigger `ensure_rls` **exist only on live**. This is the platform feature that enables RLS on every new `public` table. The function keeps the default EXECUTE for `PUBLIC`, so `anon` can execute it. | (c), test 14 | **Handled** by `20261020005000`: `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated` (guarded; the function is owned by `postgres`). An event-trigger function cannot be called directly, and the event trigger still fires after the revoke (verified on the replica with a non-superuser `CREATE TABLE`). The two new tables of `20261020300000` get RLS from the migration either way. |
| D10 | The `unaccent` extension is installed in **`public`** on live (`extensions` in the repo stubs). Its 4 functions are anon-executable and owned by `supabase_admin`, so `postgres` can neither revoke nor relocate them. | (b), test 14 | Test 14 now skips extension member functions (`pg_depend.deptype = 'e'`); they are not app RPCs. |
| D11 | Function bodies differ only in comments (`consume_quota`, `get_saudi_cycle_for_timestamp`) or CRLF line endings (`get_auth_user_household_id`, `get_auth_user_role`). Signatures, `SECURITY DEFINER`, `search_path` and grants are identical. | (b) | `20261020020000` replaces the two helpers anyway. |
| D12 | Five column comments are missing on live (`budgets.sub_allocations`, `households.monthly_income`, `households.payday_day`, `transactions.qr_code_raw`, `users.payday_day`), and the old SMS wording remains on the `transactions`, `transactions.raw_sms` and `cost_control_codes` comments. | (b) | `20261020200000` rewrites the SMS comments. The five missing ones are cosmetic. |
| D13 | Table grants are identical apart from PG17 `MAINTAIN`. Column grants (`accounts` ×7, `users` ×3) and storage policies (`receipts_*` ×3) are identical. Triggers (11 on `public` + `on_auth_user_created` on `auth.users`) and indexes (64) are identical. | (b) | None. |

### 3.2 Reference data (counts and taxonomy codes only)

| # | Drift | Class | Action |
|---|---|---|---|
| R1 | Live has an extra **system** category `OPEX-TESTING` (`is_system = true`, `household_id IS NULL`). It is visible to every household. | (c) data | Not schema, and not needed by the batch. Owner: delete it, or deactivate it via `household_category_settings`, if it is a test leftover. |
| R2 | Live has 4 sub-categories not in the repo: `OPEX-ENTERTAINMENT/sub-karting`, `OPEX-GOV/sub-iqama-fees`, `OPEX-UTILITIES/sub-district-cooling`, `OPEX-UTILITIES/sub-zain-internet-sim` (27 vs 23). | (c) data | Add them to the seed migration if they should exist in fresh environments. |

### 3.3 Migration history (DB-15)

`supabase_migrations.schema_migrations` on live has 12 rows:

- 10 rows applied on 2026-10-18, named after merged or renamed files (for example `20261008_indexes_payday_qr_and_receipts_bucket`);
- `20261018_membership_sync_and_shared_account_policies`;
- `20261019100000_sec08_round6_hardening`.

Their `version` values are **apply timestamps** (`20261018180506` …), not the files' prefixes. SEC-01..SEC-07 (`20261019030000`–`20261019090000`) are **not recorded**, but every object they create is present (they were run in the SQL editor). No local migration filename matches any recorded version. §5.3 covers what this means for the CLI.

### 3.4 Platform-only differences (ignored)

These differences are platform-managed and ignored:

- the extensions `pg_stat_statements` and `supabase_vault`;
- the `supabase_realtime_messages_publication`;
- schema ACLs on `auth`, `storage` and `public` (grantor/role names);
- the storage triggers (`protect_delete`, bucket control and name length);
- the `pgrst_*`, `issue_*` and `graphql` event triggers.

Realtime membership matches the repo: `supabase_realtime` publishes `public.budgets` and `public.transactions`.

## 4. Data checks on live (counts only, 2026-10-20)

Query: part A of [`live_db_preflight_checks.sql`](live_db_preflight_checks.sql).

| Check | Live | Impact on the batch |
|---|---|---|
| households / users / auth users / memberships | 4 / 4 / 4 / 4 | — |
| `public.users` without an `auth.users` row | 0 | The suspected missing FK (DB-15) is not a problem on live; `users_id_fkey` exists. |
| transactions / with `user_id IS NULL` | 14 / **14** | `20261020400000`: all 14 become admin-only (owner decision). Insert binding applies to new rows only. |
| transactions whose creator is not a member of the household | 0 | — |
| `source = 'sms'` → note starts `Chat:` / `Receipt Scan:` / other | 10 → **8 / 2 / 0** | `20261020200000` relabels to `chat` 8, `receipt_scan` 2, `manual` 0. |
| `source` NULL / outside `{sms, chat, receipt_scan, manual}` | 0 / 0 | The new CHECK cannot fail. |
| `spent_by` outside `{me, partner, both}` | 0 | D6. |
| `cycle_key` NULL / differs from the server derivation (DB-08 detection, computed inline) | 0 / 0 | `20261020060000` is safe. Nothing to investigate. |
| transactions with a personal account not owned by the creator / account in another household | 0 / 0 | The new `transactions_update_household` WITH CHECK holds for existing rows. All 14 have `account_id IS NULL`. |
| households without an admin / without any member / with members but no admin | 1 / 1 / 0 | `owner_user_id` backfill leaves the orphan household `NULL` (harmless). No household has members but no admin, so DB-12/BUG-03 is fine. |
| households with more than one admin | 0 | The primary-admin backfill is unambiguous. |
| users whose active household has no membership row | 0 | `20261020020000` backfill inserts 0 rows. Nobody loses access through the membership-backed helpers. |
| users whose `users.role` differs from the membership role | 0 | Switching `get_auth_user_role()` to the membership role changes nobody's permissions. |
| membership roles | admin 3, member 1 | — |
| invites (used / open / expired) / invites whose target member is in another household | 1 (1/0/0) / 0 | The `20261020010000` target-member trigger only checks new writes. Existing data is clean anyway. |
| dependents (manual members) | 0 | — |
| users with `financial_role` spouse / provider / family_member | 0 / 3 / 1 | No family household yet. Nafaqah RPCs are inert until a wife joins. |
| accounts / shared pools / pools owned by a non-admin | 1 / 0 / 0 | DB-16 pool rule affects nobody today. |
| income records / account transfers / budgets / custom categories | 0 / 0 / 24 / 0 | — |
| `transactions` has `paid_by` / `beneficiary` columns | **0** (no) | **MOB-03 answered:** live has `spent_by`, `beneficiary_type`, `beneficiary_id`, the same as the repo. The MOB-03 fix (payer in the `PaidBy:` audit tag) is correct. No columns to add. |
| `transactions` has `nafaqah_class`/`nafaqah_spouse_id`; `households` has `owner_user_id` | 0 / 0 | Not yet applied, as expected. |
| receipt objects / larger than 20 MiB / MIME outside `jpeg,png,webp` | 39 / 0 / 2 | The `20261020080000` limits apply to new uploads only. The two odd objects stay readable. The largest object is 1 MiB, far under the limit. |
| `households.rollover_rule` values | `accumulate` ×4 | D7. |
| `consume_quota(p_user_id uuid, p_bucket text, p_limit integer, p_window_seconds integer) RETURNS boolean` | present, `SECURITY DEFINER`, `search_path=public, auth, pg_temp`, EXECUTE: service_role only | Matches `ai_service/rate_limiter.py:162`. |

**RPCs the backend and app call.** All of these exist after the batch (post-check `expected_functions_missing = 0`):

- **ai_service:** `consume_quota`, `reallocate_budget`, `claim_household_role_invite`, `record_spouse_reimbursement`, `set_member_allowance`, `promote_member_to_admin`, `revoke_admin`, `transfer_primary_admin`.
- **Flutter:** `create_household_and_claim`, `join_household_by_code`, `get_user_households`, `switch_active_household`, `leave_household`, `record_income`, `transfer_between_accounts`, `reconcile_account_balance`.

On live **today**, `reallocate_budget` (D1) and the Nafaqah and role RPCs are missing. The current backend copes: it falls back for `reallocate_budget`, and it does not call the others yet.

## 5. Apply plan

### 5.1 Before you start

1. **Take a backup.** Download one (Dashboard → Database → Backups), or `pg_dump` the `public` schema with data.
2. **Run part A** of [`live_db_preflight_checks.sql`](live_db_preflight_checks.sql) in the SQL editor and compare it with §4. Note the two totals it prints (`budgets_spent_total`, `accounts_balance_total`).
3. **Pick a quiet moment.** There are 4 users. Each file takes well under a second.

### 5.2 Order and method

**SQL editor, one file per run, in this order:**

1. Open the file from this branch and paste the **whole** file.
2. Click Run and expect "Success. No rows returned". Live runs it as `postgres`.
3. Do not start the next file until the current one succeeds.

All files except `20261020080000` (a single `UPDATE`) are wrapped in `BEGIN … COMMIT`, so a failure leaves nothing half-applied. If a file fails, stop and keep the error text. The files before it are complete and consistent on their own.

| # | File | What it does on live (given §3/§4) | Coupling |
|---|---|---|---|
| 1 | `20261020005000_preflight_live_alignment.sql` | `rollover_rule`: no-op (exists). Revokes PUBLIC/anon/authenticated EXECUTE on `rls_auto_enable()`. | — |
| 2 | `20261020010000_audit_invites_rls_and_targeted_claims.sql` | RLS already on. Revokes anon on invites. Adds the target-member trigger. Fixes the two claim RPCs (DB-01, DB-05). | — |
| 3 | `20261020020000_audit_membership_policy_recursion.sql` | Adds `is_household_admin`. Replaces the memberships read policy and revokes client writes. Backfills 0 rows. Makes the helpers membership-backed (DB-02). | — |
| 4 | `20261020030000_audit_reallocate_budget_authz.sql` | **Creates** `reallocate_budget` (missing on live). EXECUTE for authenticated and service_role only (DB-03). | — |
| 5 | `20261020040000_audit_cost_control_codes_policies.sql` | Admin-only category insert/update. Revokes anon/DELETE (DB-04). | — |
| 6 | `20261020050000_audit_ledger_precision_and_income_append_only.sql` | 2-decimal and sign checks in `transfer_between_accounts` and `record_income`. Income and transfer ledgers become client read-only (DB-06, DB-07). | — |
| 7 | `20261020060000_audit_transaction_cycle_key_integrity.sql` | The cycle-key trigger also fires on `cycle_key` writes (DB-08). 0 mismatching rows. | — |
| 8 | `20261020070000_audit_definer_search_path_and_household_insert.sql` | Pins the `sync_user_household_membership` search_path. Drops direct household INSERT (DB-09, DB-10). | — |
| 9 | `20261020080000_audit_receipts_bucket_limits.sql` | `receipts` bucket: 20 MiB, jpeg/png/webp, private (DB-11). | — |
| 10 | `20261020090000_audit_sole_admin_account_deletion.sql` | Sole-admin handover before user delete (DB-12). | — |
| 11 | `20261020100000_audit_rls_initplan_and_fk_indexes.sql` | Re-creates policies in InitPlan form and adds 7 indexes, all on tiny tables (DB-13). | — |
| 12 | `20261020200000_remove_sms_artifacts.sql` | Relabels 10 rows. Default becomes `manual`. New source CHECK (API-25). | Rejects new `source='sms'`. Released builds that still send `sms` explicitly would get a CHECK error, so release the new app build promptly. |
| 13 | `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql` | Nafaqah columns, `member_allowances`, `spouse_reimbursements`, RPCs. | Before the new backend. |
| 14 | `20261020400000_admin_permissions_and_co_admins.sql` | Primary admin (3 households backfilled), co-admin RPCs, creator binding, owner-or-admin edits, admin-only pool withdrawals (DB-16, DB-18). | Before the new backend. The 14 legacy rows become admin-only. |

Then run part B of the checks file (§7). Then deploy ai_service, then the app (MASTER §6.2 steps 2–3).

Alternative to the SQL editor: run each file with `psql "<session-pooler connection string as postgres>" -v ON_ERROR_STOP=1 --single-transaction -f <file>`, in the same order.

### 5.3 Recording the history, and the CLI (DB-15)

**Do not run `supabase db push`, `supabase db reset --linked` or `supabase migration up` against this project yet.** No local file version matches a recorded live version (§3.3), so the CLI would treat all 41 local files as pending and try to replay the whole chain from `20260925_*` on the live database. The duplicate 8-digit prefixes (`20261008` ×3, `20261018` ×3, …) would then abort it part-way.

After all 14 files succeed, optionally record them in the format the CLI expects: `version` = the file's 14-digit prefix, `name` = the rest of the filename. This is a write, so the owner runs it:

```sql
INSERT INTO supabase_migrations.schema_migrations (version, name)
SELECT v, n FROM (VALUES
  ('20261020005000', 'preflight_live_alignment'),
  ('20261020010000', 'audit_invites_rls_and_targeted_claims'),
  ('20261020020000', 'audit_membership_policy_recursion'),
  ('20261020030000', 'audit_reallocate_budget_authz'),
  ('20261020040000', 'audit_cost_control_codes_policies'),
  ('20261020050000', 'audit_ledger_precision_and_income_append_only'),
  ('20261020060000', 'audit_transaction_cycle_key_integrity'),
  ('20261020070000', 'audit_definer_search_path_and_household_insert'),
  ('20261020080000', 'audit_receipts_bucket_limits'),
  ('20261020090000', 'audit_sole_admin_account_deletion'),
  ('20261020100000', 'audit_rls_initplan_and_fk_indexes'),
  ('20261020200000', 'remove_sms_artifacts'),
  ('20261020300000', 'nafaqah_wife_allowance_and_reimbursements'),
  ('20261020400000', 'admin_permissions_and_co_admins')
) AS m(v, n)
WHERE NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations s WHERE s.version = m.v);
```

The SEC-01..07 files (`20261019030000`, `060000`, `070000`, `080000`, `090000`) are applied on live but unrecorded. They can be added the same way. This is what `supabase migration repair --status applied <version>` writes.

The DB-15 re-baseline is still an owner task, to do before using the CLI:

1. Run `supabase db pull` to create a baseline migration from live.
2. Mark it applied with `migration repair`.
3. Move the pre-`20261020` files to an archive folder, so they are no longer replayed.
4. Keep the 14-digit `20261020*` files after the baseline.

## 6. Replica results

| Run | Result |
|---|---|
| Replica vs live catalog (before applying) | Identical on tables, columns, constraints, indexes, policies, function bodies and EXECUTE grants, triggers, table and column grants, bucket and realtime tables (platform-only differences of §3.4 remain) |
| Batch on the replica, first attempt (13 files, superuser) | All applied. Suite **19/20**: test 14 flagged `unaccent` ×4 and `rls_auto_enable` as anon-executable (D9, D10) |
| Batch on the live-shaped replica, as the non-superuser owner role (14 files) | All applied; post-check values as in §7; budget spent total and account balance total unchanged (245.00 / 1000.00 on the synthetic data); suite **20/20** |
| Batch on the empty replica (`run_tests.py --psql --apply-from 20261020005000 --db …`) | All applied; suite **20/20** |
| Full repo rebuild (`run_tests.py --psql --rebuild`) | **20/20** |
| Migrated replica vs migrated repo HEAD | Identical apart from D6, D8, D9 (function), D10, D12 (comments only) and comment-only function text (D11) |
| Rollback snapshot on the migrated replica | Catalog identical to live again; batch re-applied afterwards: **20/20** |

Changes made to reach this:

- **New** `supabase/migrations/20261020005000_preflight_live_alignment.sql`: captures D7 and revokes `rls_auto_enable` EXECUTE (D9). It is idempotent and loses no data.
- `supabase/migrations/20261020400000_admin_permissions_and_co_admins.sql` is now wrapped in `BEGIN … COMMIT`. It was the only multi-statement file of the batch without a transaction. Under `psql -f` it would otherwise have autocommitted statement by statement. Nothing else in the file changed.
- `supabase/tests/14_audit_catalog_guardrails.sql`: the anon-EXECUTE guardrail skips extension member functions (D10). App functions are still checked.
- `supabase/tests/run_tests.py`: new flags. Default behaviour is unchanged.
  - `--stop-before PREFIX` rebuilds the chain only up to `PREFIX`.
  - `--no-tests` builds or applies without running the suite.
  - `--apply-from PREFIX` applies pending migrations to an existing local database before testing.

## 7. Post-apply verification (read-only)

Run part B of [`live_db_preflight_checks.sql`](live_db_preflight_checks.sql) after file 14. Part B fails before the batch (it reads `households.owner_user_id`). Expected values, assuming no new transactions in between; otherwise the transaction counts grow:

| Column | Expected |
|---|---|
| `transactions` / `tx_sms` / `tx_chat` / `tx_receipt_scan` / `tx_manual` | 14 / **0** / 11 / 3 / 0 |
| `source_default` / `source_check` | `'manual'::text` / `CHECK ((source = ANY (ARRAY['chat'::text, 'receipt_scan'::text, 'manual'::text])))` |
| `tx_user_id_null` | 14 |
| `budgets_spent_total` / `accounts_balance_total` | equal to the values noted in §5.1 |
| `households` / `hh_with_primary_admin` / `hh_primary_not_admin` / `hh_admin_but_no_primary` | 4 / 3 / 0 / 0 |
| `memberships` | 4 |
| `invites_rls` / `member_allowances_rls` / `spouse_reimbursements_rls` | true / true / true |
| `tx_nafaqah_cols` / `hh_new_cols` | 2 / 2 |
| `receipts_size_limit` / `receipts_mimes` / `receipts_public` | 20971520 / `{image/jpeg,image/png,image/webp}` / false |
| `recursive_policy_left` | 0 |
| `ccc_policies` | `cost_control_codes_insert,cost_control_codes_select,cost_control_codes_update` |
| `storage_policies` | `receipts_delete_household,receipts_insert_household,receipts_select_household` |
| `policies_to_public_or_anon` / `tables_without_rls` | 0 / 0 |
| `anon_executable_app_functions` / `definer_without_search_path` | NULL / NULL |
| `expected_functions_missing` | 0 |
| `transactions_triggers` | `on_transaction_delete,on_transaction_insert,on_transaction_update,trg_bind_transaction_creator,trg_enforce_transaction_write_permission,trg_populate_transaction_cycle_key,trg_update_account_balance_on_transaction,trg_validate_category_transactions,trg_validate_transaction_nafaqah_class` |
| `membership_role_triggers` | 2 |
| `anon_can_reallocate` / `auth_can_insert_income` / `auth_can_update_owner` | false / false / false |

Then smoke-test the app as an admin and as the member:

1. Open the household list (`get_user_households`, which now includes `is_primary`).
2. Upload and view a receipt (storage policies).
3. Add an expense; it is attributed to you.
4. As the member, try to edit a legacy expense; expect a refusal.
5. As the admin, edit the same expense; it succeeds.

## 8. Rollback notes

[`../rollback/20261020_audit_batch_rollback_snapshot.sql`](../rollback/20261020_audit_batch_rollback_snapshot.sql) undoes the whole batch in one transaction. It was generated from the live catalog before the batch and verified on the replica (§6).

What it cannot undo:

- The relabel of `source` stays.
- It drops the new tables and columns, so allowances, reimbursements, Nafaqah classes and primary-admin assignments made after the batch are lost.

Undo per file, if only the last files have to go (roll back from the bottom up):

| File | Undo | Data impact |
|---|---|---|
| 14 `…400000` | Drop the triggers `trg_bind_transaction_creator`, `trg_enforce_transaction_write_permission`, `trg_protect_primary_admin`, `trg_maintain_primary_admin` and the new functions. Restore `set_member_role`, `remove_member`, `get_user_households` (drop + create), `update_account_balance_on_transaction` and the transactions insert/update policies from the snapshot. Re-run `transfer_between_accounts` from file 6 and `nafaqah_husband_id` from file 13. Revoke the `households` column grants and grant table `UPDATE` back. Drop `households.owner_user_id`. | Primary-admin choices are lost. |
| 13 `…300000` | Drop the trigger `trg_validate_transaction_nafaqah_class`, the tables `member_allowances` and `spouse_reimbursements`, the columns `transactions.nafaqah_*` and the `nafaqah_*`/allowance/reimbursement functions. | Allowances and reimbursements recorded are lost. Export them first. |
| 12 `…200000` | `ALTER TABLE transactions DROP CONSTRAINT transactions_source_check; ALTER TABLE transactions ALTER COLUMN source SET DEFAULT 'sms';` Restore the comments. Live had no source CHECK before. | Relabel not reverted (label only). |
| 11 `…100000` | Re-create the pre-batch policies (snapshot §7). Drop the 7 indexes. | None. |
| 10 `…090000` | `DROP TRIGGER trg_handover_households_on_user_delete ON users; DROP FUNCTION handover_households_on_user_delete();` | None. |
| 9 `…080000` | `UPDATE storage.buckets SET file_size_limit = NULL, allowed_mime_types = NULL WHERE id = 'receipts';` | None. |
| 8 `…070000` | Restore `sync_user_household_membership` without `SET search_path`. Re-create `households_insert_authenticated`. Re-grant `INSERT`/`DELETE` and the anon privileges. | None. |
| 7 `…060000` | Re-create `trg_populate_transaction_cycle_key` as `BEFORE INSERT OR UPDATE OF timestamp, household_id`. | None. |
| 6 `…050000` | Restore `transfer_between_accounts` and `record_income`. Re-create `income_insert_household`. Re-grant write privileges on `income_records` and `account_transfers`. | None. |
| 5 `…040000` | Drop the two new `cost_control_codes` policies. Re-grant anon and `DELETE`. Live had no write policies before. | None. |
| 4 `…030000` | `DROP FUNCTION reallocate_budget(uuid, uuid, numeric);` It did not exist on live, and ai_service falls back to a two-step update. | None. |
| 3 `…020000` | Restore the two helpers. Replace `memberships_select_own_or_admin` with the pre-batch policies. Re-grant membership privileges. Drop `is_household_admin`. | Backfilled memberships (0 on live) stay. |
| 2 `…010000` | Restore `join_household_by_code` and `claim_household_role_invite`. Drop the trigger `trg_validate_invite_target_member` and its function. Re-grant anon on `household_invites`. RLS stays on (it was on before). | None. |
| 1 `…005000` | Optional: `GRANT EXECUTE ON FUNCTION rls_auto_enable() TO PUBLIC;`. **Do not** drop `rollover_rule`; it pre-dates the batch on live. | None. |

Every "restore … from the snapshot" statement is in section 5 (functions), section 7 (policies, triggers) or section 8 (grants) of the snapshot file.
