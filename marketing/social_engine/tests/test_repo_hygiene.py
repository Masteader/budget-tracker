"""Ignore rules and the secrets template (spec Sections 4 and 11.1, task A1)."""

import subprocess
from pathlib import Path

import pytest

ENGINE_ROOT = Path(__file__).resolve().parents[1]

MUST_BE_IGNORED = [
    ".env",
    ".env.local",
    ".env.production",
    "core/.env",
    ".venv/Scripts/python.exe",
    "__pycache__/x.pyc",
    "core/__pycache__/x.pyc",
    "node_modules/remotion/index.js",
    "remotion_studio/node_modules/remotion/index.js",
    "out/frame.png",
    "output/frame.png",
    "remotion_studio/out/reel.mp4",
    "assets/raw_recordings/payday_cycle/clip_01.mp4",
    "assets/raw_recordings/payday_cycle/notes.txt",
    "assets/screenshots/home.png",
    "assets/audio/voiceovers/a.json",
    "reel.mp4",
    "clip.mov",
    "voice.m4a",
    "voice.mp3",
    "voice.wav",
    "engine.db",
    "engine.db-wal",
    "engine.db-shm",
    "logs/engine.log",
]

MUST_NOT_BE_IGNORED = [
    ".env.example",
    "config.yaml",
    "pyproject.toml",
    "core/config.py",
    "assets/branding/brand_tokens.json",
    "assets/branding/test_logo.svg",
    "remotion_studio/package-lock.json",
    "remotion_studio/props.schema.json",
    "tests/fixtures/props_valid.json",
]

SECRET_NAMES = {
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_OWNER_USER_ID",
    "AZURE_SPEECH_KEY",
    "AZURE_SPEECH_REGION",
    "ANTHROPIC_API_KEY",
    "PUBLISHER_API_KEY",
}

FORBIDDEN_TRACKED_SUFFIXES = {".mp4", ".mov", ".m4a", ".mp3", ".wav", ".db", ".db-wal", ".db-shm"}
FORBIDDEN_TRACKED_PARTS = {"node_modules", ".venv", "venv", "__pycache__"}


def _is_ignored(sample: str) -> bool:
    # --no-index: judge the rules, not whether a file happens to be tracked.
    result = subprocess.run(
        ["git", "check-ignore", "-q", "--no-index", sample],
        cwd=ENGINE_ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode in (0, 1), result.stderr
    return result.returncode == 0


@pytest.mark.parametrize("sample", MUST_BE_IGNORED)
def test_private_and_heavy_paths_are_ignored(sample):
    assert _is_ignored(sample), f"{sample} is not git-ignored"


@pytest.mark.parametrize("sample", MUST_NOT_BE_IGNORED)
def test_code_and_config_are_not_ignored(sample):
    assert not _is_ignored(sample), f"{sample} is git-ignored but must be committed"


def test_env_example_has_every_secret_name_and_only_empty_values():
    lines = (ENGINE_ROOT / ".env.example").read_text(encoding="utf-8").splitlines()
    assignments = [line for line in lines if line.strip() and not line.lstrip().startswith("#")]
    pairs = [line.split("=", 1) for line in assignments]
    assert all(len(pair) == 2 for pair in pairs), "every entry must be NAME="
    assert {name.strip() for name, _ in pairs} == SECRET_NAMES
    non_empty = [name for name, value in pairs if value.strip()]
    assert not non_empty, f"values must stay empty in .env.example: {non_empty}"


def test_nothing_heavy_or_private_is_tracked():
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "."],
        cwd=ENGINE_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout.splitlines()
    assert listed, "git ls-files returned nothing"
    offenders = []
    for line in listed:
        path = Path(line.strip('"'))
        if path.suffix.lower() in FORBIDDEN_TRACKED_SUFFIXES:
            offenders.append(line)
        elif FORBIDDEN_TRACKED_PARTS.intersection(path.parts):
            offenders.append(line)
        elif path.name == ".env" or (path.name.startswith(".env.") and path.name != ".env.example"):
            offenders.append(line)
    assert not offenders, f"would be committed: {offenders}"
