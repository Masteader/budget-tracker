"""The strict props file handed to Remotion (spec Sections 5.2 and 8.3).

There is deliberately no field for account data, and none that turns the Smart Basket
treatment off: the composition draws it from the clip's folder (D30).

Run `python -m core.render_props` to refresh `remotion_studio/props.schema.json`.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from core.brand_gate import contains_withdrawn_name, is_full_brand_name
from core.config import Fraction, SafeZones, strings_in
from core.manifest import MaskRegions, Sha256, check_masks
from core.paths import ENGINE_ROOT, RAW_RECORDING_FOLDERS, is_windows_safe_name
from core.safe_text import at_most, display_text

SCHEMA_PATH = ENGINE_ROOT / "remotion_studio" / "props.schema.json"

Template = Literal["FeatureDemo", "DailyTip", "MythVsFact"]
ReelLanguage = Literal["ar", "en"]
ClipFolder = Literal[RAW_RECORDING_FOLDERS]

MAX_REEL_MS = 180_000  # the longest Short (spec Section 10.4). Reels aim for 15 to 45 s
_MAX_PATH_CHARS = 200
_TEST_LOGO_MARKER = "test_logo"
_PUBLIC_PATH = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*")
_REEL_ID = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}[A-Za-z0-9])?")
_HEX_COLOUR = re.compile(r"#[0-9A-Fa-f]{6}")


def _is_public_path(value: str) -> str:
    if (
        len(value) > _MAX_PATH_CHARS
        or not _PUBLIC_PATH.fullmatch(value)
        or not all(is_windows_safe_name(part) for part in value.split("/"))
    ):
        raise ValueError(f"must be a relative path inside public/, got {value[:80]!r}")
    return value


def _is_reel_id(value: str) -> str:
    # The id becomes a file name and a command-line value, so no device names and no flags.
    if not _REEL_ID.fullmatch(value) or not is_windows_safe_name(value):
        raise ValueError(f"invalid reel id: {value[:80]!r}")
    return value


def _is_hex_colour(value: str) -> str:
    if not _HEX_COLOUR.fullmatch(value):
        raise ValueError(f"must be a colour like #E598B0, got {value[:80]!r}")
    return value


PublicPath = Annotated[str, AfterValidator(_is_public_path)]
NonNegativeInt = Annotated[int, Field(ge=0)]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class PropsBrand(_Strict):
    name_ar: Annotated[str, display_text(64)]
    name_en: Annotated[str, display_text(64)]
    hashtag: Annotated[str, display_text(64)]
    logo_src: PublicPath


class CaptionWord(_Strict):
    text: Annotated[str, display_text(64)]
    start_ms: NonNegativeInt
    end_ms: NonNegativeInt

    @model_validator(mode="after")
    def _runs_forwards(self) -> CaptionWord:
        if self.end_ms < self.start_ms:
            raise ValueError("a word must not end before it starts")
        return self


class FocalPoint(_Strict):
    """The feature in a clip the camera zooms to, as fractions of the clip's width and height."""

    x: Fraction
    y: Fraction


class PropsClip(_Strict):
    src: PublicPath  # clips/<folder>/<file>
    folder: ClipFolder
    sha256: Sha256
    start_ms: NonNegativeInt
    end_ms: NonNegativeInt
    mask_regions: MaskRegions
    focal_point: FocalPoint | None  # null means the template's default point

    @model_validator(mode="after")
    def _is_consistent(self) -> PropsClip:
        if self.src.split("/")[:2] != ["clips", self.folder] or self.src.count("/") != 2:
            raise ValueError(f"src must sit in its folder, clips/{self.folder}/, got {self.src!r}")
        if self.end_ms <= self.start_ms:
            raise ValueError("a clip must end after it starts")
        check_masks(self.folder, self.mask_regions)
        return self


class RenderProps(_Strict):
    reel_id: Annotated[str, AfterValidator(_is_reel_id)]
    revision: Annotated[int, Field(ge=1)]
    template: Template
    language: ReelLanguage
    width: Literal[1080]
    height: Literal[1920]
    fps: Literal[30, 60]
    duration_ms: Annotated[int, Field(gt=0, le=MAX_REEL_MS)]
    watermark: bool
    device_frame: Literal["generic"]
    digits: Literal["western", "arabic_indic"]
    highlight_color: Annotated[str, AfterValidator(_is_hex_colour)]
    safe_zones: SafeZones
    brand: PropsBrand
    hook_text: Annotated[str, display_text(200)]
    on_screen_text: Annotated[list[Annotated[str, display_text(160)]], at_most(20)]
    subtitles_en: Annotated[str, display_text(2000)]
    audio_src: PublicPath
    music_src: PublicPath | None
    duck_under_voice: Fraction
    duck_in_pauses: Fraction
    words: Annotated[list[CaptionWord], at_most(2000)]
    clips: Annotated[list[PropsClip], at_most(20)]

    @model_validator(mode="after")
    def _reel_is_consistent(self) -> RenderProps:
        for earlier, later in zip(self.words, self.words[1:], strict=False):
            if later.start_ms < earlier.start_ms:
                raise ValueError("caption words must be in time order")
        if self.template == "FeatureDemo" and not self.clips:
            raise ValueError("FeatureDemo needs at least one clip")
        if any(clip.end_ms > self.duration_ms for clip in self.clips):
            raise ValueError("a clip runs past the end of the reel")
        if any(word.end_ms > self.duration_ms for word in self.words):
            raise ValueError("a caption word runs past the end of the reel")
        return self

    @model_validator(mode="after")
    def _brand_matches_the_watermark(self) -> RenderProps:
        """A reel with no watermark goes public, so it has to carry the full real name. A
        test reel carries the test brand (spec Section 13), so the real name there is a
        mix-up. The launch gate decides earlier whether a public reel may exist at all."""
        real = is_full_brand_name(self.brand.name_en, self.brand.name_ar)
        if self.watermark and real:
            raise ValueError("a watermarked test reel must use the test brand")
        if not self.watermark and not real:
            raise ValueError("a reel with no watermark must carry the full real brand name")
        if not self.watermark and _TEST_LOGO_MARKER in self.brand.logo_src.casefold():
            raise ValueError("a reel with no watermark cannot use the test logo")
        return self

    @model_validator(mode="after")
    def _withdrawn_name_is_refused(self) -> RenderProps:
        for where, text in strings_in(self.model_dump(), ""):
            if contains_withdrawn_name(text):
                raise ValueError(f"{where} uses the withdrawn brand name (D1)")
        return self


def export_schema(path: Path = SCHEMA_PATH) -> None:
    text = json.dumps(RenderProps.model_json_schema(), indent=2, ensure_ascii=False, sort_keys=True)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(text + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    export_schema()
    print(f"wrote {SCHEMA_PATH}")
