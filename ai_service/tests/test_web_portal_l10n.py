"""Portal copy comes from web_app/src/i18n/translations.ts, not from hardcoded text in any language.

Scoped to the portal components already moved to the dictionary. DashboardView.tsx,
NewTransactionModal.tsx, TransactionsView.tsx and PortalHeader.tsx still carry hardcoded copy;
add each one to `_CLEAN_COMPONENTS` once its strings are moved.

The guard reads a component with a small TSX scanner (not a regex), because JSX text and code
quote differently: an apostrophe in JSX text is not a string delimiter. It reports:

1. JSX text with a letter in any script (`<h3>Approved</h3>`, `{x} total`);
2. a string literal that is a whole JSX child (`{'Approved'}`);
3. a literal given to a copy attribute (`title`, `alt`, `placeholder`, `aria-label`, ...) or a
   copy property (`name:`, `label:`, `title:`, `placeholder:`, ...) unless it is a code value;
4. a ternary choosing between two literals, unless both are class lists, ids or locale codes;
5. any other literal that reads as copy: Arabic script, a capitalised word, two or more plain
   words, or a value of translations.ts.

Code literals stay legal: imports, class lists, ids such as `OPEX-GROCERY`, table and column
names, locale codes, SVG attributes and template literals that only hold class names or numbers.
"""

import functools
import pathlib
import re
from dataclasses import dataclass

import pytest

PORTAL = pathlib.Path(__file__).resolve().parents[2] / "web_app" / "src" / "components" / "portal"
_CLEAN_COMPONENTS = ("BudgetsView.tsx",)

_ARABIC = re.compile("[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")
_LETTER = re.compile("[A-Za-z؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")
# A capitalised word that starts a word: "Approved", "Me". Not "currentColor", "OPEX", "en-US".
_TITLE_WORD = re.compile(r"(?<![A-Za-z0-9_-])[A-Z][a-z]+")
_PLAIN_WORD = re.compile(r"[A-Za-z]+[.,:;!?]?|&")
# One token of a class list, an id/column list, a locale code or a constant id.
_CODE_TOKEN = re.compile(
    r"[a-z0-9!-][a-z0-9:/.\[\]%#_()!,-]*"  # bg-rose-100, min-w-[260px], cycle_key,
    r"|[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})+"  # ar-SA, en-US
    r"|[A-Z0-9][A-Z0-9_-]*"  # OPEX-GROCERY
)
_COPY_ATTRS = frozenset(
    {"title", "alt", "placeholder", "label", "aria-label", "aria-description",
     "aria-placeholder", "aria-roledescription", "aria-valuetext"}
)
_COPY_PROPS = frozenset(
    {"name", "label", "title", "placeholder", "description", "desc", "message", "text",
     "subtitle", "caption", "tooltip", "hint", "heading"}
)


@dataclass
class _Literal:
    start: int
    end: int
    value: str  # a template literal's text parts, joined by a space
    attr: str | None = None  # the JSX attribute this literal is the whole value of
    child: bool = False  # the literal is a whole JSX child expression


class _TsxScanner:
    """Splits a TSX source into string literals and JSX text nodes, comments skipped."""

    def __init__(self, source: str):
        self.s, self.n = source, len(source)
        self.literals: list[_Literal] = []
        self.texts: list[tuple[int, str]] = []
        self._code(0, None)

    def _skip_ws(self, i: int) -> int:
        while i < self.n and self.s[i].isspace():
            i += 1
        return i

    def _code(self, i: int, closer: str | None) -> int:
        stack: list[str] = []
        while i < self.n:
            c = self.s[i]
            if self.s.startswith("//", i):
                end = self.s.find("\n", i)
                i = self.n if end < 0 else end
            elif self.s.startswith("/*", i):
                i = self.s.index("*/", i + 2) + 2
            elif c in "'\"":
                i = self._string(i)
            elif c == "`":
                i = self._template(i)
            elif c in "([{":
                stack.append(c)
                i += 1
            elif c in ")]}":
                if not stack:
                    if c == closer:
                        return i + 1
                    raise ValueError(f"unbalanced {c!r} at {i}")
                stack.pop()
                i += 1
            elif c == "<" and self._jsx_starts(i):
                i = self._element(i)
            else:
                i += 1
        if closer:
            raise ValueError(f"missing {closer!r}")
        return i

    def _jsx_starts(self, i: int) -> bool:
        nxt = self.s[i + 1 : i + 2]
        if not (nxt.isalpha() or nxt == ">"):
            return False  # `a < b`
        before = self.s[:i].rstrip()
        if not before or re.search(r"\breturn$", before):
            return True
        # After an identifier or `)` it is a generic or a comparison: useState<T>(), FC<Props>.
        return before[-1] in "(,=:?{[!&|;" or before.endswith("=>")

    def _string(self, i: int) -> int:
        quote, j, out = self.s[i], i + 1, []
        while self.s[j] != quote:
            if self.s[j] in "\r\n":
                raise ValueError(f"line break in a string at {i}")
            if self.s[j] == "\\":
                out.append(self.s[j + 1])
                j += 2
            else:
                out.append(self.s[j])
                j += 1
        self.literals.append(_Literal(i, j + 1, "".join(out)))
        return j + 1

    def _template(self, i: int) -> int:
        j, parts, current = i + 1, [], []
        while self.s[j] != "`":
            if self.s[j] == "\\":
                current.append(self.s[j + 1])
                j += 2
            elif self.s.startswith("${", j):
                parts.append("".join(current))
                current = []
                j = self._code(j + 2, "}")
            else:
                current.append(self.s[j])
                j += 1
        parts.append("".join(current))
        self.literals.append(_Literal(i, j + 1, " ".join(parts)))
        return j + 1

    def _expression(self, j: int) -> tuple[int, _Literal | None]:
        """Scan `{…}` from its `{`; return the end and the literal if it is the whole expression."""
        first = len(self.literals)
        end = self._code(j + 1, "}")
        inner = self.s[j + 1 : end - 1].strip()
        lits = self.literals[first:]
        if len(lits) == 1 and inner == self.s[lits[0].start : lits[0].end]:
            return end, lits[0]
        return end, None

    def _element(self, i: int) -> int:
        j = i + 1
        if self.s[j] == ">":
            return self._children(j + 1)
        name = re.match(r"[A-Za-z][\w.:-]*", self.s[j:]).group(0)
        j += len(name)
        while True:
            j = self._skip_ws(j)
            if self.s.startswith("/>", j):
                return j + 2
            if self.s[j] == ">":
                return self._children(j + 1)
            if self.s[j] == "{":  # {...spread}
                j, _ = self._expression(j)
                continue
            attr = re.match(r"[\w:.-]+", self.s[j:]).group(0)
            j = self._skip_ws(j + len(attr))
            if self.s[j] != "=":
                continue  # a boolean attribute
            j = self._skip_ws(j + 1)
            if self.s[j] in "'\"":  # JSX attribute strings have no escapes
                end = self.s.index(self.s[j], j + 1)
                self.literals.append(_Literal(j, end + 1, self.s[j + 1 : end], attr=attr))
                j = end + 1
            else:
                j, literal = self._expression(j)
                if literal:
                    literal.attr = attr

    def _children(self, j: int) -> int:
        while True:
            if self.s.startswith("</", j):
                return self.s.index(">", j) + 1
            if self.s[j] == "<":
                j = self._element(j)
            elif self.s[j] == "{":
                j, literal = self._expression(j)
                if literal:
                    literal.child = True
            else:
                end = min(k for k in (self.s.find("<", j), self.s.find("{", j), self.n) if k >= 0)
                self.texts.append((j, self.s[j:end]))
                j = end


# The app's `Language` codes (web_app/src/i18n/translations.ts) plus Urdu, used to switch language.
_LANGUAGE_CODES = frozenset({"ar", "en", "ur"})


def _code_like(value: str) -> bool:
    """A class list, id or column list, locale code or constant: not something a reader sees."""
    if value in _LANGUAGE_CODES:
        return True
    tokens = value.split()
    return (
        bool(tokens)
        and all(_CODE_TOKEN.fullmatch(t) for t in tokens)
        and any(re.search(r"[-_:/\[\d]", t) for t in tokens)
    )


@functools.cache
def _translation_copy() -> frozenset[str]:
    from test_landing_page import _translation_values

    # Values that are copy, not codes: 'calendar', 'neutral' and 'ar-SA-u-…' are left out.
    return frozenset(v for v in _translation_values() if len(v) >= 4 and not re.fullmatch(r"[a-z][\w-]*", v))


def _reads_as_copy(value: str, *, plain_words: bool = True) -> bool:
    if _ARABIC.search(value) or _TITLE_WORD.search(value) or value.strip() in _translation_copy():
        return True
    tokens = value.split()
    return plain_words and len(tokens) >= 2 and all(_PLAIN_WORD.fullmatch(t) for t in tokens)


def _hardcoded_copy(source: str) -> list[str]:
    """Hardcoded user-facing text in a TSX source, each as `line N: what`."""
    scan = _TsxScanner(source)
    found: list[tuple[int, str]] = []

    for at, text in scan.texts:
        if _LETTER.search(text):
            found.append((at, f"JSX text {text.strip()!r}"))

    for lit in scan.literals:
        before = source[: lit.start].rstrip()
        if re.search(r"\b(?:from|import)$|\bimport\($", before):
            continue
        if before.endswith(("===", "!==")):
            continue  # compared against, never shown: e.key === 'Escape'
        has_letter = bool(_LETTER.search(lit.value))
        if lit.attr is not None:
            copy = has_letter if lit.attr in _COPY_ATTRS else _reads_as_copy(lit.value, plain_words=False)
            if copy:
                found.append((lit.start, f"{lit.attr}={lit.value!r}"))
            continue
        if lit.child:
            if has_letter:
                found.append((lit.start, f"JSX child {lit.value!r}"))
            continue
        prop = re.search(r"([A-Za-z_$][\w$]*)\s*:$", before)
        if prop and prop.group(1) in _COPY_PROPS and has_letter and not _code_like(lit.value):
            found.append((lit.start, f"{prop.group(1)}: {lit.value!r}"))
        elif _reads_as_copy(lit.value):
            found.append((lit.start, f"literal {lit.value!r}"))

    ordered = sorted(scan.literals, key=lambda lit: lit.start)  # a template follows its `${…}`
    for a, b in zip(ordered, ordered[1:]):
        if (
            source[: a.start].rstrip().endswith("?")
            and re.fullmatch(r"\s*:\s*", source[a.end : b.start])
            and not (_code_like(a.value) and _code_like(b.value))
        ):
            found.append((a.start, f"ternary {a.value!r} : {b.value!r}"))

    return [f"line {source.count(chr(10), 0, at) + 1}: {what}" for at, what in sorted(set(found))]


# ── Self-tests: the guard catches hardcoded copy in the real BudgetsView.tsx ───────────────────

_BUDGETS_VIEW = PORTAL / "BudgetsView.tsx"
_TITLE_EXPR = "{dict.portal.approvedCategoriesTitle}"
_GROCERY = "name: names.grocery"


@pytest.mark.parametrize(
    ("old", "new"),
    [
        # The five mutations from review Round 1.
        (_TITLE_EXPR, "Approved Budget Categories"),
        (_TITLE_EXPR, "{'Approved Budget Categories'}"),
        (_GROCERY, "name: 'Groceries & Staples'"),
        (_TITLE_EXPR, "{isAr ? 'Approved' : 'Approved Budget Categories'}"),
        (_TITLE_EXPR, "{dict === translations.ar ? 'x' : 'Approved'}"),
        # More shapes of the same thing.
        (_TITLE_EXPR, "{dict.portal.approvedCategoriesTitle} total"),
        (_TITLE_EXPR, "approved budget categories"),
        (_TITLE_EXPR, "بنود الميزانية المعتمدة"),
        (_TITLE_EXPR, "{'approved'}"),
        (_TITLE_EXPR, '{"Wife\'s allowance"}'),
        (_TITLE_EXPR, "{`${budgets.length} categories`}"),
        (_TITLE_EXPR, "{lang === 'ar' ? 'بنود' : 'Items'}"),
        (_TITLE_EXPR, "{isAr ? 'paid' : 'due'}"),
        (_TITLE_EXPR, "{label('approved budget')}"),
        (_GROCERY, "name: 'groceries'"),
        (_GROCERY, "label: 'groceries'"),
        (_GROCERY, "name: 'البقالة والتموين'"),
        ('className="space-y-8"', 'className="space-y-8" title="Budgets"'),
        ('className="space-y-8"', "className=\"space-y-8\" aria-label={'budgets'}"),
        ('className="space-y-8"', 'className="space-y-8" placeholder="search"'),
        ('className="space-y-8"', 'className="space-y-8" alt="chart"'),
    ],
)
def test_the_guard_catches_hardcoded_copy_in_budgets_view(old, new):
    source = _BUDGETS_VIEW.read_text(encoding="utf-8")
    assert source.count(old) >= 1, old
    assert _hardcoded_copy(source.replace(old, new, 1)), new


@pytest.mark.parametrize(
    "snippet",
    [
        "import { formatSAR } from '../../lib/cycleUtils';",
        "import type { TranslationDictionary } from '../../i18n/translations';",
        "const x = useState<BudgetCategory[]>([]); const y = a < b && c > d;",
        "const c = { code: 'OPEX-GROCERY', name: names.grocery, allocated: 3500 };",
        "supabase.from('budgets').select('category_code, amount, cycle_key').eq('household_id', id);",
        "t.nafaqah_class === 'wife_personal'",
        "const when = d.toLocaleDateString(lang === 'ar' ? 'ar-SA' : 'en-US');",
        "<div className=\"rounded-3xl bg-white border border-line p-6 shadow-sm\" key={b.code} />",
        "<span className={`text-xs ${bad ? 'bg-rose-100 text-rose-800' : 'bg-teal-soft text-teal-dark'}`} />",
        "<div style={{ width: `${percent}%` }} />",
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">'
        '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87z" /></svg>',
        "<p>{dict.portal.spent}: <strong>{formatSAR(b.spent)}</strong></p>",
        "<span>{percent}%</span>",
        "<div>{formatSAR(1200)}</div>",
        "<div>{/* Wife's Personal Allowance Card (مصروف الزوجة) */}</div>",
        "// Approved Budget Categories (مصروف الزوجة)",
        "/* Groceries & Staples */",
        "<input type=\"text\" id=\"budget-search\" name=\"query\" placeholder={dict.portal.searchPlaceholder} />",
        "if (e.key === 'Escape') onClose(); if (tx.status !== 'Paid Out') skip();",
        "const other: Language = lang === 'ar' ? 'en' : 'ar';",
    ],
)
def test_the_guard_spares_code_literals_and_dictionary_lookups(snippet):
    assert _hardcoded_copy(snippet) == []


def test_the_scanner_reads_the_whole_component():
    scan = _TsxScanner(_BUDGETS_VIEW.read_text(encoding="utf-8"))
    attrs = {lit.attr for lit in scan.literals if lit.attr}
    assert {"className", "viewBox", "d"} <= attrs
    assert len(scan.texts) > 20  # whitespace and ':' between the elements


@pytest.mark.parametrize("name", _CLEAN_COMPONENTS)
def test_portal_component_takes_its_copy_from_the_dictionary(name):
    assert _hardcoded_copy((PORTAL / name).read_text(encoding="utf-8")) == [], name
