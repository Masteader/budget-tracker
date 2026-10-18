# Budget Tracker Gemini Guidelines

Welcome to the **Budget Tracker** repository. This project is an AI-powered household financial operating system specifically engineered for Saudi households and shared living groups.

All agents operating in this workspace MUST follow the project rules located in [`.agents/rules/`](.agents/rules/):

1. **[Architecture & Tech Stack](.agents/rules/01-architecture-and-tech-stack.md)**: Flutter mobile app, Python FastAPI AI microservice, React Vite web landing, Supabase PostgreSQL with RLS.
2. **[Saudi Fintech & Islamic Compliance](.agents/rules/02-saudi-fintech-and-islamic-compliance.md)**: 27th Gregorian payday cycle, ZATCA Phase 2 TLV barcode scanning, Islamic Nafaqah principles (prohibition of 50/50 spousal splits, tracking wife reimbursement debt), multi-roommate debt simplification, zero-based account balance ledger.
3. **[UI/UX & Design System](.agents/rules/03-ui-ux-and-design-system.md)**: Sovereign OS & Iced Ocean mobile HUD theme, Daylight Coastal Exploding Flow web theme, strict trilingual RTL/LTR support (Arabic primary, English, Urdu) via `AppLocalizations`, zero hardcoded strings.
4. **[Security & Privacy](.agents/rules/04-security-and-privacy.md)**: Zero SMS interception policy, Service Role Key strictly confined to server-side backend, strict PostgreSQL Row Level Security (RLS) multi-tenancy.
5. **[Code Quality & Testing](.agents/rules/05-code-quality-and-testing.md)**: Test-Driven Development (TDD), zero `flutter analyze` warnings, no placeholder/stub code.

## Quick Reference Commands

- **Flutter Tests:** `cd flutter_app && flutter test`
- **Flutter Analyzer:** `cd flutter_app && flutter analyze`
- **Python Tests:** `cd ai_service && .venv\Scripts\pytest -v` (requires virtual environment)
- **Documentation Index:** See [`docs/README.md`](docs/README.md) and [`docs/PROJECT_DETAILS.md`](docs/PROJECT_DETAILS.md)
