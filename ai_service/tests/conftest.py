"""Shared test fixtures and environment setup."""
import os
import pytest
from fastapi import Request

# Set test secrets before any imports of main
os.environ.setdefault("WEBHOOK_SECRET", "test_secret_for_ci_only_do_not_use_in_prod")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token_for_ci_only")
os.environ.setdefault("ENV", "development")
os.environ.setdefault("SUPABASE_URL", "https://mockproject.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "mock_service_role_key_for_testing")
os.environ.setdefault("LITELLM_MODEL", "gemini/gemini-2.0-flash")
os.environ.setdefault("GOOGLE_API_KEY", "mock_google_api_key_for_testing")

TEST_HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"


@pytest.fixture(autouse=True)
def mock_auth(monkeypatch, request):
    """
    Auto-mock JWT verification in tests via FastAPI dependency overrides and monkeypatch
    unless the test is specifically testing auth or security posture.
    """
    if "test_auth" in request.node.nodeid or "test_security_posture" in request.node.nodeid:
        yield
        return

    async def fake_verify(request: Request, household_id: str):
        return household_id

    import auth
    orig_verify = auth.verify_household_access

    from main import app
    app.dependency_overrides[orig_verify] = fake_verify

    monkeypatch.setattr(auth, "verify_household_access", fake_verify)

    for mod_name in ["routes.budgets", "routes.households", "routes.analytics", "routes.receipts", "routes.chat", "routes.reports"]:
        try:
            import importlib
            mod = importlib.import_module(mod_name)
            monkeypatch.setattr(mod, "verify_household_access", fake_verify)
        except Exception:
            pass

    yield
    app.dependency_overrides.pop(orig_verify, None)
