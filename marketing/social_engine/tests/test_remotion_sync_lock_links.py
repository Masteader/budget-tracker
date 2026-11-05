"""Sync copies over the kept lockfile, reads and rewrites the stamp, and `--pull-lock` reads one and
writes the other. A link at either would turn that on another file, so both fail closed."""

import os
import stat
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from conftest import make_junction

import core.remotion_sync as sync_module
from core.remotion_sync import RemotionSyncError, pull_lock, sync

LOCKFILE = "package-lock.json"
STAMP = ".synced-lock.sha256"
KEPT_FILES = [LOCKFILE, STAMP]
windows_only = pytest.mark.skipif(sys.platform != "win32", reason="junctions need Windows")


class FakeNpm:
    def __init__(self):
        self.count = 0

    def __call__(self, args, **kwargs):
        self.count += 1
        (Path(kwargs["cwd"]) / "node_modules").mkdir(exist_ok=True)
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")


@pytest.fixture
def npm(monkeypatch) -> FakeNpm:
    fake = FakeNpm()
    monkeypatch.setattr(sync_module.subprocess, "run", fake)
    monkeypatch.setattr(sync_module.shutil, "which", lambda name: f"C:/fake/{name}.cmd")
    return fake


@pytest.fixture
def engine(tmp_path) -> Path:
    root = tmp_path / "engine"
    (root / "remotion_studio" / "src").mkdir(parents=True)
    (root / "remotion_studio" / "package.json").write_text('{"name": "x"}', encoding="utf-8")
    (root / "remotion_studio" / LOCKFILE).write_text('{"v": 1}', encoding="utf-8")
    (root / "tests" / "fixtures").mkdir(parents=True)
    (root / "tests" / "fixtures" / "props_valid.json").write_text('{"ok": 1}', encoding="utf-8")
    return root


@pytest.fixture
def data_root(tmp_path) -> Path:
    return tmp_path / "data"


@pytest.fixture
def work(data_root) -> Path:
    """A real work folder holding a file that any rebuild would delete."""
    folder = data_root / "remotion_work"
    folder.mkdir(parents=True)
    (folder / "stale.txt").write_text("stale", encoding="utf-8")
    return folder


@pytest.fixture
def outside(tmp_path) -> Path:
    folder = tmp_path / "outside"
    folder.mkdir()
    (folder / "keep.txt").write_text("keep", encoding="utf-8")
    return folder


def tree(folder: Path) -> dict[str, str | None]:
    return {
        path.relative_to(folder).as_posix(): path.read_text("utf-8") if path.is_file() else None
        for path in folder.rglob("*")
    }


def assert_nothing_happened(work: Path, npm: FakeNpm) -> None:
    assert (work / "stale.txt").exists(), "the rebuild started before the refusal"
    assert npm.count == 0


def symlink_or_skip(link: Path, target: Path, *, folder: bool = False) -> None:
    try:
        link.symlink_to(target, target_is_directory=folder)
    except OSError:
        pytest.skip("creating symlinks needs developer mode on Windows")


# --- sync ----------------------------------------------------------------------------------


@windows_only
@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_junction_is_refused_and_its_target_keeps_everything(
    engine, data_root, work, npm, outside, name
):
    make_junction(work / name, outside)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert tree(outside) == before
    assert (work / name).is_junction()
    assert_nothing_happened(work, npm)


@windows_only
@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_junction_with_a_missing_target_is_refused(engine, data_root, work, npm, tmp_path, name):
    gone = tmp_path / "gone"
    gone.mkdir()
    make_junction(work / name, gone)
    gone.rmdir()
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_real_symlink_is_refused_and_the_file_it_points_at_is_unchanged(
    engine, data_root, work, npm, outside, name
):
    symlink_or_skip(work / name, outside / "keep.txt")
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert (outside / "keep.txt").read_text("utf-8") == "keep"
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
@pytest.mark.parametrize("method", ["is_symlink", "is_junction"])
def test_a_faked_link_is_refused(engine, data_root, work, npm, monkeypatch, name, method):
    # Creating a real symlink needs developer mode, so a link can be faked for one path.
    (work / name).write_text("x", encoding="utf-8")
    faked = work / name
    real = getattr(Path, method)
    monkeypatch.setattr(Path, method, lambda self: self == faked or real(self))
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
def test_any_other_reparse_point_is_refused(engine, data_root, work, npm, monkeypatch, name):
    (work / name).write_text("x", encoding="utf-8")
    real_lstat = os.lstat

    def lstat(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            return SimpleNamespace(
                st_mode=stat.S_IFREG, st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT
            )
        return real_lstat(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os, "lstat", lstat)
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_real_path_outside_the_data_root_is_refused(
    engine, data_root, work, npm, outside, monkeypatch, name
):
    (work / name).write_text("x", encoding="utf-8")
    real_realpath = os.path.realpath

    def realpath(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            return str(outside / "keep.txt")
        return real_realpath(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match=f"{name}.*outside"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_real_path_that_cannot_be_worked_out_is_refused(
    engine, data_root, work, npm, monkeypatch, name
):
    (work / name).write_text("x", encoding="utf-8")
    real_realpath = os.path.realpath

    def realpath(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            raise OSError("loop")
        return real_realpath(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match=name):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_path_that_cannot_be_checked_is_refused(engine, data_root, work, npm, monkeypatch, name):
    real_lstat = os.lstat

    def lstat(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            raise PermissionError("no access")
        return real_lstat(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os, "lstat", lstat)
    with pytest.raises(RemotionSyncError, match="no access"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT_FILES)
def test_a_folder_at_the_path_is_refused_and_kept(engine, data_root, work, npm, name):
    (work / name).mkdir()
    with pytest.raises(RemotionSyncError, match=f"{name}.*not a file"):
        sync(engine, data_root)
    assert (work / name).is_dir()
    assert_nothing_happened(work, npm)


@windows_only
def test_a_junction_at_the_stamp_that_appears_during_the_copy_stops_npm_ci(
    engine, data_root, work, npm, outside, monkeypatch
):
    before = tree(outside)
    real_copytree = sync_module.shutil.copytree

    def copy_then_link(*args, **kwargs):
        result = real_copytree(*args, **kwargs)
        if not os.path.lexists(work / STAMP):
            make_junction(work / STAMP, outside)
        return result

    monkeypatch.setattr(sync_module.shutil, "copytree", copy_then_link)
    with pytest.raises(RemotionSyncError, match=f"{STAMP}.*link"):
        sync(engine, data_root)
    assert tree(outside) == before
    assert npm.count == 0


def test_a_link_that_appears_during_npm_ci_gets_no_stamp_written_through_it(
    engine, data_root, work, npm, monkeypatch
):
    def install_then_link(args, **kwargs):
        (work / "node_modules").mkdir(exist_ok=True)
        (work / STAMP).write_text("x", encoding="utf-8")
        real = Path.is_symlink
        monkeypatch.setattr(Path, "is_symlink", lambda self: self == work / STAMP or real(self))
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

    monkeypatch.setattr(sync_module.subprocess, "run", install_then_link)
    with pytest.raises(RemotionSyncError, match=f"{STAMP}.*link"):
        sync(engine, data_root)
    assert (work / STAMP).read_text("utf-8") == "x"


# --- pull_lock -----------------------------------------------------------------------------


@windows_only
@pytest.mark.parametrize("name", KEPT_FILES)
def test_pull_lock_refuses_a_junction(engine, data_root, work, npm, outside, name):
    other = "package-lock.json" if name == STAMP else STAMP
    (work / other).write_text('{"v": 9}', encoding="utf-8")
    make_junction(work / name, outside)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        pull_lock(engine, data_root)
    assert tree(outside) == before
    assert (engine / "remotion_studio" / LOCKFILE).read_text("utf-8") == '{"v": 1}'


@pytest.mark.parametrize("name", KEPT_FILES)
def test_pull_lock_refuses_a_real_symlink(engine, data_root, work, npm, outside, name):
    (work / LOCKFILE).write_text('{"v": 9}', encoding="utf-8")
    (work / STAMP).unlink(missing_ok=True)
    (work / name).unlink(missing_ok=True)
    symlink_or_skip(work / name, outside / "keep.txt")
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        pull_lock(engine, data_root)
    assert (outside / "keep.txt").read_text("utf-8") == "keep"
    assert (engine / "remotion_studio" / LOCKFILE).read_text("utf-8") == '{"v": 1}'


@pytest.mark.parametrize("name", KEPT_FILES)
def test_pull_lock_refuses_a_real_path_outside_the_data_root(
    engine, data_root, work, npm, outside, monkeypatch, name
):
    (work / LOCKFILE).write_text('{"v": 9}', encoding="utf-8")
    (work / STAMP).write_text("old", encoding="utf-8")
    real_realpath = os.path.realpath

    def realpath(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            return str(outside / "keep.txt")
        return real_realpath(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match=f"{name}.*outside"):
        pull_lock(engine, data_root)
    assert (engine / "remotion_studio" / LOCKFILE).read_text("utf-8") == '{"v": 1}'
    assert (work / STAMP).read_text("utf-8") == "old"


@windows_only
def test_pull_lock_refuses_a_junction_at_the_repo_lockfile(engine, data_root, work, npm, outside):
    (work / LOCKFILE).write_text('{"v": 9}', encoding="utf-8")
    repo_lock = engine / "remotion_studio" / LOCKFILE
    repo_lock.unlink()
    make_junction(repo_lock, outside)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match=f"{LOCKFILE}.*link"):
        pull_lock(engine, data_root)
    assert tree(outside) == before
    assert not (work / STAMP).exists()


# --- Real files keep working ---------------------------------------------------------------


def test_real_files_pass_and_a_lockfile_is_kept_until_it_is_pulled(engine, data_root, work, npm):
    (engine / "remotion_studio" / LOCKFILE).unlink()
    (work / LOCKFILE).write_text('{"fresh": 1}', encoding="utf-8")
    sync(engine, data_root)
    assert (work / LOCKFILE).read_text("utf-8") == '{"fresh": 1}'
    pull_lock(engine, data_root)
    assert (engine / "remotion_studio" / LOCKFILE).read_text("utf-8") == '{"fresh": 1}'


def test_a_first_sync_with_neither_file_is_fine(engine, data_root, npm):
    assert sync(engine, data_root).ran_npm_ci is True
    assert sync(engine, data_root).ran_npm_ci is False


@windows_only
def test_a_data_root_junction_with_real_files_still_works(engine, npm, tmp_path):
    real_root = tmp_path / "real_root"
    (real_root / "remotion_work").mkdir(parents=True)
    (real_root / "remotion_work" / LOCKFILE).write_text('{"v": 1}', encoding="utf-8")
    (real_root / "remotion_work" / STAMP).write_text("old", encoding="utf-8")
    link = tmp_path / "root_link"
    make_junction(link, real_root)
    assert sync(engine, link).ran_npm_ci is True


@windows_only
def test_files_in_another_letter_case_still_work(engine, data_root, work, npm):
    (work / LOCKFILE.upper()).write_text('{"v": 0}', encoding="utf-8")
    sync(engine, data_root)
    assert (work / LOCKFILE).exists()
