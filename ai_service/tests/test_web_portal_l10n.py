"""Portal copy comes from web_app/src/i18n/translations.ts, not from inline per-language literals.

Scoped to the portal components already moved to the dictionary. DashboardView.tsx,
NewTransactionModal.tsx and TransactionsView.tsx still carry inline `lang === 'ar' ? '…' : '…'`
copy; add each one to `_CLEAN_COMPONENTS` once its strings are moved.

Accepted limit: English-only hardcoded text is not caught yet. A TypeScript-AST guard
covering every portal page is planned with the remaining portal copy cleanup.
"""

import pathlib
import re

import pytest

PORTAL = pathlib.Path(__file__).resolve().parents[2] / "web_app" / "src" / "components" / "portal"
_CLEAN_COMPONENTS = ("BudgetsView.tsx",)

# `lang === 'ar'` (or !==, or 'en') choosing between values, where one branch is a string literal.
_LANG_TERNARY_LITERAL = re.compile(
    r"""\blang\s*[!=]==?\s*['"](?:ar|en)['"]\s*\?\s*(?:['"`]|[^:;]*?:\s*['"`])""",
    re.DOTALL,
)
_ARABIC_LETTER = re.compile("[؀-ۿ]")
_COMMENTS = re.compile(r"\{?/\*.*?\*/\}?|(?<![:'\"`])//[^\n]*", re.DOTALL)


def _inline_copy(source: str) -> list[str]:
    """Inline per-language literals, and Arabic text outside comments, in a TSX source."""
    code = _COMMENTS.sub("", source)
    found = [m.group(0) for m in _LANG_TERNARY_LITERAL.finditer(code)]
    found += [line.strip() for line in code.splitlines() if _ARABIC_LETTER.search(line)]
    return found


@pytest.mark.parametrize(
    "snippet",
    [
        "{lang === 'ar' ? 'بنود الميزانية المعتمدة' : 'Approved Budget Categories'}",
        "name: lang === 'ar' ? 'البقالة والتموين' : 'Groceries & Staples',",
        "{lang === 'ar'\n  ? 'مخصص'\n  : 'Monthly approved'}",
        '{lang !== "en" ? x : "Monthly approved"}',
        "<div>1,200.00 ر.س</div>",
    ],
)
def test_the_guard_catches_inline_copy(snippet):
    assert _inline_copy(snippet)


@pytest.mark.parametrize(
    "snippet",
    [
        "{dict.portal.approvedCategoriesTitle}",
        "{/* Wife's Personal Allowance Card (مصروف الزوجة) */}",
        "// مصروف الزوجة",
        "const other = lang === 'ar' ? en : ar;",
    ],
)
def test_the_guard_spares_dictionary_lookups_and_comments(snippet):
    assert _inline_copy(snippet) == []


@pytest.mark.parametrize("name", _CLEAN_COMPONENTS)
def test_portal_component_takes_its_copy_from_the_dictionary(name):
    source = (PORTAL / name).read_text(encoding="utf-8")
    assert _inline_copy(source) == [], name
