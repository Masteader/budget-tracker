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

### Flutter App (`--dart-define` flags)

| Flag | Required | Description |
|---|---|---|
| `SUPABASE_URL` | ✅ | Same as above |
| `SUPABASE_PUBLISHABLE_KEY` | ✅ | Public key (safe for clients) |
| `FASTAPI_BASE_URL` | ✅ | Full URL to the FastAPI backend |

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
