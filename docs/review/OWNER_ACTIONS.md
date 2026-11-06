# Production Owner Actions & Secret Rotation Guide

This document specifies mandatory security actions that require production administrative ownership (Supabase Dashboard, Google Cloud Console, Railway Variables, Domain DNS).

---

## 1. Supabase Service-Role Key Rotation

> [!CAUTION]
> The Supabase service-role JWT was committed in initial git commit `2b07255`. Even though deleted from `.env` on HEAD, it exists in repository history. If the repository was ever public or clones exist, this key must be rotated immediately.

### Rotation Procedure:
1. Log in to [Supabase Dashboard](https://supabase.com/dashboard/project/qnhyiszgiymsypcwnntu).
2. Navigate to **Project Settings** $\rightarrow$ **API**.
3. Under **Project API keys**, locate the **service_role** key.
4. Click **Reset API Key** / **Rotate Secret**.
5. Copy the newly generated `service_role` key.
6. Open [Railway Dashboard](https://railway.app) $\rightarrow$ **ai-service** $\rightarrow$ **Variables**.
7. Update `SUPABASE_SERVICE_ROLE_KEY` with the new value.
8. Trigger a deployment / redeploy in Railway.
9. Verify `/health` on Railway returns `200 OK`.

---

## 2. Google / Gemini API Key Rotation

> [!CAUTION]
> The Gemini API key (`AIza...`) was committed in initial git commit `2b07255`. It must be rotated in Google Cloud Console.

### Rotation Procedure:
1. Log in to [Google Cloud Console](https://console.cloud.google.com/apis/credentials).
2. Locate the API Key used for Gemini API access in Budget Tracker.
3. Click **Delete** or **Regenerate Key**.
4. In Railway Dashboard $\rightarrow$ **Variables**, update `GEMINI_API_KEY` (and `GOOGLE_API_KEY`).
5. Verify `/agent/chat-transaction` functions with the new key.

---

## 3. Webhook Secret & App Token Rotation (Server-Side Backend Only)

> [!NOTE]
> **Client APK Secret Deprecation:**
> Client authentication now relies strictly on per-user verified Supabase JWTs (`Authorization: Bearer <user_jwt>`) rather than static shared secrets embedded in the client binary. Do NOT embed `WEBHOOK_SECRET` or `APP_AUTH_TOKEN` in client builds (`--dart-define`), as embedded APK secrets can be extracted by decompilation.
> `WEBHOOK_SECRET` and `APP_AUTH_TOKEN` are reserved strictly for server-to-server and automated CI backend integrations.

### Procedure (Server-Side Backend Only):
1. Generate fresh cryptographically secure 256-bit secrets:
   ```bash
   python -c "import secrets; print('APP_AUTH_TOKEN=' + secrets.token_hex(16)); print('WEBHOOK_SECRET=' + secrets.token_hex(32))"
   ```
2. Update Railway environment variables for `ai-service`:
   - `APP_AUTH_TOKEN`: `<new_token>`
   - `WEBHOOK_SECRET`: `<new_secret>`
3. Restart `ai-service` deployment to activate the rotated backend tokens.

---

## 4. Android Keystore Generation for Production Release

> [!IMPORTANT]
> The release build must never use the default debug keystore.

### Generation Command:
```bash
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Create `android/key.properties` (added to `.gitignore`):
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=../upload-keystore.jks
```

---

## 5. Domain Email Records (SPF, DKIM, DMARC for `fmsco.com.sa`)

> [!WARNING]
> **Do NOT overwrite or replace existing SPF/DMARC records.** Replacing existing records can immediately break your primary Microsoft 365 or Google Workspace corporate email delivery.
> Always **append** transactional email mechanisms to your existing TXT record.

For automated transactional and password reset emails sent from `budget.fmsco.com.sa`:
- **SPF Record (TXT for `fmsco.com.sa`):**
  If you already have a Microsoft 365 SPF record such as:
  `v=spf1 include:spf.protection.outlook.com -all`
  **Append** the transactional email mechanism before the terminating `~all` or `-all`:
  `v=spf1 include:spf.protection.outlook.com include:_spf.resend.com -all`
  *(Ensure the record contains at most 10 DNS lookups to remain RFC 7208 compliant).*
- **DKIM Record (CNAME):**
  Configure DNS CNAME records provided by your transactional email transport service (e.g. Resend / SendGrid / Postmark). DKIM records operate on subdomains/selectors and do not conflict with existing office mail.
- **DMARC Record (TXT for `_dmarc.fmsco.com.sa`):**
  If `_dmarc.fmsco.com.sa` does not already exist, create:
  `v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@fmsco.com.sa; pct=100; adkim=s; aspf=s`
  If a corporate DMARC record already exists, leave it unchanged.


## Final backend review (2026-10-20)

- **Apply `supabase/migrations/20261020500000_review_lock_financial_role.sql (✅ applied to live 2026-10-20 and recorded in schema_migrations; authenticated can no longer UPDATE users.financial_role, service_role still can)` to live** (SQL editor, one statement, idempotent, no data change). It stops members from rewriting their own `users.financial_role`, which drives Nafaqah (FR-B-04 in `docs/review/audit/final_review_backend.md`). Deploy the backend from this branch afterwards; the order does not matter for this file.

## Real-stack e2e follow-ups (2026-10-20)

- **Apply `supabase/migrations/20261020600000_e2e_helper_rpcs_and_sub_category_visibility.sql (✅ applied to live 2026-10-21 and recorded)` to live** (SQL editor, one transaction, idempotent, no data or schema change). Not applied yet. It (a) revokes client EXECUTE on the internal helpers `household_primary_admin_id`, `nafaqah_husband_id`, `nafaqah_is_spouse_member` (E2E-04; their SECURITY DEFINER callers keep working, and a guard block aborts the migration if any policy or invoker function on live depends on them), and (b) limits `cost_control_sub_categories` reads to rows whose parent category the caller can see, revoking client writes and anon access (E2E-05). The deployed app keeps working: it reads that table only for its own categories and never writes it. Deploy the backend from this branch for the API half (E2E-03 422 and E2E-05 listing); the order does not matter. Rollback statements are at the end of the migration file.
- Residual (product decision, not a bug fix): sub-category definitions under **system** categories stay shared by every household, so an admin who adds one under e.g. `OPEX-DINING` makes it visible to all households, and two households that create the same custom code share its definitions. Removing that needs a `household_id` on `cost_control_sub_categories` (breaking schema change).

## In-app account deletion (2026-11-05)

None of this is done, and nothing is deployed. Each step needs explicit approval, in the order in section 6 of [the plan](../superpowers/plans/2026-11-05-account-deletion-corrected.md): migrations, then `ai_service` and the worker, then the app build.

> [!IMPORTANT]
> Enable the worker in the same release as the page and the app. The page states the 30-day deletion and the 90-day removal of form requests, and only the worker makes those true.

### Stores
- **Play Console:** set the Data safety account deletion URL. The candidate is `https://budget.fmsco.com.sa/delete-account`; confirm the domain. Keep the Data safety answers in line with the page.
- **App Store Connect:** review notes with a test account, App Privacy answers, privacy URL.
- **AppGallery:** the requirement is unconfirmed, because Huawei's policy page timed out when this was planned. Check the User Privacy chapter of its Review Guidelines.

### Railway
- Create the Cron service as in [the runbook](../runbooks/account-deletion-purge.md): same image, start command `python account_deletion_worker.py`, schedule `17 * * * *`, `SUPABASE_URL` and `SUPABASE_SECRET_KEY` as on the API. Run it first with `ACCOUNT_DELETION_PURGE_ENABLED` unset, then set it to `1` once approved.
- Confirm `RESEND_API_KEY` or the `SMTP_*` variables, with `MAIL_FROM` and `CONTACT_RECIPIENT_EMAIL`. The page says "we may email", so it stays true without them, and purges still run.
- Purges and emails have separate switches. `ACCOUNT_DELETION_PURGE_ENABLED=1` runs jobs. `ACCOUNT_DELETION_EMAILS_ENABLED=1` emails account holders and household members, only with the purge switch on too, and needs its own approval. Developer alerts (failed and overdue jobs) and the 90-day removal of form requests run on every run, whatever either switch says, because the page promises the 90 days. To enable purges before approving reminders, set only the first: completion emails are skipped for those accounts for good. See [the runbook](../runbooks/account-deletion-purge.md#the-email-switch).

### Supabase
- **Live had drifted from the migration chain.** Section 5 of `docs/review/audit/account_deletion_preflight_checks.sql` (read-only) found exactly two older files missing on 2026-11-05: `20261026120000_household_autonomous_taxonomy.sql` and `20261101000100_nafaqah_wife_account_owner_guard.sql`. You approved running both in this release, **before** the batch. Live runs Postgres 17.6; the local tests run on 16.
  - **Before starting, re-run section 5.** The `20261105` batch files not run yet show as missing too, as step 1's pre-check says. If any other file shows missing objects, stop: the order below assumes only those two.
  - `supabase/tests/run_tests.py --rebuild` reproduces live's state and runs this exact order with every test green (the `live` scenario): the chain without the two files, `000500` and `REVOKE TRUNCATE` on `inquiries` already done, and 50 sub-category rows. Test 48 checks all 50 rows come through unchanged, once each.
- **Production run order**, one file per run. Run the read-only pre-check first, then the file, then the post-check, and stop if a check is not as stated:

| # | File | Pre-check (read-only) | Post-check (read-only) |
|---|---|---|---|
| 1 | `20261026120000_household_autonomous_taxonomy` | Section 5 shows missing objects for this file, for `20261101000100`, and for the `20261105` files not run yet (every one except `000500`; a few of those rows show nothing missing, because the file only replaces functions that already exist), and for no other file. `SELECT count(*) FROM cost_control_sub_categories` is 50. | Section 5 shows this file present. The count is still 50, and `SELECT count(*) FROM cost_control_sub_categories WHERE household_id IS NOT NULL` is 0. |
| 2 | `20261105000600` | Section 2a lists the anon insert policy on `inquiries` and the anon policy on templates. | Section 2a returns no rows. In 2b, everything is false except authenticated reading templates. In 2c, everything is false. |
| 3 | `20261105000700` | Section 3a lists `_select_autonomous` and the insert, update and delete policies. | Section 3a lists only `cost_control_sub_categories_select_scoped`. In 3b, anon has nothing and authenticated can only select. |
| 4 | `20261101000100_nafaqah_wife_account_owner_guard` | `SELECT count(*) FROM transactions WHERE nafaqah_class IS NOT NULL` is 0, so the guard rejects nothing. | Section 5 shows this file present. |
| 5 | `20261105000500` | Already applied (verified 2026-11-05). Skip it, or re-run it; that is harmless. | Section 1a: `rpc_subtracts_too` is false. |
| 6–10 | `000000`, `000100`, `000200`, `000300`, `000400` | Section 4 (all of it) before `000000`. | Section 4d after `000000` shows only `households.deletion_requested_by`, and after `000100` no rows. Section 5 shows each file present. |
| 11 | `000800` | None | Section 5 shows the file present. `SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('account_deletion_fold_confirmation', 'schedule_account_deletion_by_operator', 'cancel_account_deletion_by_operator')` returns all three names. |
| 12 | `000900` | `SELECT prosrc LIKE '%interval ''2 days''%' FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'list_account_deletion_notices_due'` is false (the function exists already, from `000300` and `000400`, so section 5 cannot tell). | The same query is true: only `000900`'s version has the 2-day window. |
| 13 | `001000_inactive_category_budgets` | Section 5 lists this file as missing (two functions and a trigger). Note the result of `SELECT count(*), sum(spent_amount), sum(allocated_amount) FROM budgets`. | Section 5 shows this file present. The same query returns the same three values (run it right before and right after the file, so no expense lands in between): the file changes no stored amount. `SELECT has_function_privilege('authenticated', 'public.budget_spent_from_transactions(uuid, text, text)', 'EXECUTE')` is false. `SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('update_budget_on_transaction', 'update_budget_on_transaction_delete', 'update_budget_on_transaction_update', 'recompute_budget_spent') AND prosrc LIKE '%is_active IS NOT FALSE%'` returns all four names. |
| 14 | `001100_last_admin_household_lock` | `SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('check_last_admin_membership', 'leave_household', 'remove_member') AND prosrc LIKE '%FROM public.households WHERE id = % FOR UPDATE%'` is 0. | The same query is 3. The file only replaces functions, so section 5 cannot tell; this source check is the post-check. |
| 15 | `001200_account_deletion_former_member_debt` | `SELECT to_regclass('public.former_member_debts') IS NULL, (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'prepare_account_purge' AND prosrc LIKE '%account_deletion_snapshot_former_member_debts%')` returns `true|0`. | The same query returns `false|1`. `SELECT relname, relrowsecurity FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname IN ('former_member_debts', 'former_member_debt_events')` shows both with `true`. `SELECT count(*) FROM public.former_member_debts` is 0. `SELECT prosrc LIKE '%creditor_owed%' FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'mark_account_deletion_notice_sent'` is true. `SELECT has_function_privilege('anon', 'public.record_former_member_debt_payment(uuid, uuid, numeric, text, uuid, uuid)', 'EXECUTE'), has_function_privilege('authenticated', 'public.list_former_member_debt_notices_due()', 'EXECUTE')` is `false|false`. |

  - **`000600` and `000700` run right after step 1.** `20261026120000` opens three things: anonymous read of templates, client execute of the two taxonomy functions, and signed-in read of every household's NULL-household sub-category names plus client writes to them. `000600` and `000700` close them, so run steps 1 to 3 back to back and the window stays as short as the three runs. Both files are safe to run again: if an operator following the chain runs them later in their filename place, nothing changes (the `live` scenario runs exactly this order, then both files again, with every test green both times).
  - **`001000` (budgets of inactive categories).** An expense recorded in a category that is inactive for the household is now filed under that category (the API part of this release) and counts in no budget: the three budget triggers and `recompute_budget_spent` change only rows with `is_active` not false. A budget row that becomes active for the household's open cycle takes that cycle's spending of its category at once; other cycles keep what they hold. **This includes every new budget row inserted for the current cycle, whatever inserts it, the cycle rollover included: its activation trigger pre-fills `spent_amount` with the spending already recorded in that cycle, instead of starting at 0.** The triggers also lock a matching inactive row (adding nothing), so an expense saved or deleted while its category is being activated is counted exactly once. It rewrites no stored amount, and wife and settlement rows keep today's handling. Deploy the backend from this branch with it, in either order: the old backend still files such expenses under a fallback category, which the new triggers count as before. Rollback statements are in the file's header.
  - **`001100` (one admin removal per household at a time).** `check_last_admin_membership` locks the household before it counts the other admins, and `leave_household` and `remove_member` lock the household before they touch a membership, as the purge already does. Without it a co-admin's purge and the primary admin leaving at the same moment could leave a household with members and no admin. No data changes; rollback statements are in the file's header.
  - **`001200` (what a deleted wife was owed).** When a wife deletes her account, her Nafaqah ledger goes with her membership, as before. Now, while her request is scheduled, the husband (the household's Nafaqah provider, or its admins when it has none) sees the amount still owed in the app and gets the `creditor_owed` email (both email switches apply). At the purge, `prepare_account_purge` first keeps one record per surviving household where something is owed, `former_member_debts`, with the amount and no name, id, email or free text; then the purge goes on exactly as before, with the same locks and the same ledger invariant. The husband or any admin closes the record by recording payments (amount and payment method, like an ordinary reimbursement today: no account, budget or transaction moves) or her waiver. Live has no wife-class transactions, so the file creates no record there and changes no stored amount. It replaces `prepare_account_purge` (from `000300`) and `mark_account_deletion_notice_sent` (from `000400`), so deploy the backend and worker from this branch with it: the old worker lists no `creditor_owed` notices, which only means none is sent. Running the file again is harmless. Rollback statements are in its header.
- Notes on the batch, because production has no migration history and nothing records what has run:
  - **The void hotfix is on live** (verified 2026-11-05). `20261105000500_void_income_single_subtraction.sql` went first, as a standalone hotfix. Running it again is harmless.
  - **`20261105000000` no longer defines `void_income_record`,** so running it after the hotfix doesn't bring the double subtraction back. It makes `income_records.user_id` nullable, so never run it on a database without `000500`: with the older function, any member could void the income of someone deleted out of band.
  - **`REVOKE TRUNCATE` on `public.inquiries` has been run by hand.** `20261105000600_limit_anonymous_contact_form.sql` is fine after it, and removes the anonymous insert policy still on `inquiries`. On a database without the templates table or the two functions, it skips those parts with a notice and still locks down `inquiries`.
  - **`20261105000700_sub_categories_household_scope.sql`** creates its read policy only where `cost_control_sub_categories.household_id` exists, which `20261026120000` adds. Without that column it leaves the existing read policy alone, says so in a notice, and still removes client writes.
  - `000600` and `000700` are safe to run again. A whole `supabase/tests/run_tests.py --rebuild` proves the batch on the full chain, in the hotfix-first order, on a database built without `20261026120000`, and on live's measured state.
- **Running a batch file a second time.** Checked on a throwaway Postgres 17 copy of the built chain (2026-11-06). Exiting cleanly does not make a re-run harmless. Some files put back their own older version of a function that a later file replaced:

| File | Second run | What it changes | To put it right |
|---|---|---|---|
| `000000` | Runs cleanly | Puts back its own `handover_households_on_user_delete`, losing `000100`'s | Run that function's `CREATE OR REPLACE FUNCTION` statement from `000100` |
| `000100` | Refused at its first DDL (`account_deletion_requests` already exists); nothing changes | Nothing | Nothing |
| `000200` | Runs cleanly | Puts back its own `cancel_account_deletion` and `request_account_deletion`, losing `000800`'s (cancel while processing, the server's word fold) | Run those two functions' statements from `000800` |
| `000300` | Runs cleanly | Puts back its own `complete_account_purge`, `list_account_deletion_notices_due`, `mark_account_deletion_notice_sent` and `prepare_account_purge` (losing `001200`'s snapshot of what a wife is owed) | Run `000400`, then `000900`, then the `complete_account_purge` statement from `000800`, then `001200` |
| `000400` | Runs cleanly | Puts back its own `list_account_deletion_notices_due`, losing `000900`'s 2-day window, and its own `mark_account_deletion_notice_sent`, which refuses `001200`'s `creditor_owed` | Run `000900`, then `001200` |
| `000800` | Refused at its first DDL (`initiated_by` already exists); nothing changes | Nothing | Nothing |
| `000500`, `000600`, `000700`, `000900`, `001000`, `001100`, `001200` | Run cleanly | Nothing | Nothing |

  So re-run `000000`, `000200`, `000300` or `000400` only before the next file has run. The `run_tests.py` rollout scenarios run `001200` a second time after the tests, and the tests again. Each fix in the last column was checked: afterwards every function, trigger, table, column, policy, constraint, index and privilege matches the built chain. The later files' own post-checks in the table above confirm it as well.
- Confirm the Magic Link email template includes `{{ .Token }}`. The app's forgotten-password fallback at re-auth asks for that code.
- Drop `budgets_spent_backup_20261019` when ready. It exists only on live, and the purge does not touch it.

#### Rolling back
Everything here is inert until the app and the worker ship: no client reaches the new tables except through the new RPCs, and only the new app, the delete-account page and the worker call those RPCs. Roll back the app, the page and the worker first, then the database.

- **`20261105000000` (ledger FKs): leave it.** Restoring `ON DELETE CASCADE` on `income_records.user_id` would bring back the bug where deleting a member's account lowered a shared pool. Its nullable columns and `SET NULL` keys are harmless without the rest.
- **`001200` (what a deleted wife was owed): roll it back first,** with the statements in its header, one transaction: it puts back `prepare_account_purge` from `000300` and `mark_account_deletion_notice_sent` from `000400`, then drops its eight functions and two tables. Checked on a throwaway Postgres 17 copy of the built chain (2026-11-06): afterwards `pg_dump --schema-only` and every function's privileges equal the chain built without `001200`. Data lost: every kept record and its history. Its functions call `000300`'s, so it cannot stay once the files below are rolled back. The counts below assume it is gone (with it, the first is 41).
- **`000100` to `000900` (the account deletion files `000100`, `000200`, `000300`, `000400`, `000800` and `000900`):** run [`account_deletion_rollback.sql`](account_deletion_rollback.sql), one transaction.
  - It puts back the three existing functions `000100` replaced (`handover_households_on_user_delete`, `maintain_household_primary_admin`, `transfer_primary_admin`), as `000000` left them. Their new versions read what is dropped next.
  - Then it drops the four triggers, the 40 functions, the three tables (`account_deletion_requests`, `account_deletion_storage_queue`, `account_deletion_worker_runs`) and the three `households.deletion_*` columns.
  - It leaves `000500`, `000600`, `000700`, `001000` and `001100`, which use none of it. It also leaves the `inquiries` type check allowing `account_deletion`, because rows of that type may exist.
  - **Checked on a throwaway Postgres 17 copy of the built chain.** Afterwards the schema is the chain built without those six files, except that `inquiries` check. That covers functions and their privileges, triggers, tables, columns, policies, constraints and indexes. Every database test except the ten that test account deletion (37–40, 44, 45, 50–53) passes on it, including 16 (sole-admin account deletion) and 36 (the ledger FKs).
  - **Data lost:** every deletion request (open, cancelled and completed tombstones), the storage queue, the worker's run log and the households' deletion marks.
- **Pre-checks (read-only), with `ACCOUNT_DELETION_PURGE_ENABLED` unset first:**
  - `SELECT status, stage, count(*) FROM public.account_deletion_requests GROUP BY 1, 2;` shows no row with `stage` other than `none`. Such a job has already deleted data; finish it with the worker first, or it is left half done.
  - `SELECT count(*) FROM public.account_deletion_storage_queue;` is 0.
  - Note `SELECT count(*) FROM public.households WHERE deletion_requested_by IS NOT NULL;`. Those households lose their marks and are not deleted.
- **Post-check (read-only):** this returns `0|0|0|0|0`. Before the rollback it returns `40|3|4|3|3`.

```sql
SELECT
 (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname ~ '(account_deletion|account_purge)') AS deletion_functions,
 (SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r' AND relname LIKE 'account_deletion%') AS deletion_tables,
 (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'trg_account_deletion%') AS deletion_triggers,
 (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'households' AND column_name LIKE 'deletion_%') AS household_mark_columns,
 (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('handover_households_on_user_delete', 'maintain_household_primary_admin', 'transfer_primary_admin') AND prosrc ~ '(account_deletion|deletion_requested)') AS restored_functions_still_new;
```

- `001000` and `001100` have their own rollback statements in their headers, independent of this.

### Handle form requests
The public form stores a row and emails the developer; nothing acts on it by itself. The developer verifies the person and schedules the ordinary 30-day deletion with `ai_service/scripts/account_deletion_operator.py`, following [the runbook](../runbooks/account-deletion-purge.md#requests-from-the-public-form). If someone has lost access to the account's email, the developer escalates to you, and nothing happens without other identity evidence. Rows are removed after 90 days whether or not anyone acted on them, and when mail is down the row is the only copy. This read-only query lists what is waiting:

```sql
SELECT reference, email, locale, status, created_at
FROM public.inquiries
WHERE type = 'account_deletion'
ORDER BY created_at;
```

### Review
- **Legal:** confirm the position on retained rows ("Deleted member") under PDPL and store policy. That now includes the owner decision of 2026-11-06, implemented in `001200`: when a wife is still owed money, her husband is shown (and may be emailed) the amount when she schedules the deletion, and the household keeps one record of the amount still owed, with no name, until it is recorded as paid or as waived by her. The page and the app say so.
- **The email sweep's limits.** At the purge, the account's address is replaced with `deleted_member` in every `text`, `varchar`, `json` and `jsonb` column in `public`, matching the whole address and ignoring letter case. Details are in [the runbook](../runbooks/account-deletion-purge.md#limits). Two places are not covered:
  - `text[]` keyword columns (`cost_control_codes`, `cost_control_sub_categories`, `cost_control_templates`).
  - A length-limited `varchar` value the replacement would overflow. This only happens with an address under 14 characters in a nearly full sub-category code or name, and that value keeps the address.

  The page's list of what is deleted (login, email address, display name, form messages) stays true. **Decided 2026-11-06: narrowed.** The sentence that said other members' free text keeps everything "except that your email address is replaced wherever it appears" now says, in ar, en and ur, that their text stays as they wrote it and "we also remove your email address from household records", which the two cases above do not contradict. Nothing outside `public` is touched.
- **Native speakers:** review the Arabic and Urdu in `ai_service/account_deletion_notices.py` (now including `creditor_owed`), in `deleteAccountTranslations` (`web_app/src/i18n/translations.ts`) and in the app's `fmd_*` strings. All of them are in [`account_deletion_translation_review.csv`](account_deletion_translation_review.csv).
