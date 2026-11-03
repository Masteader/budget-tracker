"""What the engine must never contain (spec Sections 6.3 and 11.2, decisions D1, D8, D9, task A5).

Banned names are assembled here, so this file does not flag itself.
"""

import re
import tomllib
from importlib import metadata
from pathlib import Path

import pytest
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

ENGINE_ROOT = Path(__file__).resolve().parents[1]

DATABASE_SERVICE = "supa" + "base"
BANNED_TOOLS = {
    "gem" + "ini": r"gem" + r"ini",
    "lite" + "llm": r"lite" + r"llm",
    "edge" + "_tts": r"edge" + r"[-_]tts",
    "eleven" + "labs": r"eleven" + r"labs",
}
WITHDRAWN_NAMES = ("wa" + "feer", "وف" + "يير")
APP_SERVICE = "ai" + "_service"

GUARD_FILE = "core/secrets.py"
GUARD_MENTION = DATABASE_SERVICE.upper() + "_"

SKIPPED_FOLDERS = {
    ".git",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
    "logs",
    "node_modules",
    "out",
    "output",
}
BINARY_SUFFIXES = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".ico",
    ".ttf",
    ".otf",
    ".woff",
    ".woff2",
    ".mp4",
    ".mov",
    ".m4a",
    ".mp3",
    ".wav",
    ".db",
}

_APP_IMPORT = re.compile(
    rf"""^\s*(?:from|import)\s+{APP_SERVICE}\b|(?:import_module|__import__)\(\s*["']{APP_SERVICE}""",
    re.MULTILINE,
)
_DATABASE_NAME = re.compile(DATABASE_SERVICE, re.IGNORECASE)


def _is_real_env_file(path: Path) -> bool:
    return path.name == ".env" or (path.name.startswith(".env.") and path.name != ".env.example")


def scanned_files(root: Path) -> list[Path]:
    """Everything under root except docs/, build output and real .env files, which no test
    may read."""
    files = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if relative.parts[0] == "docs" or SKIPPED_FOLDERS.intersection(relative.parts):
            continue
        if path.is_file() and not _is_real_env_file(path):
            files.append(path)
    return files


def _database_findings(relative: str, text: str) -> list[str]:
    hits = list(_DATABASE_NAME.finditer(text))
    if relative == GUARD_FILE:
        # The one allowed mention, in exactly its upper-case form. An import is still caught.
        hits = [hit for hit in hits if not text.startswith(GUARD_MENTION, hit.start())]
    return [f"{relative}: names the database service" for _ in hits]


def scan_for_violations(root: Path) -> list[str]:
    findings = []
    for path in scanned_files(root):
        relative = path.relative_to(root).as_posix()
        text = "" if path.suffix.lower() in BINARY_SUFFIXES else path.read_text("utf-8", "ignore")
        searched = f"{relative}\n{text}"
        findings += _database_findings(relative, text)
        if _DATABASE_NAME.search(relative):
            findings.append(f"{relative}: named after the database service")
        for name, pattern in BANNED_TOOLS.items():
            if re.search(pattern, searched, re.IGNORECASE):
                findings.append(f"{relative}: mentions {name}")
        for name in WITHDRAWN_NAMES:
            if name in searched.casefold():
                findings.append(f"{relative}: uses the withdrawn name")
        if path.suffix == ".py" and _APP_IMPORT.search(text):
            findings.append(f"{relative}: imports the app's AI service")
    return findings


# --- The engine itself -----------------------------------------------------------------


def test_the_scan_really_covers_the_engine():
    relative = {path.relative_to(ENGINE_ROOT).as_posix() for path in scanned_files(ENGINE_ROOT)}
    assert {
        "core/config.py",
        "core/secrets.py",
        "content_engine/schemas.py",
        "config.yaml",
        "pyproject.toml",
        ".env.example",
        "tests/conftest.py",
        "tests/fixtures/props_valid.json",
    } <= relative
    assert not any(path.startswith("docs/") for path in relative)


def test_the_engine_has_no_banned_names_or_imports():
    assert scan_for_violations(ENGINE_ROOT) == []


def _direct_dependencies() -> list[str]:
    pyproject = tomllib.loads((ENGINE_ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    pins = [pin for group in pyproject["dependency-groups"].values() for pin in group]
    assert pins
    return [Requirement(pin).name for pin in pins]


def _all_dependencies(names: list[str]) -> set[str]:
    seen: set[str] = set()
    waiting = list(names)
    while waiting:
        name = canonicalize_name(waiting.pop())
        if name in seen:
            continue
        seen.add(name)
        try:
            requirements = metadata.requires(name) or []
        except metadata.PackageNotFoundError:
            continue
        for line in requirements:
            requirement = Requirement(line)
            if requirement.marker is None or requirement.marker.evaluate({"extra": ""}):
                waiting.append(requirement.name)
    return seen


def test_no_dependency_is_banned_even_indirectly():
    dependencies = _all_dependencies(_direct_dependencies())
    assert "pydantic-core" in dependencies, "the dependency walk found nothing indirect"
    banned = [DATABASE_SERVICE, *BANNED_TOOLS]
    offenders = [dep for dep in dependencies for name in banned if name.replace("_", "-") in dep]
    assert offenders == []


def test_every_dependency_is_pinned_exactly():
    pyproject = tomllib.loads((ENGINE_ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    for group in pyproject["dependency-groups"].values():
        for pin in group:
            assert "==" in pin, f"{pin} is not pinned exactly"


# --- The scan catches what it should ---------------------------------------------------


def _write(root: Path, relative: str, text: str = "x") -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


@pytest.mark.parametrize(
    ("relative", "text"),
    [
        ("core/a.py", f"import {DATABASE_SERVICE}\n"),
        ("core/a.py", f"client = {DATABASE_SERVICE.title()}Client()\n"),
        ("core/a.py", f"x = '{GUARD_MENTION}URL'\n"),
        ("core/secrets.py", f"import {DATABASE_SERVICE}\n"),
        ("core/secrets.py", f"from {DATABASE_SERVICE} import create_client\n"),
        ("pyproject.toml", f'runtime = ["{DATABASE_SERVICE}==2.0"]\n'),
        ("core/a.py", "import " + "gem" + "ini\n"),
        ("core/a.py", "model = '" + "GEM" + "INI-pro'\n"),
        ("core/a.py", "import " + "lite" + "llm\n"),
        ("core/a.py", "import " + "edge" + "_tts\n"),
        ("pyproject.toml", 'x = ["' + "edge" + '-tts==1"]\n'),
        ("core/a.py", "import " + "eleven" + "labs\n"),
        ("remotion_studio/package.json", '{"' + "gem" + 'ini": "1"}\n'),
        (".env.example", "GEM" + "INI_KEY=\n"),
        ("core/a.py", f"import {APP_SERVICE}\n"),
        ("core/a.py", f"from {APP_SERVICE}.price_tracker import x\n"),
        ("core/a.py", f"    from {APP_SERVICE} import y\n"),
        ("core/a.py", f"importlib.import_module('{APP_SERVICE}.x')\n"),
        ("core/a.py", f"__import__('{APP_SERVICE}')\n"),
        ("core/a.py", f"name = '{WITHDRAWN_NAMES[0].title()}'\n"),
        ("tests/fixtures/a.json", f'{{"name": "{WITHDRAWN_NAMES[1]}"}}\n'),
        ("assets/branding/notes.txt", WITHDRAWN_NAMES[0].upper()),
        (f"assets/branding/{WITHDRAWN_NAMES[0]}_logo.png", "not text anyway"),
        (f"assets/branding/{WITHDRAWN_NAMES[0]}.svg", "<svg/>"),
    ],
)
def test_the_scan_flags_each_banned_sample(tmp_path, relative, text):
    _write(tmp_path, relative, text)
    assert scan_for_violations(tmp_path), f"{relative} was not flagged"


def test_the_guard_file_may_mention_the_prefix_and_nothing_else(tmp_path):
    _write(tmp_path, "core/secrets.py", f'PREFIX = "{GUARD_MENTION}"\n')
    assert scan_for_violations(tmp_path) == []


def test_the_scan_skips_docs_and_build_output(tmp_path):
    banned = f"import {DATABASE_SERVICE}\n" + WITHDRAWN_NAMES[0]
    _write(tmp_path, "docs/SPEC.md", banned)
    _write(tmp_path, "core/__pycache__/a.py", banned)
    _write(tmp_path, "remotion_work/node_modules/a.js", banned)
    assert scan_for_violations(tmp_path) == []


def test_only_the_top_level_docs_folder_is_skipped(tmp_path):
    _write(tmp_path, "core/docs/a.py", f"import {DATABASE_SERVICE}\n")
    assert scan_for_violations(tmp_path)


def test_a_real_env_file_is_never_read(tmp_path, monkeypatch):
    _write(tmp_path, ".env", WITHDRAWN_NAMES[0])
    _write(tmp_path, ".env.local", WITHDRAWN_NAMES[0])
    opened = []
    real_read_text = Path.read_text

    def spying_read_text(self, *args, **kwargs):
        opened.append(self.name)
        return real_read_text(self, *args, **kwargs)

    monkeypatch.setattr(Path, "read_text", spying_read_text)
    assert scan_for_violations(tmp_path) == []
    assert opened == []


def test_an_evidence_path_that_only_mentions_the_folder_is_not_an_import(tmp_path):
    # The claims register cites evidence in that folder by path, and never imports it.
    _write(tmp_path, "core/a.py", f'EVIDENCE = "{APP_SERVICE}/price_tracker.py"\n')
    assert scan_for_violations(tmp_path) == []
