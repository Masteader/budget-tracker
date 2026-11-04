"""Round 2's attacks on capture, and what they led to (spec Sections 5.1 to 5.3). The phone is never
left recording or holding a file without word to the owner, timeouts hold, nothing is written
through a link, and only a signed record can make a clip final. Nothing here touches a phone."""

import json
import subprocess
import sys
import time
from pathlib import Path

import capture_helpers
import pytest
from capture_helpers import SCREENSHOT_BYTES, Answers, FakeAdb, build_config, build_gate_met_config
from conftest import make_junction
from test_ingest import drop, ffmpeg, ingest, manifest_of, signed_answers  # noqa: F401

from core.manifest import ClipEntry, ClipManifest, ClipRejected, sha256_file
from core.paths import EnginePaths
from phone_capture import adb as adb_module
from phone_capture import capture_cli, process_tree
from phone_capture import ingest as ingest_module
from phone_capture.adb import AdbClient, AdbCommandFailed, Device, ScreenshotFailed
from phone_capture.capture_cli import run_capture, run_screenshot
from phone_capture.ingest import (
    CHECKLIST,
    CaptureError,
    Checklist,
    ChecklistConfirmation,
    OwnerAnswers,
    check_clip_for_reel,
    is_sealed_final,
    record_clip,
    record_screenshot,
    screenshot_manifest_path,
    strip_metadata,
)

LINES_BEFORE_DEMO = len(CHECKLIST) - 1
PKILL = "shell pkill -INT screenrecord"
REMOTE = "/sdcard/social_engine_tmp.mp4"


@pytest.fixture(autouse=True)
def no_waiting(monkeypatch):
    monkeypatch.setattr(capture_cli, "COUNTDOWN_SECONDS", 1)
    monkeypatch.setattr(capture_cli, "START_GRACE_SECONDS", 0)
    monkeypatch.setattr(capture_cli, "SETTLE_SECONDS", 0)
    monkeypatch.setattr(capture_cli, "STOP_WAIT_SECONDS", 2)


@pytest.fixture
def fake(tmp_path):
    return FakeAdb(tmp_path / "platform_tools")


@pytest.fixture
def data_root(tmp_path):
    return tmp_path / "data"


@pytest.fixture
def paths(data_root):
    built = EnginePaths.from_root(data_root)
    built.ensure_dirs()
    return built


@pytest.fixture
def config(data_root, fake):
    return build_config(data_root, fake.path)


@pytest.fixture
def recordings(monkeypatch):
    held = []
    real = Device.start_recording

    def wrapped(self, remote):
        recording = real(self, remote)
        held.append(recording)
        return recording

    monkeypatch.setattr(Device, "start_recording", wrapped)
    return held


def run(config, answers, lines=None, sleep=lambda seconds: None):
    return run_capture(
        config,
        "payday_cycle",
        ask=answers,
        out=(lines if lines is not None else []).append,
        sleep=sleep,
    )


def to_recording(*then):
    return Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", *then)


def adb_dies(recordings):
    process = recordings[-1]._process
    process.kill()
    process.wait()


def confirmed(feature="payday_cycle"):
    checklist = Checklist(feature)
    checklist.confirm(CHECKLIST, ask=lambda prompt: "yes")
    return checklist.confirmation()


# --- 10. A recording left running on the phone ----------------------------------------------


def test_ctrl_c_that_also_ended_adb_still_stops_screenrecord(fake, config, recordings):
    """A console Ctrl+C goes to every process in the console, and adb runs in the same group. The
    spec's reason for a second adb call is that this may not stop the phone."""

    def ctrl_c():
        adb_dies(recordings)
        raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        run(config, to_recording(ctrl_c))
    assert PKILL in fake.commands


def test_adb_lost_mid_recording_still_tries_to_stop_screenrecord(fake, config, recordings):
    def enter_after_adb_died():
        adb_dies(recordings)
        return ""

    with pytest.raises(adb_module.RecordingFailed):
        run(config, to_recording(enter_after_adb_died))
    assert fake.commands.count(PKILL) == 1


def test_adb_failing_mid_recording_says_why_and_saves_nothing(fake, config, paths, recordings):
    """Mutation C51: without this check the failure went on to a pull of an unfinished file."""
    fake.configure(fail=[{"match": "screenrecord", "stderr": "device offline"}])

    def enter_after_adb_failed():
        recordings[-1]._process.wait(timeout=20)
        return ""

    with pytest.raises(adb_module.RecordingFailed, match="device offline"):
        run(config, to_recording(enter_after_adb_failed))
    assert not any(command.startswith("pull") for command in fake.commands)
    assert ClipManifest.load(paths.manifest).clips == []


def test_a_failed_stop_signal_is_retried_and_reported(fake, config, recordings):
    fake.configure(fail=[{"match": "pkill"}], recording_runs_for=4)
    lines = []
    with pytest.raises(adb_module.RecordingFailed, match="did not stop") as caught:
        run(config, to_recording(""), lines)
    assert fake.commands.count(PKILL) == adb_module.STOP_SIGNAL_ATTEMPTS
    assert "may still be running" in str(caught.value)
    assert "pkill" in str(caught.value)


def test_a_stop_signal_that_works_the_second_time_is_enough(fake, config):
    fake.configure(fail=[{"match": "pkill", "times": 1}])
    assert run(config, to_recording("", "yes")).signed
    assert fake.commands.count(PKILL) == 2


def test_a_signal_that_never_arrives_and_a_lost_adb_are_reported_as_such(
    fake, config, monkeypatch
):
    fake.configure(fail=[{"match": "pkill"}])
    real_wait = process_tree.wait_for

    def adb_dies_during_the_wait(process, seconds):
        if seconds == capture_cli.STOP_WAIT_SECONDS:
            process.kill()
            process.wait()
        return real_wait(process, seconds)

    monkeypatch.setattr(process_tree, "wait_for", adb_dies_during_the_wait)
    with pytest.raises(adb_module.RecordingFailed, match="lost the phone") as caught:
        run(config, to_recording(""))
    assert "may still be running" in str(caught.value)


def test_ctrl_c_with_a_failed_stop_signal_tells_the_owner(fake, config, recordings):
    fake.configure(fail=[{"match": "pkill"}])
    lines = []
    with pytest.raises(KeyboardInterrupt):
        run(config, to_recording(KeyboardInterrupt), lines)
    assert any("may still be running" in line for line in lines), lines
    assert not fake.demo_is_on


def test_ctrl_c_during_the_stop_still_ends_adb_and_warns(fake, config, recordings, monkeypatch):
    real_shell = Device.shell

    def interrupted_shell(self, *args):
        if args[0] == "pkill":
            raise KeyboardInterrupt
        return real_shell(self, *args)

    monkeypatch.setattr(Device, "shell", interrupted_shell)
    lines = []
    with pytest.raises(KeyboardInterrupt):
        run(config, to_recording(""), lines)
    assert recordings[-1]._process.poll() is not None
    assert any("may still be running" in line for line in lines), lines
    assert not fake.demo_is_on


def test_a_recorder_that_ended_cleanly_needs_no_stop_signal(fake, config, recordings):
    fake.configure(recording_runs_for=0.05)

    def enter_after_it_ended():
        recordings[-1]._process.wait(timeout=20)
        return ""

    assert run(config, to_recording(enter_after_it_ended, "yes")).signed
    assert PKILL not in fake.commands


def test_a_second_stop_does_nothing(fake, config, recordings):
    run(config, to_recording("", "yes"))
    commands = list(fake.commands)
    recordings[-1].stop(1)
    assert recordings[-1].abort(1) is None
    assert fake.commands == commands


# --- 10. A file left on the phone without word to the owner ---------------------------------


def test_a_failed_discard_tells_the_owner(fake, config, recordings):
    def usb_drops():
        fake.recording_on_phone.parent.mkdir(exist_ok=True)
        fake.recording_on_phone.write_bytes(b"x")
        fake.configure(fail=[{"match": "rm -f"}, {"match": "pkill"}])
        adb_dies(recordings)
        return ""

    lines = []
    with pytest.raises(adb_module.RecordingFailed):
        run(config, to_recording(usb_drops), lines)
    assert fake.recording_on_phone.exists()
    assert any(REMOTE in line and "still on the phone" in line for line in lines), lines


def test_ctrl_c_in_a_failed_discard_tells_the_owner_and_demo_mode_is_off(
    fake, config, recordings, monkeypatch
):
    real_remove = Device.remove

    def interrupted_remove(self, remote):
        if interrupted_remove.calls:
            raise KeyboardInterrupt
        interrupted_remove.calls += 1
        return real_remove(self, remote)

    interrupted_remove.calls = 0
    monkeypatch.setattr(Device, "remove", interrupted_remove)
    lines = []
    with pytest.raises(ValueError):
        run(config, to_recording(_raises_value_error), lines)
    assert any(REMOTE in line for line in lines), lines
    assert not fake.demo_is_on


def _raises_value_error():
    raise ValueError("something else went wrong")


def test_ctrl_c_in_the_pull_tells_the_owner_the_file_is_still_on_the_phone(
    fake, config, monkeypatch
):
    real = AdbClient.run_checked

    def run_checked(self, args, timeout):
        if "pull" in args:
            raise KeyboardInterrupt
        return real(self, args, timeout)

    monkeypatch.setattr(AdbClient, "run_checked", run_checked)
    lines = []
    with pytest.raises(KeyboardInterrupt):
        run(config, to_recording(""), lines)
    assert fake.recording_on_phone.exists()
    assert any(REMOTE in line and "still on the phone" in line for line in lines), lines
    assert not fake.demo_is_on


def test_a_failed_pull_says_it_once(fake, config):
    fake.configure(fail=[{"match": "pull"}])
    lines = []
    with pytest.raises(adb_module.PullFailed, match="still on the phone"):
        run(config, to_recording(""), lines)
    assert not any("still on the phone" in line for line in lines)


def test_a_broken_manifest_after_the_recording_says_the_file_is_on_the_phone(
    fake, config, paths
):
    def manifest_breaks():
        paths.manifest.write_text("{not json", encoding="utf-8")
        return ""

    lines = []
    with pytest.raises(ValueError):
        run(config, to_recording(manifest_breaks), lines)
    assert fake.recording_on_phone.exists()
    assert any(REMOTE in line for line in lines), lines


# --- 11. Timeouts hold ----------------------------------------------------------------------


def _adb_with_a_child(tmp_path, monkeypatch, beat: Path, *, then_exit: bool = False) -> FakeAdb:
    """A fake adb with a child that writes a heartbeat and keeps the inherited output open."""
    fixtures = tmp_path / "fixtures"
    fixtures.mkdir()
    child = (
        "import pathlib, time\n"
        f"beat = pathlib.Path({str(beat)!r})\n"
        "for _ in range(600):  # a failed test leaves no process behind for long\n"
        "    with beat.open('a') as handle:\n"
        "        handle.write('x')\n"
        "    time.sleep(0.05)\n"
    )
    (fixtures / "fake_adb.py").write_text(
        "import pathlib, subprocess, sys, time\n"
        f"child = {child!r}\n"
        "subprocess.Popen([sys.executable, '-I', '-S', '-c', child],"
        " stdout=sys.stdout, stderr=sys.stderr)\n"
        f"beat = pathlib.Path({str(beat)!r})\n"
        "while not beat.exists():\n"
        "    time.sleep(0.01)\n"
        "print('List of devices attached')\n"
        "sys.stdout.flush()\n"
        + ("" if then_exit else "time.sleep(25)\n"),
        encoding="utf-8",
    )
    monkeypatch.setattr(capture_helpers, "FIXTURES", fixtures)
    return FakeAdb(tmp_path / "tools")


def _stops_growing(beat: Path) -> bool:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        before = beat.stat().st_size
        time.sleep(0.4)
        if beat.stat().st_size == before:
            return True
    return False


def test_the_ffmpeg_timeout_holds_when_npx_has_a_child(tmp_path, monkeypatch, paths, config):
    """npx.cmd -> cmd.exe -> node -> ffmpeg: killing only cmd.exe left the caller waiting."""
    beat = tmp_path / "beat"
    npx = tmp_path / "bin" / "npx.cmd"
    npx.parent.mkdir()
    code = (
        f"import pathlib, time; b = pathlib.Path(r'{beat}'); "
        "[(b.open('a').write('x'), time.sleep(0.05)) for _ in range(500)]"
    )
    npx.write_text(f'@"{sys.executable}" -I -S -c "{code}"\r\n', encoding="ascii")
    monkeypatch.setattr(ingest_module, "find_on_path", lambda name: npx)
    monkeypatch.setattr(ingest_module, "FFMPEG_TIMEOUT_SECONDS", 5)
    paths.remotion_work.mkdir(parents=True, exist_ok=True)
    source = paths.remotion_work / "s.mp4"
    source.write_bytes(b"x")
    started = time.monotonic()
    with pytest.raises(CaptureError):
        strip_metadata(source, paths.remotion_work / "o.mp4", config, paths)
    assert time.monotonic() - started < 15
    assert beat.exists() and _stops_growing(beat), "the child outlived the timeout"


def test_the_adb_timeout_holds_and_ends_the_child(tmp_path, monkeypatch):
    beat = tmp_path / "beat"
    built = _adb_with_a_child(tmp_path, monkeypatch, beat)
    started = time.monotonic()
    with pytest.raises(AdbCommandFailed, match="took over"):
        AdbClient(built.path).run(["devices"], 5)
    assert time.monotonic() - started < 15
    assert beat.exists() and _stops_growing(beat), "the child outlived the timeout"


def test_a_child_left_behind_does_not_hold_up_a_finished_adb(tmp_path, monkeypatch):
    """What a daemon started by `adb devices` does. adb is done, so its answer counts."""
    beat = tmp_path / "beat"
    built = _adb_with_a_child(tmp_path, monkeypatch, beat, then_exit=True)
    started = time.monotonic()
    result = AdbClient(built.path).run(["devices"], 20)
    assert time.monotonic() - started < 15
    assert result.returncode == 0
    assert "List of devices attached" in result.stdout


def test_the_screenshot_timeout_holds_and_leaves_no_file(tmp_path, fake, monkeypatch):
    monkeypatch.setattr(adb_module, "COMMAND_TIMEOUT_SECONDS", 1)
    device = AdbClient(fake.path).require_one_device()
    monkeypatch.setattr(
        Device, "_with_serial", lambda self, *args: ["shell", "screenrecord", REMOTE]
    )
    part = tmp_path / "screen.png.part"
    started = time.monotonic()
    with pytest.raises(ScreenshotFailed, match="seconds"):
        device.screenshot(part)
    assert time.monotonic() - started < 15
    assert not part.exists()


def test_a_killed_recording_ends_its_tree(tmp_path, monkeypatch):
    beat = tmp_path / "beat"
    built = _adb_with_a_child(tmp_path, monkeypatch, beat)
    device = Device(AdbClient(built.path), "FAKE0001")
    monkeypatch.setattr(Device, "shell", lambda self, *args: None)  # the signal changes nothing
    recording = device.start_recording(REMOTE)
    deadline = time.monotonic() + 15
    while not beat.exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    with pytest.raises(adb_module.RecordingFailed, match="did not stop"):
        recording.stop(0.1)
    assert _stops_growing(beat), "the child outlived the kill"


@pytest.mark.parametrize("seconds", [0, 0.05])
def test_wait_for_times_out_on_a_running_process(tmp_path, seconds):
    process = subprocess.Popen(
        [sys.executable, "-I", "-S", "-c", "import time; time.sleep(25)"],
        stdin=subprocess.DEVNULL,
    )
    try:
        with pytest.raises(subprocess.TimeoutExpired):
            process_tree.wait_for(process, seconds)
    finally:
        process_tree.kill_tree(process)
    assert process.poll() is not None


def test_kill_tree_does_not_look_up_a_process_that_has_exited(monkeypatch):
    process = subprocess.Popen([sys.executable, "-I", "-S", "-c", "pass"], stdin=subprocess.DEVNULL)
    process.wait(timeout=30)
    seen = []
    monkeypatch.setattr(process_tree.subprocess, "run", lambda *a, **k: seen.append(a))
    process_tree.kill_tree(process)
    assert seen == []


# --- 15. No tool can read the owner's terminal ----------------------------------------------


def test_every_adb_call_has_its_input_closed(fake, config, monkeypatch):
    """Mutation C48. Every answer here is a sign-off, so nothing else may read standard input."""
    real_popen = subprocess.Popen
    seen = []

    def spying_popen(args, **kwargs):
        seen.append((args, kwargs.get("stdin")))
        return real_popen(args, **kwargs)

    monkeypatch.setattr(process_tree.subprocess, "Popen", spying_popen)
    run(config, to_recording("", "yes"))
    run_screenshot(
        config,
        "payday_cycle",
        ask=Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", "yes"),
        out=lambda text: None,
    )
    assert any("screenrecord" in args for args, _ in seen)
    assert any("screencap" in args for args, _ in seen)
    assert all(stdin == subprocess.DEVNULL for _, stdin in seen)


def test_ffmpeg_has_its_input_closed(tmp_path, monkeypatch, paths, config):
    real_popen = subprocess.Popen
    seen = []

    def spying_popen(args, **kwargs):
        seen.append(kwargs.get("stdin"))
        return real_popen(args, **kwargs)

    tool = tmp_path / "ffmpeg.exe"
    tool.write_bytes(FakeAdb(tmp_path / "exe").path.read_bytes())
    monkeypatch.setattr(process_tree.subprocess, "Popen", spying_popen)
    forged = config.model_copy(
        update={"render": config.render.model_copy(update={"ffmpeg_path": str(tool)})}
    )
    source = tmp_path / "s.mp4"
    source.write_bytes(b"x")
    with pytest.raises(CaptureError):
        strip_metadata(source, tmp_path / "o.mp4", forged, paths)
    assert seen == [subprocess.DEVNULL]


# --- 15. The short wait after the stop signal -----------------------------------------------


def test_it_settles_after_the_stop_and_before_the_pull(fake, config, monkeypatch):
    """Mutation C45: spec Section 5.1 asks for a short wait after the signal."""
    monkeypatch.setattr(capture_cli, "SETTLE_SECONDS", 7)
    settled_at = []

    def sleep(seconds):
        if seconds == 7:
            settled_at.append(list(fake.commands))

    run(config, to_recording("", "yes"), sleep=sleep)
    assert len(settled_at) == 1
    assert PKILL in settled_at[0]
    assert not any(command.startswith("pull") for command in settled_at[0])
    assert any(command.startswith("pull") for command in fake.commands)


# --- 12. Nothing is written through a link --------------------------------------------------


@pytest.mark.parametrize("name", ["ingest_originals", "ingest_tmp"])
def test_a_junction_at_an_ingest_folder_is_refused_before_any_question(
    ffmpeg, config, paths, tmp_path, name  # noqa: F811
):
    outside = tmp_path / "OneDrive_or_git"
    outside.mkdir()
    make_junction(paths.manifest.parent / name, outside)
    source = drop(paths, "payday_cycle")
    with pytest.raises(CaptureError, match="link"):
        ingest(config, Answers())
    assert list(outside.rglob("*")) == []
    assert ffmpeg.calls == []
    assert source.exists()


def test_a_junction_at_a_feature_of_the_originals_is_refused(
    ffmpeg, config, paths, tmp_path  # noqa: F811
):
    outside = tmp_path / "OneDrive_or_git"
    outside.mkdir()
    (paths.manifest.parent / "ingest_originals").mkdir()
    make_junction(paths.manifest.parent / "ingest_originals" / "payday_cycle", outside)
    drop(paths, "payday_cycle")
    with pytest.raises(CaptureError, match="link"):
        ingest(config, Answers())
    assert list(outside.rglob("*")) == []


def test_a_junction_that_appears_after_the_sign_off_receives_nothing(
    ffmpeg, config, paths, tmp_path  # noqa: F811
):
    outside = tmp_path / "OneDrive_or_git"
    outside.mkdir()
    source = drop(paths, "payday_cycle")
    answers = signed_answers()

    def plant_it():
        originals = paths.manifest.parent / "ingest_originals"
        (originals / "payday_cycle").rmdir()
        make_junction(originals / "payday_cycle", outside)
        return "1.4.2"

    answers.replies[-1] = plant_it
    lines = []
    report = ingest(config, answers, lines=lines)
    assert report.signed == ["payday_cycle/clip_01.mp4"]
    assert list(outside.rglob("*")) == []
    assert source.exists()
    assert any("could not be moved" in line for line in lines)


@pytest.mark.parametrize("level", ["assets", "raw_recordings"])
def test_a_link_above_the_feature_folders_has_nothing_made_through_it(
    fake, config, data_root, tmp_path, level
):
    outside = tmp_path / "outside"
    outside.mkdir()
    data_root.mkdir()
    target = data_root / "assets"
    if level == "raw_recordings":
        target.mkdir()
        target = target / "raw_recordings"
    make_junction(target, outside)
    with pytest.raises(CaptureError, match="link"):
        run(config, Answers())
    assert list(outside.iterdir()) == []
    assert fake.calls == []


def test_a_file_that_is_a_link_is_named_and_skipped(ffmpeg, config, paths, tmp_path):  # noqa: F811
    """Mutation C14. A junction needs no developer mode, unlike a symlink, and this name makes it
    look like a recording."""
    outside = tmp_path / "outside"
    outside.mkdir()
    make_junction(paths.raw_recordings / "payday_cycle" / "x.mp4", outside)
    lines = []
    assert ingest(config, Answers(), lines=lines).signed == []
    assert any("x.mp4" in line and "link" in line for line in lines), lines
    assert ffmpeg.calls == []


# --- 15. The guards for cmd.exe -------------------------------------------------------------


@pytest.mark.parametrize("name", ["a&b.mp4", "a b.mp4", "a%PATH%.mp4", "a^b.mp4", "a(1).mp4"])
def test_a_path_cmd_could_misread_never_reaches_the_command(
    ffmpeg, config, paths, name  # noqa: F811
):
    """Mutation C15: strip_metadata's own guard, for any caller other than `run_ingest`."""
    source = paths.remotion_work / name
    source.write_bytes(b"x")
    with pytest.raises(CaptureError, match="unsafe path"):
        strip_metadata(source, paths.remotion_work / "o.mp4", config, paths)
    with pytest.raises(CaptureError, match="unsafe path"):
        strip_metadata(paths.remotion_work / "s.mp4", paths.remotion_work / name, config, paths)
    assert ffmpeg.calls == []


@pytest.mark.parametrize("folder", ["a&b", "a%b", "a^b", "a!b", "a|b", "a<b", "a>b", 'a"b'])
def test_npx_in_a_folder_cmd_could_misread_is_refused(
    ffmpeg, config, paths, monkeypatch, folder  # noqa: F811
):
    """Mutation C16."""
    monkeypatch.setattr(ingest_module, "find_on_path", lambda name: Path(f"C:/{folder}/{name}"))
    with pytest.raises(CaptureError, match="cmd.exe"):
        strip_metadata(paths.remotion_work / "s.mp4", paths.remotion_work / "o.mp4", config, paths)
    assert ffmpeg.calls == []


# --- 15. Every line of the checklist --------------------------------------------------------


@pytest.mark.parametrize("record", [record_clip, record_screenshot])
def test_a_confirmation_that_skips_a_line_does_not_count(config, paths, record):
    """Mutation C18. The class is public, so a caller could build one by hand."""
    folder = paths.raw_recordings if record is record_clip else paths.screenshots
    name = "clip_01.mp4" if record is record_clip else "screen_01.png"
    file = folder / "payday_cycle" / name
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(SCREENSHOT_BYTES)
    partial = ChecklistConfirmation("payday_cycle", CHECKLIST[:-1])
    with pytest.raises(ClipRejected, match="checklist"):
        record(
            paths,
            file,
            sha256=sha256_file(file),
            confirmation=partial,
            answers=OwnerAnswers(privacy_clean=True),
            app_version="1.4.2",
            config=config,
            final=False,
        )


# --- 15. Rollback and the cleaned copy's hash -----------------------------------------------


def test_a_refused_signature_takes_the_clip_back_out_of_the_folder(
    ffmpeg, config, paths, monkeypatch  # noqa: F811
):
    """Mutation C23: an unsigned file must not sit under a clip name."""

    def refused(*args, **kwargs):
        raise ClipRejected("refused at the last step")

    monkeypatch.setattr(ingest_module, "record_clip", refused)
    source = drop(paths, "payday_cycle")
    report = ingest(config, signed_answers())
    assert report.signed == []
    assert list(report.failed) == ["payday_cycle/Screen_Recording.mp4"]
    folder = paths.raw_recordings / "payday_cycle"
    assert [file.name for file in folder.iterdir()] == [source.name]
    assert source.exists()
    temp = paths.manifest.parent / "ingest_tmp"
    assert list(temp.iterdir()) == []


def test_a_cleaned_copy_changed_after_the_owner_watched_it_never_reaches_the_folder(
    ffmpeg, config, paths, monkeypatch  # noqa: F811
):
    """Mutation C22: refused before it moves, rather than rolled back after."""

    def must_not_be_reached(*args, **kwargs):
        raise AssertionError("record_clip was reached")

    monkeypatch.setattr(ingest_module, "record_clip", must_not_be_reached)
    drop(paths, "payday_cycle")
    answers = signed_answers()
    temp = paths.manifest.parent / "ingest_tmp"

    def swap_the_cleaned_copy():
        next(temp.rglob("output.mp4")).write_bytes(b"something else entirely")
        return "yes"

    answers.replies[len(CHECKLIST)] = swap_the_cleaned_copy
    report = ingest(config, answers)
    assert "does not match" in next(iter(report.failed.values()))


# --- 13. Names that differ only by case -----------------------------------------------------


@pytest.mark.parametrize("name", ["CLIP_01.MP4", "Clip_01.mp4", "clip_01.MP4", "FINAL_CLIP_01.MP4"])
def test_a_file_named_in_capitals_can_be_ingested_without_overwriting(
    ffmpeg, config, paths, name  # noqa: F811
):
    drop(paths, "payday_cycle", name)
    report = ingest(config, signed_answers())
    assert report.failed == {}
    assert report.signed == ["payday_cycle/clip_02.mp4"]
    kept = paths.manifest.parent / "ingest_originals" / "payday_cycle" / name
    assert kept.is_file()


def test_a_screenshot_number_held_in_capitals_is_not_used_again(fake, config, paths):
    (paths.screenshots / "payday_cycle").mkdir(parents=True)
    (paths.screenshots / "payday_cycle" / "SCREEN_04.PNG").write_bytes(b"x")
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", "yes")
    result = run_screenshot(config, "payday_cycle", ask=answers, out=lambda text: None)
    assert result.file.name == "screen_05.png"


def test_a_signed_clip_renamed_in_capitals_is_not_ingested_again(
    ffmpeg, config, paths  # noqa: F811
):
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    folder = paths.raw_recordings / "payday_cycle"
    (folder / "clip_01.mp4").rename(folder / "CLIP_01.MP4")
    ffmpeg.calls.clear()
    assert ingest(config, Answers()).signed == []
    assert ffmpeg.calls == []
    assert (folder / "CLIP_01.MP4").exists()


def test_a_dropped_final_name_does_not_make_a_final_clip(ffmpeg, config, paths):  # noqa: F811
    drop(paths, "payday_cycle", "final_clip_07.mp4")
    report = ingest(config, signed_answers())
    assert report.signed == ["payday_cycle/clip_08.mp4"]
    assert manifest_of(paths).clips[0].final_seal is None


# --- 14. Only the signed record makes a clip final ------------------------------------------


def rewrite_manifest(manifest: Path, **changes) -> None:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["clips"][0].update(changes)
    manifest.write_text(json.dumps(data), encoding="utf-8")


def rename_to_final(paths) -> ClipEntry:
    folder = paths.raw_recordings / "payday_cycle"
    (folder / "clip_01.mp4").rename(folder / "final_clip_01.mp4")
    rewrite_manifest(paths.manifest, path="payday_cycle/final_clip_01.mp4")
    return ClipManifest.load(paths.manifest).verified_clip(
        "payday_cycle/final_clip_01.mp4", paths.raw_recordings
    )


def test_a_test_clip_renamed_with_its_manifest_line_is_not_final(
    ffmpeg, config, paths  # noqa: F811
):
    drop(paths, "payday_cycle")
    assert ingest(config, signed_answers()).signed == ["payday_cycle/clip_01.mp4"]
    entry = rename_to_final(paths)
    assert not is_sealed_final(entry, paths)
    with pytest.raises(ClipRejected, match="test clip"):
        check_clip_for_reel(entry, paths, test_reel=False)


def test_a_seal_written_in_by_hand_does_not_make_a_clip_final(ffmpeg, config, paths):  # noqa: F811
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    rename_to_final(paths)
    rewrite_manifest(paths.manifest, final_seal="0" * 64)
    entry = manifest_of(paths).clips[0]
    with pytest.raises(ClipRejected, match="test clip"):
        check_clip_for_reel(entry, paths, test_reel=False)


@pytest.fixture
def gate_met(ffmpeg, data_root, paths, tmp_path, monkeypatch):  # noqa: F811
    config = build_gate_met_config(monkeypatch, tmp_path, data_root)
    drop(paths, "payday_cycle")
    assert ingest(config, signed_answers(), final=True).signed == ["payday_cycle/final_clip_01.mp4"]
    return config


def test_a_final_clip_carries_a_seal_that_passes(gate_met, paths):
    entry = manifest_of(paths).clips[0]
    assert entry.final_seal is not None
    assert is_sealed_final(entry, paths)
    check_clip_for_reel(entry, paths, test_reel=False)


@pytest.mark.parametrize(
    "edit",
    [
        {"app_version": "9.9.9"},
        {"sha256": "0" * 64},
        {"path": "payday_cycle/final_clip_02.mp4"},
        {"path": "app_experience/final_clip_01.mp4"},
    ],
)
def test_a_seal_does_not_survive_an_edit_to_what_it_covers(gate_met, paths, edit):
    """A seal copied onto another clip, or kept through an edit, is worth nothing."""
    rewrite_manifest(paths.manifest, **edit)
    assert not is_sealed_final(manifest_of(paths).clips[0], paths)


def _lose_key(paths):
    (paths.state_db.parent / "clip_seal.key").unlink()


def _break_key(paths):
    (paths.state_db.parent / "clip_seal.key").write_bytes(b"short")


@pytest.mark.parametrize("damage", [_lose_key, _break_key], ids=["lost", "too_short"])
def test_with_no_good_key_every_clip_is_a_test_clip(gate_met, paths, damage):
    damage(paths)
    assert not is_sealed_final(manifest_of(paths).clips[0], paths)


def test_a_key_behind_a_link_is_not_trusted(gate_met, paths, tmp_path):
    state = paths.state_db.parent
    moved = tmp_path / "moved_state"
    state.rename(moved)
    make_junction(state, moved)
    assert not is_sealed_final(manifest_of(paths).clips[0], paths)


def test_no_seal_can_be_made_through_a_link(ffmpeg, data_root, paths, tmp_path, monkeypatch):  # noqa: F811
    config = build_gate_met_config(monkeypatch, tmp_path, data_root)
    state = paths.state_db.parent
    state.rmdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    make_junction(state, outside)
    drop(paths, "payday_cycle")
    report = ingest(config, signed_answers(), final=True)
    assert report.signed == []
    assert list(outside.iterdir()) == []
    assert manifest_of(paths).clips == []


def test_a_key_that_is_kept_seals_later_clips_with_the_same_key(gate_met, paths):  # noqa: F811
    key = (paths.state_db.parent / "clip_seal.key").read_bytes()
    drop(paths, "payday_cycle")
    assert ingest(gate_met, signed_answers(), final=True).signed == [
        "payday_cycle/final_clip_02.mp4"
    ]
    assert (paths.state_db.parent / "clip_seal.key").read_bytes() == key
    assert all(is_sealed_final(entry, paths) for entry in manifest_of(paths).clips)


def test_the_key_is_kept_away_from_the_manifest_and_the_recordings(gate_met, paths):
    key = paths.state_db.parent / "clip_seal.key"
    assert key.is_file()
    assert key.parent not in (paths.manifest.parent, paths.raw_recordings, paths.screenshots)
    assert key.read_bytes().hex() not in paths.manifest.read_text(encoding="utf-8")


def test_a_test_clip_makes_no_key(ffmpeg, config, paths):  # noqa: F811
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    assert not (paths.state_db.parent / "clip_seal.key").exists()


# --- 15. A screenshot gets what a clip gets -------------------------------------------------


def shoot(config, *then, **kwargs):
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", *then)
    return run_screenshot(config, "payday_cycle", ask=answers, out=lambda text: None, **kwargs)


def test_a_final_picture_is_sealed_and_a_test_picture_is_not(
    fake, data_root, paths, tmp_path, monkeypatch
):
    config = build_gate_met_config(monkeypatch, tmp_path, data_root, fake.path)
    shoot(config, "yes", final=True)
    shoot(config, "yes")
    final, test = ClipManifest.load(screenshot_manifest_path(paths)).clips
    assert (final.path, test.path) == (
        "payday_cycle/final_screen_01.png",
        "payday_cycle/screen_02.png",
    )
    check_clip_for_reel(final, paths, test_reel=False)
    with pytest.raises(ClipRejected, match="test clip"):
        check_clip_for_reel(test, paths, test_reel=False)


def test_a_test_picture_renamed_with_its_manifest_line_is_not_final(fake, config, paths):
    result = shoot(config, "yes")
    final_name = result.file.with_name("final_screen_01.png")
    result.file.rename(final_name)
    manifest = screenshot_manifest_path(paths)
    rewrite_manifest(manifest, path="payday_cycle/final_screen_01.png")
    entry = ClipManifest.load(manifest).verified_clip(
        "payday_cycle/final_screen_01.png", paths.screenshots
    )
    with pytest.raises(ClipRejected, match="test clip"):
        check_clip_for_reel(entry, paths, test_reel=False)


def test_a_picture_changed_after_the_owner_looked_at_it_is_not_signed(fake, config, paths):
    def swap_the_picture():
        (paths.screenshots / "payday_cycle" / "screen_01.png").write_bytes(b"other bytes")
        return "yes"

    with pytest.raises(ClipRejected, match="signed hash"):
        shoot(config, swap_the_picture)
    assert ClipManifest.load(screenshot_manifest_path(paths)).clips == []
