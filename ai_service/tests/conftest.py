"""Shared test fixtures and environment setup.

The suite is hermetic:
- a developer's ``.env`` is never loaded (it may point at the live Supabase project
  with a privileged key; earlier versions of this file loaded it, so the suite read
  from and wrote budget rows to production);
- every Supabase call goes to an in-memory ``FakeSupabaseClient``;
- outbound sockets to non-loopback hosts are refused, so an unmocked network call
  fails fast instead of reaching a real service;
- local JSON fallback files are redirected to a temp dir so tests never rewrite
  tracked files under ``ai_service/data``.
"""
import os
import socket
import sys

import dotenv

# Neutralise .env loading for every module imported after this point
# (main.py, chat_parser.py and several tests call load_dotenv()).
dotenv.load_dotenv = lambda *a, **kw: False  # type: ignore[assignment]

import pytest
from fastapi import Request

_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
if _TESTS_DIR not in sys.path:
    sys.path.insert(0, _TESTS_DIR)

from fakes import FakeSupabaseClient  # noqa: E402

# Test secrets are forced (not "filled in if empty") so real values can never leak in.
_TEST_ENV = {
    "WEBHOOK_SECRET": "test_secret_for_ci_only_do_not_use_in_prod",
    "APP_AUTH_TOKEN": "test_token_for_ci_only",
    "ENV": "development",
    "SUPABASE_URL": "https://mockproject.supabase.co",
    "SUPABASE_JWT_SECRET": "super-secret-test-jwt-key-32bytes-long!",
    "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_mock_service_role_key_for_testing",
    "LITELLM_MODEL": "gemini/gemini-2.0-flash",
    "GOOGLE_API_KEY": "mock_google_api_key_for_testing",
}
for _key, _val in _TEST_ENV.items():
    os.environ[_key] = _val
for _key in ("SUPABASE_SECRET_KEY", "REDIS_URL", "GEMINI_API_KEY", "ALLOWED_ORIGINS", "TRUSTED_PROXY_IPS"):
    os.environ.pop(_key, None)

TEST_HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"

_REAL_CONNECT = socket.socket.connect
_REAL_CONNECT_EX = socket.socket.connect_ex
_REAL_CREATE_CONNECTION = socket.create_connection


def _is_local(address) -> bool:
    if isinstance(address, (str, bytes)):  # AF_UNIX path
        return True
    host = address[0] if isinstance(address, tuple) and address else ""
    return host in ("127.0.0.1", "::1", "localhost", "0.0.0.0", "")


def _guarded_connect(self, address):
    if not _is_local(address):
        raise ConnectionRefusedError(f"Network access blocked in tests: {address!r}")
    return _REAL_CONNECT(self, address)


def _guarded_connect_ex(self, address):
    if not _is_local(address):
        raise ConnectionRefusedError(f"Network access blocked in tests: {address!r}")
    return _REAL_CONNECT_EX(self, address)


def _guarded_create_connection(address, *args, **kwargs):
    if not _is_local(address):
        raise ConnectionRefusedError(f"Network access blocked in tests: {address!r}")
    return _REAL_CREATE_CONNECTION(address, *args, **kwargs)


socket.socket.connect = _guarded_connect  # type: ignore[assignment]
socket.socket.connect_ex = _guarded_connect_ex  # type: ignore[assignment]
socket.create_connection = _guarded_create_connection  # type: ignore[assignment]


@pytest.fixture(autouse=True)
def block_real_llm_calls(monkeypatch):
    """Unpatched LiteLLM calls fail immediately; tests that need a model response patch it."""
    import litellm

    def _blocked(*_args, **_kwargs):
        raise RuntimeError("Real LLM calls are blocked in tests; patch litellm.completion.")

    async def _blocked_async(*_args, **_kwargs):
        raise RuntimeError("Real LLM calls are blocked in tests; patch litellm.acompletion.")

    monkeypatch.setattr(litellm, "completion", _blocked)
    monkeypatch.setattr(litellm, "acompletion", _blocked_async)
    yield


@pytest.fixture(autouse=True)
def fake_supabase(monkeypatch, tmp_path):
    """Route every get_client() call to a fresh in-memory fake and isolate file fallbacks."""
    import supabase_client
    import installment_service

    fake = FakeSupabaseClient()
    monkeypatch.setattr(supabase_client, "_client", fake)
    monkeypatch.setattr(supabase_client, "_cached_cost_codes", None)
    monkeypatch.setattr(supabase_client, "_cached_cost_codes_time", None)
    monkeypatch.setattr(supabase_client, "HOUSEHOLD_SETTINGS_FILE", str(tmp_path / "household_settings.json"))
    monkeypatch.setattr(supabase_client, "HOUSEHOLD_INVITES_FILE", str(tmp_path / "household_invites.json"))
    monkeypatch.setattr(installment_service, "FALLBACK_FILE", tmp_path / "installment_plans.json")
    from rate_limiter import reset_rate_limiters
    from idempotency import idempotency_store
    reset_rate_limiters()
    idempotency_store.clear()
    yield fake


@pytest.fixture(autouse=True)
def mock_auth(monkeypatch, request):
    """
    Auto-mock JWT verification in tests via FastAPI dependency overrides and monkeypatch
    unless the test is specifically testing auth or security posture.
    """
    excluded_tests = [
        "test_auth", "test_security_posture", "test_sec03", "test_sec04", "test_api_audit", "test_jwt_hardening",
        "test_nafaqah", "test_household_permissions", "test_final_review", "test_sub_category_scoping",
        "test_fable_",
    ]
    if any(ex in request.node.nodeid for ex in excluded_tests):
        yield
        return

    async def fake_verify(request: Request, household_id: str):
        return household_id

    async def fake_verify_admin(request: Request, household_id: str):
        return household_id

    def fake_get_current_user_id(request: Request) -> str:
        return "00000000-0000-0000-0000-000000000001"

    import auth
    orig_verify = auth.verify_household_access
    orig_verify_admin = auth.verify_household_admin_access

    from main import app
    app.dependency_overrides[orig_verify] = fake_verify
    app.dependency_overrides[orig_verify_admin] = fake_verify_admin

    monkeypatch.setattr(auth, "verify_household_access", fake_verify)
    monkeypatch.setattr(auth, "verify_household_admin_access", fake_verify_admin)
    monkeypatch.setattr(auth, "get_current_user_id", fake_get_current_user_id)

    import importlib
    for mod_name in ["routes.budgets", "routes.households", "routes.analytics", "routes.receipts", "routes.chat", "routes.reports", "routes.support", "routes.nafaqah"]:
        mod = importlib.import_module(mod_name)
        if hasattr(mod, "verify_household_access"):
            monkeypatch.setattr(mod, "verify_household_access", fake_verify)
        if hasattr(mod, "verify_household_admin_access"):
            monkeypatch.setattr(mod, "verify_household_admin_access", fake_verify_admin)
        if hasattr(mod, "get_current_user_id"):
            monkeypatch.setattr(mod, "get_current_user_id", fake_get_current_user_id)

    yield
    app.dependency_overrides.pop(orig_verify, None)
    app.dependency_overrides.pop(orig_verify_admin, None)
