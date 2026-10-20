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
