"""Startup guard and subprocess environment (spec Sections 6.3, 11.1, 11.2).

Subprocesses get an allowlist, not a denylist: a new token in the environment stays out
without anyone having to remember its name. This file holds the one allowed mention of the
forbidden marker: the engine never touches that service, and refuses to start if a variable
for it is in its environment, under any prefix.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path

from dotenv import dotenv_values

FORBIDDEN_ENV_PREFIX = "SUPABASE_"
_FORBIDDEN_MARKER = FORBIDDEN_ENV_PREFIX.rstrip("_")

# What a Windows child process needs to start, find programs and use temp and profile
# folders. Proxy settings are out, since they can hold a password, and NODE_OPTIONS is out,
# since it can load code into npm.
SUBPROCESS_ENV_ALLOWLIST = frozenset(
    {
        "APPDATA",
        "COMMONPROGRAMFILES",
        "COMMONPROGRAMFILES(X86)",
        "COMMONPROGRAMW6432",
        "COMPUTERNAME",
        "COMSPEC",
        "HOME",
        "HOMEDRIVE",
        "HOMEPATH",
        "LANG",
        "LC_ALL",
        "LOCALAPPDATA",
        "NUMBER_OF_PROCESSORS",
        "OS",
        "PATH",
        "PATHEXT",
        "PROCESSOR_ARCHITECTURE",
        "PROGRAMDATA",
        "PROGRAMFILES",
        "PROGRAMFILES(X86)",
        "PROGRAMW6432",
        "SYSTEMDRIVE",
        "SYSTEMROOT",
        "TEMP",
        "TMP",
        "TZ",
        "USERDOMAIN",
        "USERNAME",
        "USERPROFILE",
        "WINDIR",
    }
)
_API_KEY_VAR = "ANTHROPIC_API_KEY"


class ForbiddenEnvironment(RuntimeError):
    """A forbidden variable is present. The message names it and never shows its value."""


def _is_forbidden(name: str) -> bool:
    return _FORBIDDEN_MARKER in name.upper()


def check_startup_environment(env: Mapping[str, str] | None = None) -> None:
    names = sorted(name for name in (os.environ if env is None else env) if _is_forbidden(name))
    if names:
        raise ForbiddenEnvironment(
            f"The engine refuses to start with these variables set: {', '.join(names)}. "
            "Remove them from its environment."
        )


def scrubbed_env(auth: str | None, env: Mapping[str, str] | None = None) -> dict[str, str]:
    """A new environment holding only what a subprocess needs. The API key passes only for
    exactly `api_key`, because `claude -p` always uses that key when it is present."""
    source = os.environ if env is None else env
    allowed = SUBPROCESS_ENV_ALLOWLIST | ({_API_KEY_VAR} if auth == "api_key" else set())
    return {name: value for name, value in source.items() if name.upper() in allowed}


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
