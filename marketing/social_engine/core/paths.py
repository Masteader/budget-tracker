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
_WINDOWS_DEVICE_NAMES = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{n}" for n in range(1, 10)),
    *(f"LPT{n}" for n in range(1, 10)),
}


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


def is_windows_safe_name(name: str) -> bool:
    """False for a path part that Windows would silently change or treat as a device: NUL,
    `a.`, `a ` (Windows drops the trailing character) and `a:b` (an alternate data stream)."""
    return (
        bool(name)
        and name[-1] not in ". "
        and ":" not in name
        and name.split(".", 1)[0].rstrip(" ").upper() not in _WINDOWS_DEVICE_NAMES
    )


def _is_inside(path: Path, folder: Path) -> bool:
    inner, outer = os.path.normcase(path), os.path.normcase(folder).rstrip("\\/")
    return inner == outer or inner.startswith(outer + os.sep)


def _check_written_form(raw: str, expanded: Path) -> None:
    text = str(expanded)
    if text.startswith(("\\\\", "//")):
        raise PathConfigError(f"data_root must be a plain local folder, got {raw!r}")
    if not expanded.is_absolute():
        raise PathConfigError(f"data_root must be an absolute path, got {raw!r}")
    for part in expanded.parts[1:]:
        if part != ".." and not is_windows_safe_name(part):
            raise PathConfigError(f"data_root has a part Windows would change: {part!r}")


def _repo_folders() -> list[Path]:
    """The engine plus every git checkout around it, including a worktree's outer checkout."""
    engine = Path(os.path.realpath(ENGINE_ROOT))
    return [engine, *(parent for parent in engine.parents if (parent / ".git").exists())]


def resolve_data_root(raw: str, env: Mapping[str, str] | None = None) -> Path:
    """OneDrive syncing a live database risks corruption, and heavy media does not belong
    in git, so a data_root inside either one is refused, as is one that holds the repo. The
    checks run on the real path, after junctions and `..`, so a link cannot get round them."""
    expanded = expand_path(raw, env)
    _check_written_form(raw, expanded)
    root = Path(os.path.realpath(expanded))
    engine = Path(os.path.realpath(ENGINE_ROOT))
    if _is_inside(engine, root) or any(_is_inside(root, repo) for repo in _repo_folders()):
        raise PathConfigError(f"data_root must be outside the social_engine repo, got {root}")
    known = _upper_keys(env)
    synced = [Path(os.path.realpath(known[n])) for n in _ONEDRIVE_VARIABLES if known.get(n)]
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
