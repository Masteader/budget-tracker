"""The translation review file matches the sources, and is safe to hand to a reviewer."""

from __future__ import annotations

import csv
import importlib.util
import io
import pathlib
import re
import shutil

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools" / "translation_review" / "generate_account_deletion_review.py"

pytestmark = pytest.mark.skipif(
    not GENERATOR.exists()
    or not (ROOT / "web_app" / "node_modules" / "typescript").exists()
    or shutil.which("node") is None
    or not (ROOT / ".git").exists(),
    reason="needs the repository, its history, node and web_app/node_modules",
)


def _generator():
    spec = importlib.util.spec_from_file_location("generate_account_deletion_review", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def gen():
    return _generator()


@pytest.fixture(scope="module")
def rows(gen):
    return gen.build_rows()


def test_the_committed_file_matches_the_sources_and_the_counts(gen, rows):
    assert gen.check(rows) == []


def test_it_opens_in_excel_as_utf8_with_the_agreed_columns(gen):
    raw = gen.OUTPUT.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf")
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig").replace("\r\n", "\n")))
    assert reader.fieldnames == ["key", "where_it_appears", "english", "arabic", "urdu", "reviewer_notes"]
    assert all(row["reviewer_notes"] == "" for row in reader)


def test_every_surface_and_the_terms_that_must_stay_are_there(rows):
    by_key = {row["key"]: row for row in rows}
    assert {row["where_it_appears"] for row in rows} == {"app", "web", "email"}
    assert by_key["deleted_member"]["english"] == "Deleted member"
    assert by_key["email.holder_t7.subject"]["urdu"]
    assert any(key.startswith("web.delete_account.") for key in by_key)
    assert any(key.startswith("web.landing.") for key in by_key)
    assert any(key.startswith("del_") for key in by_key)


def _plural_form(key):
    """Languages have different plural forms: Arabic has zero, two, few and many, English does not."""
    return key.rsplit(".", 1)[-1] in {"zero", "one", "two", "few", "many"} and not key.startswith(("web.", "email."))


def test_english_and_arabic_are_never_blank(rows):
    blank = [r["key"] for r in rows if not _plural_form(r["key"]) and (not r["english"].strip() or not r["arabic"].strip())]
    assert blank == []


def test_urdu_is_blank_only_on_the_landing_page_which_has_no_urdu(rows):
    missing = [r["key"] for r in rows if not _plural_form(r["key"]) and not r["urdu"].strip()]
    assert [key for key in missing if not key.startswith("web.landing.")] == []


def test_placeholders_match_across_the_languages(rows):
    def placeholders(text):
        return sorted(re.findall(r"\{[a-zA-Z_]+\}", text))

    for row in rows:
        if _plural_form(row["key"]):
            continue  # "one" and "two" often say the number in words
        expected = placeholders(row["english"])
        assert placeholders(row["arabic"]) == expected, row["key"]
        if row["urdu"]:
            assert placeholders(row["urdu"]) == expected, row["key"]


def test_the_dart_reader_handles_what_the_sources_contain(gen):
    text = """
      static const _localizedValues = <String, Map<String, String>>{
        'en': {
          // A comment with a 'quote'
          'a': 'one\\'s \\n two',
          'b': 'first '
              'second',
          'c': "double 'quoted'",
        },
      };
      static const Map<String, Map<String, Map<String, String>>> _pluralValues = {
        'p': {'en': {'one': '{n} item', 'other': '{n} items'}},
      };
    """
    values, plurals = gen.parse_app(text)
    assert values["en"] == {"a": "one's \n two", "b": "first second", "c": "double 'quoted'"}
    assert plurals["p"]["en"]["other"] == "{n} items"
