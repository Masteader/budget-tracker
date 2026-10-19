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

## 3. Webhook Secret & App Token Rotation

### Procedure:
1. Generate fresh cryptographically secure 256-bit secrets:
   ```bash
   python -c "import secrets; print('APP_AUTH_TOKEN=' + secrets.token_hex(16)); print('WEBHOOK_SECRET=' + secrets.token_hex(32))"
   ```
2. Update Railway environment variables:
   - `APP_AUTH_TOKEN`: `<new_token>`
   - `WEBHOOK_SECRET`: `<new_secret>`
3. Build Flutter application with environment defines (or inject into CI build):
   ```bash
   flutter build apk --dart-define=APP_AUTH_TOKEN=<new_token> --dart-define=WEBHOOK_SECRET=<new_secret>
   ```

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

For automated transactional and password reset emails sent from `budget.fmsco.com.sa`:
- **SPF Record (TXT for `fmsco.com.sa`):**
  `v=spf1 include:_spf.resend.com ~all` (or equivalent provider)
- **DKIM Record (CNAME):**
  Configure DNS CNAME records provided by your email transport service (e.g. Resend / SendGrid / Postmark).
- **DMARC Record (TXT for `_dmarc.fmsco.com.sa`):**
  `v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@fmsco.com.sa; pct=100; adkim=s; aspf=s`
