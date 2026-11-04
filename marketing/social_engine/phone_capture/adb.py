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
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from core.paths import PathConfigError, expand_path
from core.secrets import scrubbed_env

STANDARD_ADB_PATH = r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
COMMAND_TIMEOUT_SECONDS = 30
PULL_TIMEOUT_SECONDS = 300

_DEVICES_HEADER = "List of devices attached"
_READY_STATE = "device"
_UNAUTHORIZED_STATE = "unauthorized"
_MAX_DEVICE_TEXT = 300
_SHELL_ARGUMENT = re.compile(r"[A-Za-z0-9_./:=+-]+")
_SERIAL = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
_REMOTE_FILE = re.compile(r"/sdcard/[A-Za-z0-9][A-Za-z0-9_.-]*\.mp4")


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
            return subprocess.run(
                [str(self.adb_path), *args],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                env=scrubbed_env(None),
                check=False,
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

    def start_recording(self, remote: str) -> Recording:
        _check_remote_file(remote)
        try:
            process = subprocess.Popen(
                [str(self.client.adb_path), *self._with_serial("shell", "screenrecord", remote)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                env=scrubbed_env(None),
            )
        except OSError as error:
            raise RecordingFailed(f"adb could not start: {error}") from error
        return Recording(self, process)


def _check_remote_file(remote: str) -> None:
    if not _REMOTE_FILE.fullmatch(remote):
        raise UnsafeAdbArgument(f"unsafe path on the phone: {remote!r}")


class Recording:
    """`adb shell screenrecord`, running. Ctrl+C on `adb shell` may leave an unfinished file on
    Windows (spec Section 5.1), so the stop signal goes through a second adb call."""

    def __init__(self, device: Device, process: subprocess.Popen[str]):
        self._device = device
        self._process = process

    def _kill(self) -> None:
        self._process.kill()
        self._process.wait()

    def wait_started(self, grace_seconds: float) -> None:
        """A recorder still running after the grace time has started. One that ended already
        has failed, since nothing has asked it to stop."""
        try:
            output, _ = self._process.communicate(timeout=grace_seconds)
        except subprocess.TimeoutExpired:
            return
        raise RecordingFailed(f"The recording stopped straight away: {_printable(output or '')}")

    def stop(self, wait_seconds: float) -> None:
        """A non-zero exit after the stop signal is not a failure by itself, because phones
        differ. The pull and the owner's sign-off judge the file."""
        if self._process.poll() is not None:
            output, _ = self._process.communicate()
            if self._process.returncode != 0:
                detail = _printable(output or "")
                raise RecordingFailed(f"The recording failed while it was running: {detail}")
            return  # screenrecord's own time limit ended it, which leaves a finished file
        signal_error = None
        try:
            self._device.shell("pkill", "-INT", "screenrecord")
        except AdbCommandFailed as error:
            signal_error = error
        try:
            self._process.communicate(timeout=wait_seconds)
        except subprocess.TimeoutExpired as error:
            self._kill()
            raise RecordingFailed(
                "The recording did not stop, so it may be unfinished. Nothing was saved."
            ) from signal_error or error

    def abort(self, wait_seconds: float) -> None:
        """For use while another error or Ctrl+C is already on its way, so it never raises."""
        try:
            self.stop(wait_seconds)
        except (AdbError, KeyboardInterrupt):
            self._kill()
