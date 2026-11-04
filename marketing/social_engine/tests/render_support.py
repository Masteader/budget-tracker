"""Shared by the render tests: MP4 bytes built here, since `*.mp4` is git-ignored, a fake Remotion
at the subprocess boundary, and a throwaway engine and data_root under `tmp_path`."""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
from dataclasses import dataclass
from datetime import date
from pathlib import Path

import yaml

import core.brand_gate as brand_gate_module
from core.config import DEFAULT_CONFIG_PATH, EngineConfig, load_config
from core.manifest import ClipEntry, ClipManifest, sha256_file
from core.paths import EnginePaths
from core.render import ClipUse, RenderRequest

MB = 1_000_000
_FTYP = b"isom" + b"\x00\x00\x02\x00" + b"isomiso2avc1mp41"


def box(kind: bytes, payload: bytes = b"") -> bytes:
    return struct.pack(">I", 8 + len(payload)) + kind + payload


def large_box(kind: bytes, payload: bytes = b"") -> bytes:
    return struct.pack(">I", 1) + kind + struct.pack(">Q", 16 + len(payload)) + payload


def mvhd(duration_ms: int, *, version: int = 0, timescale: int = 1000) -> bytes:
    if version == 1:
        body = struct.pack(">BxxxQQIQ", 1, 0, 0, timescale, duration_ms)
    else:
        body = struct.pack(">BxxxIIII", 0, 0, 0, timescale, duration_ms)
    return box(b"mvhd", body + bytes(80))


def tkhd(width: int, height: int, *, version: int = 0) -> bytes:
    if version == 1:
        head = struct.pack(">BxxxQQIIQ", 1, 0, 0, 1, 0, 0)
    else:
        head = struct.pack(">BxxxIIIII", 0, 0, 0, 1, 0, 0)
    size = struct.pack(">II", width << 16, height << 16)
    return box(b"tkhd", head + bytes(8 + 8 + 36) + size)


def trak(
    handler: bytes,
    codec: bytes,
    *,
    width: int = 0,
    height: int = 0,
    edit_list: bool = False,
    version: int = 0,
) -> bytes:
    hdlr = box(b"hdlr", bytes(8) + handler + bytes(12) + b"\x00")
    entry = box(codec, bytes(16))
    stsd = box(b"stsd", bytes(4) + struct.pack(">I", 1) + entry)
    stbl = box(b"stbl", stsd)
    minf = box(b"minf", stbl)
    mdia = box(b"mdia", hdlr + minf)
    edts = box(b"edts", box(b"elst", bytes(8))) if edit_list else b""
    return box(b"trak", tkhd(width, height, version=version) + edts + mdia)


def moov(
    *,
    width: int = 1080,
    height: int = 1920,
    duration_ms: int = 30_000,
    edit_list: bool = False,
    video_codec: bytes = b"avc1",
    audio: bool = True,
    version: int = 0,
) -> bytes:
    tracks = trak(
        b"vide", video_codec, width=width, height=height, edit_list=edit_list, version=version
    )
    if audio:
        tracks += trak(b"soun", b"mp4a", version=version)
    return box(b"moov", mvhd(duration_ms, version=version) + tracks)


def build_mp4(
    *,
    moov_first: bool = True,
    mdat: bytes = bytes(64),
    large_mdat: bool = False,
    **moov_options,
) -> bytes:
    media = (large_box if large_mdat else box)(b"mdat", mdat)
    header = moov(**moov_options)
    parts = [header, media] if moov_first else [media, header]
    return box(b"ftyp", _FTYP) + b"".join(parts)


def write_mp4_of_size(path: Path, total_bytes: int, **moov_options) -> None:
    """A valid file of exactly this size, without building megabytes in memory."""
    prefix = box(b"ftyp", _FTYP) + moov(**moov_options)
    with open(path, "wb") as handle:
        handle.write(prefix)
        handle.write(struct.pack(">I", total_bytes - len(prefix)) + b"mdat")
        handle.truncate(total_bytes)


def option(command: list[str], name: str) -> str:
    for part in command:
        if part.startswith(f"--{name}="):
            return part.split("=", 1)[1]
    raise AssertionError(f"--{name} is not in {command}")


@dataclass
class RenderCall:
    command: list[str]
    kwargs: dict
    props: dict
    public_files: list[str]
    renders_files: list[str]


class FakeProcess:
    def __init__(self, returncode: int = 0, *, hangs: bool = False):
        self.returncode = returncode
        self.hangs = hangs
        self.pid = 4242
        self.waits = 0

    def wait(self, timeout=None):
        self.waits += 1
        if self.hangs and self.waits == 1:
            raise subprocess.TimeoutExpired("fake", timeout)
        return self.returncode


class FakeRemotion:
    """Stands in for `npx remotion render` and for the FFmpeg conform step. Each render takes the
    next writer from `outputs`, and the last one repeats."""

    def __init__(self, paths: EnginePaths):
        self.paths = paths
        self.outputs = [lambda path: path.write_bytes(build_mp4())]
        self.renders: list[RenderCall] = []
        self.conforms: list[RenderCall] = []
        self.conform_writer = None
        self.render_exit = 0
        self.conform_exit = 0
        self.hangs = False
        self.run_calls: list[list[str]] = []

    @property
    def video_kbps(self) -> list[str]:
        return [option(call.command, "video-bitrate") for call in self.renders]

    @property
    def subprocess_count(self) -> int:
        return len(self.renders) + len(self.conforms) + len(self.run_calls)

    def popen(self, args, **kwargs):
        command = [str(part) for part in args]
        cwd = Path(kwargs["cwd"])
        if "ffmpeg" in command or command[0].endswith("ffmpeg.exe"):
            return self._conform(command, kwargs, cwd)
        return self._render(command, kwargs, cwd)

    def run(self, args, **kwargs):
        # npm ci during the sync, and taskkill after a timeout.
        command = [str(part) for part in args]
        self.run_calls.append(command)
        if command[-1] == "ci":
            (Path(kwargs["cwd"]) / "node_modules").mkdir(exist_ok=True)
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

    def _snapshot(self, command, kwargs, cwd, props) -> RenderCall:
        public = cwd / "public"
        return RenderCall(
            command,
            kwargs,
            props,
            sorted(p.relative_to(public).as_posix() for p in public.rglob("*") if p.is_file()),
            sorted(p.name for p in self.paths.renders.iterdir()),
        )

    def _render(self, command, kwargs, cwd):
        props = json.loads((cwd / option(command, "props")).read_text("utf-8"))
        self.renders.append(self._snapshot(command, kwargs, cwd, props))
        if self.hangs:
            return FakeProcess(hangs=True)
        if self.render_exit:
            kwargs["stdout"].write(b"LEAK-MARKER")
            return FakeProcess(self.render_exit)
        output = cwd / next(part for part in command if part.endswith(".mp4"))
        writer = self.outputs[min(len(self.renders) - 1, len(self.outputs) - 1)]
        writer(output)
        return FakeProcess()

    def _conform(self, command, kwargs, cwd):
        self.conforms.append(self._snapshot(command, kwargs, cwd, {}))
        if self.conform_exit:
            return FakeProcess(self.conform_exit)
        source = cwd / command[command.index("-i") + 1]
        target = cwd / command[-1]
        if self.conform_writer is not None:
            self.conform_writer(target)
        else:
            shutil.copyfile(source, target)
        return FakeProcess()


def shipped_data() -> dict:
    with DEFAULT_CONFIG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


CHECKED_ON = date(2026, 11, 3)


def complete_live_data() -> dict:
    data = shipped_data()
    data["engine"]["mode"] = "live"
    data["brand"]["logo_path"] = "assets/branding/approved_logo.svg"
    data["brand"]["handles"] = {
        "instagram": "@qawam_money",
        "facebook": "qawam.money",
        "tiktok": "@qawammoney",
        "youtube": "@qawammoney",
    }
    data["brand"]["hashtags"] = ["#QawamMoney", "#قوام_المال"]
    data["brand"]["clearance"] = dict.fromkeys(data["brand"]["clearance"], CHECKED_ON)
    return data


class Rig:
    """A throwaway engine and data_root. Nothing outside `tmp_path` is read or written."""

    def __init__(self, tmp_path: Path, monkeypatch):
        self.engine = tmp_path / "engine"
        self.data_root = tmp_path / "data"
        self.paths = EnginePaths.from_root(self.data_root)
        self.paths.ensure_dirs()
        self.config: EngineConfig = load_config()
        self._write_engine()
        self.fake = FakeRemotion(self.paths)
        monkeypatch.setattr(brand_gate_module, "ENGINE_ROOT", self.engine)
        monkeypatch.setattr(subprocess, "Popen", self.fake.popen)
        monkeypatch.setattr(subprocess, "run", self.fake.run)
        monkeypatch.setattr(shutil, "which", lambda name: f"C:/fake/{name}.cmd")
        (self.paths.voiceovers / "voice.wav").write_bytes(b"voice bytes")
        self.entries: list[ClipEntry] = []

    def _write_engine(self) -> None:
        studio = self.engine / "remotion_studio"
        (studio / "src").mkdir(parents=True)
        (studio / "package.json").write_text('{"name": "x"}', encoding="utf-8")
        (studio / "package-lock.json").write_text('{"v": 1}', encoding="utf-8")
        (studio / "src" / "Root.tsx").write_text("root", encoding="utf-8")
        branding = self.engine / "assets" / "branding"
        branding.mkdir(parents=True)
        tokens = {"colors": {"roseGold": "#E598B0", "canvasDark": "#110509"}}
        (branding / "brand_tokens.json").write_text(json.dumps(tokens), encoding="utf-8")
        (branding / "test_logo.svg").write_text("<svg>TEST</svg>", encoding="utf-8")
        (branding / "approved_logo.svg").write_text("<svg>real</svg>", encoding="utf-8")
        (self.engine / "tests" / "fixtures").mkdir(parents=True)
        (self.engine / "tests" / "fixtures" / "props_valid.json").write_text("{}", encoding="utf-8")

    def add_clip(
        self, path: str = "payday_cycle/clip_01.mp4", content: bytes = b"clip bytes", **fields
    ) -> ClipEntry:
        file = self.paths.raw_recordings / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(content)
        entry = ClipEntry(
            path=path,
            sha256=sha256_file(file),
            privacy_checked=True,
            app_version="1.0.0",
            **fields,
        )
        self.entries.append(entry)
        ClipManifest(clips=self.entries).save(self.paths.manifest)
        return entry

    def add_basket_clip(self, path: str = "smart_basket/clip_01.mp4") -> ClipEntry:
        return self.add_clip(
            path,
            store_names_masked=True,
            mask_regions=[{"x": 0.05, "y": 0.2, "width": 0.9, "height": 0.08}],
        )

    def request(self, **overrides) -> RenderRequest:
        fields = {
            "reel_id": "R-2026-11-04-01",
            "revision": 1,
            "template": "DailyTip",
            "language": "ar",
            "duration_ms": 30_000,
            "highlight_color": "#E598B0",
            "hook_text": "راتبك وين يروح؟",
            "on_screen_text": ["Plan by category"],
            "subtitles_en": "Where does your salary go?",
            "voiceover": "voice.wav",
            "words": [{"text": "راتبك", "start_ms": 0, "end_ms": 400}],
            "clips": [],
        }
        fields.update(overrides)
        return RenderRequest.model_validate(fields)

    def clip_use(self, path: str = "payday_cycle/clip_01.mp4") -> ClipUse:
        return ClipUse(path=path, start_ms=1000, end_ms=5000)

    def use_live_config(self, data: dict | None = None) -> None:
        self.config = EngineConfig.model_validate(data or complete_live_data())

    def use_config(self, change) -> None:
        data = shipped_data()
        change(data)
        self.config = EngineConfig.model_validate(data)
