"""What Claude returns and what the guardrails report (spec Sections 6.2, 6.4, 6.5).

Scripts and research are model output, so unknown fields are rejected and text stays data.
Format checks sit in validators, not in the JSON schema, so the schema stays simple enough
to send to Claude as a structured-output format.
"""

from __future__ import annotations

import re
from datetime import date
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, field_validator, model_validator

from core.config import NonEmptyStr
from core.render_props import ClipFolder, ReelLanguage, Template

Tier = Literal["global", "regional", "saudi"]

_WEB_URL = re.compile(r"https?://[^\s/]+\S*")
_CLAIM_ID = re.compile(r"C\d{2}")
_RULE_ID = re.compile(r"G([1-9]|1\d|2[0-2])")


def _is_web_url(value: str) -> str:
    if not _WEB_URL.fullmatch(value):
        raise ValueError(f"must be an http or https address, got {value!r}")
    return value


WebUrl = Annotated[str, AfterValidator(_is_web_url)]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class ScriptNumber(_Strict):
    value: NonEmptyStr
    source_url: WebUrl


class ScriptSource(_Strict):
    publisher: NonEmptyStr
    url: WebUrl


class Script(_Strict):
    topic_id: NonEmptyStr
    tier: Tier
    template: Template
    language: ReelLanguage
    hook_ar: NonEmptyStr
    voice_script: NonEmptyStr
    on_screen_en: list[NonEmptyStr]
    subtitles_en: NonEmptyStr
    feature_clip_folder: ClipFolder | None
    claim_ids: list[str]
    numbers: list[ScriptNumber]
    sources: list[ScriptSource]
    caption_ar: NonEmptyStr
    caption_en: NonEmptyStr
    hashtags: list[NonEmptyStr]
    speech_seconds_estimate: Annotated[float, Field(gt=0)]

    @field_validator("claim_ids")
    @classmethod
    def _claim_ids_are_distinct(cls, value: list[str]) -> list[str]:
        if any(not _CLAIM_ID.fullmatch(claim) for claim in value):
            raise ValueError("claim ids look like C01")
        if len(set(value)) != len(value):
            raise ValueError("each claim id can appear only once")
        return value


class ResearchFact(_Strict):
    claim: NonEmptyStr
    source_url: WebUrl
    publisher: NonEmptyStr
    accessed: Annotated[date, Field(strict=False)]  # an ISO date in model output
    paraphrase_ar: NonEmptyStr
    paraphrase_en: NonEmptyStr


class ResearchResult(_Strict):
    facts: Annotated[list[ResearchFact], Field(min_length=1)]


class GuardrailFinding(_Strict):
    rule: str
    source: Literal["deterministic", "claude_review"]
    location: NonEmptyStr
    message: NonEmptyStr

    @field_validator("rule")
    @classmethod
    def _rule_exists(cls, value: str) -> str:
        if not _RULE_ID.fullmatch(value):
            raise ValueError(f"no such guardrail: {value!r}")
        return value


class GuardrailReport(_Strict):
    passed: bool
    hard_failures: list[GuardrailFinding]
    soft_flags: list[GuardrailFinding]

    @model_validator(mode="after")
    def _passed_matches_the_findings(self) -> GuardrailReport:
        if self.passed == bool(self.hard_failures):
            raise ValueError("passed must be true exactly when there are no hard failures")
        return self


class ReviewVerdict(_Strict):
    """The separate Claude review: pass or fail with reasons (spec Section 6.5)."""

    passed: bool
    reasons: list[NonEmptyStr]

    @model_validator(mode="after")
    def _a_failure_gives_reasons(self) -> ReviewVerdict:
        if not self.passed and not self.reasons:
            raise ValueError("a failed review must give its reasons")
        return self
