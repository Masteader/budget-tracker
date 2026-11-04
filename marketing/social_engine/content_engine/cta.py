"""Calls to action and bios (spec Section 6.7, decision D26, guardrail G11).

While `cta.mode` is `coming_soon`, the strings in `config.yaml` are the only CTA and bio wording
allowed. The engine fills their tokens from config and adds nothing else, so no code path here
can add a link: the landing URL is never read, whatever the mode.
"""

from __future__ import annotations

import re
from typing import Literal

from core.brand_gate import ReelBrand
from core.config import CtaWording, EngineConfig

CtaKind = Literal["bio", "caption", "voice"]
Language = Literal["ar", "en"]

BRAND_TOKEN = re.compile(r"\{brand_(?:ar|en|hashtag)\}")
_ANY_TOKEN = re.compile(r"[{}]")


class UnknownTokenError(ValueError):
    """Text holds a brace that is not one of the three brand tokens."""


def _token_value(token: str, brand: ReelBrand) -> str:
    return {
        "{brand_ar}": brand.name_ar,
        "{brand_en}": brand.name_en,
        "{brand_hashtag}": brand.hashtag,
    }[token]


def fill_tokens(text: str, brand: ReelBrand) -> str:
    """One pass, so a value is never filled again. Anything else in braces is refused, because
    a mistyped token would otherwise reach the screen as it stands."""
    if _ANY_TOKEN.search(BRAND_TOKEN.sub("", text)):
        raise UnknownTokenError(f"unknown token in {text[:80]!r}")
    return BRAND_TOKEN.sub(lambda match: _token_value(match.group(), brand), text)


def active_wording(config: EngineConfig) -> CtaWording:
    """Config refuses a mode without its wording, so this is always set."""
    wording = getattr(config.cta, config.cta.mode)
    if wording is None:
        raise ValueError(f"cta mode {config.cta.mode} has no wording")
    return wording


def cta_line(
    config: EngineConfig, brand: ReelBrand, kind: CtaKind, language: Language
) -> str:
    return fill_tokens(getattr(active_wording(config), f"{kind}_{language}"), brand)


def compose_caption(
    body: str, language: Language, config: EngineConfig, brand: ReelBrand
) -> str:
    """The caption as posted: the script's text, the CTA, the disclaimer and the disclosure."""
    parts = [
        fill_tokens(body, brand),
        cta_line(config, brand, "caption", language),
        config.captions.disclaimer,
        config.captions.ai_voice_disclosure,
    ]
    return "\n\n".join(parts)


def compose_voice(
    script_text: str, language: Language, config: EngineConfig, brand: ReelBrand
) -> str:
    return f"{fill_tokens(script_text, brand)} {cta_line(config, brand, 'voice', language)}"
