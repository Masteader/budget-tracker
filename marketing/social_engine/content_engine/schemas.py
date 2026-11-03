"""What Claude returns and what the guardrails report (spec Sections 6.2, 6.4, 6.5).

Scripts and research are model output, so unknown fields are rejected and text stays data.
Format checks sit in validators, not in the JSON schema, so the schema stays simple enough
to send to Claude as a structured-output format.
"""

from __future__ import annotations

import ipaddress
import re
from datetime import date, timedelta
from typing import Annotated, Any, Literal
from urllib.parse import urlsplit

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from core.brand_gate import contains_withdrawn_name, has_invisible_characters
from core.config import strings_in
from core.render_props import ClipFolder, ReelLanguage, Template
from core.safe_text import at_most, bounded_text, display_text

Tier = Literal["global", "regional", "saudi"]

_MAX_URL_CHARS = 2048
_WEB_URL = re.compile(r"https?://[^\s/]+(?:/\S*)?")  # the two parts cannot overlap: linear time
_PRIVATE_HOST_SUFFIXES = (".local", ".internal", ".localhost")
_CLAIM_ID = re.compile(r"C\d{2}")
_RULE_ID = re.compile(r"G([1-9]|1\d|2[0-2])")


def _is_web_url(value: str) -> str:
    """A public web address. These come from model output and get shown to the owner, so
    credentials, private hosts and hidden direction characters are refused."""
    if len(value) > _MAX_URL_CHARS or not _WEB_URL.fullmatch(value):
        raise ValueError(f"must be an http or https address, got {value[:80]!r}")
    if has_invisible_characters(value):
        raise ValueError("address contains invisible characters")
    parts = urlsplit(value)
    host = (parts.hostname or "").casefold()
    if parts.username or parts.password:
        raise ValueError("address must not carry credentials")
    if "." not in host and ":" not in host:
        raise ValueError(f"address must have a public host name, got {host!r}")
    if host.endswith(_PRIVATE_HOST_SUFFIXES):
        raise ValueError(f"address points at a private host: {host!r}")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return value
    raise ValueError(f"address must use a host name, not an IP address: {host!r}")


def _iso_date_only(value: Any) -> Any:
    """Without this, lax date parsing would read the integer 0 as a date in 1970."""
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return date.fromisoformat(value)
    raise ValueError("must be an ISO date")


def _not_in_the_future(value: date) -> date:
    if value > date.today() + timedelta(days=1):  # a day of grace for time zones
        raise ValueError(f"access date is in the future: {value}")
    return value


WebUrl = Annotated[str, AfterValidator(_is_web_url)]
AccessDate = Annotated[
    date,
    BeforeValidator(_iso_date_only),
    AfterValidator(_not_in_the_future),
    Field(strict=False),
]


def _refuse_withdrawn_name(model: BaseModel) -> None:
    for where, text in strings_in(model.model_dump(), ""):
        if contains_withdrawn_name(text):
            raise ValueError(f"{where} uses the withdrawn brand name (D1)")


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class ScriptNumber(_Strict):
    value: Annotated[str, display_text(64)]
    source_url: WebUrl


class ScriptSource(_Strict):
    publisher: Annotated[str, display_text(200)]
    url: WebUrl


class Script(_Strict):
    topic_id: Annotated[str, bounded_text(64)]
    tier: Tier
    template: Template
    language: ReelLanguage
    hook_ar: Annotated[str, display_text(200)]
    voice_script: Annotated[str, display_text(2000)]
    on_screen_en: Annotated[list[Annotated[str, display_text(160)]], at_most(20)]
    subtitles_en: Annotated[str, display_text(2000)]
    feature_clip_folder: ClipFolder | None
    claim_ids: Annotated[list[str], at_most(30)]
    numbers: Annotated[list[ScriptNumber], at_most(50)]
    sources: Annotated[list[ScriptSource], at_most(20)]
    caption_ar: Annotated[str, display_text(2200)]  # 2200 is Instagram's caption limit
    caption_en: Annotated[str, display_text(2200)]
    hashtags: Annotated[list[Annotated[str, display_text(64)]], at_most(30)]
    speech_seconds_estimate: Annotated[float, Field(gt=0, le=600, allow_inf_nan=False)]

    @field_validator("claim_ids")
    @classmethod
    def _claim_ids_are_distinct(cls, value: list[str]) -> list[str]:
        if any(not _CLAIM_ID.fullmatch(claim) for claim in value):
            raise ValueError("claim ids look like C01")
        if len(set(value)) != len(value):
            raise ValueError("each claim id can appear only once")
        return value

    @model_validator(mode="after")
    def _script_is_consistent(self) -> Script:
        if self.template == "FeatureDemo" and self.feature_clip_folder is None:
            raise ValueError("FeatureDemo needs a feature_clip_folder, as RenderProps needs a clip")
        _refuse_withdrawn_name(self)
        return self


class ResearchFact(_Strict):
    claim: Annotated[str, display_text(2000)]
    source_url: WebUrl
    publisher: Annotated[str, display_text(200)]
    accessed: AccessDate  # an ISO date in model output
    paraphrase_ar: Annotated[str, display_text(2000)]
    paraphrase_en: Annotated[str, display_text(2000)]


class ResearchResult(_Strict):
    facts: Annotated[list[ResearchFact], Field(min_length=1), at_most(50)]


class GuardrailFinding(_Strict):
    rule: str
    source: Literal["deterministic", "claude_review"]
    location: Annotated[str, bounded_text(200)]
    message: Annotated[str, bounded_text(2000)]

    @field_validator("rule")
    @classmethod
    def _rule_exists(cls, value: str) -> str:
        if not _RULE_ID.fullmatch(value):
            raise ValueError(f"no such guardrail: {value[:20]!r}")
        return value


class GuardrailReport(_Strict):
    passed: bool
    hard_failures: Annotated[list[GuardrailFinding], at_most(200)]
    soft_flags: Annotated[list[GuardrailFinding], at_most(200)]

    @model_validator(mode="after")
    def _passed_matches_the_findings(self) -> GuardrailReport:
        if self.passed == bool(self.hard_failures):
            raise ValueError("passed must be true exactly when there are no hard failures")
        return self


class ReviewVerdict(_Strict):
    """The separate Claude review: pass or fail with reasons (spec Section 6.5)."""

    passed: bool
    reasons: Annotated[list[Annotated[str, bounded_text(2000)]], at_most(50)]

    @model_validator(mode="after")
    def _a_failure_gives_reasons(self) -> ReviewVerdict:
        if not self.passed and not self.reasons:
            raise ValueError("a failed review must give its reasons")
        return self
