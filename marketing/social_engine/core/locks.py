"""The lock that stops two ticks overlapping (spec Section 3.5).

It is a byte-range lock on a file, held by the operating system. Windows drops it the moment the
holding process dies, however it dies, so a crash can never leave a stale lock to clear by hand.
The file itself stays on disk, since deleting a lock file is its own race.
"""

from __future__ import annotations

import msvcrt
import os
from pathlib import Path
from types import TracebackType


class LockHeld(RuntimeError):
    """Another holder has the lock, so this run must stop and leave the work to it."""


class EngineLock:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._descriptor: int | None = None

    @property
    def held(self) -> bool:
        return self._descriptor is not None

    def acquire(self) -> None:
        if self.held:
            raise LockHeld(f"{self.path} is already held by this object")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(self.path, os.O_RDWR | os.O_CREAT | os.O_BINARY | os.O_NOINHERIT)
        try:
            msvcrt.locking(descriptor, msvcrt.LK_NBLCK, 1)
        except OSError as error:
            os.close(descriptor)
            raise LockHeld(f"another run holds {self.path}") from error
        self._descriptor = descriptor

    def release(self) -> None:
        if self._descriptor is None:
            return
        descriptor, self._descriptor = self._descriptor, None
        try:
            os.lseek(descriptor, 0, os.SEEK_SET)
            msvcrt.locking(descriptor, msvcrt.LK_UNLCK, 1)
        finally:
            os.close(descriptor)

    def __enter__(self) -> EngineLock:
        self.acquire()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.release()
