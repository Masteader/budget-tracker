"""Talking to the phone over `adb` (spec Section 5.1).

Everything the phone's shell reads is checked against a short allow-list first, because
`adb shell a b c` joins its arguments into one command line for the shell on the phone. On this
side there is no shell at all, and `adb` must be a real `.exe`: Windows runs a batch file through
cmd.exe, which would read the arguments a second time.

How a real phone behaves is checked by the owner in LIVE-4, never in a test.
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import IO

from core.paths import PathConfigError, expand_path
from core.secrets import scrubbed_env
from phone_capture import process_tree

STANDARD_ADB_PATH = r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
COMMAND_TIMEOUT_SECONDS = 30
PULL_TIMEOUT_SECONDS = 300
STOP_SIGNAL_ATTEMPTS = 2

_DEVICES_HEADER = "List of devices attached"
_READY_STATE = "device"
_UNAUTHORIZED_STATE = "unauthorized"
_MAX_DEVICE_TEXT = 300
_SHELL_ARGUMENT = re.compile(r"[A-Za-z0-9_./:=+-]+")
_SERIAL = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
_REMOTE_FILE = re.compile(r"/sdcard/[A-Za-z0-9][A-Za-z0-9_.-]*\.mp4")
_PNG_START = b"\x89PNG\r\n\x1a\n"
_PNG_END = b"IEND\xaeB`\x82"  # the last chunk and its checksum, so a cut-off picture is caught
_MAY_STILL_BE_RECORDING = (
    "The stop signal did not reach the phone, so screenrecord may still be running there. "
    "Reconnect the phone and run: adb shell pkill -INT screenrecord"
)


class AdbError(RuntimeError):
    """The phone step cannot go on. The message says why."""


class AdbNotFound(AdbError):
    pass


class NoDevice(AdbError):
    pass


class UnauthorizedDevice(AdbError):
    pass


class DeviceNotReady(AdbError):
    pass


class MultipleDevices(AdbError):
    pass


class AdbCommandFailed(AdbError):
    pass


class UnsafeAdbArgument(AdbError):
    pass


class RecordingFailed(AdbError):
    pass


class PullFailed(AdbError):
    pass


class ScreenshotFailed(AdbError):
    pass


def _printable(text: str) -> str:
    """Text from a device goes to the terminal, so it may not carry control codes."""
    cleaned = "".join(ch if ch.isprintable() else " " for ch in text)
    return " ".join(cleaned.split())[:_MAX_DEVICE_TEXT]


def find_on_path(name: str, env: Mapping[str, str] | None = None) -> Path | None:
    """Only absolute PATH folders count. `shutil.which` also looks in the current folder on
    Windows, so a file planted in the repo would run in place of the real tool."""
    source = os.environ if env is None else env
    search = next((value for key, value in source.items() if key.upper() == "PATH"), "")
    for folder in search.split(os.pathsep):
        if folder and Path(folder).is_absolute() and (Path(folder) / name).is_file():
            return Path(folder) / name
    return None


def _configured_adb(configured: str, env: Mapping[str, str] | None) -> Path | None:
    try:
        path = expand_path(configured, env)
    except PathConfigError:
        return None
    if not path.is_absolute():
        raise AdbNotFound(f"capture.adb_path must be an absolute path, got {configured!r}")
    if path.suffix.casefold() != ".exe":
        raise AdbNotFound(
            f"capture.adb_path must be adb.exe, got {configured!r}. A batch file goes through "
            "cmd.exe, which would read the arguments as code."
        )
    return path if path.is_file() else None


def find_adb(configured: str, env: Mapping[str, str] | None = None) -> Path:
    """The configured path, then PATH, then the Android SDK's standard folder."""
    found = (
        _configured_adb(configured, env)
        or find_on_path("adb.exe", env)
        or _configured_adb(STANDARD_ADB_PATH, env)
    )
    if found is None:
        raise AdbNotFound(
            "adb.exe was not found at capture.adb_path, on PATH or in the Android SDK folder. "
            "Install the Android platform tools, or record with the phone's own screen recorder "
            "and use --ingest."
        )
    return found


def _parse_devices(output: str) -> list[tuple[str, str]]:
    """adb can print server messages before the header and around the entries."""
    lines = [line.strip() for line in output.splitlines()]
    if _DEVICES_HEADER not in lines:
        raise AdbCommandFailed(f"could not read the device list from adb: {_printable(output)}")
    entries = []
    for line in lines[lines.index(_DEVICES_HEADER) + 1 :]:
        if line and not line.startswith("*"):
            serial, _, state = line.partition("\t")
            entries.append((serial, state.strip() or "unknown"))
    return entries


@dataclass(frozen=True)
class AdbClient:
    adb_path: Path

    def run(self, args: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        try:
            return process_tree.run(
                [str(self.adb_path), *args], timeout=timeout, env=scrubbed_env(None)
            )
        except subprocess.TimeoutExpired as error:
            raise AdbCommandFailed(f"adb {args[-1]} took over {timeout} seconds") from error
        except OSError as error:
            raise AdbCommandFailed(f"adb could not start: {error}") from error

    def run_checked(self, args: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        result = self.run(args, timeout)
        if result.returncode != 0:
            detail = _printable(result.stderr or result.stdout)
            raise AdbCommandFailed(f"adb failed with exit code {result.returncode}: {detail}")
        return result

    def require_one_device(self) -> Device:
        result = self.run_checked(["devices"], COMMAND_TIMEOUT_SECONDS)
        entries = _parse_devices(result.stdout)
        if not entries:
            raise NoDevice(
                "No phone found. Connect it with USB debugging on, or use --ingest with a "
                "recording from the phone's own screen recorder."
            )
        if len(entries) > 1:
            raise MultipleDevices(
                f"{len(entries)} devices are attached. Leave only the phone you are recording on."
            )
        serial, state = entries[0]
        if state == _UNAUTHORIZED_STATE:
            raise UnauthorizedDevice(
                "The phone has not authorised this computer. Tap Allow on the USB debugging "
                "prompt on the phone, then run this again."
            )
        if state != _READY_STATE:
            raise DeviceNotReady(f"The phone is not ready. adb says: {_printable(state)}")
        return Device(self, serial)


@dataclass(frozen=True)
class Device:
    client: AdbClient
    serial: str

    def __post_init__(self) -> None:
        if not _SERIAL.fullmatch(self.serial):
            raise UnsafeAdbArgument(f"unsafe device serial: {_printable(self.serial)!r}")

    def _with_serial(self, *args: str) -> list[str]:
        return ["-s", self.serial, *args]

    def shell(self, *args: str) -> None:
        for argument in args:
            if not _SHELL_ARGUMENT.fullmatch(argument):
                raise UnsafeAdbArgument(f"unsafe argument for the phone: {argument!r}")
        self.client.run_checked(self._with_serial("shell", *args), COMMAND_TIMEOUT_SECONDS)

    def remove(self, remote: str) -> None:
        _check_remote_file(remote)
        self.shell("rm", "-f", remote)

    def pull(self, remote: str, local: Path) -> None:
        """A pull counts only once a non-empty file is on this computer. Anything less leaves
        no partial file behind."""
        _check_remote_file(remote)
        local = Path(local)
        try:
            self.client.run_checked(
                self._with_serial("pull", remote, str(local)), PULL_TIMEOUT_SECONDS
            )
            if not local.is_file() or local.stat().st_size == 0:
                raise AdbCommandFailed("adb reported success but the pulled file is empty")
        except AdbCommandFailed as error:
            local.unlink(missing_ok=True)
            raise PullFailed(
                f"Could not pull {remote}, so nothing was saved. It is still on the phone. {error}"
            ) from error
        except KeyboardInterrupt:
            local.unlink(missing_ok=True)
            raise

    def screenshot(self, local: Path) -> None:
        """`exec-out` keeps the bytes as they are, where `shell` can change line endings, and
        leaves nothing on the phone. The file counts only once it is a whole PNG, and anything
        less leaves no file. It must not exist yet, so nothing is written through it."""
        local = Path(local)
        try:
            handle = open(local, "xb")
        except OSError as error:
            raise ScreenshotFailed(f"Could not create {local.name}: {error}") from error
        try:
            with handle:
                self._write_screencap(handle)
            data = local.read_bytes()
            if not (data.startswith(_PNG_START) and data.endswith(_PNG_END)):
                raise ScreenshotFailed("The phone did not return a whole PNG. Nothing was saved.")
        except BaseException:
            local.unlink(missing_ok=True)
            raise

    def _write_screencap(self, handle) -> None:
        command = [str(self.client.adb_path), *self._with_serial("exec-out", "screencap", "-p")]
        try:
            result = process_tree.run(
                command, stdout=handle, timeout=COMMAND_TIMEOUT_SECONDS, env=scrubbed_env(None)
            )
        except subprocess.TimeoutExpired as error:
            raise ScreenshotFailed(
                f"adb took over {COMMAND_TIMEOUT_SECONDS} seconds. Nothing was saved."
            ) from error
        except OSError as error:
            raise ScreenshotFailed(f"adb could not start: {error}") from error
        if result.returncode != 0:
            detail = _printable(result.stderr)
            raise ScreenshotFailed(f"adb failed with exit code {result.returncode}: {detail}")

    def start_recording(self, remote: str) -> Recording:
        _check_remote_file(remote)
        output = tempfile.TemporaryFile()
        try:
            process = process_tree.start(
                [str(self.client.adb_path), *self._with_serial("shell", "screenrecord", remote)],
                env=scrubbed_env(None),
                stdout=output,
                stderr=subprocess.STDOUT,
            )
        except OSError as error:
            output.close()
            raise RecordingFailed(f"adb could not start: {error}") from error
        return Recording(self, process, output)


def _check_remote_file(remote: str) -> None:
    if not _REMOTE_FILE.fullmatch(remote):
        raise UnsafeAdbArgument(f"unsafe path on the phone: {remote!r}")


class Recording:
    """`adb shell screenrecord`, running. Ctrl+C on `adb shell` may leave an unfinished file on
    Windows (spec Section 5.1), so the stop signal goes through a second adb call. That call is
    made even if adb has already gone, because screenrecord lives on the phone: a console Ctrl+C
    or a USB drop ends adb and can leave the recorder running."""

    def __init__(self, device: Device, process: subprocess.Popen, output: IO[bytes]):
        self._device = device
        self._process = process
        self._output = output
        self._stopped = False
        self._signal_failed = False

    def _text(self) -> str:
        return _printable(process_tree.read_output(self._output))

    def _finish(self) -> None:
        self._stopped = True
        self._output.close()

    def wait_started(self, grace_seconds: float) -> None:
        """A recorder still running after the grace time has started. One that ended already
        has failed, since nothing has asked it to stop."""
        try:
            process_tree.wait_for(self._process, grace_seconds)
        except subprocess.TimeoutExpired:
            return
        raise RecordingFailed(f"The recording stopped straight away: {self._text()}")

    def _send_stop_signal(self) -> AdbCommandFailed | None:
        """Tried again once, since a lost stop signal leaves the phone recording."""
        failure = None
        for _ in range(STOP_SIGNAL_ATTEMPTS):
            try:
                self._device.shell("pkill", "-INT", "screenrecord")
                self._signal_failed = False
                return None
            except AdbCommandFailed as error:
                failure = error
        self._signal_failed = True
        return failure

    def _stop_failure(self, ended_with: int | None, wait_seconds: float) -> RecordingFailed | None:
        signal_error = self._send_stop_signal()
        warning = f" {_MAY_STILL_BE_RECORDING}" if signal_error else ""
        if ended_with is not None:
            return RecordingFailed(
                f"The recording failed while it was running: {self._text()}.{warning}"
            )
        try:
            code = process_tree.wait_for(self._process, wait_seconds)
        except subprocess.TimeoutExpired:
            process_tree.kill_tree(self._process)
            return RecordingFailed(
                f"The recording did not stop, so it may be unfinished. Nothing was saved.{warning}"
            )
        if signal_error and code != 0:
            return RecordingFailed(f"adb lost the phone during the stop: {self._text()}.{warning}")
        return None

    def stop(self, wait_seconds: float) -> None:
        """A non-zero exit after the stop signal is not a failure by itself, because phones
        differ. The pull and the owner's sign-off judge the file. An exit of 0 before any signal
        means screenrecord's own time limit ended it, which leaves a finished file."""
        if self._stopped:
            return
        ended_with = self._process.poll()
        failure = None if ended_with == 0 else self._stop_failure(ended_with, wait_seconds)
        self._finish()
        if failure is not None:
            raise failure

    def abort(self, wait_seconds: float) -> str | None:
        """For use while another error or Ctrl+C is already on its way, so it never raises. It
        returns what the owner has to be told, if the phone may still be recording."""
        if self._stopped:
            return None
        try:
            self.stop(wait_seconds)
        except RecordingFailed:
            pass
        except (AdbError, KeyboardInterrupt):
            self._signal_failed = True
            process_tree.kill_tree(self._process)
            self._finish()
        return _MAY_STILL_BE_RECORDING if self._signal_failed else None
