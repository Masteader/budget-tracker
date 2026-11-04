"""Invariant 1, at the source level: only the bot builds a VerifiedOwnerTap (task B3).

The syntax tree is read, so no alias or line break hides a construction from the scan, and a
plain text search backs it up for anything the tree cannot see, such as a string for `eval`.
"""

import ast
from pathlib import Path

import pytest

ENGINE_ROOT = Path(__file__).resolve().parents[1]
TAP = "VerifiedOwnerTap"
ALLOWED_FILE = "approval/telegram_bot.py"
SKIPPED_FOLDERS = {".git", ".pytest_cache", ".ruff_cache", ".venv", "__pycache__", "node_modules"}
FIRST_FOLDER_ALLOWED = "tests"


def _names_of_the_tap(tree: ast.AST) -> set[str]:
    """The class name, plus any name it was imported or assigned under."""
    names = {TAP}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name == TAP and alias.asname:
                    names.add(alias.asname)
    # An assignment can chain from an earlier one, so this repeats until nothing new turns up.
    grew = True
    while grew:
        grew = False
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and _called_name(node.value) in names:
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id not in names:
                        names.add(target.id)
                        grew = True
    return names


def _called_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Attribute):
        return node.attr
    if isinstance(node, ast.Name):
        return node.id
    return None


def constructions_in(source: str) -> list[int]:
    """Line numbers where the source builds a tap, or reaches for the class by a string."""
    tree = ast.parse(source)
    names = _names_of_the_tap(tree)
    lines = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and _builds_a_tap(node, names):
            lines.append(node.lineno)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) and TAP in node.value:
            lines.append(node.lineno)
    return lines


def _builds_a_tap(call: ast.Call, names: set[str]) -> bool:
    called = _called_name(call.func)
    if called in names:
        return True
    # VerifiedOwnerTap.__new__(VerifiedOwnerTap) and object.__new__(VerifiedOwnerTap)
    return called == "__new__" and any(_called_name(arg) in names for arg in call.args)


def _has_docstring_only_mention(node: ast.AST) -> bool:
    return isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant)


def _docstring_lines(tree: ast.AST) -> set[int]:
    """A docstring may name the class. Everything else that holds the name is a finding."""
    lines = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Module | ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef):
            if node.body and _has_docstring_only_mention(node.body[0]):
                lines.add(node.body[0].value.lineno)
    return lines


def findings_in(relative: str, source: str) -> list[str]:
    if relative == ALLOWED_FILE or relative.split("/", 1)[0] == FIRST_FOLDER_ALLOWED:
        return []
    docstrings = _docstring_lines(ast.parse(source))
    found = [line for line in constructions_in(source) if line not in docstrings]
    return [f"{relative}:{line} builds a {TAP}" for line in found]


def engine_sources() -> list[Path]:
    return [
        path
        for path in ENGINE_ROOT.rglob("*.py")
        if not SKIPPED_FOLDERS.intersection(path.relative_to(ENGINE_ROOT).parts)
    ]


def test_the_scan_really_covers_the_engine():
    relative = {path.relative_to(ENGINE_ROOT).as_posix() for path in engine_sources()}
    assert {"core/state.py", "core/locks.py", "core/cadence.py", "core/config.py"} <= relative


def test_nothing_outside_the_bot_builds_a_tap():
    findings = []
    for path in engine_sources():
        relative = path.relative_to(ENGINE_ROOT).as_posix()
        findings += findings_in(relative, path.read_text(encoding="utf-8"))
    assert findings == []


def test_the_state_store_only_describes_the_tap():
    # It defines the class and checks instances of it, and it must never make one.
    source = (ENGINE_ROOT / "core" / "state.py").read_text(encoding="utf-8")
    assert f"class {TAP}" in source
    assert findings_in("core/state.py", source) == []


@pytest.mark.parametrize(
    "source",
    [
        f"from core.state import {TAP}\nx = {TAP}('r', 1, 'approve', 1, 'c')\n",
        f"import core.state\nx = core.state.{TAP}('r', 1, 'approve', 1, 'c')\n",
        f"import core.state as s\nx = s.{TAP}('r', 1, 'approve', 1, 'c')\n",
        f"from core.state import {TAP} as Tap\nx = Tap('r', 1, 'approve', 1, 'c')\n",
        f"from core.state import {TAP}\nTap = {TAP}\nx = Tap('r', 1, 'approve', 1, 'c')\n",
        f"from core.state import {TAP}\nA = {TAP}\nB = A\nx = B('r', 1, 'approve', 1, 'c')\n",
        f"x = {TAP}.__new__({TAP})\n",
        f"x = object.__new__({TAP})\n",
        f"import core.state as s\nx = getattr(s, '{TAP}')\n",
        f"eval('{TAP}(1)')\n",
        f"def f():\n    return {TAP}(\n        'r',\n    )\n",
    ],
)
def test_the_scan_catches_a_construction(source):
    assert findings_in("publisher/base.py", source), source


@pytest.mark.parametrize(
    "source",
    [
        f"def f(tap: {TAP}) -> None:\n    '''Takes a {TAP}.'''\n",
        f'"""Module about {TAP}."""\n',
        f"from core.state import {TAP}\ndef f(tap):\n    return isinstance(tap, {TAP})\n",
    ],
)
def test_the_scan_allows_a_mere_mention_that_builds_nothing(source):
    assert findings_in("publisher/base.py", source) == []


def test_the_bot_and_the_tests_may_build_one():
    source = f"x = {TAP}('r', 1, 'approve', 1, 'c')\n"
    assert findings_in("approval/telegram_bot.py", source) == []
    assert findings_in("tests/test_x.py", source) == []
    assert findings_in("approval/other.py", source)
    assert findings_in("approval/telegram_bot_extra.py", source)
