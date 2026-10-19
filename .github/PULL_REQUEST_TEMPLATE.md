## Summary & Architectural Intent
<!--
Provide a clear, high-level summary of:
- What problem or feature does this PR address?
- What architectural design choices were made and why?
-->

## Type of Change
- [ ] `feat`: New feature or capability
- [ ] `fix`: Bug fix or security hardening
- [ ] `test`: New or updated tests
- [ ] `refactor`: Code change that neither fixes a bug nor adds a feature
- [ ] `docs`: Documentation, spec, or plan update
- [ ] `chore`: Tooling, dependencies, or configuration

## Files Modified & Summary of Changes
<!--
List every modified, created, or deleted file and a 1-line description of the change.
- `path/to/file`: Description of change
-->

## Rule 01–06 Compliance Verification Checklist
Before submitting this PR, verify that all applicable project rules are strictly satisfied:

- [ ] **Rule 01: Architecture & Tech Stack**
  - [ ] Inter-service contracts respected (Client -> Supabase with Anon key, Client -> AI service, AI Service -> Supabase with Service Role key).
  - [ ] No architectural layer violations.
- [ ] **Rule 02: Saudi Fintech & Islamic Compliance**
  - [ ] Payday cycle aligns with 27th Gregorian cycle (`cycle_key` format `YYYY-MM`).
  - [ ] ZATCA Phase 2 TLV barcode scanning compatibility preserved.
  - [ ] Islamic Nafaqah principles respected (no automatic 50/50 spousal splits; wife contributions tracked as reimbursable debt).
  - [ ] Multi-roommate debt simplification and zero-based account balance invariants maintained.
- [ ] **Rule 03: UI/UX & Design System**
  - [ ] Sovereign OS / Iced Ocean theme consistency (dark/light palettes, glassmorphism, rounded corners).
  - [ ] Strict trilingual localization (Arabic primary RTL, English, Urdu) via `AppLocalizations` / `web_app/src/i18n`.
  - [ ] Zero hardcoded user-facing strings; directional paddings/layouts use `Directional` APIs.
- [ ] **Rule 04: Security & Privacy**
  - [ ] Zero SMS interception policy maintained (no SMS permissions/listeners).
  - [ ] `SUPABASE_SERVICE_ROLE_KEY` strictly absent from client mobile/web code.
  - [ ] PostgreSQL Row Level Security (RLS) enabled and verified on all sensitive tables.
  - [ ] Client balance mutations prevented; atomic financial RPCs used.
- [ ] **Rule 05: Code Quality & Testing**
  - [ ] Test-Driven Development (TDD) followed: new/updated tests written first.
  - [ ] `flutter analyze` completed with **0 warnings and 0 errors**.
  - [ ] `flutter test` passes (all unit/widget tests green).
  - [ ] `pytest -v` in `ai_service` passes (all backend tests green).
  - [ ] Zero stubbed code, dummy handlers, or placeholder `TODO` comments.
- [ ] **Rule 06: PR & External Argon Audit Pipeline**
  - [ ] Dedicated feature/fix branch used (never committed directly to `main`).
  - [ ] Audit bundle prepared via `.agent/workflows/submit-for-audit.md` (or `.agents/workflows/submit-for-audit.md`).

## Verification Test Commands & Evidence
```bash
# Flutter Analyzer
cd flutter_app && flutter analyze

# Flutter Test Suite
cd flutter_app && flutter test

# Python FastAPI AI Microservice Test Suite
cd ai_service && .venv\Scripts\pytest -v
```
