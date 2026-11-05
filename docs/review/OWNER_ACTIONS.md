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

  - **`000600` and `000700` run right after step 1.** `20261026120000` opens three things: anonymous read of templates, client execute of the two taxonomy functions, and signed-in read of every household's NULL-household sub-category names plus client writes to them. `000600` and `000700` close them, so run steps 1 to 3 back to back and the window stays as short as the three runs. Both files are safe to run again: if an operator following the chain runs them later in their filename place, nothing changes (the `live` scenario runs exactly this order, then both files again, with every test green both times).
  - **`001000` (budgets of inactive categories).** An expense recorded in a category that is inactive for the household is now filed under that category (the API part of this release) and counts in no budget: the three budget triggers and `recompute_budget_spent` change only rows with `is_active` not false. A budget row that becomes active for the household's open cycle takes that cycle's spending of its category at once; other cycles keep what they hold. **This includes every new budget row inserted for the current cycle, whatever inserts it, the cycle rollover included: its activation trigger pre-fills `spent_amount` with the spending already recorded in that cycle, instead of starting at 0.** The triggers also lock a matching inactive row (adding nothing), so an expense saved or deleted while its category is being activated is counted exactly once. It rewrites no stored amount, and wife and settlement rows keep today's handling. Deploy the backend from this branch with it, in either order: the old backend still files such expenses under a fallback category, which the new triggers count as before. Rollback statements are in the file's header.
  - **`001100` (one admin removal per household at a time).** `check_last_admin_membership` locks the household before it counts the other admins, and `leave_household` and `remove_member` lock the household before they touch a membership, as the purge already does. Without it a co-admin's purge and the primary admin leaving at the same moment could leave a household with members and no admin. No data changes; rollback statements are in the file's header.
- Notes on the batch, because production has no migration history and nothing records what has run:
  - **The void hotfix is on live** (verified 2026-11-05). `20261105000500_void_income_single_subtraction.sql` went first, as a standalone hotfix. Running it again is harmless.
  - **`20261105000000` no longer defines `void_income_record`,** so running it after the hotfix doesn't bring the double subtraction back. It makes `income_records.user_id` nullable, so never run it on a database without `000500`: with the older function, any member could void the income of someone deleted out of band.
  - **`REVOKE TRUNCATE` on `public.inquiries` has been run by hand.** `20261105000600_limit_anonymous_contact_form.sql` is fine after it, and removes the anonymous insert policy still on `inquiries`. On a database without the templates table or the two functions, it skips those parts with a notice and still locks down `inquiries`.
  - **`20261105000700_sub_categories_household_scope.sql`** creates its read policy only where `cost_control_sub_categories.household_id` exists, which `20261026120000` adds. Without that column it leaves the existing read policy alone, says so in a notice, and still removes client writes.
  - `000600` and `000700` are safe to run again. A whole `supabase/tests/run_tests.py --rebuild` proves the batch on the full chain, in the hotfix-first order, on a database built without `20261026120000`, and on live's measured state.
- Confirm the Magic Link email template includes `{{ .Token }}`. The app's forgotten-password fallback at re-auth asks for that code.
- Drop `budgets_spent_backup_20261019` when ready. It exists only on live, and the purge does not touch it.

### Handle form requests
The public form stores a row and emails the developer; nothing acts on it by itself. The developer verifies the person and schedules the ordinary 30-day deletion with `ai_service/scripts/account_deletion_operator.py`, following [the runbook](../runbooks/account-deletion-purge.md#requests-from-the-public-form). If someone has lost access to the account's email, the developer escalates to you, and nothing happens without other identity evidence. Rows are removed after 90 days whether or not anyone acted on them, and when mail is down the row is the only copy. This read-only query lists what is waiting:

```sql
SELECT reference, email, locale, status, created_at
FROM public.inquiries
WHERE type = 'account_deletion'
ORDER BY created_at;
```

### Review
- **Legal:** confirm the position on retained rows ("Deleted member") under PDPL and store policy.
- **Native speakers:** review the Arabic and Urdu in `ai_service/account_deletion_notices.py` and in `deleteAccountTranslations` (`web_app/src/i18n/translations.ts`).
