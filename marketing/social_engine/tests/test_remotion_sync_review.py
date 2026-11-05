"""What Round 2's review of the sync proved, and the fixes for it. Temp folders only."""

import hashlib
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest
from conftest import make_junction

import core.remotion_sync as sync_module
from core.remotion_sync import RemotionSyncError, pull_lock, sync


def is_read_only(path: Path) -> bool:
    return bool(os.lstat(path).st_file_attributes & stat.FILE_ATTRIBUTE_READONLY)


class FakeNpm:
    def __init__(self):
        self.count = 0
        self.args = None
        self.exit_code = 0

    def __call__(self, args, **kwargs):
        self.count += 1
        self.args = list(args)
        (Path(kwargs["cwd"]) / "node_modules").mkdir(exist_ok=True)
        return subprocess.CompletedProcess(args, self.exit_code, stdout="", stderr="")


@pytest.fixture
def npm(monkeypatch) -> FakeNpm:
    fake = FakeNpm()
    monkeypatch.setattr(sync_module.subprocess, "run", fake)
    monkeypatch.setattr(sync_module.shutil, "which", lambda name: f"C:/fake/{name}.cmd")
    return fake


@pytest.fixture
def engine(tmp_path):
    root = tmp_path / "engine"
    studio = root / "remotion_studio"
    (studio / "src").mkdir(parents=True)
    (studio / "package.json").write_text('{"name": "x"}', encoding="utf-8")
    (studio / "package-lock.json").write_text('{"v": 1}', encoding="utf-8")
    (studio / "src" / "Root.tsx").write_text("root", encoding="utf-8")
    (root / "assets" / "branding").mkdir(parents=True)
    (root / "tests" / "fixtures").mkdir(parents=True)
    (root / "tests" / "fixtures" / "props_valid.json").write_text("{}", encoding="utf-8")
    return root


@pytest.fixture
def data_root(tmp_path):
    return tmp_path / "data"


@pytest.fixture
def work(data_root):
    return data_root / "remotion_work"


@pytest.fixture
def outside(tmp_path):
    folder = tmp_path / "outside"
    folder.mkdir()
    return folder


# --- Hard links ----------------------------------------------------------------------------------


def test_a_kept_lockfile_that_is_a_hard_link_is_refused_and_not_written_through(
    engine, data_root, work, outside, npm
):
    work.mkdir(parents=True)
    precious = outside / "precious.json"
    precious.write_text("precious", encoding="utf-8")
    os.link(precious, work / "package-lock.json")
    with pytest.raises(RemotionSyncError, match="hard link, and sync overwrites"):
        sync(engine, data_root)
    assert precious.read_text("utf-8") == "precious"


def test_a_stamp_that_is_a_hard_link_is_refused_and_not_written_through(
    engine, data_root, work, outside, npm
):
    sync(engine, data_root)
    precious = outside / "precious.txt"
    precious.write_text("precious", encoding="utf-8")
    (work / ".synced-lock.sha256").unlink()
    os.link(precious, work / ".synced-lock.sha256")
    for call in (sync, pull_lock):
        with pytest.raises(RemotionSyncError, match="hard link"):
            call(engine, data_root)
    assert precious.read_text("utf-8") == "precious"


def test_a_repo_lockfile_that_is_a_hard_link_is_not_pulled_over(
    engine, data_root, work, outside, npm
):
    sync(engine, data_root)
    (work / "package-lock.json").write_text('{"v": 2}', encoding="utf-8")
    precious = outside / "precious.json"
    precious.write_text("precious", encoding="utf-8")
    lock = engine / "remotion_studio" / "package-lock.json"
    lock.unlink()
    os.link(precious, lock)
    with pytest.raises(RemotionSyncError, match="link"):
        pull_lock(engine, data_root)
    assert precious.read_text("utf-8") == "precious"


def test_the_flag_outside_is_not_cleared_through_a_hard_link(engine, data_root, work, outside, npm):
    work.mkdir(parents=True)
    precious = outside / "read_only.txt"
    precious.write_text("precious", encoding="utf-8")
    os.link(precious, work / "stale.txt")
    os.chmod(precious, stat.S_IREAD)
    assert is_read_only(work / "stale.txt")
    with pytest.raises(RemotionSyncError, match="hard link"):
        sync(engine, data_root)
    assert is_read_only(precious)
    assert precious.read_text("utf-8") == "precious"


def test_the_flag_outside_is_not_cleared_through_a_nested_hard_link(
    engine, data_root, work, outside, npm
):
    (work / "stale" / "deeper").mkdir(parents=True)
    precious = outside / "read_only.txt"
    precious.write_text("precious", encoding="utf-8")
    os.link(precious, work / "stale" / "deeper" / "linked.txt")
    os.chmod(precious, stat.S_IREAD)
    with pytest.raises(RemotionSyncError, match="hard link"):
        sync(engine, data_root)
    assert is_read_only(precious)


def test_a_writable_stale_hard_link_is_removed_and_the_file_outside_stays(
    engine, data_root, work, outside, npm
):
    work.mkdir(parents=True)
    precious = outside / "writable.txt"
    precious.write_text("precious", encoding="utf-8")
    os.link(precious, work / "stale.txt")
    sync(engine, data_root)
    assert not (work / "stale.txt").exists()
    assert precious.read_text("utf-8") == "precious"


def test_a_read_only_file_that_is_no_link_is_still_cleared(engine, data_root, work, npm):
    work.mkdir(parents=True)
    (work / "stale.txt").write_text("stale", encoding="utf-8")
    os.chmod(work / "stale.txt", stat.S_IREAD)
    sync(engine, data_root)
    assert not (work / "stale.txt").exists()


# --- Junctions -----------------------------------------------------------------------------------


def test_a_junction_nested_deep_in_the_work_folder_is_not_followed(
    engine, data_root, work, outside, npm
):
    nested = work / "stale" / "deeper"
    nested.mkdir(parents=True)
    (outside / "keep.txt").write_text("keep", encoding="utf-8")
    os.chmod(outside / "keep.txt", stat.S_IREAD)
    make_junction(nested / "link", outside)
    os.chmod(nested, stat.S_IREAD)
    sync(engine, data_root)
    assert (outside / "keep.txt").read_text("utf-8") == "keep"
    assert is_read_only(outside / "keep.txt")
    assert not (work / "stale").exists()


def test_a_studio_folder_that_is_a_junction_is_not_pulled_through(
    tmp_path, data_root, work, outside, npm
):
    real = outside / "elsewhere_studio"
    (real / "src").mkdir(parents=True)
    (real / "package-lock.json").write_text("precious", encoding="utf-8")
    root = tmp_path / "engine2"
    root.mkdir()
    make_junction(root / "remotion_studio", real)
    work.mkdir(parents=True)
    (work / "package-lock.json").write_text("from work", encoding="utf-8")
    with pytest.raises(RemotionSyncError, match="link"):
        pull_lock(root, data_root)
    assert (real / "package-lock.json").read_text("utf-8") == "precious"


# --- What the studio may bring -------------------------------------------------------------------


def test_a_public_folder_in_the_studio_is_not_copied(engine, data_root, work, npm):
    stray = engine / "remotion_studio" / "public" / "clips"
    stray.mkdir(parents=True)
    (stray / "raw.mp4").write_bytes(b"raw")
    sync(engine, data_root)
    assert (work / "public").is_dir()
    assert not (work / "public" / "clips").exists()


def test_a_nested_folder_named_public_is_copied_as_any_other(engine, data_root, work, npm):
    nested = engine / "remotion_studio" / "src" / "public"
    nested.mkdir(parents=True)
    (nested / "a.ts").write_text("a", encoding="utf-8")
    sync(engine, data_root)
    assert (work / "src" / "public" / "a.ts").is_file()


def test_a_stamp_committed_in_the_studio_cannot_skip_npm(engine, data_root, npm):
    studio = engine / "remotion_studio"
    sync(engine, data_root)
    assert npm.count == 1
    lock = studio / "package-lock.json"
    lock.write_text('{"v": 2, "tampered": true}', encoding="utf-8")
    (studio / ".synced-lock.sha256").write_text(
        hashlib.sha256(lock.read_bytes()).hexdigest(), encoding="utf-8"
    )
    assert sync(engine, data_root).ran_npm_ci is True


# --- The stamp -----------------------------------------------------------------------------------


@pytest.mark.parametrize("content", [b"\xff\xfe\x00garbage", b"", b"not the hash"])
def test_a_corrupt_stamp_means_a_reinstall(engine, data_root, work, npm, content):
    sync(engine, data_root)
    (work / ".synced-lock.sha256").write_bytes(content)
    assert sync(engine, data_root).ran_npm_ci is True


def test_pull_lock_after_a_failed_npm_ci_does_not_fake_an_install(engine, data_root, npm):
    sync(engine, data_root)
    lock = engine / "remotion_studio" / "package-lock.json"
    lock.write_text('{"v": 2}', encoding="utf-8")
    npm.exit_code = 1
    with pytest.raises(RemotionSyncError):
        sync(engine, data_root)  # npm died part way, and node_modules is half made
    npm.exit_code = 0
    pull_lock(engine, data_root)
    assert sync(engine, data_root).ran_npm_ci is True


def test_a_hand_edited_work_lockfile_gets_a_clean_install_once_pulled(engine, data_root, work, npm):
    sync(engine, data_root)
    (work / "package-lock.json").write_text('{"tampered": true}', encoding="utf-8")
    pull_lock(engine, data_root)
    assert sync(engine, data_root).ran_npm_ci is True


def test_pulling_the_lockfile_that_is_already_installed_needs_no_reinstall(engine, data_root, npm):
    sync(engine, data_root)
    pull_lock(engine, data_root)
    assert sync(engine, data_root).ran_npm_ci is False


# --- A tampered lockfile -------------------------------------------------------------------------


def test_a_tampered_lockfile_does_not_run_install_scripts(engine, data_root, npm):
    evil = {
        "packages": {
            "node_modules/x": {
                "version": "1.0.0",
                "resolved": "https://evil.example/x.tgz",
                "hasInstallScript": True,
            }
        }
    }
    lock = engine / "remotion_studio" / "package-lock.json"
    lock.write_text(json.dumps(evil), encoding="utf-8")
    sync(engine, data_root)
    assert npm.args == ["C:/fake/npm.cmd", "ci", "--ignore-scripts"]
