"""The pre-capture checklist, the owner's sign-off and the manual fallback (spec Sections 5.1
to 5.3, decisions D22, D23 and D30, guardrails G15 and G19).

**Sign-off.** A clip reaches `manifest.json` only through `record_clip`, and that needs a
confirmation that only a fully answered `Checklist` hands out. Only a typed `yes` counts.

**Test clips.** A clip is final only when its signed record holds a seal, which `record_clip` and
`record_screenshot` make while the launch gate is met (D23). The seal is keyed with a file kept
apart from the manifest and covers the path, hash and app version, so renaming a test clip and
editing its manifest line cannot promote it. Every other clip is a test clip. Someone who also
reads the key file can forge a seal, so this stops edits and mistakes, not the machine's owner.
`check_clip_for_reel` is the check for whoever picks clips or pictures for a public reel.

**Manual fallback.** The owner records with the phone's own recorder and drops files into a feature
folder. `run_ingest` strips each one by re-encoding and signs the cleaned copy, not the original.
"""

from __future__ import annotations

import hmac
import os
import re
import secrets
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
from phone_capture import process_tree
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
# Without regard to case, because Windows treats CLIP_01.MP4 and clip_01.mp4 as one file.
_NUMBERED_CLIP = re.compile(r"(?:final_)?clip_(\d+)\.mp4(?:\.part)?", re.IGNORECASE)
_TEST_SCREENSHOT = re.compile(r"screen_\d+\.png")
_FINAL_SCREENSHOT = re.compile(r"final_screen_\d+\.png")
_NUMBERED_SCREENSHOT = re.compile(r"(?:final_)?screen_(\d+)\.png(?:\.part)?", re.IGNORECASE)
_SCREENSHOT_MANIFEST = "manifest.json"
_SEAL_KEY_FILE = "clip_seal.key"
_SEAL_KEY_BYTES = 32
_CLIP_MASK_NOTE = (
    "Smart Basket clip: the mask regions below are blurred at render, and the illustrative "
    "prices / أسعار توضيحية label is added there too. Neither can be left out."
)
_SCREENSHOT_MASK_NOTE = (
    "Smart Basket screenshot: this file stays unmasked on disk, and nothing masks it yet. The "
    "regions below are kept with it, and any use has to apply them and the illustrative prices / "
    "أسعار توضيحية label."
)
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
    """Whether the name is right for a final clip. Only `is_sealed_final` says that it is one."""
    return bool(_FINAL_CLIP.fullmatch(clip_path.rsplit("/", 1)[-1]))


def _seal_key_path(paths: EnginePaths) -> Path:
    return paths.state_db.parent / _SEAL_KEY_FILE


def _existing_seal_key(paths: EnginePaths) -> bytes | None:
    """None for anything but a plain, whole key inside the data_root, which leaves every clip a
    test clip rather than trusting a key that came from somewhere else."""
    file = _seal_key_path(paths)
    parts = file.relative_to(paths.data_root).parts
    expected = os.path.join(os.path.realpath(paths.data_root), *parts)
    try:
        if os.path.normcase(os.path.realpath(file)) != os.path.normcase(expected):
            return None
        key = file.read_bytes()
    except OSError:
        return None
    return key if len(key) == _SEAL_KEY_BYTES else None


def _new_or_existing_seal_key(paths: EnginePaths) -> bytes:
    file = _seal_key_path(paths)
    _checked_folder(paths, file.parent, "the seal key")
    try:
        with open(file, "xb") as handle:
            handle.write(secrets.token_bytes(_SEAL_KEY_BYTES))
    except FileExistsError:
        pass
    key = _existing_seal_key(paths)
    if key is None:
        raise ClipRejected(f"{file} cannot be used to seal a final clip")
    return key


def _final_seal(key: bytes, path: str, sha256: str, app_version: str) -> str:
    signed = "\0".join((path, sha256, app_version)).encode("utf-8")
    return hmac.new(key, signed, "sha256").hexdigest()


def is_sealed_final(entry: ClipEntry, paths: EnginePaths) -> bool:
    """Fails closed: no seal, no key or a seal for another path, hash or version is a test clip."""
    if entry.final_seal is None:
        return False
    key = _existing_seal_key(paths)
    if key is None:
        return False
    expected = _final_seal(key, entry.path, entry.sha256, entry.app_version)
    return hmac.compare_digest(entry.final_seal, expected)


def check_clip_for_reel(entry: ClipEntry, paths: EnginePaths, *, test_reel: bool) -> None:
    """A clip or picture from before the launch gate shows the old name, so it stays in test
    reels. Pass the entry from `ClipManifest.verified_clip`, which has checked the file's hash."""
    if not test_reel and not is_sealed_final(entry, paths):
        raise ClipRejected(f"{entry.path} is a test clip, and a public reel needs a final clip")


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


def screenshot_manifest_path(paths: EnginePaths) -> Path:
    """Apart from `paths.manifest`, so a picture can never reach the clip allow-list."""
    return paths.screenshots / _SCREENSHOT_MANIFEST


def next_screenshot_path(paths: EnginePaths, feature: str, *, final: bool) -> Path:
    """As in `next_clip_path`, a number is never used twice."""
    folder = paths.screenshots / feature
    manifest = ClipManifest.load(screenshot_manifest_path(paths))
    names = [entry.name for entry in folder.iterdir()]
    names += [entry.path.split("/", 1)[1] for entry in manifest.clips if entry.folder == feature]
    matches = (_NUMBERED_SCREENSHOT.fullmatch(name) for name in names)
    number = max((int(match.group(1)) for match in matches if match), default=0) + 1
    prefix = "final_" if final else ""
    return folder / f"{prefix}screen_{number:02d}.png"


# --- Where clips live -------------------------------------------------------------------


def check_feature(feature: str) -> None:
    if feature not in RAW_RECORDING_FOLDERS:
        raise CaptureError(f"{feature!r} is not a folder in the shot list (spec Section 5.4)")


def _checked_folder(paths: EnginePaths, folder: Path, what: str) -> Path:
    """Made and checked level by level from the data_root down, so a link at any level has
    nothing made or written through it."""
    paths.data_root.mkdir(parents=True, exist_ok=True)
    current = paths.data_root
    expected = os.path.realpath(paths.data_root)
    for part in folder.relative_to(paths.data_root).parts:
        current = current / part
        expected = os.path.join(expected, part)
        current.mkdir(exist_ok=True)
        if os.path.normcase(os.path.realpath(current)) != os.path.normcase(expected):
            raise CaptureError(f"{current} is a link, and {what} must stay in the data_root")
    return folder


def prepare_paths(config: EngineConfig) -> EnginePaths:
    """`resolve_data_root` keeps data out of OneDrive and git. A link further down could still
    lead back there, so each feature folder has to really be where it looks like it is."""
    paths = EnginePaths.from_root(resolve_data_root(config.paths.data_root))
    for feature in RAW_RECORDING_FOLDERS:
        _checked_folder(paths, paths.raw_recordings / feature, "clips")
    return paths


def prepare_screenshot_folder(paths: EnginePaths, feature: str) -> Path:
    return _checked_folder(paths, paths.screenshots / feature, "screenshots")


def _ingest_tmp(paths: EnginePaths) -> Path:
    return _checked_folder(paths, paths.manifest.parent / "ingest_tmp", "ingest copies")


def _originals_folder(paths: EnginePaths, feature: str) -> Path:
    folder = paths.manifest.parent / "ingest_originals" / feature
    return _checked_folder(paths, folder, "original recordings")


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


def ask_sign_off(
    feature: str, file: Path, *, ask: Ask, out: Out, screenshot: bool = False
) -> OwnerAnswers:
    """Whatever the answers, the caller records nothing unless `privacy_clean` comes back true,
    and a Smart Basket clip also has to have its masks confirmed (D30, G19)."""
    look = "Look over this picture" if screenshot else "Watch this file to the end"
    prompt = f"{look}: {file} \nIs it privacy-clean? Type yes to sign off: "
    if not is_yes(ask, prompt):
        return OwnerAnswers(privacy_clean=False)
    if feature != MASKED_FOLDER:
        return OwnerAnswers(privacy_clean=True)
    out(_SCREENSHOT_MASK_NOTE if screenshot else _CLIP_MASK_NOTE)
    regions = _ask_masks(ask, out)
    if not regions:
        return OwnerAnswers(privacy_clean=False)
    covered = is_yes(
        ask,
        "Do these regions cover every store name, logo and cheapest store line for the whole "
        f"{'picture' if screenshot else 'clip'}? Type yes to confirm: ",
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
    feature = _checked_sign_off(file, paths.raw_recordings, confirmation, answers, config, final)
    if is_final_clip(file.name) != final:
        raise ClipRejected(
            f"{file.name} has the wrong name: only a final clip is named final_clip_NN.mp4"
        )
    seal = _seal_if_final(paths, final, feature, file, sha256, app_version)
    return _save_signed_entry(
        feature, file, sha256, answers, app_version, seal, paths.manifest, paths.raw_recordings
    )


def record_screenshot(
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
    """The only way into the screenshot manifest, with the same proof as `record_clip`."""
    file = Path(file)
    feature = _checked_sign_off(file, paths.screenshots, confirmation, answers, config, final)
    if not (_FINAL_SCREENSHOT if final else _TEST_SCREENSHOT).fullmatch(file.name):
        raise ClipRejected(
            f"{file.name} has the wrong name: use screen_NN.png, or final_screen_NN.png if final"
        )
    manifest_path = screenshot_manifest_path(paths)
    seal = _seal_if_final(paths, final, feature, file, sha256, app_version)
    return _save_signed_entry(
        feature, file, sha256, answers, app_version, seal, manifest_path, paths.screenshots
    )


def _checked_sign_off(
    file: Path,
    root: Path,
    confirmation: ChecklistConfirmation,
    answers: OwnerAnswers,
    config: EngineConfig,
    final: bool,
) -> str:
    """What every signature needs. Returns the feature folder the file is in."""
    feature = file.parent.name
    if feature not in RAW_RECORDING_FOLDERS or file.parent != root / feature:
        raise ClipRejected(f"{file} is not in a feature folder under {root}")
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
    return feature


def _seal_if_final(
    paths: EnginePaths, final: bool, feature: str, file: Path, sha256: str, app_version: str
) -> str | None:
    if not final:
        return None
    key = _new_or_existing_seal_key(paths)
    return _final_seal(key, f"{feature}/{file.name}", sha256, app_version)


def _save_signed_entry(
    feature: str,
    file: Path,
    sha256: str,
    answers: OwnerAnswers,
    app_version: str,
    final_seal: str | None,
    manifest_path: Path,
    root: Path,
) -> ClipEntry:
    try:
        entry = ClipEntry(
            path=f"{feature}/{file.name}",
            sha256=sha256,
            privacy_checked=True,
            app_version=app_version,
            store_names_masked=answers.store_names_masked,
            mask_regions=list(answers.mask_regions),
            final_seal=final_seal,
        )
    except ValidationError as error:
        raise ClipRejected(f"This clip cannot be signed off: {error}") from error
    manifest = ClipManifest.load(manifest_path)
    manifest.add_clip(entry, root).save(manifest_path)
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
        result = process_tree.run(
            args, cwd=cwd, env=scrubbed_env(None), timeout=FFMPEG_TIMEOUT_SECONDS
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
    known = {entry.path.casefold() for entry in ClipManifest.load(paths.manifest).clips}
    found = []
    for folder in (feature,) if feature else RAW_RECORDING_FOLDERS:
        for file in sorted((paths.raw_recordings / folder).iterdir()):
            is_signed = f"{folder}/{file.name}".casefold() in known
            if file.suffix.casefold() not in VIDEO_SUFFIXES or is_signed:
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
    folder = _originals_folder(paths, feature)
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
    staging = _ingest_tmp(paths) / uuid.uuid4().hex
    staging.mkdir()
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
        except (OSError, CaptureError) as error:
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
    if files:
        _ingest_tmp(paths)  # refused here, before the owner has answered anything
    for folder in {folder for folder, _ in files}:
        _originals_folder(paths, folder)
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
