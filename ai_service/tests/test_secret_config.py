"""Tests that secrets are never hardcoded and require env var configuration."""
import inspect
import main


def test_app_auth_token_requires_env_var():
    """APP_AUTH_TOKEN must come from environment, no fallback."""
    src = inspect.getsource(main)
    assert 'APP_AUTH_TOKEN = os.environ.get("APP_AUTH_TOKEN", "").strip()' in src
    assert "bt_sec_" not in src


def test_webhook_secret_requires_env_var():
    """WEBHOOK_SECRET must come from environment, no fallback."""
    src = inspect.getsource(main)
    assert 'WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "").strip()' in src
    assert "dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400" not in src
