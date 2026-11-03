"""Where runtime data lives (spec Section 4): outside OneDrive and outside git."""

from __future__ import annotations

import os
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

ENGINE_ROOT = Path(__file__).resolve().parents[1]

RAW_RECORDING_FOLDERS = (
    "payday_cycle",
    "zatca_receipt_scan",
    "receipt_photo_scan",
    "chat_and_voice_entry",
    "multi_account_ledger",
    "budget_capacity",
    "nafaqah_wife_expenses",
    "roommate_debt_split",
    "recurring_and_installments",
    "price_tracker",
    "smart_basket",
    "app_experience",
)

_WINDOWS_VARIABLE = re.compile(r"%([^%/\\]+)%")
_ONEDRIVE_VARIABLES = ("ONEDRIVE", "ONEDRIVECONSUMER", "ONEDRIVECOMMERCIAL")


class PathConfigError(ValueError):
    """A configured path cannot be used. The message says why."""


def _upper_keys(env: Mapping[str, str] | None) -> dict[str, str]:
    return {name.upper(): value for name, value in (os.environ if env is None else env).items()}


def expand_path(raw: str, env: Mapping[str, str] | None = None) -> Path:
    """Expand %VAR%. An undefined variable stops here, or the engine would create a
    folder literally named %LOCALAPPDATA% in the working directory."""
    known = _upper_keys(env)

    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name.upper() not in known:
            raise PathConfigError(f"{name} is not set, so {raw!r} cannot be expanded")
        return known[name.upper()]

    return Path(_WINDOWS_VARIABLE.sub(replace, raw))


def _is_inside(path: Path, folder: Path) -> bool:
    return os.path.normcase(path).startswith(os.path.normcase(folder) + os.sep) or (
        os.path.normcase(path) == os.path.normcase(folder)
    )


def resolve_data_root(raw: str, env: Mapping[str, str] | None = None) -> Path:
    """OneDrive syncing a live database risks corruption, and heavy media does not belong
    in git, so a data_root inside either one is refused."""
    root = Path(os.path.normpath(expand_path(raw, env)))
    if not root.is_absolute():
        raise PathConfigError(f"data_root must be an absolute path, got {raw!r}")
    if _is_inside(root, ENGINE_ROOT):
        raise PathConfigError(f"data_root must be outside marketing/social_engine, got {root}")
    known = _upper_keys(env)
    synced = [Path(known[name]) for name in _ONEDRIVE_VARIABLES if known.get(name)]
    in_named_folder = any(part.casefold().startswith("onedrive") for part in root.parts)
    if in_named_folder or any(_is_inside(root, folder) for folder in synced):
        raise PathConfigError(f"data_root must be outside OneDrive, got {root}")
    return root


@dataclass(frozen=True)
class EnginePaths:
    data_root: Path
    env_file: Path
    remotion_work: Path
    raw_recordings: Path
    screenshots: Path
    manifest: Path
    bg_music: Path
    voiceovers: Path
    renders: Path
    state_db: Path
    claude_cwd: Path
    logs: Path

    @classmethod
    def from_root(cls, data_root: Path) -> EnginePaths:
        assets = data_root / "assets"
        return cls(
            data_root=data_root,
            env_file=data_root / ".env",
            remotion_work=data_root / "remotion_work",
            raw_recordings=assets / "raw_recordings",
            screenshots=assets / "screenshots",
            manifest=assets / "manifest.json",
            bg_music=assets / "audio" / "bg_music",
            voiceovers=assets / "audio" / "voiceovers",
            renders=data_root / "renders",
            state_db=data_root / "state" / "engine.db",
            claude_cwd=data_root / "claude_cwd",
            logs=data_root / "logs",
        )

    def ensure_dirs(self) -> None:
        folders = [
            self.remotion_work,
            *(self.raw_recordings / folder for folder in RAW_RECORDING_FOLDERS),
            self.screenshots,
            self.bg_music,
            self.voiceovers,
            self.renders,
            self.state_db.parent,
            self.claude_cwd,
            self.logs,
        ]
        for folder in folders:
            folder.mkdir(parents=True, exist_ok=True)
