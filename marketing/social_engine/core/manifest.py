"""The clip allow-list, `manifest.json` (spec Sections 5.2 and 8.3, guardrails G15 and G19).

A clip gets into the manifest only after the owner's sign-off, so a manifest with an
unsigned clip does not load. A clip is usable only while its file still has the signed hash.
"""

from __future__ import annotations

import hashlib
import os
import re
from pathlib import Path
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from core.paths import RAW_RECORDING_FOLDERS

MASKED_FOLDER = "smart_basket"

_CLIP_PATH = re.compile(r"([a-z_]+)/[A-Za-z0-9][A-Za-z0-9._-]*")
_SHA256 = re.compile(r"[0-9a-f]{64}")
_FLOAT_TOLERANCE = 1e-9


class ClipRejected(ValueError):
    """This clip may not be used. The message says why."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def is_sha256(value: str) -> str:
    if not _SHA256.fullmatch(value):
        raise ValueError("must be a lowercase SHA-256 in hex")
    return value


def _is_signed(value: bool) -> bool:
    if value is not True:
        raise ValueError("privacy_checked must be true: the owner has not signed this clip off")
    return value


Sha256 = Annotated[str, AfterValidator(is_sha256)]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class MaskRegion(_Strict):
    """A rectangle to blur, as fractions of the clip's width and height, so it holds at any
    recording resolution."""

    x: Annotated[float, Field(ge=0, le=1)]
    y: Annotated[float, Field(ge=0, le=1)]
    width: Annotated[float, Field(gt=0, le=1)]
    height: Annotated[float, Field(gt=0, le=1)]

    @model_validator(mode="after")
    def _inside_the_clip(self) -> MaskRegion:
        limit = 1 + _FLOAT_TOLERANCE
        if self.x + self.width > limit or self.y + self.height > limit:
            raise ValueError("mask region runs outside the clip")
        return self


def check_masks(folder: str, mask_regions: list[MaskRegion]) -> None:
    """Masks belong to the Smart Basket folder, which cannot be used without them (D30)."""
    if folder == MASKED_FOLDER and not mask_regions:
        raise ValueError(f"a {MASKED_FOLDER} clip needs non-empty mask_regions")
    if folder != MASKED_FOLDER and mask_regions:
        raise ValueError(f"mask_regions are only for {MASKED_FOLDER} clips")


class ClipEntry(_Strict):
    path: str  # <folder>/<file>, relative to raw_recordings
    sha256: Sha256
    privacy_checked: Annotated[bool, AfterValidator(_is_signed)]  # strict, so 1 is not true
    app_version: Annotated[str, Field(min_length=1)]
    store_names_masked: bool = False
    mask_regions: list[MaskRegion] = []

    @property
    def folder(self) -> str:
        return self.path.split("/", 1)[0]

    @model_validator(mode="after")
    def _path_and_masks_are_valid(self) -> ClipEntry:
        match = _CLIP_PATH.fullmatch(self.path)
        if not match or match.group(1) not in RAW_RECORDING_FOLDERS:
            raise ValueError(f"path must be a file in a shot list folder, got {self.path!r}")
        check_masks(self.folder, self.mask_regions)
        if self.folder == MASKED_FOLDER and not self.store_names_masked:
            raise ValueError(f"a {MASKED_FOLDER} clip needs store_names_masked: true")
        if self.folder != MASKED_FOLDER and self.store_names_masked:
            raise ValueError(f"store_names_masked is only for {MASKED_FOLDER} clips")
        return self


class ClipManifest(_Strict):
    clips: list[ClipEntry]

    @model_validator(mode="after")
    def _each_path_once(self) -> ClipManifest:
        paths = [entry.path for entry in self.clips]
        if len(set(paths)) != len(paths):
            raise ValueError("each clip path can appear only once")
        return self

    @classmethod
    def load(cls, path: Path) -> ClipManifest:
        if not Path(path).exists():
            return cls(clips=[])
        return cls.model_validate_json(Path(path).read_text(encoding="utf-8"))

    def save(self, path: Path) -> None:
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f"{target.name}.tmp")
        temporary.write_text(self.model_dump_json(indent=2), encoding="utf-8")
        os.replace(temporary, target)

    def add_clip(self, entry: ClipEntry, recordings_root: Path) -> ClipManifest:
        """Returns the new manifest. The caller saves it."""
        if any(existing.path == entry.path for existing in self.clips):
            raise ClipRejected(f"{entry.path} is already in the manifest")
        _check_file(entry, recordings_root)
        return ClipManifest(clips=[*self.clips, entry])

    def verified_clip(self, clip_path: str, recordings_root: Path) -> ClipEntry:
        """The render allow-list: the only way to get a clip out of the manifest."""
        for entry in self.clips:
            if entry.path == clip_path:
                _check_file(entry, recordings_root)
                return entry
        raise ClipRejected(f"{clip_path} is not in the manifest")


def _check_file(entry: ClipEntry, recordings_root: Path) -> None:
    file = Path(recordings_root) / entry.path
    if not file.is_file():
        raise ClipRejected(f"{entry.path} is missing from {recordings_root}")
    if sha256_file(file) != entry.sha256:
        raise ClipRejected(f"{entry.path} does not match its signed hash")
