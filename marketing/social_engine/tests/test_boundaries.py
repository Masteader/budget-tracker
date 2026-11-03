"""What the engine must never contain (spec Sections 6.3 and 11.2, decisions D1, D8, D9, task A5).

Claude is the only LLM and Azure the only voice, so no other provider's name belongs here.
Python imports are read from the syntax tree, so no spelling of an import can hide from a
line-based pattern. Banned names are assembled here, so this file does not flag itself.
"""

import ast
import io
import re
import tokenize
import tomllib
import unicodedata
from importlib import metadata
from pathlib import Path

import pytest
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

from core.brand_gate import contains_withdrawn_name

ENGINE_ROOT = Path(__file__).resolve().parents[1]

DATABASE_SERVICE = "supa" + "base"
APP_SERVICE = "ai" + "_service"
GOOGLE_SDKS = ("google.generative" + "ai", "google.gen" + "ai")
BANNED_TEXT = {
    "gem" + "ini": r"gem" + r"ini",
    "lite" + "llm": r"lite" + r"llm",
    "edge" + "_tts": r"edge" + r"[-_ ]?tts",
    "eleven" + "labs": r"eleven" + r"labs",
    "open" + "ai": r"open" + r"ai",
    "mistral" + "ai": r"mistral" + r"ai",
    "co" + "here": r"\bco" + r"here\b",
    "oll" + "ama": r"oll" + r"ama",
    "lang" + "chain": r"lang" + r"chain",
    "post" + "grest": r"post" + r"grest",
    "go" + "true": r"\bgo" + r"true\b",
    GOOGLE_SDKS[0]: r"google[.-]generative" + r"ai",
    GOOGLE_SDKS[1]: r"google[.-]gen" + r"ai",
}
BANNED_IMPORT_ROOTS = {
    DATABASE_SERVICE,
    APP_SERVICE,
    "gem" + "ini",
    "lite" + "llm",
    "edge" + "_tts",
    "eleven" + "labs",
    "open" + "ai",
    "mistral" + "ai",
    "co" + "here",
    "oll" + "ama",
    "lang" + "chain",
    "post" + "grest",
    "go" + "true",
}
WITHDRAWN_NAMES = ("wa" + "feer", "وف" + "يير")

GUARD_FILE = "core/secrets.py"
GUARD_MENTION = DATABASE_SERVICE.upper() + "_"

SKIPPED_FOLDERS = {
    ".git",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
    "node_modules",
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
    ".webm",
    ".m4a",
    ".mp3",
    ".wav",
    ".db",
    ".sqlite",
    ".sqlite3",
}
_DYNAMIC_IMPORT_CALLS = {
    "__import__",
    "import_module",
    "run_module",
    "run_path",
    "find_spec",
    "spec_from_file_location",
}
_DATABASE_NAME = re.compile(DATABASE_SERVICE, re.IGNORECASE)


def _is_real_env_file(path: Path) -> bool:
    is_env = path.name.startswith(".env") or path.name.endswith(".env")
    return is_env and path.name != ".env.example"


def scanned_files(root: Path) -> list[Path]:
    """Everything under root except the Markdown in docs/, caches and real .env files, which
    no test may read."""
    files = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if relative.parts[0] == "docs" and path.suffix.lower() == ".md":
            continue
        if SKIPPED_FOLDERS.intersection(relative.parts):
            continue
        if path.is_file() and not _is_real_env_file(path):
            files.append(path)
    return files


def _is_banned_import(dotted: str) -> bool:
    return dotted.split(".", 1)[0] in BANNED_IMPORT_ROOTS or any(
        dotted == sdk or dotted.startswith(f"{sdk}.") for sdk in GOOGLE_SDKS
    )


def _folded_string(node: ast.AST) -> str | None:
    """A literal, or literals joined with +, which is the usual way to dodge a text search."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = _folded_string(node.left), _folded_string(node.right)
        if left is not None and right is not None:
            return left + right
    return None


def _call_arguments(node: ast.Call) -> list[str]:
    values = [_folded_string(arg) for arg in [*node.args, *(kw.value for kw in node.keywords)]]
    return [value for value in values if value is not None]


def _is_dynamic_import(node: ast.Call) -> bool:
    function = node.func
    name = function.attr if isinstance(function, ast.Attribute) else getattr(function, "id", "")
    return name in _DYNAMIC_IMPORT_CALLS


def _is_sys_path_change(node: ast.Call) -> bool:
    function = node.func
    return (
        isinstance(function, ast.Attribute)
        and function.attr in {"append", "insert", "extend"}
        and isinstance(function.value, ast.Attribute)
        and function.value.attr == "path"
        and getattr(function.value.value, "id", "") == "sys"
    )


def _names_banned_module(text: str) -> bool:
    folded = unicodedata.normalize("NFKC", text).casefold()
    names = [*BANNED_IMPORT_ROOTS, *GOOGLE_SDKS]
    return any(name in folded for name in names)


def _python_findings(relative: str, raw: bytes) -> list[str]:
    """The source is read as Python itself reads it: cookie first, then the syntax tree, where
    identifiers are already normalised, so full-width letters come out as plain ones."""
    try:
        encoding, _ = tokenize.detect_encoding(io.BytesIO(raw).readline)
    except SyntaxError as error:
        return [f"{relative}: bad encoding declaration: {error}"]
    if encoding not in {"utf-8", "utf-8-sig"}:
        return [f"{relative}: declares encoding {encoding}, and only UTF-8 is allowed"]
    try:
        tree = ast.parse(raw)
    except (SyntaxError, ValueError) as error:
        return [f"{relative}: cannot be parsed, so it cannot be checked: {error}"]

    findings = []
    for node in ast.walk(tree):
        imported: list[str] = []
        if isinstance(node, ast.Import):
            imported = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module and not node.level:
            imported = [node.module, *(f"{node.module}.{alias.name}" for alias in node.names)]
        findings += [f"{relative}: imports {name}" for name in imported if _is_banned_import(name)]

        if isinstance(node, ast.Call) and (_is_dynamic_import(node) or _is_sys_path_change(node)):
            for text in _call_arguments(node):
                if _names_banned_module(text):
                    findings.append(f"{relative}: reaches a banned module through {text!r}")
        if (
            isinstance(node, ast.Constant)
            and isinstance(node.value, str)
            and contains_withdrawn_name(node.value)
        ):
            findings.append(f"{relative}: uses the withdrawn name")
    return findings


def _database_findings(relative: str, text: str) -> list[str]:
    hits = list(_DATABASE_NAME.finditer(text))
    if relative == GUARD_FILE:
        # The one allowed mention, in exactly its upper-case form. An import is still caught.
        hits = [hit for hit in hits if not text.startswith(GUARD_MENTION, hit.start())]
    return [f"{relative}: names the database service" for _ in hits]


def _text_findings(relative: str, text: str, is_python: bool) -> list[str]:
    normalised = unicodedata.normalize("NFKC", text)
    searched = f"{relative}\n{normalised}"
    findings = _database_findings(relative, normalised)
    # Source that shows one thing and means another (bidi controls, zero-width characters).
    # Code writes these as escapes, so they stay visible in review.
    hidden = sorted({ch for ch in text if unicodedata.category(ch) == "Cf"})
    if hidden:
        findings.append(f"{relative}: holds hidden characters {[hex(ord(c)) for c in hidden]}")
    if _DATABASE_NAME.search(relative):
        findings.append(f"{relative}: named after the database service")
    for name, pattern in BANNED_TEXT.items():
        if re.search(pattern, searched, re.IGNORECASE):
            findings.append(f"{relative}: mentions {name}")
    if contains_withdrawn_name(relative) or any(
        name in searched.casefold() for name in WITHDRAWN_NAMES
    ):
        findings.append(f"{relative}: uses the withdrawn name")
    if not is_python and any(contains_withdrawn_name(line) for line in text.splitlines()):
        # Python literals were checked one by one, so that an assembled name stays legal there.
        findings.append(f"{relative}: uses the withdrawn name")
    return findings


def scan_for_violations(root: Path) -> list[str]:
    findings = []
    for path in scanned_files(root):
        relative = path.relative_to(root).as_posix()
        if path.suffix.lower() in BINARY_SUFFIXES:
            findings += _text_findings(relative, "", is_python=False)
            continue
        raw = path.read_bytes()
        is_python = path.suffix == ".py"
        if is_python:
            python_findings = _python_findings(relative, raw)
            findings += python_findings
            if any("encoding" in item or "parsed" in item for item in python_findings):
                continue
        try:
            text = raw.decode("utf-8").removeprefix(chr(0xFEFF))
        except UnicodeDecodeError:
            findings.append(f"{relative}: is not UTF-8, so it cannot be checked")
            continue
        if "\x00" in text:  # UTF-16 with no byte-order mark decodes as UTF-8 with NUL bytes
            findings.append(f"{relative}: holds NUL bytes, so it is not UTF-8 text")
            continue
        findings += _text_findings(relative, text, is_python)
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
    assert not any(path.startswith("docs/") and path.endswith(".md") for path in relative)


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
    banned = [name.replace("_", "-").replace(".", "-") for name in BANNED_TEXT]
    banned.append(DATABASE_SERVICE)
    assert [dep for dep in dependencies for name in banned if name in dep] == []


def test_every_dependency_is_pinned_exactly():
    pyproject = tomllib.loads((ENGINE_ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    for group in pyproject["dependency-groups"].values():
        for pin in group:
            assert "==" in pin, f"{pin} is not pinned exactly"


# --- The scan catches what it should ---------------------------------------------------


def _write(root: Path, relative: str, text: str = "x", encoding: str = "utf-8") -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode(encoding))


def _full_width(text: str) -> str:
    return "".join(chr(ord(ch) + 0xFEE0) if ch.isalnum() else ch for ch in text)


OTHER_LLM = "open" + "ai"
OTHER_LLM_2 = "mistral" + "ai"


@pytest.mark.parametrize(
    ("relative", "text"),
    [
        ("core/a.py", f"import {DATABASE_SERVICE}\n"),
        ("core/a.py", f"client = {DATABASE_SERVICE.title()}Client()\n"),
        ("core/a.py", f"x = '{GUARD_MENTION}URL'\n"),
        ("core/secrets.py", f"import {DATABASE_SERVICE}\n"),
        ("core/secrets.py", f"from {DATABASE_SERVICE} import create_client\n"),
        ("pyproject.toml", f'runtime = ["{DATABASE_SERVICE}==2.0"]\n'),
        ("pyproject.toml", 'runtime = ["post' + 'grest==1"]\n'),
        ("core/a.py", "import " + "gem" + "ini\n"),
        ("core/a.py", "model = '" + "GEM" + "INI-pro'\n"),
        ("core/a.py", "import " + "lite" + "llm\n"),
        ("core/a.py", "import " + "edge" + "_tts\n"),
        ("core/a.py", "x = '" + "edge" + " tts'\n"),
        ("pyproject.toml", 'x = ["' + "edge" + '-tts==1"]\n'),
        ("core/a.py", "import " + "eleven" + "labs\n"),
        ("core/a.py", f"import {OTHER_LLM}\n"),
        ("core/a.py", f"from {OTHER_LLM} import Client\n"),
        ("core/a.py", f"import {OTHER_LLM_2}\n"),
        ("core/a.py", f"import {GOOGLE_SDKS[0]}\n"),
        ("core/a.py", f"import {GOOGLE_SDKS[0]} as genai\n"),
        ("core/a.py", "from google import gen" + "ai\n"),
        ("core/a.py", "from google import generative" + "ai\n"),
        ("pyproject.toml", 'x = ["google-gen' + 'ai==1"]\n'),
        ("pyproject.toml", 'x = ["google-generative' + 'ai==1"]\n'),
        ("remotion_studio/package.json", '{"' + "gem" + 'ini": "1"}\n'),
        (".env.example", "GEM" + "INI_KEY=\n"),
        ("core/a.py", f"import {APP_SERVICE}\n"),
        ("core/a.py", f"from {APP_SERVICE}.price_tracker import x\n"),
        ("core/a.py", f"    from {APP_SERVICE} import y\n"),
        ("core/a.py", f"import os, {APP_SERVICE}\n"),
        ("core/a.py", f"import os; import {APP_SERVICE}\n"),
        ("core/a.py", f"if True: import {APP_SERVICE}\n"),
        ("core/a.py", f"from \\\n  {APP_SERVICE} import x\n"),
        ("core/a.py", f"import\\\n {APP_SERVICE}\n"),
        ("core/a.py", f"import {_full_width(APP_SERVICE)}\n"),
        ("core/a.py", f"import {_full_width(DATABASE_SERVICE)}\n"),
        ("core/a.py", f"def f():\n    if x:\n        import {APP_SERVICE}\n"),
        ("core/a.py", f"importlib.import_module('{APP_SERVICE}.x')\n"),
        ("core/a.py", f"importlib.import_module(name='{APP_SERVICE}')\n"),
        ("core/a.py", f"__import__('{APP_SERVICE}')\n"),
        ("core/a.py", "__import__('ai_' + 'serv' + 'ice')\n"),
        ("core/a.py", "__import__('su' + 'pa' + 'ba' + 'se')\n"),
        ("core/a.py", f"runpy.run_module('{APP_SERVICE}')\n"),
        ("core/a.py", f"sys.path.append('../../{APP_SERVICE}')\n"),
        ("core/a.py", f"sys.path.insert(0, '../../{APP_SERVICE}')\n"),
        ("core/a.py", f"name = '{WITHDRAWN_NAMES[0].title()}'\n"),
        ("core/a.py", f"# a comment about {WITHDRAWN_NAMES[0]}\n"),
        ("core/a.py", "name = 'W\u00e1" + "feer'\n"),
        ("tests/fixtures/a.json", f'{{"name": "{WITHDRAWN_NAMES[1]}"}}\n'),
        ("assets/branding/notes.txt", WITHDRAWN_NAMES[0].upper()),
        ("assets/branding/notes.txt", f"{WITHDRAWN_NAMES[0][:2]} {WITHDRAWN_NAMES[0][2:]}"),
        ("config.yaml", f"name: {WITHDRAWN_NAMES[0][:2]}\u200d{WITHDRAWN_NAMES[0][2:]}\n"),
        ("config.yaml", f"name: {WITHDRAWN_NAMES[1][0]}\u064e{WITHDRAWN_NAMES[1][1:]}\n"),
        (f"assets/branding/{WITHDRAWN_NAMES[0]}_logo.png", "not text anyway"),
        (f"assets/branding/{WITHDRAWN_NAMES[0]}.svg", "<svg/>"),
        ("docs/evil.py", f"import {DATABASE_SERVICE}\n"),
        ("docs/data.json", '{"' + "gem" + 'ini": 1}\n'),
        ("core/out/evil.py", f"import {DATABASE_SERVICE}\n"),
        ("core/logs/evil.py", f"import {DATABASE_SERVICE}\n"),
    ],
)
def test_the_scan_flags_each_banned_sample(tmp_path, relative, text):
    _write(tmp_path, relative, text)
    assert scan_for_violations(tmp_path), f"{relative} was not flagged: {text!r}"


@pytest.mark.parametrize(
    ("relative", "raw"),
    [
        ("core/a.py", b"# coding: utf-7\nimport +AHM-upabase\n"),
        ("core/a.py", b"# -*- coding: latin-1 -*-\nx = 1\n"),
        ("core/a.py", b"# coding: not-a-real-codec\nx = 1\n"),
        ("core/a.py", "x = 'é'\n".encode("latin-1")),
        ("core/a.py", "x = 1\n".encode("utf-16")),
        ("core/a.py", b"def broken(:\n"),
        ("requirements.txt", f"{DATABASE_SERVICE}==2.0\n".encode("utf-16")),
        ("remotion_studio/package.json", ('{"' + "gem" + 'ini": "1"}').encode("utf-16")),
        ("pyproject.toml", 'x = "é"\n'.encode("latin-1")),
        ("config.yaml", "name: x\n".encode("utf-16-le")),
    ],
)
def test_the_scan_fails_on_files_it_cannot_read_as_utf8(tmp_path, relative, raw):
    path = tmp_path / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    assert scan_for_violations(tmp_path), f"{relative} was not flagged: {raw!r}"


@pytest.mark.parametrize(
    "code_point", [0x202E, 0x2066, 0x200B, 0x200F, 0xFEFF], ids=lambda point: hex(point)
)
@pytest.mark.parametrize("relative", ["core/a.py", "config.yaml", "tests/fixtures/a.json"])
def test_the_scan_flags_hidden_characters_written_straight_into_a_file(
    tmp_path, relative, code_point
):
    _write(tmp_path, relative, f'x = "a{chr(code_point)}b"\n')
    assert scan_for_violations(tmp_path), f"{relative} was not flagged"


def test_a_hidden_character_written_as_an_escape_is_fine(tmp_path):
    _write(tmp_path, "core/a.py", 'x = "a\\u202eb"\n')
    assert scan_for_violations(tmp_path) == []


def test_a_utf8_bom_is_still_readable(tmp_path):
    (tmp_path / "a.py").write_bytes(b"\xef\xbb\xbfx = 1\n")
    assert scan_for_violations(tmp_path) == []


def test_the_guard_file_may_mention_the_prefix_and_nothing_else(tmp_path):
    _write(tmp_path, "core/secrets.py", f'PREFIX = "{GUARD_MENTION}"\n')
    assert scan_for_violations(tmp_path) == []


def test_the_scan_skips_markdown_in_docs_and_caches(tmp_path):
    banned = f"import {DATABASE_SERVICE}\n" + WITHDRAWN_NAMES[0]
    _write(tmp_path, "docs/SPEC.md", banned)
    _write(tmp_path, "core/__pycache__/a.py", banned)
    _write(tmp_path, "remotion_work/node_modules/a.js", banned)
    assert scan_for_violations(tmp_path) == []


def test_only_the_top_level_docs_folder_is_skipped(tmp_path):
    _write(tmp_path, "core/docs/a.md", f"import {DATABASE_SERVICE}\n")
    assert scan_for_violations(tmp_path)


def test_a_real_env_file_is_never_read(tmp_path, monkeypatch):
    for name in (".env", ".env.local", ".env - Copy", "secrets.env"):
        _write(tmp_path, name, WITHDRAWN_NAMES[0])
    opened = []
    real_read_bytes = Path.read_bytes

    def spying_read_bytes(self):
        opened.append(self.name)
        return real_read_bytes(self)

    monkeypatch.setattr(Path, "read_bytes", spying_read_bytes)
    assert scan_for_violations(tmp_path) == []
    assert opened == []


def test_an_evidence_path_that_only_mentions_the_folder_is_not_an_import(tmp_path):
    # The claims register cites evidence in that folder by path, and never imports it.
    _write(tmp_path, "core/a.py", f'EVIDENCE = "{APP_SERVICE}/price_tracker.py"\n')
    _write(tmp_path, "core/b.py", f'evidence.append("{APP_SERVICE}/price_tracker.py")\n')
    assert scan_for_violations(tmp_path) == []


def test_a_relative_import_with_an_ordinary_name_is_fine(tmp_path):
    _write(tmp_path, "core/a.py", "from . import paths\nfrom .secrets import load_env_file\n")
    assert scan_for_violations(tmp_path) == []


def test_an_assembled_name_in_a_python_literal_stays_legal_for_guards(tmp_path):
    # core/brand_gate.py has to hold the withdrawn name to refuse it.
    head, tail = WITHDRAWN_NAMES[0][:2], WITHDRAWN_NAMES[0][2:]
    _write(tmp_path, "core/a.py", f'NAME = "{head}" + "{tail}"\n')
    assert scan_for_violations(tmp_path) == []
