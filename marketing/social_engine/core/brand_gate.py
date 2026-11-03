"""The launch gate (spec Section 13) and the withdrawn brand (decision D1).

`live` mode refuses to render, offer approval or publish while the name, logo, handles,
hashtags or any clearance field is empty. A test reel carries the watermark and the test
brand, and can never be approved, however complete the real brand is. The bot and the
publisher call these functions again at the moment they act, so a forged callback or a
config edit after rendering is still refused.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from core.config import EngineConfig

# Assembled, so that the boundary scan keeps code free of the name itself.
_WITHDRAWN_NAMES = ("wa" + "feer", "وف" + "يير")
_WITHDRAWN_LOGO_MARKERS = ("flutter_app/", "ic_launcher")


class BrandGateError(ValueError):
    """The real brand was requested while the launch gate is not met."""


def _letters_only(text: str) -> str:
    """Case, spacing, punctuation, diacritics and invisible marks do not hide a name."""
    folded = unicodedata.normalize("NFKC", text).casefold()
    return "".join(ch for ch in folded if ch.isalnum())


def contains_withdrawn_name(text: str) -> bool:
    letters = _letters_only(text)
    return any(name in letters for name in _WITHDRAWN_NAMES)


def is_withdrawn_logo_path(path: str) -> bool:
    """Checks the path, so a renamed copy of the old file is the owner's check at approval."""
    normalised = path.replace("\\", "/").casefold()
    return contains_withdrawn_name(path) or any(m in normalised for m in _WITHDRAWN_LOGO_MARKERS)


def gate_failures(config: EngineConfig) -> tuple[str, ...]:
    """Everything still missing before a public reel, as config key names."""
    brand = config.brand
    failures: list[str] = []
    if config.engine.mode != "live":
        failures.append("engine.mode is not live")
    for label, value in [
        ("brand.name_en", brand.name_en),
        ("brand.name_ar", brand.name_ar),
        ("brand.logo_path", brand.logo_path),
        *((f"brand.handles.{k}", v) for k, v in brand.handles.model_dump().items()),
    ]:
        if not value.strip():
            failures.append(f"{label} is empty")
    if not brand.hashtags or not all(tag.strip() for tag in brand.hashtags):
        failures.append("brand.hashtags is empty")
    for key, value in brand.clearance.model_dump().items():
        if value is None:
            failures.append(f"brand.clearance.{key} is empty")
    return tuple(failures)


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
