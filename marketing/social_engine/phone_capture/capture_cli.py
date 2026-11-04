"""Record a clip from the phone, or ingest clips recorded by hand (spec Section 5).

    python -m phone_capture.capture_cli --feature zatca_receipt_scan
    python -m phone_capture.capture_cli --ingest

Run it in a terminal, from `marketing/social_engine`. The questions must be answered by the owner
in person, so piped answers are refused. Recordings come from the demo account only (D22), and
they stay test clips until the launch gate is met and `--final` is given (D23).
"""

from __future__ import annotations

import argparse
import signal
import sys
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from core.config import ConfigError, EngineConfig, load_config
from core.manifest import ClipManifest, ClipRejected, sha256_file
from core.paths import RAW_RECORDING_FOLDERS, PathConfigError
from core.secrets import ForbiddenEnvironment, check_startup_environment
from phone_capture.adb import AdbClient, AdbError, Device, find_adb
from phone_capture.ingest import (
    CHECKLIST,
    STATUS_BAR_LINE,
    Ask,
    CaptureAborted,
    CaptureError,
    Checklist,
    Out,
    ask_app_version,
    ask_sign_off,
    check_feature,
    next_clip_path,
    prepare_paths,
    record_clip,
    require_gate_for_final,
    run_ingest,
)

REMOTE_RECORDING = "/sdcard/social_engine_tmp.mp4"

COUNTDOWN_SECONDS = 3
START_GRACE_SECONDS = 1
STOP_WAIT_SECONDS = 15
SETTLE_SECONDS = 1  # the short wait after the stop signal (spec Section 5.1)
DEMO_EXIT_ATTEMPTS = 3

_DEMO_BROADCAST = ("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command")
# In the order of spec Section 5.1, which follows Android's documented commands.
DEMO_ENTER_COMMANDS = (
    ("settings", "put", "global", "sysui_demo_allowed", "1"),
    (*_DEMO_BROADCAST, "enter"),
    (*_DEMO_BROADCAST, "clock", "-e", "hhmm", "0941"),
    (*_DEMO_BROADCAST, "battery", "-e", "level", "100"),
    (*_DEMO_BROADCAST, "network", "-e", "wifi", "show", "-e", "level", "4"),
    (*_DEMO_BROADCAST, "notifications", "-e", "visible", "false"),
)
DEMO_EXIT_COMMAND = (*_DEMO_BROADCAST, "exit")

EXIT_FAILED = 1
EXIT_INTERRUPTED = 130


@dataclass(frozen=True)
class CaptureResult:
    clip: Path
    signed: bool
    test_clip: bool
    demo_off: bool


@dataclass
class _DemoMode:
    off: bool = False


def _switch_demo_mode_off(device: Device, out: Out) -> tuple[bool, bool]:
    """Returns (switched off, Ctrl+C arrived). It keeps trying through an impatient second
    Ctrl+C, because leaving the phone's status bar faked is the worse outcome."""
    interrupted = False
    for _ in range(DEMO_EXIT_ATTEMPTS):
        try:
            device.shell(*DEMO_EXIT_COMMAND)
            return True, interrupted
        except AdbError:
            continue
        except KeyboardInterrupt:
            interrupted = True
    out(
        "WARNING: demo mode may still be on. With the phone connected, run: "
        f"adb shell {' '.join(DEMO_EXIT_COMMAND)}"
    )
    return False, interrupted


@contextmanager
def demo_mode(device: Device, out: Out) -> Iterator[_DemoMode]:
    """Off again however the block ends: an error, a failed entry command or Ctrl+C."""
    state = _DemoMode()
    try:
        for command in DEMO_ENTER_COMMANDS:
            device.shell(*command)
        yield state
    finally:
        state.off, interrupted = _switch_demo_mode_off(device, out)
        if interrupted:
            raise KeyboardInterrupt


def _countdown(out: Out, sleep: Callable[[float], None]) -> None:
    out("Keep the clip under 60 seconds and the phone in portrait. Sound is not recorded.")
    for number in range(COUNTDOWN_SECONDS, 0, -1):
        out(f"{number}...")
        sleep(1)


def _record(device: Device, ask: Ask, out: Out, sleep: Callable[[float], None]) -> None:
    recording = device.start_recording(REMOTE_RECORDING)
    try:
        recording.wait_started(START_GRACE_SECONDS)
        try:
            ask("Recording. Press Enter to stop: ")
        except EOFError as error:
            raise CaptureAborted("The terminal closed while recording.") from error
        recording.stop(STOP_WAIT_SECONDS)
    except BaseException:
        recording.abort(STOP_WAIT_SECONDS)
        raise
    sleep(SETTLE_SECONDS)


def _discard_from_phone(device: Device) -> None:
    """For a recording that was given up on, while an error or Ctrl+C is already on its way."""
    try:
        device.remove(REMOTE_RECORDING)
    except (AdbError, KeyboardInterrupt):
        pass


def _save_recording(device: Device, target: Path, out: Out) -> None:
    """A part file until the pull is known to be good, and the phone's copy goes only after
    that. `os.rename` refuses to overwrite on Windows, which is what this wants."""
    part = target.with_name(f"{target.name}.part")
    device.pull(REMOTE_RECORDING, part)
    part.rename(target)
    try:
        device.remove(REMOTE_RECORDING)
    except AdbError as error:
        out(f"The clip is saved, but {REMOTE_RECORDING} is still on the phone: {error}")


def run_capture(
    config: EngineConfig,
    feature: str,
    *,
    ask: Ask,
    out: Out,
    sleep: Callable[[float], None],
    final: bool = False,
    app_version: str | None = None,
) -> CaptureResult:
    check_feature(feature)
    require_gate_for_final(config, final)
    paths = prepare_paths(config)
    ClipManifest.load(paths.manifest)  # a broken manifest should stop this before the phone moves

    device = AdbClient(find_adb(config.capture.adb_path)).require_one_device()
    out(f"This session records a {'FINAL' if final else 'TEST'} clip for {feature}.")
    if not final:
        out("Test clips stay out of public reels (D23).")

    checklist = Checklist(feature)
    before_demo = [line for line in CHECKLIST if line != STATUS_BAR_LINE]
    checklist.confirm(before_demo, ask=ask)
    version = ask_app_version(app_version, ask=ask)

    recording_began = False
    try:
        with demo_mode(device, out) as demo:
            checklist.confirm([STATUS_BAR_LINE], ask=ask)
            confirmation = checklist.confirmation()
            device.remove(REMOTE_RECORDING)  # an old file must never pass for this recording
            _countdown(out, sleep)
            recording_began = True
            _record(device, ask, out, sleep)
    except BaseException:
        if recording_began:
            _discard_from_phone(device)
        raise

    target = next_clip_path(paths, feature, final=final)
    _save_recording(device, target, out)
    out(f"Saved {target}")

    digest = sha256_file(target)
    answers = ask_sign_off(feature, target, ask=ask, out=out)
    signed = answers.privacy_clean
    if signed:
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
        out(f"Signed off {feature}/{target.name}.")
    else:
        out(f"{target.name} was not signed off, so it cannot be used. --ingest will ask again.")
    return CaptureResult(clip=target, signed=signed, test_clip=not final, demo_off=demo.off)


def _use_utf8_console() -> None:
    """The checklist holds Arabic, which an old code page or a redirected stream would crash on."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def _raise_interrupt(signum, frame) -> None:
    raise KeyboardInterrupt


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0], allow_abbrev=False)
    parser.add_argument("--feature", choices=RAW_RECORDING_FOLDERS, help="the shot list folder")
    parser.add_argument(
        "--ingest", action="store_true", help="sign off recordings dropped into the feature folders"
    )
    parser.add_argument(
        "--final", action="store_true", help="a final clip, which needs the launch gate to be met"
    )
    parser.add_argument("--app-version", help="the app version shown on the phone")
    parser.add_argument("--config", type=Path, help="config.yaml to use instead of the shipped one")
    return parser


def _run(args: argparse.Namespace) -> int:
    check_startup_environment()
    if not sys.stdin.isatty():
        raise CaptureError(
            "This needs the owner at a terminal, since every answer is a sign-off. "
            "Run it in PowerShell, with no piped input."
        )
    config = load_config(args.config)
    if args.ingest:
        report = run_ingest(
            config,
            ask=input,
            out=print,
            feature=args.feature,
            final=args.final,
            app_version=args.app_version,
        )
        return EXIT_FAILED if report.failed else 0
    result = run_capture(
        config,
        args.feature,
        ask=input,
        out=print,
        sleep=time.sleep,
        final=args.final,
        app_version=args.app_version,
    )
    return 0 if result.demo_off else EXIT_FAILED


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    if not args.ingest and args.feature is None:
        parser.error("give --feature, or --ingest")
    _use_utf8_console()
    # Ctrl+Break would otherwise end Python on the spot, with demo mode still on.
    previous_break_handler = signal.signal(signal.SIGBREAK, _raise_interrupt)
    try:
        return _run(args)
    except KeyboardInterrupt:
        print("Stopped. Nothing was signed off by that step.", file=sys.stderr)
        return EXIT_INTERRUPTED
    except (
        AdbError,
        CaptureError,
        ClipRejected,
        ConfigError,
        ForbiddenEnvironment,
        PathConfigError,
        OSError,
        ValueError,
    ) as error:
        print(error, file=sys.stderr)
        return EXIT_FAILED
    finally:
        signal.signal(signal.SIGBREAK, previous_break_handler)


if __name__ == "__main__":
    raise SystemExit(main())
