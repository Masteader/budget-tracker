"""The pre-capture checklist, the owner's sign-off and the manual fallback (spec Sections 5.1
to 5.3, decisions D22, D23 and D30, guardrails G15 and G19).

**Sign-off.** A clip reaches `manifest.json` only through `record_clip`, and that needs a
confirmation that only a fully answered `Checklist` hands out. Only a typed `yes` counts.

**Test clips.** `ClipEntry` has no field for this, so the file name carries it, and it fails
closed: a clip is final only when named `final_clip_NN.mp4`. Every other clip is a test clip, and
that name can only be given while the launch gate is met (D23). `check_clip_for_reel` is the check
for whoever picks clips for a public reel.

**Manual fallback.** The owner records with the phone's own recorder and drops files into a feature
folder. `run_ingest` strips each one by re-encoding and signs the cleaned copy, not the original.
"""

from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import uuid
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from pathlib import Path

from pydantic import ValidationError

from core.brand_gate import gate_failures, is_gate_met
from core.config import EngineConfig
from core.manifest import (
    MASKED_FOLDER,
    MAX_MASK_REGIONS,
    ClipEntry,
    ClipManifest,
    ClipRejected,
    MaskRegion,
    sha256_file,
)
from core.paths import RAW_RECORDING_FOLDERS, EnginePaths, resolve_data_root
from core.secrets import scrubbed_env
from phone_capture.adb import find_on_path

Ask = Callable[[str], str]
Out = Callable[[str], None]

# Word for word from spec Section 5.3, which a test compares against.
CHECKLIST = (
    "Logged in to the demo account only, not the real account.",
    "Household switcher shows only the demo household.",
    "Do Not Disturb is on; no messages or calls can pop up.",
    "Demo-mode status bar is showing (or the bar will be cropped out).",
    "App language and theme match what this shot needs.",
    "No real name, photo, email, phone number or IBAN is visible anywhere, including settings and "
    "the profile screen.",
    "No bank name or logo in the frame, ever (D29).",
    "No real merchant or store name or logo in the frame unless legal check L4 is cleared. The one "
    "exception is a `smart_basket` clip, where the names on screen are masked at render (D30).",
    "Debug banners and test toasts are off.",
    "For a final clip: the launch gate is met and the build on screen says Qawam Money / قوام المال"
    '. On the base of this branch, the Android label and app title still say "Budget Tracker" and '
    'the Arabic title says "ميزانية الأسرة". Until then, clips are test clips only (D23).',
)
STATUS_BAR_LINE = CHECKLIST[3]  # capture asks this one once demo mode is on, so it can be seen

FFMPEG_TIMEOUT_SECONDS = 600
VIDEO_SUFFIXES = {".mp4", ".mov", ".m4v", ".webm", ".mkv", ".3gp"}

_FINAL_CLIP = re.compile(r"final_clip_\d+\.mp4")
_NUMBERED_CLIP = re.compile(r"(?:final_)?clip_(\d+)\.mp4(?:\.part)?")
_APP_VERSION = re.compile(r"[0-9A-Za-z][0-9A-Za-z._+-]{0,39}")
# Survives cmd.exe unread: npx is a batch file, which reads & % ^ ( ) and quotes as code.
_ARGUMENT_CMD_CANNOT_MISREAD = re.compile(r"[A-Za-z0-9_./:+=-]+")
_CMD_METACHARACTERS = set('&|<>^%!"')
_MASK_SEPARATOR = re.compile(r"[\s,]+")


class CaptureError(RuntimeError):
    """The capture or ingest step cannot go on. The message says why."""


class ChecklistRefused(CaptureError):
    """The owner did not confirm a checklist line."""


class CaptureAborted(CaptureError):
    """The terminal closed in the middle of a step."""


def is_yes(ask: Ask, prompt: str) -> bool:
    """Only a typed yes counts. A closed input is not an answer."""
    try:
        return ask(prompt).strip().casefold() == "yes"
    except EOFError:
        return False


@dataclass(frozen=True)
class ChecklistConfirmation:
    """Proof that every line was answered yes. A test keeps its one constructor call in here."""

    feature: str
    lines: tuple[str, ...]


class Checklist:
    """Line by line, and it can be asked in stages. Refusing any line ends the session."""

    def __init__(self, feature: str):
        self._feature = feature
        self._confirmed: set[str] = set()

    def confirm(self, lines: Iterable[str], *, ask: Ask) -> None:
        for line in lines:
            if not is_yes(ask, f"{line}\nType yes to confirm: "):
                raise ChecklistRefused(f"Checklist line not confirmed: {line}")
            self._confirmed.add(line)

    def confirmation(self) -> ChecklistConfirmation:
        missing = [line for line in CHECKLIST if line not in self._confirmed]
        if missing:
            raise ChecklistRefused(f"Checklist lines not confirmed: {missing}")
        return ChecklistConfirmation(self._feature, CHECKLIST)


# --- Test clips and final clips ---------------------------------------------------------


def is_final_clip(clip_path: str) -> bool:
    return bool(_FINAL_CLIP.fullmatch(clip_path.rsplit("/", 1)[-1]))


def check_clip_for_reel(clip_path: str, *, test_reel: bool) -> None:
    """A clip recorded before the launch gate shows the old name, so it stays in test reels."""
    if not test_reel and not is_final_clip(clip_path):
        raise ClipRejected(f"{clip_path} is a test clip, and a public reel needs a final clip")


def require_gate_for_final(config: EngineConfig, final: bool) -> None:
    if final and not is_gate_met(config):
        reasons = "; ".join(gate_failures(config))
        raise CaptureError(f"Final clips wait for the launch gate (D23). Still open: {reasons}")


def next_clip_path(paths: EnginePaths, feature: str, *, final: bool) -> Path:
    """A number held by a file or by the manifest is never used again, so nothing is overwritten
    and an old signature can never describe a new file."""
    folder = paths.raw_recordings / feature
    manifest = ClipManifest.load(paths.manifest)
    names = [entry.name for entry in folder.iterdir()]
    names += [entry.path.split("/", 1)[1] for entry in manifest.clips if entry.folder == feature]
    matches = (_NUMBERED_CLIP.fullmatch(name) for name in names)
    number = max((int(match.group(1)) for match in matches if match), default=0) + 1
    prefix = "final_" if final else ""
    return folder / f"{prefix}clip_{number:02d}.mp4"


# --- Where clips live -------------------------------------------------------------------


def check_feature(feature: str) -> None:
    if feature not in RAW_RECORDING_FOLDERS:
        raise CaptureError(f"{feature!r} is not a folder in the shot list (spec Section 5.4)")


def prepare_paths(config: EngineConfig) -> EnginePaths:
    """`resolve_data_root` keeps data out of OneDrive and git. A link further down could still
    lead back there, so each feature folder has to really be where it looks like it is."""
    paths = EnginePaths.from_root(resolve_data_root(config.paths.data_root))
    real_root = os.path.realpath(paths.data_root)
    for feature in RAW_RECORDING_FOLDERS:
        folder = paths.raw_recordings / feature
        folder.mkdir(parents=True, exist_ok=True)
        expected = os.path.join(real_root, "assets", "raw_recordings", feature)
        if os.path.normcase(os.path.realpath(folder)) != os.path.normcase(expected):
            raise CaptureError(f"{folder} is a link, and clips must stay in the data_root")
    return paths


# --- The sign-off -----------------------------------------------------------------------


@dataclass(frozen=True)
class OwnerAnswers:
    privacy_clean: bool
    mask_regions: tuple[MaskRegion, ...] = ()
    store_names_masked: bool = False


def _parse_mask(text: str) -> MaskRegion | None:
    parts = [part for part in _MASK_SEPARATOR.split(text.strip()) if part]
    if len(parts) != 4:
        return None
    try:
        x, y, width, height = (float(part) for part in parts)
        return MaskRegion(x=x, y=y, width=width, height=height)
    except ValueError:  # pydantic's ValidationError is a ValueError
        return None


def _ask_masks(ask: Ask, out: Out) -> tuple[MaskRegion, ...]:
    out(
        "Mask regions are fractions of the clip's width and height: x y width height, such as "
        "0.1 0.2 0.5 0.05. Cover every store name, logo and cheapest store line. An empty line "
        "ends the list."
    )
    regions: list[MaskRegion] = []
    while len(regions) < MAX_MASK_REGIONS:
        try:
            text = ask(f"Mask region {len(regions) + 1}: ")
        except EOFError:
            break
        if not text.strip():
            break
        region = _parse_mask(text)
        if region is None:
            out("That is not a usable region. It may be too small or run off the clip.")
        else:
            regions.append(region)
    return tuple(regions)


def ask_sign_off(feature: str, file: Path, *, ask: Ask, out: Out) -> OwnerAnswers:
    """Whatever the answers, the caller records nothing unless `privacy_clean` comes back true,
    and a Smart Basket clip also has to have its masks confirmed (D30, G19)."""
    prompt = f"Watch this file to the end: {file} \nIs it privacy-clean? Type yes to sign off: "
    if not is_yes(ask, prompt):
        return OwnerAnswers(privacy_clean=False)
    if feature != MASKED_FOLDER:
        return OwnerAnswers(privacy_clean=True)
    out(
        "Smart Basket clip: the mask regions below are blurred at render, and the illustrative "
        "prices / أسعار توضيحية label is added there too. Neither can be left out."
    )
    regions = _ask_masks(ask, out)
    if not regions:
        return OwnerAnswers(privacy_clean=False)
    covered = is_yes(
        ask,
        "Do these regions cover every store name, logo and cheapest store line for the whole "
        "clip? Type yes to confirm: ",
    )
    if not covered:
        return OwnerAnswers(privacy_clean=False)
    return OwnerAnswers(privacy_clean=True, mask_regions=regions, store_names_masked=True)


def ask_app_version(given: str | None, *, ask: Ask) -> str:
    """Clips are tagged with the version they show, so stale screens can be re-recorded."""
    if given is None:
        try:
            given = ask("Which app version is on the phone? Settings shows it: ")
        except EOFError:
            given = ""
    version = given.strip()
    if not _APP_VERSION.fullmatch(version):
        raise CaptureError(f"The app version must look like 1.4.2 or 1.4.2+9, got {version!r}")
    return version


def record_clip(
    paths: EnginePaths,
    file: Path,
    *,
    sha256: str,
    confirmation: ChecklistConfirmation,
    answers: OwnerAnswers,
    app_version: str,
    config: EngineConfig,
    final: bool,
) -> ClipEntry:
    """The only way into the manifest. `sha256` is the hash of what the owner watched, and
    `add_clip` refuses the clip if the file on disk no longer has it."""
    file = Path(file)
    feature = file.parent.name
    if feature not in RAW_RECORDING_FOLDERS or file.parent != paths.raw_recordings / feature:
        raise ClipRejected(f"{file} is not in a feature folder under {paths.raw_recordings}")
    if (
        not isinstance(confirmation, ChecklistConfirmation)
        or confirmation.feature != feature
        or confirmation.lines != CHECKLIST
    ):
        raise ClipRejected("The pre-capture checklist was not confirmed for this clip")
    if answers.privacy_clean is not True:
        raise ClipRejected("The owner has not signed this clip off as privacy-clean")
    if final and not is_gate_met(config):
        raise ClipRejected("A final clip needs the launch gate to be met (D23)")
    if is_final_clip(file.name) != final:
        raise ClipRejected(
            f"{file.name} has the wrong name: only a final clip is named final_clip_NN.mp4"
        )
    try:
        entry = ClipEntry(
            path=f"{feature}/{file.name}",
            sha256=sha256,
            privacy_checked=True,
            app_version=app_version,
            store_names_masked=answers.store_names_masked,
            mask_regions=list(answers.mask_regions),
        )
    except ValidationError as error:
        raise ClipRejected(f"This clip cannot be signed off: {error}") from error
    manifest = ClipManifest.load(paths.manifest)
    manifest.add_clip(entry, paths.raw_recordings).save(paths.manifest)
    return entry


# --- Stripping metadata -----------------------------------------------------------------


def _ffmpeg_command(config: EngineConfig, paths: EnginePaths, staging: Path) -> tuple[list, Path]:
    """Remotion's bundled FFmpeg unless the owner set `render.ffmpeg_path` (plan Section 2.4).
    `--no` stops npx from downloading anything when the local package is missing."""
    configured = config.render.ffmpeg_path
    if configured:
        tool = Path(configured)
        if not tool.is_absolute() or tool.suffix.casefold() != ".exe" or not tool.is_file():
            raise CaptureError(f"render.ffmpeg_path must be an existing .exe, got {configured!r}")
        return [str(tool)], staging
    npx = find_on_path("npx.cmd")
    if npx is None:
        raise CaptureError("npx was not found on PATH, and it runs Remotion's bundled FFmpeg")
    if _CMD_METACHARACTERS & set(str(npx)):
        raise CaptureError(f"npx is in a folder cmd.exe cannot read safely: {npx}")
    if not paths.remotion_work.is_dir():
        raise CaptureError(
            f"{paths.remotion_work} does not exist. Run python -m core.remotion_sync and "
            "npm install there first, since it holds Remotion's bundled FFmpeg."
        )
    return [str(npx), "--no", "remotion", "ffmpeg"], paths.remotion_work


def _relative_argument(path: Path, cwd: Path) -> str:
    argument = os.path.relpath(path, cwd).replace("\\", "/")
    if not _ARGUMENT_CMD_CANNOT_MISREAD.fullmatch(argument):
        raise CaptureError(f"unsafe path for the FFmpeg command: {argument!r}")
    return argument


def strip_metadata(source: Path, output: Path, config: EngineConfig, paths: EnginePaths) -> None:
    """Re-encodes, so nothing of the container's metadata can survive. Sound goes too: reels use
    the voiceover, and a phone's own recorder may have picked up the room. FFmpeg's own output
    stays out of the message, in the same way as npm's in `core.remotion_sync`."""
    command, cwd = _ffmpeg_command(config, paths, Path(source).parent)
    args = [
        *command,
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        _relative_argument(source, cwd),
        "-map",
        "0:v:0",
        "-an",
        "-sn",
        "-dn",
        "-map_metadata",
        "-1",
        "-map_chapters",
        "-1",
        "-c:v",
        "libx264",
        "-crf",
        "18",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "-fflags",
        "+bitexact",
        _relative_argument(output, cwd),
    ]
    try:
        result = subprocess.run(
            args,
            cwd=cwd,
            env=scrubbed_env(None),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=FFMPEG_TIMEOUT_SECONDS,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError) as error:
        raise CaptureError(f"FFmpeg could not finish: {type(error).__name__}") from error
    if result.returncode != 0:
        raise CaptureError(f"FFmpeg failed with exit code {result.returncode}")
    if not Path(output).is_file() or Path(output).stat().st_size == 0:
        raise CaptureError("FFmpeg reported success but wrote no file")


# --- The manual fallback ----------------------------------------------------------------


@dataclass
class IngestReport:
    signed: list[str] = field(default_factory=list)
    declined: list[str] = field(default_factory=list)
    failed: dict[str, str] = field(default_factory=dict)


def _is_link(path: Path) -> bool:
    attributes = getattr(os.lstat(path), "st_file_attributes", 0)
    return bool(attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT) or path.is_symlink()


def _new_files(paths: EnginePaths, feature: str | None, out: Out) -> list[tuple[str, Path]]:
    if feature is None:
        for loose in sorted(paths.raw_recordings.iterdir()):
            if loose.is_file() and loose.suffix.casefold() in VIDEO_SUFFIXES:
                out(f"Skipped {loose.name}: move it into a feature folder first.")
    known = {entry.path for entry in ClipManifest.load(paths.manifest).clips}
    found = []
    for folder in (feature,) if feature else RAW_RECORDING_FOLDERS:
        for file in sorted((paths.raw_recordings / folder).iterdir()):
            if file.suffix.casefold() not in VIDEO_SUFFIXES or f"{folder}/{file.name}" in known:
                continue
            if _is_link(file):
                out(f"Skipped {folder}/{file.name}: it is a link, not a recording.")
            elif not file.is_file():
                continue
            elif file.stat().st_size == 0:
                out(f"Skipped {folder}/{file.name}: the file is empty.")
            else:
                found.append((folder, file))
    return found


def _keep_original(paths: EnginePaths, feature: str, source: Path) -> Path:
    """Moved out of the way and never deleted, since deleting data is the owner's call."""
    folder = paths.manifest.parent / "ingest_originals" / feature
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / source.name
    count = 1
    while target.exists():
        count += 1
        target = folder / f"{source.stem}_{count}{source.suffix}"
    os.rename(source, target)
    return target


def _ingest_file(
    config: EngineConfig,
    paths: EnginePaths,
    feature: str,
    source: Path,
    *,
    final: bool,
    app_version: str | None,
    ask: Ask,
    out: Out,
) -> str | None:
    """Returns the signed clip's path, or None when the owner did not sign it off. The working
    folder has a generated name, so the owner's file name never reaches FFmpeg's command line."""
    staging = paths.manifest.parent / "ingest_tmp" / uuid.uuid4().hex
    staging.mkdir(parents=True)
    try:
        staged_source = staging / f"source{source.suffix.casefold()}"
        shutil.copyfile(source, staged_source)
        cleaned = staging / "output.mp4"
        strip_metadata(staged_source, cleaned, config, paths)
        digest = sha256_file(cleaned)
        out(f"Cleaned copy of {feature}/{source.name} has SHA-256 {digest}")

        checklist = Checklist(feature)
        checklist.confirm(CHECKLIST, ask=ask)
        confirmation = checklist.confirmation()
        answers = ask_sign_off(feature, cleaned, ask=ask, out=out)
        if not answers.privacy_clean:
            return None
        version = ask_app_version(app_version, ask=ask)
        if sha256_file(cleaned) != digest:
            raise ClipRejected(f"{cleaned} does not match its signed hash")

        target = next_clip_path(paths, feature, final=final)
        os.rename(cleaned, target)
        try:
            record_clip(
                paths,
                target,
                sha256=digest,
                confirmation=confirmation,
                answers=answers,
                app_version=version,
                config=config,
                final=final,
            )
        except BaseException:
            os.rename(target, cleaned)
            raise
        try:
            _keep_original(paths, feature, source)
        except OSError as error:
            out(f"Signed off, but {source.name} could not be moved: {error}")
        return f"{feature}/{target.name}"
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def run_ingest(
    config: EngineConfig,
    *,
    ask: Ask,
    out: Out,
    feature: str | None = None,
    final: bool = False,
    app_version: str | None = None,
) -> IngestReport:
    """One problem file does not stop the others. Files that were not signed stay where they are
    and cannot be rendered, and the next run asks about them again."""
    if feature is not None:
        check_feature(feature)
    require_gate_for_final(config, final)
    paths = prepare_paths(config)
    files = _new_files(paths, feature, out)
    report = IngestReport()
    if not files:
        out(f"Nothing to ingest. Drop recordings into a feature folder in {paths.raw_recordings}")
    for folder, source in files:
        label = f"{folder}/{source.name}"
        try:
            signed = _ingest_file(
                config,
                paths,
                folder,
                source,
                final=final,
                app_version=app_version,
                ask=ask,
                out=out,
            )
        except ChecklistRefused:
            signed = None
        except (CaptureError, ClipRejected, OSError) as error:
            report.failed[label] = str(error)
            out(f"Could not ingest {label}: {error}")
            continue
        if signed is None:
            report.declined.append(label)
            out(f"{label} was not signed off, so it cannot be used.")
        else:
            report.signed.append(signed)
            out(f"Signed off {signed}{'' if final else ' as a test clip'}.")
    return report
