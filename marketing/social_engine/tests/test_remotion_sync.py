"""Copy the studio out of OneDrive before npm runs (spec Section 4, plan Section 2.3, task A6)."""

import json
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
from core.remotion_sync import RemotionSyncError, main, pull_lock, sync
from core.secrets import FORBIDDEN_ENV_PREFIX


class FakeNpm:
    """Stands in at the subprocess boundary, and can pretend to fail."""

    def __init__(self):
        self.calls = []
        self.returncode = 0

    def __call__(self, args, **kwargs):
        self.calls.append((list(args), kwargs))
        cwd = Path(kwargs["cwd"])
        if self.returncode == 0:
            (cwd / "node_modules").mkdir(exist_ok=True)
        return subprocess.CompletedProcess(args, self.returncode, stdout="", stderr="npm said no")

    @property
    def count(self) -> int:
        return len(self.calls)


@pytest.fixture
def npm(monkeypatch) -> FakeNpm:
    fake = FakeNpm()
    monkeypatch.setattr(sync_module.subprocess, "run", fake)
    monkeypatch.setattr(sync_module.shutil, "which", lambda name: f"C:/fake/{name}.cmd")
    return fake


@pytest.fixture
def engine(tmp_path) -> Path:
    root = tmp_path / "engine"
    (root / "remotion_studio" / "src" / "compositions").mkdir(parents=True)
    (root / "remotion_studio" / "package.json").write_text('{"name": "x"}', encoding="utf-8")
    (root / "remotion_studio" / "package-lock.json").write_text('{"v": 1}', encoding="utf-8")
    (root / "remotion_studio" / "props.schema.json").write_text("{}", encoding="utf-8")
    (root / "remotion_studio" / "src" / "Root.tsx").write_text("root", encoding="utf-8")
    (root / "remotion_studio" / "src" / "compositions" / "A.tsx").write_text("a", encoding="utf-8")
    (root / "assets" / "branding" / "fonts" / "cairo").mkdir(parents=True)
    (root / "assets" / "branding" / "brand_tokens.json").write_text("{}", encoding="utf-8")
    (root / "assets" / "branding" / "fonts" / "cairo" / "OFL.txt").write_text("ofl", "utf-8")
    (root / "tests" / "fixtures").mkdir(parents=True)
    (root / "tests" / "fixtures" / "props_valid.json").write_text('{"ok": 1}', encoding="utf-8")
    return root


@pytest.fixture
def data_root(tmp_path) -> Path:
    return tmp_path / "data"


def work(data_root: Path) -> Path:
    return data_root / "remotion_work"


# --- What gets copied ------------------------------------------------------------------


def test_it_copies_all_of_the_studio(engine, data_root, npm):
    sync(engine, data_root)
    assert (work(data_root) / "package.json").read_text("utf-8") == '{"name": "x"}'
    assert (work(data_root) / "package-lock.json").read_text("utf-8") == '{"v": 1}'
    assert (work(data_root) / "props.schema.json").exists()
    assert (work(data_root) / "src" / "Root.tsx").read_text("utf-8") == "root"
    assert (work(data_root) / "src" / "compositions" / "A.tsx").read_text("utf-8") == "a"


def test_it_copies_branding_into_public(engine, data_root, npm):
    sync(engine, data_root)
    assert (work(data_root) / "public" / "brand_tokens.json").exists()
    assert (work(data_root) / "public" / "fonts" / "cairo" / "OFL.txt").read_text("utf-8") == "ofl"


def test_it_copies_the_valid_props_fixture(engine, data_root, npm):
    sync(engine, data_root)
    copied = work(data_root) / "fixtures" / "props_valid.json"
    assert json.loads(copied.read_text("utf-8")) == {"ok": 1}


def test_it_works_before_branding_exists(engine, data_root, npm):
    # Batch F adds assets/branding/, and this batch must still run on its own.
    shutil.rmtree(engine / "assets")
    sync(engine, data_root)
    assert (work(data_root) / "public").is_dir()


def test_a_missing_props_fixture_is_an_error(engine, data_root, npm):
    (engine / "tests" / "fixtures" / "props_valid.json").unlink()
    with pytest.raises(RemotionSyncError, match="props_valid"):
        sync(engine, data_root)


def test_a_missing_studio_is_an_error(engine, data_root, npm):
    shutil.rmtree(engine / "remotion_studio")
    with pytest.raises(RemotionSyncError, match="remotion_studio"):
        sync(engine, data_root)


def test_a_file_removed_from_the_repo_leaves_the_build_copy(engine, data_root, npm):
    sync(engine, data_root)
    (engine / "remotion_studio" / "src" / "compositions" / "A.tsx").unlink()
    (engine / "remotion_studio" / "props.schema.json").unlink()
    (engine / "assets" / "branding" / "brand_tokens.json").unlink()
    sync(engine, data_root)
    assert not (work(data_root) / "src" / "compositions" / "A.tsx").exists()
    assert not (work(data_root) / "props.schema.json").exists()
    assert not (work(data_root) / "public" / "brand_tokens.json").exists()


def test_node_modules_and_output_in_the_work_folder_survive_a_sync(engine, data_root, npm):
    sync(engine, data_root)
    (work(data_root) / "node_modules" / "keep.js").write_text("x", encoding="utf-8")
    (work(data_root) / "out").mkdir()
    (work(data_root) / "out" / "keep.png").write_text("x", encoding="utf-8")
    sync(engine, data_root)
    assert (work(data_root) / "node_modules" / "keep.js").exists()
    assert (work(data_root) / "out" / "keep.png").exists()


def test_a_lockfile_from_npm_install_survives_a_sync_before_it_is_pulled(engine, data_root, npm):
    (engine / "remotion_studio" / "package-lock.json").unlink()
    sync(engine, data_root)
    (work(data_root) / "package-lock.json").write_text('{"fresh": 1}', encoding="utf-8")
    sync(engine, data_root)
    assert (work(data_root) / "package-lock.json").read_text("utf-8") == '{"fresh": 1}'


# --- When npm runs ---------------------------------------------------------------------


def test_npm_ci_runs_on_the_first_sync_in_the_work_folder(engine, data_root, npm):
    assert sync(engine, data_root).ran_npm_ci is True
    assert npm.count == 1
    args, kwargs = npm.calls[0]
    assert args == ["C:/fake/npm.cmd", "ci"]
    assert Path(kwargs["cwd"]) == work(data_root)


def test_npm_ci_does_not_run_when_the_lockfile_has_not_changed(engine, data_root, npm):
    sync(engine, data_root)
    assert sync(engine, data_root).ran_npm_ci is False
    assert npm.count == 1


def test_a_source_change_alone_does_not_run_npm_ci(engine, data_root, npm):
    sync(engine, data_root)
    (engine / "remotion_studio" / "src" / "Root.tsx").write_text("changed", encoding="utf-8")
    assert sync(engine, data_root).ran_npm_ci is False
    assert (work(data_root) / "src" / "Root.tsx").read_text("utf-8") == "changed"


def test_npm_ci_runs_again_when_the_lockfile_changes(engine, data_root, npm):
    sync(engine, data_root)
    (engine / "remotion_studio" / "package-lock.json").write_text('{"v": 2}', encoding="utf-8")
    assert sync(engine, data_root).ran_npm_ci is True
    assert npm.count == 2


def test_npm_ci_runs_again_when_node_modules_is_gone(engine, data_root, npm):
    sync(engine, data_root)
    shutil.rmtree(work(data_root) / "node_modules")
    assert sync(engine, data_root).ran_npm_ci is True


def test_npm_does_not_run_with_no_lockfile(engine, data_root, npm):
    (engine / "remotion_studio" / "package-lock.json").unlink()
    assert sync(engine, data_root).ran_npm_ci is False
    assert npm.count == 0


def test_a_failed_npm_ci_is_an_error_and_is_retried_next_time(engine, data_root, npm):
    npm.returncode = 1
    with pytest.raises(RemotionSyncError, match="npm ci"):
        sync(engine, data_root)
    npm.returncode = 0
    assert sync(engine, data_root).ran_npm_ci is True


def test_missing_npm_is_a_clear_error(engine, data_root, npm, monkeypatch):
    monkeypatch.setattr(sync_module.shutil, "which", lambda name: None)
    with pytest.raises(RemotionSyncError, match="npm"):
        sync(engine, data_root)


def test_npm_gets_a_scrubbed_environment(engine, data_root, npm, monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "secret")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "secret")
    monkeypatch.setenv(FORBIDDEN_ENV_PREFIX + "URL", "secret")
    sync(engine, data_root)
    env = npm.calls[0][1]["env"]
    assert "TELEGRAM_BOT_TOKEN" not in env
    assert "ANTHROPIC_API_KEY" not in env
    assert FORBIDDEN_ENV_PREFIX + "URL" not in env
    assert "PATH" in {name.upper() for name in env}


def test_npm_never_runs_inside_the_repo(engine, data_root, npm):
    sync(engine, data_root)
    assert not (engine / "remotion_studio" / "node_modules").exists()
    assert engine not in Path(npm.calls[0][1]["cwd"]).parents


def test_a_real_npm_child_sees_no_secret_and_its_output_is_not_repeated(
    engine, data_root, monkeypatch, tmp_path
):
    secrets = {
        "CLAUDE_CODE_OAUTH_TOKEN": "SECRET-1",
        "NPM_TOKEN": "SECRET-2",
        "VITE_" + FORBIDDEN_ENV_PREFIX + "ANON_KEY": "SECRET-3",
        "GEM" + "INI_API_KEY": "SECRET-4",
        "WEBHOOK_SECRET": "SECRET-5",
    }
    for name, value in secrets.items():
        monkeypatch.setenv(name, value)
    seen = tmp_path / "seen.txt"
    echoed = " ".join(f"%{name}%" for name in secrets)
    fake = tmp_path / "npm.cmd"
    fake.write_text(
        f'@echo off\r\necho RAN {echoed} > "{seen}"\r\n'
        "echo PATH=%PATH% LEAK-MARKER 1>&2\r\nexit /b 3\r\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(sync_module.shutil, "which", lambda name: str(fake))
    with pytest.raises(RemotionSyncError) as caught:
        sync(engine, data_root)
    assert "RAN" in seen.read_text("utf-8"), "the child did not run"
    assert "SECRET" not in seen.read_text("utf-8"), "the child saw a secret"
    message = str(caught.value)
    assert "exit code 3" in message
    assert "LEAK-MARKER" not in message
    assert os.environ["PATH"] not in message


def test_a_failed_lockfile_update_cannot_pass_for_the_old_install(engine, data_root, npm):
    # v1 installed, v2 fails halfway, then the repo goes back to v1. node_modules is unknown
    # by then, so npm ci has to run again.
    sync(engine, data_root)
    lockfile = engine / "remotion_studio" / "package-lock.json"
    lockfile.write_text('{"v": 2}', encoding="utf-8")
    npm.returncode = 1
    with pytest.raises(RemotionSyncError):
        sync(engine, data_root)
    npm.returncode = 0
    lockfile.write_text('{"v": 1}', encoding="utf-8")
    assert sync(engine, data_root).ran_npm_ci is True


@pytest.mark.skipif(sys.platform != "win32", reason="junctions are a Windows feature")
def test_a_junction_in_the_work_folder_is_removed_without_touching_its_target(
    engine, data_root, npm, tmp_path
):
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "keep.txt").write_text("keep", encoding="utf-8")
    work(data_root).mkdir(parents=True)
    link = work(data_root) / "link"
    make_junction(link, outside)
    sync(engine, data_root)
    assert not link.exists()
    assert (outside / "keep.txt").read_text("utf-8") == "keep"


def test_a_symlink_in_the_work_folder_is_removed_without_touching_its_target(
    engine, data_root, npm, tmp_path
):
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "keep.txt").write_text("keep", encoding="utf-8")
    work(data_root).mkdir(parents=True)
    link = work(data_root) / "link"
    try:
        link.symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip("creating symlinks needs developer mode on Windows")
    sync(engine, data_root)
    assert not link.is_symlink()
    assert (outside / "keep.txt").exists()


def test_a_link_to_a_folder_is_unlinked_rather_than_emptied(monkeypatch):
    # Creating a real symlink needs developer mode, so the decision is checked directly too.
    calls = []

    class Link:
        def is_junction(self):
            return False

        def is_symlink(self):
            return True

        def is_dir(self):
            return True

        def unlink(self):
            calls.append("unlink")

    monkeypatch.setattr(sync_module.shutil, "rmtree", lambda path: calls.append("rmtree"))
    sync_module._remove(Link())
    assert calls == ["unlink"]


def test_a_file_system_error_is_a_clear_sync_error(engine, data_root, npm, monkeypatch):
    def refuse(*args, **kwargs):
        raise PermissionError("locked")

    monkeypatch.setattr(sync_module.shutil, "copytree", refuse)
    with pytest.raises(RemotionSyncError, match="locked"):
        sync(engine, data_root)


# --- The work folder itself has to be a real folder ------------------------------------

windows_only = pytest.mark.skipif(sys.platform != "win32", reason="junctions need Windows")


def tree(folder: Path) -> dict[str, str | None]:
    return {
        path.relative_to(folder).as_posix(): path.read_text("utf-8") if path.is_file() else None
        for path in folder.rglob("*")
    }


@pytest.fixture
def outside(tmp_path) -> Path:
    folder = tmp_path / "outside"
    (folder / "nested").mkdir(parents=True)
    (folder / "keep.txt").write_text("keep", encoding="utf-8")
    (folder / "nested" / "keep.txt").write_text("keep too", encoding="utf-8")
    return folder


@pytest.fixture
def stale_work(data_root) -> Path:
    """A real work folder holding a file that any rebuild would delete."""
    folder = work(data_root)
    folder.mkdir(parents=True)
    (folder / "stale.txt").write_text("stale", encoding="utf-8")
    return folder


def pretend(monkeypatch, method: str, faked: Path) -> None:
    """Creating a real symlink needs developer mode, so a link can be faked for one path."""
    real = getattr(Path, method)
    monkeypatch.setattr(Path, method, lambda self: self == faked or real(self))


@windows_only
def test_a_junction_as_the_work_folder_is_refused_and_its_target_keeps_everything(
    engine, data_root, npm, outside
):
    data_root.mkdir()
    make_junction(work(data_root), outside)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert tree(outside) == before
    assert work(data_root).is_junction()
    assert npm.count == 0


@windows_only
def test_the_command_line_refuses_a_junction_as_the_work_folder(
    engine, data_root, npm, outside, monkeypatch, capsys
):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    data_root.mkdir()
    make_junction(work(data_root), outside)
    before = tree(outside)
    assert main(["--data-root", str(data_root)]) == 1
    assert "remotion_work" in capsys.readouterr().err
    assert tree(outside) == before
    assert npm.count == 0


@windows_only
def test_a_junction_with_a_missing_target_is_refused(engine, data_root, npm, tmp_path):
    gone = tmp_path / "gone"
    gone.mkdir()
    data_root.mkdir()
    make_junction(work(data_root), gone)
    gone.rmdir()
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert work(data_root).is_junction()


@windows_only
def test_a_junction_pointing_back_inside_the_data_root_is_refused(engine, data_root, npm):
    real_folder = data_root / "elsewhere"
    real_folder.mkdir(parents=True)
    (real_folder / "keep.txt").write_text("keep", encoding="utf-8")
    make_junction(work(data_root), real_folder)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert (real_folder / "keep.txt").exists()


@windows_only
def test_pull_lock_refuses_a_junction_as_the_work_folder(engine, data_root, npm, outside):
    (outside / "package-lock.json").write_text('{"foreign": 1}', encoding="utf-8")
    data_root.mkdir()
    make_junction(work(data_root), outside)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        pull_lock(engine, data_root)
    assert (engine / "remotion_studio" / "package-lock.json").read_text("utf-8") == '{"v": 1}'
    assert tree(outside) == before


@windows_only
def test_a_junction_that_appears_while_the_folder_is_made_is_refused(
    engine, data_root, npm, outside, monkeypatch
):
    before = tree(outside)
    real_mkdir = Path.mkdir

    def racing_mkdir(self, *args, **kwargs):
        if self == work(data_root):
            real_mkdir(data_root, parents=True)
            make_junction(self, outside)
        else:
            real_mkdir(self, *args, **kwargs)

    monkeypatch.setattr(Path, "mkdir", racing_mkdir)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert tree(outside) == before


def test_a_real_symlink_as_the_work_folder_is_refused(engine, data_root, npm, outside):
    data_root.mkdir()
    try:
        work(data_root).symlink_to(outside, target_is_directory=True)
    except OSError:
        pytest.skip("creating symlinks needs developer mode on Windows")
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert tree(outside) == before


@pytest.mark.parametrize("method", ["is_symlink", "is_junction"])
def test_a_faked_link_as_the_work_folder_is_refused(
    engine, data_root, npm, stale_work, monkeypatch, method
):
    pretend(monkeypatch, method, stale_work)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert (stale_work / "stale.txt").exists()
    assert npm.count == 0


def test_a_faked_link_is_refused_by_pull_lock_too(engine, data_root, npm, stale_work, monkeypatch):
    (stale_work / "package-lock.json").write_text('{"foreign": 1}', encoding="utf-8")
    pretend(monkeypatch, "is_symlink", stale_work)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        pull_lock(engine, data_root)
    assert (engine / "remotion_studio" / "package-lock.json").read_text("utf-8") == '{"v": 1}'


def test_any_other_reparse_point_as_the_work_folder_is_refused(
    engine, data_root, npm, stale_work, monkeypatch
):
    real_lstat = os.lstat

    def lstat(path, *args, **kwargs):
        if os.fspath(path) == str(stale_work):
            return SimpleNamespace(
                st_mode=stat.S_IFDIR, st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT
            )
        return real_lstat(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os, "lstat", lstat)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, data_root)
    assert (stale_work / "stale.txt").exists()


def test_a_real_path_outside_the_data_root_is_refused(
    engine, data_root, npm, stale_work, outside, monkeypatch
):
    real_realpath = os.path.realpath

    def realpath(path, *args, **kwargs):
        if os.fspath(path) == str(stale_work):
            return str(outside)
        return real_realpath(path, *args, **kwargs)

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match="remotion_work.*outside"):
        sync(engine, data_root)
    assert (stale_work / "stale.txt").exists()


def test_a_real_path_that_cannot_be_worked_out_is_refused(
    engine, data_root, npm, stale_work, monkeypatch
):
    def realpath(path, *args, **kwargs):
        raise OSError("loop")

    monkeypatch.setattr(sync_module.os.path, "realpath", realpath)
    with pytest.raises(RemotionSyncError, match="remotion_work"):
        sync(engine, data_root)
    assert (stale_work / "stale.txt").exists()


def test_a_file_named_like_the_work_folder_is_refused_and_kept(engine, data_root, npm):
    data_root.mkdir()
    work(data_root).write_text("not a folder", encoding="utf-8")
    with pytest.raises(RemotionSyncError, match="remotion_work.*not a folder"):
        sync(engine, data_root)
    assert work(data_root).read_text("utf-8") == "not a folder"


@windows_only
def test_a_data_root_that_is_itself_a_junction_still_works(engine, npm, tmp_path):
    # The check compares real paths, so a link above the work folder is resolved, not refused.
    real_root = tmp_path / "real_root"
    (real_root / "remotion_work").mkdir(parents=True)
    (real_root / "remotion_work" / "stale.txt").write_text("stale", encoding="utf-8")
    (real_root / "sibling.txt").write_text("keep", encoding="utf-8")
    link = tmp_path / "root_link"
    make_junction(link, real_root)
    sync(engine, link)
    assert (real_root / "remotion_work" / "package.json").exists()
    assert not (real_root / "remotion_work" / "stale.txt").exists()
    assert (real_root / "sibling.txt").exists()


@windows_only
def test_a_junction_higher_up_than_the_data_root_still_works(engine, npm, tmp_path):
    real_parent = tmp_path / "real_parent"
    real_parent.mkdir()
    link = tmp_path / "parent_link"
    make_junction(link, real_parent)
    sync(engine, link / "data")
    assert (real_parent / "data" / "remotion_work" / "package.json").exists()


@windows_only
def test_a_data_root_junction_does_not_hide_a_work_folder_junction(engine, npm, tmp_path, outside):
    real_root = tmp_path / "real_root"
    real_root.mkdir()
    make_junction(real_root / "remotion_work", outside)
    link = tmp_path / "root_link"
    make_junction(link, real_root)
    before = tree(outside)
    with pytest.raises(RemotionSyncError, match="remotion_work.*link"):
        sync(engine, link)
    assert tree(outside) == before


def test_dot_dot_in_the_data_root_still_works(engine, data_root, npm, stale_work):
    roundabout = data_root / "gone" / ".." / ".." / data_root.name
    sync(engine, roundabout)
    assert (stale_work / "package.json").exists()
    assert not (stale_work / "stale.txt").exists()


@windows_only
def test_a_work_folder_in_another_letter_case_still_works(engine, data_root, npm):
    data_root.mkdir()
    (data_root / "Remotion_Work").mkdir()
    sync(engine, data_root)
    assert (data_root / "Remotion_Work" / "package.json").exists()


# --- Pre-flight ------------------------------------------------------------------------


def test_preflight_fails_if_node_modules_is_in_the_repo(engine, data_root, npm):
    (engine / "remotion_studio" / "node_modules").mkdir()
    with pytest.raises(RemotionSyncError, match="node_modules"):
        sync(engine, data_root)
    assert npm.count == 0
    assert not work(data_root).exists()


def test_preflight_catches_node_modules_for_pull_lock_as_well(engine, data_root, npm):
    sync(engine, data_root)
    (engine / "remotion_studio" / "node_modules").mkdir()
    with pytest.raises(RemotionSyncError, match="node_modules"):
        pull_lock(engine, data_root)


# --- Pulling the lockfile back ---------------------------------------------------------


def test_pull_lock_copies_the_lockfile_back(engine, data_root, npm):
    sync(engine, data_root)
    (work(data_root) / "package-lock.json").write_text('{"v": 9}', encoding="utf-8")
    pull_lock(engine, data_root)
    assert (engine / "remotion_studio" / "package-lock.json").read_text("utf-8") == '{"v": 9}'


def test_pull_lock_with_no_lockfile_is_an_error(engine, data_root, npm):
    work(data_root).mkdir(parents=True)
    with pytest.raises(RemotionSyncError, match="package-lock"):
        pull_lock(engine, data_root)


def test_a_pulled_lockfile_does_not_trigger_npm_ci(engine, data_root, npm):
    # It came from that very node_modules, so nothing needs reinstalling.
    (engine / "remotion_studio" / "package-lock.json").unlink()
    sync(engine, data_root)
    (work(data_root) / "node_modules").mkdir()
    (work(data_root) / "package-lock.json").write_text('{"fresh": 1}', encoding="utf-8")
    pull_lock(engine, data_root)
    assert sync(engine, data_root).ran_npm_ci is False
    assert npm.count == 0


# --- Command line ----------------------------------------------------------------------


def test_the_command_line_syncs(engine, data_root, npm, monkeypatch):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    assert main(["--data-root", str(data_root)]) == 0
    assert (work(data_root) / "src" / "Root.tsx").exists()


@pytest.mark.parametrize(
    "name",
    [FORBIDDEN_ENV_PREFIX + "URL", "VITE_" + FORBIDDEN_ENV_PREFIX + "ANON_KEY"],
)
def test_the_command_line_stops_on_a_forbidden_variable(
    engine, data_root, npm, monkeypatch, capsys, name
):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    monkeypatch.setenv(name, "very-secret-value")
    assert main(["--data-root", str(data_root)]) == 1
    error = capsys.readouterr().err
    assert name in error
    assert "very-secret-value" not in error
    assert npm.count == 0
    assert not work(data_root).exists()


def test_the_command_line_pulls_the_lock(engine, data_root, npm, monkeypatch):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    assert main(["--data-root", str(data_root)]) == 0
    (work(data_root) / "package-lock.json").write_text('{"v": 9}', encoding="utf-8")
    assert main(["--data-root", str(data_root), "--pull-lock"]) == 0
    assert (engine / "remotion_studio" / "package-lock.json").read_text("utf-8") == '{"v": 9}'


def test_the_command_line_reports_failure_with_a_clear_message(
    engine, data_root, npm, monkeypatch, capsys
):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    (engine / "remotion_studio" / "node_modules").mkdir()
    assert main(["--data-root", str(data_root)]) == 1
    assert "node_modules" in capsys.readouterr().err


def test_the_command_line_expands_and_checks_the_data_root(
    engine, npm, monkeypatch, tmp_path, capsys
):
    monkeypatch.setattr(sync_module, "ENGINE_ROOT", engine)
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path / "local"))
    assert main(["--data-root", "%LOCALAPPDATA%/SocialEngine"]) == 0
    assert (tmp_path / "local" / "SocialEngine" / "remotion_work" / "package.json").exists()
    assert main(["--data-root", str(tmp_path / "OneDrive" / "x")]) == 1
    assert "OneDrive" in capsys.readouterr().err
