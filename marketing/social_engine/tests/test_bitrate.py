"""Bitrate, the size loop and the temp name (spec Sections 3.5 and 8.6, task G2)."""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import make_junction
from render_support import MB, Rig, build_mp4, option, write_mp4_of_size

import core.render as render_module
from core.manifest import sha256_file
from core.mp4_check import read_mp4
from core.render import (
    RenderFailed,
    RenderRefused,
    lower_bitrate,
    render_reel,
    video_kbps,
)

TELEGRAM_BOT_LIMIT = 50 * MB


@pytest.fixture
def rig(tmp_path, monkeypatch) -> Rig:
    return Rig(tmp_path, monkeypatch)


def render(rig: Rig, **overrides):
    return render_reel(
        rig.request(**overrides),
        store=rig.reels,
        config=rig.config,
        paths=rig.paths,
        engine_root=rig.engine,
    )


def oversized(path: Path) -> None:
    write_mp4_of_size(path, 48 * MB + 1)


def good(path: Path) -> None:
    path.write_bytes(build_mp4())


def renders_folder(rig: Rig) -> list[str]:
    return sorted(path.name for path in rig.paths.renders.iterdir() if path.suffix != ".json")


def work_out(rig: Rig) -> list[str]:
    out = rig.paths.remotion_work / "out"
    return sorted(path.name for path in out.iterdir() if path.suffix != ".log")


# --- The formula -----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("seconds", "kbps"),
    [(15, 8000), (35, 8000), (45, 8000), (60, 6074)],
)
def test_the_spec_table(rig, seconds, kbps):
    assert video_kbps(seconds * 1000, rig.config.render) == kbps


def test_the_longest_reel_still_fits(rig):
    kbps = video_kbps(180_000, rig.config.render)
    assert kbps == 1896
    size_mb = (kbps + rig.config.render.audio_kbps) * 180 / 8000
    assert size_mb <= 47


def test_a_very_short_reel_stays_at_the_cap(rig):
    assert video_kbps(1, rig.config.render) == 8000


def test_the_budget_follows_the_configured_values(rig):
    def change(data):
        data["render"].update(max_mb=25, audio_kbps=128, video_kbps_cap=20_000)

    rig.use_config(change)
    assert video_kbps(60_000, rig.config.render) == 24 * 8000 // 60 - 128


def test_a_budget_with_no_room_for_video_is_refused(rig):
    rig.use_config(lambda data: data["render"].update(max_mb=1))
    with pytest.raises(RenderRefused, match="bitrate"):
        video_kbps(60_000, rig.config.render)


def test_each_lower_bitrate_is_15_percent_down(rig):
    assert lower_bitrate(8000) == 6800
    assert lower_bitrate(6800) == 5780
    assert lower_bitrate(6074) == 5162


def test_the_shipped_limit_is_under_the_telegram_limit(rig):
    assert rig.config.render.max_mb * MB < TELEGRAM_BOT_LIMIT


# --- The render command ----------------------------------------------------------------


def test_the_render_uses_the_formula_and_the_spec_format(rig):
    rig.fake.outputs = [lambda path: path.write_bytes(build_mp4(duration_ms=60_000))]
    render(rig, duration_ms=60_000)
    command = rig.fake.renders[0].command
    assert command[:5] == ["C:/fake/npx.cmd", "--no", "remotion", "render", "DailyTip"]
    assert option(command, "video-bitrate") == "6074k"
    assert option(command, "audio-bitrate") == "192k"
    assert option(command, "codec") == "h264"
    assert option(command, "audio-codec") == "aac"


def test_the_render_runs_in_the_work_folder_with_a_scrubbed_environment(rig, monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "secret")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "secret")
    render(rig)
    for call in [*rig.fake.renders, *rig.fake.conforms]:
        assert Path(call.kwargs["cwd"]) == rig.paths.remotion_work
        assert "TELEGRAM_BOT_TOKEN" not in call.kwargs["env"]
        assert "ANTHROPIC_API_KEY" not in call.kwargs["env"]


def test_command_arguments_hold_no_folder_from_the_machine(rig):
    # A .cmd goes through cmd.exe, so only validated names should reach its command line.
    render(rig)
    for call in [*rig.fake.renders, *rig.fake.conforms]:
        assert not any(str(rig.data_root) in part for part in call.command[1:])


def test_the_conform_step_moves_moov_forward_and_avoids_edit_lists(rig):
    render(rig)
    command = rig.fake.conforms[0].command
    assert command[:4] == ["C:/fake/npx.cmd", "--no", "remotion", "ffmpeg"]
    assert command[command.index("-movflags") + 1] == "+faststart"
    assert command[command.index("-use_editlist") + 1] == "0"
    assert command[command.index("-c") + 1] == "copy"


def test_a_configured_ffmpeg_path_is_used_for_the_conform_step(rig):
    rig.use_config(lambda data: data["render"].update(ffmpeg_path="C:/tools/ffmpeg.exe"))
    render(rig)
    assert rig.fake.conforms[0].command[0] == str(Path("C:/tools/ffmpeg.exe"))


# --- The size loop ---------------------------------------------------------------------


def test_a_file_that_fits_renders_once(rig):
    result = render(rig)
    assert rig.fake.video_kbps == ["8000k"]
    assert result.renders == 1
    assert result.video_kbps == 8000


def test_oversize_re_renders_at_15_percent_lower(rig):
    rig.fake.outputs = [oversized, good]
    result = render(rig)
    assert rig.fake.video_kbps == ["8000k", "6800k"]
    assert result.video_kbps == 6800
    assert result.renders == 2


def test_oversize_twice_then_a_fit_is_the_last_allowed_try(rig):
    rig.fake.outputs = [oversized, oversized, good]
    result = render(rig)
    assert rig.fake.video_kbps == ["8000k", "6800k", "5780k"]
    assert result.renders == 3


def test_it_fails_rather_than_keep_a_file_it_cannot_deliver(rig):
    rig.fake.outputs = [oversized]
    with pytest.raises(RenderFailed, match="48 MB"):
        render(rig)
    assert rig.fake.video_kbps == ["8000k", "6800k", "5780k"]
    assert renders_folder(rig) == []
    assert work_out(rig) == []


def test_the_size_is_measured_after_the_conform_step(rig):
    # The render fits, and only the conformed file is too big.
    rig.fake.conform_writer = oversized
    with pytest.raises(RenderFailed, match="48 MB"):
        render(rig)
    assert renders_folder(rig) == []


def test_the_delivered_file_is_really_under_the_limit(rig):
    rig.fake.outputs = [oversized, lambda path: write_mp4_of_size(path, 48 * MB)]
    result = render(rig)
    assert result.size_bytes == 48 * MB < TELEGRAM_BOT_LIMIT
    assert result.path.stat().st_size == 48 * MB


# --- Bad output is never kept or retried ----------------------------------------------


@pytest.mark.parametrize(
    "bad",
    [
        pytest.param(lambda path: path.write_bytes(build_mp4()[:-10]), id="truncated mdat"),
        pytest.param(
            lambda path: path.write_bytes(build_mp4(moov_first=False)[:-10]), id="truncated moov"
        ),
        pytest.param(lambda path: path.write_bytes(b"not a video at all"), id="not an MP4"),
        pytest.param(lambda path: path.write_bytes(b""), id="empty"),
        pytest.param(lambda path: path.write_bytes(build_mp4(width=720)), id="wrong size"),
        pytest.param(lambda path: path.write_bytes(build_mp4(duration_ms=9_000)), id="too short"),
        pytest.param(lambda path: path.write_bytes(build_mp4(moov_first=False)), id="moov late"),
        pytest.param(lambda path: path.write_bytes(build_mp4(edit_list=True)), id="edit list"),
        pytest.param(lambda path: path.write_bytes(build_mp4(video_codec=b"vp09")), id="not H264"),
    ],
)
def test_bad_output_fails_with_no_final_file_and_no_retry(rig, bad):
    rig.fake.outputs = [bad]
    with pytest.raises(RenderFailed, match="checks"):
        render(rig)
    assert len(rig.fake.renders) == 1
    assert renders_folder(rig) == []
    assert work_out(rig) == []


def test_a_retry_that_writes_nothing_cannot_pass_with_the_file_before_it(rig):
    rig.fake.outputs = [oversized, lambda path: None]
    with pytest.raises(RenderFailed):
        render(rig)
    assert len(rig.fake.renders) == 2
    assert renders_folder(rig) == []


def test_a_conform_step_that_writes_no_file_fails(rig):
    rig.fake.conform_writer = lambda path: None
    with pytest.raises(RenderFailed):
        render(rig)
    assert renders_folder(rig) == []


# --- Temp name -------------------------------------------------------------------------


def test_nothing_is_in_renders_until_the_checks_pass(rig):
    rig.fake.outputs = [oversized, good]
    result = render(rig)
    for call in [*rig.fake.renders, *rig.fake.conforms]:
        assert call.renders_files == []
    assert renders_folder(rig) == [result.path.name]


def test_the_render_goes_to_a_temp_name_in_out(rig):
    result = render(rig)
    output = next(part for part in rig.fake.renders[0].command if part.endswith(".mp4"))
    assert output.startswith("out/")
    assert Path(output).name != result.path.name


def test_temp_files_are_gone_after_success(rig):
    render(rig)
    assert work_out(rig) == []


def test_the_result_describes_the_final_file(rig):
    result = render(rig)
    assert result.path.parent == rig.paths.renders
    assert result.sha256 == sha256_file(result.path)
    assert result.size_bytes == result.path.stat().st_size
    assert read_mp4(result.path).moov_before_mdat is True


def test_a_failed_render_is_an_error_that_does_not_repeat_its_output(rig):
    rig.fake.render_exit = 7
    with pytest.raises(RenderFailed, match="exit code 7") as caught:
        render(rig)
    assert len(rig.fake.renders) == 1
    assert renders_folder(rig) == []
    assert "LEAK-MARKER" not in str(caught.value)


def test_a_failed_conform_step_is_an_error(rig):
    rig.fake.conform_exit = 3
    with pytest.raises(RenderFailed, match="exit code 3"):
        render(rig)
    assert renders_folder(rig) == []


def test_a_render_that_hangs_is_stopped_with_its_child_processes(rig):
    rig.fake.hangs = True
    with pytest.raises(RenderFailed, match="did not finish"):
        render(rig)
    kills = [call for call in rig.fake.run_calls if call[0] == "taskkill"]
    assert kills == [["taskkill", "/T", "/F", "/PID", "4242"]]
    assert renders_folder(rig) == []


def test_missing_npx_is_a_clear_error(rig, monkeypatch):
    real = shutil.which
    monkeypatch.setattr(shutil, "which", lambda name: None if name == "npx" else real(name))
    with pytest.raises(RenderFailed, match="npx"):
        render(rig)


def test_a_render_that_cannot_start_is_a_clear_error(rig, monkeypatch):
    def refuse(*args, **kwargs):
        raise PermissionError("locked")

    monkeypatch.setattr("subprocess.Popen", refuse)
    with pytest.raises(RenderFailed, match="locked"):
        render(rig)


# --- A real child process, through a real .cmd, as npx is on Windows --------------------

REAL_POPEN = subprocess.Popen
REAL_RUN = subprocess.run
_HELPER = """
import os, shutil, sys, time
from pathlib import Path

args = sys.argv[1:]
Path(args[0]).write_text(str(os.getpid()) + " " + " ".join(args[1:]), encoding="utf-8")
if args[1] == "hang":
    time.sleep(120)
elif "render" in args:
    print("LEAK-MARKER")
    output = next(arg for arg in args[2:] if arg.endswith(".mp4"))
    shutil.copyfile(args[1], output)
else:
    shutil.copyfile(args[args.index("-i") + 1], args[-1])
"""


def install_real_npx(rig: Rig, tmp_path: Path, monkeypatch, first_argument: str) -> Path:
    """npx.cmd runs a helper script, and the helper records what it was given."""
    helper = tmp_path / "helper.py"
    helper.write_text(_HELPER, encoding="utf-8")
    seen = tmp_path / "seen.txt"
    npx = tmp_path / "npx.cmd"
    npx.write_text(
        f'@echo off\r\n"{sys.executable}" -I "{helper}" "{seen}" {first_argument} %*\r\n',
        encoding="utf-8",
    )
    (rig.engine / "remotion_studio" / "package-lock.json").unlink()  # so no npm ci is needed
    monkeypatch.setattr(subprocess, "Popen", REAL_POPEN)
    monkeypatch.setattr(subprocess, "run", REAL_RUN)
    monkeypatch.setattr(shutil, "which", lambda name: str(npx))
    return seen


def test_a_real_child_gets_its_arguments_and_the_result_passes_the_checks(
    rig, tmp_path, monkeypatch
):
    good_file = tmp_path / "good.mp4"
    good_file.write_bytes(build_mp4())
    seen = install_real_npx(rig, tmp_path, monkeypatch, f'"{good_file}"')
    result = render(rig)
    assert result.path.read_bytes() == good_file.read_bytes()
    command = seen.read_text("utf-8")
    assert "+faststart" in command
    assert "-use_editlist 0" in command


def test_a_real_child_that_hangs_is_killed_with_its_whole_tree(rig, tmp_path, monkeypatch):
    seen = install_real_npx(rig, tmp_path, monkeypatch, "hang")
    monkeypatch.setattr(render_module, "_STEP_TIMEOUT_S", 3)
    with pytest.raises(RenderFailed, match="did not finish"):
        render(rig)
    helper_pid = seen.read_text("utf-8").split()[0]
    listed = REAL_RUN(
        ["tasklist", "/FI", f"PID eq {helper_pid}", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert helper_pid not in listed.stdout, "the helper outlived the timeout"


def test_real_child_output_goes_to_the_log_and_not_the_message(rig, tmp_path, monkeypatch):
    # The helper copies a missing file, so it prints its marker and then fails.
    install_real_npx(rig, tmp_path, monkeypatch, f'"{tmp_path / "missing.mp4"}"')
    with pytest.raises(RenderFailed, match="exit code") as caught:
        render(rig)
    assert "LEAK-MARKER" not in str(caught.value)
    logs = list((rig.paths.remotion_work / "out").glob("*.log"))
    assert "LEAK-MARKER" in logs[0].read_text("utf-8", errors="replace")


# --- Same content reuses the file (spec Section 3.5) ----------------------------------


def test_the_same_content_reuses_the_checked_file(rig):
    first = render(rig)
    count = rig.fake.subprocess_count
    second = render(rig)
    assert second.reused is True
    assert second.path == first.path
    assert second.sha256 == first.sha256
    assert second.content_hash == first.content_hash
    assert rig.fake.subprocess_count == count


def test_a_reused_file_that_fails_the_checks_is_rendered_again(rig):
    first = render(rig)
    first.path.write_bytes(build_mp4()[:-5])
    second = render(rig)
    assert second.reused is False
    assert second.path == first.path
    assert read_mp4(second.path).size_bytes == len(build_mp4())


@pytest.mark.parametrize(
    "change",
    [
        pytest.param(lambda rig: rig.request(hook_text="نص جديد"), id="props"),
        pytest.param(
            lambda rig: (rig.paths.voiceovers / "voice.wav").write_bytes(b"new") and None,
            id="audio",
        ),
        pytest.param(
            lambda rig: (rig.engine / "remotion_studio" / "src" / "Root.tsx").write_text("v2")
            and None,
            id="template version",
        ),
        pytest.param(
            lambda rig: (rig.engine / "assets" / "branding" / "test_logo.svg").write_text("<svg/>")
            and None,
            id="logo",
        ),
    ],
)
def test_a_change_in_any_input_is_a_new_render(rig, change):
    first = render(rig)
    request = change(rig)
    second = (
        render_reel(
            request,
            store=rig.reels,
            config=rig.config,
            paths=rig.paths,
            engine_root=rig.engine,
        )
        if request is not None
        else render(rig)
    )
    assert second.content_hash != first.content_hash
    assert second.reused is False


def test_a_new_revision_is_a_new_file(rig):
    first = render(rig)
    second = render(rig, revision=2)
    assert second.path != first.path
    assert second.reused is False


# --- Output folders --------------------------------------------------------------------


def test_a_junction_at_renders_is_refused_before_any_render(rig, tmp_path):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    rig.paths.renders.rmdir()
    make_junction(rig.paths.renders, elsewhere)
    with pytest.raises(RenderFailed, match="renders"):
        render(rig)
    assert list(elsewhere.iterdir()) == []
    assert rig.fake.renders == []


def test_a_junction_at_out_is_refused_and_nothing_is_written_through_it(rig, tmp_path):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    (elsewhere / "keep.txt").write_text("keep", encoding="utf-8")
    rig.paths.remotion_work.mkdir(exist_ok=True)
    make_junction(rig.paths.remotion_work / "out", elsewhere)
    with pytest.raises(RenderFailed, match="out is a link"):
        render(rig)
    assert [path.name for path in elsewhere.iterdir()] == ["keep.txt"]
    assert rig.fake.renders == []


def test_a_junction_that_appears_at_out_after_the_sync_is_refused_before_the_render(
    rig, tmp_path, monkeypatch
):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    real_sync = render_module.sync

    def sync_then_link(engine_root, data_root):
        result = real_sync(engine_root, data_root)
        make_junction(rig.paths.remotion_work / "out", elsewhere)
        return result

    started = []
    monkeypatch.setattr(render_module, "sync", sync_then_link)
    monkeypatch.setattr(render_module._Run, "start", lambda self, props: started.append(props))
    with pytest.raises(RenderFailed, match="out is a link"):
        render(rig)
    assert started == [], "the props file would have been written through the link"
    assert list(elsewhere.iterdir()) == []
    assert rig.fake.renders == []


def test_a_junction_that_appears_during_the_render_stops_the_next_step(rig, tmp_path):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    (rig.engine / "remotion_studio" / "package-lock.json").unlink()  # so nothing makes node_modules

    def write_then_link(path: Path) -> None:
        good(path)
        make_junction(rig.paths.remotion_work / "node_modules", elsewhere)

    rig.fake.outputs = [write_then_link]
    with pytest.raises(RenderFailed, match="node_modules is a link"):
        render(rig)
    assert rig.fake.conforms == []
    assert list(elsewhere.iterdir()) == []
    assert renders_folder(rig) == []
