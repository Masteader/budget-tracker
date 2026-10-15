"""Tests that secrets are never hardcoded and require env var configuration."""
import os
import importlib
from unittest.mock import patch


def test_app_auth_token_requires_env_var():
    """APP_AUTH_TOKEN must come from environment, no fallback."""
    with patch.dict(os.environ, {"APP_AUTH_TOKEN": "", "ENV": "development"}, clear=False):
        import main
        importlib.reload(main)
        assert main.APP_AUTH_TOKEN == ""


def test_webhook_secret_requires_env_var():
    """WEBHOOK_SECRET must come from environment, no fallback."""
    with patch.dict(os.environ, {"WEBHOOK_SECRET": "", "ENV": "development"}, clear=False):
        import main
        importlib.reload(main)
        assert main.WEBHOOK_SECRET != "dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400"
        assert main.WEBHOOK_SECRET == ""
