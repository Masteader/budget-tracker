# Budget Tracker Agent Guidelines

Welcome to the **Budget Tracker** repository. This project is an AI-powered household financial operating system specifically engineered for Saudi households and shared living groups.

All agents operating in this workspace MUST follow the project rules located in [`.agents/rules/`](.agents/rules/):

1. **[Architecture & Tech Stack](.agents/rules/01-architecture-and-tech-stack.md)**: Flutter mobile app, Python FastAPI AI microservice, React Vite web landing, Supabase PostgreSQL with RLS.
2. **[Saudi Fintech & Islamic Compliance](.agents/rules/02-saudi-fintech-and-islamic-compliance.md)**: per-household payday cycle (`households.payday_day`, default 27th), ZATCA Phase 2 TLV barcode scanning, Islamic Nafaqah family-mode rules 1–4 (no spousal percentage splits, wife reimbursement ledger, wife personal allowance), multi-roommate debt simplification, zero-based account balance ledger.
3. **[UI/UX & Design System](.agents/rules/03-ui-ux-and-design-system.md)**: Sovereign OS & Iced Ocean mobile HUD theme, Daylight Coastal Exploding Flow web theme, strict trilingual RTL/LTR support (Arabic primary, English, Urdu) via `AppLocalizations`, zero hardcoded strings.
4. **[Security & Privacy](.agents/rules/04-security-and-privacy.md)**: Zero SMS policy, secret/service-role key confined to the backend, RLS multi-tenancy, admin/co-admin permission model, JWT-only API authentication (`X-Signature` optional).
5. **[Code Quality & Testing](.agents/rules/05-code-quality-and-testing.md)**: Test-Driven Development (TDD), all test suites green, zero `flutter analyze` issues, no placeholder/stub code.
6. **[PR & External Argon Audit Pipeline](.agents/rules/06-pr-and-audit-pipeline.md)**: Dedicated branch isolation, main protection, mandatory pre-PR verification gate, two-stage External Argon Audit review loop.

## Quick Reference Commands & Workflows

- **Flutter Tests:** `cd flutter_app && flutter test`
- **Flutter Analyzer:** `cd flutter_app && flutter analyze`
- **Python Tests:** `cd ai_service && python -m pytest -v` (inside the virtual environment: `source .venv/bin/activate`, Windows `.venv\Scripts\activate`)
- **Database Tests (local PostgreSQL only):** `PGHOST=localhost PGPORT=<port> PGUSER=postgres python3 supabase/tests/run_tests.py --psql --rebuild --db bt_tests` (flags: [README](README.md#running-the-tests))
- **Web Build/Lint:** `cd web_app && npm ci && npm run lint && npm run build`
- **Submit for Audit Workflow:** [`.agents/workflows/submit-for-audit.md`](.agents/workflows/submit-for-audit.md) (or `.agent/workflows/submit-for-audit.md`)
- **Address Review Workflow:** [`.agents/workflows/address-review.md`](.agents/workflows/address-review.md) (or `.agent/workflows/address-review.md`)
- **End-to-end Tests:** `tests/e2e/`
- **Deployment Order:** database migrations → `ai_service` → app build ([README](README.md#deployment-order))
- **Documentation Index:** See [`docs/README.md`](docs/README.md) and [`docs/PROJECT_DETAILS.md`](docs/PROJECT_DETAILS.md)
- **Never** write to the live Supabase project or call live services from tests; use local Postgres and mocks and supabase backups.
