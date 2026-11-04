"""Deterministic guardrails, the first of three layers (spec Section 6.5).

Everything here runs before a reel reaches Telegram, on Arabic and English text. A hard failure
blocks the reel, and a soft flag is shown to the owner. G15 and G16 run at render time, in
`core/render.py`.

Figures and product statements are checked against what they must match, not against what is
banned. A figure has to be in a research fact from the source it cites, with the same value and
unit, or in an approved claim the script uses, or carry an example label in its own sentence. A
sentence about the app has to stay within the words of its approved claims. Anything else in those
two areas is refused.

Word lists are the second layer, and they are easy to walk around, so text is folded first:
diacritics, kashida, hidden characters, spelling variants, look-alike letters, digit forms and
letter-by-letter spacing do not change what a rule sees. Terms also match with gaps between their
letters, but only where the whole term stands as a word, so "teams message" does not hold "sms".
Meaning, especially in dialect, is the job of the separate Claude review, and the owner's tap on
Telegram is the final check.
"""

from __future__ import annotations

import re
import unicodedata
from bisect import bisect_right
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, replace
from datetime import date
from decimal import Decimal
from functools import cache, lru_cache
from pathlib import Path
from typing import Literal, Protocol
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict

from content_engine import denylists as words
from content_engine.cta import (
    BRAND_TOKEN,
    UnknownTokenError,
    active_wording,
    compose_caption,
    compose_voice,
    fill_tokens,
    without_engine_lines,
)
from content_engine.schemas import GuardrailFinding, GuardrailReport, ResearchFact, Script
from core.brand_gate import FULL_NAME_AR, FULL_NAME_EN, ReelBrand, contains_withdrawn_name
from core.config import EngineConfig

REGISTER_PATH = Path(__file__).resolve().parent / "approved_claims.json"

_MAX_FINDINGS = 200  # GuardrailReport's own limit
_NEAR_SPOUSE = 12
_NEAR_BRAND = 8
_NEAR_EXAMPLE = 6
_NEAR_SALARY = 6
_NEAR_COMPARISON = 10
_NEAR_BANK_CONTRAST = 3
_NEAR_BASKET = 20
_NEAR_QR = 12
_NEAR_AUTHORITY = 5
_NEAR_MESSAGE = 4
_NEAR_ASSET = 4

_C18 = "C18"
_C21 = "C21"
_C11 = "C11"
_SMART_BASKET_FOLDER = "smart_basket"
_NAFAQAH_FOLDER = "nafaqah_wife_expenses"
_TOKEN_MARK = "qbrandtoken"  # what a brand token looks like to the word rules

Stage = Literal["script", "filled"]
Language = Literal["ar", "en"]


# --- The claims register -----------------------------------------------------------------


class Claim(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    meaning: str
    wording_ar: str
    wording_en: str
    evidence: tuple[str, ...]
    last_checked: date
    code_check: Literal["supported", "not_supported"]
    code_note: str
    clip_folders: tuple[str, ...]


class RejectedClaim(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    claim: str
    caught_by: tuple[str, ...]
    samples_ar: tuple[str, ...]
    samples_en: tuple[str, ...]


class _RegisterFile(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    schema_version: Literal[1]
    claims: tuple[Claim, ...]
    rejected_claims: tuple[RejectedClaim, ...]


@dataclass(frozen=True)
class ClaimsRegister:
    claims: dict[str, Claim]
    rejected: tuple[RejectedClaim, ...]

    @property
    def approved(self) -> tuple[Claim, ...]:
        """What the writer may use. A claim the code does not back stays held, as in G1."""
        return tuple(claim for claim in self.claims.values() if claim.code_check == "supported")


@lru_cache(maxsize=4)
def load_claims_register(path: Path = REGISTER_PATH) -> ClaimsRegister:
    parsed = _RegisterFile.model_validate_json(path.read_bytes().decode("utf-8"))
    return ClaimsRegister({claim.id: claim for claim in parsed.claims}, parsed.rejected_claims)


# --- Folding text ------------------------------------------------------------------------

_FOLDS = {
    # Arabic spelling variants, Urdu and Persian letters, and letters with their dots removed.
    "\u0649": "\u064a",  # alef maksura
    "\u06cc": "\u064a",  # Persian yeh
    "\u06d2": "\u064a",  # Urdu yeh barree
    "\u06a9": "\u0643",  # keheh
    "\u06aa": "\u0643",  # swash kaf
    "\u06c1": "\u0647",  # heh goal
    "\u06be": "\u0647",  # heh doachashmee
    "\u06d5": "\u0647",  # ae
    "\u0671": "\u0627",  # alef wasla
    "\u0672": "\u0627",
    "\u0673": "\u0627",
    "\u0675": "\u0627",
    "\u066f": "\u0642",  # dotless qaf
    "\u06a1": "\u0641",  # dotless feh
    "\u066e": "\u0628",  # dotless beh
    "\u06ba": "\u0646",  # dotless noon
    "\u066a": "%",  # Arabic percent sign
    "\u066b": ".",  # Arabic decimal separator
    "\u066c": ",",  # Arabic thousands separator
    "\u06a7": "\u0642",  # qaf variants
    "\u06a8": "\u0642",
    "\u06c4": "\u0648",  # waw variants
    "\u06c5": "\u0648",
    "\u06c6": "\u0648",
    "\u06c7": "\u0648",
    "\u06c8": "\u0648",
    "\u06c9": "\u0648",
    "\u06ca": "\u0648",
    "\u06cb": "\u0648",
    "\u06cf": "\u0648",
    # Latin look-alikes from Cyrillic and Greek, after case folding.
    "\u0430": "a",
    "\u0435": "e",
    "\u043e": "o",
    "\u0440": "p",
    "\u0441": "c",
    "\u0443": "y",
    "\u0445": "x",
    "\u0456": "i",
    "\u0458": "j",
    "\u0455": "s",
    "\u051b": "q",
    "\u04bb": "h",
    "\u043c": "m",
    "\u0442": "t",
    "\u043a": "k",
    "\u043d": "h",
    "\u0432": "b",
    "\u03b1": "a",
    "\u03b5": "e",
    "\u03bf": "o",
    "\u03c1": "p",
    "\u03bd": "v",
    "\u03b9": "i",
    "\u03ba": "k",
    "\u03c4": "t",
    "\u0131": "i",  # dotless i
    # Small capitals, which NFKC leaves alone.
    "\u1d00": "a",
    "\u0299": "b",
    "\u1d04": "c",
    "\u1d05": "d",
    "\u1d07": "e",
    "\ua730": "f",
    "\u0262": "g",
    "\u029c": "h",
    "\u026a": "i",
    "\u1d0a": "j",
    "\u1d0b": "k",
    "\u029f": "l",
    "\u1d0d": "m",
    "\u0274": "n",
    "\u1d0f": "o",
    "\u1d18": "p",
    "\u0280": "r",
    "\ua731": "s",
    "\u1d1b": "t",
    "\u1d1c": "u",
    "\u1d20": "v",
    "\u1d21": "w",
    "\u028f": "y",
    "\u1d22": "z",
}
_DROPPED_LETTERS = {"\u0640", "\u3164", "\uffa0", "\u115f", "\u1160"}  # kashida, blank letters
_BLANK_SYMBOLS = {"\u2800"}
_REMOVED_CATEGORIES = {"Mn", "Me", "Cf"}

_WORD_CHAR = r"[^\W_]"
_START = rf"(?<!{_WORD_CHAR})"
_END = rf"(?!{_WORD_CHAR})"
_WORD = re.compile(rf"{_WORD_CHAR}+")
_SINGLE_CHARS = re.compile(
    rf"{_START}{_WORD_CHAR}(?:[ .\-_\u00b7\u2022*~]{_WORD_CHAR}{_END}){{2,}}"
)
_SPACED_DIGITS = re.compile(rf"{_START}(\d) (\d){_END}")
_SPACES = re.compile(r"[ ]+")
_SPACE_AROUND_NEWLINE = re.compile(r" ?\n ?")


def _clean(text: str) -> str:
    composed = unicodedata.normalize("NFKC", text).casefold()
    folded = []
    for ch in unicodedata.normalize("NFD", composed):
        category = unicodedata.category(ch)
        if category in _REMOVED_CATEGORIES or ch in _DROPPED_LETTERS:
            continue
        if category == "Nd":
            folded.append(str(unicodedata.digit(ch)))
        elif ch == "\n":
            folded.append(ch)
        elif ch.isspace() or category == "Cc" or ch in _BLANK_SYMBOLS:
            folded.append(" ")
        else:
            folded.append(_FOLDS.get(ch, ch))
    return "".join(folded)


def _rejoin_spaced_letters(text: str) -> str:
    joined = _SINGLE_CHARS.sub(lambda m: "".join(c for c in m.group() if c.isalnum()), text)
    return _SPACED_DIGITS.sub(r"\1\2", joined)


def brand_form(text: str) -> str:
    """What a reader sees, with the difference between ة and ه kept: قوامة is another word."""
    rejoined = _rejoin_spaced_letters(_clean(text))
    return _SPACE_AROUND_NEWLINE.sub("\n", _SPACES.sub(" ", rejoined)).strip()


def lexicon_form(text: str) -> str:
    """The form every word rule reads. مناصفة and مناصفه, and شراء and شرا, are one word here."""
    return brand_form(text).replace("\u0629", "\u0647").replace("\u0621", "")


# --- Compiling word lists ----------------------------------------------------------------

_LETTER_GAP = r"[\W_]{0,2}"
_WORD_GAP = r"[\W_]{0,3}"
_AR_PREFIX = "[\u0648\u0641\u0628\u0644\u0643]{0,2}(?:\u0627\u0644)?"
_AR_ENDING = (
    "(?:\u0643|\u0643\u0645|\u0643\u0646|\u0646\u0627|\u064a|\u0647|\u0647\u0627|\u0647\u0645"
    "|\u0647\u0646)?"
)


def _is_arabic(ch: str) -> bool:
    return "\u0600" <= ch <= "\u06ff"


def _term_body(form: str) -> str:
    parts: list[str] = []
    for index, ch in enumerate(form):
        if ch.isalnum():
            parts.append(re.escape(ch))
            if index + 1 < len(form) and form[index + 1].isalnum():
                parts.append(_LETTER_GAP)
        elif parts and parts[-1] != _WORD_GAP:
            parts.append(_WORD_GAP)
    if parts and parts[-1] == _WORD_GAP:
        parts.pop()
    return "".join(parts)


def _term_pattern(form: str) -> str:
    body = _term_body(form)
    prefix = _AR_PREFIX if _is_arabic(form[0]) else ""
    ending = _AR_ENDING if _is_arabic(form[-1]) else ""
    return f"{prefix}{body}{ending}"


def _alternatives(terms: Iterable[str], form=lexicon_form) -> str:
    forms = sorted({form(term) for term in terms}, key=len, reverse=True)
    return "(?:" + "|".join(_term_pattern(item) for item in forms) + ")"


@cache
def _lexicon(terms: tuple[str, ...]) -> re.Pattern[str]:
    return re.compile(f"{_START}{_alternatives(terms)}{_END}")


def _positions_near(text: str, first: Sequence[int], second: Sequence[int], window: int) -> bool:
    if not first or not second:
        return False
    starts = [match.start() for match in _WORD.finditer(text)]
    first_words = [bisect_right(starts, position) for position in first]
    second_words = [bisect_right(starts, position) for position in second]
    return any(abs(a - b) <= window for a in first_words for b in second_words)


def _positions(pattern: re.Pattern[str], text: str) -> list[int]:
    return [match.start() for match in pattern.finditer(text)]


def _near(text: str, first: re.Pattern[str], second: re.Pattern[str], window: int) -> bool:
    """Whether a match of each pattern falls within `window` words of the other."""
    return _positions_near(text, _positions(first, text), _positions(second, text), window)


_SENTENCE_END = re.compile(r"[!?\u061f\n]+|(?<!\be)(?<!\be\.g)\.(?!\d)")


def _sentences(text: str) -> list[str]:
    return [piece for piece in _SENTENCE_END.split(text) if piece.strip()]


# --- Context and results -----------------------------------------------------------------


@dataclass(frozen=True)
class GuardrailContext:
    """What a rule needs to know beyond the words themselves."""

    stage: Stage = "script"  # "script" holds tokens, and "filled" holds the brand from config
    language: Language | None = None  # sets the brand order on screen. None: no order rule
    spoken: bool = False  # voiceover may say one name. Everything else shows both
    hashtag: bool = False
    numbers: tuple[str, ...] = ()  # text whose figures are proved: facts and the claims in use
    claim_ids: frozenset[str] = frozenset()
    basket: bool = False  # a Smart Basket reel, where any saving wording is tied to the basket
    family: bool = False  # a family reel, where split wording is out wherever it stands
    cta_mode: str = "coming_soon"
    landing_url: str | None = None
    brand: ReelBrand | None = None  # required at the filled stage
    other_brand_names: tuple[str, ...] = ()  # test brand names, which a script may not hard-code
    register: ClaimsRegister | None = None

    def claims(self) -> ClaimsRegister:
        return self.register or load_claims_register()


@dataclass(frozen=True)
class _Hit:
    rule: str
    message: str
    soft: bool = False


@dataclass(frozen=True)
class _Text:
    raw: str
    brand: str
    lex: str


def _prepare(raw: str) -> _Text:
    marked = BRAND_TOKEN.sub(f" {_TOKEN_MARK} ", raw)
    return _Text(raw, brand_form(marked), lexicon_form(marked))


def _quote(match: re.Match[str]) -> str:
    return repr(match.group()[:60])


# --- G1: every product statement maps to an approved claim ---------------------------------


_FEATURES_ALWAYS = (
    (words.SMART_BASKET_NAMES, frozenset({"C21"})),
    (words.PRICE_TRACKER_NAMES, frozenset({"C15"})),
)
_FEATURES_WITH_APP = (
    (words.NAFAQAH_NAMES, frozenset({"C11"})),
    (words.QR_TERMS, frozenset({"C05", "C15"})),
)
_CONTENTS_OF = re.compile(rf"{_START}مضمون ال")  # "the contents of", not "guaranteed"
_ELIDED_SUBJECT = re.compile(rf"^\s*(?:it |هو )?{_alternatives(words.PRODUCT_VERBS)}{_END}")
_AR_WORD_PREFIX = re.compile("^(?:وال|بال|فال|كال|لل|ال|و|ب|ل|ف)(?=..)")
_AR_WORD_ENDING = re.compile("(?<=..)(?:كم|هم|ها|نا|ات|ين|ون|ك|ه|ي)$")
_AR_LONG_VOWELS = str.maketrans("", "", "\u0627\u0648\u064a")
_EN_WORD_ENDING = re.compile(r"(?<=...)(?:ing|ed|es|s)$")
_FILLER_WORDS = frozenset(lexicon_form(word) for word in words.PRODUCT_FILLER_WORDS)


def _stem(word: str) -> str:
    """Near enough to compare: مصاريف and مصروف, and tracks and tracking, come out alike."""
    if not _is_arabic(word[0]):
        return _EN_WORD_ENDING.sub("", word)
    bare = _AR_WORD_ENDING.sub("", _AR_WORD_PREFIX.sub("", word))
    return bare.translate(_AR_LONG_VOWELS) or bare


def _same_stem(first: str, second: str) -> bool:
    shorter, longer = sorted((first, second), key=len)
    if shorter == longer:
        return True
    shortest_allowed = 3 if _is_arabic(first[0]) else 4
    return len(shorter) >= shortest_allowed and longer.startswith(shorter)


@lru_cache(maxsize=256)
def _stems_of(wording: str) -> frozenset[str]:
    return frozenset(_stem(word) for word in _WORD.findall(lexicon_form(wording)))


def _says_what_counts(sentence: str) -> list[str]:
    """The words of a product sentence that state something, as stems."""
    found = []
    for word in _WORD.findall(sentence):
        plain = _AR_WORD_PREFIX.sub("", word) if _is_arabic(word[0]) else word
        if word == _TOKEN_MARK or word.isdigit() or len(word) < 2:
            continue
        if word not in _FILLER_WORDS and plain not in _FILLER_WORDS:
            found.append(_stem(word))
    return found


def _goes_beyond_claims(sentence: str, context: GuardrailContext) -> bool:
    """G1, by what a sentence must match. Most of what it says has to come from the wording of
    a claim the script names. It cannot prove the meaning is kept: that is the Claude review."""
    stated = _says_what_counts(sentence)
    if not stated:
        return False
    register = context.claims().claims
    known = set()
    for claim_id in context.claim_ids:
        claim = register.get(claim_id)
        if claim is not None:
            known |= _stems_of(claim.wording_ar) | _stems_of(claim.wording_en)
    backed = sum(any(_same_stem(word, stem) for stem in known) for word in stated)
    return backed * 2 < len(stated)


def _is_about_the_app(sentence: str) -> bool:
    return (
        _TOKEN_MARK in sentence
        or bool(_lexicon(words.APP_MENTIONS).search(sentence))
        or bool(_ELIDED_SUBJECT.match(sentence))
    )


def _g1(text: _Text, context: GuardrailContext) -> list[_Hit]:
    if context.stage != "script":
        return []  # the CTA names the brand and is not a product statement
    hits = []
    unapproved = _lexicon(words.UNAPPROVED_FEATURES).search(_CONTENTS_OF.sub(" ", text.lex))
    if unapproved:
        hits.append(_Hit("G1", f"no approved claim covers {_quote(unapproved)}"))
    for terms, claim_ids in _FEATURES_ALWAYS:
        found = _lexicon(terms).search(text.lex)
        if found and not claim_ids & context.claim_ids:
            hits.append(_Hit("G1", f"{_quote(found)} needs one of {sorted(claim_ids)}"))
    if context.hashtag:
        return hits
    statements = [sentence for sentence in _sentences(text.lex) if _is_about_the_app(sentence)]
    if not statements:
        return hits
    if not context.claim_ids:
        hits.append(_Hit("G1", "a product statement carries no claim id"))
        return hits
    for terms, claim_ids in _FEATURES_WITH_APP:
        found = _lexicon(terms).search(text.lex)
        if found and not claim_ids & context.claim_ids:
            hits.append(_Hit("G1", f"{_quote(found)} needs one of {sorted(claim_ids)}"))
    for sentence in statements:
        if _goes_beyond_claims(sentence, context):
            hits.append(_Hit("G1", f"says more than its claims: {sentence[:80]!r}"))
    return hits


def _claim_hits(claim_ids: Iterable[str], register: ClaimsRegister) -> list[_Hit]:
    hits = []
    for claim_id in claim_ids:
        claim = register.claims.get(claim_id)
        if claim is None:
            hits.append(_Hit("G1", f"{claim_id} is not in the approved claims register"))
        elif claim.code_check != "supported":
            hits.append(_Hit("G1", f"{claim_id} is held, the code does not back it"))
    return hits


def check_claim_ids(claim_ids: Iterable[str], register: ClaimsRegister) -> list[GuardrailFinding]:
    """Each id must exist, and must not be one the code re-check could not back."""
    return [_finding(hit, "claim_ids") for hit in _claim_hits(claim_ids, register)]


def _clip_hits(folder: str | None, claim_ids: Iterable[str], register: ClaimsRegister) -> list:
    if folder is None or folder == "app_experience":
        return []
    allowed = [claim for claim in register.claims.values() if folder in claim.clip_folders]
    if any(claim.id in claim_ids for claim in allowed):
        return []
    return [_Hit("G1", f"the {folder} clip shows a feature none of the claim ids cover")]


# --- G2: no unverifiable numbers -----------------------------------------------------------


_NUMBER = r"\d(?:[\d,]*\d)?(?:\.\d+)?"
_NOT_IN_NUMBER = r"(?<![\d.,])"
_PERCENT_WORDS = _alternatives(words.PERCENT_WORDS)
_PERCENT_LEADS = _alternatives(words.PERCENT_LEAD_WORDS)
_MONEY_FORMS = sorted(
    (
        (re.sub(r"[\W_]", "", lexicon_form(form)), code)
        for code, forms in words.MONEY_UNITS.items()
        for form in forms
    ),
    key=lambda item: -len(item[0]),
)
_MONEY_WORDS = _alternatives(form for forms in words.MONEY_UNITS.values() for form in forms)
_CURRENCY = "".join(
    re.escape(ch)
    for ch in (*(chr(code) for code in range(0x10000)), *words.CURRENCY_SYMBOLS)
    if unicodedata.category(ch) == "Sc" or ch in words.CURRENCY_SYMBOLS
)
_NUMBER_WORD_VALUES = {lexicon_form(word): value for word, value in words.NUMBER_WORDS.items()}
_NUMBER_WORD = _alternatives(words.NUMBER_WORDS)
_NUMBER_PHRASE = rf"{_NUMBER_WORD}(?:{_WORD_GAP}(?:and{_WORD_GAP})?{_NUMBER_WORD})*"
_ONE_NUMBER_WORD = re.compile(
    "(?:" + "|".join(sorted(map(re.escape, _NUMBER_WORD_VALUES), key=len, reverse=True)) + ")"
)
_SCALE_VALUES = {lexicon_form(word): value for word, value in words.NUMBER_SCALES.items()}
_SCALE = rf"(?:{_WORD_GAP}(?P<scale>{_alternatives(words.NUMBER_SCALES)}){_END})?"
_DIGITS = rf"(?P<digits>{_NUMBER})(?![.,]?\d)"  # no backing up to read 5,000 as a 5
_WORDS = rf"(?P<words>{_NUMBER_PHRASE})"
_UNIT_AFTER = rf"(?:(?P<unit>{_MONEY_WORDS}){_END}|(?P<symbol>[{_CURRENCY}]))"
_UNIT_BEFORE = rf"(?:{_START}(?P<unit>{_MONEY_WORDS})|(?P<symbol>[{_CURRENCY}]))"
_COMPARISONS = _alternatives(words.MULTIPLIER_COMPARISONS)
_TIMES_WORDS = _alternatives(("times", "مرات", "مره"))
_COUNT_WORDS = _alternatives(words.COUNT_WORDS)
_FOLD_WORDS = _alternatives(("fold", "اضعاف"))
_NON_MONEY = _alternatives(words.NON_MONEY_UNITS)
_PER_PERIOD = _alternatives(
    (
        "every",
        "each",
        "a",
        "an",
        "per",
        "monthly",
        "weekly",
        "daily",
        "كل",
        "بالشهر",
        "شهريا",
        "بالاسبوع",
        "اسبوعيا",
        "باليوم",
        "يوميا",
    )
)
_ENDS_THE_AMOUNT = rf"(?=[^\w%]*(?:$|[.,!?\u061f\u060c\n]|{_PER_PERIOD}{_END}))"
_MONEY_VERBS = _alternatives(words.MONEY_VERBS)
_FIGURE_PATTERNS = tuple(
    (re.compile(pattern), kind)
    for pattern, kind in (
        (rf"{_NOT_IN_NUMBER}{_DIGITS}{_WORD_GAP}(?:%|{_PERCENT_WORDS}{_END})", "percent"),
        (rf"(?<!\d)%{_LETTER_GAP}{_DIGITS}", "percent"),
        (rf"{_START}{_PERCENT_LEADS}{_WORD_GAP}{_DIGITS}", "percent"),
        (rf"{_START}{_WORDS}{_WORD_GAP}(?:%|{_PERCENT_WORDS}{_END})", "percent"),
        (rf"(?<!\d)%{_WORD_GAP}{_WORDS}", "percent"),
        (rf"{_NOT_IN_NUMBER}{_DIGITS}{_SCALE}{_WORD_GAP}{_UNIT_AFTER}", "money"),
        (rf"{_UNIT_BEFORE}{_WORD_GAP}{_DIGITS}{_SCALE}", "money"),
        (rf"{_START}{_WORDS}{_WORD_GAP}{_UNIT_AFTER}", "money"),
        (rf"{_START}(?P<unit>{_MONEY_WORDS}){_WORD_GAP}{_WORDS}{_END}", "money"),
        (rf"{_START}{_MONEY_VERBS}{_WORD_GAP}{_DIGITS}{_SCALE}{_ENDS_THE_AMOUNT}", "money"),
        (rf"{_START}{_MONEY_VERBS}{_WORD_GAP}(?:a )?{_WORDS}{_ENDS_THE_AMOUNT}", "money"),
        (rf"{_NOT_IN_NUMBER}{_DIGITS} ?[x\u00d7]{_END}", "multiplier"),
        (rf"{_START}[x\u00d7] ?{_DIGITS}", "multiplier"),
        (rf"{_NOT_IN_NUMBER}{_DIGITS}{_WORD_GAP}{_TIMES_WORDS}{_WORD_GAP}{_COMPARISONS}{_END}",
         "multiplier"),
        (rf"{_START}{_WORDS}{_WORD_GAP}{_TIMES_WORDS}{_WORD_GAP}{_COMPARISONS}{_END}",
         "multiplier"),
        (rf"{_START}{_COUNT_WORDS}{_WORD_GAP}{_TIMES_WORDS}{_WORD_GAP}{_COMPARISONS}{_END}",
         "multiplier"),
        (rf"{_NOT_IN_NUMBER}{_DIGITS}{_WORD_GAP}{_FOLD_WORDS}{_END}", "multiplier"),
        (rf"{_START}{_WORDS}{_WORD_GAP}{_FOLD_WORDS}{_END}", "multiplier"),
    )
)
_MONEY_DUAL_FORMS = {lexicon_form(word): code for word, code in words.MONEY_DUALS.items()}
_MONEY_DUALS = _lexicon(tuple(words.MONEY_DUALS))
_MULTIPLIERS = tuple(
    (_lexicon((term,)), None if value is None else Decimal(value))
    for term, value in words.MULTIPLIER_TERMS.items()
)
_PROPORTIONS = _lexicon(words.PROPORTION_TERMS)
_ANY_NUMBER = re.compile(rf"{_NOT_IN_NUMBER}{_NUMBER}")
_BARE_NUMBER = re.compile(
    rf"(?<![\d.,a-z])(?P<digits>{_NUMBER})(?![a-z\d])(?!{_WORD_GAP}{_NON_MONEY}{_END})"
)
_SMALLEST_BARE_FIGURE = 100
_SAVE_30 = re.compile(
    rf"{_START}{_alternatives(words.SAVE_WORDS)}{_WORD_GAP}30{_END}"
    rf"(?!{_WORD_GAP}{_NON_MONEY})"
)


@dataclass(frozen=True)
class _Figure:
    kind: str  # percent, money, multiplier, or bare: a large number with no unit at all
    number: Decimal | None
    start: int
    end: int
    shown: str
    unit: str | None = None  # the currency, for money. None: the text does not say

    @property
    def key(self) -> tuple[str, Decimal | None, str | None]:
        return (self.kind, self.number, self.unit)


def _phrase_value(phrase: str) -> Decimal | None:
    """خمسة وعشرين is 25, and five hundred and fifty is 550."""
    squeezed = re.sub(r"[\W_]", "", phrase)
    total = current = Decimal(0)
    position = 0
    found = False
    while position < len(squeezed):
        match = _ONE_NUMBER_WORD.match(squeezed, position)
        if match is None:
            position += 1  # an attached prefix, an ending, or "and"
            continue
        found = True
        position = match.end()
        value = Decimal(_NUMBER_WORD_VALUES[match.group()])
        if value == 100:
            current = max(current, Decimal(1)) * value
        elif value >= 1000:
            total += max(current, Decimal(1)) * value
            current = Decimal(0)
        else:
            current += value
    return total + current if found else None


def _number_in(match: re.Match[str]) -> Decimal | None:
    groups = match.groupdict()
    if groups.get("digits"):
        number = Decimal(groups["digits"].replace(",", ""))
        scale = groups.get("scale")
        if scale:
            number *= _SCALE_VALUES.get(re.sub(r"[\W_]", "", scale), 1)
        return number
    if groups.get("words"):
        return _phrase_value(groups["words"])
    return None


def _unit_in(match: re.Match[str]) -> str | None:
    groups = match.groupdict()
    symbol = groups.get("symbol")
    if symbol:
        return words.CURRENCY_SYMBOLS.get(symbol, symbol)
    unit = groups.get("unit")
    if unit:
        squeezed = re.sub(r"[\W_]", "", unit)
        return next((code for form, code in _MONEY_FORMS if form in squeezed), None)
    return None


def _is_a_year(digits: str) -> bool:
    return "," not in digits and "." not in digits and (
        1400 <= int(digits) <= 1500 or 1900 <= int(digits) <= 2100
    )


@lru_cache(maxsize=512)
def _figures(text: str) -> tuple[_Figure, ...]:
    found = []
    for pattern, kind in _FIGURE_PATTERNS:
        for match in pattern.finditer(text):
            found.append(
                _Figure(
                    kind,
                    _number_in(match),
                    match.start(),
                    match.end(),
                    match.group()[:60],
                    _unit_in(match),
                )
            )
    for match in _MONEY_DUALS.finditer(text):
        squeezed = re.sub(r"[\W_]", "", match.group())
        unit = next((code for form, code in _MONEY_DUAL_FORMS.items() if form in squeezed), None)
        found.append(_Figure("money", Decimal(2), match.start(), match.end(), match.group(), unit))
    for pattern, value in _MULTIPLIERS:
        for match in pattern.finditer(text):
            shown = match.group()[:60]
            found.append(_Figure("multiplier", value, match.start(), match.end(), shown))
    for match in _PROPORTIONS.finditer(text):
        found.append(_Figure("percent", None, match.start(), match.end(), match.group()[:60]))
    named = list(found)
    for match in _BARE_NUMBER.finditer(text):
        digits = match.group("digits")
        number = Decimal(digits.replace(",", ""))
        if number < _SMALLEST_BARE_FIGURE or _is_a_year(digits):
            continue
        if not any(item.start <= match.start() < item.end for item in named):
            found.append(_Figure("bare", number, match.start(), match.end(), digits[:60]))
    # 5 آلاف ريال also holds آلاف ريال, and ثلاث أضعاف also holds أضعاف. Only the whole one counts.
    return tuple(
        figure
        for figure in found
        if not any(
            other.number is not None
            and other.start <= figure.start
            and figure.end <= other.end
            and (other.start, other.end) != (figure.start, figure.end)
            for other in found
        )
        and (
            figure.number is not None
            or not any(
                other.number is not None
                and (other.start, other.end) == (figure.start, figure.end)
                for other in found
            )
        )
    )


def _numbers_in(text: str) -> set[Decimal]:
    numbers = {Decimal(item.replace(",", "")) for item in _ANY_NUMBER.findall(text)}
    numbers.update(figure.number for figure in _figures(text) if figure.number is not None)
    for match in re.finditer(rf"{_START}{_NUMBER_PHRASE}{_END}", text):
        value = _phrase_value(match.group())
        if value is not None:
            numbers.add(value)
    return numbers


def figures_missing_from(text: str, source_text: str) -> list[str]:
    """The figures in `text` whose number is nowhere in `source_text`. Only the number is compared,
    because a page and its paraphrase can word a unit differently."""
    stated = [figure for figure in _figures(lexicon_form(text)) if figure.number is not None]
    if not stated:
        return []
    held = _numbers_in(lexicon_form(source_text))
    return [figure.shown for figure in stated if figure.number not in held]


def _is_30_percent(figure: _Figure) -> bool:
    return figure.kind == "percent" and figure.number == 30


def _thirty_percent_hits(text: str) -> list[_Hit]:
    """R01. Decision D32 drops these figures outright, so neither a source nor a label helps."""
    hits = [
        _Hit("G2", f"a 30% figure is dropped (R01): {figure.shown!r}")
        for figure in _figures(text)
        if _is_30_percent(figure)
    ]
    saved = _SAVE_30.search(text)
    if saved:
        hits.append(_Hit("G2", f"a 30% figure is dropped (R01): {_quote(saved)}"))
    return hits


def _proved_figures(proved: Sequence[str]) -> set[tuple[str, Decimal | None, str | None]]:
    keys = set()
    for value in proved:
        keys.update(
            figure.key for figure in _figures(lexicon_form(value)) if figure.number is not None
        )
    return keys


def _has_example_label(text: str, figure: _Figure) -> bool:
    """A label only covers a figure in its own sentence."""
    stops = list(_SENTENCE_END.finditer(text))
    start = max((stop.end() for stop in stops if stop.end() <= figure.start), default=0)
    end = min((stop.start() for stop in stops if stop.start() >= figure.end), default=len(text))
    labels = [
        position
        for position in _positions(_lexicon(words.EXAMPLE_LABELS), text)
        if start <= position < end
    ]
    return _positions_near(text, [figure.start], labels, _NEAR_EXAMPLE)


def _g2(text: _Text, context: GuardrailContext) -> list[_Hit]:
    hits = _thirty_percent_hits(text.lex)
    proved = _proved_figures(context.numbers)
    for figure in _figures(text.lex):
        if _is_30_percent(figure) or figure.key in proved:
            continue
        if _has_example_label(text.lex, figure):
            continue
        hits.append(_Hit("G2", f"{figure.shown!r} has no matching fact and no example label"))
    return hits


def _value_is_stated(value: str, fact_text: str) -> bool:
    """Value and unit, as the fact words them. A plain number says nothing of what it counts, so
    it must be in the fact, and it still clears no percentage, amount or multiplier in the text."""
    wanted, fact = lexicon_form(value), lexicon_form(fact_text)
    figures = _figures(wanted)
    if not figures:
        numbers = _numbers_in(wanted)
        return bool(numbers) and numbers <= _numbers_in(fact)
    held = {figure.key for figure in _figures(fact)}
    numbers = _numbers_in(fact)
    return all(
        figure.number is not None
        and (figure.key in held or (figure.kind == "bare" and figure.number in numbers))
        for figure in figures
    )


def _check_numbers_against_facts(
    script: Script, facts: Sequence[ResearchFact]
) -> tuple[tuple[str, ...], list[_Hit]]:
    """Each entry of `numbers[]` must be stated by a fact from the URL it cites. Only those that
    are go on to clear figures in the text."""
    by_source: dict[str, list[str]] = {}
    for fact in facts:
        text = "\n".join((fact.claim, fact.paraphrase_ar, fact.paraphrase_en))
        by_source.setdefault(_url_key(fact.source_url), []).append(text)
    proved = []
    hits = []
    for number in script.numbers:
        stated_by = by_source.get(_url_key(number.source_url), [])
        if any(_value_is_stated(number.value, text) for text in stated_by):
            proved.append(number.value)
        else:
            hits.append(_Hit("G2", f"no fact from the cited source states {number.value}"))
    return tuple(proved), hits


# --- G3: research is cited, not copied -----------------------------------------------------


def _url_key(url: str) -> str:
    parts = urlsplit(url)
    return f"{parts.netloc.casefold()}{parts.path.rstrip('/')}?{parts.query}"


def _word_runs(text: str, length: int) -> set[tuple[str, ...]]:
    found = _WORD.findall(lexicon_form(text))
    return {tuple(found[start : start + length]) for start in range(len(found) - length + 1)}


def _spoken_and_shown_text(script: Script) -> list[tuple[str, str]]:
    return [
        ("hook_ar", script.hook_ar),
        ("voice_script", script.voice_script),
        *((f"on_screen_en[{i}]", item) for i, item in enumerate(script.on_screen_en)),
        ("subtitles_en", script.subtitles_en),
        ("caption_ar", script.caption_ar),
        ("caption_en", script.caption_en),
    ]


class _HasText(Protocol):
    text: str


def _excerpt_text(excerpt: str | _HasText) -> str:
    return excerpt if isinstance(excerpt, str) else excerpt.text


def check_research_use(
    script: Script,
    *,
    facts: Sequence[ResearchFact],
    excerpts: Sequence[str | _HasText],
    max_copied_words: int,
) -> list[GuardrailFinding]:
    """Plain inputs, so this needs nothing from the research step. Spec Section 6.4 calls an
    overlap of `max_copied_words` consecutive words a long one, so that length itself fails.

    What this can prove depends on the route. Under `claude_cli`, WebFetch hands back what a small
    model made of the page, so an excerpt is a summary, not the page. A pass then proves the script
    copies no long run from that summary. It cannot prove the script copies nothing from the page
    itself, and a citation only proves the URL was fetched (spec Section 6.4)."""
    hits: list[tuple[str, _Hit]] = []
    known = {_url_key(fact.source_url) for fact in facts}
    for source in script.sources:
        if _url_key(source.url) not in known:
            hits.append(("sources", _Hit("G3", f"{source.url[:200]} is not in the research")))
    for number in script.numbers:
        if _url_key(number.source_url) not in known:
            message = f"{number.value} cites {number.source_url[:200]}, not in the research"
            hits.append(("numbers", _Hit("G3", message)))

    copied: set[tuple[str, ...]] = set()
    for excerpt in excerpts:
        copied |= _word_runs(_excerpt_text(excerpt), max_copied_words)
    message = f"{max_copied_words} or more words in a row copied from a source"
    for location, text in _spoken_and_shown_text(script):
        if _word_runs(BRAND_TOKEN.sub(" ", text), max_copied_words) & copied:
            hits.append((location, _Hit("G3", message)))
    for fact in facts:
        for text in (fact.paraphrase_ar, fact.paraphrase_en):
            if _word_runs(text, max_copied_words) & copied:
                hits.append(("facts", _Hit("G3", f"a paraphrase of {fact.publisher}: {message}")))
    return [_finding(hit, location) for location, hit in hits]


# --- G4 to G10 -----------------------------------------------------------------------------


_SMS_WITH_DIGITS = re.compile(rf"{_START}{_term_body('sms')}\d")


def _g4(text: _Text, context: GuardrailContext) -> list[_Hit]:
    searched = text.lex
    if _C18 in context.claim_ids:
        claim = context.claims().claims[_C18]
        for wording in (claim.wording_ar, claim.wording_en):
            searched = searched.replace(lexicon_form(wording).rstrip("."), " ")
    found = _lexicon(words.SMS_TERMS).search(searched) or _SMS_WITH_DIGITS.search(searched)
    if found:
        return [_Hit("G4", f"only the approved no-SMS claim may mention this: {_quote(found)}")]
    messages = _lexicon(words.MESSAGE_TERMS)
    if _near(searched, messages, _lexicon(words.BANK_WORDS), _NEAR_MESSAGE) or _near(
        searched, messages, _lexicon(words.MESSAGE_READING_TERMS), _NEAR_MESSAGE
    ):
        return [_Hit("G4", "implies that the app reads messages or alerts")]
    return []


_THOUSAND_WORDS = _alternatives(("thousand", "k", "الف", "الاف"))
_CALENDAR = _alternatives(words.CALENDAR_MONTHS)
_NAMED_MONTH = rf"{_WORD_GAP}(?:(?:of|من){_WORD_GAP})?{_CALENDAR}{_END}"
_COUNTS_SOMETHING = rf" (?!(?:of|every|each|to|and|is){_END})[a-z]{{2,}}"  # the 27 items you bought
_BARE_27 = re.compile(
    rf"{_NOT_IN_NUMBER}27(?!\d)(?!{_WORD_GAP}{_NON_MONEY}{_END})"
    rf"(?!{_WORD_GAP}{_THOUSAND_WORDS}{_END})(?!{_NAMED_MONTH})(?!{_COUNTS_SOMETHING})"
)
_DATE_27 = re.compile(
    rf"{_START}(?:the|on|day|يوم|بتاريخ){_WORD_GAP}27(?!\d)(?!{_NAMED_MONTH})"
    rf"(?!{_COUNTS_SOMETHING})"
)


def _with_only_27(text: str) -> str:
    """27,000 is a sum and 2.27 is a price, so neither may read as the 27th."""
    return _ANY_NUMBER.sub(lambda match: match.group() if match.group() == "27" else " ", text)


def _g5(text: _Text, context: GuardrailContext) -> list[_Hit]:
    hits = []
    fixed = _lexicon(words.FIXED_27_TERMS)
    salary = _lexicon(words.SALARY_TERMS)
    searched = _with_only_27(text.lex)
    # Across the whole text, because "Payday! 27!" is one statement in two sentences.
    tied_to_salary = _near(searched, _BARE_27, salary, _NEAR_SALARY)
    for sentence in _sentences(searched):
        states_27 = fixed.search(sentence) or _DATE_27.search(sentence)
        if not (states_27 or (tied_to_salary and _BARE_27.search(sentence))):
            continue
        says_default_and_change = (
            _lexicon(words.DEFAULT_WORDS).search(sentence)
            and _lexicon(words.CHANGE_WORDS).search(sentence)
            and not _lexicon(words.CANNOT_WORDS).search(sentence)
        )
        if not says_default_and_change:
            hits.append(_Hit("G5", f"payday is per household, not a fixed 27th: {sentence[:80]!r}"))
    return hits


_RATIO = re.compile(rf"(?<![\d/])(\d{{1,3}}){_WORD_GAP}[/:\-]{_WORD_GAP}(\d{{1,3}})(?![\d/])")


def _ratio_positions(text: str) -> list[int]:
    return [
        match.start()
        for match in _RATIO.finditer(text)
        if int(match.group(1)) + int(match.group(2)) == 100
    ]


def _g6(text: _Text, context: GuardrailContext) -> list[_Hit]:
    spouse = _lexicon(words.SPOUSE_TERMS)
    split = _lexicon(words.SPLIT_TERMS)
    ratios = _ratio_positions(text.lex)
    percentages = [figure.start for figure in _figures(text.lex) if figure.kind == "percent"]
    spouses = _positions(spouse, text.lex)
    splits = _positions(split, text.lex)
    if _positions_near(text.lex, [*splits, *ratios, *percentages], spouses, _NEAR_SPOUSE):
        return [_Hit("G6", "no percentage split between spouses. Split wording is for roommates")]
    if context.family and (splits or ratios):
        return [_Hit("G6", "split wording has no place in a family reel")]
    return []


_FULL_STOP = re.compile(r"\n+|\.(?!\d)")


def _g7(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    hits = []
    burden = _lexicon(words.WIFE_BURDEN_PHRASES).search(text.lex)
    if burden:
        hits.append(_Hit("G7", f"against family rules 1 to 4: {_quote(burden)}"))
    freed = _lexicon(words.NOT_HER_OBLIGATION).sub(" ", text.lex)
    # Only a full stop ends the thought here, because "Your wife? Must pay." is one statement.
    for sentence in _FULL_STOP.split(freed):
        obliged = (
            _lexicon(words.WIFE_TERMS).search(sentence)
            and _lexicon(words.OBLIGATION_TERMS).search(sentence)
            and _lexicon(words.PAY_TERMS).search(sentence)
        )
        if obliged:
            hits.append(_Hit("G7", f"never imply she should pay: {sentence[:80]!r}"))
    for sentence in _sentences(text.lex):
        contribution = _lexicon(words.WIFE_CONTRIBUTION_PHRASES).search(sentence)
        if contribution and not _lexicon(words.VOLUNTARY_WORDS).search(sentence):
            hits.append(_Hit("G7", f"her contribution is voluntary: {_quote(contribution)}"))
    return hits


_CLAUSE_BREAK = re.compile(r"[,;:\u060c\u061b]")
_APR_AS_MONTH = re.compile(
    rf"{_START}(?:in|on|by|from|until|to|next|last|this){_WORD_GAP}apr{_END}"
    rf"|{_START}apr{_WORD_GAP}(?:(?:or|and|to){_END}|\d)"
    rf"|\d{_WORD_GAP}apr{_END}"
)


def _g8(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    """A warning only clears the clause it stands in, so "Don't wait, get a loan" still sells."""
    hits = []
    interest = _lexicon(words.INTEREST_TERMS)
    bnpl = _lexicon(words.BNPL_TERMS)
    promotion = _lexicon(words.PROMOTION_TERMS)
    warning = _lexicon(words.WARNING_TERMS)
    false_warning = _lexicon(words.FALSE_WARNINGS)
    searched = _lexicon(words.INTEREST_HARMLESS).sub(" ", _APR_AS_MONTH.sub(" ", text.lex))
    for sentence in _sentences(searched):
        rest = false_warning.sub(" ", sentence)
        sold = bool(false_warning.search(sentence)) or bool(promotion.search(rest))
        warned = bool(warning.search(rest))
        for clause in _CLAUSE_BREAK.split(rest):
            found = interest.search(clause)
            plan = bnpl.search(clause)
            if not found and not plan:
                continue
            clause_sells = promotion.search(clause) and not warning.search(clause)
            if clause_sells or (sold and not warned):
                named = _quote(found or plan)
                hits.append(_Hit("G8", f"promotes an interest-based product: {named}"))
            elif found:
                hits.append(
                    _Hit("G8", f"neutral mention, for the owner: {_quote(found)}", soft=True)
                )
    return hits


def _g9(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    searched = _lexicon(words.BEFORE_BUYING).sub(" ", text.lex)
    found = _lexicon(words.PERSONAL_ADVICE_TERMS).search(searched)
    if found:
        return [_Hit("G9", f"personalised advice: {_quote(found)}")]
    if _near(searched, _lexicon(words.BUYING_TERMS), _lexicon(words.ASSET_TERMS), _NEAR_ASSET):
        return [_Hit("G9", "telling a viewer to buy an asset is personalised advice")]
    return []


def _g10(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    authority = _lexicon(words.AUTHORITY_TERMS)
    certified = _lexicon(words.CERTIFIED_TERMS)
    if _near(text.lex, authority, certified, _NEAR_AUTHORITY):
        return [_Hit("G10", "no certification or endorsement claims: nothing supports them")]
    return []


# --- G11: availability and CTA -------------------------------------------------------------


_URL_PREFIX = re.compile(r"(?:(?:https?|hxxps?)[:/]|www\.)[^\s]*")
_DOMAIN = re.compile(
    r"(?<![@#\w.\-])[a-z0-9\-]{1,63}(?:\.[a-z0-9\-]{1,63})*\.(?:"
    + "|".join(words.URL_TLDS)
    + rf"){_END}"
)
_SHORT_LINK = re.compile(r"(?<![@#\w.\-])[a-z0-9\-]{1,63}\.[a-z]{2,24}/\S*")


def _g11(text: _Text, context: GuardrailContext) -> list[_Hit]:
    hits = []
    allowed_url = lexicon_form(context.landing_url) if context.landing_url else None
    for pattern in (_URL_PREFIX, _DOMAIN, _SHORT_LINK):
        for match in pattern.finditer(text.lex):
            if allowed_url is None or match.group() not in allowed_url:
                hits.append(_Hit("G11", f"no link of any kind: {_quote(match)}"))
    spoken_dot = _lexicon(words.SPOKEN_DOT_WORDS).search(text.lex)
    if spoken_dot and allowed_url is None:
        hits.append(_Hit("G11", f"no link of any kind: {_quote(spoken_dot)}"))
    if allowed_url is None:
        link = _lexicon(words.LINK_WORDING).search(text.lex)
        if link:
            hits.append(_Hit("G11", f"no link wording while the URL is empty: {_quote(link)}"))
    if context.cta_mode != "store":
        for terms in (words.DOWNLOAD_WORDING, words.STORE_WORDING, words.AVAILABILITY_WORDING):
            found = _lexicon(terms).search(text.lex)
            if found:
                hits.append(_Hit("G11", f"not available yet, so not {_quote(found)}"))
    return hits


# --- G12 and G18: the brand ----------------------------------------------------------------


_NAME_GAP = r"[ _.\-]{0,3}"
_AR_FIRST = lexicon_form(FULL_NAME_AR.split()[0])
_AR_SECOND = lexicon_form(FULL_NAME_AR.split()[1])
_EN_FIRST, _EN_SECOND = lexicon_form(FULL_NAME_EN).split()
_FULL_NAME = re.compile(
    rf"{_START}{_AR_PREFIX}{_AR_FIRST}{_NAME_GAP}{_AR_SECOND}{_END}"
    rf"|{_START}{_EN_FIRST}{_NAME_GAP}{_EN_SECOND}{_END}"
)
_NOT_AFTER_A_LETTER = r"(?<![^\W\d_])"  # a digit in front of the name does not make it another word
_AR_NAME = _LETTER_GAP.join(
    f"{re.escape(ch)}{{1,2}}" if ch == "\u0627" else re.escape(ch) for ch in _AR_FIRST
)
_BARE_AR = re.compile(
    rf"{_NOT_AFTER_A_LETTER}[\u0648\u0641\u0628\u0644\u0643]{{0,3}}(?:\u0627\u0644)?{_AR_NAME}"
    rf"(?:\u0627|{_AR_ENDING}){_END}"
)
_BARE_EN = re.compile(
    rf"{_NOT_AFTER_A_LETTER}q{_LETTER_GAP}[a4@i]{{0,2}}{_LETTER_GAP}w{{1,2}}{_LETTER_GAP}"
    rf"[a4@]{{1,2}}{_LETTER_GAP}m"
)
_FAMILY_HEADSHIP = re.compile(
    f"{_START}{_alternatives(words.FAMILY_HEADSHIP_WORDS, form=brand_form)}{_END}"
)
_BRAND_MENTION = re.compile(f"{_TOKEN_MARK}|{_FULL_NAME.pattern}|{_BARE_AR.pattern}")
_STRAY_TOKEN = re.compile(rf"[{{}}]|brand_?(?:ar|en|hashtag){_END}")


def _bare_name(form: str) -> re.Match[str] | None:
    """The full name is taken out first, so whatever is left of it stands alone."""
    rest = _FULL_NAME.sub(" ", form)
    return _BARE_AR.search(rest) or _BARE_EN.search(rest)


def _g18(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    hits = []
    bare = _bare_name(text.brand)
    if bare:
        hits.append(_Hit("G18", f"always the full name, never {_quote(bare)}"))
    body = _lexicon(words.BODY_SHAPE_TERMS)
    if _near(text.lex, _BRAND_MENTION, body, _NEAR_BRAND):
        hits.append(_Hit("G18", "body-shape wording near the name. Keep it clearly about money"))
    headship = _FAMILY_HEADSHIP.search(text.brand)
    if headship:
        hits.append(_Hit("G18", f"another word, for the owner: {_quote(headship)}", soft=True))
    return hits


def _token_order_hits(text: _Text, context: GuardrailContext) -> list[_Hit]:
    if context.hashtag and re.search(r"\{brand_(?:ar|en)\}", text.raw):
        return [_Hit("G12", "a hashtag can only use {brand_hashtag}")]
    if context.language is None:
        return []
    first, second = (
        ("{brand_ar}", "{brand_en}") if context.language == "ar" else ("{brand_en}", "{brand_ar}")
    )
    rest = text.raw.replace(f"{first} {second}", " ")
    if second in rest or (first in rest and not context.spoken):
        return [_Hit("G12", f"{context.language} text shows {first} {second}, in that order")]
    return []


def _name_order_hits(text: _Text, context: GuardrailContext) -> list[_Hit]:
    brand = context.brand
    if brand is None or context.language is None:
        return []
    arabic, english = lexicon_form(brand.name_ar), lexicon_form(brand.name_en)
    first, second = (arabic, english) if context.language == "ar" else (english, arabic)
    rest = text.lex.replace(f"{first} {second}", " ")
    if second in rest or (first in rest and not context.spoken):
        return [_Hit("G12", f"{context.language} text shows {first} {second}, in that order")]
    return []


def _g12(text: _Text, context: GuardrailContext) -> list[_Hit]:
    hits = []
    if contains_withdrawn_name(text.raw):
        hits.append(_Hit("G12", "the withdrawn brand name (D1)"))
    old_name = _lexicon(words.OLD_APP_NAMES).search(text.lex)
    if old_name:
        hits.append(_Hit("G12", f"not the brand: {_quote(old_name)}"))
    if context.stage == "script":
        rest = BRAND_TOKEN.sub(" ", text.raw)
        if _STRAY_TOKEN.search(lexicon_form(rest)):
            hits.append(_Hit("G12", "only {brand_ar}, {brand_en} and {brand_hashtag} are tokens"))
        literal = _FULL_NAME.search(text.brand) or _bare_name(text.brand)
        if literal:
            hits.append(_Hit("G12", f"scripts use tokens, not the name: {_quote(literal)}"))
        for name in context.other_brand_names:
            if lexicon_form(name) in text.lex:
                hits.append(_Hit("G12", f"scripts use tokens, not {name!r}"))
        hits += _token_order_hits(text, context)
    else:
        hits += _name_order_hits(text, context)
        shown = context.brand
        if shown is not None and shown.is_test:
            literal = _FULL_NAME.search(text.brand) or _bare_name(text.brand)
            if literal:
                hits.append(_Hit("G12", "a test reel must not show the real name"))
    return hits


# --- G13, G14, G17 -------------------------------------------------------------------------


_NAMED_RIVALS = (
    words.STORE_NAMES
    + words.BANK_AND_WALLET_NAMES
    + words.NAMES_ONLY_WHEN_COMPARED
    + words.COMPETING_APPS
)


def _without_lookalike_stores(text: str) -> str:
    return _lexicon(words.NOT_A_STORE_NAME).sub(" ", text)


def _g13(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    hits = []
    if _near(
        _without_lookalike_stores(text.lex),
        _lexicon(_NAMED_RIVALS),
        _lexicon(words.COMPARISON_TERMS),
        _NEAR_COMPARISON,
    ):
        hits.append(_Hit("G13", "no named bank, chain or app shown as better or cheaper"))
    generic = _lexicon(words.GENERIC_APP_COMPARISONS).search(text.lex)
    if generic:
        hits.append(_Hit("G13", f"no comparison with other apps: {_quote(generic)}"))
    return hits


def _g14(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    hits = []
    found = _lexicon(words.PRIVACY_OVERCLAIMS).search(text.lex)
    if found:
        hits.append(_Hit("G14", f"receipt photos go to an AI service: {_quote(found)}"))
    for sentence in _sentences(text.lex):
        on_device = _lexicon(words.ON_DEVICE_TERMS).search(sentence)
        photo = _lexicon(words.RECEIPT_PHOTO_TERMS).search(sentence)
        if on_device and photo and not _lexicon(words.QR_TERMS).search(sentence):
            hits.append(_Hit("G14", f"only QR decoding runs on the device: {sentence[:80]!r}"))
    return hits


def _g17(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    found = _lexicon(words.VOICE_REALNESS_CLAIMS).search(text.lex)
    return [_Hit("G17", f"the voice is synthetic: {_quote(found)}")] if found else []


# --- G19 to G22 ----------------------------------------------------------------------------


def _g19(text: _Text, context: GuardrailContext) -> list[_Hit]:
    hits = []
    store = _lexicon(words.STORE_NAMES).search(_without_lookalike_stores(text.lex))
    if store:
        hits.append(_Hit("G19", f"no store names: {_quote(store)}"))
    saving = _lexicon(words.BASKET_SAVING_TERMS)
    found = saving.search(text.lex)
    tied_to_basket = context.basket or _near(
        text.lex, _lexicon(words.BASKET_TERMS), saving, _NEAR_BASKET
    )
    if found and tied_to_basket:
        hits.append(_Hit("G19", f"no real saving and no cheaper store: {_quote(found)}"))
    return hits


def _g20(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    hits = []
    name = _lexicon(words.BANK_AND_WALLET_NAMES).search(text.lex)
    if name:
        hits.append(_Hit("G20", f"no bank or wallet names: {_quote(name)}"))
    feature = _lexicon(words.BANK_FEATURE_PHRASES).search(text.lex)
    if feature:
        hits.append(_Hit("G20", f"there is no bank feature: {_quote(feature)}"))
    bank = _lexicon(words.BANK_WORDS)
    contrast = _lexicon(words.COMPARISON_TERMS + words.BANK_CONTRAST_TERMS)
    # Close by, because "Best practice: check your bank statement" compares nothing with a bank.
    without_allowances = _lexicon(words.ALLOWANCE_PHRASES).sub(" ", text.lex)
    if _near(without_allowances, bank, contrast, _NEAR_BANK_CONTRAST):
        hits.append(_Hit("G20", "no comparison or contrast with banks"))
    plain = bank.search(text.lex)
    if plain:
        hits.append(_Hit("G20", f"the word bank, for the owner: {_quote(plain)}", soft=True))
    return hits


def _without_qr_denials(text: str) -> str:
    return _lexicon(words.QR_DENIALS).sub(" ", text)


def _g21(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    hits = []
    market = _lexicon(words.MARKET_PRICE_TERMS).search(text.lex)
    if market:
        hits.append(_Hit("G21", f"there is no market data: {_quote(market)}"))
    searched = _without_qr_denials(text.lex)
    qr = _lexicon(words.QR_TERMS + words.QR_ALIASES)
    if _near(searched, qr, _lexicon(words.PRICE_TRACKING_TERMS), _NEAR_QR):
        hits.append(_Hit("G21", "price tracking uses line items from your own receipts, not QR"))
    return hits


_ACTION_UNITS = _alternatives(words.ACTION_UNITS)
_ARABIC_UNITS = _alternatives(unit for unit in words.ACTION_UNITS if _is_arabic(unit[0]))
_ARABIC_COUNTS = _alternatives(word for word in words.COUNT_WORDS if _is_arabic(word[0]))
_COUNT_THEN_UNIT = re.compile(
    rf"(?:{_NOT_IN_NUMBER}\d+|{_START}{_COUNT_WORDS}){_WORD_GAP}{_ACTION_UNITS}{_END}"
)
_UNIT_THEN_COUNT = re.compile(rf"{_START}{_ARABIC_UNITS}{_WORD_GAP}{_ARABIC_COUNTS}{_END}")
_UNIT_N_TIMES = re.compile(rf"{_START}{_ACTION_UNITS}{_WORD_GAP}\d+{_WORD_GAP}{_TIMES_WORDS}{_END}")


def _g22(text: _Text, _context: GuardrailContext) -> list[_Hit]:
    for pattern in (
        _COUNT_THEN_UNIT,
        _UNIT_THEN_COUNT,
        _UNIT_N_TIMES,
        _lexicon(words.ACTION_COUNT_PHRASES),
    ):
        found = pattern.search(text.lex)
        if found:
            return [_Hit("G22", f"no click or tap counts, none was measured: {_quote(found)}")]
    return []


_TEXT_RULES = (
    _g1,
    _g2,
    _g4,
    _g5,
    _g6,
    _g7,
    _g8,
    _g9,
    _g10,
    _g11,
    _g12,
    _g13,
    _g14,
    _g17,
    _g18,
    _g19,
    _g20,
    _g21,
    _g22,
)


# --- Reports -------------------------------------------------------------------------------


def _finding(hit: _Hit, location: str) -> GuardrailFinding:
    return GuardrailFinding(
        rule=hit.rule, source="deterministic", location=location, message=hit.message[:2000]
    )


def _text_findings(
    text: str, context: GuardrailContext, location: str
) -> list[tuple[GuardrailFinding, bool]]:
    prepared = _prepare(text)
    return [
        (_finding(hit, location), hit.soft)
        for rule in _TEXT_RULES
        for hit in rule(prepared, context)
    ]


def _report(found: Iterable[tuple[GuardrailFinding, bool]]) -> GuardrailReport:
    """One line per rule and place. A report past the schema's limit is cut, and it still fails."""
    seen = set()
    hard: list[GuardrailFinding] = []
    flags: list[GuardrailFinding] = []
    for finding, is_soft in found:
        key = (finding.rule, finding.location, is_soft)
        if key in seen:
            continue
        seen.add(key)
        (flags if is_soft else hard).append(finding)
    return GuardrailReport(
        passed=not hard, hard_failures=hard[:_MAX_FINDINGS], soft_flags=flags[:_MAX_FINDINGS]
    )


def check_text(
    text: str, context: GuardrailContext | None = None, location: str = "text"
) -> GuardrailReport:
    """Every rule that reads text, on one piece of it."""
    return _report(_text_findings(text, context or GuardrailContext(), location))


def check_caption_words(
    caption_words: Sequence[str], context: GuardrailContext | None = None
) -> GuardrailReport:
    """Word-by-word captions show one token at a time, so قوام followed by المال on the next
    token still shows the bare name. Each token must hold the whole name, and the words also
    run through every rule together, so no rule can be split across tokens."""
    context = context or GuardrailContext(stage="filled")
    found: list[tuple[GuardrailFinding, bool]] = []
    for index, word in enumerate(caption_words):
        bare = _bare_name(brand_form(word))
        if bare:
            hit = _Hit("G18", f"the name must stay in one token, not {_quote(bare)}")
            found.append((_finding(hit, f"caption_words[{index}]"), False))
    found += _text_findings(" ".join(caption_words), context, "caption_words")
    return _report(found)


def _with_cta_settings(context: GuardrailContext, config: EngineConfig) -> GuardrailContext:
    return replace(context, cta_mode=config.cta.mode, landing_url=config.cta.landing_url)


def _disclosure_hits(text: str, config: EngineConfig) -> list[_Hit]:
    if lexicon_form(config.captions.ai_voice_disclosure) not in lexicon_form(text):
        return [_Hit("G17", "the caption is missing the AI voice disclosure line")]
    return []


def check_final_caption(
    text: str,
    language: Language,
    config: EngineConfig,
    brand: ReelBrand,
    context: GuardrailContext | None = None,
) -> GuardrailReport:
    """The caption as it will be posted, with the brand filled in (G11, G12, G17, G18)."""
    return _report(_final_caption_findings(text, language, config, brand, context))


def _final_caption_findings(
    text: str,
    language: Language,
    config: EngineConfig,
    brand: ReelBrand,
    context: GuardrailContext | None,
    location: str = "caption",
) -> list[tuple[GuardrailFinding, bool]]:
    base = _with_cta_settings(context or GuardrailContext(), config)
    filled = replace(base, stage="filled", language=language, brand=brand)
    found = _text_findings(text, filled, location)
    found += [(_finding(hit, location), False) for hit in _disclosure_hits(text, config)]
    return found


def check_bio(
    text: str, language: Language, config: EngineConfig, brand: ReelBrand
) -> GuardrailReport:
    """Bios use only the approved wording, with the brand filled in (spec Section 6.7)."""
    context = _with_cta_settings(
        GuardrailContext(stage="filled", language=language, brand=brand), config
    )
    found = _text_findings(text, context, "bio")
    approved = fill_tokens(getattr(active_wording(config), f"bio_{language}"), brand)
    if lexicon_form(text) != lexicon_form(approved):
        hit = _Hit("G11", "a bio uses only the approved wording in spec Section 6.7")
        found.append((_finding(hit, "bio"), False))
    return _report(found)


def check_cta_line(
    text: str, language: Language, config: EngineConfig, brand: ReelBrand, *, spoken: bool = False
) -> GuardrailReport:
    """A CTA or bio line once filled: every text rule, at the filled stage."""
    context = _with_cta_settings(
        GuardrailContext(stage="filled", language=language, spoken=spoken, brand=brand), config
    )
    return check_text(text, context, "cta")


# --- A whole script ------------------------------------------------------------------------


def _is_family(script: Script, all_text: str) -> bool:
    return (
        _C11 in script.claim_ids
        or script.feature_clip_folder == _NAFAQAH_FOLDER
        or bool(_lexicon(words.NAFAQAH_NAMES).search(all_text))
    )


def _is_basket(script: Script, all_text: str) -> bool:
    return (
        _C21 in script.claim_ids
        or script.feature_clip_folder == _SMART_BASKET_FOLDER
        or bool(_lexicon(words.SMART_BASKET_NAMES).search(all_text))
    )


def _script_stage_findings(
    script: Script, base: GuardrailContext, config: EngineConfig
) -> list[tuple[GuardrailFinding, bool]]:
    """The engine's own closing lines are taken out first: they are not the writer's statement."""
    found = []
    voice = without_engine_lines(script.voice_script, config)
    for location, text, changes in (
        ("hook_ar", script.hook_ar, {"language": "ar"}),
        ("voice_script", voice, {"language": script.language, "spoken": True}),
        ("subtitles_en", script.subtitles_en, {"language": "en"}),
        ("caption_ar", without_engine_lines(script.caption_ar, config), {"language": "ar"}),
        ("caption_en", without_engine_lines(script.caption_en, config), {"language": "en"}),
    ):
        found += _text_findings(text, replace(base, **changes), location)
    # A viewer hears the hook and then the voice, so a rule must hold across the two.
    found += _text_findings(f"{script.hook_ar} {voice}", base, "hook_and_voice")

    on_screen = replace(base, language="en")
    for index, item in enumerate(script.on_screen_en):
        found += _text_findings(item, on_screen, f"on_screen_en[{index}]")
    found += _text_findings(" ".join(script.on_screen_en), base, "on_screen_en")

    hashtag = replace(base, hashtag=True)
    for index, item in enumerate(script.hashtags):
        found += _text_findings(item, hashtag, f"hashtags[{index}]")
    found += _text_findings(" ".join(script.hashtags), hashtag, "hashtags")
    return found


def _filled_stage_findings(
    script: Script,
    base: GuardrailContext,
    config: EngineConfig,
    brand: ReelBrand,
) -> list[tuple[GuardrailFinding, bool]]:
    filled = replace(base, stage="filled", brand=brand)
    found = _final_caption_findings(
        compose_caption(script.caption_ar, "ar", config, brand), "ar", config, brand, base,
        "caption_ar",
    )
    found += _final_caption_findings(
        compose_caption(script.caption_en, "en", config, brand), "en", config, brand, base,
        "caption_en",
    )
    voice = compose_voice(script.voice_script, script.language, config, brand)
    found += _text_findings(
        voice, replace(filled, language=script.language, spoken=True), "voice_script"
    )
    for location, text, language in (
        ("hook_ar", script.hook_ar, "ar"),
        ("subtitles_en", script.subtitles_en, "en"),
        *((f"on_screen_en[{i}]", item, "en") for i, item in enumerate(script.on_screen_en)),
    ):
        found += _text_findings(
            fill_tokens(text, brand), replace(filled, language=language), location
        )
    for index, item in enumerate(script.hashtags):
        found += _text_findings(
            fill_tokens(item, brand), replace(filled, hashtag=True), f"hashtags[{index}]"
        )
    return found


def check_script(
    script: Script,
    *,
    config: EngineConfig,
    brand: ReelBrand,
    register: ClaimsRegister | None = None,
    facts: Sequence[ResearchFact] = (),
    excerpts: Sequence[str | _HasText] = (),
) -> GuardrailReport:
    """Every deterministic rule on a script, as written and again with the brand filled in."""
    register = register or load_claims_register()
    all_text = lexicon_form(
        "\n".join(text for _, text in _spoken_and_shown_text(script)) + "\n"
        + "\n".join(script.hashtags)
    )
    proved, number_hits = _check_numbers_against_facts(script, facts)
    claim_wording = tuple(
        wording
        for claim_id in script.claim_ids
        if claim_id in register.claims and register.claims[claim_id].code_check == "supported"
        for wording in (register.claims[claim_id].wording_ar, register.claims[claim_id].wording_en)
    )
    base = GuardrailContext(
        numbers=(*proved, *claim_wording),
        claim_ids=frozenset(script.claim_ids),
        basket=_is_basket(script, all_text),
        family=_is_family(script, all_text),
        cta_mode=config.cta.mode,
        landing_url=config.cta.landing_url,
        other_brand_names=(config.test_brand.name_ar, config.test_brand.name_en),
        register=register,
    )
    found = _script_stage_findings(script, base, config)

    for hit in (
        *_claim_hits(script.claim_ids, register),
        *_clip_hits(script.feature_clip_folder, script.claim_ids, register),
    ):
        found.append((_finding(hit, "claim_ids"), False))
    found += [(_finding(hit, "numbers"), False) for hit in number_hits]
    for number in script.numbers:
        for hit in _thirty_percent_hits(lexicon_form(number.value)):
            found.append((_finding(hit, "numbers"), False))
    found += [
        (finding, False)
        for finding in check_research_use(
            script,
            facts=facts,
            excerpts=excerpts,
            max_copied_words=config.guardrails.max_copied_words,
        )
    ]

    try:
        found += _filled_stage_findings(script, base, config, brand)
    except UnknownTokenError:
        pass  # already a G12 failure at the script stage, and there is nothing to fill
    return _report(found)
