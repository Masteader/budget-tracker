# Architecture & Tech Stack Rules

## 1. System Architecture Overview

```
                      ┌───────────────────────────────────────┐
                      │            Flutter Mobile App         │
                      │  (Android / iOS - Sovereign OS Theme) │
                      └───────┬───────────────────────▲───────┘
                              │ REST / Multipart      │ Supabase Realtime
                              ▼                       │ (PostgreSQL CDC)
┌───────────────────────────────────────┐             │
│            Python AI Service          │             │
│       (FastAPI + Gemini + LiteLLM)    │────────┐    │
└───────────────────────────────────────┘        │    │
                                                 ▼    │
                                      ┌───────────────────────┐
                                      │   Supabase Platform   │
                                      │ (PostgreSQL + RLS)    │
                                      └───────────────────────┘
```

## 2. Technology Stack & Frameworks

| Layer | Technology | Primary Role |
|---|---|---|
| **Mobile Client** | Flutter 3.22+, Dart 3.x | Cross-platform mobile app (Android & iOS). Sovereign OS & Iced Ocean HUD design. |
| **Web Portal / Landing** | React 18, TypeScript, Vite, TailwindCSS | Daylight Coastal RTL web landing page, interactive salary & payday simulator. |
| **AI Microservice** | Python 3.11, FastAPI, Uvicorn | Vision OCR (Gemini 2.5 Flash), dialect chat agent, recurring bill detector, price tracker, PDF statement generator. |
| **Database & Storage** | Supabase (PostgreSQL 15+) | Multi-tenant relational storage, Row Level Security (RLS), Supabase Storage (receipt images), Realtime subscriptions. |
| **Local Offline Cache** | SQLite (`sqflite` / `drift`) | Local offline transaction buffer and queue with auto-sync on network reconnect. |

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
│   │   ├── theme/       # App themes (Iced Ocean, Sovereign OS, Dark/Light)
│   │   └── widgets/     # Modular, reusable UI components
│   └── test/            # Comprehensive unit and widget tests
├── ai_service/          # Python microservice
│   ├── routes/          # FastAPI route routers (chat, receipts, budgets, etc.)
│   ├── tests/           # pytest suite
│   └── main.py          # App entrypoint and middleware pipeline
├── web_app/             # Vite + React web portal & landing experience
├── docs/                # Project documentation hub
│   ├── runbooks/        # Operational runbooks (security, deployment)
│   └── superpowers/     # Design specifications and implementation plans
└── supabase/            # Database schema, migrations, and seed scripts
```

## 4. Communication Guidelines Between Components

1. **Client to Supabase:** Flutter app interacts directly with Supabase for CRUD operations governed by Row Level Security (RLS) using the **Anon Key**.
2. **Client to AI Backend:** Heavy computing tasks (Gemini Vision OCR, conversational Arabic audio/text expense extraction, PDF statement generation) are routed to the FastAPI backend.
3. **Backend to Supabase:** The FastAPI service communicates with Supabase using the **Service Role Key** (bypassing RLS) strictly for internal processing, validation, and analytics.
