"""OneDrive marks repo folders read-only, the copy keeps that flag, and the next sync then failed
with WinError 5 while removing the old copy. The flag is cleared only on paths that are really
inside `remotion_work`, and never through a link."""

import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import make_junction

import core.remotion_sync as sync_module
from core.remotion_sync import RemotionSyncError, pull_lock, sync

windows_only = pytest.mark.skipif(sys.platform != "win32", reason="the flag is a Windows feature")
pytestmark = windows_only


def is_read_only(path: Path) -> bool:
    return bool(os.lstat(path).st_file_attributes & stat.FILE_ATTRIBUTE_READONLY)


def set_read_only(path: Path) -> None:
    os.chmod(path, stat.S_IREAD, follow_symlinks=False)


def set_tree_read_only(folder: Path) -> None:
    for path in folder.rglob("*"):
        set_read_only(path)
    set_read_only(folder)


def clear_tree(folder: Path) -> None:
    """So the end of a test can always delete what it made."""
    for path in folder.rglob("*"):
        os.chmod(path, stat.S_IWRITE, follow_symlinks=False)
    os.chmod(folder, stat.S_IWRITE, follow_symlinks=False)


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
def engine(tmp_path):
    """A repo whose folders and files all carry the flag, the way OneDrive leaves them."""
    root = tmp_path / "engine"
    studio = root / "remotion_studio"
    (studio / "src" / "compositions").mkdir(parents=True)
    (studio / "package.json").write_text('{"name": "x"}', encoding="utf-8")
    (studio / "package-lock.json").write_text('{"v": 1}', encoding="utf-8")
    (studio / "src" / "Root.tsx").write_text("root", encoding="utf-8")
    (studio / "src" / "compositions" / "A.tsx").write_text("a", encoding="utf-8")
    (root / "assets" / "branding" / "fonts").mkdir(parents=True)
    (root / "assets" / "branding" / "fonts" / "OFL.txt").write_text("ofl", encoding="utf-8")
    (root / "tests" / "fixtures").mkdir(parents=True)
    (root / "tests" / "fixtures" / "props_valid.json").write_text("{}", encoding="utf-8")
    set_tree_read_only(studio)
    set_tree_read_only(root / "assets")
    yield root
    clear_tree(root)


@pytest.fixture
def data_root(tmp_path):
    root = tmp_path / "data"
    yield root
    if root.exists():
        clear_tree(root)


@pytest.fixture
def work(data_root) -> Path:
    return data_root / "remotion_work"


@pytest.fixture
def outside(tmp_path):
    folder = tmp_path / "outside"
    (folder / "nested").mkdir(parents=True)
    (folder / "keep.txt").write_text("keep", encoding="utf-8")
    (folder / "nested" / "keep.txt").write_text("keep too", encoding="utf-8")
    yield folder
    clear_tree(folder)


# --- A second sync works -------------------------------------------------------------------


def test_the_flag_really_reaches_the_copy(engine, data_root, work, npm):
    # Otherwise the tests below would pass without proving anything.
    sync(engine, data_root)
    assert is_read_only(work / "src")
    assert is_read_only(work / "src" / "Root.tsx")


def test_a_second_sync_works_on_read_only_folders_and_files(engine, data_root, work, npm):
    sync(engine, data_root)
    sync(engine, data_root)
    assert (work / "src" / "compositions" / "A.tsx").read_text("utf-8") == "a"
    assert (work / "public" / "fonts" / "OFL.txt").read_text("utf-8") == "ofl"


def test_a_file_removed_from_a_read_only_repo_still_leaves_the_build_copy(
    engine, data_root, work, npm
):
    sync(engine, data_root)
    stale = engine / "remotion_studio" / "src" / "compositions" / "A.tsx"
    os.chmod(stale, stat.S_IWRITE)
    stale.unlink()
    sync(engine, data_root)
    assert not (work / "src" / "compositions" / "A.tsx").exists()


def test_a_read_only_file_at_the_top_of_the_work_folder_is_removed(engine, data_root, work, npm):
    work.mkdir(parents=True)
    (work / "stale.txt").write_text("stale", encoding="utf-8")
    set_read_only(work / "stale.txt")
    sync(engine, data_root)
    assert not (work / "stale.txt").exists()


def test_a_changed_lockfile_replaces_a_read_only_copy(engine, data_root, work, npm):
    sync(engine, data_root)
    set_read_only(work / "package-lock.json")  # as a copy made before this fix still is
    lockfile = engine / "remotion_studio" / "package-lock.json"
    os.chmod(lockfile, stat.S_IWRITE)
    lockfile.write_text('{"v": 2}', encoding="utf-8")
    assert sync(engine, data_root).ran_npm_ci is True
    assert (work / "package-lock.json").read_text("utf-8") == '{"v": 2}'


def test_a_read_only_stamp_does_not_stop_a_reinstall(engine, data_root, work, npm):
    sync(engine, data_root)
    set_read_only(work / ".synced-lock.sha256")
    lockfile = engine / "remotion_studio" / "package-lock.json"
    os.chmod(lockfile, stat.S_IWRITE)
    lockfile.write_text('{"v": 2}', encoding="utf-8")
    assert sync(engine, data_root).ran_npm_ci is True


def test_a_read_only_stamp_does_not_stop_pull_lock(engine, data_root, work, npm):
    sync(engine, data_root)
    set_read_only(work / ".synced-lock.sha256")
    lockfile = engine / "remotion_studio" / "package-lock.json"
    os.chmod(lockfile, stat.S_IWRITE)
    pull_lock(engine, data_root)
    assert lockfile.read_text("utf-8") == '{"v": 1}'


def test_the_repo_keeps_its_flags(engine, data_root, npm):
    sync(engine, data_root)
    sync(engine, data_root)
    assert is_read_only(engine / "remotion_studio" / "src")
    assert is_read_only(engine / "remotion_studio" / "src" / "Root.tsx")


def test_node_modules_and_out_keep_their_files_and_flags(engine, data_root, work, npm):
    sync(engine, data_root)
    (work / "out").mkdir()
    (work / "out" / "keep.mp4").write_text("x", encoding="utf-8")
    set_read_only(work / "out" / "keep.mp4")
    (work / "node_modules" / "keep.js").write_text("x", encoding="utf-8")
    set_read_only(work / "node_modules" / "keep.js")
    sync(engine, data_root)
    assert is_read_only(work / "out" / "keep.mp4")
    assert is_read_only(work / "node_modules" / "keep.js")


# --- Links are never followed --------------------------------------------------------------


def test_a_read_only_junction_at_the_top_is_removed_and_its_target_keeps_its_flags(
    engine, data_root, work, npm, outside
):
    set_tree_read_only(outside)
    work.mkdir(parents=True)
    link = work / "link"
    make_junction(link, outside)
    set_read_only(link)
    sync(engine, data_root)
    assert not os.path.lexists(link)
    assert is_read_only(outside)
    assert is_read_only(outside / "keep.txt")
    assert is_read_only(outside / "nested" / "keep.txt")
    assert (outside / "nested" / "keep.txt").read_text("utf-8") == "keep too"


def test_a_junction_deep_in_a_read_only_folder_leaves_its_target_alone(
    engine, data_root, work, npm, outside
):
    set_tree_read_only(outside)
    sync(engine, data_root)
    nested = work / "src" / "compositions"
    link = nested / "link"
    make_junction(link, outside)
    set_read_only(link)
    set_read_only(nested)
    sync(engine, data_root)
    assert not os.path.lexists(link)
    assert is_read_only(outside)
    assert is_read_only(outside / "keep.txt")
    assert (outside / "keep.txt").read_text("utf-8") == "keep"


def test_a_writable_target_is_not_given_the_flag_or_changed(engine, data_root, work, npm, outside):
    work.mkdir(parents=True)
    link = work / "link"
    make_junction(link, outside)
    set_read_only(link)
    sync(engine, data_root)
    assert not is_read_only(outside)
    assert (outside / "keep.txt").read_text("utf-8") == "keep"


# --- Only paths verified inside the work folder --------------------------------------------


def test_the_flag_is_not_cleared_on_a_path_outside_the_work_folder(data_root, work, outside):
    work.mkdir(parents=True)
    file = outside / "keep.txt"
    set_read_only(file)
    with pytest.raises(RemotionSyncError, match="outside"):
        sync_module._clear_read_only(file, data_root)
    assert is_read_only(file)


def test_the_flag_is_not_cleared_through_a_junction_in_the_work_folder(data_root, work, outside):
    work.mkdir(parents=True)
    make_junction(work / "link", outside)
    file = outside / "keep.txt"
    set_read_only(file)
    with pytest.raises(RemotionSyncError, match="outside"):
        sync_module._clear_read_only(work / "link" / "keep.txt", data_root)
    assert is_read_only(file)


def test_dot_dot_cannot_lead_the_clear_out_of_the_work_folder(data_root, work, outside):
    work.mkdir(parents=True)
    file = outside / "keep.txt"
    set_read_only(file)
    roundabout = work / ".." / ".." / outside.name / "keep.txt"
    with pytest.raises(RemotionSyncError, match="outside"):
        sync_module._clear_read_only(roundabout, data_root)
    assert is_read_only(file)


def test_a_folder_whose_name_only_starts_like_the_work_folder_is_outside(data_root, work):
    work.mkdir(parents=True)
    sibling = data_root / f"{work.name}_other"
    sibling.mkdir()
    file = sibling / "keep.txt"
    file.write_text("keep", encoding="utf-8")
    set_read_only(file)
    with pytest.raises(RemotionSyncError, match="outside"):
        sync_module._clear_read_only(file, data_root)
    assert is_read_only(file)


def test_the_work_folder_itself_is_not_a_path_inside_it(data_root, work):
    work.mkdir(parents=True)
    set_read_only(work)
    with pytest.raises(RemotionSyncError, match="outside"):
        sync_module._clear_read_only(work, data_root)
    assert is_read_only(work)


def test_a_work_folder_that_is_a_junction_is_still_refused_before_any_flag_changes(
    data_root, work, outside
):
    data_root.mkdir()
    make_junction(work, outside)
    file = outside / "keep.txt"
    set_read_only(file)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync_module._clear_read_only(work / "keep.txt", data_root)
    assert is_read_only(file)


def test_a_failure_other_than_permission_is_not_retried(data_root, work, monkeypatch):
    work.mkdir(parents=True)
    (work / "folder").mkdir()
    cleared = []
    monkeypatch.setattr(sync_module, "_clear_read_only", lambda *args: cleared.append(args))

    def fail(path, **kwargs):
        kwargs["onexc"](os.rmdir, str(path), OSError("disk error"))

    monkeypatch.setattr(sync_module.shutil, "rmtree", fail)
    with pytest.raises(OSError, match="disk error"):
        sync_module._remove(work / "folder", data_root)
    assert cleared == []


def test_a_permission_failure_outside_a_delete_is_not_retried(data_root, work, monkeypatch):
    work.mkdir(parents=True)
    (work / "folder").mkdir()
    cleared = []
    monkeypatch.setattr(sync_module, "_clear_read_only", lambda *args: cleared.append(args))

    def fail(path, **kwargs):
        kwargs["onexc"](os.scandir, str(path), PermissionError("no access"))

    monkeypatch.setattr(sync_module.shutil, "rmtree", fail)
    with pytest.raises(PermissionError, match="no access"):
        sync_module._remove(work / "folder", data_root)
    assert cleared == []
