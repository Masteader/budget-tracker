"""Startup guard and scrubbed subprocess environment (spec Sections 6.3, 11.1, 11.2).

This file holds the one allowed mention of the forbidden prefix: the engine never touches
that service, and refuses to start if a variable for it is in its environment.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path

from dotenv import dotenv_values

FORBIDDEN_ENV_PREFIX = "SUPABASE_"

# Removed from every subprocess. Claude Code would bill ANTHROPIC_AUTH_TOKEN silently, so it
# goes as well, and ANTHROPIC_API_KEY stays only for `auth: api_key`.
SECRET_ENV_VARS = frozenset(
    {
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_OWNER_USER_ID",
        "AZURE_SPEECH_KEY",
        "AZURE_SPEECH_REGION",
        "PUBLISHER_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
    }
)
_API_KEY_VAR = "ANTHROPIC_API_KEY"


class ForbiddenEnvironment(RuntimeError):
    """A forbidden variable is present. The message names it and never shows its value."""


def _is_forbidden(name: str) -> bool:
    return name.upper().startswith(FORBIDDEN_ENV_PREFIX)


def check_startup_environment(env: Mapping[str, str] | None = None) -> None:
    names = sorted(name for name in (os.environ if env is None else env) if _is_forbidden(name))
    if names:
        raise ForbiddenEnvironment(
            f"The engine refuses to start with these variables set: {', '.join(names)}. "
            "Remove them from its environment."
        )


def scrubbed_env(auth: str | None, env: Mapping[str, str] | None = None) -> dict[str, str]:
    """A copy of the environment that is safe to hand to a subprocess. Anything other than
    exactly `api_key` removes the API key, which `claude -p` would otherwise always use."""
    source = os.environ if env is None else env
    removed = SECRET_ENV_VARS if auth == "api_key" else SECRET_ENV_VARS | {_API_KEY_VAR}
    return {
        name: value
        for name, value in source.items()
        if name.upper() not in removed and not _is_forbidden(name)
    }


def load_env_file(data_root: Path) -> dict[str, str]:
    """Values from `<data_root>/.env`, returned and not put in the process environment, so
    subprocesses cannot inherit them by accident."""
    path = Path(data_root) / ".env"
    if not path.is_file():
        return {}
    values = {
        name: value
        for name, value in dotenv_values(path, interpolate=False).items()
        if value is not None
    }
    check_startup_environment(values)
    return values
