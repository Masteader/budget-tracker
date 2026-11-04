"""A link at the kept `node_modules` or `out` would turn `npm ci` or a render on another folder.
Everything here lives under `tmp_path`, and each outside folder is one the test made."""

import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from conftest import make_junction

import core.remotion_sync as sync_module
from core.remotion_sync import RemotionSyncError, checked_kept_folders, main, sync

KEPT = ["node_modules", "out"]
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
    (root / "remotion_studio" / "package-lock.json").write_text('{"v": 1}', encoding="utf-8")
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
    (folder / "nested").mkdir(parents=True)
    (folder / "keep.txt").write_text("keep", encoding="utf-8")
    (folder / "nested" / "keep.txt").write_text("keep too", encoding="utf-8")
    return folder


def tree(folder: Path) -> dict[str, str | None]:
    return {
        path.relative_to(folder).as_posix(): path.read_text("utf-8") if path.is_file() else None
        for path in folder.rglob("*")
    }


def assert_nothing_happened(work: Path, npm: FakeNpm) -> None:
    assert (work / "stale.txt").exists(), "the rebuild started before the refusal"
    assert npm.count == 0


@windows_only
@pytest.mark.parametrize("name", KEPT)
def test_a_junction_at_a_kept_folder_is_refused_and_its_target_keeps_everything(
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
@pytest.mark.parametrize("name", KEPT)
def test_a_junction_with_a_missing_target_is_refused(engine, data_root, work, npm, tmp_path, name):
    gone = tmp_path / "gone"
    gone.mkdir()
    make_junction(work / name, gone)
    gone.rmdir()
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@windows_only
@pytest.mark.parametrize("name", KEPT)
def test_a_junction_to_another_folder_inside_the_data_root_is_refused(
    engine, data_root, work, npm, name
):
    # Still a link, and whatever sits at that other path would be deleted or overwritten.
    elsewhere = data_root / "elsewhere"
    elsewhere.mkdir()
    (elsewhere / "keep.txt").write_text("keep", encoding="utf-8")
    make_junction(work / name, elsewhere)
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert (elsewhere / "keep.txt").exists()
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
def test_a_real_symlink_is_refused(engine, data_root, work, npm, outside, name):
    try:
        (work / name).symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip("creating symlinks needs developer mode on Windows")
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert tree(outside) == before
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
@pytest.mark.parametrize("method", ["is_symlink", "is_junction"])
def test_a_faked_link_is_refused(engine, data_root, work, npm, monkeypatch, name, method):
    # Creating a real symlink needs developer mode, so a link can be faked for one path.
    (work / name).mkdir()
    faked = work / name
    real = getattr(Path, method)
    monkeypatch.setattr(Path, method, lambda self: self == faked or real(self))
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
def test_any_other_reparse_point_is_refused(engine, data_root, work, npm, monkeypatch, name):
    (work / name).mkdir()
    real_lstat = os.lstat

    def lstat(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            return SimpleNamespace(
                st_mode=stat.S_IFDIR, st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT
            )
        return real_lstat(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os, "lstat", lstat)
    with pytest.raises(RemotionSyncError, match=f"{name}.*link"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
def test_a_real_path_outside_the_data_root_is_refused(
    engine, data_root, work, npm, outside, monkeypatch, name
):
    (work / name).mkdir()
    real_realpath = os.path.realpath

    def realpath(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            return str(outside)
        return real_realpath(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match=f"{name}.*outside"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
def test_a_real_path_that_cannot_be_worked_out_is_refused(
    engine, data_root, work, npm, monkeypatch, name
):
    (work / name).mkdir()
    real_realpath = os.path.realpath

    def realpath(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            raise OSError("loop")
        return real_realpath(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match=name):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
def test_a_folder_that_cannot_be_checked_is_refused(
    engine, data_root, work, npm, monkeypatch, name
):
    real_lstat = os.lstat

    def lstat(path, *args, **kwargs):
        if os.fspath(path) == str(work / name):
            raise PermissionError("no access")
        return real_lstat(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os, "lstat", lstat)
    with pytest.raises(RemotionSyncError, match="no access"):
        sync(engine, data_root)
    assert_nothing_happened(work, npm)


@pytest.mark.parametrize("name", KEPT)
def test_a_file_at_a_kept_path_is_refused_and_kept(engine, data_root, work, npm, name):
    (work / name).write_text("not a folder", encoding="utf-8")
    with pytest.raises(RemotionSyncError, match=f"{name}.*not a folder"):
        sync(engine, data_root)
    assert (work / name).read_text("utf-8") == "not a folder"
    assert_nothing_happened(work, npm)


@windows_only
def test_a_junction_at_node_modules_that_appears_during_the_copy_stops_npm_ci(
    engine, data_root, work, npm, outside, monkeypatch
):
    before = tree(outside)
    real_copytree = shutil.copytree

    def copy_then_link(*args, **kwargs):
        result = real_copytree(*args, **kwargs)
        if not (work / "node_modules").exists():
            make_junction(work / "node_modules", outside)
        return result

    monkeypatch.setattr(sync_module.shutil, "copytree", copy_then_link)
    with pytest.raises(RemotionSyncError, match="node_modules.*link"):
        sync(engine, data_root)
    assert tree(outside) == before
    assert npm.count == 0


@windows_only
def test_the_command_line_refuses_a_kept_junction(
    engine, data_root, work, npm, outside, monkeypatch, capsys
):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    make_junction(work / "out", outside)
    before = tree(outside)
    assert main(["--data-root", str(data_root)]) == 1
    assert "out is a link" in capsys.readouterr().err
    assert tree(outside) == before
    assert npm.count == 0


# --- Real folders keep working ---------------------------------------------------------


def test_real_kept_folders_pass_and_survive(engine, data_root, work, npm):
    (work / "node_modules").mkdir()
    (work / "node_modules" / "keep.js").write_text("x", encoding="utf-8")
    (work / "out").mkdir()
    (work / "out" / "keep.mp4").write_text("x", encoding="utf-8")
    sync(engine, data_root)
    assert (work / "node_modules" / "keep.js").exists()
    assert (work / "out" / "keep.mp4").exists()


def test_a_first_sync_with_no_kept_folders_is_fine(engine, data_root, npm):
    assert sync(engine, data_root).ran_npm_ci is True
    checked_kept_folders(data_root)


def test_no_work_folder_at_all_passes_the_check(data_root):
    checked_kept_folders(data_root)



@windows_only
def test_a_data_root_junction_with_real_kept_folders_still_works(engine, npm, tmp_path):
    real_root = tmp_path / "real_root"
    (real_root / "remotion_work" / "node_modules").mkdir(parents=True)
    (real_root / "remotion_work" / "out").mkdir()
    link = tmp_path / "root_link"
    make_junction(link, real_root)
    sync(engine, link)
    assert (real_root / "remotion_work" / "package.json").exists()


@windows_only
def test_a_data_root_junction_does_not_hide_a_kept_junction(engine, npm, tmp_path, outside):
    real_root = tmp_path / "real_root"
    (real_root / "remotion_work").mkdir(parents=True)
    make_junction(real_root / "remotion_work" / "out", outside)
    link = tmp_path / "root_link"
    make_junction(link, real_root)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match="out.*link"):
        sync(engine, link)
    assert tree(outside) == before


@windows_only
def test_a_kept_folder_in_another_letter_case_still_works(engine, data_root, work, npm):
    (work / "Node_Modules").mkdir()
    (work / "OUT").mkdir()
    checked_kept_folders(data_root)
