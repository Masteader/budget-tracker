"""The delete-account page's logic (web_app/src/lib/accountDeletion.ts), run with Node.

1. The typed word: the page folds it exactly as public.account_deletion_fold_confirmation does
   (supabase/migrations/20261105000800), so it never accepts what the server refuses or the
   reverse. The character lists are read from both files and compared, and the page's fold is
   checked against the SQL's five steps, re-done here from the SQL's own lists.
2. Cancel is offered whenever the status JSON's can_cancel is true, whatever the status.

web_app has no test runner, and the bundle is minified, so the module is run directly: Node 22.18
and later strip TypeScript types. Skipped without such a Node, never silently passed.
"""

from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import unicodedata

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / "web_app" / "src" / "lib" / "accountDeletion.ts"
SQL = ROOT / "supabase" / "migrations" / "20261105000800_account_deletion_operator_request.sql"


def _node() -> str:
    node = shutil.which("node")
    if node is None:
        pytest.skip("Node is not installed")
    version = subprocess.run([node, "--version"], capture_output=True, text=True).stdout.strip().lstrip("v")
    major, minor = (int(part) for part in version.split(".")[:2])
    if (major, minor) < (22, 18):
        pytest.skip(f"Node {version} cannot run TypeScript directly")
    return node


def _run(tmp_path: pathlib.Path, calls: list) -> list:
    runner = tmp_path / "run.mjs"
    runner.write_text(
        "import * as m from " + json.dumps(MODULE.as_uri()) + ";\n"
        "const calls = JSON.parse(process.argv[2]);\n"
        "console.log(JSON.stringify(calls.map(([fn, arg]) => m[fn](arg))));\n",
        encoding="utf-8",
    )
    proc = subprocess.run([_node(), str(runner), json.dumps(calls)], capture_output=True, text=True, encoding="utf-8")
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


# ── The SQL's fold, re-done from the SQL file ────────────────────────────────


def _sql_function() -> str:
    text = SQL.read_text(encoding="utf-8")
    start = text.index("CREATE OR REPLACE FUNCTION public.account_deletion_fold_confirmation(")
    return text[start:text.index("\n$$;\n", start)]


_SQL_ASCII_SPACE = {"\t", "\n", "\v", "\f", "\r", " "}  # PostgreSQL's \s in a bracket


def _class_chars(body: str, escape: str) -> set:
    """Characters of a bracket expression written with \\uXXXX escapes (and \\s, \\t...)."""
    chars: set = set()
    tokens = re.findall(r"\\u([0-9A-Fa-f]{4})(?:-\\u([0-9A-Fa-f]{4}))?|\\([stnvfr])|( )", body)
    for start, end, letter, space in tokens:
        if start:
            chars.update(chr(c) for c in range(int(start, 16), int(end or start, 16) + 1))
        elif letter == "s":
            chars.update(_SQL_ASCII_SPACE)
        elif letter:
            chars.add({"t": "\t", "n": "\n", "v": "\v", "f": "\f", "r": "\r"}[letter])
        elif space:
            chars.add(" ")
    assert re.sub(r"\\u[0-9A-Fa-f]{4}(?:-\\u[0-9A-Fa-f]{4})?|\\[stnvfr]| ", "", body) == "", (escape, body)
    return chars


def _sql_lists():
    fn = _sql_function()
    removed, spaced = re.findall(r"'\[([^\]]*)\]', '[^']*', 'g'\)", fn)
    src, dst = re.findall(r"U&'((?:\\[0-9A-Fa-f]{4})+)'", fn)
    letters = dict(zip(re.findall(r"\\([0-9A-Fa-f]{4})", src), re.findall(r"\\([0-9A-Fa-f]{4})", dst)))
    return (_class_chars(removed, "sql removed"), _class_chars(spaced, "sql spaces"),
            {chr(int(a, 16)): chr(int(b, 16)) for a, b in letters.items()})


def _ts_lists():
    ts = MODULE.read_text(encoding="utf-8")
    removed = re.search(r"const REMOVED = /\[([^\]]*)\]/g;", ts).group(1)
    spaced = re.search(r"const SPACES = /\[([^\]]*)\]/g;", ts).group(1)
    letters = dict(re.findall(r"'(.)': '(.)',", ts[ts.index("const LETTERS"):]))
    return _class_chars(removed, "ts removed"), _class_chars(spaced, "ts spaces"), letters


def _sql_fold(value: str) -> str:
    removed, spaced, letters = _sql_lists()
    out = unicodedata.normalize("NFC", value)
    out = "".join(c for c in out if c not in removed)
    out = "".join(" " if c in spaced else c for c in out)
    out = "".join(letters.get(c, c) for c in out)
    return re.sub(" {2,}", " ", out).strip(" ").lower()


def test_the_page_folds_with_exactly_the_servers_character_lists():
    assert _ts_lists() == _sql_lists()
    removed, spaced, letters = _sql_lists()
    # What the release review asked for, so neither file can drift on its own.
    assert {"\u00A0", "\u200E", "\u200F", "\u3000", "\u2028"} <= spaced
    assert {"\u200B", "\u200C", "\u200D", "\uFEFF", "\u202E", "\u2066"} <= removed
    assert letters == {"ک": "ك", "ی": "ي", "ں": "ن", "ى": "ي"}


URDU = "حذف کریں"  # as the app shows it
ACCEPTED = [
    "delete", " DELETE ", "DeLeTe", "\tdelete\n", "del\u200Bete", "\uFEFFdelete",
    "حذف",
    URDU,
    "حذف كرين",  # Arabic keyboard: kaf, yeh, noon
    "حذف كرىن",  # alef maksura
    "حذف\u00A0کریں",  # no-break space
    "\u200Fحذف\u200Fکریں\u200E",  # direction marks as spaces
    "حذف\u2003\u3000كرين",
    "حذف\u0085کریں",
    "حذف \u202Bکریں\u202C",  # an embedding, dropped
]
REFUSED = [
    "", "   ", "\u200B", "delet", "remove", "delete delete", "حذ",
    "حذفكرين",  # no space
    "حذف\u200Cکریں",  # a non-joiner is dropped, not a space
    "حذف كرين x",
]


def test_the_page_accepts_exactly_what_the_server_accepts(tmp_path):
    words = ACCEPTED + REFUSED
    results = _run(tmp_path, [["foldConfirmation", w] for w in words] + [["isAcceptedConfirmation", w] for w in words])
    folded, accepted = results[:len(words)], results[len(words):]
    assert folded == [_sql_fold(w) for w in words]
    server_words = {_sql_fold(w) for w in ("delete", "حذف", URDU)}
    assert accepted == [_sql_fold(w) in server_words for w in words]
    assert accepted == [True] * len(ACCEPTED) + [False] * len(REFUSED)


@pytest.mark.parametrize("status, can_cancel, view, cancel", [
    ("none", False, "schedule", False),
    ("scheduled", True, "pending", True),
    ("processing", True, "starting", True),
    ("failed", True, "stopped", True),
    ("processing", False, "inProgress", False),
    ("failed", False, "stoppedPartway", False),
    ("scheduled", False, "inProgress", False),
])
def test_cancel_is_offered_whenever_the_server_says_can_cancel(tmp_path, status, can_cancel, view, cancel):
    got_view, = _run(tmp_path, [["deletionView", {"status": status, "can_cancel": can_cancel}]])
    got_cancel, = _run(tmp_path, [["offersCancel", got_view]])
    assert (got_view, got_cancel) == (view, cancel)
