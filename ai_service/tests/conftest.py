"""Shared test fixtures and environment setup."""
import os
import pytest
from fastapi import Request

from dotenv import load_dotenv

load_dotenv()

# Set test secrets before any imports of main (fall back to mocks if not set or empty in .env)
_TEST_DEFAULTS = {
    "WEBHOOK_SECRET": "test_secret_for_ci_only_do_not_use_in_prod",
    "APP_AUTH_TOKEN": "test_token_for_ci_only",
    "ENV": "development",
    "SUPABASE_URL": "https://mockproject.supabase.co",
    "SUPABASE_JWT_SECRET": "super-secret-test-jwt-key-32bytes-long!",
    "SUPABASE_SERVICE_ROLE_KEY": "mock_service_role_key_for_testing",
    "LITELLM_MODEL": "gemini/gemini-2.0-flash",
    "GOOGLE_API_KEY": "mock_google_api_key_for_testing",
}
for key, val in _TEST_DEFAULTS.items():
    if not os.environ.get(key, "").strip():
        os.environ[key] = val

TEST_HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"


@pytest.fixture(autouse=True)
def mock_auth(monkeypatch, request):
    """
    Auto-mock JWT verification in tests via FastAPI dependency overrides and monkeypatch
    unless the test is specifically testing auth or security posture.
    """
    excluded_tests = ["test_auth", "test_security_posture", "test_sec03", "test_sec04"]
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
    orig_get_user_id = getattr(auth, "get_current_user_id", None)

    from main import app
    app.dependency_overrides[orig_verify] = fake_verify
    app.dependency_overrides[orig_verify_admin] = fake_verify_admin

    monkeypatch.setattr(auth, "verify_household_access", fake_verify)
    monkeypatch.setattr(auth, "verify_household_admin_access", fake_verify_admin)
    monkeypatch.setattr(auth, "get_current_user_id", fake_get_current_user_id)

    for mod_name in ["routes.budgets", "routes.households", "routes.analytics", "routes.receipts", "routes.chat", "routes.reports", "routes.support"]:
        try:
            import importlib
            mod = importlib.import_module(mod_name)
            if hasattr(mod, "verify_household_access"):
                monkeypatch.setattr(mod, "verify_household_access", fake_verify)
            if hasattr(mod, "verify_household_admin_access"):
                monkeypatch.setattr(mod, "verify_household_admin_access", fake_verify_admin)
            if hasattr(mod, "get_current_user_id"):
                monkeypatch.setattr(mod, "get_current_user_id", fake_get_current_user_id)
        except Exception:
            pass

    yield
    app.dependency_overrides.pop(orig_verify, None)
    app.dependency_overrides.pop(orig_verify_admin, None)
