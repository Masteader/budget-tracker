# In-app account deletion with a 30-day grace period (Qawam Money / قوام المال)

**Sensitive:** yes, because it changes `supabase/migrations/**`, RLS, role and membership lifecycles, ledger FKs and auth screens, and permanently deletes data using the service-role key. It needs Rounds 1 and 2 (Opus 5.5 high) and Round 3 (Fable high).

Replaces the draft `2026-11-05-account-deletion-grace-period.md`. Findings below came from reading code at `09980b1` and `main` (`1a1ddb7`); nothing was executed when this was written, so DB behaviour here is by reading, and Task 1's red tests must prove it. Migrations and DB tests were identical on both branches.

## 1. Decisions

User decisions:
- 30-day grace period after re-login and a typed confirmation.
- An admin of a household with other members chooses: assign another admin and leave, OR delete the whole household. Other members keep their logins but no longer belong to it.
- Every household the user still administers at final deletion is deleted (see co-admin default below).
- A deleted member's shared rows are kept with the creator removed and shown as "Deleted member". NO `is_archived`/`is_locked` columns. Free text scrubbed, receipt images deleted, disclosed plainly.
- Household deletion removes all data in it, including other members' account entries in that household and the wife's ledger there. Warn with a banner and prompt export.
- Email: account holder reminders at T-7, T-1 and completion; members when their household is marked and at T-7. Missing mail provider never blocks the purge. Turning this on for real users needs separate user approval at rollout.
- Household stays active during grace, with a banner for members.
- Public page at `/delete-account`.
- Local `main` merged into the work branch. Local tests use a throwaway Docker Postgres.

Orchestrator defaults, reported to the user, who has not objected:
- D1: account fully usable during grace; explicit Cancel; signing in cancels nothing. All copy says so.
- D3: `transfer` runs immediately through `transfer_primary_admin`; the caller stays a co-admin until final deletion, so cancelling only loses the primary title.
- D4: a non-primary co-admin leaves at final deletion and the household survives (rule 04 forbids removing the primary admin).
- D5: in the purge only, delete a departing wife's `wife_personal` rows first so no budget moves (the existing trigger would otherwise move them into category budgets). `wife_reimbursable` was already counted, so declassifying moves nothing. `leave_household`/`remove_member` unchanged.
- D6: receipt images of preserved rows deleted; row data kept.
- D8: settlement drops rows paid by a departed member and re-splits current-cycle equal splits, changing survivors' debts; budgets funded by a deleted personal account show under the viewer's default account (display only). Account balances and budget spend don't change. Warn before scheduling; don't change the engine; open a follow-up.

## 2. Findings that shape the design

- Nothing purges today. `railway.json` does not exist on any branch despite `docs/sensitive.md` naming it; Railway is dashboard-configured. No `pg_cron`, APScheduler, lifespan or background loop exists.
- Sign-in is email and password only; OTP only in `forgot_password_screen.dart`; no Apple or Google sign-in, so Apple token revocation doesn't apply. A read-only preflight must confirm `auth.identities` has only `email`.
- `main.dart:_fetchHouseholdFromSupabase` reads only `users.household_id`, so NULL sends a member with other households to onboarding, and `users.role`/`financial_role` go stale. Repoint is required.
- `transactions.is_archived`/`is_locked` don't exist (only `accounts.is_archived`). Rule 04 already says "Rows without a creator are admin-only", and test 20 proves it.
- Client `UPDATE` on `users`/`households` is column-listed, so new columns aren't client-writable. But `users_select_household` would expose new `users` columns to housemates, so use a separate table. Add no `users` columns.
- `clearQueue()` exists with no callers; sign-out keeps queue, blobs and most prefs.
- `spent_by` is `me|partner|both` relative to `user_id`, with a live CHECK from `20260930`, holds no name, and is read by `settlement_engine.py`. Never write a label into it.
- These don't exist: device tokens, server-side chat history, audit logs. No push infrastructure. Off-topic history and idempotency keys are Redis or in-memory with TTL ≤ 24h.
- Rule 01 is out of date: `web_app` already talks to Supabase directly.
- Checked safe: `reconcileUnlinkedTransactions` filters on `user_id = me` and last 10 min; `IncomeRecord.fromMap` tolerates NULL `user_id`; nothing in `lib/`, `ai_service`, `web_app/src` reads `account_transfers`.

Blockers:
1. `income_records.user_id` is `ON DELETE CASCADE` and `trg_adjust_account_balance_on_income_change` subtracts `net_amount` on delete, so deleting anyone who recorded income into a shared pool lowers that pool's balance.
2. `account_transfers.from_account_id`/`to_account_id` and `income_records.account_id` are `RESTRICT`; the cascade from a user to personal accounts can hit them depending on trigger order, always when another user's row references the account. Household cascades have the same race. Test 16 has no transfers or income, so doesn't exercise this.
3. Deleting a household with members is order-dependent: `check_last_admin_membership` also fires on the cascade from `households` and raises if the last admin's row is processed while others remain. Test 20 line 583 passes only for its particular state.
4. Making `income_records.user_id` nullable opens a hole in `void_income_record`: `v_income.user_id <> v_caller_uid` in an `AND` chain goes NULL, so the `IF` doesn't raise, and any member could void a departed member's pool income. Change to `IS DISTINCT FROM` in the same commit.
5. Replacing the handover trigger with household deletion is dangerous: it would delete households on any `auth.users` delete including a dashboard click, and break test 16. Keep the handover for out-of-band deletes; put household deletion only in the purge.
6. `/delete-account` can't load today: `main.py` has no SPA fallback (only `GET /`); the firewall middleware returns 401 for any proxied path not on its allow-list; `App.tsx` returns `PortalShell` for signed-in users before routing; `ai_service/static` is a committed build, and rebuilding also ships `main`'s web branding if not already refreshed.
7. The local DB runner is very likely broken since `5bcd2bd`. `--rebuild` applies `schema.sql` before migrations. The consolidated `schema.sql` defines `member_allowances(user_id)`, `spouse_reimbursements(claimant_id)`, an `inquiries` table without `type`, and a `household_type` CHECK of `family|flatmates|individual`. `20261020300000` uses `CREATE TABLE IF NOT EXISTS`, a no-op, then indexes `member_allowances(member_user_id)`, which should abort. `'roommates'` would fail the CHECK. `tests/e2e/e2e_harness/stack.py` and README setup use the same order. Live was built from the older `schema.sql` plus migrations. **The migration chain, not `schema.sql`, is the FK truth.**

File checks: `lib/services/api_service.dart` is the FastAPI facade; role RPCs go through Supabase directly, so use a new `account_deletion_service.dart`. `lib/screens/home/dashboard_screen.dart`: insert next to `PaydayCheckinBanner`. Target section is `SettingsSection` titled `set_account_section`. `supabase/tests/36_*` free (latest `35_void_income_record.sql`). `run_tests.py` globs `supabase/tests/*.sql` sorted, skipping `00_`; passes on exit 0 under `ON_ERROR_STOP`; tests use `BEGIN … ROLLBACK`, `RAISE EXCEPTION`, `RAISE NOTICE 'PASSED: …'`. `url_launcher` isn't in `pubspec.yaml`, so the Settings privacy link adds a dependency. Re-check migration timestamp at implementation.

## 3. Per-table disposition

### 3a. Member leaves, household survives

| Table.column | Today | Disposition |
|---|---|---|
| `public.users.id` → `auth.users` | CASCADE | Scrub first, then Auth Admin delete cascades |
| `api_quota.user_id`, `invite_attempt_log.user_id` (holds IP) | CASCADE | Keep |
| `transactions.user_id` | SET NULL | Keep row, NULL creator |
| `transactions.account_id` | SET NULL | Keep. Survivors' balances untouched |
| `transactions.nafaqah_spouse_id` | SET NULL + D3 trigger | D5: delete her `wife_personal` rows first in the purge |
| `transactions.notes` | none | Scrub to machine-readable `PaidBy…SpentBy` tail, or NULL. Keep `Settlement \| PaidBy:` head with the ID replaced |
| `transactions.beneficiary_id`, `settlement_target_id`, `line_items[].beneficiary` (text; UUID or claimed dependent's name) | none | Replace with sentinel `deleted_member`. A pytest proves results match an unknown UUID |
| `transactions.spent_by` | CHECK enum | Untouched |
| `transactions.receipt_url` and image | none | Queue image for Storage API removal, NULL the URL |
| `income_records.user_id` into a pool | CASCADE | Change to nullable SET NULL. Row kept. NULL `notes` |
| `income_records` into their personal account | CASCADE/RESTRICT | Delete before the account |
| `account_transfers.user_id`, `from_account_id`, `to_account_id` | CASCADE/RESTRICT, NOT NULL | All nullable SET NULL. Delete a row only when both sides were theirs. NULL `notes` |
| `accounts.owner_user_id`, personal | CASCADE | Delete |
| `accounts.owner_user_id`, shared pool | CASCADE, re-owned by trigger | Keep, re-owned. Assert balance unchanged |
| `budgets.account_id` → their personal account | SET NULL | Accept, disclose (D8) |
| `households.owner_user_id` | SET NULL + trigger | Keep |
| `households.nafaqah_provider_user_id` | SET NULL + clear trigger | Keep. Prompt new primary |
| `household_memberships.user_id` | CASCADE + triggers | Remove in purge, after pool re-own |
| `member_allowances.member_user_id`, `spouse_reimbursements.wife_user_id` | CASCADE + D3 | Keep behaviour. Warn the husband |
| `member_allowances.set_by`, `spouse_reimbursements.paid_by_user_id`, `recorded_by` | SET NULL | Keep |
| `household_dependents.linked_user_id` | SET NULL (real name stays) | Delete the row if linked; targeted invites cascade |
| `household_invites.created_by` | SET NULL | Keep (test 16) |
| `household_invites.used_by` | CASCADE | Keep (test 16) |
| `inquiries` (no FK on live; holds `email`, `name='User <uuid>'`, `message`) | none | Delete by email or name marker in purge |
| `display_name` | on `users` | Overwritten when shell scrubbed |
| `transactions.reallocated_from_budget_id`, `installment_plans.original_transaction_id` | not user-linked | Untouched |

### 3b. Household deleted

CASCADE from `households`: `cost_control_codes`, `cost_control_sub_categories`, `household_category_settings`, `budgets`, `accounts` (including other members' personal accounts), `transactions`, `account_transfers`, `income_records`, `installment_plans`, `household_dependents`, `household_invites`, `household_memberships`, `member_allowances`, `spouse_reimbursements`. `users.household_id`: SET NULL, then repoint.

Fixed delete order in purge: (1) income and transfers; (2) non-admin memberships, then admin memberships; (3) the `households` row; (4) repoint former members.

Outside the DB: `receipts` bucket paths are `<household_id>/…`; SQL deletes not allowed on Supabase, so use the Storage API via the queue; a deleted household's whole folder goes through it. `storage.objects.owner` can't attribute uploads (service-role uploads have none); preflight checks for an FK to `auth.users`. `budgets_spent_backup_20261019` exists only on live, not touched. Developer mailbox copies, Railway logs, Supabase backups, `auth.audit_log_entries` are out of reach: disclose on the page and in the policy.

## 4. Design

### 4.1 Purge
A Railway Cron service using the same image, start command `python account_deletion_worker.py`, hourly (`17 * * * *` UTC), exits when done; Railway skips overlaps. Rejected: `pg_cron` (can't call Auth Admin or Storage APIs, secrets in DB), in-process FastAPI loop (no failure signal), HTTP trigger (new destructive route and secret). No new secrets: reuses `SUPABASE_SECRET_KEY`, backend only. Safety switch: without `ACCOUNT_DELETION_PURGE_ENABLED=1` the worker only logs due counts.

States: status `scheduled → processing → completed`, `failed` terminal alert; stage `none → db_prepared → storage_done`.

Per job: (1) `claim_due_account_deletions` leases with `FOR UPDATE SKIP LOCKED`; (2) `prepare_account_purge` does all DB work in one transaction, no-op if prepared; (3) remove queued storage objects, retry-safe; (4) `client.auth.admin.delete_user(uid)`, 404 counts as success; (5) `complete_account_purge` verifies the `auth.users` row is gone, then NULLs `user_id` and `reason`, leaving an identifier-free tombstone.

Retry with exponential backoff capped at 24h; after 5 attempts `failed`. Visibility: `last_error_code` holds codes only, never raw errors; `account_deletion_worker_runs` heartbeat per run; non-zero exit shows as failed in Railway; developer email through `mail_service` on `failed` or when a job is >48h overdue. Limit: if the cron itself stops nothing alerts; the runbook has a read-only check. JWT stays valid until `exp` after deletion, but with the row gone RLS and membership checks return nothing; accepted.

### 4.2 Household rules

| Caller's position | At request | At final deletion |
|---|---|---|
| Regular member | Nothing | Leaves. Rows preserved |
| Sole member | No choice; marked for deletion | Household deleted |
| Primary or sole admin, others present | Required choice: `transfer` to a named member, or `delete` | As chosen |
| Non-primary co-admin | No choice | Leaves. Household kept |

Successor must be a current member, not the caller, not pending deletion (`successor_pending_deletion`). A household marked `delete` stays active with a banner; the mark clears if the requester cancels, transfers primary, or leaves. Late-surfaced household (a pending co-admin becomes sole or primary admin because the primary left): `prepare_account_purge` won't delete silently; it marks the household with 7 days' notice, extends the request, returns `{deferred: true}`, then applies the "still administers" rule.

`account_deletion_repoint_active_household(p_user_id)`: pick next membership by `is_default DESC, created_at ASC`; set `household_id`, `role`, `financial_role` from it and `is_default`; if none, `household_id = NULL`, `role = 'member'`. `leave_household` and `remove_member` have the same no-repoint defect: note, don't change.

### 4.3 Kept rows
NULL creator gives the locked behaviour with no read-path risk. Required UI fix: `models.dart:~182` shows a NULL-creator `spent_by='me'` row as paid by the viewer and `edit_transaction_sheet.dart` treats NULL creator as the viewer: show localized "Deleted member". Preflight counts NULL `user_id` rows on live because older rows get the same label. Settlement: NULL creator resolves to "not attributed" in `_caller_relative`, never credited to the caller.

### 4.4 Grace period
Allowed for a pending user: normal use, exports, `switch_active_household`, cancel. Blocked: joining, claiming invites, creating a household, being promoted, receiving primary admin, becoming Nafaqah provider. Blocked for a marked household: new members, new invites.

Enforce with triggers so RPC and service-role paths are covered. `BEFORE INSERT` also fires on the sync trigger's `ON CONFLICT`, so the guard must return early when the membership already exists, otherwise `switch_active_household` breaks; test explicitly. Handover trigger skips pending users when choosing a successor.

Concurrency: partial unique index plus per-user advisory lock, so a double request returns the existing one. Cancel and purge serialize on the request row lock; once `processing`, cancel returns `deletion_in_progress`. On cancel marks clear and the banner disappears on next load or resume (`households` isn't in the realtime publication); transfers already done stay done.

Reminders: `mail_service.send_email(..., to_override=)` for T-7, T-1, completion in ar/en/ur; plus member emails on mark and T-7. Missing provider logged, never blocks. No push.

### 4.5 Re-auth and typed confirmation
Enforced in the RPC: JWT `session_id` must match an `auth.sessions` row for this user with `created_at` within 15 minutes. Don't rely on `amr`. Client: `signInWithPassword` with typed password creates a fresh session; forgotten-password fallback `signInWithOtp(shouldCreateUser: false)` + `verifyOTP(type: email)`; owner must confirm email template includes `{{ .Token }}`. Typed word also checked on server after normalize and trim: `DELETE` (case-insensitive), `حذف`, or `حذف کریں`. Cancel needs no re-auth. Keep friction to one re-auth, one typed word, one choice per affected household.

### 4.6 RPCs
Client (`SECURITY DEFINER`, `SET search_path = public, pg_temp`, act only on `auth.uid()`, `REVOKE ALL FROM PUBLIC, anon`, `GRANT EXECUTE TO authenticated, service_role`):
```sql
public.get_account_deletion_preflight() RETURNS jsonb
public.request_account_deletion(
    p_confirmation text,
    p_household_choices jsonb DEFAULT '[]'::jsonb,
    -- [{"household_id": uuid, "action": "transfer"|"delete", "successor_user_id": uuid|null}]
    p_reason text DEFAULT NULL,   -- optional, max 500 chars
    p_locale text DEFAULT 'ar'    -- ar|en|ur
) RETURNS jsonb
public.cancel_account_deletion() RETURNS jsonb
public.get_account_deletion_status() RETURNS jsonb
```
Error hints: `reauthentication_required`, `confirmation_mismatch`, `household_choice_missing`, `household_choice_invalid`, `successor_invalid`, `successor_pending_deletion`, `account_pending_deletion`, `household_pending_deletion`, `deletion_in_progress`.

Service-only (`REVOKE ALL FROM PUBLIC, anon, authenticated`, `GRANT EXECUTE TO service_role`, each refuses when `auth.uid()` is set):
```sql
public.claim_due_account_deletions(p_limit int DEFAULT 20, p_lease_minutes int DEFAULT 30)
    RETURNS TABLE(request_id uuid, user_id uuid, stage text, attempts int, locale text)
public.prepare_account_purge(p_request_id uuid) RETURNS jsonb
public.list_account_purge_storage(p_request_id uuid)
    RETURNS TABLE(bucket text, path text, is_prefix boolean)
public.mark_account_purge_storage_done(p_request_id uuid) RETURNS void
public.complete_account_purge(p_request_id uuid) RETURNS void
public.record_account_purge_failure(p_request_id uuid, p_error_code text) RETURNS jsonb
public.list_account_deletion_notices_due()
    RETURNS TABLE(request_id uuid, user_id uuid, notice text, locale text, scheduled_for timestamptz)
public.mark_account_deletion_notice_sent(p_request_id uuid, p_notice text) RETURNS void
public.record_account_deletion_worker_run(
    p_started_at timestamptz, p_claimed int, p_completed int, p_failed int) RETURNS void
```
Internal (revoked from client roles): `account_deletion_recent_login_ok()`, `account_deletion_repoint_active_household(uuid)`, trigger functions.

New tables (RLS enabled, `REVOKE ALL` from clients, no policies, RPC only): `account_deletion_requests` (no FK to `users`, so it outlives the row), `account_deletion_storage_queue`, `account_deletion_worker_runs`. New columns: `households.deletion_requested_at`, `deletion_scheduled_for`, `deletion_requested_by` (FK SET NULL, indexed, test 17 requires). No client grant; test 23's exact column list stays true.

### 4.7 Web
Add explicit `GET /delete-account` in `main.py` serving the same index, plus a firewall allow-list entry; no generic SPA fallback. `App.tsx` checks the path before the session split. Authenticated: sign in, fresh re-auth, same RPCs; identity from the session, so nobody can request for someone else. Unauthenticated: reuse `POST /public/inquiries` (allow-listed, honeypot, 5/IP, 3/email, 200/hour global, failing closed), type `account_deletion`; it only stores a row and emails the developer, never looks up an account, never mails the submitted address. Keep the row 90 days, stated on the page. Languages: page-scoped `deleteAccountTranslations` in `translations.ts` for ar/en/ur, `?lang=ur`, RTL for ar and ur; full-site Urdu out of scope. Content names the app as on the store listing; says what is deleted, retained anonymized, out of reach, the 30-day window, how to cancel, and that signing in alone doesn't cancel. No invented claims. Add a `Privacy` item, footer link, and a link in Settings.

### 4.8 Device cleanup
`LocalAccountDataCleaner.wipeForUser(uid)`: remove only this user's offline queue rows and blobs (new `clearForUser`; `clearQueue()` would drop other accounts' items), `last_household_id_<uid>`, household-scoped checklist prefs (`paydayConfirmedKey`, `hiddenKey`), `payday_day`, signed-URL cache, reminders, temporary statement PDFs. Keep theme and language. When: per-user local flag with `scheduled_for` set on request, removed on cancel; sign-out while pending wipes; on launch wipe any flagged user whose date passed. If offline items are pending at request, offer "sync first" without blocking.

## 5. Ordered tasks
One commit per task, isolated worktree, tests first and shown failing for the right reason. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Task 0: Base and runner.** Run `PGHOST=localhost PGPORT=<port> PGUSER=postgres python3 supabase/tests/run_tests.py --psql --rebuild --db bt_tests` against a throwaway Docker Postgres. If it fails as predicted, commit `fix(db): restore a replayable baseline`: restore `supabase/schema.sql` from `5bcd2bd~1` for replay, keep the consolidated copy as `docs/` reference only, keep `README.md` consistent; all 35 tests and the e2e rebuild pass.

**Task 1: Ledger-safe deletes.** `fix(db): keep ledgers and balances intact when a member is deleted`. `supabase/migrations/20261105000000_account_deletion_ledger_fks.sql`, `supabase/tests/36_account_deletion_ledger.sql`. FKs from 3a using the by-column drop pattern from `20261020700000`, with a closing guard aborting on mismatch. `handover_households_on_user_delete` deletes income into their personal accounts first. `void_income_record` uses `IS DISTINCT FROM`. Tests: member's pool income keeps balance and row with NULL `user_id`; personal→pool and admin's pool→personal transfers: deletion succeeds, pool unchanged, row kept with NULL side; regular member can't void NULL-creator pool income, admin can; household with transfers, income and several members deletes through the fixed order; tests 14, 16, 19, 20, 23, 26 stay green unchanged.

**Task 2: Schema and guards.** `feat(db): add account deletion requests and pending-deletion guards`. `20261105000100_account_deletion_schema.sql`, `37_account_deletion_guards.sql`, `00_local_supabase_stubs.sql` (add `auth.sessions`). Tables, household columns, guard triggers on `household_memberships` and `household_invites`, trigger clearing marks when requester leaves, `CREATE OR REPLACE` of `transfer_primary_admin` and `set_nafaqah_provider`, `inquiries` type CHECK extended. Tests: pending user can't join, claim, create or be promoted, can switch; marked household refuses joins by invite and permanent code and new invites; anon and authenticated can read or write none of the new tables; authenticated can't update new household columns or delete their own `users` row.

**Task 3: User RPCs.** `feat(db): add account deletion request, cancel and status RPCs`. `20261105000200_account_deletion_rpcs.sql`, `38_account_deletion_rpcs.sql`. Tests: refused without `session_id`, stale session, another user's session, wrong phrase; accepted for each locale's phrase; 30 days out, repeat keeps original date; regular member, sole member, primary admin (`transfer` and `delete`), co-admin; multiple households including missing choice, unknown or foreign household, duplicate; successor not a member, the caller, or pending; cancel clears only that user's marks, keeps transfers, refused while `processing`; status never exposes reason or another user's request; anon can execute none (test 14).

**Task 4: Purge functions and DB proof.** `feat(db): add service-only account purge`. `20261105000300_account_deletion_purge.sql`, `39_account_deletion_purge.sql`. Seed a roommate household and a family household with a wife; pool, personal accounts, income, transfers, budgets, receipt paths, dependents, invites, inquiries; users admin A, member B and wife W, with B also in a second household. Assert: sum of surviving pool balances and every surviving budget's `spent_amount` exactly equal before and after a member purge; preserved rows have NULL creator and no email or display name remains anywhere in `public`; `spent_by` unchanged; budget unchanged after purging W; A's marked household deleted, B keeps login, `household_id` repoints with correct `role` and `financial_role`, a member with no other household gets NULL; co-admin's household survives; late-surfaced deferred 7 days and marked; `prepare` twice no-op, repeated `complete` safe; not-due and cancelled refused; lease expiry reclaims, held lease skipped; backoff, then `failed` after 5; authenticated and anon get 42501 on every purge function; storage queue has the right paths. Stub `auth.users` delete stands in for the Admin API. Never point at live.

**Task 5: Worker.** `feat(ai): add account deletion worker and notices`. `ai_service/account_deletion_worker.py`, `account_deletion_notices.py`, `tests/test_account_deletion_worker.py`, `.env.example`, `docs/runbooks/account-deletion-purge.md`. Mocks only: disabled flag no destructive call; happy-path call order; Auth 404 success; failure at each stage then retry resumes correctly; storage pagination and batching; raw errors, emails, tokens never logged; mail failure doesn't block; 3-language notices with Qawam brand; exit code reflects failures; `/health` and route table gain no purge route.

**Task 6: Public backend routes.** `feat(ai): serve the deletion page and accept deletion inquiries`. `main.py`, `routes/inquiries.py`, `supabase_client.py` and `routes/households.py` (map guard hints to 409), `tests/test_landing_page.py`, `tests/test_inquiries.py`. Tests: unauthenticated proxied `GET /delete-account` 200 with built index (with `X-Forwarded-For`); other unknown paths still 401 or 404; form only touches `inquiries`, no auth or RPC; honeypot and limits; response doesn't vary by account existence.

**Task 7: Flutter data layer.** `feat(settings): add account deletion service, provider and local cleanup`. `lib/services/account_deletion_service.dart`, `lib/services/local_account_data_cleaner.dart`, `lib/models/account_deletion.dart`, `lib/providers/account_deletion_provider.dart`, `lib/services/offline_queue_manager.dart`, `lib/main.dart` (register, reset on sign-out, load on ready and resume, re-resolve if household vanished), tests. All status and error mappings; `clearForUser` leaves another account's items; cleaner timing; keeps theme and language.

**Task 8: Flow UI.** `feat(settings): add account deletion flow`. `lib/widgets/settings/account_deletion_flow.dart`, `settings_screen.dart`, `app_localizations.dart`, `test/screens/settings_account_deletion_test.dart`. Steps: consequences including settlement warning; per-household choice; re-auth; typed word; result with date and Cancel. Tests with `test/support/fake_settings_supabase.dart`: all four positions, RTL, 3 locales, `ui_l10n_guard_test`, pending successor unselectable, wrong password stays on step.

**Task 9: Banners and attribution.** `feat(ui): show deletion banners and label former members`. `lib/widgets/dashboard/household_deletion_banner.dart`, `dashboard_screen.dart`, `lib/models/models.dart`, `edit_transaction_sheet.dart`, `household_join.dart`. Tests: member banner shows date and export hint and disappears after cancel; NULL-creator row never shown as "me"; join refusals localized.

**Task 10: Web.** `feat(web): add public account deletion page and privacy disclosure`. `web_app/src/components/AccountDeletionPage.tsx`, `App.tsx`, `i18n/translations.ts`, `components/Footer.tsx`, `lib/inquiries.ts`, rebuilt `ai_service/static/` with `VITE_API_BASE_URL=` per README. `npm run lint`, `npm run build`, Python bundle tests, manual browser check signed in and out in all 3 languages. `Privacy.tsx` only renders dictionary items, so new text goes in `translations.ts`.

**Task 11: Docs.** `docs: record account deletion rules and owner actions`. `.agents/rules/01-architecture-and-tech-stack.md` (web and worker), `.agents/rules/04-security-and-privacy.md`, `docs/sensitive.md` (new paths; `railway.json` named but absent), `docs/review/OWNER_ACTIONS.md`, `docs/review/audit/account_deletion_preflight_checks.sql` (read-only: FK actions, `auth.sessions` privilege, `storage.objects` FKs, `auth.identities` providers, NULL-creator counts).

**Task 12: Gate and review.** `flutter analyze`, `flutter test`, `pytest`, full DB runner, `npm run lint`, `npm run build`, `tests/e2e/test_04_account_deletion.py` against the local stack with a fake Auth Admin. Then Rounds 1, 2, 3 on fresh subagents.

## 6. Rollout: each step needs explicit user approval
Order (rule 01): migrations, then `ai_service` and worker, then app build. Enable the worker in the same release, since a job comes due 30 days after the first request. Approval needed for: read-only preflight on live; each production migration, one per run in filename order, with a pre/post checks file; deploying `ai_service`; shipping app builds; creating the Railway Cron service and setting `ACCOUNT_DELETION_PURGE_ENABLED=1`; any test purge on real infrastructure using a throwaway account the user names; reminder emails to real users; store console submissions.

Owner actions: Play Console Data safety deletion URL (candidate `https://budget.fmsco.com.sa/delete-account`, confirm domain); App Store Connect review notes with a test account, App Privacy answers, privacy URL; AppGallery: requirement unconfirmed (Huawei's policy page timed out), check Review Guidelines User Privacy chapter; Railway: confirm `RESEND_API_KEY` or SMTP, or the page must not promise reminders; Supabase: confirm Magic Link template includes `{{ .Token }}`, drop `budgets_spent_backup_20261019` when ready; Legal: confirm retained-row position under PDPL and store policy.

## 7. Sources
- https://developer.apple.com/support/offering-account-deletion-in-your-app/
- https://support.google.com/googleplay/android-developer/answer/13327111?hl=en
- https://support.google.com/googleplay/android-developer/community-guide/246344978/about-the-data-safety-form-and-account-deletion?hl=en
- https://supabase.com/docs/guides/auth/jwt-fields
- https://supabase.com/docs/guides/auth/sessions
- https://supabase.com/docs/guides/auth/managing-user-data
- https://docs.railway.com/cron-jobs
