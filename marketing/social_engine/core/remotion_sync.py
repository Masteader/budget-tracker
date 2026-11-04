"""Copy the Remotion studio to `remotion_work`, because npm never runs inside the repo.

Thousands of small files under `node_modules` would sync through OneDrive all day (spec
Section 4). The first `npm install` happens by hand in `remotion_work`, and `--pull-lock`
then copies `package-lock.json` back to the repo.

    python -m core.remotion_sync --data-root "%LOCALAPPDATA%\\SocialEngine"
    python -m core.remotion_sync --data-root "%LOCALAPPDATA%\\SocialEngine" --pull-lock
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from core.paths import ENGINE_ROOT, PathConfigError, resolve_data_root
from core.secrets import ForbiddenEnvironment, check_startup_environment, scrubbed_env

LOCKFILE = "package-lock.json"
_STAMP = ".synced-lock.sha256"  # the lockfile that `npm ci` last installed
_FIXTURE = Path("tests") / "fixtures" / "props_valid.json"
_KEPT_FOLDERS = ("node_modules", "out")
_KEPT_IN_WORK = {*_KEPT_FOLDERS, LOCKFILE, _STAMP}


class RemotionSyncError(RuntimeError):
    """The sync cannot go on. The message says why."""


@dataclass(frozen=True)
class SyncResult:
    work_dir: Path
    ran_npm_ci: bool


def _work_dir(data_root: Path) -> Path:
    return Path(data_root) / "remotion_work"


def _preflight(engine_root: Path) -> Path:
    studio = Path(engine_root) / "remotion_studio"
    if not studio.is_dir():
        raise RemotionSyncError(f"remotion_studio not found at {studio}")
    if (studio / "node_modules").exists():
        raise RemotionSyncError(
            f"{studio / 'node_modules'} exists. npm must only run in remotion_work, so "
            "that folder must not sync through OneDrive. Remove it, then sync again."
        )
    return studio


def _remove(path: Path) -> None:
    """A link is removed on its own, and the folder it points at stays untouched."""
    if path.is_junction():
        os.rmdir(path)
    elif path.is_symlink() or not path.is_dir():
        path.unlink()
    else:
        shutil.rmtree(path)


def _copy_into(source_dir: Path, target_dir: Path) -> None:
    shutil.copytree(source_dir, target_dir, dirs_exist_ok=True)


def _is_link(path: Path, info: os.stat_result) -> bool:
    """A junction, a symlink, or any other reparse point such as a mounted volume."""
    attributes = getattr(info, "st_file_attributes", 0)
    return (
        path.is_junction()
        or path.is_symlink()
        or bool(attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT)
    )


def _checked_work_dir(data_root: Path) -> Path:
    """Sync deletes inside this folder, so it has to be a real folder in the real data_root.
    A link would turn that delete on whatever it points at. Links above the work folder are
    resolved, because both real paths pass through them: only this last step can leave the
    data_root. A work folder that does not exist yet is fine, and nothing is deleted on any
    refusal. This looks once and does not lock, so it stops mistakes and not a live attacker."""
    work = _work_dir(data_root)
    try:
        info = os.lstat(work)
    except FileNotFoundError:
        return work
    except OSError as error:
        raise RemotionSyncError(f"could not check {work}. Nothing was deleted: {error}") from error
    if _is_link(work, info):
        raise RemotionSyncError(
            f"{work} is a link, and sync deletes files inside remotion_work, so the folder it "
            "points at would be emptied. Nothing was deleted. Remove the link, then sync again."
        )
    if not stat.S_ISDIR(info.st_mode):
        raise RemotionSyncError(f"{work} is not a folder. Nothing was deleted.")
    try:
        real_work = os.path.realpath(work, strict=True)
        real_root = os.path.realpath(data_root, strict=True)
    except OSError as error:
        raise RemotionSyncError(f"could not check {work}. Nothing was deleted: {error}") from error
    expected = os.path.join(real_root, work.name)
    if os.path.normcase(real_work) != os.path.normcase(expected):
        raise RemotionSyncError(
            f"{work} is really at {real_work}, outside the data_root {real_root}. "
            "Nothing was deleted."
        )
    return work


def _check_kept_folder(work: Path, name: str, data_root: Path) -> None:
    kept = work / name
    try:
        info = os.lstat(kept)
    except FileNotFoundError:
        return
    except OSError as error:
        raise RemotionSyncError(f"could not check {kept}: {error}") from error
    if _is_link(kept, info):
        raise RemotionSyncError(
            f"{kept} is a link, and npm ci deletes node_modules and a render writes to out, so "
            "the folder it points at would be changed. Remove the link, then try again."
        )
    if not stat.S_ISDIR(info.st_mode):
        raise RemotionSyncError(f"{kept} is not a folder.")
    try:
        real_kept = os.path.realpath(kept, strict=True)
        real_root = os.path.realpath(data_root, strict=True)
    except OSError as error:
        raise RemotionSyncError(f"could not check {kept}: {error}") from error
    expected = os.path.join(real_root, work.name, name)
    if os.path.normcase(real_kept) != os.path.normcase(expected):
        raise RemotionSyncError(f"{kept} is really at {real_kept}, outside the data_root.")


def checked_kept_folders(data_root: Path) -> None:
    """Sync keeps these two folders, and `npm ci` or a render then deletes and writes inside
    them, so each has to be a real folder in its real place. A folder that does not exist yet
    is fine. Like the work folder check, this looks once and does not lock."""
    work = _work_dir(data_root)
    for name in _KEPT_FOLDERS:
        _check_kept_folder(work, name, data_root)


def _rebuild_work_dir(studio: Path, engine_root: Path, data_root: Path) -> None:
    """Everything is replaced except what npm and rendering own, so a file deleted from the
    repo cannot linger in the build."""
    work = _checked_work_dir(data_root)
    work.mkdir(parents=True, exist_ok=True)
    _checked_work_dir(data_root)  # again now that it exists, right before anything is deleted
    checked_kept_folders(data_root)
    for entry in work.iterdir():
        if entry.name not in _KEPT_IN_WORK:
            _remove(entry)
    _copy_into(studio, work)

    (work / "public").mkdir(exist_ok=True)
    branding = Path(engine_root) / "assets" / "branding"
    if branding.is_dir():
        _copy_into(branding, work / "public")

    (work / "fixtures").mkdir(exist_ok=True)
    shutil.copy2(Path(engine_root) / _FIXTURE, work / "fixtures" / _FIXTURE.name)


def _lock_hash(lockfile: Path) -> str:
    return hashlib.sha256(lockfile.read_bytes()).hexdigest()


def _run_npm_ci(work: Path) -> None:
    npm = shutil.which("npm")
    if npm is None:
        raise RemotionSyncError("npm was not found on PATH")
    result = subprocess.run(
        [npm, "ci"],
        cwd=work,
        env=scrubbed_env(None),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        # npm's own output stays out of this message, because it can echo its environment.
        raise RemotionSyncError(
            f"npm ci failed with exit code {result.returncode} in {work}. "
            "Run it there by hand to see why."
        )


def sync(engine_root: Path, data_root: Path) -> SyncResult:
    studio = _preflight(engine_root)
    if not (Path(engine_root) / _FIXTURE).is_file():
        raise RemotionSyncError(f"{_FIXTURE.as_posix()} is missing from {engine_root}")
    work = _work_dir(data_root)
    try:
        _rebuild_work_dir(studio, engine_root, data_root)
    except OSError as error:
        raise RemotionSyncError(f"could not copy the studio to {work}: {error}") from error

    repo_lock = studio / LOCKFILE
    if not repo_lock.is_file():
        return SyncResult(work, ran_npm_ci=False)  # before the first `npm install`
    wanted = _lock_hash(repo_lock)
    stamp = work / _STAMP
    installed = stamp.read_text(encoding="utf-8") if stamp.is_file() else None
    checked_kept_folders(data_root)  # again, right before node_modules is trusted or deleted
    if installed == wanted and (work / "node_modules").is_dir():
        return SyncResult(work, ran_npm_ci=False)
    stamp.unlink(missing_ok=True)
    _run_npm_ci(work)
    stamp.write_text(wanted, encoding="utf-8")
    return SyncResult(work, ran_npm_ci=True)


def pull_lock(engine_root: Path, data_root: Path) -> Path:
    """The pulled lockfile came from that `node_modules`, so it needs no reinstall."""
    studio = _preflight(engine_root)
    work = _checked_work_dir(data_root)
    source = work / LOCKFILE
    if not source.is_file():
        raise RemotionSyncError(f"{LOCKFILE} not found in {work}. Run npm install there first.")
    target = studio / LOCKFILE
    shutil.copy2(source, target)
    (work / _STAMP).write_text(_lock_hash(target), encoding="utf-8")
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-root", required=True)
    parser.add_argument(
        "--pull-lock", action="store_true", help="copy package-lock.json back to the repo"
    )
    args = parser.parse_args(argv)
    try:
        check_startup_environment()
        data_root = resolve_data_root(args.data_root)
        if args.pull_lock:
            print(f"pulled {pull_lock(ENGINE_ROOT, data_root)}")
        else:
            result = sync(ENGINE_ROOT, data_root)
            print(f"synced to {result.work_dir}, npm ci ran: {result.ran_npm_ci}")
    except (ForbiddenEnvironment, RemotionSyncError, PathConfigError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
