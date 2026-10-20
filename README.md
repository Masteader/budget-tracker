# Budget Tracker

> **AI-powered household expense management for Saudi families.**
> Smart receipt scanning with ZATCA QR decoding, conversational AI expense chat, voice logging, and interactive salary-cycle budgeting for modern households.

---

## Architecture

```
Android / iOS Phone                 Python AI Service              Supabase
┌───────────────────────┐           ┌─────────────────────┐       ┌────────────────┐
│ Flutter App           │ REST /    │ FastAPI + Gemini    │       │ PostgreSQL     │
│ • Camera / ZATCA QR   │ Multipart │ • Vision Receipt OCR│ ────► │ • transactions │
│ • Voice / Chat Input  │ ────────► │ • Dialect Chat Agent│       │ • budgets      │
│ • Dashboard & Bills   │           │ • Bill Reserves     │       │ • users        │
│ • Live Feed           │ ◄─────────│ • 2D Settlement     │       │                │
└───────────────────────┘ Realtime  └─────────────────────┘       └────────────────┘
                          Stream
```

---

## Features

- 🧾 **ZATCA QR & Vision OCR Scanner**: Instant TLV decoding and line-item categorization.
- 💬 **Conversational AI Expense Chat**: Natural Saudi dialect parser with interactive previews.
- 🎙️ **Voice Entry**: Quick hands-free logging with automatic item and merchant extraction.
- 📅 **Salary-Cycle & Recurring Bills**: Saudi 27th payday alignment, reserve tracking, and 1-tap bill payments.
- 🔒 **Privacy-First & Zero SMS Interception**: Completely standalone without background SMS listeners or SMS permissions.

---

## Prerequisites

| Tool | Version |
|---|---|
| Flutter SDK | ≥ 3.22 |
| Android Studio / SDK | API 26+ target |
| Python | 3.11 |
| Docker + Docker Compose | Latest |
| Supabase account | [supabase.com](https://supabase.com) |
| Google AI Studio API key | [aistudio.google.com](https://aistudio.google.com) |

---

## Project Structure

```
budget-tracker/
├── supabase/           # SQL schema, seed data, Realtime config
├── ai_service/         # Python FastAPI + Gemini AI microservice
│   └── tests/          # pytest test suite
└── flutter_app/        # Flutter Android/iOS mobile application
    ├── android/        # Native Android project configuration
    └── lib/            # Dart source code (screens, widgets, providers)
```

---

## Step 1 — Supabase Setup

### 1.1 Create a Supabase Project

1. Go to [app.supabase.com](https://app.supabase.com) → **New Project**
2. Note your **Project URL** and both **API keys** (anon + service role)

### 1.2 Apply the Schema

1. Open **SQL Editor** in Supabase Dashboard
2. Paste and run [`supabase/schema.sql`](supabase/schema.sql)
3. Then run [`supabase/seed.sql`](supabase/seed.sql)

### 1.3 Enable Realtime

Follow the steps in [`supabase/realtime_config.md`](supabase/realtime_config.md).

---

## Step 2 — Python AI Service

### 2.1 Configure Environment

```bash
cd ai_service
cp .env.example .env
# Edit .env and fill in your Supabase + Gemini credentials
```

### 2.2 Run with Docker Compose (Recommended)

```bash
docker compose up --build
```

Service starts on **http://localhost:8000**

Verify it's running:
```bash
curl http://localhost:8000/health
# → {"status":"ok","timestamp":...}
```

### 2.3 Run Locally (Without Docker)

```bash
cd ai_service
python -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

### 2.4 Run Tests

```bash
cd ai_service
pip install -r requirements.txt
pytest tests/ -v
```

Expected output:
```
tests/test_parser.py::test_arabic_grocery_sms        PASSED
tests/test_parser.py::test_english_education_sms     PASSED
tests/test_parser.py::test_english_dining_sms        PASSED
tests/test_parser.py::test_duplicate_sms_rejected    PASSED
tests/test_parser.py::test_otp_sms_rejected          PASSED
5 passed in X.XXs
```

---

## Step 3 — Flutter App

### 3.1 Install Dependencies

```bash
cd flutter_app
flutter pub get
```

### 3.2 Build and Run

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<id>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=FASTAPI_BASE_URL=http://<your-machine-ip>:8000
```

> **Tip**: On a physical Android device, use your machine's LAN IP address (e.g. `192.168.1.10`) — not `localhost`.
> On the Android emulator, use `10.0.2.2` (the default).

### 3.3 Grant Permissions

On first launch the app may request:
- **Camera** — required for invoice photo and ZATCA QR code scanning
- **Microphone** — required for hands-free voice expense logging
- **Post Notifications** — required for budget cycle & bill reminder alerts (Android 13+)

---

## Environment Variable Reference

### Python AI Service (`ai_service/.env`)

| Variable | Required | Description |
|---|---|---|
| `SUPABASE_URL` | ✅ | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ | Service role key (full DB access, never expose to clients) |
| `GOOGLE_API_KEY` | ✅ | Google AI Studio API key for Gemini models |
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
| `ALLOWED_ORIGINS` | ❌ | Comma-separated CORS origins; replaces the defaults (localhost dev ports, `https://budget.fmsco.com.sa`, `https://www.budget.fmsco.com.sa`) |

#### Contact, support and VIP early-access email

`POST /public/inquiries` (anonymous; web app, landing pages) and `POST /support/inquiries`
(in-app, requires the user's Supabase JWT, which supplies the sender identity) email each request
to `CONTACT_RECIPIENT_EMAIL` from `MAIL_FROM` (`Budget Tracker <fmscoinfo@fmsco.com.sa>`) with
`Reply-To` set to the person who submitted it. With SMTP, use the credentials of the
`fmscoinfo@fmsco.com.sa` mailbox; with Resend, verify the `fmsco.com.sa` domain (SPF and DKIM
records) first, or providers will reject or spam-folder the mail. Subjects look like
`[Budget Tracker] VIP early access — <email>` or `[Budget Tracker] Support — <email>`.

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
(`landing_page.py` falls back to the generated `_landing_impl.py` page only when it is missing).
Refresh it after changing `web_app/` so the live VIP form posts to the same origin:

```bash
cd web_app && npm ci && VITE_API_BASE_URL= npm run build
rm ../ai_service/static/assets/index-*.js ../ai_service/static/assets/index-*.css
cp dist/index.html ../ai_service/static/ && cp dist/assets/index-* ../ai_service/static/assets/
```

### Flutter App (`--dart-define` flags)

| Flag | Required | Description |
|---|---|---|
| `SUPABASE_URL` | ✅ | Same as above |
| `SUPABASE_PUBLISHABLE_KEY` | ✅ | Public key (safe for clients; `SUPABASE_ANON_KEY` accepted as alias). Service-role / `sb_secret_` keys are rejected at startup. |
| `FASTAPI_BASE_URL` | ✅ | Full URL to the FastAPI backend (`https://` required in release builds) |
| `WEBHOOK_SECRET` | ✅ release | HMAC key for `X-Signature` on chat/receipt calls (backend requires it in production) |
| `AUTH_REDIRECT_URL` | ❌ | Email-confirmation redirect (defaults to `FASTAPI_BASE_URL`) |

The app has no built-in defaults: a build missing a required flag stops at startup with a
`StateError` naming each missing flag. Release signing reads `flutter_app/android/key.properties`
(git-ignored: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`).

---

## Troubleshooting

### Camera or Microphone not opening

- Check that **Camera** and **Microphone** permissions are granted in Android Settings → Apps → Budget Tracker → Permissions.

### Supabase Realtime not updating the Flutter UI

- Verify both tables are added to the `supabase_realtime` publication (see `realtime_config.md`)
- Check that your RLS policies allow SELECT for the authenticated user
- The Python service must use the **service role key** (bypasses RLS); the Flutter SDK uses the **anon key** (subject to RLS)

### Supabase Realtime not updating the Flutter UI

- Verify both tables are added to the `supabase_realtime` publication (see `realtime_config.md`)
- Check that your RLS policies allow SELECT for the authenticated user
- The Python service must use the **service role key** (bypasses RLS); the Flutter SDK uses the **anon key** (subject to RLS)

### LiteLLM model errors

- Ensure `GOOGLE_API_KEY` is set correctly in `.env`
- Test the key separately: `curl "https://generativelanguage.googleapis.com/v1/models?key=<your-key>"`
- Try switching `LITELLM_MODEL` to `openai/gpt-4o-mini` if Gemini is unavailable

### Docker: port 8000 already in use

```bash
docker compose down
lsof -ti:8000 | xargs kill -9   # Linux/macOS
netstat -ano | findstr :8000    # Windows — note the PID, then taskkill /PID <pid> /F
docker compose up --build
```

---

## Security Notes

- The **service role key** must **never** appear in the Flutter app or any client-side code.
- The **WEBHOOK_SECRET** is an HMAC-SHA256 shared secret — rotate it if compromised.
- All Supabase tables have **Row Level Security (RLS)** enabled — users can only access their household's data.
- Transaction and receipt audit data is stored securely in Supabase with household-isolated Row Level Security.

---

## License

MIT — see [LICENSE](LICENSE).
