# Real-stack end-to-end tests

These tests drive the **actual** backend: the `ai_service` FastAPI app talks over HTTP to a
**real PostgREST** in front of a local Postgres built from `supabase/schema.sql`, `seed.sql` and
every migration. Users are simulated with locally signed JWTs. Only the LLM (`litellm`) and the
e-mail provider endpoint are faked. Nothing contacts a hosted Supabase project, Railway, an LLM
API or an e-mail provider: a socket guard fails the run on any non-loopback connection.

```
pytest ──HTTP──▶ ai_service (uvicorn, real app, in-process thread, 127.0.0.1:<port>)
                     │ supabase-py, service_role JWT
pytest ──HTTP──▶ gateway (127.0.0.1:<port>)      /rest/v1/*  → PostgREST (byte-for-byte proxy)
  (user JWTs)        │                            /storage/v1 → in-memory stub
                     │                            /__resend   → captured e-mails (fake Resend)
                     ▼
                PostgREST 12.2.3 (official static binary) ──▶ Postgres 16 `bt_e2e`
```

The suite is opt-in and is never collected by the hermetic `ai_service` suite
(`ai_service/pytest.ini` only collects `ai_service/tests`). Without `BT_E2E=1` every test here is
skipped.

## Requirements

- Postgres 16 reachable with trust auth (defaults: `localhost:54329`, user `postgres`). The
  fixture drops and recreates the database `bt_e2e` (override with `BT_E2E_DB`) using
  `supabase/tests/run_tests.py --psql --rebuild --no-tests`, which applies
  `supabase/tests/00_local_supabase_stubs.sql` (auth/storage schemas, `anon`/`authenticated`/
  `service_role` roles, `auth.uid()`/`auth.jwt()` reading `request.jwt.claims` exactly as
  PostgREST sets them). **Never point it at a hosted database.**
- It creates a cluster-wide login role `bt_e2e_authenticator` (NOINHERIT, granted `anon`,
  `authenticated`, `service_role`) for PostgREST to connect as, like Supabase's `authenticator`.
- PostgREST binary: `BT_E2E_POSTGREST_BIN`, else `postgrest` on `PATH`, else it is downloaded by
  `scripts/fetch_postgrest.sh` (GitHub release asset, cached under `~/.cache/bt-e2e/`).
- Python 3.11+ with `pip install -r tests/e2e/requirements.txt` (the ai_service requirements
  plus `psycopg[binary]`).

## Running

```bash
python3 -m venv ~/.venvs/bt-e2e && ~/.venvs/bt-e2e/bin/pip install -r tests/e2e/requirements.txt
cd tests/e2e
BT_E2E=1 PGHOST=localhost PGPORT=54329 ~/.venvs/bt-e2e/bin/python -m pytest -v
```

Useful variables:

| Variable | Meaning |
|---|---|
| `BT_E2E=1` | required; otherwise everything is skipped |
| `BT_E2E_SKIP_REBUILD=1` | reuse the existing `bt_e2e` database (faster iteration) |
| `BT_E2E_POSTGREST_BIN` | path to a PostgREST binary |
| `BT_E2E_PGHOST` / `BT_E2E_PGPORT` / `BT_E2E_PGUSER` / `BT_E2E_DB` | database location |

A full run (rebuild included) takes about two minutes.

## How the app is configured

`e2e_harness/app_loader.py` sets the environment before importing `main`:
`SUPABASE_URL` = the gateway, `SUPABASE_SECRET_KEY` = a locally signed `service_role` JWT,
`SUPABASE_JWT_SECRET` = the shared HS256 test secret (also PostgREST's `jwt-secret`),
`ENV=development`, `REDIS_URL` empty (in-memory limiter + database quota), every provider key
empty, `LITELLM_LOCAL_MODEL_COST_MAP=True` (litellm otherwise downloads its price map at import).
`dotenv.load_dotenv` is disabled so a developer `.env` is never read. The app keeps no local
files (the JSON / in-memory fallbacks were removed; the database is the only store).

## Layout

| File | Scenario |
|---|---|
| `test_01_households_and_invites.py` | family and roommate households joined by invite code; single-use codes; brute-force lockout → 429 (API and PostgREST RPC); forged/expired/wrong-issuer tokens rejected |
| `test_02_expense_commits_and_cycles.py` | chat commits by every member (LLM mocked), heuristic fallback, ZATCA QR receipt with Nafaqah class and fingerprint de-duplication, `cycle_key` for payday 27 and payday 10 around month boundaries and Riyadh midnight |
| `test_03_nafaqah_and_settlement.py` | wife advance → husband owes; partial/full repayment; overpayment 409 (API and DB); allowance spent/remaining; wife cannot set her allowance; family settlement = ledger, never 50/50; roommate settlement paths |
| `test_04_permissions.py` | own vs other's transactions (API and PostgREST), admin overrides, shared-pool withdrawal admin-only, co-admin promotion, primary-admin protection and transfer |
| `test_05_idor_sweep.py` | every household-scoped API route and the PostgREST tables/RPCs called by household A with household B's ids |
| `test_06_quota_and_inquiries.py` | persistent DB quota (no Redis) for chat and receipts; inquiries 503 without a provider, 200 with the fake Resend, 502 on provider failure, per-IP limit |
| `test_07_money_integrity.py` | DB-06 sub-halala rejection; budgets.spent_amount == Σ transactions per (category, cycle) and account balance == ledger after a long mixed sequence |

Tests that expose an application bug are marked `xfail(strict=True)` with the bug description
(IDs `E2E-xx`); when the bug is fixed the test XPASSes and the strict marker fails the run so the
marker gets removed. Results and reproduction steps: `docs/review/audit/e2e_results.md`.
