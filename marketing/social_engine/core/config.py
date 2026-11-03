"""Load and validate `config.yaml` (spec Section 11.3).

Unknown keys and invalid values stop the engine with a clear message. Validation is strict,
so `"true"` is not a boolean and `"3"` is not a number. The config holds no secrets.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from datetime import date
from pathlib import Path
from typing import Annotated, Any, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import yaml
from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)

from core.brand_gate import contains_withdrawn_name, is_withdrawn_logo_path

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parents[1] / "config.yaml"

_CLAUDE_ALIASES = {"opus", "sonnet", "haiku", "fable"}
_CLAUDE_MODEL_ID = re.compile(r"claude-[a-z0-9][a-z0-9.\-]*")
_CLOCK = re.compile(r"([01]\d|2[0-3]):[0-5]\d")
_HTTPS_URL = re.compile(r"https://[^\s/]+\S*")

_MODE_NEEDS_WORDING = ("early_access", "store")


class ConfigError(Exception):
    """The config cannot be used. The message says what to change."""


def _not_blank(value: str) -> str:
    if not value.strip():
        raise ValueError("must not be empty")
    return value


def _is_clock(value: str) -> str:
    if not _CLOCK.fullmatch(value):
        raise ValueError(f"must be a 24-hour time like 09:00, got {value!r}")
    return value


NonEmptyStr = Annotated[str, AfterValidator(_not_blank)]
Clock = Annotated[str, AfterValidator(_is_clock)]
PositiveInt = Annotated[int, Field(gt=0)]
Fraction = Annotated[float, Field(ge=0, le=1)]
Weekday = Literal["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
ClearanceDate = date | None


class _Section(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class Engine(_Section):
    mode: Literal["test", "live"]


class BrandHandles(_Section):
    instagram: str
    facebook: str
    tiktok: str
    youtube: str


class BrandClearance(_Section):
    google_play_checked_on: ClearanceDate
    app_store_checked_on: ClearanceDate
    saip_checked_on: ClearanceDate
    approved_by_owner_on: ClearanceDate


class Brand(_Section):
    name_en: str
    name_ar: str
    tagline_en: str
    tagline_ar: str
    handles: BrandHandles
    hashtags: list[str]
    logo_path: str
    tokens: NonEmptyStr
    clearance: BrandClearance


class TestBrand(_Section):
    __test__ = False  # not a test class, despite the name

    name_en: NonEmptyStr
    name_ar: NonEmptyStr
    hashtag: NonEmptyStr
    logo_path: NonEmptyStr


class Paths(_Section):
    data_root: NonEmptyStr


class Capture(_Section):
    adb_path: NonEmptyStr


class Llm(_Section):
    backend: Literal["claude_cli", "anthropic_api"]
    auth: Literal["subscription", "api_key"]
    model: str
    claude_path: str
    claude_version: str
    max_turns: PositiveInt
    max_budget_usd: Annotated[float, Field(gt=0)]

    @field_validator("model")
    @classmethod
    def _claude_only(cls, value: str) -> str:
        if value not in _CLAUDE_ALIASES and not _CLAUDE_MODEL_ID.fullmatch(value):
            raise ValueError(f"Claude models only (decision D9), got {value!r}")
        return value


class Voice(_Section):
    provider: Literal["azure_speech"]
    azure_tier: Literal["F0", "S0"]
    arabic_voice: str
    english_voice: str
    rate: str
    pitch: str
    output_format: NonEmptyStr
    monthly_char_cap: PositiveInt
    allow_public_on_f0: bool
    chars_per_second: Annotated[float, Field(gt=0)]
    pronunciation: dict[str, str]


class SafeZones(_Section):
    top: Annotated[int, Field(ge=0)]
    bottom: Annotated[int, Field(ge=0)]
    left: Annotated[int, Field(ge=0)]
    right: Annotated[int, Field(ge=0)]

    @model_validator(mode="after")
    def _fits_the_canvas(self) -> SafeZones:
        if self.top + self.bottom >= 1920 or self.left + self.right >= 1080:
            raise ValueError("safe zones leave no room on a 1080x1920 canvas")
        return self


class Render(_Section):
    fps: Literal[30, 60]
    video_kbps_cap: PositiveInt
    audio_kbps: PositiveInt
    max_mb: Annotated[int, Field(gt=0, le=50)]  # Telegram bots cannot send more than 50 MB
    ffmpeg_path: str
    safe_zones: SafeZones


class Captions(_Section):
    digits: Literal["western", "arabic_indic"]
    disclaimer: NonEmptyStr
    ai_voice_disclosure: NonEmptyStr
    max_hashtags: PositiveInt


class Audio(_Section):
    music_enabled: bool
    music_library: str | None
    duck_under_voice: Fraction
    duck_in_pauses: Fraction

    @model_validator(mode="after")
    def _music_needs_a_licensed_library(self) -> Audio:
        if self.music_enabled and not (self.music_library or "").strip():
            raise ValueError("music_enabled needs music_library naming a licensed library (D25)")
        return self


class Content(_Section):
    mix: dict[Literal["global", "regional", "saudi"], Annotated[int, Field(ge=0)]]
    english_audio_share: Fraction

    @field_validator("mix")
    @classmethod
    def _mix_is_complete(cls, value: dict[str, int]) -> dict[str, int]:
        if set(value) != {"global", "regional", "saudi"} or sum(value.values()) != 100:
            raise ValueError("needs global, regional and saudi, adding up to 100")
        return value


class CtaWording(_Section):
    bio_ar: NonEmptyStr
    bio_en: NonEmptyStr
    caption_ar: NonEmptyStr
    caption_en: NonEmptyStr
    voice_ar: NonEmptyStr
    voice_en: NonEmptyStr


def _blank_means_none(value: Any) -> Any:
    return None if isinstance(value, str) and not value.strip() else value


class Cta(_Section):
    mode: Literal["coming_soon", "early_access", "store"]
    landing_url: Annotated[str | None, BeforeValidator(_blank_means_none)]
    coming_soon: CtaWording
    early_access: CtaWording | None
    store: CtaWording | None

    @field_validator("landing_url")
    @classmethod
    def _url_is_https(cls, value: str | None) -> str | None:
        if value is not None and not _HTTPS_URL.fullmatch(value):
            raise ValueError(f"must be a full https:// address, got {value!r}")
        return value

    @model_validator(mode="after")
    def _mode_matches_url(self) -> Cta:
        if self.mode == "coming_soon" and self.landing_url:
            raise ValueError(
                "landing_url is set while mode is coming_soon. Moving on is an explicit "
                "owner edit: change the mode as well (D26)"
            )
        if self.mode in _MODE_NEEDS_WORDING:
            if not self.landing_url:
                raise ValueError(f"mode {self.mode} needs a landing_url (D26)")
            if getattr(self, self.mode) is None:
                raise ValueError(f"mode {self.mode} needs owner-approved {self.mode} wording")
        return self


class Approval(_Section):
    expire_after_hours: PositiveInt
    max_regenerations: Annotated[int, Field(ge=0)]
    max_waiting: PositiveInt


class Guardrails(_Section):
    max_copied_words: PositiveInt


class Cadence(_Section):
    reels_per_week: Annotated[int, Field(ge=1, le=7)]
    generation_days: list[Weekday]

    @field_validator("generation_days")
    @classmethod
    def _days_are_distinct(cls, value: list[str]) -> list[str]:
        if not value or len(set(value)) != len(value):
            raise ValueError("needs at least one day, with no day listed twice")
        return value


class PostingWindow(_Section):
    name: NonEmptyStr
    start: Clock
    end: Clock

    @model_validator(mode="after")
    def _starts_before_it_ends(self) -> PostingWindow:
        if self.start >= self.end:
            raise ValueError(f"window {self.name} must start before it ends")
        return self


class PaydayBoost(_Section):
    enabled: bool
    days_of_month: list[Annotated[int, Field(ge=1, le=31)]]
    reels_per_day: PositiveInt


class Schedule(_Section):
    timezone: str
    generate_after: Clock
    cadence: Cadence
    windows: Annotated[list[PostingWindow], Field(min_length=1)]
    payday_boost: PaydayBoost
    ramadan_windows: list[PostingWindow] | None

    @field_validator("timezone")
    @classmethod
    def _timezone_exists(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise ValueError(f"unknown timezone {value!r}") from error
        return value


class Retention(_Section):
    auto_delete: bool


def _strings_in(node: Any, where: str) -> Iterator[tuple[str, str]]:
    if isinstance(node, str):
        yield where, node
    elif isinstance(node, dict):
        for key, value in node.items():
            yield where, str(key)
            yield from _strings_in(value, f"{where}.{key}" if where else str(key))
    elif isinstance(node, list):
        for value in node:
            yield from _strings_in(value, where)


class EngineConfig(_Section):
    engine: Engine
    brand: Brand
    test_brand: TestBrand
    paths: Paths
    capture: Capture
    llm: Llm
    voice: Voice
    render: Render
    captions: Captions
    audio: Audio
    content: Content
    cta: Cta
    approval: Approval
    guardrails: Guardrails
    publishing_mode: Literal["telegram_only"]
    schedule: Schedule
    retention: Retention

    @model_validator(mode="after")
    def _withdrawn_brand_is_refused(self) -> EngineConfig:
        for where, text in _strings_in(self.model_dump(), ""):
            if contains_withdrawn_name(text):
                raise ValueError(f"{where} uses the withdrawn brand name (D1)")
        for where, path in [
            ("brand.logo_path", self.brand.logo_path),
            ("test_brand.logo_path", self.test_brand.logo_path),
        ]:
            if is_withdrawn_logo_path(path):
                raise ValueError(f"{where} points at a withdrawn logo or launcher icon (D1)")
        return self


class _NoDuplicateKeysLoader(yaml.SafeLoader):
    """PyYAML keeps the last of two equal keys. Here that would hide a changed setting."""


def _construct_mapping(loader: yaml.SafeLoader, node: yaml.MappingNode) -> dict:
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=True)
        if key in seen:
            raise yaml.YAMLError(f"duplicate key {key!r} on line {key_node.start_mark.line + 1}")
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep=True)


_NoDuplicateKeysLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping
)


def _describe(error: ValidationError) -> str:
    lines = []
    for item in error.errors():
        location = ".".join(str(part) for part in item["loc"]) or "config"
        lines.append(f"  - {location}: {item['msg']}")
    return "\n".join(lines)


def load_config(path: Path | None = None) -> EngineConfig:
    config_path = DEFAULT_CONFIG_PATH if path is None else Path(path)
    try:
        text = config_path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise ConfigError(f"Config file not found: {config_path}") from error
    try:
        data = yaml.load(text, Loader=_NoDuplicateKeysLoader)  # a SafeLoader subclass
    except yaml.YAMLError as error:
        raise ConfigError(f"Config {config_path} is not valid YAML: {error}") from error
    if not isinstance(data, dict):
        raise ConfigError(f"Config {config_path} must be a YAML mapping of sections")
    try:
        return EngineConfig.model_validate(data)
    except ValidationError as error:
        raise ConfigError(f"Invalid config {config_path}:\n{_describe(error)}") from error
