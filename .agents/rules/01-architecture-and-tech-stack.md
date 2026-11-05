# Architecture & Tech Stack Rules

## 1. System Architecture Overview

```
                      ┌───────────────────────────────────────┐
                      │            Flutter Mobile App         │
                      │ (Android / iOS - Velvet Burgundy HUD) │
                      └───────┬───────────────────────┬───────┘
          HTTPS + user JWT    │                       │ supabase_flutter: CRUD under RLS,
          (X-Signature opt.)  ▼                       │ RPCs, Realtime (publishable key)
┌───────────────────────────────────────┐             │
│            Python AI Service          │             │
│        (FastAPI + LiteLLM/Gemini)     │────────┐    │
└───────────────────▲───────────────────┘        │    │ secret key, explicit
                    │ POST /public/inquiries     ▼    ▼ membership/admin checks
┌───────────────────┴───────────────────┐  ┌───────────────────────┐
│ web_app (React/Vite landing, portal,  │─▶│   Supabase Platform   │
│ /delete-account; publishable key)     │  │ (PostgreSQL + RLS)    │
└───────────────────────────────────────┘  │                       │
┌───────────────────────────────────────┐  │                       │
│ account_deletion_worker.py (Railway   │─▶│                       │
│ Cron, same image; secret key)         │  │                       │
└───────────────────────────────────────┘  └───────────────────────┘
```

## 2. Technology Stack & Frameworks

| Layer | Technology | Primary Role |
|---|---|---|
| **Mobile Client** | Flutter 3.22+, Dart 3.x | Cross-platform mobile app (Android & iOS). Velvet Burgundy HUD design language (with legacy Sovereign OS compatibility token layer). |
| **Web Portal / Landing** | React 19, TypeScript, Vite, TailwindCSS | Daylight Coastal RTL web landing page (the only one), payday countdown example, VIP early-access form, signed-in portal, public account deletion page (`/delete-account`). Built into `ai_service/static/`. |
| **AI Microservice** | Python 3.11, FastAPI, Uvicorn, LiteLLM | Receipt OCR and dialect chat agent (model from `LITELLM_MODEL`, Gemini by default), salary cycles, settlements and Nafaqah, recurring bill detector, price tracker, PDF statements, support/inquiry email. |
| **Database & Storage** | Supabase (PostgreSQL 15+) | Multi-tenant relational storage, Row Level Security (RLS), Supabase Storage (receipt images), Realtime subscriptions. |
| **Local Offline Cache** | SQLite (`sqflite`) | Local offline transaction buffer and queue with auto-sync on network reconnect. |

## 3. Directory Layout Conventions

```
budget-tracker/
├── flutter_app/         # Flutter application code
│   ├── lib/
│   │   ├── l10n/        # Trilingual localization (EN, AR, UR)
│   │   ├── models/      # Immutable data models & helper extensions
│   │   ├── providers/   # State management (ChangeNotifier / Provider)
│   │   ├── screens/     # Screen-level views
│   │   ├── services/    # Network, Supabase & SQLite API clients
│   │   ├── theme/       # App themes (Velvet Burgundy, Sovereign OS bridge, Dark/Light)
│   │   └── widgets/     # Modular, reusable UI components
│   └── test/            # Unit and widget tests
├── ai_service/          # Python microservice
│   ├── routes/          # FastAPI routers (budgets, households, nafaqah, receipts, chat, inquiries, ...)
│   ├── static/          # Committed production build of web_app (served at / and /delete-account)
│   ├── tests/           # Hermetic pytest suite
│   └── main.py          # App entrypoint and middleware pipeline
├── web_app/             # Vite + React web portal & landing experience
├── supabase/            # schema.sql, seed.sql, migrations/, tests/ (SQL suite + run_tests.py)
├── tests/e2e/           # End-to-end suite (local services and mocks only)
└── docs/                # Project documentation hub
    ├── runbooks/        # Operational runbooks
    ├── review/          # Audit reports, fix log, rollback snapshots
    └── superpowers/     # Historical design specifications and implementation plans
```

## 4. Communication Guidelines Between Components

1. **Client to Supabase:** the Flutter app uses Supabase directly with the **publishable (anon) key**; every read and write is governed by Row Level Security, and ledger or role changes go through `SECURITY DEFINER` RPCs.
2. **Client to AI Backend:** AI and server-side logic (receipt OCR, chat expense extraction, salary cycles, settlements, Nafaqah, PDF statements, support) go to FastAPI with the user's Supabase JWT (`Authorization: Bearer`). `X-Signature` is optional defense in depth.
3. **Backend to Supabase:** FastAPI uses the **secret / service-role key** (bypasses RLS), so every route re-checks the verified JWT user's household membership and admin rights itself (`auth.verify_household_access`, `household_permissions.py`).
4. **Web to Supabase and Backend:** `web_app` uses Supabase directly with the **publishable (anon) key** (Auth, the signed-in portal's reads and writes under RLS, and the account deletion RPCs). The only `ai_service` route it calls is the anonymous `POST /public/inquiries`.
5. **Account deletion worker:** `ai_service/account_deletion_worker.py` is a separate Railway Cron service from the same image, start command `python account_deletion_worker.py`, run once an hour. It uses the secret key, and the API process neither imports it nor has a route to it. See `docs/runbooks/account-deletion-purge.md`.
6. **Deployment order:** database migrations first, then `ai_service` and the worker, then the app build.
