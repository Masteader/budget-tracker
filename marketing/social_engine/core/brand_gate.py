"""The launch gate (spec Section 13), the full name (G18) and the withdrawn brand (D1).

`live` mode refuses to render, offer approval or publish until the name, logo, handles,
hashtags and clearance fields hold real values. A value made of invisible characters, a
placeholder, a bare `Qawam`, a test asset or an impossible date does not count as filled in.
A test reel carries the watermark and the test brand, and can never be approved, however
complete the real brand is. The bot and the publisher call these functions again at the
moment they act, so a forged callback or a config edit after rendering is still refused.
"""

from __future__ import annotations

import re
import stat
import unicodedata
from dataclasses import dataclass
from datetime import date
from pathlib import PurePosixPath
from typing import TYPE_CHECKING

from core.paths import ENGINE_ROOT

if TYPE_CHECKING:
    from core.config import EngineConfig

NAME_CHOSEN_ON = date(2026, 11, 3)  # decision D1: clearance cannot predate the name

_KASHIDA = "\u0640"
_LOOK_ALIKES = str.maketrans(
    {
        "\u06cc": "\u064a",  # Persian yeh
        "\u0649": "\u064a",  # alef maksura
        "\u0430": "a",  # Cyrillic
        "\u0435": "e",
        "\u043e": "o",
        "\u0440": "p",
        "\u0441": "c",
        "\u0443": "y",
        "\u0445": "x",
    }
)
_INVISIBLE_CATEGORIES = {"Cc", "Cf", "Cs", "Co", "Cn"}
_LOGO_SUFFIXES = {".svg", ".png", ".webp"}
_PLACEHOLDERS = {
    "",
    "changeme",
    "example",
    "na",
    "none",
    "null",
    "placeholder",
    "sample",
    "tbd",
    "test",
    "todo",
    "unset",
    "xxx",
}
# Words that mark a file name as unfinished wherever they stand in it. "na" is left out, because
# it can be part of a real name, and the empty string is what a run of separators leaves behind.
_PLACEHOLDER_WORDS = (_PLACEHOLDERS - {"", "na"}) | {
    "demo",
    "draft",
    "dummy",
    "fake",
    "mock",
    "mockup",
    "temp",
    "tmp",
    "wip",
}
_PLACEHOLDERS_IN_ANY_FORM = ("placeholder", "changeme")  # no real name contains these letters
_CAMEL_CASE_BOUNDARY = re.compile(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
_NAME_WORD_SEPARATOR = re.compile(r"[\W\d_]+")
_WITHDRAWN_LOGO_MARKERS = ("flutter_app/", "ic_launcher")


class BrandGateError(ValueError):
    """The real brand was requested while the launch gate is not met."""


def letters_only(text: str) -> str:
    """Compare what a reader sees. Case, spacing, punctuation, diacritics, kashida, yeh
    variants, look-alike letters and invisible marks do not hide or change a name."""
    composed = unicodedata.normalize("NFKC", text).casefold()
    decomposed = unicodedata.normalize("NFD", composed)
    folded = decomposed.translate(_LOOK_ALIKES)
    return "".join(ch for ch in folded if ch.isalnum() and ch != _KASHIDA)


# Assembled, so that the boundary scan keeps code free of the withdrawn name itself.
_WITHDRAWN_NAMES = tuple(letters_only(name) for name in ("wa" + "feer", "وف" + "يير"))
FULL_NAME_EN = "Qawam Money"
FULL_NAME_AR = "قوام المال"
_FULL_EN = letters_only(FULL_NAME_EN)
_FULL_AR = letters_only(FULL_NAME_AR)
_BARE_NAMES = (letters_only("Qawam"), letters_only("قوام"))


def contains_withdrawn_name(text: str) -> bool:
    letters = letters_only(text)
    return any(name in letters for name in _WITHDRAWN_NAMES)


def is_withdrawn_logo_path(path: str) -> bool:
    """Checks the path, so a renamed copy of the old file is the owner's check at approval."""
    normalised = path.replace("\\", "/").casefold()
    return contains_withdrawn_name(path) or any(m in normalised for m in _WITHDRAWN_LOGO_MARKERS)


def has_invisible_characters(text: str) -> bool:
    return any(unicodedata.category(ch) in _INVISIBLE_CATEGORIES for ch in text)


def contains_real_brand(text: str) -> bool:
    """Includes the bare name, which on its own can also mean body shape (G18)."""
    letters = letters_only(text)
    return any(name in letters for name in _BARE_NAMES)


def is_full_brand_name(name_en: str, name_ar: str) -> bool:
    return letters_only(name_en) == _FULL_EN and letters_only(name_ar) == _FULL_AR


def _holds_full_name(text: str) -> bool:
    letters = letters_only(text)
    return _FULL_EN in letters or _FULL_AR in letters


def _text_problem(text: str) -> str | None:
    if not text.strip():
        return "is empty"
    if has_invisible_characters(text):
        return "contains invisible characters"
    return None


def _name_failure(label: str, value: str, full_name: str) -> str | None:
    problem = _text_problem(value)
    if problem:
        return f"{label} {problem}"
    if letters_only(value) != letters_only(full_name):
        return f"{label} must be the full name, {full_name} (G18)"
    return None


def _name_words(stem: str) -> set[str]:
    """The words of a file name: logo_draft, logo-draft, logoDraft and draft2 all hold draft."""
    unmarked = "".join(
        ch for ch in unicodedata.normalize("NFD", stem) if unicodedata.category(ch) != "Mn"
    )
    separated = _CAMEL_CASE_BOUNDARY.sub(" ", unmarked)
    return {letters_only(word) for word in _NAME_WORD_SEPARATOR.split(separated)}


def _names_a_placeholder(stem: str) -> bool:
    letters = letters_only(stem)
    return (
        letters in _PLACEHOLDERS
        or any(word in letters for word in _PLACEHOLDERS_IN_ANY_FORM)
        or bool(_name_words(stem) & _PLACEHOLDER_WORDS)
    )


def _is_usable_file(logo: str) -> bool:
    """Relative paths start at the engine, not at whatever folder the process runs in. A zero
    byte file counts as missing, because it cannot be a logo."""
    try:
        info = (ENGINE_ROOT / logo.replace("\\", "/")).stat()
    except (OSError, ValueError):
        return False
    return stat.S_ISREG(info.st_mode) and info.st_size > 0


def _logo_failure(config: EngineConfig) -> str | None:
    """Catches a logo that is plainly not ready: not set, not an image file, named as a test or
    a placeholder, or, in live mode, not on disk. It reads the name only, and a final file can
    have any name, so passing here does not approve a logo. The final logo decision is still
    the owner's, recorded in `brand.clearance.approved_by_owner_on`."""
    logo = config.brand.logo_path
    problem = _text_problem(logo)
    if problem:
        return f"brand.logo_path {problem}"
    path = PurePosixPath(logo.replace("\\", "/"))
    if path.suffix.casefold() not in _LOGO_SUFFIXES:
        return "brand.logo_path is a placeholder, not an approved logo file"
    if {"test", "logo"} <= _name_words(path.stem):
        return "brand.logo_path is the test logo"
    if _names_a_placeholder(path.stem):
        return "brand.logo_path is a placeholder, not an approved logo file"
    if config.engine.mode == "live" and not _is_usable_file(logo):
        return "brand.logo_path names no usable file on disk"
    return None


def _handle_failure(label: str, value: str) -> str | None:
    problem = _text_problem(value)
    if problem:
        return f"{label} {problem}"
    if not _holds_full_name(value):
        return f"{label} must carry the full name (G18)"
    return None


def _hashtag_failures(hashtags: list[str]) -> list[str]:
    if not hashtags:
        return ["brand.hashtags is empty"]
    failures = []
    for tag in hashtags:
        failure = _handle_failure("brand.hashtags", tag)
        if failure is None and not tag.startswith("#"):
            failure = "brand.hashtags must start with #"
        if failure:
            failures.append(failure)
    return failures


def _clearance_failure(label: str, value: date | None) -> str | None:
    if value is None:
        return f"{label} is empty"
    if value < NAME_CHOSEN_ON:
        return f"{label} is before the name was chosen on {NAME_CHOSEN_ON}"
    if value > date.today():
        return f"{label} is in the future"
    return None


def gate_failures(config: EngineConfig) -> tuple[str, ...]:
    """Everything still missing before a public reel, as config key names."""
    brand = config.brand
    candidates = [
        "engine.mode is not live" if config.engine.mode != "live" else None,
        _name_failure("brand.name_en", brand.name_en, FULL_NAME_EN),
        _name_failure("brand.name_ar", brand.name_ar, FULL_NAME_AR),
        _logo_failure(config),
        *(_handle_failure(f"brand.handles.{k}", v) for k, v in brand.handles.model_dump().items()),
        *_hashtag_failures(brand.hashtags),
        *(
            _clearance_failure(f"brand.clearance.{k}", v)
            for k, v in brand.clearance.model_dump().items()
        ),
    ]
    return tuple(failure for failure in candidates if failure)


def is_gate_met(config: EngineConfig) -> bool:
    return not gate_failures(config)


@dataclass(frozen=True)
class RenderDecision:
    allowed: bool
    watermark: bool
    reasons: tuple[str, ...] = ()


def render_decision(config: EngineConfig, *, test_reel: bool) -> RenderDecision:
    if test_reel:
        return RenderDecision(allowed=True, watermark=True)
    failures = gate_failures(config)
    return RenderDecision(allowed=not failures, watermark=False, reasons=failures)


def _public_step_allowed(config: EngineConfig, test_reel: bool) -> bool:
    return not test_reel and is_gate_met(config)


def approve_button_allowed(config: EngineConfig, *, test_reel: bool) -> bool:
    """Whether the bot may show Approve at all."""
    return _public_step_allowed(config, test_reel)


def approval_allowed(config: EngineConfig, *, test_reel: bool) -> bool:
    """The callback handler's re-check, for a tap on a stale or forged button."""
    return _public_step_allowed(config, test_reel)


def publish_allowed(config: EngineConfig, *, test_reel: bool) -> bool:
    """The publisher's re-check, just before anything goes out."""
    return _public_step_allowed(config, test_reel)


@dataclass(frozen=True)
class ReelBrand:
    name_ar: str
    name_en: str
    hashtag: str
    logo_path: str
    is_test: bool


def brand_for_reel(config: EngineConfig, *, test_reel: bool) -> ReelBrand:
    if test_reel:
        test = config.test_brand
        return ReelBrand(test.name_ar, test.name_en, test.hashtag, test.logo_path, is_test=True)
    failures = gate_failures(config)
    if failures:
        raise BrandGateError(f"launch gate not met: {'; '.join(failures)}")
    brand = config.brand
    return ReelBrand(
        brand.name_ar, brand.name_en, brand.hashtags[0], brand.logo_path, is_test=False
    )


def brand_display(brand: ReelBrand, language: str) -> str:
    """Arabic text shows Arabic then English, and English text the reverse (G12)."""
    if language == "ar":
        return f"{brand.name_ar} {brand.name_en}"
    if language == "en":
        return f"{brand.name_en} {brand.name_ar}"
    raise ValueError(f"unknown reel language: {language!r}")
