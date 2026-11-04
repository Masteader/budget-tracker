"""Screenshots from the phone with a fake `adb` executable (spec Section 5, `adb exec-out screencap
-p` under the same checklist). Nothing here touches a phone. Real phone behaviour is LIVE-4."""

import subprocess
import sys
from pathlib import Path

import pytest
import yaml
from capture_helpers import (
    SCREENSHOT_BYTES,
    Answers,
    FakeAdb,
    build_config,
    build_gate_met_config,
    config_data,
)
from conftest import make_junction

from core.config import EngineConfig
from core.manifest import ClipManifest, ClipRejected, sha256_file
from core.paths import ENGINE_ROOT, EnginePaths, PathConfigError
from core.secrets import FORBIDDEN_ENV_PREFIX
from phone_capture import capture_cli
from phone_capture.adb import (
    AdbClient,
    MultipleDevices,
    NoDevice,
    ScreenshotFailed,
    UnauthorizedDevice,
)
from phone_capture.capture_cli import main, run_screenshot
from phone_capture.ingest import (
    CHECKLIST,
    STATUS_BAR_LINE,
    CaptureError,
    Checklist,
    ChecklistRefused,
    OwnerAnswers,
    record_screenshot,
    screenshot_manifest_path,
)

DEMO_ON = [
    "shell settings put global sysui_demo_allowed 1",
    "shell am broadcast -a com.android.systemui.demo -e command enter",
    "shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941",
    "shell am broadcast -a com.android.systemui.demo -e command battery -e level 100",
    "shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4",
    "shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false",
]
DEMO_OFF = "shell am broadcast -a com.android.systemui.demo -e command exit"
SCREENCAP = "exec-out screencap -p"
LINES_BEFORE_DEMO = len(CHECKLIST) - 1
MASK = "0.1 0.2 0.5 0.05"
BASKET = "smart_basket"


def happy_answers(*after_privacy, privacy="yes", app_version="1.4.2"):
    return Answers(
        *["yes"] * LINES_BEFORE_DEMO,
        app_version,
        "yes",  # the status bar line, once demo mode is on
        privacy,
        *after_privacy,
    )


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


def shoot(config, feature="payday_cycle", answers=None, **kwargs):
    lines = []
    ask = answers or happy_answers()
    return run_screenshot(config, feature, ask=ask, out=lines.append, **kwargs)


def entries(paths) -> list:
    return ClipManifest.load(screenshot_manifest_path(paths)).clips


def folder_of(paths, feature="payday_cycle") -> Path:
    return paths.screenshots / feature


def assert_nothing_saved(paths, feature="payday_cycle") -> None:
    folder = folder_of(paths, feature)
    assert not folder.exists() or list(folder.iterdir()) == []
    assert entries(paths) == []


def assert_demo_was_switched_off(fake) -> None:
    assert DEMO_OFF in fake.commands
    assert not fake.demo_is_on


# --- The normal path -------------------------------------------------------------------------


def test_it_takes_the_picture_with_demo_mode_on_and_switches_it_off(fake, config):
    result = shoot(config)
    assert result.demo_off
    assert fake.commands == ["devices", *DEMO_ON, SCREENCAP, DEMO_OFF]
    assert_demo_was_switched_off(fake)


def test_the_phone_is_named_by_serial(fake, config):
    shoot(config)
    assert ["-s", "FAKE0001", "exec-out", "screencap", "-p"] in fake.calls


def test_the_png_is_saved_by_feature_with_its_exact_bytes(fake, config, paths):
    result = shoot(config)
    assert result.file == folder_of(paths) / "screen_01.png"
    assert result.file.read_bytes() == SCREENSHOT_BYTES


def test_nothing_is_stored_on_the_phone(fake, config):
    shoot(config)
    assert not fake.phone.exists() or [p.name for p in fake.phone.iterdir()] == []


def test_sign_off_records_its_hash_and_app_version(fake, config, paths):
    result = shoot(config)
    assert result.signed
    entry = ClipManifest.load(screenshot_manifest_path(paths)).verified_clip(
        "payday_cycle/screen_01.png", paths.screenshots
    )
    assert entry.sha256 == sha256_file(result.file)
    assert entry.app_version == "1.4.2"
    assert entry.privacy_checked is True


def test_screenshots_stay_out_of_the_render_allow_list(fake, config, paths):
    shoot(config)
    assert ClipManifest.load(paths.manifest).clips == []
    assert screenshot_manifest_path(paths) != paths.manifest


def test_adb_gets_a_scrubbed_environment(fake, config, monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "not-for-adb")
    monkeypatch.setenv(FORBIDDEN_ENV_PREFIX + "URL", "not-for-adb")
    shoot(config)
    for record in fake.records:
        assert "TELEGRAM_BOT_TOKEN" not in record["env"]
        assert FORBIDDEN_ENV_PREFIX + "URL" not in record["env"]


def test_pictures_are_numbered_and_never_overwritten(fake, config, paths):
    first = shoot(config)
    second = shoot(config)
    assert (first.file.name, second.file.name) == ("screen_01.png", "screen_02.png")
    assert len(entries(paths)) == 2


def test_a_number_held_by_the_manifest_is_never_used_again(fake, config, paths):
    first = shoot(config)
    first.file.unlink()
    assert shoot(config).file.name == "screen_02.png"


def test_a_leftover_part_file_keeps_its_number(fake, config, paths):
    folder_of(paths).mkdir(parents=True)
    (folder_of(paths) / "screen_07.png.part").write_bytes(b"x")
    assert shoot(config).file.name == "screen_08.png"


# --- The device ------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("devices", "error"),
    [
        ("List of devices attached\n", NoDevice),
        ("List of devices attached\nA\tunauthorized\n", UnauthorizedDevice),
        ("List of devices attached\nA\tdevice\nB\tdevice\n", MultipleDevices),
    ],
)
def test_it_needs_exactly_one_authorised_phone(fake, config, paths, devices, error):
    fake.configure(devices=devices)
    with pytest.raises(error):
        shoot(config, answers=Answers())
    assert fake.commands == ["devices"]
    assert_nothing_saved(paths)


# --- The same checklist ----------------------------------------------------------------------


def test_every_checklist_line_is_asked_word_for_word(fake, config):
    answers = happy_answers()
    shoot(config, answers=answers)
    for line in CHECKLIST:
        assert any(prompt.startswith(line) for prompt in answers.prompts), line


@pytest.mark.parametrize("index", range(LINES_BEFORE_DEMO))
def test_refusing_a_line_before_demo_mode_leaves_the_phone_alone(fake, config, paths, index):
    answers = Answers(*["yes"] * index, "no")
    with pytest.raises(ChecklistRefused):
        shoot(config, answers=answers)
    assert fake.commands == ["devices"]
    assert_nothing_saved(paths)


def test_refusing_the_status_bar_line_takes_no_picture_and_ends_demo_mode(fake, config, paths):
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "no")
    with pytest.raises(ChecklistRefused):
        shoot(config, answers=answers)
    assert SCREENCAP not in fake.commands
    assert_demo_was_switched_off(fake)
    assert_nothing_saved(paths)


def test_the_status_bar_line_is_asked_while_demo_mode_is_on(fake, config):
    def check_demo_is_on():
        assert fake.demo_is_on
        assert SCREENCAP not in fake.commands
        return "yes"

    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", check_demo_is_on, "yes")
    shoot(config, answers=answers)


def test_a_closed_terminal_is_not_a_yes(fake, config, paths):
    with pytest.raises(ChecklistRefused):
        shoot(config, answers=Answers(EOFError))
    assert_nothing_saved(paths)


# --- When the picture goes wrong -------------------------------------------------------------


@pytest.mark.parametrize("output", ["empty", "not_a_png", "cut_off"])
def test_output_that_is_not_a_whole_png_is_refused_and_leaves_no_file(fake, config, paths, output):
    fake.configure(screencap=output)
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes")
    with pytest.raises(ScreenshotFailed):
        shoot(config, answers=answers)
    assert_demo_was_switched_off(fake)
    assert_nothing_saved(paths)


def test_a_failed_adb_call_leaves_no_file_and_ends_demo_mode(fake, config, paths):
    fake.configure(fail=[{"match": "screencap", "stderr": "device offline"}])
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes")
    with pytest.raises(ScreenshotFailed, match="device offline"):
        shoot(config, answers=answers)
    assert_demo_was_switched_off(fake)
    assert_nothing_saved(paths)


def test_a_failed_demo_command_takes_no_picture_and_still_ends_demo_mode(fake, config, paths):
    fake.configure(fail=[{"match": "command battery"}])
    with pytest.raises(capture_cli.AdbError):
        shoot(config, answers=Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2"))
    assert SCREENCAP not in fake.commands
    assert_demo_was_switched_off(fake)
    assert_nothing_saved(paths)


def test_ctrl_c_at_the_picture_leaves_no_file_and_ends_demo_mode(fake, config, paths, monkeypatch):
    real_run = subprocess.run

    def interrupted(args, **kwargs):
        if "screencap" in args:
            raise KeyboardInterrupt
        return real_run(args, **kwargs)

    monkeypatch.setattr(subprocess, "run", interrupted)
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", "yes")
    with pytest.raises(KeyboardInterrupt):
        shoot(config, answers=answers)
    assert_demo_was_switched_off(fake)
    assert_nothing_saved(paths)


def test_a_hung_adb_is_a_failure_and_leaves_no_file(fake, tmp_path, monkeypatch):
    real_run = subprocess.run

    def hung(args, **kwargs):
        if "screencap" in args:
            raise subprocess.TimeoutExpired(args, 1)
        return real_run(args, **kwargs)

    monkeypatch.setattr(subprocess, "run", hung)
    device = AdbClient(fake.path).require_one_device()
    part = tmp_path / "screen.png.part"
    with pytest.raises(ScreenshotFailed, match="seconds"):
        device.screenshot(part)
    assert not part.exists()


def test_it_never_writes_through_a_file_already_at_the_part_name(fake, tmp_path):
    device = AdbClient(fake.path).require_one_device()
    part = tmp_path / "screen.png.part"
    part.write_bytes(b"keep")
    with pytest.raises(ScreenshotFailed):
        device.screenshot(part)
    assert part.read_bytes() == b"keep"


def test_a_demo_mode_that_will_not_end_is_reported(fake, config, paths):
    fake.configure(fail=[{"match": "command exit"}])
    result = shoot(config)
    assert result.demo_off is False
    assert result.signed


# --- The same sign-off -----------------------------------------------------------------------


@pytest.mark.parametrize("reply", ["no", "", "y", EOFError])
def test_only_a_typed_yes_signs_it_off(fake, config, paths, reply):
    result = shoot(config, answers=happy_answers(privacy=reply))
    assert result.signed is False
    assert entries(paths) == []


def test_an_unsigned_picture_is_kept_but_stays_unusable(fake, config, paths):
    result = shoot(config, answers=happy_answers(privacy="no"))
    assert result.file.exists()
    with pytest.raises(ClipRejected, match="not in the manifest"):
        ClipManifest.load(screenshot_manifest_path(paths)).verified_clip(
            f"payday_cycle/{result.file.name}", paths.screenshots
        )


def test_the_owner_is_told_which_file_to_look_at(fake, config, paths):
    answers = happy_answers()
    result = shoot(config, answers=answers)
    assert str(result.file) in answers.prompts[-1]


@pytest.mark.parametrize("app_version", ["", "not a version", "1.0; rm -rf"])
def test_a_bad_app_version_stops_before_demo_mode(fake, config, paths, app_version):
    answers = Answers(*["yes"] * LINES_BEFORE_DEMO, app_version)
    with pytest.raises(CaptureError, match="app version"):
        shoot(config, answers=answers)
    assert fake.commands == ["devices"]


# --- The same Smart Basket mask requirement --------------------------------------------------


def test_a_smart_basket_picture_needs_masks_covering_the_store_names(fake, config, paths):
    result = shoot(config, BASKET, answers=happy_answers(MASK, "", "yes"))
    assert result.signed
    entry = entries(paths)[0]
    assert entry.store_names_masked is True
    assert (entry.mask_regions[0].x, entry.mask_regions[0].width) == (0.1, 0.5)


def test_a_smart_basket_picture_with_no_masks_is_not_signed(fake, config, paths):
    result = shoot(config, BASKET, answers=happy_answers(""))
    assert result.signed is False
    assert entries(paths) == []


def test_a_smart_basket_picture_with_masks_not_confirmed_is_not_signed(fake, config, paths):
    result = shoot(config, BASKET, answers=happy_answers(MASK, "", "no"))
    assert result.signed is False
    assert entries(paths) == []


def test_a_mask_too_small_to_hide_a_name_does_not_count(fake, config, paths):
    result = shoot(config, BASKET, answers=happy_answers("0.1 0.2 0.01 0.01", ""))
    assert result.signed is False
    assert entries(paths) == []


def test_other_features_are_not_asked_about_masks(fake, config, paths):
    assert shoot(config, answers=happy_answers()).signed
    assert entries(paths)[0].mask_regions == []


def test_the_owner_is_told_the_mask_is_not_burned_into_the_file(fake, config):
    # Render blurs clips. Nothing blurs a PNG yet, so the prompt must not say that it does.
    lines = []
    run_screenshot(config, BASKET, ask=happy_answers(MASK, "", "yes"), out=lines.append)
    said = " ".join(lines).casefold()
    assert "unmasked" in said
    assert "blurred at render" not in said


# --- Storage stays out of OneDrive and git ---------------------------------------------------


@pytest.mark.parametrize(
    "root",
    [
        pytest.param(lambda tmp: tmp / "OneDrive" / "shots", id="onedrive"),
        pytest.param(lambda tmp: ENGINE_ROOT / "assets" / "shots", id="the repo"),
    ],
)
def test_a_data_root_in_onedrive_or_git_is_refused_before_the_phone_is_touched(
    fake, tmp_path, root
):
    config = EngineConfig.model_validate(config_data(root(tmp_path), fake.path))
    with pytest.raises(PathConfigError):
        shoot(config, answers=Answers())
    assert fake.calls == []


@pytest.mark.skipif(sys.platform != "win32", reason="junctions need Windows")
def test_a_junction_at_the_feature_folder_is_refused_before_the_phone_is_touched(
    fake, config, paths, tmp_path
):
    outside = tmp_path / "OneDrive"
    outside.mkdir()
    paths.screenshots.mkdir(parents=True)
    make_junction(folder_of(paths), outside)
    with pytest.raises(CaptureError, match="link"):
        shoot(config, answers=Answers())
    assert fake.calls == []
    assert list(outside.iterdir()) == []


@pytest.mark.skipif(sys.platform != "win32", reason="junctions need Windows")
def test_a_junction_at_the_screenshots_folder_is_refused_before_the_phone_is_touched(
    fake, config, paths, tmp_path
):
    outside = tmp_path / "OneDrive"
    outside.mkdir()
    paths.screenshots.parent.mkdir(parents=True)
    make_junction(paths.screenshots, outside)
    with pytest.raises(CaptureError, match="link"):
        shoot(config, answers=Answers())
    assert fake.calls == []
    assert list(outside.iterdir()) == []


def test_a_broken_screenshot_manifest_stops_before_the_phone_moves(fake, config, paths):
    paths.screenshots.mkdir(parents=True)
    screenshot_manifest_path(paths).write_text("not json", encoding="utf-8")
    with pytest.raises(ValueError):
        shoot(config, answers=Answers())
    assert fake.calls == []


def test_a_feature_outside_the_shot_list_is_refused(fake, config):
    with pytest.raises(CaptureError, match="shot list"):
        shoot(config, "../outside", answers=Answers())
    assert fake.calls == []


# --- Test pictures and final pictures (D23) --------------------------------------------------


def test_a_picture_is_a_test_picture_while_the_gate_is_closed(fake, config):
    result = shoot(config)
    assert result.test_screenshot
    assert result.file.name == "screen_01.png"


def test_a_final_picture_is_refused_while_the_gate_is_closed(fake, config, paths):
    with pytest.raises(CaptureError, match="launch gate"):
        shoot(config, answers=Answers(), final=True)
    assert fake.calls == []


def test_a_final_picture_is_named_once_the_gate_is_met(fake, data_root, tmp_path, monkeypatch):
    config = build_gate_met_config(monkeypatch, tmp_path, data_root, fake.path)
    result = shoot(config, final=True)
    assert result.file.name == "final_screen_01.png"
    assert result.test_screenshot is False


# --- Only `record_screenshot` signs ----------------------------------------------------------


@pytest.fixture
def signable(paths) -> Path:
    file = folder_of(paths) / "screen_01.png"
    file.parent.mkdir(parents=True)
    file.write_bytes(SCREENSHOT_BYTES)
    return file


def confirmed(feature="payday_cycle"):
    checklist = Checklist(feature)
    checklist.confirm(CHECKLIST, ask=lambda prompt: "yes")
    return checklist.confirmation()


def signed_kwargs(file, **changes) -> dict:
    return {
        "sha256": sha256_file(file),
        "confirmation": confirmed(),
        "answers": OwnerAnswers(privacy_clean=True),
        "app_version": "1.4.2",
        "final": False,
        **changes,
    }


def test_a_signature_needs_a_real_checklist_confirmation(config, paths, signable):
    for fake_proof in (None, object(), confirmed("smart_basket")):
        with pytest.raises(ClipRejected, match="checklist"):
            record_screenshot(
                paths, signable, config=config, **signed_kwargs(signable, confirmation=fake_proof)
            )
    assert entries(paths) == []


def test_a_signature_needs_the_owners_answer(config, paths, signable):
    kwargs = signed_kwargs(signable, answers=OwnerAnswers(privacy_clean=False))
    with pytest.raises(ClipRejected, match="signed"):
        record_screenshot(paths, signable, config=config, **kwargs)


def test_a_signature_describes_the_file_the_owner_looked_at(config, paths, signable):
    digest = sha256_file(signable)
    signable.write_bytes(b"changed afterwards")
    with pytest.raises(ClipRejected, match="hash"):
        record_screenshot(paths, signable, config=config, **signed_kwargs(signable, sha256=digest))


def test_a_file_outside_the_screenshot_folders_cannot_be_signed(config, paths, tmp_path):
    other = tmp_path / "payday_cycle" / "screen_01.png"
    other.parent.mkdir()
    other.write_bytes(SCREENSHOT_BYTES)
    with pytest.raises(ClipRejected, match="feature folder"):
        record_screenshot(paths, other, config=config, **signed_kwargs(other))


@pytest.mark.parametrize("name", ["final_screen_01.png", "clip_01.mp4", "screen.png"])
def test_a_wrongly_named_file_cannot_be_signed_as_a_test_picture(config, paths, name):
    file = folder_of(paths) / name
    file.parent.mkdir(parents=True)
    file.write_bytes(SCREENSHOT_BYTES)
    with pytest.raises(ClipRejected, match="name"):
        record_screenshot(paths, file, config=config, **signed_kwargs(file))


def test_a_smart_basket_entry_cannot_be_made_without_masks(config, paths):
    file = folder_of(paths, BASKET) / "screen_01.png"
    file.parent.mkdir(parents=True)
    file.write_bytes(SCREENSHOT_BYTES)
    kwargs = signed_kwargs(file, confirmation=confirmed(BASKET))
    with pytest.raises(ClipRejected, match="mask"):
        record_screenshot(paths, file, config=config, **kwargs)
    assert entries(paths) == []


# --- The command line ------------------------------------------------------------------------


def test_the_command_line_needs_a_feature(capsys):
    with pytest.raises(SystemExit) as stopped:
        main(["--screenshot"])
    assert stopped.value.code == 2


def test_the_command_line_will_not_mix_it_with_ingest(capsys):
    with pytest.raises(SystemExit) as stopped:
        main(["--screenshot", "--ingest", "--feature", "payday_cycle"])
    assert stopped.value.code == 2


@pytest.fixture
def config_file(tmp_path, data_root, fake) -> Path:
    path = tmp_path / "config.yaml"
    path.write_text(
        yaml.safe_dump(config_data(data_root, fake.path), allow_unicode=True), encoding="utf-8"
    )
    return path


class _Stdin:
    def __init__(self, terminal: bool):
        self.terminal = terminal

    def isatty(self) -> bool:
        return self.terminal


def test_the_command_line_refuses_piped_answers(fake, config_file, capsys, monkeypatch):
    monkeypatch.setattr(capture_cli.sys, "stdin", _Stdin(False))
    command = ["--screenshot", "--feature", "payday_cycle", "--config", str(config_file)]
    assert main(command) == 1
    assert "terminal" in capsys.readouterr().err
    assert fake.calls == []


def test_the_command_line_takes_a_picture_and_exits_clean(
    fake, config_file, paths, monkeypatch, capsys
):
    answers = happy_answers()
    monkeypatch.setattr(capture_cli.sys, "stdin", _Stdin(True))
    monkeypatch.setattr("builtins.input", answers)
    command = ["--screenshot", "--feature", "payday_cycle", "--config", str(config_file)]
    assert main(command) == 0
    assert (folder_of(paths) / "screen_01.png").read_bytes() == SCREENSHOT_BYTES
    assert any(prompt.startswith(STATUS_BAR_LINE) for prompt in answers.prompts)
    assert "screen_01.png" in capsys.readouterr().out


def test_the_command_line_reports_a_demo_mode_that_will_not_end(
    fake, config_file, monkeypatch, capsys
):
    fake.configure(fail=[{"match": "command exit"}])
    monkeypatch.setattr(capture_cli.sys, "stdin", _Stdin(True))
    monkeypatch.setattr("builtins.input", happy_answers())
    command = ["--screenshot", "--feature", "payday_cycle", "--config", str(config_file)]
    assert main(command) == 1


def test_the_command_line_treats_ctrl_c_as_a_clean_stop(
    fake, config_file, paths, monkeypatch, capsys
):
    monkeypatch.setattr(capture_cli.sys, "stdin", _Stdin(True))
    monkeypatch.setattr(
        "builtins.input", Answers(*["yes"] * LINES_BEFORE_DEMO, "1.4.2", KeyboardInterrupt)
    )
    command = ["--screenshot", "--feature", "payday_cycle", "--config", str(config_file)]
    assert main(command) == 130
    assert_demo_was_switched_off(fake)
    assert_nothing_saved(paths)
