"""Render a reel through Remotion and keep the file only if it passes (spec Sections 3.5, 5.2,
8.3, 8.6, guardrails G15, G16, G19).

`render_reel` is the only way to render. A caller describes the reel, and the safety values
are not its to give: `watermark` is `ReelBrand.is_test`, and each clip's folder, hash and
`mask_regions` come from `ClipManifest.verified_clip()`, read from the manifest on disk. So a
caller cannot pass a different value, and a test reel cannot render without the watermark.

Only allow-listed files reach `public/`, the folder is rebuilt by the sync before every render,
and each copied file is hashed again, so what renders is what was checked.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from pydantic import BaseModel, ConfigDict, ValidationError

from core.brand_gate import BrandGateError, ReelBrand, brand_for_reel, render_decision
from core.config import EngineConfig, Render, strings_in
from core.manifest import ClipEntry, ClipManifest, sha256_file
from core.mp4_check import Mp4Error, Mp4TooLarge, check_output
from core.paths import ENGINE_ROOT, EnginePaths, PathConfigError, expand_path
from core.remotion_sync import RemotionSyncError, checked_kept_folders, sync
from core.render_props import (
    CaptionWord,
    FocalPoint,
    PropsBrand,
    PublicPath,
    ReelLanguage,
    RenderProps,
    Template,
)
from core.secrets import scrubbed_env

BYTES_PER_MB = 1_000_000  # the spec's table counts 47 MB as 47,000 kB, the stricter reading
MAX_RENDERS = 3  # the first, then a lower bitrate up to twice (spec Section 8.6)
WIDTH = 1080
HEIGHT = 1920

_BUDGET_MARGIN_MB = 1  # the spec aims at 47 MB and refuses over 48 MB
_RETRY_PERCENT = 85
_BANNED_COLOUR = "#c9933b"  # looks like a brand colour, and is not one (spec Section 8.5)
_HEX_COLOUR = re.compile(r"#[0-9A-Fa-f]{6}")
_AUDIO_SUFFIXES = {".wav", ".mp3", ".m4a", ".aac"}
_STEP_TIMEOUT_S = 30 * 60
_KILL_WAIT_S = 30
_HASH_CHARS = 12


class RenderError(RuntimeError):
    """No file came out of this render. The message says why."""


class RenderRefused(RenderError):
    """A gate said no, before anything ran. Trying again will not help."""


class RenderFailed(RenderError):
    """The render ran and gave no file that can be delivered."""


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class ClipUse(_Strict):
    """Which signed clip to show, and when. Everything else about it comes from the manifest."""

    path: str  # <folder>/<file>, as in manifest.json
    start_ms: int
    end_ms: int
    focal_point: FocalPoint | None = None  # what the camera zooms to in this use of the clip


class RenderRequest(_Strict):
    """What a caller may decide about a reel. Unknown fields are refused, so there is no place
    here for account data, the watermark or a mask."""

    reel_id: str
    revision: int
    template: Template
    language: ReelLanguage
    duration_ms: int
    highlight_color: str
    hook_text: str
    on_screen_text: list[str]
    subtitles_en: str
    words: list[CaptionWord]
    voiceover: PublicPath  # relative to assets/audio/voiceovers
    music: PublicPath | None = None  # relative to assets/audio/bg_music
    clips: list[ClipUse] = []


@dataclass(frozen=True)
class RenderResult:
    path: Path
    sha256: str
    size_bytes: int
    content_hash: str
    video_kbps: int | None  # None for a reused file
    renders: int
    reused: bool


def video_kbps(duration_ms: int, render: Render) -> int:
    """min(8000, floor(47 MB x 8000 / duration_s) - 192), from the configured values."""
    budget_mb = render.max_mb - _BUDGET_MARGIN_MB
    kbps = budget_mb * 8000 * 1000 // duration_ms - render.audio_kbps
    if kbps <= 0:
        raise RenderRefused(
            f"a {duration_ms} ms reel leaves no video bitrate within {render.max_mb} MB"
        )
    return min(render.video_kbps_cap, kbps)


def lower_bitrate(kbps: int) -> int:
    return kbps * _RETRY_PERCENT // 100


@dataclass(frozen=True)
class _Stage:
    """A file to copy into `public/`, and the hash it has to have once it is there."""

    source: Path
    public_path: str
    sha256: str


@dataclass(frozen=True)
class _Inputs:
    props: RenderProps
    stages: tuple[_Stage, ...]
    content_hash: str


def _describe(error: ValidationError) -> str:
    """Field names and rules only. Pydantic's own text repeats the input, which is the very
    account data that was refused."""
    return "; ".join(
        f"{'.'.join(str(part) for part in item['loc']) or 'value'}: {item['msg']}"
        for item in error.errors()
    )


def _reel_brand(config: EngineConfig, test_reel: bool) -> ReelBrand:
    decision = render_decision(config, test_reel=test_reel)
    if not decision.allowed:
        raise RenderRefused(f"launch gate not met: {'; '.join(decision.reasons)}")
    try:
        brand = brand_for_reel(config, test_reel=test_reel)
    except BrandGateError as error:
        raise RenderRefused(str(error)) from error
    if brand.is_test is not test_reel:
        raise RenderRefused(f"the brand has is_test={brand.is_test} on a reel with {test_reel=}")
    return brand


def _check_colours(highlight: str, config: EngineConfig, engine_root: Path) -> None:
    tokens = engine_root / config.brand.tokens
    try:
        data = json.loads(tokens.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise RenderRefused(f"G16: cannot read the brand tokens: {error}") from error
    allowed = {
        colour.casefold()
        for _, text in strings_in(data, "")
        for colour in _HEX_COLOUR.findall(text)
    }
    if not allowed:
        raise RenderRefused(f"G16: {tokens.name} lists no colours")
    if _BANNED_COLOUR in allowed:
        raise RenderRefused(f"G16: {tokens.name} lists the banned colour {_BANNED_COLOUR}")
    if highlight.casefold() not in allowed:
        raise RenderRefused(f"G16: {highlight[:16]!r} is not a brand colour")
    templates = engine_root / "remotion_studio" / "src"
    for file in sorted(templates.rglob("*")):
        if file.is_file() and _BANNED_COLOUR.encode() in file.read_bytes().lower():
            raise RenderRefused(f"G16: {file.name} uses the banned colour {_BANNED_COLOUR}")


def _verified_clips(request: RenderRequest, paths: EnginePaths) -> list[ClipEntry]:
    try:
        manifest = ClipManifest.load(paths.manifest)
    except ValidationError as error:
        raise RenderRefused(f"manifest.json cannot be used: {_describe(error)}") from None
    except (OSError, ValueError) as error:
        raise RenderRefused(f"manifest.json cannot be read: {error}") from error
    try:
        return [manifest.verified_clip(use.path, paths.raw_recordings) for use in request.clips]
    except (OSError, ValueError) as error:  # ClipRejected is a ValueError
        raise RenderRefused(f"G15: {error}") from error


def _allowed_audio(folder: Path, relative: str, what: str) -> Path:
    """Audio the engine made or the owner licensed, from its own folder and nowhere else. The
    field's schema already refuses `..` and absolute paths, and a link is refused here."""
    if Path(relative).suffix.casefold() not in _AUDIO_SUFFIXES:
        raise RenderRefused(f"{what} {relative} is not an audio file")
    file = folder / relative
    if not file.is_file():
        raise RenderRefused(f"{what} {relative} is missing from {folder}")
    expected = os.path.join(os.path.realpath(folder), relative)
    if os.path.normcase(os.path.realpath(file)) != os.path.normcase(expected):
        raise RenderRefused(f"{what} {relative} is a link to somewhere outside {folder}")
    return file


def _props_from(
    request: RenderRequest,
    config: EngineConfig,
    brand: ReelBrand,
    logo_src: str,
    entries: list[ClipEntry],
    music_src: str | None,
) -> RenderProps:
    clips = [
        {
            "src": f"clips/{entry.path}",
            "folder": entry.folder,
            "sha256": entry.sha256,
            "start_ms": use.start_ms,
            "end_ms": use.end_ms,
            "mask_regions": entry.mask_regions,
            "focal_point": use.focal_point,
        }
        for use, entry in zip(request.clips, entries, strict=True)
    ]
    try:
        return RenderProps.model_validate(
            {
                "reel_id": request.reel_id,
                "revision": request.revision,
                "template": request.template,
                "language": request.language,
                "width": WIDTH,
                "height": HEIGHT,
                "fps": config.render.fps,
                "duration_ms": request.duration_ms,
                "watermark": brand.is_test,
                "device_frame": "generic",
                "digits": config.captions.digits,
                "highlight_color": request.highlight_color,
                "safe_zones": config.render.safe_zones.strictest(),
                "brand": PropsBrand.model_validate(
                    {
                        "name_ar": brand.name_ar,
                        "name_en": brand.name_en,
                        "hashtag": brand.hashtag,
                        "logo_src": logo_src,
                    }
                ),
                "hook_text": request.hook_text,
                "on_screen_text": request.on_screen_text,
                "subtitles_en": request.subtitles_en,
                "audio_src": f"audio/{request.voiceover}",
                "music_src": music_src,
                "duck_under_voice": config.audio.duck_under_voice,
                "duck_in_pauses": config.audio.duck_in_pauses,
                "words": request.words,
                "clips": clips,
            }
        )
    except ValidationError as error:
        raise RenderRefused(f"the reel cannot be rendered: {_describe(error)}") from None


def _stages_for(
    request: RenderRequest,
    config: EngineConfig,
    paths: EnginePaths,
    logo: Path,
    entries: list[ClipEntry],
) -> tuple[list[_Stage], str | None]:
    stages = [
        _Stage(logo, logo.name, sha256_file(logo)),
        *(
            _Stage(paths.raw_recordings / entry.path, f"clips/{entry.path}", entry.sha256)
            for entry in entries
        ),
    ]
    voice = _allowed_audio(paths.voiceovers, request.voiceover, "voiceover")
    stages.append(_Stage(voice, f"audio/{request.voiceover}", sha256_file(voice)))
    if request.music is None:
        return stages, None
    if not config.audio.music_enabled:
        raise RenderRefused("music was asked for while audio.music_enabled is false (D25)")
    music = _allowed_audio(paths.bg_music, request.music, "music")
    music_src = f"audio/music/{request.music}"
    stages.append(_Stage(music, music_src, sha256_file(music)))
    return stages, music_src


def _digest_tree(digest, root: Path) -> None:
    for file in sorted(root.rglob("*")):
        if file.is_file():
            digest.update(f"{file.relative_to(root).as_posix()}\0{sha256_file(file)}\0".encode())


def _content_hash(
    props: RenderProps, stages: list[_Stage], config: EngineConfig, engine_root: Path
) -> str:
    """Props, clip hashes, template version and audio (spec Section 3.5), and what else changes
    the picture or the size: the logo, the fonts and the render settings."""
    digest = hashlib.sha256(props.model_dump_json().encode())
    for stage in stages:
        digest.update(f"{stage.public_path}\0{stage.sha256}\0".encode())
    render = config.render
    digest.update(f"{render.video_kbps_cap}\0{render.audio_kbps}\0{render.max_mb}\0".encode())
    _digest_tree(digest, engine_root / "remotion_studio")
    _digest_tree(digest, engine_root / "assets" / "branding")
    return digest.hexdigest()


def _checked_inputs(
    request: RenderRequest,
    config: EngineConfig,
    paths: EnginePaths,
    test_reel: bool,
    engine_root: Path,
) -> _Inputs:
    """Every gate, before anything is changed or run."""
    brand = _reel_brand(config, test_reel)
    try:
        _check_colours(request.highlight_color, config, engine_root)
        entries = _verified_clips(request, paths)
        logo = engine_root / brand.logo_path
        if not logo.is_file():
            raise RenderRefused(f"the logo {brand.logo_path} is missing from {engine_root}")
        stages, music_src = _stages_for(request, config, paths, logo, entries)
        props = _props_from(request, config, brand, logo.name, entries, music_src)
        video_kbps(props.duration_ms, config.render)  # no room for video is a refusal
        return _Inputs(props, tuple(stages), _content_hash(props, stages, config, engine_root))
    except OSError as error:
        raise RenderRefused(f"an input cannot be read: {error}") from error


def _checked_renders_folder(paths: EnginePaths) -> Path:
    """The finished file goes here, so a link here would put it somewhere else."""
    try:
        paths.renders.mkdir(parents=True, exist_ok=True)
        real = os.path.realpath(paths.renders, strict=True)
        expected = os.path.join(os.path.realpath(paths.data_root, strict=True), paths.renders.name)
    except OSError as error:
        raise RenderFailed(f"could not check {paths.renders}: {error}") from error
    if os.path.normcase(real) != os.path.normcase(expected):
        raise RenderFailed(f"{paths.renders} is really at {real}, not inside the data_root")
    return paths.renders


def _copy_into_public(stages: tuple[_Stage, ...], work: Path) -> None:
    for stage in stages:
        target = work / "public" / stage.public_path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(stage.source, target)
        if sha256_file(target) != stage.sha256:
            target.unlink()
            raise RenderRefused(f"{stage.public_path} changed after it was checked")


def _prepare_work_folder(inputs: _Inputs, engine_root: Path, paths: EnginePaths) -> None:
    work = paths.remotion_work
    try:
        sync(engine_root, paths.data_root)
        _copy_into_public(inputs.stages, work)
        checked_kept_folders(paths.data_root)
        (work / "out").mkdir(exist_ok=True)
    except RemotionSyncError as error:
        raise RenderFailed(str(error)) from error
    except OSError as error:
        raise RenderFailed(f"could not prepare {work}: {error}") from error


def _kill_tree(process: subprocess.Popen) -> None:
    # npx.cmd starts node, which starts the browser, and killing the first leaves the others.
    subprocess.run(
        ["taskkill", "/T", "/F", "/PID", str(process.pid)],
        capture_output=True,
        check=False,
    )
    try:
        process.wait(timeout=_KILL_WAIT_S)
    except subprocess.TimeoutExpired:
        pass


def _npx() -> str:
    npx = shutil.which("npx")
    if npx is None:
        raise RenderFailed("npx was not found on PATH")
    return npx


@dataclass(frozen=True)
class _Run:
    """One reel's files in `out/`. Commands name them relative to the work folder, so only
    validated names reach a command line that may pass through cmd.exe."""

    data_root: Path
    work: Path
    stem: str

    @property
    def rendered(self) -> str:
        return f"out/{self.stem}.render.mp4"

    @property
    def conformed(self) -> str:
        return f"out/{self.stem}.conformed.mp4"

    @property
    def props_file(self) -> str:
        return f"out/{self.stem}.props.json"

    @property
    def log(self) -> Path:
        return self.work / "out" / f"{self.stem}.log"

    def clear_outputs(self) -> None:
        """So a render that writes nothing cannot pass with the file from the try before it.
        These unlink, so a link left at one of these names is never written through."""
        (self.work / self.rendered).unlink(missing_ok=True)
        (self.work / self.conformed).unlink(missing_ok=True)

    def start(self, props: RenderProps) -> None:
        self.clear_outputs()
        self.log.unlink(missing_ok=True)
        (self.work / self.props_file).unlink(missing_ok=True)
        with open(self.work / self.props_file, "xb") as handle:
            handle.write(props.model_dump_json().encode("utf-8"))

    def clear_quietly(self) -> None:
        for name in (self.rendered, self.conformed, self.props_file):
            try:
                (self.work / name).unlink(missing_ok=True)
            except OSError:
                pass

    def execute(self, command: list[str], what: str) -> None:
        """npx output goes to a log and stays out of the message. With pipes, a child left
        running after a timeout would hold them open and hang this call."""
        try:
            checked_kept_folders(self.data_root)
            with open(self.log, "ab") as log:
                process = subprocess.Popen(
                    command,
                    cwd=self.work,
                    env=scrubbed_env(None),
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                )
                try:
                    code = process.wait(timeout=_STEP_TIMEOUT_S)
                except subprocess.TimeoutExpired:
                    _kill_tree(process)
                    raise RenderFailed(
                        f"{what} did not finish in {_STEP_TIMEOUT_S} s and was stopped"
                    ) from None
        except RemotionSyncError as error:
            raise RenderFailed(str(error)) from error
        except OSError as error:
            raise RenderFailed(f"{what} could not run: {error}") from error
        if code != 0:
            raise RenderFailed(f"{what} failed with exit code {code}. See {self.log}")


def _ffmpeg_command(config: EngineConfig) -> list[str]:
    configured = config.render.ffmpeg_path
    if not configured:
        return [_npx(), "--no", "remotion", "ffmpeg"]
    try:
        return [str(expand_path(configured))]
    except PathConfigError as error:
        raise RenderFailed(str(error)) from error


def _render_and_conform(
    run: _Run, props: RenderProps, config: EngineConfig, kbps: int
) -> None:
    """`--no` stops npx from downloading anything, so only what the lockfile installed runs."""
    run.execute(
        [
            _npx(),
            "--no",
            "remotion",
            "render",
            props.template,
            run.rendered,
            f"--props={run.props_file}",
            "--codec=h264",
            "--audio-codec=aac",
            f"--video-bitrate={kbps}k",
            f"--audio-bitrate={config.render.audio_kbps}k",
            "--enforce-audio-track",
            "--overwrite",
        ],
        "the render",
    )
    run.execute(
        [
            *_ffmpeg_command(config),
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            run.rendered,
            "-map",
            "0",
            "-c",
            "copy",
            "-map_metadata",
            "-1",
            "-use_editlist",
            "0",
            "-movflags",
            "+faststart",
            run.conformed,
        ],
        "the conform step",
    )


def _output_limits(props: RenderProps, config: EngineConfig) -> dict[str, int]:
    return {
        "width": props.width,
        "height": props.height,
        "duration_ms": props.duration_ms,
        "max_bytes": config.render.max_mb * BYTES_PER_MB,
    }


def _render_until_it_fits(
    run: _Run, inputs: _Inputs, config: EngineConfig, final: Path
) -> RenderResult:
    props = inputs.props
    kbps = video_kbps(props.duration_ms, config.render)
    try:
        run.start(props)
        for attempt in range(1, MAX_RENDERS + 1):
            run.clear_outputs()
            _render_and_conform(run, props, config, kbps)
            output = run.work / run.conformed
            try:
                info = check_output(output, **_output_limits(props, config))
            except Mp4TooLarge:
                if attempt < MAX_RENDERS:
                    kbps = lower_bitrate(kbps)
                continue
            except Mp4Error as error:
                raise RenderFailed(f"the output failed its checks: {error}") from error
            sha256 = sha256_file(output)
            os.replace(output, final)
            return RenderResult(
                path=final,
                sha256=sha256,
                size_bytes=info.size_bytes,
                content_hash=inputs.content_hash,
                video_kbps=kbps,
                renders=attempt,
                reused=False,
            )
    except OSError as error:
        raise RenderFailed(f"could not finish the render: {error}") from error
    finally:
        run.clear_quietly()
    raise RenderFailed(
        f"the output was still over {config.render.max_mb} MB after {MAX_RENDERS} renders"
    )


def _reusable(final: Path, inputs: _Inputs, config: EngineConfig) -> RenderResult | None:
    """The same inputs already gave this file (spec Section 3.5), and it still has to pass."""
    if not final.is_file():
        return None
    try:
        info = check_output(final, **_output_limits(inputs.props, config))
        sha256 = sha256_file(final)
    except (Mp4Error, OSError):
        return None
    return RenderResult(
        path=final,
        sha256=sha256,
        size_bytes=info.size_bytes,
        content_hash=inputs.content_hash,
        video_kbps=None,
        renders=0,
        reused=True,
    )


def render_reel(
    request: RenderRequest,
    *,
    config: EngineConfig,
    paths: EnginePaths,
    test_reel: bool,
    engine_root: Path = ENGINE_ROOT,
) -> RenderResult:
    """Raises `RenderRefused` if a gate says no and `RenderFailed` if the render gives no good
    file. In both cases no new file is left in `renders/`."""
    root = Path(engine_root)
    inputs = _checked_inputs(request, config, paths, test_reel, root)
    props = inputs.props
    stem = f"{props.reel_id}-r{props.revision}-{inputs.content_hash[:_HASH_CHARS]}"
    final = _checked_renders_folder(paths) / f"{stem}.mp4"
    reused = _reusable(final, inputs, config)
    if reused is not None:
        return reused
    _prepare_work_folder(inputs, root, paths)
    run = _Run(paths.data_root, paths.remotion_work, stem)
    return _render_until_it_fits(run, inputs, config, final)
