# Documentation consistency pass

Date: 2026-10-20 · Base: `952098d` (branch `audit/claude-comprehensive-review`) · Scope: root
`README.md`, `docs/README.md`, `docs/PROJECT_DETAILS.md`, `docs/runbooks/*`, `AGENTS.md`,
`GEMINI.md`, `.agents/rules/*.md`, `ai_service/.env.example`, `flutter_app/README.md`,
`web_app/README.md`. No code, tests, migrations, `docs/review/**` (except this file) or
`docs/superpowers/**` were changed.

## How claims were checked

- **Environment variables:** every `os.environ` / `os.getenv` read in `ai_service/*.py` (non-test),
  `String.fromEnvironment` in `flutter_app/lib/supabase_config.dart`, `import.meta.env` in `web_app/src`.
- **API endpoints:** generated from the app object (`main.app.openapi()` with `ENV=development` and
  fake credentials, no network): 64 operations; listed in `PROJECT_DETAILS.md` §5.
- **Commands actually run (local only):**
  - `cd ai_service && python -m pytest` → 584 passed (Python 3.11 venv).
  - `cd flutter_app && flutter test` → 511 passed; `flutter analyze` → No issues found.
  - `PGHOST=localhost PGPORT=54329 PGUSER=postgres python3 supabase/tests/run_tests.py --psql --rebuild --db bt_docs_agent_check` → 20 passed, 0 failed (throwaway local DB, dropped afterwards); `--help` confirms `--psql --rebuild --db --stop-before --apply-from --no-tests`.
  - `cd web_app && npm ci && VITE_API_BASE_URL= npm run build && npm run lint` → OK; the build is byte-identical in file names/hashes to the committed `ai_service/static/assets`.
- **Links:** a relative-link and `#anchor` checker over every markdown file in scope: 10 broken before, 0 after.

## What was wrong → what changed

| # | File(s) | What was wrong | Change |
|---|---|---|---|
| 1 | `AGENTS.md`, `GEMINI.md` | Pytest command used a Windows-only path (`.venv\Scripts\pytest`); no DB, web or e2e commands | Portable `python -m pytest -v` with venv activation for both OSes; DB runner, web lint/build, `tests/e2e/`, deployment order, "never touch live" |
| 2 | `README.md` | Supabase setup ran only `schema.sql` + `seed.sql`; the 41 migrations were never mentioned | Replay schema, seed, then all migrations in filename order with the one `20261018_*` dependency exception; warn against `supabase db push` before the DB-15 re-baseline |
| 3 | `README.md` | Env table missing `ENV` (unset = production via `utils.is_production`), `LITELLM_MODEL`, `SUPABASE_JWT_SECRET`, `WEBHOOK_SECRET`, `APP_AUTH_TOKEN`, `REDIS_URL`, `GEMINI_API_KEY`; no web env | Added all of them with real defaults/effects; added `VITE_API_BASE_URL` table |
| 4 | `README.md` | Flutter example used the `SUPABASE_ANON_KEY` alias and claimed `10.0.2.2` is "the default" (there are no defaults) | Uses `SUPABASE_PUBLISHABLE_KEY`; states there is no default |
| 5 | `README.md` | Tests section covered pytest only; no deployment order | "Running the Tests" table for all suites incl. every DB runner flag; "Deployment Order" DB → backend → app linking the audit pre-flight docs |
| 6 | `README.md` | Static refresh copied only `index-*`; a changed hashed image (`hero_glacier-*.png`) would be missed | Copies the whole `dist/assets/` |
| 7 | `README.md` | Duplicated troubleshooting section, "anon key" wording, broken `LICENSE` link, health response without `version` | Deduplicated, publishable/secret key wording, 401 troubleshooting, license note, real `/health` body |
| 8 | `ai_service/.env.example` | No `ENV`, `REDIS_URL` or `GEMINI_API_KEY`; nothing said that `LITELLM_MODEL` defaults differ per module | Added with explanations (`ENV=development` for local copies) |
| 9 | `docs/README.md` | 6 links to renamed specs/plans; multi-household spec/plan and 4 plans not cataloged; "deployment guides" runbook that does not exist; `docs/review/` not indexed; stale "128 passing tests" | All 11 specs / 21 plans cataloged with working links; review folder indexed; superpowers marked historical |
| 10 | `docs/PROJECT_DETAILS.md` | "19 migrations"/"19 tables"; migrations table listed 20 of 41 files and named tables that do not exist (`reimbursement_debts`, `transfers`, `categories`) | Table of all 41 migrations with the objects they really touch |
| 11 | `docs/PROJECT_DETAILS.md` | Cycle example wrong: "`2026-10` covers Oct 27 to Nov 26" — the code (SQL/Python) names that cycle `2026-11`; payday described as fixed 27th | Per-household payday (`payday_day`, Riyadh dates, clamping, key naming rule) |
| 12 | `docs/PROJECT_DETAILS.md`, rule 02 | Rollover described as "Option A / Option C" | Real values `send_to_savings` (default), `rollover_to_categories`, `fresh_start` |
| 13 | `docs/PROJECT_DETAILS.md` | Roles "Admin / Contributing Member / Dependent"; multi-household switching listed as planned although `switch_active_household` ships | Admin (primary + co-admins) / member; dependents are profiles; switching moved to applied features |
| 14 | `docs/PROJECT_DETAILS.md` | "Gemini 2.5 Flash" OCR, React 18, "HMAC signature verification" as protection, no inquiry email, no endpoint list, stale test counts (128 / 121) | LiteLLM model from env, React 19, JWT-only auth with optional `X-Signature`, support/VIP email section, generated API table, current counts |
| 15 | rule 01 | React 18, `drift` (not a dependency), diagram without the app → Supabase path, layout missing `supabase/tests`, `tests/e2e`, `docs/review`, `landing_page`, `ai_service/static` | Updated stack, diagram, layout and communication rules (JWT, re-checks, deployment order) |
| 16 | rule 03 | `AppLocalizations.of(context).translate('key')` — no `translate` method exists; deprecated `withOpacity` | `context.tr` / `trArgs` / `AppLocalizations.get`; `withValues(alpha:)`; web translations path |
| 17 | rule 04 | RLS table list named `recurring_bills` and `reimbursement_debts` (no such tables) and missed 9 real ones; old policy snippet; "web app" uses the anon key (it does not use Supabase); service key "used for migrations" | Real table list, current `(SELECT …)` policy pattern, guardrail test, corrected key usage |
| 18 | rule 05 | Regression step ran `flutter test` only | All suites with DB runner flags and `tests/e2e/` |
| 19 | runbook | `REDIS_URL=redis://redis:6379/0` points at a compose service that does not exist; `SUPABASE_JWT_SECRET` shown as required | Optional, explained; Railway named; link to owner procedures |
| 20 | `flutter_app/README.md`, `web_app/README.md` | Unmodified `flutter create` / Vite templates | Real run/test/config/release instructions |

GitHub Actions / CI: no reference existed in the files in scope, so nothing was removed. (The
docstring of `supabase/tests/run_tests.py` still says "Supabase local Docker / CI"; it is code and
out of scope.)

## Not verified / left as is

- `tests/e2e/` does not exist yet at `952098d` (another agent is writing it); it is referenced as
  a folder in plain text, not linked, and its commands are not documented here.
- `LITELLM_MODEL=gemini/gemini-3.6-flash-lite` (from `.env.example`) was not checked against the
  provider; no live model was called. The per-module fallbacks differ (`gemini/gemini-3.5-flash-lite`
  in `receipt_scanner.py`, `gemini/gemini-2.0-flash` in `chat_parser.py` / `support_agent.py`,
  `gemini/gemini-2.0-flash-lite` in `docker-compose.yml`); worth unifying in code.
- `docker compose up` was not run (no Docker daemon used); Docker steps are checked against the
  Dockerfile and compose file only. Railway settings, Resend/SMTP delivery and the live Supabase
  project were not touched.
- Feature descriptions not tied to a specific name (reconciliation dialog, salary distribution
  assistant, haptics, theme visuals) were kept from the previous text without UI testing.
- Code observations (no change made): `IS_PRODUCTION` in `main.py` and `auth.py` defaults to
  development but is unused; the effective switch is `utils.is_production()`, where unset `ENV`
  means production. `FASTAPI_WEBHOOK_URL` is still read by the app but is redundant because
  `FASTAPI_BASE_URL` is required.
