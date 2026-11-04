"""Phone capture with a fake `adb` executable (spec Section 5.1 to 5.3, task H1).

Nothing here touches a phone. Real phone behaviour is the owner's LIVE-4 step.
"""

import io
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest
import yaml
from capture_helpers import (
    RECORDING_BYTES,
    Answers,
    FakeAdb,
    build_config,
    build_gate_met_config,
    config_data,
    shipped_data,
)
from conftest import make_junction

from core.brand_gate import is_gate_met
from core.manifest import ClipManifest, sha256_file
from core.paths import ENGINE_ROOT, EnginePaths, PathConfigError
from core.secrets import FORBIDDEN_ENV_PREFIX
from phone_capture import adb as adb_module
from phone_capture import capture_cli
from phone_capture.adb import (
    AdbClient,
    AdbCommandFailed,
    AdbNotFound,
    DeviceNotReady,
    MultipleDevices,
    NoDevice,
    PullFailed,
    RecordingFailed,
    UnauthorizedDevice,
    UnsafeAdbArgument,
    find_adb,
)
from phone_capture.capture_cli import main, run_capture
from phone_capture.ingest import CHECKLIST, STATUS_BAR_LINE, CaptureError, ChecklistRefused

DEMO_ON = [
    "shell settings put global sysui_demo_allowed 1",
    "shell am broadcast -a com.android.systemui.demo -e command enter",
    "shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941",
    "shell am broadcast -a com.android.systemui.demo -e command battery -e level 100",
    "shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4",
    "shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false",
]
DEMO_OFF = "shell am broadcast -a com.android.systemui.demo -e command exit"
REMOTE = "/sdcard/social_engine_tmp.mp4"
LINES_BEFORE_DEMO = len(CHECKLIST) - 1
MASK = "0.1 0.2 0.5 0.05"


def happy_answers(*after_privacy, privacy="yes", app_version="1.4.2"):
    return Answers(
        *["yes"] * LINES_BEFORE_DEMO,
        app_version,
        "yes",  # the status bar line, once demo mode is on
        "",  # Enter stops the recording
        privacy,
        *after_privacy,
    )


@pytest.fixture(autouse=True)
def no_waiting(monkeypatch):
    monkeypatch.setattr(capture_cli, "COUNTDOWN_SECONDS", 1)
    monkeypatch.setattr(capture_cli, "START_GRACE_SECONDS", 0)
    monkeypatch.setattr(capture_cli, "SETTLE_SECONDS", 0)
    monkeypatch.setattr(capture_cli, "STOP_WAIT_SECONDS", 20)


@pytest.fixture
def fake(tmp_path) -> FakeAdb:
    return FakeAdb(tmp_path / "platform_tools")


@pytest.fixture
def data_root(tmp_path) -> Path:
    return tmp_path / "data"


@pytest.fixture
def paths(data_root) -> EnginePaths:
    return EnginePaths.from_root(data_root)


@pytest.fixture
def config(data_root, fake):
    return build_config(data_root, fake.path)


def capture(config, feature="payday_cycle", answers=None, **kwargs):
    lines = []
    return run_capture(
        config,
        feature,
        ask=answers or happy_answers(),
        out=lines.append,
        sleep=lambda seconds: None,
        **kwargs,
    )


def assert_demo_was_switched_off(fake: FakeAdb) -> None:
    assert DEMO_OFF in fake.commands
    assert not fake.demo_is_on


def assert_nothing_signed(paths: EnginePaths) -> None:
    assert ClipManifest.load(paths.manifest).clips == []


# --- Finding adb ------------------------------------------------------------------------


def test_adb_is_found_in_the_standard_sdk_folder_when_it_is_not_on_path(tmp_path, monkeypatch):
    sdk_tools = tmp_path / "localappdata" / "Android" / "Sdk" / "platform-tools"
    installed = FakeAdb(sdk_tools)
    monkeypatch.setenv("PATH", str(tmp_path / "nothing_here"))
    assert find_adb(shipped_data()["capture"]["adb_path"]) == installed.path


def test_the_standard_folder_is_tried_even_when_the_configured_path_is_stale(tmp_path, monkeypatch):
    sdk_tools = tmp_path / "localappdata" / "Android" / "Sdk" / "platform-tools"
    installed = FakeAdb(sdk_tools)
    monkeypatch.setenv("PATH", "")
    assert find_adb(str(tmp_path / "gone" / "adb.exe")) == installed.path


def test_adb_on_path_is_used_when_the_configured_path_is_missing(tmp_path, monkeypatch):
    on_path = FakeAdb(tmp_path / "on_path")
    monkeypatch.setenv("PATH", str(on_path.folder))
    assert find_adb(str(tmp_path / "gone" / "adb.exe")) == on_path.path


def test_a_configured_path_that_exists_comes_first(tmp_path, monkeypatch):
    configured = FakeAdb(tmp_path / "configured")
    on_path = FakeAdb(tmp_path / "on_path")
    monkeypatch.setenv("PATH", str(on_path.folder))
    assert find_adb(str(configured.path)) == configured.path


def test_no_adb_anywhere_explains_the_manual_fallback(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", "")
    with pytest.raises(AdbNotFound, match="--ingest"):
        find_adb(str(tmp_path / "gone" / "adb.exe"))


def test_an_unset_localappdata_is_a_clear_refusal(tmp_path, monkeypatch):
    monkeypatch.delenv("LOCALAPPDATA")
    monkeypatch.setenv("PATH", "")
    with pytest.raises(AdbNotFound):
        find_adb(shipped_data()["capture"]["adb_path"])


def test_adb_in_the_current_folder_is_not_picked_up(tmp_path, monkeypatch):
    planted = FakeAdb(tmp_path / "planted")
    monkeypatch.chdir(planted.folder)
    monkeypatch.setenv("PATH", ".")
    with pytest.raises(AdbNotFound):
        find_adb(str(tmp_path / "gone" / "adb.exe"))


@pytest.mark.parametrize("name", ["adb.cmd", "adb.bat"])
def test_a_batch_file_is_never_run_as_adb(tmp_path, monkeypatch, name):
    # cmd.exe would read the arguments a second time, which is how shell injection gets in.
    batch = tmp_path / name
    batch.write_text("@echo off\n", encoding="utf-8")
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(AdbNotFound):
        find_adb(str(batch))
    with pytest.raises(AdbNotFound):
        find_adb(str(tmp_path / "gone" / "adb.exe"))


def test_a_relative_configured_path_is_refused(monkeypatch):
    monkeypatch.setenv("PATH", "")
    with pytest.raises(AdbNotFound, match="absolute"):
        find_adb("tools/adb.exe")


# --- Exactly one authorised device ------------------------------------------------------


@pytest.mark.parametrize(
    ("listing", "error", "message"),
    [
        ("List of devices attached\n\n", NoDevice, "No phone"),
        ("* daemon started successfully\nList of devices attached\n", NoDevice, "No phone"),
        ("List of devices attached\nAAA\tunauthorized\n", UnauthorizedDevice, "Allow"),
        ("List of devices attached\nAAA\toffline\n", DeviceNotReady, "offline"),
        ("List of devices attached\nAAA\tno permissions (x)\n", DeviceNotReady, "no perm"),
        ("List of devices attached\nAAA\tdevice\nBBB\tdevice\n", MultipleDevices, "2"),
        ("List of devices attached\nAAA\tdevice\nBBB\tunauthorized\n", MultipleDevices, "2"),
        ("List of devices attached\nAAA\tunauthorized\nBBB\toffline\n", MultipleDevices, "2"),
        ("something else entirely\n", AdbCommandFailed, "could not read"),
    ],
)
def test_capture_is_refused_unless_exactly_one_authorised_device(
    fake, config, paths, listing, error, message
):
    fake.configure(devices=listing)
    answers = Answers()  # any question at all would fail the test
    with pytest.raises(error, match=message):
        capture(config, answers=answers)
    assert fake.commands == ["devices"]
    assert_nothing_signed(paths)


def test_daemon_chatter_around_the_listing_is_ignored(fake):
    fake.configure(devices="* daemon not running\n* started\nList of devices attached\nAAA\tdevice")
    assert AdbClient(fake.path).require_one_device().serial == "AAA"


def test_a_network_serial_is_accepted(fake):
    fake.configure(devices="List of devices attached\n192.168.1.5:5555\tdevice\n")
    assert AdbClient(fake.path).require_one_device().serial == "192.168.1.5:5555"


def test_a_failing_adb_is_reported(fake):
    fake.configure(fail=[{"match": "devices", "stderr": "server broke"}])
    with pytest.raises(AdbCommandFailed, match="server broke"):
        AdbClient(fake.path).require_one_device()


@pytest.mark.parametrize("serial", ["-evil", "abc;reboot", "a$(reboot)", "a&b", "a|b", "../x"])
def test_a_device_with_an_unsafe_serial_is_refused(fake, serial):
    fake.configure(devices=f"List of devices attached\n{serial}\tdevice\n")
    with pytest.raises(UnsafeAdbArgument):
        AdbClient(fake.path).require_one_device()
    assert fake.commands == ["devices"]


def test_every_call_after_the_listing_names_the_serial(fake, config):
    capture(config)
    assert fake.calls[0] == ["devices"]
    assert all(call[:2] == ["-s", "FAKE0001"] for call in fake.calls[1:])


# --- Nothing unsafe reaches the phone's shell or the disk -------------------------------


@pytest.mark.parametrize(
    "argument",
    [
        "a;reboot",
        "a b",
        "$(reboot)",
        "`reboot`",
        "a|b",
        "a&b",
        "a>b",
        "a\nreboot",
        "'a'",
        '"a"',
        "",
        "a\\b",
        "a*",
    ],
)
def test_shell_refuses_any_argument_the_phone_shell_could_read_as_code(fake, argument):
    device = adb_module.Device(AdbClient(fake.path), "FAKE0001")
    with pytest.raises(UnsafeAdbArgument):
        device.shell("echo", argument)
    assert fake.calls == []


@pytest.mark.parametrize(
    "remote",
    [
        "/sdcard/../data/x.mp4",
        "/sdcard/sub/x.mp4",
        "/data/x.mp4",
        "x.mp4",
        "/sdcard/x.mp4;reboot",
        "/sdcard/x y.mp4",
        "/sdcard/-rf.mp4",
        "/sdcard/x.txt",
        "/sdcard/.mp4",
    ],
)
def test_remote_paths_outside_the_allowed_shape_are_refused(fake, tmp_path, remote):
    device = adb_module.Device(AdbClient(fake.path), "FAKE0001")
    for call in (
        lambda: device.remove(remote),
        lambda: device.pull(remote, tmp_path / "x.mp4"),
        lambda: device.start_recording(remote),
    ):
        with pytest.raises(UnsafeAdbArgument):
            call()
    assert fake.calls == []


@pytest.mark.parametrize(
    "feature",
    ["../../evil", "payday_cycle/../../evil", "..", "", "PAYDAY_CYCLE", "payday_cycle;reboot", "x"],
)
def test_a_feature_outside_the_shot_list_is_refused(fake, config, paths, feature):
    with pytest.raises(CaptureError, match="shot list"):
        capture(config, feature=feature, answers=Answers())
    assert fake.calls == []
    assert not (paths.data_root.parent / "evil").exists()


@pytest.mark.parametrize("feature", ["../../evil", "payday_cycle/../../evil", "x"])
def test_the_command_line_refuses_those_features_too(feature, capsys):
    with pytest.raises(SystemExit) as stopped:
        main(["--feature", feature])
    assert stopped.value.code == 2


def test_adb_gets_a_scrubbed_environment(fake, config, monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "not-for-adb")
    monkeypatch.setenv("SOME_NEW_TOKEN", "not-for-adb")
    capture(config)
    for record in fake.records:
        assert not {"TELEGRAM_BOT_TOKEN", "SOME_NEW_TOKEN"} & set(record["env"])


def test_device_text_cannot_write_control_codes_to_the_terminal(fake):
    fake.configure(fail=[{"match": "devices", "stderr": "bad\x1b[2Jthing"}])
    with pytest.raises(AdbCommandFailed) as caught:
        AdbClient(fake.path).require_one_device()
    assert "\x1b" not in str(caught.value)


def test_adb_that_cannot_start_is_a_clear_failure(tmp_path):
    with pytest.raises(AdbCommandFailed):
        AdbClient(tmp_path / "gone.exe").require_one_device()


# --- The checklist ----------------------------------------------------------------------


def test_the_checklist_holds_every_line_of_the_spec():
    spec = (ENGINE_ROOT / "docs" / "SPEC.md").read_text(encoding="utf-8")
    section = spec.split("### 5.3 Pre-capture checklist")[1].split("### 5.4")[0]
    lines = [line[6:] for line in section.splitlines() if line.startswith("- [ ] ")]
    assert list(CHECKLIST) == lines
    assert len(lines) == 10
    assert any("No bank name or logo" in line for line in CHECKLIST)
    assert any("No real merchant or store name" in line for line in CHECKLIST)


def test_each_line_is_asked_on_its_own_before_recording_starts(fake, config):
    answers = happy_answers()
    capture(config, answers=answers)
    asked = answers.prompts
    for line in CHECKLIST:
        assert sum(line in prompt for prompt in asked) == 1, line
    enter_at = next(index for index, prompt in enumerate(asked) if "Enter" in prompt)
    last_line_at = max(i for i, p in enumerate(asked) if any(line in p for line in CHECKLIST))
    assert last_line_at < enter_at


@pytest.mark.parametrize("line_number", range(LINES_BEFORE_DEMO))
def test_refusing_any_line_stops_before_demo_mode_or_recording(fake, config, paths, line_number):
    answers = Answers(*["yes"] * line_number, "no")
    with pytest.raises(ChecklistRefused):
        capture(config, answers=answers)
    assert fake.commands == ["devices"]
    assert not list(paths.raw_recordings.rglob("*.mp4"))
    assert_nothing_signed(paths)


@pytest.mark.parametrize("reply", ["y", "Y", "", "yes please", "no", "1", "true", "نعم"])
def test_only_a_typed_yes_counts(fake, config, reply):
    with pytest.raises(ChecklistRefused):
        capture(config, answers=Answers(reply))
    assert fake.commands == ["devices"]


def test_a_closed_input_counts_as_no(fake, config):
    with pytest.raises(ChecklistRefused):
        capture(config, answers=Answers(EOFError))
    assert fake.commands == ["devices"]


def test_yes_with_spaces_or_capitals_counts(fake, config):
    answers = Answers(*[" YES "] * LINES_BEFORE_DEMO, "1.4.2", "Yes", "", "yes")
    assert capture(config, answers=answers).signed


def test_the_status_bar_line_is_asked_only_once_demo_mode_is_showing(fake, config):
    seen_when_asked = []

    def record_commands():
        seen_when_asked.extend(fake.commands)
        return "yes"

    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", record_commands, "", "yes")
    capture(config, answers=answers)
    assert seen_when_asked[1:] == DEMO_ON
    assert STATUS_BAR_LINE in answers.prompts[LINES_BEFORE_DEMO + 1]


def test_refusing_the_status_bar_line_stops_and_switches_demo_mode_off(fake, config, paths):
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "no")
    with pytest.raises(ChecklistRefused):
        capture(config, answers=answers)
    assert_demo_was_switched_off(fake)
    assert not any("screenrecord" in command for command in fake.commands)
    assert_nothing_signed(paths)


# --- Demo mode --------------------------------------------------------------------------


def test_demo_mode_commands_run_in_the_documented_order_and_exit_comes_last(fake, config):
    capture(config)
    commands = fake.commands
    assert commands[0] == "devices"
    assert commands[1:7] == DEMO_ON
    assert commands.count(DEMO_OFF) == 1
    assert commands.index(DEMO_OFF) > commands.index(f"shell screenrecord {REMOTE}")
    assert not fake.demo_is_on


@pytest.mark.parametrize("failing", DEMO_ON)
def test_exit_runs_when_any_demo_mode_command_fails(fake, config, paths, failing):
    fake.configure(fail=[{"match": failing.removeprefix("shell ")}])
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2")
    with pytest.raises(AdbCommandFailed):
        capture(config, answers=answers)
    assert fake.commands[-1] == DEMO_OFF
    assert not any("screenrecord" in command for command in fake.commands)
    assert_nothing_signed(paths)


def test_exit_runs_when_screenrecord_fails_at_once(fake, config, paths, monkeypatch):
    monkeypatch.setattr(capture_cli, "START_GRACE_SECONDS", 20)
    fake.configure(fail=[{"match": "screenrecord", "stderr": "Unable to get output buffers"}])
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes")
    with pytest.raises(RecordingFailed, match="output buffers"):
        capture(config, answers=answers)
    assert_demo_was_switched_off(fake)
    assert_nothing_signed(paths)


def test_exit_runs_when_the_stop_signal_fails_and_the_stuck_recorder_is_killed(
    fake, config, paths, monkeypatch
):
    monkeypatch.setattr(capture_cli, "STOP_WAIT_SECONDS", 0.5)
    fake.configure(fail=[{"match": "pkill"}])
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", "")
    started = time.monotonic()
    with pytest.raises(RecordingFailed, match="did not stop"):
        capture(config, answers=answers)
    assert time.monotonic() - started < 30
    assert_demo_was_switched_off(fake)
    assert not any(command.startswith("pull") for command in fake.commands)
    assert_nothing_signed(paths)


def test_exit_runs_when_the_pull_fails(fake, config):
    fake.configure(fail=[{"match": "pull"}])
    with pytest.raises(PullFailed):
        capture(config, answers=Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", ""))
    assert_demo_was_switched_off(fake)


# Each index is the question at which Ctrl+C lands, after that many answers.
@pytest.mark.parametrize(
    ("answers_before_ctrl_c", "demo_was_on", "recording_started"),
    [
        (0, False, False),  # first checklist line
        (LINES_BEFORE_DEMO, False, False),  # app version
        (LINES_BEFORE_DEMO + 1, True, False),  # status bar line, demo mode on
        (LINES_BEFORE_DEMO + 2, True, True),  # waiting for Enter, recording
    ],
)
def test_ctrl_c_at_any_question_leaves_demo_mode_off(
    fake, config, paths, answers_before_ctrl_c, demo_was_on, recording_started
):
    script = [*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes"][:answers_before_ctrl_c]
    with pytest.raises(KeyboardInterrupt):
        capture(config, answers=Answers(*script, KeyboardInterrupt))
    assert (DEMO_OFF in fake.commands) == demo_was_on
    assert not fake.demo_is_on
    assert ("shell pkill -INT screenrecord" in fake.commands) == recording_started
    assert not fake.recording_on_phone.exists()
    assert not list(paths.raw_recordings.rglob("*.mp4"))
    assert_nothing_signed(paths)


def test_ctrl_c_stops_the_recording_before_it_switches_demo_mode_off(fake, config):
    script = [*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", KeyboardInterrupt]
    with pytest.raises(KeyboardInterrupt):
        capture(config, answers=Answers(*script))
    commands = fake.commands
    assert commands.index("shell pkill -INT screenrecord") < commands.index(DEMO_OFF)


def test_ctrl_c_during_the_countdown_leaves_demo_mode_off(fake, config):
    def interrupted_sleep(seconds):
        raise KeyboardInterrupt

    script = [*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes"]
    with pytest.raises(KeyboardInterrupt):
        run_capture(
            config,
            "payday_cycle",
            ask=Answers(*script),
            out=lambda text: None,
            sleep=interrupted_sleep,
        )
    assert_demo_was_switched_off(fake)
    assert not any("screenrecord" in command for command in fake.commands)


def test_ctrl_c_while_demo_mode_is_being_switched_off_still_switches_it_off(
    fake, monkeypatch, config
):
    real_run = subprocess.run
    tripped = []

    def run_that_gets_interrupted_once(args, **kwargs):
        if args[-1] == "exit" and not tripped:
            tripped.append(True)
            raise KeyboardInterrupt
        return real_run(args, **kwargs)

    monkeypatch.setattr(adb_module.subprocess, "run", run_that_gets_interrupted_once)
    with pytest.raises(KeyboardInterrupt):
        capture(config)
    assert tripped
    assert_demo_was_switched_off(fake)


def test_exit_is_tried_again_when_the_first_attempt_fails(fake, config):
    fake.configure(fail=[{"match": "-e command exit", "times": 1}])
    result = capture(config)
    assert result.demo_off
    assert fake.commands.count(DEMO_OFF) == 2
    assert not fake.demo_is_on


def test_exit_that_keeps_failing_is_reported_and_names_the_manual_command(fake, config):
    fake.configure(fail=[{"match": "-e command exit"}])
    lines = []
    result = run_capture(
        config, "payday_cycle", ask=happy_answers(), out=lines.append, sleep=lambda s: None
    )
    assert not result.demo_off
    assert fake.commands.count(DEMO_OFF) == capture_cli.DEMO_EXIT_ATTEMPTS
    warning = "\n".join(lines)
    assert "may still be on" in warning
    assert "-e command exit" in warning


def test_a_failed_exit_does_not_hide_the_original_error(fake, config):
    fake.configure(fail=[{"match": "-e command exit"}, {"match": "pull", "stderr": "pull broke"}])
    with pytest.raises(PullFailed, match="pull broke"):
        capture(config, answers=Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", ""))


# --- Recording, stopping, pulling -------------------------------------------------------


def test_recording_runs_the_documented_command(fake, config):
    capture(config)
    assert f"shell screenrecord {REMOTE}" in fake.commands


def test_the_stop_signal_is_a_second_adb_call_while_the_first_is_still_running(fake, config):
    stop_seen_on_phone = []

    def press_enter():
        # The recorder is still running: it writes its file only after the stop signal.
        stop_seen_on_phone.append(fake.recording_on_phone.exists())
        return ""

    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", press_enter, "yes")
    capture(config, answers=answers)
    commands = fake.commands
    assert stop_seen_on_phone == [False]
    assert commands.index(f"shell screenrecord {REMOTE}") < commands.index(
        "shell pkill -INT screenrecord"
    )
    assert commands.index("shell pkill -INT screenrecord") < commands.index(DEMO_OFF)


def test_the_recording_is_pulled_deleted_from_the_phone_and_saved_by_feature(fake, config, paths):
    result = capture(config, feature="zatca_receipt_scan")
    saved = paths.raw_recordings / "zatca_receipt_scan" / "clip_01.mp4"
    assert result.clip == saved
    assert saved.read_bytes() == RECORDING_BYTES
    assert not fake.recording_on_phone.exists()
    commands = fake.commands
    assert commands[-1] == f"shell rm -f {REMOTE}"
    pull = next(command for command in commands if command.startswith("pull"))
    assert commands.index(pull) < len(commands) - 1
    assert [path.name for path in saved.parent.iterdir()] == ["clip_01.mp4"]


def test_a_stale_recording_on_the_phone_is_cleared_before_a_new_one(fake, config):
    capture(config)
    commands = fake.commands
    assert commands.index(f"shell rm -f {REMOTE}") < commands.index(f"shell screenrecord {REMOTE}")


def test_clips_are_numbered_and_never_overwritten(fake, config, paths):
    first = capture(config)
    second = capture(config)
    assert (first.clip.name, second.clip.name) == ("clip_01.mp4", "clip_02.mp4")
    assert first.clip.read_bytes() == RECORDING_BYTES
    assert len(ClipManifest.load(paths.manifest).clips) == 2


def test_a_number_held_only_by_the_manifest_is_not_reused(fake, config, paths):
    first = capture(config)
    first.clip.unlink()
    assert capture(config).clip.name == "clip_02.mp4"


def test_the_recording_ending_by_itself_at_the_time_limit_is_still_saved(fake, config, paths):
    fake.configure(recording_runs_for=0.05)

    def press_enter_late():
        deadline = time.monotonic() + 15
        while not fake.recording_on_phone.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        time.sleep(0.2)
        return ""

    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", press_enter_late, "yes")
    result = capture(config, answers=answers)
    assert result.clip.read_bytes() == RECORDING_BYTES


@pytest.mark.parametrize("scenario", [{"fail": [{"match": "pull"}]}, {"pull_leaves_empty_file": 1}])
def test_a_failed_pull_saves_nothing_and_keeps_the_recording_on_the_phone(
    fake, config, paths, scenario
):
    fake.configure(**scenario)
    with pytest.raises(PullFailed, match=REMOTE):
        capture(config, answers=Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", ""))
    assert fake.recording_on_phone.exists()
    assert not list((paths.raw_recordings / "payday_cycle").iterdir())
    assert_nothing_signed(paths)
    assert fake.commands.count(f"shell rm -f {REMOTE}") == 1  # only the clear before recording


def test_ctrl_c_during_the_pull_leaves_no_part_file(fake, config, paths, monkeypatch):
    real_run = subprocess.run

    def run_interrupted_at_the_pull(args, **kwargs):
        if "pull" in args:
            Path(args[-1]).write_bytes(b"half a file")
            raise KeyboardInterrupt
        return real_run(args, **kwargs)

    monkeypatch.setattr(adb_module.subprocess, "run", run_interrupted_at_the_pull)
    with pytest.raises(KeyboardInterrupt):
        capture(config, answers=Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", ""))
    assert list((paths.raw_recordings / "payday_cycle").iterdir()) == []
    assert_demo_was_switched_off(fake)
    assert_nothing_signed(paths)


def test_a_failed_clear_before_recording_stops_with_demo_mode_off(fake, config):
    fake.configure(fail=[{"match": "rm -f"}])
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes")
    with pytest.raises(AdbCommandFailed):
        capture(config, answers=answers)
    assert_demo_was_switched_off(fake)
    assert not any("screenrecord" in command for command in fake.commands)


def test_a_failed_delete_after_the_pull_keeps_the_clip_and_warns(fake, config, paths):
    fake.configure(fail=[{"match": "rm -f", "skip": 1}])  # the clear before recording works
    lines = []
    result = run_capture(
        config, "payday_cycle", ask=happy_answers(), out=lines.append, sleep=lambda s: None
    )
    assert result.clip.read_bytes() == RECORDING_BYTES
    assert result.signed
    assert fake.recording_on_phone.exists()
    assert any(REMOTE in line and "still on the phone" in line for line in lines)


# --- Where clips live -------------------------------------------------------------------


def test_a_data_root_in_onedrive_is_refused_before_anything_runs(tmp_path, fake):
    config = build_config(tmp_path / "OneDrive" / "data", fake.path)
    with pytest.raises(PathConfigError, match="OneDrive"):
        capture(config, answers=Answers())
    assert fake.calls == []


def test_a_data_root_inside_the_repo_is_refused_before_anything_runs(fake):
    config = build_config(ENGINE_ROOT / "assets" / "data", fake.path)
    with pytest.raises(PathConfigError, match="outside"):
        capture(config, answers=Answers())
    assert fake.calls == []


def test_a_feature_folder_that_is_a_link_is_refused_before_anything_runs(
    fake, config, paths, tmp_path
):
    outside = tmp_path / "outside"
    outside.mkdir()
    (paths.raw_recordings).mkdir(parents=True)
    make_junction(paths.raw_recordings / "payday_cycle", outside)
    with pytest.raises(CaptureError, match="link"):
        capture(config, answers=Answers())
    assert fake.calls == []
    assert list(outside.iterdir()) == []


def test_a_broken_manifest_stops_before_anything_runs(fake, config, paths):
    paths.manifest.parent.mkdir(parents=True)
    paths.manifest.write_text("{not json", encoding="utf-8")
    with pytest.raises(ValueError):
        capture(config, answers=Answers())
    assert fake.calls == []


# --- Sign-off after capture -------------------------------------------------------------


def test_sign_off_adds_the_clip_with_its_hash_and_app_version(fake, config, paths):
    result = capture(config)
    assert result.signed
    entry = ClipManifest.load(paths.manifest).verified_clip(
        "payday_cycle/clip_01.mp4", paths.raw_recordings
    )
    assert entry.privacy_checked is True
    assert entry.sha256 == sha256_file(result.clip)
    assert entry.app_version == "1.4.2"


def test_no_sign_off_leaves_the_file_unusable(fake, config, paths):
    result = capture(config, answers=happy_answers(privacy="no"))
    assert not result.signed
    assert result.clip.exists()
    assert_nothing_signed(paths)


def test_the_app_version_is_refused_when_blank_or_unsafe(fake, config, paths):
    for reply in ("", "  ", "1.0;reboot", "1 0", "\u202e1.0"):
        with pytest.raises(CaptureError, match="app version"):
            capture(config, answers=Answers(*["yes"] * LINES_BEFORE_DEMO, reply))
    assert all(command == "devices" for command in fake.commands)


def test_the_app_version_can_come_from_the_command_line(fake, config, paths):
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "yes", "", "yes")
    capture(config, answers=answers, app_version="2.0.0+7")
    assert ClipManifest.load(paths.manifest).clips[0].app_version == "2.0.0+7"


def test_a_smart_basket_capture_needs_masks_covering_the_store_names(fake, config, paths):
    result = capture(config, "smart_basket", happy_answers(MASK, "", "yes"))
    entry = ClipManifest.load(paths.manifest).clips[0]
    assert result.signed
    assert entry.store_names_masked is True
    assert entry.mask_regions[0].width == 0.5


def test_a_smart_basket_capture_with_no_masks_is_not_signed(fake, config, paths):
    result = capture(config, "smart_basket", happy_answers(""))
    assert not result.signed
    assert_nothing_signed(paths)


def test_a_smart_basket_capture_with_masks_not_confirmed_is_not_signed(fake, config, paths):
    result = capture(config, "smart_basket", happy_answers(MASK, "", "no"))
    assert not result.signed
    assert_nothing_signed(paths)


def test_the_file_being_changed_after_the_owner_watched_it_stops_the_sign_off(fake, config, paths):
    def swap_the_file():
        (paths.raw_recordings / "payday_cycle" / "clip_01.mp4").write_bytes(b"other bytes")
        return "yes"

    answers = happy_answers(privacy=swap_the_file)
    with pytest.raises(capture_cli.ClipRejected, match="signed hash"):
        capture(config, answers=answers)
    assert_nothing_signed(paths)


# --- The launch gate: everything before it is a test clip -------------------------------


def test_clips_while_the_gate_is_closed_are_test_clips(fake, config):
    assert not is_gate_met(config)
    result = capture(config)
    assert result.test_clip
    assert result.clip.name == "clip_01.mp4"


def test_asking_for_a_final_clip_while_the_gate_is_closed_is_refused(fake, config, paths):
    with pytest.raises(CaptureError, match="launch gate"):
        capture(config, answers=Answers(), final=True)
    assert fake.calls == []


def test_the_session_says_it_records_test_clips(fake, config):
    lines = []
    run_capture(config, "payday_cycle", ask=happy_answers(), out=lines.append, sleep=lambda s: 0)
    assert any("test clip" in line.casefold() for line in lines)


def test_a_final_clip_is_possible_once_the_gate_is_met(fake, data_root, tmp_path, monkeypatch):
    config = build_gate_met_config(monkeypatch, tmp_path, data_root, fake.path)
    assert is_gate_met(config)
    result = capture(config, final=True)
    assert not result.test_clip
    assert result.clip.name == "final_clip_01.mp4"


def test_with_the_gate_met_a_clip_is_still_a_test_clip_unless_asked(
    fake, data_root, tmp_path, monkeypatch
):
    config = build_gate_met_config(monkeypatch, tmp_path, data_root, fake.path)
    result = capture(config)
    assert result.test_clip
    assert result.clip.name == "clip_01.mp4"


# --- The command line -------------------------------------------------------------------


@pytest.fixture
def config_file(tmp_path, data_root, fake) -> Path:
    path = tmp_path / "config.yaml"
    path.write_text(
        yaml.safe_dump(config_data(data_root, fake.path), allow_unicode=True), encoding="utf-8"
    )
    return path


class _Terminal:
    def isatty(self) -> bool:
        return True


@pytest.fixture
def at_a_terminal(monkeypatch):
    monkeypatch.setattr(capture_cli.sys, "stdin", _Terminal())
    monkeypatch.setattr(capture_cli.time, "sleep", lambda seconds: None)


def script_input(monkeypatch, answers: Answers) -> None:
    monkeypatch.setattr("builtins.input", answers)


def test_main_runs_a_capture_end_to_end(
    fake, config_file, paths, monkeypatch, at_a_terminal, capsys
):
    script_input(monkeypatch, happy_answers())
    assert main(["--feature", "payday_cycle", "--config", str(config_file)]) == 0
    assert len(ClipManifest.load(paths.manifest).clips) == 1
    assert "clip_01.mp4" in capsys.readouterr().out


def test_main_finds_the_shipped_config_and_the_standard_adb(
    tmp_path, monkeypatch, at_a_terminal, capsys
):
    # Uses the config as shipped: data_root and adb are both under %LOCALAPPDATA%.
    root = tmp_path / "localappdata"
    fake = FakeAdb(root / "Android" / "Sdk" / "platform-tools")
    monkeypatch.setenv("PATH", "")
    script_input(monkeypatch, happy_answers())
    assert main(["--feature", "price_tracker"]) == 0
    assert (root / "SocialEngine" / "assets" / "raw_recordings" / "price_tracker").is_dir()
    assert (
        root / "SocialEngine" / "assets" / "raw_recordings" / "price_tracker" / "clip_01.mp4"
    ).read_bytes() == RECORDING_BYTES
    assert fake.calls


@pytest.mark.parametrize(
    ("listing", "words"),
    [
        ("List of devices attached\n", "No phone"),
        ("List of devices attached\nA\tunauthorized\n", "Allow"),
        ("List of devices attached\nA\tdevice\nB\tdevice\n", "2"),
    ],
)
def test_main_reports_device_problems_as_a_clear_failure(
    fake, config_file, monkeypatch, at_a_terminal, capsys, listing, words
):
    fake.configure(devices=listing)
    script_input(monkeypatch, Answers())
    assert main(["--feature", "payday_cycle", "--config", str(config_file)]) == 1
    assert words in capsys.readouterr().err


def test_main_treats_ctrl_c_as_a_clean_stop(
    fake, config_file, monkeypatch, at_a_terminal, paths, capsys
):
    script = [*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", KeyboardInterrupt]
    script_input(monkeypatch, Answers(*script))
    assert main(["--feature", "payday_cycle", "--config", str(config_file)]) == 130
    assert_demo_was_switched_off(fake)
    assert_nothing_signed(paths)


def test_ctrl_break_is_handled_like_ctrl_c(
    fake, config_file, monkeypatch, at_a_terminal, paths, capsys
):
    # Without a handler, Ctrl+Break ends Python on the spot and demo mode would stay on.
    def break_arrives():
        signal.raise_signal(signal.SIGBREAK)
        return ""

    before = signal.getsignal(signal.SIGBREAK)
    script = [*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes", break_arrives]
    script_input(monkeypatch, Answers(*script))
    assert main(["--feature", "payday_cycle", "--config", str(config_file)]) == 130
    assert_demo_was_switched_off(fake)
    assert signal.getsignal(signal.SIGBREAK) == before


def test_main_fails_when_demo_mode_could_not_be_switched_off(
    fake, config_file, monkeypatch, at_a_terminal, capsys
):
    fake.configure(fail=[{"match": "-e command exit"}])
    script_input(monkeypatch, happy_answers())
    assert main(["--feature", "payday_cycle", "--config", str(config_file)]) == 1


def test_main_refuses_a_forbidden_environment(
    fake, config_file, monkeypatch, at_a_terminal, capsys
):
    monkeypatch.setenv(FORBIDDEN_ENV_PREFIX + "URL", "x")
    script_input(monkeypatch, Answers())
    assert main(["--feature", "payday_cycle", "--config", str(config_file)]) == 1
    assert fake.calls == []


def test_main_needs_a_feature_or_ingest(capsys):
    with pytest.raises(SystemExit) as stopped:
        main([])
    assert stopped.value.code == 2


def test_main_does_not_guess_abbreviated_options(capsys):
    with pytest.raises(SystemExit) as stopped:
        main(["--fin", "--feature", "payday_cycle"])
    assert stopped.value.code == 2


def test_piped_answers_cannot_stand_in_for_the_owner(tmp_path, fake, config_file):
    # A real process with real pipes: `yes | capture_cli` signs nothing and starts nothing.
    run = subprocess.run(
        [
            sys.executable,
            "-m",
            "phone_capture.capture_cli",
            "--feature",
            "payday_cycle",
            "--config",
            str(config_file),
        ],
        cwd=ENGINE_ROOT,
        input="yes\n" * 40,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        check=False,
    )
    assert run.returncode == 1
    assert "terminal" in run.stderr
    assert fake.calls == []


def test_arabic_checklist_lines_cannot_crash_a_console_with_an_old_code_page(monkeypatch):
    # The final-clip line holds Arabic, which a cp1252 stream cannot encode.
    stream = io.TextIOWrapper(io.BytesIO(), encoding="cp1252")
    monkeypatch.setattr(capture_cli.sys, "stdout", stream)
    capture_cli._use_utf8_console()
    print(CHECKLIST[-1])
    stream.flush()
    assert CHECKLIST[-1].encode("utf-8") in stream.buffer.getvalue()


def test_the_fake_adb_is_a_real_executable(fake):
    # Keeps the tests honest: they exercise real processes and real argument passing.
    run = subprocess.run(
        [str(fake.path), "shell", "echo", "a;b c"], capture_output=True, check=False, timeout=30
    )
    assert run.returncode == 0
    assert fake.calls == [["shell", "echo", "a;b c"]]
