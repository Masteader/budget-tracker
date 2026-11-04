"""Checks for text that ends up on screen, shared by `Script` and `RenderProps`.

Reels never show real account data (spec Section 5.2), so text that looks like an IBAN, a
phone number, a card number or an email is refused. These are safety nets for mistakes and
for model output. Whether a number is true stays the job of guardrail G2.

Lengths are checked first, so no later step has to cope with a huge string. These checks
are validators rather than schema constraints, which keeps the JSON schema simple enough to
send to Claude as a structured-output format.
"""

from __future__ import annotations

import re
import unicodedata

from pydantic import AfterValidator

# Direction marks and joiners are normal in Arabic text, as long as real text surrounds them.
_ALLOWED_FORMAT_CHARACTERS = {"\u200c", "\u200d", "\u200e", "\u200f"}
_IBAN = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]{2}\d{2}(?:[ -]?[A-Za-z0-9]){11,30}(?![A-Za-z0-9])")
_MIN_DIGITS_IN_IBAN = 10
# A run of nine digits is a Saudi mobile number with its leading 0 dropped, so the run also
# catches account and card numbers. Grouping commas are not separators, so 1,250 is fine.
_LONG_DIGIT_RUN = re.compile(r"(?<!\d)(?:\+?\d[\s\-.()]{0,2}){9,}")


def _looks_like_email(text: str) -> bool:
    for word in text.split():
        before, at, after = word.partition("@")
        if at and before and "." in after:
            return True
    return False


def _account_data_found(text: str) -> str | None:
    # \d also matches Arabic-Indic digits, so these patterns cover both digit forms.
    for match in _IBAN.finditer(text):
        # Ordinary words can fit the IBAN shape, as in "FY26 budget plan here". An IBAN cannot
        # be that short of digits.
        if sum(ch.isdigit() for ch in match.group()) >= _MIN_DIGITS_IN_IBAN:
            return "an IBAN"
    if _LONG_DIGIT_RUN.search(text):
        return "a phone or account number"
    if _looks_like_email(text):
        return "an email address"
    return None


def _hidden_character_found(text: str) -> str | None:
    for ch in text:
        category = unicodedata.category(ch)
        if category == "Cc" and ch != "\n":
            return f"control character U+{ord(ch):04X}"
        if category in {"Cs", "Co", "Cn"}:
            return f"unassigned character U+{ord(ch):04X}"
        if category == "Cf" and ch not in _ALLOWED_FORMAT_CHARACTERS:
            return f"hidden character U+{ord(ch):04X}"
    return None


def bounded_text(max_chars: int) -> AfterValidator:
    """Visible text within a length limit. For internal text that may quote anything."""

    def check(value: str) -> str:
        if len(value) > max_chars:
            raise ValueError(f"longer than {max_chars} characters")
        if not any(ch.isalnum() for ch in value):
            raise ValueError("has no visible text")
        return value

    return AfterValidator(check)


def display_text(max_chars: int) -> AfterValidator:
    """Text that will be seen or heard in a reel."""
    bounded = bounded_text(max_chars).func

    def check(value: str) -> str:
        bounded(value)
        hidden = _hidden_character_found(value)
        if hidden:
            raise ValueError(f"contains a {hidden}")
        found = _account_data_found(value)
        if found:
            raise ValueError(f"looks like it holds {found}, and reels never show account data")
        return value

    return AfterValidator(check)


def at_most(max_items: int) -> AfterValidator:
    def check(value: list) -> list:
        if len(value) > max_items:
            raise ValueError(f"more than {max_items} items")
        return value

    return AfterValidator(check)
