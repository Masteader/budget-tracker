#!/usr/bin/env python3
"""
Generates docs/review/account_deletion_translation_review.csv from the sources, for a native reviewer.

    python tools/translation_review/generate_account_deletion_review.py          # writes the file
    python tools/translation_review/generate_account_deletion_review.py --check  # fails if it is stale

Never edit the CSV by hand: a reviewer's answers go in their own copy, and approved changes go in the
sources. Needs git history and web_app/node_modules (for the TypeScript compiler).

What is in it:
  app    del_* and deleted_member, and every key added to the app dictionaries since BASE_APP
         (the settle and settings work).
  web    all of deleteAccountTranslations, and landing page strings new since BASE_WEB (privacy).
  email  every template in ai_service/account_deletion_notices.py.
"""

from __future__ import annotations

import argparse
import ast
import csv
import io
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterator, List, Tuple

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs" / "review" / "account_deletion_translation_review.csv"
DART = "flutter_app/lib/l10n/app_localizations.dart"
TS = "web_app/src/i18n/translations.ts"
NOTICES = "ai_service/account_deletion_notices.py"
BASE_APP = "7eb1550"
# main as merged into the release (db33356): its own new strings (the portal Budgets view) are
# not part of this review. Before that merge this was the branch point, 1a1ddb7.
BASE_WEB = "db33356"
COLUMNS = ["key", "where_it_appears", "english", "arabic", "urdu", "reviewer_notes"]
LANGUAGES = ("en", "ar", "ur")

# Settings the code reads, not words anyone sees.
WEB_MACHINE_KEYS = {"dateLocale", "dir", "deleteAccountHref"}

Row = Dict[str, str]


# ── Dart map literals ───────────────────────────────────────────────────────


class _DartMap:
    """Reads a Dart map literal of string keys, with string or nested map values."""

    _ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "'": "'", '"': '"', "$": "$"}

    def __init__(self, text: str, start: int):
        self.text = text
        self.i = start

    def _skip(self) -> None:
        while self.i < len(self.text):
            ch = self.text[self.i]
            if ch.isspace() or ch == ",":
                self.i += 1
            elif self.text.startswith("//", self.i):
                self.i = self.text.index("\n", self.i)
            else:
                return

    def _one_string(self) -> str:
        raw = self.text[self.i] == "r"
        if raw:
            self.i += 1
        quote = self.text[self.i]
        self.i += 1
        out = []
        while self.text[self.i] != quote:
            ch = self.text[self.i]
            if ch == "\\" and not raw:
                self.i += 1
                esc = self.text[self.i]
                if esc == "u":
                    out.append(chr(int(self.text[self.i + 1:self.i + 5], 16)))
                    self.i += 4
                else:
                    out.append(self._ESCAPES.get(esc, esc))
            else:
                out.append(ch)
            self.i += 1
        self.i += 1
        return "".join(out)

    def _string(self) -> str:
        parts = [self._one_string()]
        while True:
            self._skip_space()
            if self.text[self.i] in "'\"" or (self.text[self.i] == "r" and self.text[self.i + 1] in "'\""):
                parts.append(self._one_string())
            else:
                return "".join(parts)

    def _skip_space(self) -> None:
        while self.text[self.i].isspace() or self.text.startswith("//", self.i):
            if self.text.startswith("//", self.i):
                self.i = self.text.index("\n", self.i)
            else:
                self.i += 1

    def read(self) -> Dict[str, Any]:
        assert self.text[self.i] == "{", self.text[self.i:self.i + 40]
        self.i += 1
        out: Dict[str, Any] = {}
        while True:
            self._skip()
            if self.text[self.i] == "}":
                self.i += 1
                return out
            key = self._string()
            self._skip_space()
            assert self.text[self.i] == ":", self.text[self.i - 40:self.i + 10]
            self.i += 1
            self._skip_space()
            out[key] = self.read() if self.text[self.i] == "{" else self._string()


def _dart_map(text: str, marker: str) -> Dict[str, Any]:
    start = text.index(marker)
    return _DartMap(text, text.index("{", start + len(marker))).read()


def parse_app(text: str) -> Tuple[Dict[str, Dict[str, str]], Dict[str, Dict[str, Dict[str, str]]]]:
    """(language -> key -> text, key -> language -> plural form -> text)"""
    return (
        _dart_map(text, "static const _localizedValues = <String, Map<String, String>>"),
        _dart_map(text, "static const Map<String, Map<String, Map<String, String>>> _pluralValues ="),
    )


def _git_show(ref: str, path: str) -> str:
    return subprocess.run(["git", "show", f"{ref}:{path}"], cwd=ROOT, capture_output=True, check=True,
                          ).stdout.decode("utf-8")


def _row(key: str, where: str, en: str, ar: str, ur: str) -> Row:
    return {"key": key, "where_it_appears": where, "english": en, "arabic": ar, "urdu": ur, "reviewer_notes": ""}


def app_rows(current: str, base: str) -> List[Row]:
    values, plurals = parse_app(current)
    base_values, base_plurals = parse_app(base)
    known = set().union(*(set(base_values[lang]) for lang in LANGUAGES))
    keys = [
        key for key in values["en"]
        if key.startswith("del_") or key == "deleted_member" or key not in known
    ]
    rows = [_row(key, "app", values["en"].get(key, ""), values["ar"].get(key, ""), values["ur"].get(key, "")) for key in keys]
    for key, by_language in plurals.items():
        if key.startswith("del_") or key not in base_plurals:
            forms = list(dict.fromkeys(form for lang in LANGUAGES for form in by_language.get(lang, {})))
            for form in forms:
                rows.append(_row(f"{key}.{form}", "app", *(by_language.get(lang, {}).get(form, "") for lang in LANGUAGES)))
    return rows


# ── Web dictionaries ────────────────────────────────────────────────────────


def _dump_ts(text: str) -> Dict[str, Any]:
    with tempfile.TemporaryDirectory() as scratch:
        path = os.path.join(scratch, "translations.ts")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        out = subprocess.run(["node", str(Path(__file__).parent / "dump_translations.cjs"), path],
                             capture_output=True, check=True)
    return json.loads(out.stdout.decode("utf-8"))


def _leaves(node: Any, path: str = "") -> Iterator[Tuple[str, str]]:
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for key, value in node.items():
            if key not in WEB_MACHINE_KEYS:
                yield from _leaves(value, f"{path}.{key}" if path else key)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _leaves(value, f"{path}.{index}")


def web_rows(current: str, base: str) -> List[Row]:
    now = _dump_ts(current)
    before = _dump_ts(base)

    deletion = {lang: dict(_leaves(now["deleteAccountTranslations"][lang])) for lang in LANGUAGES}
    paths = list(dict.fromkeys(path for lang in LANGUAGES for path in deletion[lang]))
    rows = [_row(f"web.delete_account.{path}", "web", *(deletion[lang].get(path, "") for lang in LANGUAGES)) for path in paths]

    # Landing page: a leaf is new when its text was nowhere in that language before. Items added
    # to a list move the ones after them, so a path alone would call those new too.
    landing = {lang: dict(_leaves(now["translations"][lang])) for lang in ("en", "ar")}
    old = {lang: set(dict(_leaves(before["translations"][lang])).values()) for lang in ("en", "ar")}
    for path in landing["en"]:
        en, ar = landing["en"][path], landing["ar"].get(path, "")
        if en not in old["en"] or ar not in old["ar"]:
            rows.append(_row(f"web.landing.{path}", "web", en, ar, ""))
    return rows


# ── Emails ──────────────────────────────────────────────────────────────────


def _templates(text: str) -> Dict[str, Dict[str, Tuple[str, str]]]:
    for node in ast.parse(text).body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "_TEMPLATES":
            return ast.literal_eval(node.value)
    raise ValueError("no _TEMPLATES in the notices file")


def email_rows(text: str) -> List[Row]:
    rows = []
    for notice, languages in _templates(text).items():
        for index, part in enumerate(("subject", "body")):
            rows.append(_row(f"email.{notice}.{part}", "email", *(languages[lang][index] for lang in LANGUAGES)))
    return rows


# ── The file ────────────────────────────────────────────────────────────────


def build_rows() -> List[Row]:
    return (
        app_rows((ROOT / DART).read_text(encoding="utf-8"), _git_show(BASE_APP, DART))
        + web_rows((ROOT / TS).read_text(encoding="utf-8"), _git_show(BASE_WEB, TS))
        + email_rows((ROOT / NOTICES).read_text(encoding="utf-8"))
    )


def render(rows: List[Row]) -> str:
    # The BOM makes Excel read this as UTF-8. Line ends are LF, so git and the check agree.
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=COLUMNS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return "﻿" + buffer.getvalue()


def source_counts() -> Dict[str, int]:
    """What the sources hold, counted without the parsers above, to catch a parser that drops rows."""
    dart = (ROOT / DART).read_text(encoding="utf-8")
    english = dart[dart.index("    'en': {"):dart.index("    'ar': {")]
    templates = (ROOT / NOTICES).read_text(encoding="utf-8")
    ts = (ROOT / TS).read_text(encoding="utf-8")
    english_web = ts[ts.index("export const deleteAccountTranslations"):]
    return {
        "app del_ and deleted_member": len(re.findall(r"^\s*'(?:del_\w+|deleted_member)'\s*:", english, re.M)),
        "email parts": 2 * len(re.findall(r'^    "(?:holder|member|creditor)_\w+": \{$', templates, re.M)),
        "web date settings": len(re.findall(r"^\s*dateLocale:", english_web, re.M)),
    }


def check(rows: List[Row]) -> List[str]:
    problems = []
    counts = source_counts()
    app_core = sum(1 for r in rows if r["where_it_appears"] == "app" and (r["key"].startswith("del_") or r["key"] == "deleted_member"))
    if app_core != counts["app del_ and deleted_member"]:
        problems.append(f"app del_ rows {app_core}, source has {counts['app del_ and deleted_member']}")
    emails = sum(1 for r in rows if r["where_it_appears"] == "email")
    if emails != counts["email parts"]:
        problems.append(f"email rows {emails}, source has {counts['email parts']}")
    if counts["web date settings"] != 3:
        problems.append("expected dateLocale in 3 web languages")
    if len({r["key"] for r in rows}) != len(rows):
        problems.append("duplicate keys")
    if not OUTPUT.exists():
        problems.append(f"{OUTPUT} is missing")
    else:
        on_disk = OUTPUT.read_bytes().decode("utf-8").replace("\r\n", "\n")
        if on_disk != render(rows):
            problems.append(f"{OUTPUT.name} is stale: regenerate it")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="Fail if the file does not match the sources.")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    rows = build_rows()
    summary = {where: sum(1 for r in rows if r["where_it_appears"] == where) for where in ("app", "web", "email")}
    if args.check:
        problems = check(rows)
        print(f"rows: {len(rows)} {summary}")
        for problem in problems:
            print("PROBLEM:", problem)
        return 1 if problems else 0
    OUTPUT.write_bytes(render(rows).encode("utf-8"))
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {len(rows)} rows {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
