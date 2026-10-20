# Database / Supabase Audit (Round 7)

Scope: `supabase/schema.sql`, `supabase/seed.sql`, `supabase/migrations/*`, `supabase/tests/*`, cross-checked against
the Flutter / ai_service call sites that depend on them. The whole chain was rebuilt from scratch on a local
PostgreSQL 16 with Supabase platform stubs (`supabase/tests/00_local_supabase_stubs.sql`). The live project
was not touched: no connection, migration, or query was made against it. "Confirmed" means reproduced on the
replayed schema. Live may differ (see DB-15), so each fix ships with a catalog check under
[Owner actions](#owner-actions).

Branch: `worktree-agent-a56ddfb476d55d771` · Base: `f17eb2b`

## Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| DB-01 | Critical | `household_invites` has no RLS: anon reads every invite code, any user forges an invite to any household and joins it | Fixed `4fef446`, test 08 |
| DB-03 | Critical | `reallocate_budget` (SECURITY DEFINER, no checks) is executable by anon: cross-household budget rewrite | Fixed `7e3f326`, test 10 |
| DB-02 | High | Recursive `memberships_admin_manage` policy: every authenticated read of memberships and every receipts storage policy fails | Fixed `83776af`, test 09 |
| DB-04 | High | `cost_control_codes` insert/update policies (role PUBLIC) let anon/any user write categories into any household | Fixed `31c6a7b`, test 11 |
| DB-05 | High | Targeted invites always fail (`claimed_user_id` column does not exist), and the target member is not household-scoped | Fixed `4fef446`, test 08 |
| DB-06 | Medium | Transfers with a third decimal mint money (1.005 debits 1.00 and credits 1.01); `record_income` accepts negative components and invalid cycle keys | Fixed `729d0d7`, test 12 |
| DB-07 | Medium | Clients can still INSERT `income_records` directly, which forges the income ledger | Fixed `729d0d7`, test 12 |
| DB-08 | Medium | Clients can overwrite `transactions.cycle_key` to move spending out of a budget cycle | Fixed `a565bc8`, test 13 |
| DB-12 | Medium | A sole admin cannot delete their account, and the delete cascade would destroy the household's shared pools | Fixed `070a662`, test 16 |
| DB-14 | Medium | Existing DB tests masked failures (`ON_ERROR_STOP off`, handlers that swallow their own assertion, test 03 re-creating the policies it tests) | Fixed `c12baba` |
| DB-15 | Medium | The migration chain cannot be replayed as shipped (dependency order, duplicate version prefix), and live has drifted from it | Partially fixed `c12baba` (local replay). CLI/live baseline: owner action |
| DB-09 | Low | `sync_user_household_membership()` is SECURITY DEFINER with no pinned `search_path` | Fixed `f17e6c6`, test 14 |
| DB-10 | Low | Clients can INSERT households directly, which bypasses the quota and gives an invite-code existence oracle | Fixed `f17e6c6`, test 14 |
| DB-11 | Low | Receipts bucket has no size or MIME limits | Fixed `e1761b4`, test 15 |
| DB-13 | Low (perf) | RLS helpers run per row; 6 foreign keys and the lockout lookup have no index | Fixed `4271db6`, test 17 |
| DB-16 | Medium (suspected / design) | Any household member can move the whole shared pool into their own account with `transfer_between_accounts` | Fixed (owner decision: admins only) `59a422d`, test 20 |
| DB-17 | Low | Non-admin members can read `households.invite_code` directly, which bypasses the SEC-08 masking | Not fixed: released app builds read the column directly (see below) |
| DB-18 | Low (suspected / design) | `transactions.user_id` is not bound to the caller, and members can edit or delete each other's transactions | Fixed (owner decision: creator bound, owner-or-admin edits) `59a422d`, test 20 |

## Test results

| Run | Command (see [How to run](#how-to-run-the-db-tests-locally)) | Result |
|---|---|---|
| Baseline: original suite, shipped schema, plain psql | `run_tests.py --psql --rebuild` at `f17eb2b` + runner | 2 passed / 5 failed. Fixtures assumed the drifted live dump: missing `auth.users` rows, `users.email`, `account_type` 'checking', NOT NULL `keywords` |
| Baseline after fixture-only adaptation (`c12baba`) | same | **5 passed / 2 failed**. 01 fails: anon reads invites (DB-01). 03 fails: membership policy recursion (DB-02). 07 had been passing only because its errors were ignored (DB-14) |
| New audit tests on the pre-fix schema | all 17 files against `c12baba` migrations | **5 passed / 12 failed**. Every new test fails for the documented reason |
| After fixes, fresh database rebuilt from scratch | `run_tests.py --psql --rebuild --db bt_audit_final` | **17 passed / 0 failed** (98 PASSED assertions), and 17/17 again on a second run against the same database |
| Concurrency stress (not committed; script in the session scratchpad) | 4 parallel sessions, 1,200 transfers A→B and B→A | 0 deadlocks / 0 errors. Money conserved: 200,000.00 − 60.00 fees = 199,940.00 |
| Admin permissions and co-admins (DB-16 / DB-18), fresh rebuild | `run_tests.py --psql --rebuild --db bt_perms` | **20 passed / 0 failed** (test 20: 10 sections, roommate and family households) |
| RLS overhead, 50k transactions in one household | `EXPLAIN ANALYZE SELECT count(*) …` as `authenticated` | 55 ms → 11 ms (per-row policy calls became an InitPlan) |

## How to run the DB tests locally

Requires PostgreSQL 16+ and `psql`. Docker is not needed.

```bash
# Rebuild a throwaway database (stubs + schema.sql + seed.sql + migrations) and run every test
PGHOST=localhost PGPORT=54329 PGUSER=postgres \
  python3 supabase/tests/run_tests.py --psql --rebuild --db bt_audit_tests

# Re-run tests against an existing database without rebuilding
PGHOST=localhost PGPORT=54329 PGUSER=postgres \
  python3 supabase/tests/run_tests.py --psql --db bt_audit_tests

# Run a subset
PGHOST=localhost PGPORT=54329 PGUSER=postgres \
  python3 supabase/tests/run_tests.py --psql --db bt_audit_tests supabase/tests/12_audit_ledger_integrity.sql

# Legacy Docker mode (unchanged default): docker exec budget_tracker_review_pg psql …
DB_NAME=live_rebuilt_round5 python3 supabase/tests/run_tests.py
```

`--rebuild` applies `00_local_supabase_stubs.sql` (local stand-ins for `auth.*`, `storage.*`, API roles, the
`extensions` schema, the realtime publication and Supabase's default `public` grants), then `schema.sql`,
`seed.sql`, and every migration in replay order. Never point `--rebuild` at a hosted project.

---

## Details

### DB-01: `household_invites` has no RLS (Critical)

- **Where:** `supabase/migrations/20261015_family_nafaqah_and_multi_roommate_settlement.sql:9-18` creates the
  table and never runs `ENABLE ROW LEVEL SECURITY`. The policies in
  `20261019030000_sec01_sec02_household_takeover_prevention.sql:71-95` are therefore inert.
- **Root cause:** Supabase grants SELECT/INSERT/UPDATE/DELETE on `public` tables to `anon` and `authenticated`.
  Without RLS, those grants decide access.
- **Reproduction:** As `anon`, `SELECT invite_code FROM household_invites` returns every code. As any
  authenticated user, `INSERT INTO household_invites (household_id, invite_code, …) VALUES ('<victim hh>', 'X', …)`
  followed by `join_household_by_code('X')` makes the caller a member of the victim household with full read
  access. `UPDATE … SET used_by = NULL, expires_at = …` also re-opens used or expired invites. The pre-existing
  test 01 already failed on this (`Anon user can see 1 household invites`).
- **Impact:** Anyone can take over member-level access to every household (transactions, receipts, accounts,
  income).
- **Fix (`20261020010000_audit_invites_rls_and_targeted_claims.sql`):** enable RLS and revoke `anon`. Also gives
  `claim_household_role_invite` the same 5-failures/15-minutes lockout and attempt logging as
  `join_household_by_code`; before this it had none.
- **Status:** Fixed in `4fef446`. Test: `08_audit_invites_rls_and_targeted_claims.sql`, plus test 01.

### DB-02: Recursive policy on `household_memberships` (High)

- **Where:** `supabase/migrations/20261018_household_memberships_and_switching.sql:27-36`
  (`memberships_admin_manage`, FOR ALL, role PUBLIC).
- **Root cause:** The USING clause selects from `household_memberships` inside its own policy, so Postgres
  raises `infinite recursion detected in policy for relation "household_memberships"` (42P17).
- **Reproduction:** As `authenticated`, `SELECT count(*) FROM household_memberships` raises 42P17. So does
  `SELECT … FROM storage.objects`, because every receipts policy (20261019060000) consults the table. The
  pre-existing test 03 failed with this error.
- **Impact:** Receipt upload, view and delete through the Storage API fail for every user. The Flutter
  household-switcher fallback and any client roster read fail too. Had the policy evaluated, admins could also
  INSERT, UPDATE or DELETE membership rows directly. That would bypass `remove_member`/`leave_household`, which
  reset `users.household_id`, and leave a removed user with full access.
- **Fix (`20261020020000_audit_membership_policy_recursion.sql`):**
  - Drop the policy.
  - Add a single SELECT policy (`own rows OR is_household_admin(household_id)`). The new helper is
    SECURITY DEFINER, so the check does not recurse.
  - Revoke client writes. Membership changes now go only through the RPCs.
  - Backfill memberships for any `users.household_id` that has none.
  - `get_auth_user_household_id()` and `get_auth_user_role()` now require a live membership row for the
    active household, so a stale pointer never grants access.
- **Status:** Fixed in `83776af`. Test: `09_audit_membership_policies.sql`, plus test 03.

### DB-03: `reallocate_budget` is callable by anon (Critical)

- **Where:** `supabase/schema.sql:181-202`. No later migration redefined or revoked it.
- **Root cause:** SECURITY DEFINER, no `auth.uid()` or household check, no amount validation, and the default
  `EXECUTE` grant to PUBLIC.
- **Reproduction:** As `anon`: `SELECT reallocate_budget('<budget A>', '<budget B>', 900)` moves 900 SAR of
  allocation between any two budget rows, in any household and across households. Negative amounts are
  accepted too.
- **Impact:** Anyone holding the public anon key can tamper with any household's budget by UUID. Budget UUIDs
  leak through realtime payloads and shared screenshots.
- **Fix (`20261020030000_audit_reallocate_budget_authz.sql`):**
  - `EXECUTE` is granted only to `authenticated` and `service_role`.
  - JWT callers must be admin of the household that owns both rows.
  - Both rows must be in the same household.
  - The amount must be > 0, have at most 2 decimals, and be no more than the source allocation.
  - Rows are locked in id order.
  - ai_service calls with the service role key and keeps working without a user JWT.
- **Status:** Fixed in `7e3f326`. Test: `10_audit_reallocate_budget_authz.sql`.

### DB-04: `cost_control_codes` write policies are not household-scoped (High)

- **Where:** `supabase/migrations/20261011_hybrid_category_lifecycle.sql:38-45`. SEC-01/02 replaced only the
  SELECT policy.
- **Root cause:** `cost_control_codes_insert` and `_update` apply to role PUBLIC and check only
  `household_id IS NOT NULL AND is_system = false`.
- **Reproduction:** As `anon`, `INSERT INTO cost_control_codes (code, …, household_id) VALUES (…, '<victim hh>')`
  succeeds. An authenticated outsider can do the same, and can also move their own category into another
  household with UPDATE.
- **Impact:** An outsider can pollute a victim household's categories, for example with phishing text in names
  shown in the app. They can also squat on `(household_id, code)` so the household cannot create that code.
- **Fix (`20261020040000_audit_cost_control_codes_policies.sql`):** writes are allowed only for admins of the
  caller's active household, on non-system rows of that household. There is no client DELETE path, and anon is
  revoked. ai_service uses the service role and is unaffected.
- **Note:** FIX_LOG SEC-02 states "Zero policies with role `{public}` remain". That is not true for the
  replayed chain: these two policies and DB-02's policy are PUBLIC. Verify on live.
- **Status:** Fixed in `31c6a7b`. Test: `11_audit_cost_control_codes_policies.sql`.

### DB-05: Targeted (manual-member) invites are broken (High)

- **Where:** `supabase/migrations/20261019100000_sec08_round6_hardening.sql:652-656` (join) and `:738-742`
  (claim).
- **Root cause:** Both functions run `UPDATE household_dependents SET claimed_user_id = …`. The column is
  `linked_user_id` (20261015_manual_members_and_claim_merge.sql:6). PL/pgSQL resolves the name only at run
  time, so the bug appears only when an invite carries `target_member_id`. In addition,
  `target_member_id` was never checked against the invite's household.
- **Reproduction:** Any invite with `target_member_id` fails with
  `ERROR: column "claimed_user_id" of relation "household_dependents" does not exist`, from both RPCs.
- **Impact:** The "claim a pre-created family member" flow (ai_service `/households/invites/{code}/claim`) is
  broken. Once fixed naively, a service-created invite could also link a dependent of another household.
- **Fix:** Use `linked_user_id`, scoped to the invite's household. Add a BEFORE INSERT/UPDATE trigger that
  rejects a `target_member_id` from another household; it also binds service-role inserts. Same migration
  as DB-01.
- **Status:** Fixed in `4fef446`. Test: `08_audit_invites_rls_and_targeted_claims.sql`.

### DB-06: Ledger precision and income validation (Medium)

- **Where:** `supabase/migrations/20261019100000_sec08_round6_hardening.sql:244-479`
  (`transfer_between_accounts`, `record_income`).
- **Root cause:** The parameters are unconstrained `NUMERIC`, while `accounts.balance` and
  `account_transfers.amount` are `NUMERIC(14,2)` and `fee` is `NUMERIC(10,2)`. Each side of a transfer is
  rounded on its own. `record_income` accepted negative components (negative deductions inflate net) and any
  `cycle_key` text.
- **Reproduction:** Two transfers of `1.005` between your own accounts (A=100, B=0) leave A=100.01 and B=0.01.
  That is 0.02 SAR created, with each log row saying 1.01. The amount can be repeated without limit.
- **Impact:** Account balances no longer add up to the transfers and income recorded against them, and
  households see wrong numbers in their totals.
- **Fix (`20261020050000_audit_ledger_precision_and_income_append_only.sql`):**
  - Reject amounts and fees with more than 2 decimals (22023).
  - Reject negative income components, an empty title, and a `cycle_key` that is not `YYYY-MM`.
  - When `cycle_key` is NULL, derive it from `received_at` and the household payday.
  - Lock order was already deterministic and the overdraft check already present; both are verified by the
    stress run (0 deadlocks in 1,200 opposite-direction transfers).
- **Status:** Fixed in `729d0d7`. Test: `12_audit_ledger_integrity.sql`.

### DB-07: Clients can INSERT into the income ledger directly (Medium)

- **Where:** `supabase/migrations/20261019090000_sec05_accounts_security_and_transfers.sql:149-154`
  (`income_insert_household`). SEC-08 dropped only UPDATE and DELETE.
- **Reproduction:** A member inserts `income_records` with another member's `account_id` and
  `net_amount = -5000`, and the insert succeeds.
- **Impact:** Forged income history that budgets, rollover and the payday banner read. It bypasses
  `record_income`'s account-ownership check, sign check and balance update. A later admin or service-role
  delete of the forged row would then move the real balance through `adjust_account_balance_on_income_change`.
- **Fix:** Drop the policy. `income_records` and `account_transfers` become read-only for clients; writes go
  through the SECURITY DEFINER RPCs only. Flutter already uses `record_income`.
- **Status:** Fixed in `729d0d7`. Test: `12_audit_ledger_integrity.sql`, plus test 07.

### DB-08: Clients can relabel a transaction's cycle (Medium)

- **Where:** `supabase/migrations/20261019080000_bug02_payday_cycle_parity_and_triggers.sql:131-135`.
- **Root cause:** `trg_populate_transaction_cycle_key` fires only on `UPDATE OF timestamp, household_id`.
- **Reproduction:** A member runs `UPDATE transactions SET cycle_key = '1999-01' WHERE id = …`. The value is
  kept, and `update_budget_on_transaction_update` moves the 200 SAR out of the 2026-11 budget, whose
  `spent_amount` drops to 0.
- **Impact:** A member can hide overspending from the household budget.
- **Fix (`20261020060000_audit_transaction_cycle_key_integrity.sql`):** the trigger also fires on
  `UPDATE OF cycle_key`, so the server-derived key always wins. The migration does no backfill on purpose: a
  difference can also come from a legitimate payday change. See the detection query under Owner actions.
- **Cycle logic review (no defect found):** `get_saudi_cycle_for_timestamp` was checked exhaustively for
  payday 1..31 on every day of 2026-2029:
  - Every day falls inside its cycle, with no gaps or overlaps.
  - Each new cycle starts the day after the previous one ends.
  - Keys advance exactly one month at a time.
  - Specific cases pass: 23:59:59 vs 00:00 Riyadh on the 26th/27th, Dec→Jan, payday 31 in February, payday 30
    on 29 Feb 2028, payday 31 in 30-day months, payday 1 near UTC midnight, and Oct 28 → `2026-11`.

  These checks are committed as a regression in test 13.
- **Status:** Fixed in `a565bc8`. Test: `13_audit_cycle_key_integrity.sql`.

### DB-09: Unpinned `search_path` on a SECURITY DEFINER trigger function (Low)

- **Where:** `supabase/migrations/20261018_membership_sync_and_shared_account_policies.sql:28`.
- **Fix:** `ALTER FUNCTION … SET search_path = public, pg_temp`. Test 14 adds a guardrail: every SECURITY
  DEFINER function in `public` must pin `search_path`.
- **Status:** Fixed in `f17e6c6`. Test: `14_audit_catalog_guardrails.sql`.

### DB-10: Clients can INSERT households directly (Low)

- **Where:** `supabase/migrations/20261019030000_sec01_sec02_household_takeover_prevention.sql:639-643`.
- **Impact:**
  - Bypasses `create_household_and_claim`'s limit of 5 households per user and its server-generated 16-hex
    invite code.
  - `INSERT … (invite_code = '<guess>')` returns a UNIQUE violation (23505) when the guess exists, so any
    user can test whether a static join code exists with no rate limit.
- **Fix:** Drop the policy and revoke INSERT, DELETE and TRUNCATE from clients. No client inserts households
  directly.
- **Status:** Fixed in `f17e6c6`. Test: `14_audit_catalog_guardrails.sql`.

### DB-11: Receipts bucket has no upload limits (Low)

- **Where:** `supabase/migrations/20261008_create_receipts_bucket_and_policies.sql:4-6` and
  `20261019060000_sec06_private_receipts_bucket.sql`.
- **Root cause:** `file_size_limit` and `allowed_mime_types` were never set. The storage policy checks only
  the extension in the file name.
- **Fix:** 20 MiB limit, and only `image/jpeg`, `image/png` and `image/webp`.
  - 20 MiB covers ai_service's stitched multi-shot receipts: a 25 MB base64 request body is about 18.75 MB
    of binary.
  - Flutter uploads JPEGs of at most 1600 px.
  - The Storage API enforces these limits.
- **Status:** Fixed in `e1761b4`. Test: `15_audit_receipts_bucket_limits.sql`.

### DB-12: A sole admin cannot delete their account (Medium)

- **Where:** `supabase/migrations/20261019030000_sec01_sec02_household_takeover_prevention.sql:497-534`
  (`check_last_admin_membership`), together with
  `20261018_multi_source_income_and_accounts.sql:11` (`accounts.owner_user_id … ON DELETE CASCADE`).
- **Reproduction:** `DELETE FROM auth.users WHERE id = <sole admin with members>` fails with
  `Cannot remove the sole admin while other household members remain`. This is the path used by the Supabase
  Auth admin API and in-app account deletion.
- **Impact:** Account-deletion requests cannot be honoured (PDPL and app-store rules require them). If the
  trigger were simply relaxed, the cascade would also delete every shared-pool account that admin created.
- **Fix (`20261020090000_audit_sole_admin_account_deletion.sql`):** a BEFORE DELETE trigger on `public.users`
  hands the household over before the cascade runs:
  - It promotes the longest-standing member (membership and `users.role`).
  - It re-owns that user's shared pools to an admin of the household.
  - Direct demotion or removal of a sole admin stays blocked; BUG-03 is unchanged and re-asserted in test 16.
- **Status:** Fixed in `070a662`. Test: `16_audit_account_deletion.sql`.

### DB-13: Per-row RLS evaluation and missing indexes (Low, performance)

- **Root cause:**
  - Policies call `auth.uid()`, `get_auth_user_household_id()` and `get_auth_user_role()` unwrapped, so they
    run once per row.
  - `transactions_select_household` also re-parsed the JWT for every row (`auth.uid() IS NOT NULL`).
  - Six foreign keys had no supporting index: `transactions.reallocated_from_budget_id`,
    `household_invites.{household_id, created_by, used_by}`, `account_transfers.user_id` and
    `income_records.user_id`. The two `user_id` columns are scanned by the account-deletion cascade.
  - The invite lockout count on `invite_attempt_log (user_id, attempted_at)` was unindexed and runs on every
    join attempt.
- **Fix (`20261020100000_audit_rls_initplan_and_fk_indexes.sql`):**
  - Every policy in `public` and the receipts policies in `storage` was re-created with
    `(SELECT …)`-wrapped calls. Names and semantics are unchanged.
  - The legacy `household_id IN (SELECT household_id FROM users …)` form now uses the membership-backed
    helper.
  - Receipts policies resolve households from memberships only.
  - Seven indexes were added.
  - Measured: 55 ms → 11 ms for a 50k-row household scan.
- **Status:** Fixed in `4271db6`. Test: `17_audit_rls_performance.sql` is a guardrail: no unwrapped helper in
  any policy, and every foreign key indexed.

### DB-14: Tests that could not fail (Medium, test integrity)

- **Problems:**
  - `07_sec08_round6_hardening.sql` wrapped every block in `\set ON_ERROR_STOP off`, so `RAISE EXCEPTION
    'VULNERABILITY…'` never failed the run. Its TEST 3 fixture actually errored (`income_records.cycle_key`
    NOT NULL), so the income-ledger assertions never ran.
  - Tests 4, 5 and 7 in that file caught `raise_exception` or `OTHERS` around their own VULNERABILITY raise,
    so they could not fail even with `ON_ERROR_STOP` on.
  - `03_sec06_private_receipts.sql` redefined `storage.foldername()` and `storage.extension()` and
    re-created the three receipts policies inside the test. It tested its own copy, not the migration.
  - In `06_sec05…sql`, subtest 1 inserted `account_type = 'checking'` (violates the CHECK) under
    `WHEN OTHERS`, so it passed on the CHECK error rather than on RLS.
- **Fix:** Remove `ON_ERROR_STOP off`, use flag-based assertions, use the shipped policies and helpers, expect
  `insufficient_privilege`, and correct the fixtures to the migrated schema. FIX_LOG's SEC-06 and SEC-08
  "verified" claims should be read in this light: test 03 would have failed on the replayed chain (DB-02).
- **Status:** Fixed in `c12baba`.

### DB-15: Migration chain is not replayable, and live has drifted (Medium, process)

- **Findings:**
  - `20261018_membership_sync_and_shared_account_policies.sql` creates a policy on `public.accounts`, which is
    created only by `20261018_multi_source_income_and_accounts.sql`. Filename (lexical) order applies them the
    wrong way round, so the chain fails.
  - Three files each share the version prefixes `20261008` and `20261018`, and two each share `20260925`,
    `20261002`, `20261005`, `20261009`, `20261011` and `20261015`. The Supabase CLI keys `schema_migrations` on that prefix,
    so `supabase db reset` / `db push` will reject the duplicates.
  - The original tests only worked against a dump of live: `users.email`, `account_type` values
    'checking'/'savings', nullable `cost_control_codes.keywords`, and public `users` rows without `auth.users`
    (suspected missing FK). Live therefore differs from what the migrations build.
- **Fix:** `run_tests.py --rebuild` replays with an explicit dependency override and documents why. Shipped
  migrations were not renamed (rule: never edit shipped migrations).
- **Status:** Partially fixed in `c12baba`. The live baseline is an owner action.

### DB-16: Shared pool can be drained by any member (resolved by owner decision)

`transfer_between_accounts` let any household member transfer from a shared pool into their own personal
account (`20261019100000…sql:308-311`). Direct edits and `reconcile_account_balance` on shared pools were
already admin-only.

- **Owner decision (family and roommate households):** only household admins move money out of a shared
  pool. Members still move money between their own personal accounts and pay into the pool. Expenses
  recorded against the pool are not transfers and stay allowed for members (roommates spend from the pool);
  they are attributed to their creator (DB-18) and visible to everyone.
- **Fix (`20261020400000_admin_permissions_and_co_admins.sql`):** `transfer_between_accounts` raises
  `42501` when the source is a shared pool and the caller is not an admin of the household (primary admin or
  co-admin). The app offers pools as a transfer source to admins only.
- **Status:** Fixed in `59a422d`. Test: `20_admin_permissions_and_co_admins.sql` §5.

### DB-17: Members can read the static join code (Low, still open)

`households_select_own` exposes `households.invite_code` to every member. SEC-08 hides it only in
`get_user_households()`. The current app reads the code through that RPC (MOB-25), but:

- Column privileges cannot be limited to non-admins: `REVOKE SELECT (invite_code) ON public.households FROM
  authenticated` also removes the column from admins' direct reads.
- Released app builds (`main`) render the whole household settings section from
  `households.select('name, invite_code')` (`ingestion_settings_screen.dart:129`) and fall back to an
  embedded `households(name, invite_code)` select in `budget_api_client.dart:594`. With the revoke both
  queries fail with `42501`, so every user of an older build, admins included, loses the household name,
  member list, payday, income and rollover settings.

**Decision:** not tightened in this round. Apply `REVOKE SELECT (invite_code) ON public.households FROM
authenticated` together with a matching column-list `GRANT SELECT` once builds older than this branch are
retired. Until then a non-admin who reads the table directly still sees the join code.

### DB-18: Transaction attribution bound to the caller (resolved by owner decision)

`transactions_insert_household` and `_update_household` did not bind `user_id` to `auth.uid()`, and any
member could edit or delete any other member's transaction that had no personal account attached. In
multi-roommate settlement this allowed attribution spoofing.

- **Owner decision (family and roommate households):** a member creates transactions and edits or deletes
  only their own. Only household admins edit or delete another member's transactions. The creator is bound
  at insert.
- **Fix (`20261020400000_admin_permissions_and_co_admins.sql`):**
  - `trg_bind_transaction_creator` (BEFORE INSERT): a client insert without `user_id` (older app builds) gets
    `auth.uid()`; naming anyone else raises `42501`. The insert policy also requires `user_id = auth.uid()`.
  - `trg_enforce_transaction_write_permission` (BEFORE UPDATE/DELETE): the creator can never change; a
    non-admin touching someone else's row (or a legacy row with no creator) gets `42501`. It raises instead
    of hiding the row through RLS so clients, including older builds, report a refusal rather than a silent
    no-op. Writes issued by other triggers (`pg_trigger_depth() > 1`: foreign-key `SET NULL`/`CASCADE` on
    account, spouse or household deletion) pass.
  - `transactions_update_household` keeps household scoping in `USING` and repeats owner-or-admin in
    `WITH CHECK`; a transaction's personal account must belong to its creator
    (`transaction_account_matches`, definer because an admin cannot read a member's personal account).
  - `update_account_balance_on_transaction` lets an admin's edit or delete of a member's own transaction
    adjust that member's personal account; nobody can attach a transaction to someone else's account.
  - The service role bypasses all of this; `ai_service` passes the verified JWT user as the creator and
    checks owner-or-admin itself (enrichment, installment linking, settlements).
- **Legacy rows:** transactions created before this migration through `ai_service` or most app screens have
  `user_id IS NULL` (the creator was never recorded). They are admin-only from now on; no creator is guessed. **Owner decision (2026-10-20): keep it this way** — admins edit legacy rows, every new row is attributed to the user who entered it.
- **Status:** Fixed in `59a422d`. Test: `20_admin_permissions_and_co_admins.sql` §3, §4, §10.

### Household roles: co-admins and the primary admin (owner decision)

- `households.owner_user_id` is the primary admin, backfilled from the longest-standing admin membership and
  kept by triggers: the first admin of a new household becomes primary; when the primary admin's membership
  ends (leave, removal by themselves, account deletion), the longest-standing remaining admin takes over
  (after the DB-12 handover promoted one if needed). Clients cannot write the column (column-list `UPDATE`
  grant on `households`).
- `promote_member_to_admin`, `revoke_admin`, `transfer_primary_admin`, `get_household_members`: SECURITY
  DEFINER, pinned `search_path`, caller resolved from the JWT (the service role passes `p_actor_user_id`;
  an authenticated caller can never act for someone else), household-scoped.
  - Any admin promotes members and revokes co-admins (themselves included).
  - Nobody can demote the primary admin (`trg_protect_primary_admin`), and only the primary admin can end
    their own membership.
  - Only the primary admin transfers primary admin; the target becomes an admin if needed and the previous
    primary stays a co-admin.
- `set_member_role` / `remove_member` (active household) now go through the same rules.
  `get_user_households()` also returns `is_primary`.
- The last-admin protections (BUG-03 trigger, DB-12 account deletion handover) are unchanged.
- Family Nafaqah: the husband or any household admin (co-admins included, never the wife herself) sets the
  wife's allowance; `nafaqah_husband_id` now prefers the primary admin among provider members.

## Owner actions

1. **Before applying, check the live catalog** (read-only, SQL editor):
   ```sql
   SELECT relname, relrowsecurity FROM pg_class WHERE oid = 'public.household_invites'::regclass;          -- DB-01
   SELECT policyname, roles FROM pg_policies WHERE tablename IN ('household_memberships','cost_control_codes'); -- DB-02/04
   SELECT has_function_privilege('anon','public.reallocate_budget(uuid,uuid,numeric)','EXECUTE');          -- DB-03
   SELECT count(*) FROM pg_attribute WHERE attrelid='public.household_dependents'::regclass AND attname='claimed_user_id'; -- DB-05
   ```
2. Apply `supabase/migrations/20261020010000_*` through `20261020100000_*` in order, each in its own
   transaction, after review. They are idempotent re-definitions plus one bucket UPDATE. On a hosted project
   the bucket UPDATE needs the storage schema owner, which is the default for the SQL editor.
3. **DB-08 detection** (rows whose stored key differs from the derivation, e.g. tampering):
   ```sql
   SELECT t.id, t.household_id, t.cycle_key,
          (SELECT c.cycle_key FROM public.get_saudi_cycle_for_timestamp(t.timestamp, h.payday_day) c) AS expected
   FROM public.transactions t JOIN public.households h ON h.id = t.household_id
   WHERE t.cycle_key IS DISTINCT FROM
         (SELECT c.cycle_key FROM public.get_saudi_cycle_for_timestamp(t.timestamp, h.payday_day) c);
   ```
4. **DB-15:** take a fresh baseline from live (`supabase db pull`), squash or rename the duplicate-prefix
   migrations in a new baseline, and point CI at `run_tests.py --psql --rebuild`.
5. DB-16 and DB-18 are decided and fixed (`20261020400000_admin_permissions_and_co_admins.sql`; apply after
   `20261020300000_*`). Before applying, check how many live transactions have no creator
   (`SELECT count(*) FROM public.transactions WHERE user_id IS NULL;`): those become admin-only.
   Schedule DB-17 once older app builds are retired.

## Cross-team notes (outside `supabase/`, not changed here)

- **Flutter:** `flutter_app/lib/widgets/dashboard/payday_checkin_banner.dart:42-46` filters
  `income_records` on `income_type`, but the column is `source_type`. The query errors, the catch swallows
  it, and the payday check-in banner never shows.
- **ai_service:** `ai_service/salary_cycle.py:44` (`get_cycle_for_date`) uses
  `datetime.now(timezone.utc).date()`. Between 00:00 and 03:00 Riyadh on payday it reports the previous
  cycle, while the DB (Asia/Riyadh) reports the new one.
- **ai_service:** the invite-claim route should surface the new lockout error from
  `claim_household_role_invite`, `Too many failed join attempts…`, as HTTP 429.
- **Informational:** `consume_quota` / `check_quota_status` assign `timezone('utc', now())`, a timestamp
  without time zone, to a `timestamptz` variable. Window boundaries therefore depend on the session
  `TimeZone`. That is harmless while PostgREST sessions stay on UTC, the Supabase default.
