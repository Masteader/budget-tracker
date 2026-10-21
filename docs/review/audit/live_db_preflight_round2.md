# Live database pre-flight, round 2: `20261020700000` and `20261020800000`

Date: 2026-10-21 · Branch: `audit/claude-db-preflight-round2` (from `893bd67`) · Method: same as [`live_db_preflight.md`](live_db_preflight.md) §2 and §6 · Checks: [`live_db_preflight_round2_checks.sql`](live_db_preflight_round2_checks.sql) · Rollback: [`../rollback/20261020_round2_rollback_snapshot.sql`](../rollback/20261020_round2_rollback_snapshot.sql)

This pre-flight covers the two migrations that are not yet applied anywhere:

- `supabase/migrations/20261020700000_fable_db_hardening.sql` (FABLE-DB-02, -04 to -09);
- `supabase/migrations/20261020800000_household_roles_and_nafaqah_integrity.sql` (FABLE-LOGIC-01, -02, -04 to -06, FABLE-DB-01, -03).

Live already has every migration up to `20261020600000`. It was only read, through the Management API with `read_only=true` (connected as `supabase_read_only_user`). Only catalog queries and aggregate counts were sent. No row was copied and nothing was written.

## 1. Verdict

**Safe to apply: yes.** Apply the two files in order (700000, then 800000), each as one SQL editor run, using the plan in §6.

Why:

- **Both files applied cleanly to a faithful replica of live.**
  - The replica was generated from live's own catalog and is owned by a non-superuser `BYPASSRLS` role, as live's `postgres` is. Its catalog is identical to live apart from platform-only objects (§3).
  - It held synthetic data matching **63 of 64** of live's aggregate checks, including the per-household shape (§4). The one mismatch is a PG17-only privilege check, which reads NULL on the local PG16 server.
  - Each file's own guard and post-check blocks passed.
- **The full DB suite passes, 24/24, in every setup:**
  - on the migrated live-shaped replica;
  - on an empty replica migrated as the owner role;
  - on an empty replica migrated with `run_tests.py --apply-from`;
  - after rollback and re-apply;
  - on a full repo rebuild.
- **No existing row changes.** A fingerprint of all 21 tables (`public`, `auth.users`, `storage.objects`) is identical before and after the pair, apart from the two new columns. Budget totals stay at spent 9112.42 / allocated 20844.52, and the account balance total stays at 360.00.
- **Nothing re-keys at apply time.** The payday trigger fires only when `payday_day` changes, and neither file updates `payday_day`. All 14 transactions and 24 budgets keep cycle `2026-10`. Live's budget `spent_amount` already equals the recompute rule for all 24 budgets (drift 0), so a later payday change moves no money beyond the designed re-keying.
- **The provider backfill is unambiguous:**
  - 3 households get their primary admin as Nafaqah provider. Each has exactly one admin, who is the primary admin and has `financial_role = provider`.
  - The memberless household gets NULL, because it has no primary admin.
  - No household has a spouse member or a spouse owner, so the provider is inert everywhere for now.
- **After the pair, the replica catalog equals the repo HEAD rebuild**, apart from the same pre-existing drift items (§5).
- **There is a tested rollback.** On the migrated replica it returns the catalog exactly to live's current state, including function bodies, grants and the one function comment. Re-applying afterwards is clean and passes 24/24. It also works on a dirty database (after the test suite ran) and refuses to run twice.

**Migration fixes needed: none.** Neither file was changed.

Known consequences, all intended by the review:

- After 800000, members who are not admins can no longer read invite codes. On live this affects the 1 member (`family_member`). The released app never reads `household_invites` (checked in `flutter_app/lib`).
- The 1 used invite is now deleted with its claimer (`ON DELETE CASCADE`) instead of blocking account deletion. Its `created_by` is already NULL.
- Clients lose TRUNCATE/TRIGGER/REFERENCES on every public table, anon loses INSERT/UPDATE/DELETE, and on PG17 anon and authenticated also lose MAINTAIN. That is 15 tables (16 for MAINTAIN). PostgREST never uses these privileges.
- Admins can update only `name`, `payday_day`, `monthly_income` and `rollover_rule` on `households`. That is all the app writes.

## 2. Method (what was reused, what changed)

Tooling from the round-1 scratch pre-flight was reused: inventory, replica generator, owner-role apply, catalog diff and rollback generator. Changes in this round:

| Item | Change | Why |
|---|---|---|
| Live-shaped fixture | Rebuilt for live's current counts. 4 households: H1 payday 27 with 2 members (admin/provider + member/family_member), 8 transactions, 6 budgets, 1 personal account (360.00), and 1 used `family_member` invite with `created_by` NULL. H2 payday 27, 1 admin, 5 transactions, 11 budgets. H3 **payday 1**, 1 admin, 1 transaction, 6 budgets. H4 payday 27, memberless, owner NULL, 1 budget. Totals: 14 creator-less transactions (`chat` 11 / `receipt_scan` 3) whose total equals live's spent total, 24 budgets (17 with sub-allocations, 20 active), 24 backup rows, 11 system categories, 27 sub-categories, 39 receipt objects. | Live's data changed since round 1: payday 1 household, relabelled sources, provider/primary admin. |
| Rollback generator | (1) After `REVOKE ALL` on a table, it re-grants every target **column** grant on that table. Before, column grants present both before and after, such as `accounts` ×7 and `users` ×2, were silently dropped. (2) It restores **MAINTAIN** through a `server_version_num >= 170000` block, since live is PG17. | 700000 changes table privileges on 15 tables that also carry column grants. |
| Row fingerprint | New `md5` of every row per table, ignoring only the two new columns. | Proves the pair changes no existing row. |
| Part A / part B | New checks for the provider backfill, membership financial roles, invite FKs and policies, column grants, PG17 MAINTAIN, and budget spent drift. | §4 and §7. |

Servers: PostgreSQL 16.15 locally, PostgreSQL 17.6 on live.

## 3. Drift since the last batch (live vs repo rebuilt up to `20261020600000`)

Live now matches the repository much more closely than in round 1. The diff, keyed by table, column, constraint, policy, function signature, trigger, grant and bucket, shows only these items:

| # (round 1) | Drift | Status | Effect on the pair |
|---|---|---|---|
| D1–D5, D7 | `reallocate_budget`, invite RLS, recursive policy, category policies, source CHECK, `rollover_rule` | **Resolved** by the round-1 batch | — |
| D6 | `transactions_spent_by_check` exists only in the repo | Unchanged (deliberate) | None. All 14 rows are `me` 9 / `both` 4 / `partner` 1. |
| D8 | `budgets_spent_backup_20261019` exists only on live: 24 rows, RLS on, no policies, owner `postgres`, full anon/authenticated privileges | Unchanged | 700000 §6 also revokes TRUNCATE, TRIGGER, REFERENCES, anon DML and MAINTAIN on it. Afterwards anon has SELECT and authenticated has SELECT/INSERT/UPDATE/DELETE, and RLS shows no rows. Its DB-08 guard covers it. |
| D9 | `rls_auto_enable()` and the `ensure_rls` event trigger exist only on live (EXECUTE: postgres, service_role) | Unchanged | Not touched. |
| D10 | `unaccent` lives in `public` (4 functions owned by `supabase_admin`) | Unchanged | Not touched. 700000 §6 loops over tables only. |
| D11 | Comment-only body differences in `consume_quota` and `get_saudi_cycle_for_timestamp` | Unchanged | Neither function is touched. |
| D12 | 5 column comments missing on live | Unchanged | Cosmetic. |
| — | Function comments on `household_primary_admin_id` and `nafaqah_is_spouse_member` | Present on live and in the repo; the replica generator does not emit function comments | Not touched by the pair. The rollback restores the one comment the pair changes (`nafaqah_husband_id`). |
| — | `supabase_migrations.schema_migrations`: 28 rows; the 16 `20261020*` files are recorded with their 14-digit prefix as `version` | **New (good)** | Record the pair the same way (§6.3). |

Everything else is identical, apart from the platform-only items listed in round 1 §3.4: realtime messages publication, `pg_stat_statements`, `supabase_vault`, schema ACL grantors and storage triggers. That covers the 19 tables, 198 columns, 85 constraints, 82 indexes, 39 policies (public + storage), 62 functions (bodies, `SECURITY DEFINER`, `search_path`, EXECUTE), 19 triggers, 48 table grants and 19 column grants (`accounts` ×7, `households` ×10, `users` ×2), the bucket and the realtime tables. All 19 public tables are owned by `postgres`, and all table, column and function privileges were granted by `postgres`. `REVOKE` run as `postgres` therefore removes them, and the guards cannot trip on a grant made by another grantor. The function lists the guards need are all present.

## 4. Data checks on live (part A, counts only, 2026-10-21)

Query: part A of [`live_db_preflight_round2_checks.sql`](live_db_preflight_round2_checks.sql). The replica reproduces every value except `tables_client_maintain_pg17`, which is NULL on PG16.

| Check | Live | Impact on the pair |
|---|---|---|
| households / users / auth users / memberships | 4 / 4 / 4 / 4 | — |
| memberships by role × `users.financial_role` | admin/provider **3**, member/family_member **1** | 800000 backfills `household_memberships.financial_role` to exactly these values. No user has a NULL role, so the `COALESCE(…,'provider')` default affects nobody. |
| users with more than one membership / membership outside the user's active household | 0 / 0 | The backfill from the per-user role is exact (guard notice: "0 user(s) belong to more than one household"). |
| `users.financial_role` outside the known set | 0 | The 800000 guard and the new CHECK hold. |
| users whose active household has no membership / `users.role` ≠ membership role | 0 / 0 | Sync trigger and helpers are consistent. |
| households with `owner_user_id` NULL / of which with members | **1** / 0 | That one is the memberless household. It gets provider NULL, which is harmless. |
| households whose owner is not an admin member | 0 | — |
| **households whose owner is a spouse** | **0** | No household is skipped by the backfill rule. |
| households expected to get a provider (owner is a non-spouse member) | **3** | Post-check notice: "3 household(s) have a Nafaqah provider". |
| households with more than one admin / with a spouse member / with a peer member | 0 / 0 / 0 | `nafaqah_husband_id()` stays NULL everywhere. The provider is inert until a wife joins. |
| invites total / open / used / expired | 1 / 0 / 1 / 0 | — |
| invite claimed by a current member of its household | 1 | `trg_refuse_invite_claim_by_member` checks only new claims (`OLD.used_by IS NULL`), so this row is unaffected. |
| invites whose creator or claimer no longer exists / `created_by` NULL | 0 / 0 / 1 | Re-adding the two FKs re-validates cleanly. SET NULL is already the state of the one row. |
| current invite FK actions / invite policies | `created_by:a, used_by:a` / `invites_delete_admin, invites_insert_household, invites_select_household` | After the pair: `n` / `c` and `invites_select_admin`. |
| dependents (manual members) / linked | 0 / 0 | — |
| transactions / with `user_id` NULL / classified (Nafaqah) / `wife_personal` / `wife_reimbursable` | 14 / 14 / **0** / 0 / 0 | The budget-trigger change and the ledger guard have no historic rows to reinterpret. |
| member allowances / spouse reimbursements | 0 / 0 | The ledger guard starts from an empty ledger. |
| `cycle_key` NULL / differing from the server derivation | 0 / 0 | — |
| budgets / spent total / allocated total / **spent ≠ recompute rule** | 24 / **9112.42** / **20844.52** / **0** | Note the totals. A future payday change recomputes spent, and since there is no drift, that recompute moves nothing in the current state. |
| accounts / balance total | 1 / **360.00** | — |
| sub-categories / custom categories | 27 / 0 | — |
| **payday_day distribution** / NULL | **1:1, 27:3** / 0 | Neither file updates `payday_day`, so `trg_rekey_cycles_on_payday_change` does not fire during the apply (verified: 0 transaction or budget rows changed). On 2026-10-21 the open cycle is `2026-10` for both paydays. |
| authenticated may UPDATE on `households` | 10 columns (`accumulated_savings, created_at, id, invite_code, last_rollover_*, monthly_income, name, payday_day, rollover_rule`) | After the pair: `monthly_income, name, payday_day, rollover_rule`. |
| tables with TRUNCATE/TRIGGER/REFERENCES for clients or anon DML / with client MAINTAIN (PG17) | 15 / 16 | 0 / 0 after the pair. |
| `nafaqah_current_cycle_key` / `generate_secure_invite_code` executable by authenticated | true / true | false / false afterwards. service_role keeps EXECUTE. |
| guard functions present (`get_saudi_cycle_for_timestamp`, `household_resolve_actor`, `household_require_admin`, `household_member_role`, `populate_transaction_cycle_key`, `record_spouse_reimbursement`, `household_primary_admin_id`, `household_apply_role`) | 8 / 8 | The 800000 §0 guard passes. |
| new columns already present | 0 | Not applied yet, as expected. |
| migrations recorded / last | 28 / `20261020600000` | — |

**Provider backfill outcome on live, in counts:**

| Household group | Count | `nafaqah_provider_user_id` after 800000 |
|---|---|---|
| Has a primary admin who is a non-spouse member (all `provider`) | 3 | = primary admin (`owner_user_id`) |
| Memberless, `owner_user_id` NULL | 1 | NULL |
| Primary admin is a spouse | 0 | (would be NULL) |

`household_memberships.financial_role` after 800000: admin/provider 3, member/family_member 1, NULL 0. The `users.financial_role` cache matches all 4 memberships.

## 5. Replica results

| Run | Result |
|---|---|
| Replica vs live catalog (before) | Identical apart from platform-only objects (§3) |
| Live-shaped replica vs live data checks | 63/64 equal. The exception is `tables_client_maintain_pg17` (PG17-only, NULL on PG16). The per-household shape (payday, owner, members, transactions, budgets, keys, accounts, invites) is identical. |
| 700000 then 800000 as owner role `live_owner` (non-superuser, `BYPASSRLS`) on the live-shaped replica | Both applied without error. Guard notices: 0 multi-household users, 0 classified transactions. Post-check: "3 household(s) have a Nafaqah provider". The 700000 guard passed silently. |
| Row fingerprint, before vs after (21 tables, new columns excluded) | **Identical.** No existing row changed. |
| Totals before → after | spent 9112.42 → 9112.42, allocated 20844.52 → 20844.52, balance 360.00 → 360.00, cycle keys `2026-10`: 14 transactions / 24 budgets → same |
| Part B on the migrated replica | All values as in §7 |
| Full suite on the migrated live-shaped replica (`run_tests.py --psql --db bt_r2_shaped`) | **24/24** |
| Empty replica, pair applied as owner role, suite | **24/24** (post-check: 0 providers) |
| Empty replica, `run_tests.py --psql --apply-from 20261020700000` | **24/24** |
| Full repo rebuild (`run_tests.py --psql --rebuild`) | **24/24** |
| Migrated replica vs migrated repo HEAD rebuild | Identical apart from the pre-existing D6, D8, D9, D10, D11 and D12. D8's privileges are now trimmed by 700000. Every object the pair creates or changes matches HEAD exactly. |
| Pair re-run on the already migrated replica | Clean. Catalog and part B unchanged (idempotent). |
| Functional smoke on the migrated live-shaped replica (rolled back) | member: 0 invites visible, payday update 0 rows. admin: 1 invite visible; payday 27→25 accepted (re-key trigger runs over the 8 legacy creator-less rows without error). `get_household_members` shows `admin/provider/primary` and `member/family_member`. `set_nafaqah_provider` works and reports the primary admin as previous provider. Direct UPDATE of `invite_code` / `nafaqah_provider_user_id`: permission denied. service role: payday 1→5 accepted. Totals unchanged. |

## 6. Apply plan

### 6.1 Before you start

1. **Take a backup**, as in round 1 (Dashboard → Database → Backups, or `pg_dump` of `public` with data).
2. **Run part A** of [`live_db_preflight_round2_checks.sql`](live_db_preflight_round2_checks.sql) and compare it with §4. Write down `budgets_spent_total`, `budgets_allocated_total` and `accounts_balance_total`. If `hh_owner_is_spouse`, `users_multi_membership`, `memberships_user_fr_null` or `users_fr_unknown` is no longer 0, stop and re-read §4.
3. **Pick a quiet moment.** Both files take ACCESS EXCLUSIVE locks on `households`, `household_memberships`, `household_invites` and `users` for well under a second (4 rows each).

### 6.2 Order and method

**SQL editor, one file per run, in this order. Live runs each one as `postgres`.**

| # | File | What it does on live | Expected output |
|---|---|---|---|
| 1 | `20261020700000_fable_db_hardening.sql` | Re-creates the invite FKs (`created_by` SET NULL, `used_by` CASCADE). `reallocate_budget` fails closed. Revokes client EXECUTE on `nafaqah_current_cycle_key` and `generate_secure_invite_code`. Sets the client UPDATE columns on `households` (4) and the INSERT/UPDATE columns on `household_dependents` and `users`. Revokes TRUNCATE/TRIGGER/REFERENCES, anon DML and MAINTAIN (PG17) on all 19 public tables. Ends with a guard that aborts if anything differs. | "Success. No rows returned" |
| 2 | `20261020800000_household_roles_and_nafaqah_integrity.sql` | Adds `household_memberships.financial_role` (backfilled: provider 3, family_member 1) and `households.nafaqah_provider_user_id` (backfilled: 3 = primary admin, 1 NULL). Adds the role, provider, invite-claim and ledger-guard triggers and functions. Makes invites admin-only. Budget triggers ignore `wife_personal`. Adds the payday re-key trigger, which fires only on a later change. Ends with post-checks. | Success. In the notices: "guard: 0 user(s) belong to more than one household …", "guard: 0 classified (Nafaqah) transaction(s)", "post-check: 3 household(s) have a Nafaqah provider" |

Each file is wrapped in `BEGIN … COMMIT`, and its guard blocks abort the transaction on any mismatch. A failure therefore leaves nothing half-applied. Stop and keep the error text. File 2's §0 guard checks only the round-1 prerequisites, so it would also apply without file 1. Keep the order anyway: file 2's grant comments assume file 1's households column list, and the replica and suite results cover this order only.

Alternative: `psql "<session-pooler connection string as postgres>" -v ON_ERROR_STOP=1 -f <file>`, run on each file in the same order. Each file has its own transaction, so do not add `--single-transaction`.

Then run part B (§7), deploy ai_service, then release the app build (MASTER §6.2).

### 6.3 Recording the history

Live records the 16 `20261020*` files with `version` = the 14-digit prefix. After both files succeed, the owner records the pair the same way (this is a write):

```sql
INSERT INTO supabase_migrations.schema_migrations (version, name)
SELECT v, n FROM (VALUES
  ('20261020700000', 'fable_db_hardening'),
  ('20261020800000', 'household_roles_and_nafaqah_integrity')
) AS m(v, n)
WHERE NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations s WHERE s.version = m.v);
```

The round-1 CLI warning still holds. Do not run `supabase db push`, `db reset --linked` or `migration up` against live until the DB-15 re-baseline is done (round 1 §5.3).

## 7. Post-apply verification (part B, read-only)

Run part B of [`live_db_preflight_round2_checks.sql`](live_db_preflight_round2_checks.sql) after file 2. Part B fails before the pair is applied. These are the expected values on live, assuming no data changes in between. They are exactly what the migrated live-shaped replica printed, except `tables_client_maintain_pg17`, which is NULL there because of PG16.

| Column | Expected |
|---|---|
| `households` / `memberships` / `users` / `invites` / `dependents` | 4 / 4 / 4 / 1 / 0 |
| `memberships_fr_null` / `membership_fr_not_null` | 0 / true |
| `membership_role_x_fr` | `admin/provider:3,member/family_member:1` |
| `users_fr_cache_mismatch` | 0 |
| `membership_fr_check` | `CHECK ((financial_role = ANY (ARRAY['provider'::text, 'spouse'::text, 'peer'::text, 'family_member'::text, 'dependent'::text])))` |
| `hh_with_provider` / `hh_provider_is_primary_admin` / `hh_provider_not_primary_admin` | **3 / 3 / 0** |
| `hh_owner_but_no_provider` / `hh_no_owner_no_provider` / `hh_provider_invalid` | 0 / **1** / 0 |
| `provider_fk` | `FOREIGN KEY (nafaqah_provider_user_id) REFERENCES users(id) ON DELETE SET NULL` |
| `invite_fk_actions` | `created_by:n,used_by:c` |
| `invite_policies` | `invites_delete_admin=DELETE,invites_insert_household=INSERT,invites_select_admin=SELECT` |
| `invites_select_qual` | `((household_id = ( SELECT get_auth_user_household_id() AS get_auth_user_household_id)) AND (( SELECT get_auth_user_role() AS get_auth_user_role) = 'admin'::text))` |
| `hh_auth_update_cols` | `monthly_income,name,payday_day,rollover_rule` |
| `dependents_auth_update_cols` / `dependents_auth_insert_cols` | `avatar_icon,monthly_allowance,name,relationship` / `avatar_icon,created_at,household_id,id,monthly_allowance,name,relationship` |
| `users_auth_insert_cols` / `users_auth_update_cols` | `created_at,display_name,household_id,id,payday_day,role` / `display_name,payday_day` |
| `auth_can_update_provider` / `auth_can_write_memberships` | false / false |
| `tables_with_unneeded_client_privs` / `tables_client_maintain_pg17` / `tables_service_role_truncate` | **0 / 0** / 19 |
| `auth_x_nafaqah_cycle_key` / `auth_x_gen_invite_code` / `svc_x_nafaqah_cycle_key` | false / false / true |
| `anon_x_reallocate` / `auth_x_set_provider` / `anon_x_set_provider` / `auth_x_rekey` / `auth_x_husband_id` | false / true / false / false / false |
| `new_functions_missing` | 0 |
| `membership_triggers` | `trg_clear_nafaqah_provider,trg_maintain_primary_admin,trg_membership_financial_role_cache,trg_membership_financial_role_rules,trg_prevent_last_admin_demotion,trg_protect_primary_admin` |
| `households_triggers` | `trg_households_nafaqah_provider,trg_rekey_cycles_on_payday_change` |
| `invites_triggers` | `trg_refuse_invite_claim_by_member,trg_validate_invite_target_member` |
| `transactions_triggers` | `on_transaction_delete,on_transaction_insert,on_transaction_update,trg_bind_transaction_creator,trg_enforce_transaction_write_permission,trg_populate_transaction_cycle_key,trg_update_account_balance_on_transaction,trg_validate_category_transactions,trg_validate_transaction_nafaqah_class,trg_wife_ledger_guard` |
| `policies_to_public_or_anon` / `tables_without_rls` | 0 / 0 |
| `payday_distribution` | `1:1,27:3` |
| `transactions` / `tx_cycle_key_null` / `tx_cycle_keys` / `budget_cycle_keys` / `budgets` | 14 / 0 / `2026-10:14` / `2026-10:24` / 24. New transactions after 2026-10-26 (payday 27) legitimately add `2026-11`. |
| `budgets_spent_total` / `budgets_allocated_total` / `accounts_balance_total` | equal to part A (9112.42 / 20844.52 / 360.00 on 2026-10-21) |

Smoke test in the app, as in round 1, plus:

1. As the member, open settings. The invite list is not shown or is empty. Nothing in the released app reads it.
2. As the admin, change and restore `payday_day`. It succeeds, and the budgets screen still shows the same totals.

## 8. Rollback notes

[`../rollback/20261020_round2_rollback_snapshot.sql`](../rollback/20261020_round2_rollback_snapshot.sql) undoes **both** files in one transaction. It was generated from live's catalog before the pair, and it refuses to run unless 800000 is applied. Section by section, it:

1. drops the 7 new triggers;
2. drops `invites_select_admin`;
3. drops the new or changed constraints and the provider index;
4. drops the two new columns;
5. drops the 12 new functions and restores 14 function bodies and the EXECUTE grants of 16 functions;
6. re-adds the invite FKs with NO ACTION;
7. re-creates `invites_select_household`;
8. restores the table and column privileges of 15 tables, plus MAINTAIN on PG17;
9. restores the `nafaqah_husband_id` comment.

Verification on the replica:

- live-shaped replica → pair → rollback: catalog identical to live (and to the pre-pair replica), function comments identical, and the row fingerprint of all 21 tables identical to the pre-pair data;
- then pair re-applied: catalog and part B identical to the first apply, and the suite passes 24/24;
- rollback on the replica after the full suite (extra memberships, providers and invites): it applies, and the catalog again equals the pre-pair state;
- a second run is refused by its guard.

The MAINTAIN block cannot be exercised locally (PG16). It uses `EXECUTE 'GRANT MAINTAIN …'` behind a version check, and the same privilege checks were confirmed on live's PG17 with a read-only query (16 tables have client MAINTAIN today).

Data impact of a rollback:

- per-membership financial roles and chosen Nafaqah providers are lost, because the columns are dropped;
- `users.financial_role` keeps its last cached value;
- invites deleted by the new cascade are not recreated;
- cycle keys re-keyed by a payday change made while the pair was live stay re-keyed.

To undo only file 2, use the commented rollback at the end of `20261020800000`. Run its function re-definitions before the column drops, as that comment says. To undo only file 1, take sections 3, 5 (only `reallocate_budget`, `nafaqah_current_cycle_key` and `generate_secure_invite_code`) and 8 of the snapshot.

## 9. PostgreSQL 17 notes

- **MAINTAIN** (PG17-only) is the one version-dependent part:
  - 700000 §6 revokes it from PUBLIC, anon and authenticated only when `server_version_num >= 170000`;
  - the rollback re-grants it the same way;
  - part B checks it (`tables_client_maintain_pg17`, expected 0 on live).

  The 700000 guard does not check MAINTAIN. Part B does.
- Nothing else in either file depends on the version: FK actions, column privileges, `has_*_privilege`, triggers, `pg_get_constraintdef` output and the `information_schema` reads all behave the same in PG16 and PG17. The diff tool ignores MAINTAIN in table-grant comparisons.
- Follow-up (not blocking): live's default privileges for `postgres` and `supabase_admin` in `public` still grant `arwdDxtm` on new tables to anon and authenticated. A future migration that creates a table must revoke those privileges explicitly. The catalog-wide check in test 23 (FABLE-DB-08) will flag it otherwise.

## 10. Artefacts

- [`live_db_preflight_round2_checks.sql`](live_db_preflight_round2_checks.sql): part A (before) and part B (after). Read-only; validated on live (part A) and on the migrated replica (both parts).
- [`../rollback/20261020_round2_rollback_snapshot.sql`](../rollback/20261020_round2_rollback_snapshot.sql): the tested rollback for both files.
- Scratch tooling (not committed): replica generator and inventory as in round 1, plus the round-2 fixture, the row fingerprint and the patched rollback generator.
