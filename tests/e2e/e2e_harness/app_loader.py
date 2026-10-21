"""Import the real ai_service app against the local stack (env is set before any app import)."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from . import config
from .tokens import service_role_key

# Variables that could make the app reach a real provider; forced empty so load_dotenv() (which
# never overrides an existing variable) cannot fill them from a stray .env file either.
_FORCED_EMPTY = (
    "SUPABASE_SERVICE_ROLE_KEY", "REDIS_URL", "GEMINI_API_KEY", "GOOGLE_API_KEY", "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY", "RESEND_API_KEY", "SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME", "SMTP_PASSWORD",
    "APP_AUTH_TOKEN", "WEBHOOK_SECRET", "TRUSTED_PROXY_IPS", "ALLOWED_ORIGINS",
)


def configure_env(gateway_url: str) -> None:
    for var in _FORCED_EMPTY:
        os.environ[var] = ""
    os.environ.update({
        "SUPABASE_URL": gateway_url,
        "SUPABASE_SECRET_KEY": service_role_key(),
        "SUPABASE_JWT_SECRET": config.JWT_SECRET,
        "ENV": "development",
        "LITELLM_MODEL": "e2e/fake-model",
        "MAIL_FROM": "Budget Tracker E2E <noreply@e2e.test>",
        "CONTACT_RECIPIENT_EMAIL": "inbox@e2e.test",
    })


def load_app(data_dir: Path):
    """
    Import ``main``. ``data_dir`` is a scratch directory for the app (it keeps no local files since
    the JSON fallbacks were removed; the database is the only store).
    """
    ai_dir = str(config.AI_SERVICE_DIR)
    if ai_dir not in sys.path:
        sys.path.insert(0, ai_dir)
    import dotenv

    dotenv.load_dotenv = lambda *a, **k: False  # never read a developer .env during e2e

    data_dir.mkdir(parents=True, exist_ok=True)

    import main

    return main.app
