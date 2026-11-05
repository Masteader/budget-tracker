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
- The one switch turns on purges and emails together. If mail variables are on the Cron service, enabling it sends reminders to real users and alerts to the developer. To enable purges before approving reminders, leave them off that service, which also means no failure alerts: check the runbook's health queries instead.

### Supabase
- Run the read-only checks in `docs/review/audit/account_deletion_preflight_checks.sql`, section 4 before the migrations.
- Apply the migrations one per run, in filename order.
- Confirm the Magic Link email template includes `{{ .Token }}`. The app's forgotten-password fallback at re-auth asks for that code.
- Drop `budgets_spent_backup_20261019` when ready. It exists only on live, and the purge does not touch it.

### Decide how form requests are handled
The public form stores a row and emails the developer; nothing acts on it. `request_account_deletion` only works for the signed-in user, so there is no tool to schedule a deletion for someone else. Decide how a request is verified and carried out before the page goes live, because the page tells visitors that a person handles it. Rows are removed after 90 days whether or not anyone acted on them, and when mail is down the row is the only copy. This read-only query lists what is waiting:

```sql
SELECT reference, email, locale, status, created_at
FROM public.inquiries
WHERE type = 'account_deletion'
ORDER BY created_at;
```

### Review
- **Legal:** confirm the position on retained rows ("Deleted member") under PDPL and store policy.
- **Native speakers:** review the Arabic and Urdu in `ai_service/account_deletion_notices.py` and in `deleteAccountTranslations` (`web_app/src/i18n/translations.ts`).
