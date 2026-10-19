"""Tests that secrets are never hardcoded and require env var configuration."""
import inspect
import os
import subprocess
import sys
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


def test_runtime_secret_loading_in_isolated_process():
    """Verify runtime behavior: without env vars set, tokens default to empty string without hardcoded fallbacks."""
    code = """
import os
import sys
import dotenv

# Prevent reading local .env file
dotenv.load_dotenv = lambda *a, **kw: None
os.environ.pop("APP_AUTH_TOKEN", None)
os.environ.pop("WEBHOOK_SECRET", None)

import main

assert main.APP_AUTH_TOKEN == "", f"Expected empty APP_AUTH_TOKEN, got {main.APP_AUTH_TOKEN}"
assert main.WEBHOOK_SECRET == "", f"Expected empty WEBHOOK_SECRET, got {main.WEBHOOK_SECRET}"
print("RUNTIME_SECRETS_VERIFIED")
"""
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        cwd=os.path.dirname(os.path.dirname(__file__)),
    )
    assert result.returncode == 0, f"Subprocess failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert "RUNTIME_SECRETS_VERIFIED" in result.stdout
