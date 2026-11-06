"""Portal copy comes from web_app/src/i18n/translations.ts, not from hardcoded text in any language.

Scoped to the portal components already moved to the dictionary. DashboardView.tsx,
NewTransactionModal.tsx, TransactionsView.tsx and PortalHeader.tsx still carry hardcoded copy;
add each one to `_CLEAN_COMPONENTS` once its strings are moved.

The guard reads a component with a small TSX scanner (not a regex), because JSX text and code
quote differently: an apostrophe in JSX text is not a string delimiter. Each string literal gets
the context it sits in: a JSX child `{…}`, a JSX attribute, a class or query-builder call, or
plain code. Text counts as copy where it is shown:

1. JSX text with a letter in any script (`<h3>Approved</h3>`, `{x} total`);
2. a literal that is the whole of a JSX child or of a copy attribute (`{'Approved'}`,
   `title="…"`, `subtitle={'…'}`), when it has a letter;
3. a literal a JSX child, a copy attribute or a copy property (`name:`, `label:`, …) renders
   directly, through `? :`, `&&`, `||`, `??` or `+` (`{isAr ? 'paid' : 'due'}`), unless it is a
   code value such as a class list, an id or a language code;
4. elsewhere in a JSX child or copy attribute, two or more plain words (`{label('two words')}`);
5. anywhere, a literal with a strong sign of copy: Arabic or Urdu script, a capitalised word,
   or a value of translations.ts (`const t = 'Approved'`, `['Grocery', 'Fuel']`).

Not copy: imports, values compared with `===`/`!==`, empty strings, arguments of class helpers
(`cn`, `clsx`) and of query-builder calls (`.select`, `.eq`, `.order`, …), and literals inside
code attributes (`className`, `dir`, `type`, `key`, `id`, `role`, …) without a strong sign.
"""

import functools
import pathlib
import re
from dataclasses import dataclass

import pytest

PORTAL = pathlib.Path(__file__).resolve().parents[2] / "web_app" / "src" / "components" / "portal"
_CLEAN_COMPONENTS = ("BudgetsView.tsx",)

# Arabic script, which Urdu also uses (ٹ ڈ ڑ ں ہ ے are in these blocks).
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
# The app's `Language` codes (web_app/src/i18n/translations.ts) plus Urdu, used to switch language.
_LANGUAGE_CODES = frozenset({"ar", "en", "ur"})

_COPY_WORDS = frozenset(
    {"title", "label", "placeholder", "description", "desc", "message", "text", "subtitle",
     "caption", "tooltip", "hint", "heading", "emptyText", "helperText", "errorText"}
)
# `name` is copy as an object property (a category's name) but not as a JSX attribute, where it
# is a form field's name (<input name="query">).
_COPY_ATTRS = _COPY_WORDS | {"alt", "aria-label", "aria-description", "aria-placeholder",
                             "aria-roledescription", "aria-valuetext"}
_COPY_PROPS = _COPY_WORDS | {"name"}
# Calls whose string arguments are class names or database names, never shown.
_CLASS_CALLS = frozenset({"cn", "clsx", "classNames", "twMerge", "cva"})
_QUERY_CALLS = frozenset(
    {"from", "select", "eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike", "is", "in",
     "contains", "containedBy", "order", "range", "limit", "match", "not", "or", "filter", "rpc"}
)
_KEYWORDS = frozenset(
    {"return", "typeof", "case", "in", "of", "await", "yield", "void", "delete", "throw", "new",
     "else", "do"}
)


class TsxSyntaxError(ValueError):
    """The scanner met syntax it does not read; the message names the line."""


@dataclass
class _Literal:
    start: int
    end: int
    value: str  # a template literal's text parts, joined by a space
    context: tuple[str, str | None, int]  # ("code" | "child" | "attr" | "call", name, `{`/`(` index)
    attr: str | None = None  # the JSX attribute this literal is the whole value of
    child: bool = False  # the literal is a whole JSX child expression


class _TsxScanner:
    """Splits a TSX source into string literals and JSX text nodes, comments skipped.

    `masked` is the source with the inside of every literal, regex, comment and JSX text
    blanked, so brackets and colons there cannot mislead a walk back through the code.
    """

    def __init__(self, source: str):
        self.s, self.n = source, len(source)
        self.literals: list[_Literal] = []
        self.texts: list[tuple[int, str]] = []
        self._contexts: list[tuple[str, str | None, int]] = []
        self._open: list[int] = []  # where each construct being read began, innermost last
        self._blank: list[tuple[int, int]] = []
        try:
            self._code(0, None)
        except (IndexError, AttributeError, ValueError) as error:
            at = self._open[-1] if self._open else self.n
            raise TsxSyntaxError(f"unsupported syntax at line {self.s.count(chr(10), 0, at) + 1}") from error
        chars = list(source)
        for start, end in self._blank:
            chars[start:end] = " " * (end - start)
        self.masked = "".join(chars)

    def _context(self) -> tuple[str, str | None, int]:
        return self._contexts[-1] if self._contexts else ("code", None, -1)

    def _skip_ws(self, i: int) -> int:
        while self.s[i].isspace():
            i += 1
        return i

    def _code(self, i: int, closer: str | None) -> int:
        stack: list[bool] = []  # per open bracket: did it push a call context?
        brackets: list[str] = []
        while i < self.n:
            c = self.s[i]
            if self.s.startswith("//", i):
                end = self.s.find("\n", i)
                end = self.n if end < 0 else end
                self._blank.append((i, end))
                i = end
            elif self.s.startswith("/*", i):
                self._open.append(i)
                end = self.s.index("*/", i + 2) + 2
                self._open.pop()
                self._blank.append((i, end))
                i = end
            elif c == "/" and self._regex_starts(i):
                i = self._regex(i)
            elif c in "'\"":
                i = self._string(i)
            elif c == "`":
                i = self._template(i)
            elif c in "([{":
                pushed = c == "(" and self._call_context(i)
                brackets.append(c)
                stack.append(pushed)
                i += 1
            elif c in ")]}":
                if not brackets:
                    if c == closer:
                        return i + 1
                    raise ValueError(f"unbalanced {c!r}")
                brackets.pop()
                if stack.pop():
                    self._contexts.pop()
                i += 1
            elif c == "<" and self._jsx_starts(i):
                i = self._element(i)
            else:
                i += 1
        if closer:
            raise ValueError(f"missing {closer!r}")
        return i

    def _previous(self, i: int) -> str:
        return self.s[:i].rstrip()[-1:]

    def _regex_starts(self, i: int) -> bool:
        if self.s.startswith(("//", "/*"), i):
            return False
        before = self.s[max(0, i - 40) : i].rstrip()
        word = re.search(r"([A-Za-z_$][\w$]*)$", before)
        if word:
            return word.group(1) in _KEYWORDS  # `x / 2` divides; `return /a/` is a regex
        return not before or before[-1] in "(,=:[!&|?{};+-*%<>~^"

    def _regex(self, i: int) -> int:
        self._open.append(i)
        j, in_class = i + 1, False
        while True:
            c = self.s[j]
            if c in "\r\n":
                raise ValueError("line break in a regex")
            if c == "\\":
                j += 2
                continue
            if c == "[":
                in_class = True
            elif c == "]":
                in_class = False
            elif c == "/" and not in_class:
                break
            j += 1
        self._blank.append((i + 1, j))
        j += 1
        while j < self.n and self.s[j].isalpha():  # flags
            j += 1
        self._open.pop()
        return j

    def _call_context(self, i: int) -> bool:
        """At `(`: a class helper or a query-builder call starts a context its literals inherit."""
        m = re.search(r"(\.?)\s*([A-Za-z_$][\w$]*)\s*$", self.s[max(0, i - 60) : i])
        if m and (m.group(2) in _CLASS_CALLS or (m.group(1) and m.group(2) in _QUERY_CALLS)):
            self._contexts.append(("call", m.group(2), i))
            return True
        return False

    def _jsx_starts(self, i: int) -> bool:
        rest = self.s[i + 1 : i + 80]
        if not (rest[:1].isalpha() or rest[:1] == ">"):
            return False  # `a < b`
        if re.match(r"[A-Za-z_$][\w$]*\s*(?:,|extends\b)", rest):
            return False  # a generic arrow in TSX: <T,>(x: T) => x, <T extends object>(…) => …
        before = self.s[:i].rstrip()
        if not before or re.search(r"\breturn$", before):
            return True
        # After an identifier or `)` it is a generic or a comparison: useState<T>(), FC<Props>.
        return before[-1] in "(,=:?{[!&|;" or before.endswith("=>")

    def _string(self, i: int) -> int:
        self._open.append(i)
        quote, j, out = self.s[i], i + 1, []
        while self.s[j] != quote:
            if self.s[j] in "\r\n":
                raise ValueError("line break in a string")
            if self.s[j] == "\\":
                out.append(self.s[j + 1])
                j += 2
            else:
                out.append(self.s[j])
                j += 1
        self.literals.append(_Literal(i, j + 1, "".join(out), self._context()))
        self._blank.append((i + 1, j))
        self._open.pop()
        return j + 1

    def _template(self, i: int) -> int:
        self._open.append(i)
        j, parts, current, part_start = i + 1, [], [], i + 1
        while self.s[j] != "`":
            if self.s[j] == "\\":
                current.append(self.s[j + 1])
                j += 2
            elif self.s.startswith("${", j):
                parts.append("".join(current))
                current = []
                self._blank.append((part_start, j))
                j = self._code(j + 2, "}")
                part_start = j
            else:
                current.append(self.s[j])
                j += 1
        parts.append("".join(current))
        self._blank.append((part_start, j))
        self.literals.append(_Literal(i, j + 1, " ".join(parts), self._context()))
        self._open.pop()
        return j + 1

    def _expression(self, j: int, context: tuple[str, str | None, int]) -> tuple[int, _Literal | None]:
        """Scan `{…}` from its `{`; return the end and the literal if it is the whole expression."""
        first = len(self.literals)
        self._contexts.append(context)
        end = self._code(j + 1, "}")
        self._contexts.pop()
        inner = self.s[j + 1 : end - 1].strip()
        lits = self.literals[first:]
        if len(lits) == 1 and inner == self.s[lits[0].start : lits[0].end]:
            return end, lits[0]
        return end, None

    def _element(self, i: int) -> int:
        self._open.append(i)
        j = i + 1
        if self.s[j] == ">":
            end = self._children(j + 1)
            self._open.pop()
            return end
        name = re.match(r"[A-Za-z][\w.:-]*", self.s[j:]).group(0)
        j += len(name)
        while True:
            j = self._skip_ws(j)
            if self.s.startswith("/>", j):
                self._open.pop()
                return j + 2
            if self.s[j] == ">":
                end = self._children(j + 1)
                self._open.pop()
                return end
            if self.s[j] == "{":  # {...spread}
                j, _ = self._expression(j, self._context())
                continue
            attr = re.match(r"[\w:.-]+", self.s[j:]).group(0)
            j = self._skip_ws(j + len(attr))
            if self.s[j] != "=":
                continue  # a boolean attribute
            j = self._skip_ws(j + 1)
            if self.s[j] in "'\"":  # JSX attribute strings have no escapes
                end = self.s.index(self.s[j], j + 1)
                self.literals.append(
                    _Literal(j, end + 1, self.s[j + 1 : end], ("attr", attr, j), attr=attr)
                )
                self._blank.append((j + 1, end))
                j = end + 1
            else:
                j, literal = self._expression(j, ("attr", attr, j))
                if literal:
                    literal.attr = attr

    def _children(self, j: int) -> int:
        while True:
            if self.s.startswith("</", j):
                return self.s.index(">", j) + 1
            if self.s[j] == "<":
                j = self._element(j)
            elif self.s[j] == "{":
                j, literal = self._expression(j, ("child", None, j))
                if literal:
                    literal.child = True
            else:
                end = min(k for k in (self.s.find("<", j), self.s.find("{", j)) if k >= 0)
                self.texts.append((j, self.s[j:end]))
                self._blank.append((j, end))
                j = end


def _owner(masked: str, pos: int) -> tuple[str, object]:
    """What the value at `pos` belongs to, walking back through the code at the same depth.

    ("prop", name) for an object property's value, also through `? :`, `||`, `&&` or `+`;
    ("open", index) when the walk reaches an enclosing `{` (a JSX child or attribute starts
    there); ("call", index) for a function argument; ("array"/"sep"/"top", index) otherwise.
    """
    depth, j = 0, pos - 1
    while j >= 0:
        c = masked[j]
        if c in ")]}":
            depth += 1
        elif c in "([{":
            if depth:
                depth -= 1
            elif c == "(":
                before = masked[max(0, j - 40) : j].rstrip()
                word = re.search(r"([A-Za-z_$][\w$]*)$", before)
                grouping = (
                    not before
                    or before.endswith("=>")
                    or (word and word.group(1) in _KEYWORDS)
                    or not (word or before[-1] in ")]>")
                )
                if not grouping:
                    return ("call", j)
            else:
                return ("open", j) if c == "{" else ("array", j)
        elif depth == 0:
            if c in ",;":
                return ("sep", j)
            if c == ":":
                prop = re.search(r"[{,]\s*([A-Za-z_$][\w$]*)\s*$", masked[max(0, j - 80) : j])
                if prop:
                    return ("prop", prop.group(1))
        j -= 1
    return ("top", -1)


def _code_like(value: str) -> bool:
    """A class list, id or column list, locale code or constant: not something a reader sees."""
    if not value.strip() or value in _LANGUAGE_CODES:
        return True
    tokens = value.split()
    return all(_CODE_TOKEN.fullmatch(t) for t in tokens) and any(re.search(r"[-_:/\[\d]", t) for t in tokens)


@functools.cache
def _translation_copy() -> frozenset[str]:
    from test_landing_page import _translation_values

    # Values that are copy, not codes: 'calendar', 'neutral' and 'ar-SA-u-…' are left out.
    return frozenset(v for v in _translation_values() if len(v) >= 4 and not re.fullmatch(r"[a-z][\w-]*", v))


def _strongly_copy(value: str) -> bool:
    """Arabic or Urdu script, a capitalised word, or a value of translations.ts."""
    return bool(_ARABIC.search(value) or _TITLE_WORD.search(value) or value.strip() in _translation_copy())


def _plain_words(value: str) -> bool:
    tokens = value.split()
    return len(tokens) >= 2 and all(_PLAIN_WORD.fullmatch(t) for t in tokens)


def _hardcoded_copy(source: str) -> list[str]:
    """Hardcoded user-facing text in a TSX source, each as `line N: what`."""
    scan = _TsxScanner(source)
    found: list[tuple[int, str]] = []

    for at, text in scan.texts:
        if _LETTER.search(text):
            found.append((at, f"JSX text {text.strip()!r}"))

    for lit in scan.literals:
        value = lit.value
        if not value.strip():
            continue
        before = source[max(0, lit.start - 40) : lit.start].rstrip()
        if re.search(r"\b(?:from|import)$|\bimport\($", before) or before.endswith(("===", "!==")):
            continue  # a module path, or compared against and never shown: e.key === 'Escape'
        letter = bool(_LETTER.search(value))
        kind, name, opened = lit.context
        if lit.attr is not None:
            if (letter if lit.attr in _COPY_ATTRS else _strongly_copy(value)):
                found.append((lit.start, f"{lit.attr}={value!r}"))
            continue
        if lit.child:
            if letter:
                found.append((lit.start, f"JSX child {value!r}"))
            continue
        if kind == "call":  # cn('relative flex'), .select('id, amount'), .eq('status', 'due')
            if _ARABIC.search(value) or value.strip() in _translation_copy():
                found.append((lit.start, f"{name}(… {value!r} …)"))
            continue
        owner = _owner(scan.masked, lit.start)
        if owner[0] == "prop" and owner[1] in _COPY_PROPS:
            if letter and not _code_like(value):
                found.append((lit.start, f"{owner[1]}: {value!r}"))
            continue
        if kind == "child" or (kind == "attr" and name in _COPY_ATTRS):
            shown = owner == ("open", opened)  # rendered as is, through ? :, &&, || or +
            if (shown and letter and not _code_like(value)) or _strongly_copy(value) or _plain_words(value):
                found.append((lit.start, f"{'JSX child' if kind == 'child' else name} shows {value!r}"))
            continue
        if _strongly_copy(value):  # plain code, or a code attribute such as className or dir
            found.append((lit.start, f"literal {value!r}"))

    return [f"line {source.count(chr(10), 0, at) + 1}: {what}" for at, what in sorted(set(found))]


# ── Self-tests: the guard catches hardcoded copy in the real BudgetsView.tsx ───────────────────

_BUDGETS_VIEW = PORTAL / "BudgetsView.tsx"
_TITLE_EXPR = "{dict.portal.approvedCategoriesTitle}"
_GROCERY = "name: names.grocery"
_ROOT_DIV = 'className="space-y-8"'
_CODE_LINE = "const names = dict.portal.budgetCategories;"


def _with_code(statement: str) -> tuple[str, str]:
    """A splice that adds a statement to the component body."""
    return _CODE_LINE, f"{_CODE_LINE}\n  {statement}"


def _splice(old: str, new: str) -> str:
    source = _BUDGETS_VIEW.read_text(encoding="utf-8")
    assert source.count(old) >= 1, old
    return source.replace(old, new, 1)


@pytest.mark.parametrize(
    ("old", "new"),
    [
        # The five evasions from review Round 1.
        (_TITLE_EXPR, "Approved Budget Categories"),
        (_TITLE_EXPR, "{'Approved Budget Categories'}"),
        (_GROCERY, "name: 'Groceries & Staples'"),
        (_TITLE_EXPR, "{isAr ? 'Approved' : 'Approved Budget Categories'}"),
        (_TITLE_EXPR, "{dict === translations.ar ? 'x' : 'Approved'}"),
        # The second reviewer's set.
        (_TITLE_EXPR, "{`${budgets.length} categories`}"),
        _with_code("const cats = ['Grocery', 'Fuel'];"),
        _with_code("const t = 'Approved';"),
        _with_code("const t = `Approved ${budgets.length}`;"),
        _with_code("const u = 'منظور شدہ بجٹ';"),
        (_TITLE_EXPR, "{'منظور شدہ بجٹ'}"),
        (_TITLE_EXPR, "<Card title=\"per month\" />"),
        (_TITLE_EXPR, "{loading && 'Loading'}"),
        (_TITLE_EXPR, "{budgets.length + ' Total'}"),
        (_TITLE_EXPR, "{'APPROVED'}"),
        # Lowercase copy where it is shown: a JSX child, a copy attribute or a copy property.
        (_TITLE_EXPR, "{isAr ? 'paid' : 'due'}"),
        (_TITLE_EXPR, "{loading && 'loading'}"),
        (_TITLE_EXPR, "{budgets.length + ' total'}"),
        (_TITLE_EXPR, "<Card subtitle=\"per month\" />"),
        (_TITLE_EXPR, "<Card emptyText={'nothing yet'} />"),
        (_TITLE_EXPR, "<Card title={isAr ? 'paid' : 'due'} />"),
        (_GROCERY, "name: isAr ? 'groceries' : 'grocery'"),
        (_GROCERY, "name: names.grocery || 'groceries'"),
        # More shapes of the same thing.
        (_TITLE_EXPR, "{dict.portal.approvedCategoriesTitle} total"),
        (_TITLE_EXPR, "approved budget categories"),
        (_TITLE_EXPR, "بنود الميزانية المعتمدة"),
        (_TITLE_EXPR, "{'approved'}"),
        (_TITLE_EXPR, '{"Wife\'s allowance"}'),
        (_TITLE_EXPR, "{lang === 'ar' ? 'بنود' : 'Items'}"),
        (_TITLE_EXPR, "{label('approved budget')}"),
        (_GROCERY, "name: 'groceries'"),
        (_GROCERY, "label: 'groceries'"),
        (_GROCERY, "name: 'البقالة والتموين'"),
        (_ROOT_DIV, f'{_ROOT_DIV} title="Budgets"'),
        (_ROOT_DIV, f"{_ROOT_DIV} aria-label={{'budgets'}}"),
        (_ROOT_DIV, f'{_ROOT_DIV} placeholder="search"'),
        (_ROOT_DIV, f'{_ROOT_DIV} alt="chart"'),
    ],
)
def test_the_guard_catches_hardcoded_copy_in_budgets_view(old, new):
    assert _hardcoded_copy(_splice(old, new)), new


@pytest.mark.parametrize(
    ("old", "new"),
    [
        # Code that is never shown, from review Round 1 of the scanner (each was flagged).
        (_ROOT_DIV, "className={`p-4 ${active ? 'ring-2' : ''}`}"),
        (_ROOT_DIV, "className={open ? 'block' : 'hidden'}"),
        (_ROOT_DIV, "className={x ? 'grid' : 'flex'}"),
        (_ROOT_DIV, "className={`relative flex ${x}`}"),
        (_ROOT_DIV, "className={cn('relative flex', open && 'block')}"),
        _with_code("const c = cn('relative flex', open && 'block');"),
        _with_code("const k = clsx('grid gap-4', wide ? 'grid-cols-2' : '');"),
        _with_code("const base = 'relative flex';"),
        _with_code("const q = supabase.from('budgets').select('id, amount');"),
        _with_code("const r = supabase.from('budgets').select('amount, spent').order('amount');"),
        _with_code("const s = supabase.from('budgets').select('id').eq('status', paid ? 'paid' : 'due');"),
        (_ROOT_DIV, f"{_ROOT_DIV} dir={{isAr ? 'rtl' : 'ltr'}}"),
        (_ROOT_DIV, f"{_ROOT_DIV} type={{show ? 'text' : 'password'}}"),
        (_ROOT_DIV, f"{_ROOT_DIV} role={{open ? 'dialog' : 'region'}} id={{`budget-${{x}}`}}"),
    ],
)
def test_the_guard_spares_code_spliced_into_budgets_view(old, new):
    assert _hardcoded_copy(_splice(old, new)) == []


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
        "<div>{new Date(d).toLocaleDateString('ar-SA')}</div>",
        "<div>{items.join(', ')}</div>",
        "<div>{/* Wife's Personal Allowance Card (مصروف الزوجة) */}</div>",
        "// Approved Budget Categories (مصروف الزوجة)",
        "/* Groceries & Staples */",
        "<input type=\"text\" id=\"budget-search\" name=\"query\" placeholder={dict.portal.searchPlaceholder} />",
        "if (e.key === 'Escape') onClose(); if (tx.status !== 'Paid Out') skip();",
        "const other: Language = lang === 'ar' ? 'en' : 'ar';",
        "<div>{items.map((b) => (<span key={b.id} className={b.on ? 'block' : 'hidden'}>{b.label}</span>))}</div>",
    ],
)
def test_the_guard_spares_code_literals_and_dictionary_lookups(snippet):
    assert _hardcoded_copy(snippet) == []


@pytest.mark.parametrize(
    "snippet",
    [
        # A regex literal holding a quote, and TSX generic arrows: review Round 1 crashes.
        "const strip = (s: string) => s.replace(/'/g, '');",
        'const quoted = /"/.test(text) ? 1 : 0;',
        "const unescape = (s: string) => s.replace(/\\/'[a-z]/gi, '');",
        "const id = <T,>(x: T) => x;",
        "const keep = <T extends object>(x: T): T => x;",
        "const half = total / 2; const ratio = (a / b) / c;",
    ],
)
def test_the_scanner_parses_regexes_and_generic_arrows(snippet):
    assert _hardcoded_copy(snippet) == []


@pytest.mark.parametrize(
    ("snippet", "line"),
    [
        ("const a = 1;\nconst b = 'not closed;\n", 2),
        ("const a = 1;\n\nconst id = <T>(x: T) => x;\n", 3),  # in TSX `<T>` opens an element
        ("const a = 1;\nconst b = (<div className={x}>\n  text\n", 2),  # never closed
    ],
)
def test_the_scanner_names_the_line_it_cannot_read(snippet, line):
    with pytest.raises(ValueError, match=rf"unsupported syntax at line {line}\b"):
        _hardcoded_copy(snippet)


def test_the_scanner_reads_the_whole_component():
    scan = _TsxScanner(_BUDGETS_VIEW.read_text(encoding="utf-8"))
    attrs = {lit.attr for lit in scan.literals if lit.attr}
    assert {"className", "viewBox", "d"} <= attrs
    assert len(scan.texts) > 20  # whitespace and ':' between the elements


@pytest.mark.parametrize("name", _CLEAN_COMPONENTS)
def test_portal_component_takes_its_copy_from_the_dictionary(name):
    assert _hardcoded_copy((PORTAL / name).read_text(encoding="utf-8")) == [], name
