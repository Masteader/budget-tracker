# Budget Tracker

> **AI-powered household expense management for Saudi families and shared homes.**
> Receipt scanning with ZATCA QR decoding, conversational expense chat, voice logging and
> salary-cycle budgeting that follows each household's payday.

---

## Architecture

```
Android / iOS Phone                 Python AI Service              Supabase
┌───────────────────────┐ HTTPS +   ┌─────────────────────┐       ┌────────────────┐
│ Flutter App           │ user JWT  │ FastAPI + LiteLLM   │       │ PostgreSQL+RLS │
│ • Camera / ZATCA QR   │ ────────► │ • Receipt OCR       │ ────► │ • transactions │
│ • Voice / Chat Input  │           │ • Dialect chat      │       │ • budgets      │
│ • Dashboard & Bills   │           │ • Cycles, settlement│       │ • accounts ... │
│ • Live Feed           │ ◄──────── │ • Nafaqah, inquiries│       │ • Storage      │
└──────────┬────────────┘  JSON     └─────────────────────┘       └───────▲────────┘
           └──────────── supabase_flutter (publishable key, RLS, Realtime) ┘
```

- The app talks to Supabase directly (publishable key, Row Level Security, Realtime) and to the
  FastAPI service for AI and server-side logic.
- Every user route of the API is authenticated by the caller's Supabase JWT. `X-Signature` is an
  optional integrity check, never the credential (see [Security Notes](#security-notes)).
- The API uses the privileged Supabase key and re-checks household membership and admin rights
  itself ([`.agents/rules/04-security-and-privacy.md`](.agents/rules/04-security-and-privacy.md)).

---

## Features

- 🧾 **ZATCA QR & Vision OCR Scanner**: TLV decoding and line-item categorization.
- 💬 **Conversational AI Expense Chat**: Saudi dialect parser with interactive previews.
- 🎙️ **Voice Entry**: hands-free logging with item and merchant extraction.
- 📅 **Salary Cycles & Recurring Bills**: cycles follow the household payday
  (`households.payday_day`, default 27th, Asia/Riyadh dates), bill reserves and BNPL installments.
- 👪 **Family & Wife Expenses / Roommate Settlements**: no spousal percentage splits, wife reimbursement
  ledger and personal allowance; multi-roommate debt simplification.
- 🛡️ **Admin / co-admin permissions**: the database and the API enforce who may move shared money
  and edit other members' transactions.
- ✉️ **Support & VIP early-access email**: in-app and web forms are emailed to the team.
- 🔒 **Zero SMS Interception**: no SMS permissions, listeners or SMS ingestion anywhere.

Full feature, API and schema reference: [`docs/PROJECT_DETAILS.md`](docs/PROJECT_DETAILS.md).

---

## Prerequisites

| Tool | Version |
|---|---|
| Flutter SDK | Dart `>=3.3.0 <4.0.0` (see `flutter_app/pubspec.yaml`) |
| Android Studio / SDK | API 26+ target |
| Python | 3.11 (as in the Docker image) |
| Node.js + npm | for `web_app/` (Vite) |
| PostgreSQL client (`psql`) + a local server | database test suite only |
| Docker + Docker Compose | optional, to run the API container |
| Supabase project | [supabase.com](https://supabase.com) |
| Google AI Studio API key | [aistudio.google.com](https://aistudio.google.com) |

---

## Project Structure

```
budget-tracker/
├── supabase/           # schema.sql, seed.sql, migrations/, tests/ (SQL suite + run_tests.py)
├── ai_service/         # Python FastAPI + LiteLLM service (routes/, tests/, static/ = built web_app)
├── flutter_app/        # Flutter Android/iOS app (lib/, test/)
├── web_app/            # React + Vite landing page, the only one (VIP early-access form)
├── tests/e2e/          # End-to-end suite
└── docs/               # Documentation hub: docs/README.md
```

---

## Step 1 — Supabase Setup

1. Create a project at [app.supabase.com](https://app.supabase.com) and note the **Project URL**,
   the **publishable (anon) key** (for the app) and a **secret key** (`sb_secret_…`, or the legacy
   `service_role` JWT) for the API.
2. In the **SQL Editor**, run, one file per run and in this order:
   1. [`supabase/schema.sql`](supabase/schema.sql)
   2. [`supabase/seed.sql`](supabase/seed.sql)
   3. every file in [`supabase/migrations/`](supabase/migrations/) in filename order, except that
      `20261018_multi_source_income_and_accounts.sql` must run **before**
      `20261018_membership_sync_and_shared_account_policies.sql` (same prefix, reversed
      dependency; `supabase/tests/run_tests.py` encodes this order).
3. Enable Realtime as described in [`supabase/realtime_config.md`](supabase/realtime_config.md).

Do not use `supabase db push` on an existing project until the migration history is re-baselined
(audit item DB-15, [`docs/review/audit/db.md`](docs/review/audit/db.md)).

---

## Step 2 — Python AI Service

### 2.1 Configure Environment

```bash
cd ai_service
cp .env.example .env
# Fill in SUPABASE_URL, SUPABASE_SECRET_KEY, GOOGLE_API_KEY, LITELLM_MODEL, a mail provider,
# and ENV=development for local work (see the reference below)
```

### 2.2 Run with Docker Compose

```bash
cd ai_service
docker compose up --build
```

The compose file builds the API only (no Redis service; without `REDIS_URL` rate limits are kept
in process memory). Service: **http://localhost:8000**

```bash
curl http://localhost:8000/health
# → {"status":"ok","version":"1.0.2","timestamp":...}
```

### 2.3 Run Locally (Without Docker)

```bash
cd ai_service
python -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

With `ENV=development` the interactive API docs are at `http://localhost:8000/docs` (hidden in
production).

---

## Step 3 — Flutter App

```bash
cd flutter_app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<id>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-or-anon-key> \
  --dart-define=FASTAPI_BASE_URL=http://<your-machine-ip>:8000
```

> On a physical device use your machine's LAN IP (e.g. `192.168.1.10`), on the Android emulator
> `http://10.0.2.2:8000`. There is no default: a missing flag stops the app at startup.

On first use the app may request **Camera** (receipt photos, ZATCA QR), **Microphone** (voice
entry) and **Notifications** (bill and cycle reminders, Android 13+). It never requests SMS
permissions.

---

## Running the Tests

| Suite | Command | Notes |
|---|---|---|
| API (pytest) | `cd ai_service && python -m pytest -v` | Hermetic: in-memory Supabase fake, no network, no real LLM. `tests/test_sms_removal.py` enforces the zero-SMS policy. |
| Flutter | `cd flutter_app && flutter test` and `flutter analyze` | Analyzer must report no issues. |
| Database (SQL) | `PGHOST=localhost PGPORT=<port> PGUSER=postgres python3 supabase/tests/run_tests.py --psql --rebuild --db bt_tests` | Needs a **local** PostgreSQL server and `psql`. See below. |
| Web | `cd web_app && npm ci && npm run lint && npm run build` | No unit tests; lint + type-checked build. |
| End-to-end | see `tests/e2e/` | Local services and mocks only, never live. |

Database runner (`supabase/tests/run_tests.py`) flags:

- `--psql`: use the local `psql` binary with the libpq variables (`PGHOST`, `PGPORT`, `PGUSER`,
  `PGPASSWORD`). Without it the runner uses `docker exec` into a container named
  `budget_tracker_review_pg`.
- `--rebuild`: drop and recreate `--db`, then replay stubs, `schema.sql`, `seed.sql` and all
  migrations before the tests (implies `--psql`). **Never point it at a real Supabase project.**
- `--db NAME`: database to use (default `$DB_NAME`, else `live_rebuilt_round5`).
- `--stop-before PREFIX` (with `--rebuild`): replay only migrations sorting before `PREFIX`.
- `--apply-from PREFIX` (without `--rebuild`): apply migrations at or after `PREFIX` to an existing
  local replica first.
- `--no-tests`: only rebuild / apply.
- Positional file names run a subset, e.g. `20_admin_permissions_and_co_admins.sql`.

---

## Deployment Order

Ship changes in this order: **database → backend → app**.

1. **Database:** apply new migrations in the SQL Editor, one file per run, in filename order.
   Before and after, run the checks in
   [`docs/review/audit/live_db_preflight_checks.sql`](docs/review/audit/live_db_preflight_checks.sql)
   (procedure: [`docs/review/audit/live_db_preflight.md`](docs/review/audit/live_db_preflight.md)).
2. **Backend:** deploy `ai_service` (it calls RPCs the migrations create). It still accepts older
   app builds.
3. **App:** release a new build with all `--dart-define` values and the release keystore.

Details and couplings: [`docs/review/audit/MASTER_AUDIT_REPORT.md`](docs/review/audit/MASTER_AUDIT_REPORT.md) §6.2.

---

## Environment Variable Reference

### Python AI Service (`ai_service/.env`)

| Variable | Required | Description |
|---|---|---|
| `SUPABASE_URL` | ✅ | Your Supabase project URL |
| `SUPABASE_SECRET_KEY` or `SUPABASE_SERVICE_ROLE_KEY` | ✅ one | Privileged server key, never exposed to clients: an `sb_secret_…` key or a legacy `service_role` JWT, in either variable. If both are set, an `sb_secret_…` key wins over a legacy JWT (`SUPABASE_SECRET_KEY` first on a tie); anon/publishable values are ignored with a startup warning, and with no privileged key every DB-backed route fails closed. Needs `supabase>=2.16.0` |
| `ENV` | ✅ in practice | `production` on deployments. **Unset counts as production** (`utils.is_production`); use `development` (or `dev`, `local`, `test`) locally to get `/docs`, unsigned dev requests and a fail-open quota check |
| `GOOGLE_API_KEY` | ✅ for AI | Gemini key for receipt OCR, chat and the support agent (`GEMINI_API_KEY` is also read by the support agent) |
| `LITELLM_MODEL` | recommended | LiteLLM model string (`.env.example`: `gemini/gemini-3.6-flash-lite`). Unset, each module uses its own default, so set it explicitly. `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` for other providers |
| `SUPABASE_JWT_SECRET` | ❌ | Only for legacy HS256 user tokens; without it only ES256 tokens verified via the project JWKS are accepted |
| `WEBHOOK_SECRET` | ❌ | HMAC key for the optional `X-Signature` check (see Security Notes) |
| `APP_AUTH_TOKEN` | ❌ | Legacy firewall pass (`X-App-Token`) for old app builds only |
| `PREVIEW_TOKEN_SECRET` | recommended | HMAC key (≥ 32 characters, same on every instance) signing the `preview_token` of chat/receipt previews, so a confirmed preview is saved without a second LLM call. Unset: a random per-process key and a logged warning; commits reaching another instance (or after a restart) are parsed again. Server only |
| `REDIS_URL` | ❌ | Shared rate-limit store; without it limits are per process (in memory) |
| `PORT` | ❌ | HTTP port (default: 8000) |
| `RELOAD` | ❌ | Hot-reload on file change (default: false) |
| `CONTACT_RECIPIENT_EMAIL` | ❌ | Where support and VIP early-access emails go (default: `abedmowafaq@gmail.com`) |
| `MAIL_FROM` | ❌ | Sender of those emails (default: `Budget Tracker <fmscoinfo@fmsco.com.sa>`) |
| `RESEND_API_KEY` | ✅ one provider | Resend API key; preferred provider (HTTP, works where outbound SMTP is blocked, e.g. Railway non-Pro). `fmsco.com.sa` must be verified in Resend (SPF + DKIM) |
| `RESEND_FROM` | ❌ | Overrides `MAIL_FROM` for Resend only |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_SECURITY` | ✅ one provider | SMTP alternative, used when `RESEND_API_KEY` is empty. `SMTP_SECURITY` is `starttls` (default, port 587) or `ssl` (port 465) |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | with SMTP | Login of the `fmscoinfo@fmsco.com.sa` mailbox (the sender) on its own SMTP server |
| `SMTP_FROM` | ❌ | Overrides `MAIL_FROM` for SMTP only |
| `TRUSTED_PROXY_IPS` | ❌ | Proxy IPs whose `X-Forwarded-For` is trusted for per-IP rate limits (default loopback) |
| `TRUST_PROXY_HEADERS` | ❌ | `1` trusts `X-Forwarded-For` from any peer (the client is the hop the proxies appended), `0` never; unset = on when `RAILWAY_ENVIRONMENT` is set (Railway's edge is the only way in and its addresses are not static). **Assumes the service is reachable only through Railway's HTTP edge**: no Railway TCP proxy, no private-network ingress from other services, no public port; otherwise callers choose their own `X-Forwarded-For` (and rate-limit identity), so set `0` |
| `TRUSTED_PROXY_HOPS` | ❌ | Proxies appending to `X-Forwarded-For` in front of the app (default `1`, Railway's edge; `2` with a CDN in front). Must equal the real hop count: a higher value uses a client-supplied entry |
| `ALLOWED_ORIGINS` | ❌ | Comma-separated CORS origins; replaces the defaults (localhost dev ports, `https://budget.fmsco.com.sa`, `https://www.budget.fmsco.com.sa`) |

#### Contact, support and VIP early-access email

`POST /public/inquiries` (anonymous; web app, landing pages) and `POST /support/inquiries`
(in-app, requires the user's Supabase JWT, which supplies the sender identity) email each request
to `CONTACT_RECIPIENT_EMAIL` from `MAIL_FROM` with `Reply-To` set to the person who submitted it.
With SMTP, use the credentials of the `fmscoinfo@fmsco.com.sa` mailbox; with Resend, verify the
`fmsco.com.sa` domain (SPF and DKIM records) first, or providers will reject or spam-folder the
mail. Subjects look like `[Budget Tracker] VIP early access — <email>` or
`[Budget Tracker] Support — <email>`.

```json
{"type": "vip_early_access" | "support" | "contact", "email": "you@example.com",
 "name": "optional", "message": "required for support/contact", "locale": "ar", "source": "web" | "landing" | "app"}
```

The endpoints answer `200 {"status": "sent"}` only after the provider accepted the email, `503`
when no provider is configured (logged as an error; nothing is sent), `502` when the provider
fails, `422` for invalid input and `429` past the limits (public: 5 per IP and 3 per email per
hour; app: 5 per user per hour; 200 per hour overall). Set either `RESEND_API_KEY` or the `SMTP_*`
variables on the deployment, or every form shows an error.

The page served at `/` is the `web_app` production build committed in `ai_service/static/`
(`ai_service/landing_page.py` serves a tiny inline fallback page only when `static/index.html` is
missing; the same module holds the `/auth/confirm` and `/auth/callback` pages).
Refresh it after changing `web_app/` so the live VIP form posts to the same origin:

```bash
cd web_app && npm ci && VITE_API_BASE_URL= npm run build
rm -rf ../ai_service/static/assets && cp -r dist/assets ../ai_service/static/
cp dist/index.html dist/favicon.svg ../ai_service/static/
```

### Web App (`web_app/.env`, Vite)

| Variable | Description |
|---|---|
| `VITE_API_BASE_URL` | Backend for the VIP form. Unset: `https://budget.fmsco.com.sa`; empty string: same origin (the build served by `ai_service`); e.g. `http://localhost:8000` for local work |

### Flutter App (`--dart-define` flags)

| Flag | Required | Description |
|---|---|---|
| `SUPABASE_URL` | ✅ | Supabase project URL (`https://` required in release builds) |
| `SUPABASE_PUBLISHABLE_KEY` | ✅ | Public key (safe for clients; `SUPABASE_ANON_KEY` accepted as alias). Service-role / `sb_secret_` keys are rejected at startup. |
| `FASTAPI_BASE_URL` | ✅ | Full URL to the FastAPI backend (`https://` required in release builds) |
| `WEBHOOK_SECRET` | ❌ | Optional HMAC key: when set, POST bodies carry an `X-Signature` header (defense in depth). The user's Supabase JWT is the credential: a signature that does not match the backend's current `WEBHOOK_SECRET` (e.g. after a rotation) is logged and ignored while the JWT is valid. Leave it out and requests are sent unsigned |
| `AUTH_REDIRECT_URL` | ❌ | Email-confirmation redirect (defaults to `FASTAPI_BASE_URL`) |

The app has no built-in defaults: a build missing a required flag (`SUPABASE_URL`, the publishable
key, `FASTAPI_BASE_URL`) stops at startup with a `StateError` naming each missing flag; a missing
`WEBHOOK_SECRET` never stops the app. Release signing reads `flutter_app/android/key.properties`
(git-ignored: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`).

---

## Troubleshooting

### Camera or Microphone not opening

- Check that **Camera** and **Microphone** permissions are granted in Android Settings → Apps → Budget Tracker → Permissions.

### Supabase Realtime not updating the Flutter UI

- Verify `transactions` and `budgets` are in the `supabase_realtime` publication (see [`supabase/realtime_config.md`](supabase/realtime_config.md))
- Check that your RLS policies allow SELECT for the authenticated user
- The Python service uses the **secret / service-role key** (bypasses RLS); the Flutter app uses the **publishable key** (subject to RLS)

### API answers 401

- User routes need `Authorization: Bearer <Supabase access token>`; expired tokens get 401 so the app refreshes and retries.
- Requests through a proxy or tunnel without a valid JWT are stopped by the firewall middleware.

### LiteLLM model errors

- Ensure `GOOGLE_API_KEY` and `LITELLM_MODEL` are set in `.env`
- Test the key separately: `curl "https://generativelanguage.googleapis.com/v1/models?key=<your-key>"`
- Another provider works too, e.g. `LITELLM_MODEL=openai/gpt-4o-mini` with `OPENAI_API_KEY`

### Docker: port 8000 already in use

```bash
docker compose down
lsof -ti:8000 | xargs kill -9   # Linux/macOS
netstat -ano | findstr :8000    # Windows — note the PID, then taskkill /PID <pid> /F
docker compose up --build
```

---

## Security Notes

- The **secret / service-role key** must **never** appear in the Flutter app or any client-side code.
- **Authentication** of every user route is the caller's Supabase JWT (`Authorization: Bearer`).
- **`X-Signature`** (HMAC-SHA256 of the exact body with `WEBHOOK_SECRET`) is defense in depth, never
  the authentication of a user route. With a valid JWT, an invalid or unverifiable signature (also
  when `WEBHOOK_SECRET` is unset) is logged (rate limited, route + hashed user id) and the request is
  served; without a valid JWT it is 401. Compatibility: `WEBHOOK_SECRET` has already been rotated on
  Railway, so every installed app build signs with the old value; rejecting those signatures would
  break all their chat and receipt calls. A server-to-server webhook route without a JWT must
  require a valid signature (`utils.verify_signature`); none exists today.
- **`X-App-Token`** (`APP_AUTH_TOKEN`) is only a legacy pass at the firewall for old app builds; it
  never authenticates a user (every route still verifies the JWT). The current app does not send it.
- All `public` tables have **Row Level Security (RLS)** enabled — users only see their household's
  data; ledger and role changes go through `SECURITY DEFINER` RPCs with actor checks.
- Secret rotation: [`docs/runbooks/security-secret-rotation.md`](docs/runbooks/security-secret-rotation.md).

---

## License

MIT (no `LICENSE` file is committed yet).
