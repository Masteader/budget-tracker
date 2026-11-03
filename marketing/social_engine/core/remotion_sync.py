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
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from core.paths import ENGINE_ROOT, PathConfigError, resolve_data_root
from core.secrets import scrubbed_env

LOCKFILE = "package-lock.json"
_STAMP = ".synced-lock.sha256"  # the lockfile that `npm ci` last installed
_FIXTURE = Path("tests") / "fixtures" / "props_valid.json"
_KEPT_IN_WORK = {"node_modules", "out", LOCKFILE, _STAMP}


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
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def _copy_into(source_dir: Path, target_dir: Path) -> None:
    shutil.copytree(source_dir, target_dir, dirs_exist_ok=True)


def _rebuild_work_dir(studio: Path, engine_root: Path, work: Path) -> None:
    """Everything is replaced except what npm and rendering own, so a file deleted from the
    repo cannot linger in the build."""
    work.mkdir(parents=True, exist_ok=True)
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
        raise RemotionSyncError(f"npm ci failed in {work}:\n{result.stderr}")


def sync(engine_root: Path, data_root: Path) -> SyncResult:
    studio = _preflight(engine_root)
    if not (Path(engine_root) / _FIXTURE).is_file():
        raise RemotionSyncError(f"{_FIXTURE.as_posix()} is missing from {engine_root}")
    work = _work_dir(data_root)
    _rebuild_work_dir(studio, engine_root, work)

    repo_lock = studio / LOCKFILE
    if not repo_lock.is_file():
        return SyncResult(work, ran_npm_ci=False)  # before the first `npm install`
    wanted = _lock_hash(repo_lock)
    stamp = work / _STAMP
    installed = stamp.read_text(encoding="utf-8") if stamp.is_file() else None
    if installed == wanted and (work / "node_modules").is_dir():
        return SyncResult(work, ran_npm_ci=False)
    stamp.unlink(missing_ok=True)
    _run_npm_ci(work)
    stamp.write_text(wanted, encoding="utf-8")
    return SyncResult(work, ran_npm_ci=True)


def pull_lock(engine_root: Path, data_root: Path) -> Path:
    """The pulled lockfile came from that `node_modules`, so it needs no reinstall."""
    studio = _preflight(engine_root)
    work = _work_dir(data_root)
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
        data_root = resolve_data_root(args.data_root)
        if args.pull_lock:
            print(f"pulled {pull_lock(ENGINE_ROOT, data_root)}")
        else:
            result = sync(ENGINE_ROOT, data_root)
            print(f"synced to {result.work_dir}, npm ci ran: {result.ran_npm_ci}")
    except (RemotionSyncError, PathConfigError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
