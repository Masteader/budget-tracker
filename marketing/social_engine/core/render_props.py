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

from core.config import Fraction, NonEmptyStr, SafeZones
from core.manifest import MaskRegion, Sha256, check_masks
from core.paths import ENGINE_ROOT, RAW_RECORDING_FOLDERS

SCHEMA_PATH = ENGINE_ROOT / "remotion_studio" / "props.schema.json"

Template = Literal["FeatureDemo", "DailyTip", "MythVsFact"]
ReelLanguage = Literal["ar", "en"]
ClipFolder = Literal[RAW_RECORDING_FOLDERS]

_PUBLIC_PATH = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*")
_REEL_ID = re.compile(r"[A-Za-z0-9-]{1,40}")
_HEX_COLOUR = re.compile(r"#[0-9A-Fa-f]{6}")


def _is_public_path(value: str) -> str:
    if not _PUBLIC_PATH.fullmatch(value):
        raise ValueError(f"must be a relative path inside public/, got {value!r}")
    return value


def _is_reel_id(value: str) -> str:
    if not _REEL_ID.fullmatch(value):
        raise ValueError(f"invalid reel id: {value!r}")
    return value


def _is_hex_colour(value: str) -> str:
    if not _HEX_COLOUR.fullmatch(value):
        raise ValueError(f"must be a colour like #E598B0, got {value!r}")
    return value


PublicPath = Annotated[str, AfterValidator(_is_public_path)]
NonNegativeInt = Annotated[int, Field(ge=0)]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class PropsBrand(_Strict):
    name_ar: NonEmptyStr
    name_en: NonEmptyStr
    hashtag: NonEmptyStr
    logo_src: PublicPath


class CaptionWord(_Strict):
    text: NonEmptyStr
    start_ms: NonNegativeInt
    end_ms: NonNegativeInt

    @model_validator(mode="after")
    def _runs_forwards(self) -> CaptionWord:
        if self.end_ms < self.start_ms:
            raise ValueError("a word must not end before it starts")
        return self


class PropsClip(_Strict):
    src: PublicPath  # clips/<folder>/<file>
    folder: ClipFolder
    sha256: Sha256
    start_ms: NonNegativeInt
    end_ms: NonNegativeInt
    mask_regions: list[MaskRegion]

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
    duration_ms: Annotated[int, Field(gt=0)]
    watermark: bool
    device_frame: Literal["generic"]
    digits: Literal["western", "arabic_indic"]
    highlight_color: Annotated[str, AfterValidator(_is_hex_colour)]
    safe_zones: SafeZones
    brand: PropsBrand
    hook_text: NonEmptyStr
    on_screen_text: list[NonEmptyStr]
    subtitles_en: NonEmptyStr
    audio_src: PublicPath
    music_src: PublicPath | None
    duck_under_voice: Fraction
    duck_in_pauses: Fraction
    words: list[CaptionWord]
    clips: list[PropsClip]

    @model_validator(mode="after")
    def _reel_is_consistent(self) -> RenderProps:
        for earlier, later in zip(self.words, self.words[1:], strict=False):
            if later.start_ms < earlier.start_ms:
                raise ValueError("caption words must be in time order")
        if self.template == "FeatureDemo" and not self.clips:
            raise ValueError("FeatureDemo needs at least one clip")
        if any(clip.end_ms > self.duration_ms for clip in self.clips):
            raise ValueError("a clip runs past the end of the reel")
        return self


def export_schema(path: Path = SCHEMA_PATH) -> None:
    text = json.dumps(RenderProps.model_json_schema(), indent=2, ensure_ascii=False, sort_keys=True)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(text + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    export_schema()
    print(f"wrote {SCHEMA_PATH}")
