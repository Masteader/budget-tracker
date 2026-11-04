"""Run `adb` and FFmpeg with a timeout that holds.

`subprocess.run` kills only the process it started and then waits for its pipes to close, so a
child that outlives it (`npx.cmd` starts cmd.exe, node and FFmpeg) keeps the caller waiting long
after the timeout. Here output goes to temporary files, so nothing waits on a pipe, and a timeout
or Ctrl+C ends the whole tree. Waiting is done in short sleeps, which Ctrl+C can interrupt.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path
from time import monotonic
from time import sleep as pause
from typing import IO

from core.secrets import scrubbed_env

KILL_WAIT_SECONDS = 5
_POLL_SECONDS = 0.05


def _taskkill() -> str:
    return str(Path(os.environ.get("SystemRoot") or r"C:\Windows") / "System32" / "taskkill.exe")


def kill_tree(process: subprocess.Popen) -> None:
    """`taskkill /T` walks the tree through living parents, so a child whose parent has already
    exited can survive it. The caller's timeout still holds, since nothing waits on that child.
    A process that has exited is not looked up, because Windows may have reused its id."""
    try:
        if process.poll() is None:
            subprocess.run(
                [_taskkill(), "/T", "/F", "/PID", str(process.pid)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=KILL_WAIT_SECONDS,
                env=scrubbed_env(None),
                check=False,
            )
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        process.kill()
        try:
            process.wait(timeout=KILL_WAIT_SECONDS)
        except subprocess.TimeoutExpired:
            pass


def wait_for(process: subprocess.Popen, seconds: float) -> int:
    """The exit code, or `TimeoutExpired`. It does not wait for the process's children."""
    deadline = monotonic() + seconds
    while (code := process.poll()) is None:
        left = deadline - monotonic()
        if left <= 0:
            raise subprocess.TimeoutExpired(process.args, seconds)
        pause(min(_POLL_SECONDS, left))
    return code


def read_output(handle: IO[bytes]) -> str:
    handle.seek(0)
    return handle.read().decode("utf-8", errors="replace").replace("\r\n", "\n")


def start(
    args: list[str], *, env: dict[str, str], cwd: Path | None = None, stdout, stderr
) -> subprocess.Popen:
    """Standard input is closed: a tool must never read the owner's answers from the terminal."""
    return subprocess.Popen(
        args, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr
    )


def run(
    args: list[str],
    *,
    timeout: float,
    env: dict[str, str],
    cwd: Path | None = None,
    stdout: IO[bytes] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Like `subprocess.run` with `capture_output`. Given `stdout`, the bytes go to that file."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = start(args, env=env, cwd=cwd, stdout=stdout or out, stderr=err)
        try:
            code = wait_for(process, timeout)
        except BaseException:
            kill_tree(process)
            raise
        return subprocess.CompletedProcess(args, code, read_output(out), read_output(err))
