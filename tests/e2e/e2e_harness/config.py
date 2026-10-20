"""Static configuration of the e2e stack (everything local; nothing points at a hosted service)."""

from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
AI_SERVICE_DIR = REPO_ROOT / "ai_service"
SUPABASE_DIR = REPO_ROOT / "supabase"
RUN_TESTS = SUPABASE_DIR / "tests" / "run_tests.py"
FETCH_POSTGREST = REPO_ROOT / "tests" / "e2e" / "scripts" / "fetch_postgrest.sh"

PGHOST = os.environ.get("BT_E2E_PGHOST", os.environ.get("PGHOST", "localhost"))
PGPORT = int(os.environ.get("BT_E2E_PGPORT", os.environ.get("PGPORT", "54329")))
PGUSER = os.environ.get("BT_E2E_PGUSER", "postgres")
DB_NAME = os.environ.get("BT_E2E_DB", "bt_e2e")

# Login role PostgREST connects as (switches to anon/authenticated/service_role per request,
# exactly like Supabase's `authenticator`). A dedicated role so the shared stub role is untouched.
AUTHENTICATOR_ROLE = "bt_e2e_authenticator"

# HS256 test secret shared by PostgREST (jwt-secret) and ai_service (SUPABASE_JWT_SECRET).
JWT_SECRET = "bt-e2e-local-test-secret-not-for-production-0123456789"

LOCAL_HOSTS = ("127.0.0.1", "::1", "localhost")


def pg_dsn(dbname: str = DB_NAME, user: str = PGUSER) -> str:
    return f"host={PGHOST} port={PGPORT} user={user} dbname={dbname}"
