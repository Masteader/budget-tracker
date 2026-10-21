# Live database pre-flight, round 3: the four pending files

Date: 2026-10-21 · Branch: from `audit/claude-comprehensive-review` at `7f97e7f` · Method: same as [`live_db_preflight_round2.md`](live_db_preflight_round2.md) §2 · Checks: [`live_db_preflight_round3_checks.sql`](live_db_preflight_round3_checks.sql) · Rollbacks: [`../rollback/20261020_round3_rollback_snapshot.sql`](../rollback/20261020_round3_rollback_snapshot.sql), then [`../rollback/20261020_round2_rollback_snapshot.sql`](../rollback/20261020_round2_rollback_snapshot.sql)

This pre-flight covers the four migrations that are in the repository but not yet on live. They must be applied in this order:

1. `supabase/migrations/20261020700000_fable_db_hardening.sql` (FABLE-DB-02, -04 to -09);
2. `supabase/migrations/20261020750000_installment_pay_atomic.sql` (FABLE-API-10);
3. `supabase/migrations/20261020800000_household_roles_and_nafaqah_integrity.sql` (FABLE-LOGIC-01, -02, -04 to -06, FABLE-DB-01, -03);
4. `supabase/migrations/20261020900000_household_type_and_round2_fixes.sql` (owner decisions D1 to D3, FABLE2-DB-01, -02, -05, -07).

Live already has every migration up to `20261020600000`. It was only read, through the Management API with `read_only=true`. Only catalog queries and aggregate counts were sent. No row was copied and nothing was written.

## 1. Verdict

**Safe to apply: yes.** Apply the four files in order (700000, 750000, 800000, 900000). Run each one in its own SQL editor run, following the plan in §6.

Why:

- **Live has not changed since round 2.** Its catalog is identical to the round-2 inventory; the only difference is two new daily realtime partitions, which belong to the platform. All 64 round-2 part-A values are identical, and the per-household shape is unchanged (§3, §4). The round-2 findings therefore still hold for 700000 and 800000.
- **All four files applied cleanly to a faithful replica of current live.**
  - The replica was regenerated from today's live inventory. It is owned by a non-superuser `BYPASSRLS` role, as live's `postgres` is. This time the replica also carries live's three function comments.
  - Its catalog is identical to live apart from platform-only objects.
  - Its synthetic data reproduces **80 of 81** part-A values, all 50 round-1 data checks, the value distributions and the per-household shape. The one mismatch is `tables_client_maintain_pg17`, which PostgreSQL 16 cannot report.
  - Every guard and post-check block in the four files passed. The notices are listed in §6.2.
- **The full DB suite passes, 26/26, in every setup:**
  - the migrated live-shaped replica;
  - an empty replica migrated as the owner role;
  - an empty replica migrated with `run_tests.py --apply-from 20261020700000`;
  - after the double rollback and a re-apply, on both a clean and a post-suite ("dirty") database;
  - a full repo rebuild with `--rebuild`.
- **No existing row changes.** A per-table `md5` fingerprint of all 21 tables (19 `public` tables, `auth.users`, `storage.objects`) is identical before and after the four files. Only the three new columns are excluded.
  - Budget totals stay at spent 9112.42 / allocated 20844.52.
  - The account balance total stays at 360.00.
  - Transactions (14) and budgets (24) all stay on cycle `2026-10`.
- **The household outcomes are as expected:**
  - all 4 households end with `household_type = 'family'`. Live has no `peer`, so no household becomes `roommates`;
  - the Nafaqah provider is the primary admin for the 3 households that have one, and NULL for the memberless household;
  - membership financial roles are unchanged: `admin/provider` ×3 and `member/family_member` ×1, all of which fit `family`;
  - live has **0 installment plans**, so the new `paid_installments` CHECK is added and validated straight away (`[validated]`).
- **After the four files, the replica's catalog equals the repo HEAD rebuild.** The only differences are the same pre-existing drift items as in round 2 (D6, D8, D9, D10, D11, D12). Every object the four files create or change matches HEAD exactly: bodies, grants, triggers, constraints and comments.
- **Both rollbacks are tested on the live replica and work in sequence:**
  - the round-3 rollback returns the catalog exactly to "live + 700000/750000/800000";
  - the round-2 rollback then returns it exactly to current live: catalog, function bodies, EXECUTE grants, the three function comments, the row fingerprint and all 81 part-A values;
  - each rollback refuses to run out of order or twice;
  - re-applying the four files afterwards reproduces the first apply exactly and passes 26/26.
- **Re-running all four files in order is idempotent.** The catalog, all 89 part-B values and the row fingerprint are unchanged.

**Migration fixes needed: none.** None of the four files was changed.

Known consequences, all intended by the review:

- Round 2's consequences apply unchanged (round 2 §1):
  - members who are not admins can no longer read invite codes;
  - the 1 used invite cascades with its claimer;
  - clients lose TRUNCATE/TRIGGER/REFERENCES, anon loses DML, and on PG17 anon and authenticated also lose MAINTAIN;
  - `households` gets a client UPDATE column list.
- `create_household_and_claim(text)` is replaced by `create_household_and_claim(text, text DEFAULT 'family')`. The released app calls `{p_name}` only, and that call still resolves (tested). It returns the same JSON row, now with `household_type`.
- Clients lose UPDATE of `installment_plans.paid_installments` and `status`. They keep UPDATE on the other 10 columns. The app never writes this table. The deployed ai_service writes it with the service role, which keeps full UPDATE.
- `pay_installment_plan` (new in 750000, tightened in 900000) is EXECUTE for `service_role` only. The deployed ai_service (`origin/main`) does not call it yet; the HEAD ai_service does. Hence the deployment order: migrations, then ai_service, then the app.
- `households.household_type` is not client-writable. It changes only through `set_household_type` (admins).

## 2. Method (what was reused, what changed)

The round-2 tooling was reused: inventory, replica generator, owner-role apply, catalog diff, row fingerprint and `cmpjson`. The fixture was also reused, because live's data shape is unchanged. Changes in this round:

| Item | Change | Why |
|---|---|---|
| Live inventory | Taken again today (21 catalog queries, read-only) | Detect drift since round 2 |
| Function comments | Added to the inventory, the catalog diff and the replica generator (`COMMENT ON FUNCTION`) | Round 2's replica lacked live's 3 function comments. 750000 adds a 4th, and the rollbacks must restore the comment set exactly. |
| Part A | Round 2's 64 columns plus 17 new ones: expected household type, `is_settlement` / `nafaqah_spouse_id` rows, installment plans (count, range violations, status, grants), presence of `household_type` / `pay_installment_plan` / both `create_household_and_claim` signatures, function comment list, public function count, and **per-table row counts** (`table_rows`) | 750000 / 900000 inputs |
| Part B | Round 2's 54 columns plus 35 new ones: type distribution, NOT NULL / default / CHECK, roles fitting the type, installment CHECK and column grants, new RPC privileges, provider trigger definition, comments, `table_rows`, migration history | 750000 / 900000 outputs |
| Per-household shape | One aggregate line per household: payday, owner present, members, admins, role/financial-role pairs, transactions, cycle keys, budgets, accounts, invites, plans, income records. No ids or names. | Proves the fixture still mirrors live |
| Apply | Four files, each as its own `psql -v ON_ERROR_STOP=1` run under `SET ROLE live_owner`, mirroring one SQL editor run per file | — |
| Rollback round trip | Round-3 rollback, then round-2 rollback, each diffed against the matching replica state. Also tested on a database the suite had already run on. | The round-3 snapshot was generated from a repo rebuild, so it needed proving against live's real state |

Servers: PostgreSQL 16.15 locally, PostgreSQL 17.6 on live.

## 3. Drift since round 2

**Catalog.** The live inventory was diffed against the round-2 inventory over tables, columns, constraints, indexes, policies, functions (incl. EXECUTE), function definitions, triggers, table and column grants, owners, bucket, publications, extensions, default ACLs, schema ACLs and migrations. The only difference is in `supabase_realtime_messages_publication`: live now also lists `realtime.messages_2026_10_23` and `_24`, the platform's daily partitions. Live still has 28 recorded migrations, the last one `20261020600000`.

**Data.** All 64 round-2 part-A values are identical today (`cmpjson`: 0 differences on the shared keys). The per-household shape is identical as well.

**Live vs the repo rebuilt up to `20261020600000`.** The diff has the same items as round 2 §3, and no new ones:

- D6: `transactions_spent_by_check` exists only in the repo;
- D8: `budgets_spent_backup_20261019` exists only on live;
- D9: `rls_auto_enable()` and the `ensure_rls` event trigger exist only on live;
- D10: `unaccent` lives in `public`;
- D11: comment-only body differences in `consume_quota` and `get_saudi_cycle_for_timestamp`;
- D12: 5 column comments missing on live;
- platform-only items: publications, extensions, schema ACLs.

None of these is touched by 750000 or 900000. As before, 700000 §6 trims D8's grants.

## 4. Data checks on live (part A, counts only, 2026-10-21)

Query: part A of [`live_db_preflight_round3_checks.sql`](live_db_preflight_round3_checks.sql). The first 64 columns and their impact are exactly as in round 2 §4. They are repeated here only where they matter for the four files together.

| Check | Live | Impact |
|---|---|---|
| households / users / auth users / memberships | 4 / 4 / 4 / 4 | — |
| memberships by role × `users.financial_role` | admin/provider **3**, member/family_member **1** | 800000 backfills `household_memberships.financial_role` to exactly these values. All of them fit `family`, so 900000 changes no role. |
| users with more than one membership / `financial_role` NULL / unknown | 0 / 0 / 0 | 800000 guards pass |
| households with owner NULL (memberless) / owner is a spouse / expected to get a provider | **1** / 0 / **3** | Provider backfill: 3 = primary admin, 1 NULL |
| households with a spouse member / with a peer member | 0 / **0** | `expected_hh_roommates` = **0** and `expected_hh_family` = **4**. 900000's ambiguity guard (peer plus spouse or Nafaqah data) counts 0. |
| transactions / creator-less / classified / `nafaqah_spouse_id` set / `is_settlement` | 14 / 14 / **0** / **0** / **0** | 900000 §12 (D3 cleanup of orphaned ledgers) touches 0 rows. Its guard notice reads "0 classified row(s) of a wife who is no longer a member". The FABLE2-DB-05 budget-trigger change has no settlement rows to reinterpret. |
| member allowances / spouse reimbursements | 0 / 0 | 900000 §12 deletes nothing |
| **installment plans / outside 0..installment_count / status distribution** | **0** / 0 / (none) | The CHECK is validated immediately. Notice: "guard: 0 installment plan(s) outside 0..installment_count". |
| authenticated UPDATE on `installment_plans` (table / `paid_installments`) / anon UPDATE | true / true / true | After the four files: authenticated has UPDATE on 10 columns only and not on `paid_installments`/`status`; anon has none |
| `households.household_type` present / `pay_installment_plan` present | 0 / false | Not applied yet, as expected |
| `create_household_and_claim(text)` / `(text, text)` | true / false | 900000 drops the 1-argument version and creates the 2-argument version with a default |
| function comments / public functions | `household_primary_admin_id, nafaqah_husband_id, nafaqah_is_spouse_member` / 62 | After: `pay_installment_plan` added / 79 |
| `cycle_key` NULL / differing from the server derivation / budget spent drift | 0 / 0 / 0 | No re-keying at apply time. The payday trigger fires only when `payday_day` changes, and no file updates it. |
| budgets / spent total / allocated total | 24 / **9112.42** / **20844.52** | Part B must print the same totals |
| accounts / balance total | 1 / **360.00** | — |
| payday distribution | `1:1,27:3` | Open cycle on 2026-10-21 is `2026-10` for both paydays |
| client privileges (TRUNCATE/TRIGGER/REFERENCES or anon DML) / client MAINTAIN (PG17) | 15 / 16 | 0 / 0 after the four files |
| `nafaqah_current_cycle_key` / `generate_secure_invite_code` executable by authenticated | true / true | false / false after |
| invite FK actions / invite policies | `created_by:a, used_by:a` / `invites_delete_admin, invites_insert_household, invites_select_household` | After: `n` / `c` and `invites_select_admin` |
| 800000 guard functions present | 8 / 8 | — |
| migrations recorded / last | 28 / `20261020600000` | — |
| `table_rows` | `account_transfers:0, accounts:1, api_quota:0, budgets:24, budgets_spent_backup_20261019:24, cost_control_codes:11, cost_control_sub_categories:27, household_category_settings:0, household_dependents:0, household_invites:1, household_memberships:4, households:4, income_records:0, installment_plans:0, invite_attempt_log:1, member_allowances:0, spouse_reimbursements:0, transactions:14, users:4` | Part B must print the same |

**Per household (aggregate shape, live = replica):**

| Payday | Owner | Members (role/financial role) | Tx | Budgets | Accounts | Invites | Plans | After 900000 |
|---|---|---|---|---|---|---|---|---|
| 27 | yes | admin/provider, member/family_member | 8 | 6 | 1 | 1 | 0 | family, provider = primary admin |
| 27 | yes | admin/provider | 5 | 11 | 0 | 0 | 0 | family, provider = primary admin |
| 1 | yes | admin/provider | 1 | 6 | 0 | 0 | 0 | family, provider = primary admin |
| 27 | no | (none) | 0 | 1 | 0 | 0 | 0 | family, provider NULL |

## 5. Replica results

| Run | Result |
|---|---|
| Replica vs live catalog (before) | Identical, including function definitions (CRLF-normalised) and function comments. The only differences are platform-only objects (realtime publication, `pg_stat_statements`, `supabase_vault`, schema ACL grantors). |
| Live-shaped replica vs live data checks | Part A: 80/81 equal. The exception is `tables_client_maintain_pg17`, which is NULL on PG16. Round-1 checks: 50/50. Distributions: identical. Per-household shape: identical. |
| 700000 → 750000 → 800000 → 900000 as `live_owner` on the live-shaped replica | All applied without error. The notices are exactly those in §6.2. |
| Row fingerprint before vs after (21 tables, the 3 new columns excluded) | **Identical** |
| Households after | `family` ×4. Provider = owner ×3, NULL ×1 (the memberless household). Roles: `admin/provider:3, member/family_member:1`. |
| `installment_plans_paid_installments_range` | `CHECK (((paid_installments >= 0) AND (paid_installments <= installment_count))) [validated]` |
| Totals before → after | spent 9112.42 → 9112.42, allocated 20844.52 → 20844.52, balance 360.00 → 360.00. Cycle keys `2026-10:14` / `2026-10:24`, unchanged. |
| Part B on the migrated replica | All values as in §7 |
| Full suite on a copy of the migrated live-shaped replica (`run_tests.py --psql --db …`) | **26/26** |
| Empty replica (reference data only), four files as the owner role, suite | **26/26**. Post-checks: 0 providers; 0 roommates / 0 family. |
| Empty replica, `run_tests.py --psql --apply-from 20261020700000` | **26/26** (applies the same four files) |
| Full repo rebuild (`run_tests.py --psql --rebuild`) | **26/26** |
| Migrated replica vs migrated repo HEAD rebuild | Identical apart from the pre-existing D6, D8, D9, D10, D11, D12 and the owner role name. The diff has exactly the shape of "live vs repo up to 600000", with D8's grants trimmed by 700000. |
| Four files re-run, in order, on the migrated replica | Clean, with the same notices. Catalog, function definitions, all 89 part-B values and the row fingerprint are unchanged (idempotent). |
| Rollback round trip | See §8. Both rollbacks are exact and refuse out of order; re-apply passes 26/26. |
| Functional smoke on the migrated live-shaped replica (in a transaction, rolled back; fingerprint unchanged afterwards) | See below |

Functional smoke results:

- **Member:**
  - sees 0 invites;
  - reads `household_type = family`;
  - `set_household_type` is refused with 42501.
- **Admin:**
  - sees 1 invite;
  - a direct UPDATE of `household_type` is refused with "permission denied";
  - `set_household_type(H1, 'family')` returns `changed=false`;
  - `set_member_financial_role(member, 'peer')` in a family household is refused with 22023;
  - `set_member_financial_role(member, 'dependent')` returns previous `family_member`.
- **Single-admin household, family → roommates:**
  - the provider becomes NULL and the role becomes `peer`;
  - changing back to family restores the provider to the primary admin and the role to `provider`.
- **`create_household_and_claim(p_name => …)` (the released app's call):** creates a `family` household whose provider is the creator.
- **Installments:**
  - a client UPDATE of `paid_installments` is refused with "permission denied";
  - a client call of `pay_installment_plan` is refused with "permission denied";
  - the service role's `pay_installment_plan` moves 1/4 to 2/4 `ACTIVE`;
  - `paid_installments = 9` on a 4-installment plan raises `check_violation`.
- **Totals afterwards:** unchanged.

## 6. Apply plan

### 6.1 Before you start

1. **Take a backup**, as in rounds 1 and 2: Dashboard → Database → Backups, or a `pg_dump` of `public` with data.
2. **Run part A** of [`live_db_preflight_round3_checks.sql`](live_db_preflight_round3_checks.sql) and compare it with §4.
   - Write down `budgets_spent_total`, `budgets_allocated_total`, `accounts_balance_total` and `table_rows`.
   - Stop and re-read §4 if any of these is no longer 0: `hh_owner_is_spouse`, `users_multi_membership`, `memberships_user_fr_null`, `users_fr_unknown`, `installment_plans_out_of_range` or `hh_with_peer_member`.
   - Also stop if `expected_hh_roommates` is no longer 0. A peer member would make that household `roommates`, with provider NULL.
3. **Pick a quiet moment.** The files take ACCESS EXCLUSIVE locks on `households`, `household_memberships`, `household_invites`, `users` and `installment_plans` for well under a second each (4 rows or fewer, 0 plans).

### 6.2 Order and method

**SQL editor, one file per run, in this order. Live runs each one as `postgres`.**

| # | File | What it does on live | Expected output |
|---|---|---|---|
| 1 | `20261020700000_fable_db_hardening.sql` | Re-creates the invite FKs (`created_by` SET NULL, `used_by` CASCADE). `reallocate_budget` fails closed. Revokes client EXECUTE on `nafaqah_current_cycle_key` and `generate_secure_invite_code`. Sets the client column lists on `households`, `household_dependents` and `users`. Revokes TRUNCATE/TRIGGER/REFERENCES, anon DML and MAINTAIN (PG17) on all 19 public tables. Ends with a guard that aborts on any mismatch. | "Success. No rows returned"; no notices |
| 2 | `20261020750000_installment_pay_atomic.sql` | Adds `pay_installment_plan(uuid, uuid, uuid)`: an atomic conditional increment, `SECURITY DEFINER`, EXECUTE for `service_role` only, with a comment. Changes no table and no data. | "Success. No rows returned"; no notices |
| 3 | `20261020800000_household_roles_and_nafaqah_integrity.sql` | Adds `household_memberships.financial_role` (backfilled: provider 3, family_member 1) and `households.nafaqah_provider_user_id` (backfilled: 3 = primary admin, 1 NULL). Adds the role, provider, invite-claim, ledger-guard and payday re-key triggers and functions. Makes invites admin-only. Budget triggers ignore `wife_personal`. | Notices: `guard: 0 user(s) belong to more than one household (their memberships are backfilled from users.financial_role)`, `guard: 0 classified (Nafaqah) transaction(s)`, `post-check: 3 household(s) have a Nafaqah provider`, plus eight harmless `trigger/policy "…" does not exist, skipping` from `DROP … IF EXISTS` |
| 4 | `20261020900000_household_type_and_round2_fixes.sql` | Adds `households.household_type text NOT NULL DEFAULT 'family'` with a CHECK (`family`/`roommates`). The backfill makes 0 households `roommates`, so all 4 are `family`. Financial roles follow the type. The provider is defaulted only at creation. Classification rights go to the wife, the provider or an admin (D2). A wife's ledger is removed when her membership ends (D3). Budget triggers skip settlement rows. Replaces `create_household_and_claim(text)` with `(text, text DEFAULT 'family')`. Adds `set_household_type` and `set_member_financial_role`. Adds the validated `installment_plans_paid_installments_range` CHECK. Clients lose UPDATE of `paid_installments`/`status`. `pay_installment_plan` counts only ACTIVE plans. The orphaned-ledger cleanup touches 0 rows. Ends with post-checks. | Notices: `guard: 0 installment plan(s) outside 0..installment_count (CHECK stays NOT VALID if > 0)`, `guard: 0 classified row(s) of a wife who is no longer a member (declassified by D3)`, `post-check: 0 roommates household(s), 4 family household(s)`, plus one harmless `trigger "trg_remove_nafaqah_ledger_on_membership_end" … does not exist, skipping` |

Each file is wrapped in `BEGIN … COMMIT`, and its guard and post-check blocks raise on any mismatch. A failure therefore leaves nothing half-applied: stop and keep the error text.

- The guards of 800000 and 900000 check their prerequisites: 900000 needs 750000's `pay_installment_plan` and 800000's columns and functions.
- **Keep the order.** The replica and suite results cover this order only.
- If the notice text differs from the table (for example "1 roommates household(s)"), the data changed after part A. The file has still been applied consistently, but compare part B with the new values.
- Whatever the SQL editor shows, part B is the authoritative check.

**Do not re-run a single earlier file after file 4.** Re-running file 2 or 3 alone (tested on the replica) brings back the 750000/800000 versions:

- `create_household_and_claim(text)` returns as a second overload, which makes `{p_name}` ambiguous for PostgREST;
- `pay_installment_plan` loses its ACTIVE-only rule;
- the provider trigger loses `household_type`.

If that happens, re-run file 4. That restores the exact post-apply catalog (tested). Re-running all four files in order is idempotent.

Alternative: `psql "<session-pooler connection string as postgres>" -v ON_ERROR_STOP=1 -f <file>`, run on each file in the same order. Each file has its own transaction, so do not add `--single-transaction`.

Then run part B (§7), deploy ai_service (its HEAD build calls `pay_installment_plan`), then release the app build. This is the README deployment order. The deployed backend and app (`origin/main`) keep working between steps:

- they call `create_household_and_claim` with `{p_name}` only;
- they write `installment_plans` with the service role;
- the HEAD app falls back to `{p_name}` against an older database.

Supabase reloads the PostgREST schema cache after DDL. If an RPC call returns PGRST202 right after file 4, wait a few seconds. Do not add another overload.

### 6.3 Recording the history

Live records the `20261020*` files with `version` = the 14-digit prefix and `name` = the rest of the file name. `statements`, `created_by`, `idempotency_key` and `rollback` are nullable, and `postgres` may INSERT. After **all four files and part B** succeed, the owner records them in one statement. This is a write, and it is safe to run twice:

```sql
INSERT INTO supabase_migrations.schema_migrations (version, name)
SELECT v, n FROM (VALUES
  ('20261020700000', 'fable_db_hardening'),
  ('20261020750000', 'installment_pay_atomic'),
  ('20261020800000', 'household_roles_and_nafaqah_integrity'),
  ('20261020900000', 'household_type_and_round2_fixes')
) AS m(v, n)
WHERE NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations s WHERE s.version = m.v);
```

On the replica, the first run printed `INSERT 0 4` and the second `INSERT 0 0`. Afterwards part B shows `migrations_recorded` 32, `last_migration` `20261020900000` and `round3_versions_recorded` 4.

The round-1 CLI warning still holds. Do not run `supabase db push`, `db reset --linked` or `migration up` against live until the DB-15 re-baseline is done (round 1 §5.3).

## 7. Post-apply verification (part B, read-only)

Run part B of [`live_db_preflight_round3_checks.sql`](live_db_preflight_round3_checks.sql) after file 4. Part B fails before the files are applied (verified on live today: `column "financial_role" does not exist`). These are the expected values on live, assuming no data changes in between. They are exactly what the migrated live-shaped replica printed, except `tables_client_maintain_pg17`, which is NULL there because of PG16.

Round-2 columns (unchanged expectations):

| Column | Expected |
|---|---|
| `households` / `memberships` / `users` / `invites` / `dependents` | 4 / 4 / 4 / 1 / 0 |
| `memberships_fr_null` / `membership_fr_not_null` / `users_fr_cache_mismatch` | 0 / true / 0 |
| `membership_role_x_fr` | `admin/provider:3,member/family_member:1` |
| `membership_fr_check` | `CHECK ((financial_role = ANY (ARRAY['provider'::text, 'spouse'::text, 'peer'::text, 'family_member'::text, 'dependent'::text])))` |
| `hh_with_provider` / `hh_provider_is_primary_admin` / `hh_provider_not_primary_admin` | **3 / 3 / 0** |
| `hh_owner_but_no_provider` / `hh_no_owner_no_provider` / `hh_provider_invalid` | 0 / **1** / 0 |
| `provider_fk` | `FOREIGN KEY (nafaqah_provider_user_id) REFERENCES users(id) ON DELETE SET NULL` |
| `invite_fk_actions` / `invite_policies` | `created_by:n,used_by:c` / `invites_delete_admin=DELETE,invites_insert_household=INSERT,invites_select_admin=SELECT` |
| `invites_select_qual` | `((household_id = ( SELECT get_auth_user_household_id() AS get_auth_user_household_id)) AND (( SELECT get_auth_user_role() AS get_auth_user_role) = 'admin'::text))` |
| `hh_auth_update_cols` | `monthly_income,name,payday_day,rollover_rule` (`household_type` is **not** in it) |
| `dependents_auth_update_cols` / `dependents_auth_insert_cols` | `avatar_icon,monthly_allowance,name,relationship` / `avatar_icon,created_at,household_id,id,monthly_allowance,name,relationship` |
| `users_auth_insert_cols` / `users_auth_update_cols` | `created_at,display_name,household_id,id,payday_day,role` / `display_name,payday_day` |
| `auth_can_update_provider` / `auth_can_write_memberships` | false / false |
| `tables_with_unneeded_client_privs` / `tables_service_role_truncate` / `tables_client_maintain_pg17` | **0** / 19 / **0** on live (NULL on PG16) |
| `auth_x_nafaqah_cycle_key` / `auth_x_gen_invite_code` / `svc_x_nafaqah_cycle_key` | false / false / true |
| `anon_x_reallocate` / `auth_x_set_provider` / `anon_x_set_provider` / `auth_x_rekey` / `auth_x_husband_id` | false / true / false / false / false |
| `new_functions_missing` | 0 |
| `membership_triggers` | `trg_clear_nafaqah_provider,trg_maintain_primary_admin,trg_membership_financial_role_cache,trg_membership_financial_role_rules,trg_prevent_last_admin_demotion,trg_protect_primary_admin,trg_remove_nafaqah_ledger_on_membership_end` |
| `households_triggers` | `trg_households_nafaqah_provider,trg_rekey_cycles_on_payday_change` |
| `invites_triggers` | `trg_refuse_invite_claim_by_member,trg_validate_invite_target_member` |
| `transactions_triggers` | `on_transaction_delete,on_transaction_insert,on_transaction_update,trg_bind_transaction_creator,trg_enforce_transaction_write_permission,trg_populate_transaction_cycle_key,trg_update_account_balance_on_transaction,trg_validate_category_transactions,trg_validate_transaction_nafaqah_class,trg_wife_ledger_guard` |
| `policies_to_public_or_anon` / `tables_without_rls` | 0 / 0 |
| `payday_distribution` | `1:1,27:3` |
| `transactions` / `tx_cycle_key_null` / `tx_cycle_keys` / `budget_cycle_keys` / `budgets` | 14 / 0 / `2026-10:14` / `2026-10:24` / 24. New transactions from 2026-10-27 on (payday 27) legitimately add `2026-11`. |
| `budgets_spent_total` / `budgets_allocated_total` / `accounts_balance_total` | equal to part A (9112.42 / 20844.52 / 360.00 on 2026-10-21) |

Round-3 columns (750000 / 900000):

| Column | Expected |
|---|---|
| `household_type_distribution` | **`family:4`** |
| `household_type_not_null` / `household_type_default` | true / `'family'::text` |
| `household_type_check` | `CHECK ((household_type = ANY (ARRAY['family'::text, 'roommates'::text])))` |
| `memberships_role_not_fitting_type` / `roommates_with_provider` / `auth_can_update_household_type` | 0 / 0 / false |
| `installment_range_check` | `CHECK (((paid_installments >= 0) AND (paid_installments <= installment_count))) [validated]` |
| `installment_auth_update_cols` | `category_code,day_of_month,installment_count,merchant,monthly_amount,notes,original_transaction_id,provider,start_date,total_amount` |
| `auth_installment_table_update` / `anon_installment_update` / `svc_installment_update` / `installment_plans` | false / false / true / **0** |
| `svc_x_pay_installment` / `auth_x_pay_installment` / `anon_x_pay_installment` | true / false / false |
| `create_hh_1arg_gone` / `auth_x_create_hh` / `anon_x_create_hh` | true / true / false |
| `auth_x_set_household_type` / `anon_x_set_household_type` / `auth_x_set_member_fr` / `anon_x_set_member_fr` | true / false / true / false |
| `auth_x_internal_r3` / `r3_functions_missing` | false / 0 |
| `provider_trigger_def` | `CREATE TRIGGER trg_households_nafaqah_provider BEFORE INSERT OR UPDATE OF owner_user_id, nafaqah_provider_user_id, household_type ON public.households FOR EACH ROW EXECUTE FUNCTION households_nafaqah_provider_rules()` |
| `tx_classified` / `member_allowances` / `spouse_reimbursements` | 0 / 0 / 0 |
| `function_comments` / `public_functions` | `household_primary_admin_id,nafaqah_husband_id,nafaqah_is_spouse_member,pay_installment_plan` / **79** |
| `table_rows` | identical to part A (see §4) |
| `migrations_recorded` / `last_migration` / `round3_versions_recorded` | 28 / `20261020600000` / 0 before §6.3; **32 / `20261020900000` / 4** after it |

Smoke test in the app, as in round 2, plus:

1. As an admin, create a new household from the released app. It is created normally, and the household is `family`.
2. As the admin, change and restore `payday_day`. It succeeds, and the budgets screen still shows the same totals.

## 8. Rollback notes

Undo in this order: first [`../rollback/20261020_round3_rollback_snapshot.sql`](../rollback/20261020_round3_rollback_snapshot.sql) (undoes 900000), then, if needed, [`../rollback/20261020_round2_rollback_snapshot.sql`](../rollback/20261020_round2_rollback_snapshot.sql) (undoes 800000, 750000 and 700000 together). Run each one in the SQL editor as `postgres`. Each is one transaction.

- **Guards (tested):**
  - the round-2 script refuses while `household_type` exists ("run 20261020_round3_rollback_snapshot.sql first");
  - the round-3 script refuses when 900000 is not applied;
  - the round-2 script refuses when 800000 is not applied.

  So neither script can run twice or out of order.
- **The round-3 rollback**, on the migrated live-shaped replica:
  - the catalog is identical to the replica with only 700000/750000/800000 applied: function definitions, EXECUTE, function comments (4) and the `installment_plans` grants (back to table-level UPDATE for authenticated);
  - `create_household_and_claim(text)` is back;
  - `household_type`, both new CHECKs and the new trigger are gone.
- **Then the round-2 rollback:**
  - the catalog is identical to the pre-apply replica, which equals live. That covers function definitions, EXECUTE grants, the 3 live function comments and the table and column privileges;
  - `pay_installment_plan` is gone;
  - the row fingerprint of all 21 tables is identical to the pre-apply data;
  - all 81 part-A values equal the pre-apply values.
- **Re-apply** of the four files afterwards gives the same notices, a catalog identical to the first apply, and all 89 part-B values identical. The suite passes 26/26.
- **Dirty database:** the same round trip on a copy on which the full suite had already run (8 households, extra memberships, plans and invites) gives the same catalog results. The re-apply passes 26/26.

The MAINTAIN block of the round-2 rollback still cannot be exercised locally (PG16); see round 2 §8. The round-3 rollback does not touch MAINTAIN: it changes only authenticated's UPDATE on `installment_plans`.

Data impact of a rollback, in addition to round 2 §8:

- the household types are lost, because the column is dropped;
- roles changed by `set_household_type` or `set_member_financial_role` stay as they are (valid 800000 values);
- D3 removals (a wife's ledger when her membership ends) are permanent;
- a provider left NULL after owner succession stays NULL;
- installment payments recorded through `pay_installment_plan` stay recorded.

## 9. PostgreSQL 17 notes

- MAINTAIN behaves as described in round 2 §9:
  - 700000 revokes it from clients on PG17;
  - part B checks `tables_client_maintain_pg17` (expected 0);
  - the round-2 rollback re-grants it behind a version check.
- 750000 and 900000 contain nothing version-dependent. The calls they use behave the same on PG16 and PG17: `REVOKE UPDATE ON … FROM …` plus a column-level `GRANT UPDATE (…)`, `ADD CONSTRAINT … NOT VALID` / `VALIDATE CONSTRAINT`, `DROP FUNCTION IF EXISTS`, `pg_get_triggerdef` and `has_*_privilege`.
- Live's default privileges for `postgres` in `public` grant EXECUTE on new functions to anon, authenticated and service_role, and the replica emulates that. Every function that 900000 creates is explicitly revoked from PUBLIC and anon, and from authenticated where it is internal. Part B checks the result.

## 10. Artefacts

- [`live_db_preflight_round3_checks.sql`](live_db_preflight_round3_checks.sql): part A (before) and part B (after). Read-only, SELECT only. Part A was validated on live today and on the replica; part B on the migrated replica, before and after the history INSERT.
- [`../rollback/20261020_round3_rollback_snapshot.sql`](../rollback/20261020_round3_rollback_snapshot.sql) and [`../rollback/20261020_round2_rollback_snapshot.sql`](../rollback/20261020_round2_rollback_snapshot.sql): the tested rollbacks, unchanged.
- Scratch tooling (not committed): today's live inventory (with function comments), the replica generator, `build_shaped.sh` / `apply4.sh` / `roundtrip.sh`, the per-household shape query, the row fingerprint and the functional smoke.
