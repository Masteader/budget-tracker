"""The manual fallback and the sign-off (spec Sections 5.1, 5.2 and 5.3, task H2).

FFmpeg is faked at the subprocess boundary. Whether Remotion's bundled FFmpeg really does the
job is proved in tasks F7 and LIVE-4.
"""

import ast
import re
import subprocess
from pathlib import Path

import pytest
from capture_helpers import Answers, build_config, build_gate_met_config, shipped_data
from conftest import make_junction

from core.config import EngineConfig
from core.manifest import ClipEntry, ClipManifest, ClipRejected, sha256_file
from core.paths import ENGINE_ROOT, EnginePaths, PathConfigError
from phone_capture import ingest as ingest_module
from phone_capture.ingest import (
    CHECKLIST,
    CaptureError,
    Checklist,
    ChecklistRefused,
    OwnerAnswers,
    check_clip_for_reel,
    is_final_clip,
    record_clip,
    run_ingest,
    strip_metadata,
)

SOURCE_BYTES = b"phone recording with GPS and a device name in its metadata"
STRIPPED_BYTES = b"the same picture with no metadata"
MASK = "0.1 0.2 0.5 0.05"
ALL_LINES = ["yes"] * len(CHECKLIST)
_ARGS_CMD_CANNOT_MISREAD = re.compile(r"[A-Za-z0-9_./:+=-]+")


class FakeFfmpeg:
    """Stands in at the subprocess boundary. Writes the output file like the real tool."""

    def __init__(self):
        self.calls = []
        self.returncode = 0
        self.writes_output = True
        self.timeout = False
        self.fails_on_call = None

    def __call__(self, args, **kwargs):
        self.calls.append((list(args), kwargs))
        if self.timeout:
            raise subprocess.TimeoutExpired(args, kwargs.get("timeout"))
        assert (Path(kwargs["cwd"]) / args[args.index("-i") + 1]).is_file()
        failed = self.returncode != 0 or self.fails_on_call == len(self.calls)
        if self.writes_output and not failed:
            (Path(kwargs["cwd"]) / args[-1]).write_bytes(STRIPPED_BYTES)
        code = 1 if failed else 0
        return subprocess.CompletedProcess(args, code, stdout="", stderr="secret-ish output")

    @property
    def args(self) -> list[str]:
        return self.calls[-1][0]


@pytest.fixture
def ffmpeg(monkeypatch) -> FakeFfmpeg:
    fake = FakeFfmpeg()
    monkeypatch.setattr(ingest_module.process_tree, "run", fake)
    monkeypatch.setattr(ingest_module, "find_on_path", lambda name: Path(f"C:/fake/{name}"))
    return fake


@pytest.fixture
def data_root(tmp_path) -> Path:
    return tmp_path / "data"


@pytest.fixture
def paths(data_root) -> EnginePaths:
    built = EnginePaths.from_root(data_root)
    built.ensure_dirs()
    return built


@pytest.fixture
def config(data_root) -> EngineConfig:
    return build_config(data_root)


def drop(paths: EnginePaths, feature: str, name: str = "Screen_Recording.mp4") -> Path:
    file = paths.raw_recordings / feature / name
    file.write_bytes(SOURCE_BYTES)
    return file


def ingest(config, answers, **kwargs):
    lines = kwargs.pop("lines", [])
    return run_ingest(config, ask=answers, out=lines.append, **kwargs)


def signed_answers(*after_privacy, version="1.4.2"):
    return Answers(*ALL_LINES, "yes", *after_privacy, version)


def manifest_of(paths: EnginePaths) -> ClipManifest:
    return ClipManifest.load(paths.manifest)


def confirmed(feature: str = "payday_cycle"):
    checklist = Checklist(feature)
    checklist.confirm(CHECKLIST, ask=lambda prompt: "yes")
    return checklist.confirmation()


# --- The manual fallback, start to finish -----------------------------------------------


def test_a_dropped_file_goes_through_hash_strip_checklist_and_sign_off(ffmpeg, config, paths):
    source = drop(paths, "payday_cycle")
    report = ingest(config, signed_answers())
    assert report.signed == ["payday_cycle/clip_01.mp4"]
    saved = paths.raw_recordings / "payday_cycle" / "clip_01.mp4"
    assert saved.read_bytes() == STRIPPED_BYTES
    entry = manifest_of(paths).verified_clip("payday_cycle/clip_01.mp4", paths.raw_recordings)
    assert entry.privacy_checked is True
    assert entry.sha256 == sha256_file(saved)
    assert entry.app_version == "1.4.2"
    assert not source.exists()


def test_the_owner_is_shown_the_cleaned_copy_they_are_signing(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    answers = signed_answers()
    shown = []

    def watch_what_is_named():
        prompt = answers.prompts[-1]
        file = next(word for word in re.split(r"\s+", prompt) if word.endswith(".mp4"))
        shown.append(Path(file).read_bytes())
        return "yes"

    answers.replies[len(CHECKLIST)] = watch_what_is_named
    ingest(config, answers)
    assert shown == [STRIPPED_BYTES]


def test_the_checklist_comes_before_the_sign_off_line_by_line(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    answers = signed_answers()
    ingest(config, answers)
    for index, line in enumerate(CHECKLIST):
        assert line in answers.prompts[index]
    assert "privacy" in answers.prompts[len(CHECKLIST)].casefold()


def test_the_original_is_kept_out_of_the_recordings_and_never_deleted(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    kept = paths.data_root / "assets" / "ingest_originals" / "payday_cycle" / "Screen_Recording.mp4"
    assert kept.read_bytes() == SOURCE_BYTES
    assert sorted(p.name for p in (paths.raw_recordings / "payday_cycle").iterdir()) == [
        "clip_01.mp4"
    ]


def test_originals_with_the_same_name_do_not_overwrite_each_other(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    (paths.raw_recordings / "payday_cycle" / "Screen_Recording.mp4").write_bytes(b"second")
    ingest(config, signed_answers())
    kept = paths.data_root / "assets" / "ingest_originals" / "payday_cycle"
    assert sorted(p.read_bytes() for p in kept.iterdir()) == sorted([SOURCE_BYTES, b"second"])


def test_each_file_in_each_folder_is_handled(ffmpeg, config, paths):
    drop(paths, "payday_cycle", "a.mp4")
    drop(paths, "payday_cycle", "b.mov")
    drop(paths, "app_experience", "c.webm")
    report = ingest(config, Answers(*[*signed_answers().replies] * 3))
    assert sorted(report.signed) == [
        "app_experience/clip_01.mp4",
        "payday_cycle/clip_01.mp4",
        "payday_cycle/clip_02.mp4",
    ]


def test_a_second_run_finds_nothing_new(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    ffmpeg.calls.clear()
    lines = []
    report = ingest(config, Answers(), lines=lines)
    assert report.signed == []
    assert ffmpeg.calls == []
    assert any("raw_recordings" in line for line in lines)


def test_one_feature_can_be_chosen(ffmpeg, config, paths):
    drop(paths, "payday_cycle", "a.mp4")
    drop(paths, "app_experience", "b.mp4")
    report = ingest(config, signed_answers(), feature="app_experience")
    assert report.signed == ["app_experience/clip_01.mp4"]
    assert (paths.raw_recordings / "payday_cycle" / "a.mp4").exists()


def test_a_folder_outside_the_shot_list_is_refused(ffmpeg, config, paths):
    with pytest.raises(CaptureError, match="shot list"):
        ingest(config, Answers(), feature="../../evil")


def test_it_works_with_a_folder_structure_that_does_not_exist_yet(ffmpeg, data_root, config):
    lines = []
    ingest(config, Answers(), lines=lines)
    assert (data_root / "assets" / "raw_recordings" / "smart_basket").is_dir()


# --- What counts as a file to ingest ----------------------------------------------------


@pytest.mark.parametrize("name", ["notes.txt", "clip.mp4.part", "desktop.ini", "x.mp4.lnk"])
def test_other_files_are_left_alone(ffmpeg, config, paths, name):
    drop(paths, "payday_cycle", name)
    assert ingest(config, Answers()).signed == []
    assert ffmpeg.calls == []
    assert (paths.raw_recordings / "payday_cycle" / name).exists()


def test_an_empty_file_is_reported_and_not_ingested(ffmpeg, config, paths):
    (paths.raw_recordings / "payday_cycle" / "empty.mp4").write_bytes(b"")
    lines = []
    report = ingest(config, Answers(), lines=lines)
    assert report.signed == []
    assert ffmpeg.calls == []
    assert any("empty.mp4" in line for line in lines)


def test_a_file_dropped_outside_a_feature_folder_is_pointed_out(ffmpeg, config, paths):
    (paths.raw_recordings / "loose.mp4").write_bytes(SOURCE_BYTES)
    lines = []
    report = ingest(config, Answers(), lines=lines)
    assert report.signed == []
    assert any("loose.mp4" in line for line in lines)


def test_a_feature_folder_that_is_a_link_is_refused(ffmpeg, config, paths, tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "x.mp4").write_bytes(SOURCE_BYTES)
    (paths.raw_recordings / "payday_cycle").rmdir()
    make_junction(paths.raw_recordings / "payday_cycle", outside)
    with pytest.raises(CaptureError, match="link"):
        ingest(config, Answers())
    assert ffmpeg.calls == []
    assert (outside / "x.mp4").exists()


def test_a_file_that_is_a_link_is_not_ingested(ffmpeg, config, paths, tmp_path):
    real = tmp_path / "elsewhere.mp4"
    real.write_bytes(SOURCE_BYTES)
    try:
        (paths.raw_recordings / "payday_cycle" / "x.mp4").symlink_to(real)
    except OSError:
        pytest.skip("creating symlinks needs developer mode on Windows")
    lines = []
    assert ingest(config, Answers(), lines=lines).signed == []
    assert ffmpeg.calls == []
    assert any("link" in line for line in lines)


def test_a_data_root_in_onedrive_is_refused(ffmpeg, tmp_path):
    with pytest.raises(PathConfigError, match="OneDrive"):
        ingest(build_config(tmp_path / "OneDrive" / "data"), Answers())
    assert ffmpeg.calls == []


@pytest.mark.parametrize(
    "name",
    [
        "a&calc.mp4",
        "100%PATH%.mp4",
        "a^b.mp4",
        "a(1).mp4",
        "a b.mp4",
        "a;b.mp4",
        "$(x).mp4",
        "تسجيل الشاشة.mp4",
        "-rf.mp4",
    ],
)
def test_a_dropped_file_name_never_reaches_the_ffmpeg_command(ffmpeg, config, paths, name):
    # npx is a batch file, and cmd.exe reads & % ^ ( ) as code, so the arguments hold only a
    # generated name. The saved clip gets a clean name too, which the manifest requires.
    drop(paths, "payday_cycle", name)
    report = ingest(config, signed_answers())
    assert report.signed == ["payday_cycle/clip_01.mp4"]
    for argument in ffmpeg.args[1:]:
        assert _ARGS_CMD_CANNOT_MISREAD.fullmatch(argument), argument


def test_a_data_root_with_spaces_and_symbols_stays_out_of_the_command(ffmpeg, tmp_path):
    root = tmp_path / "odd & name (1)"
    built = EnginePaths.from_root(root)
    built.ensure_dirs()
    drop(built, "payday_cycle")
    report = ingest(build_config(root), signed_answers())
    assert report.signed == ["payday_cycle/clip_01.mp4"]
    for argument in ffmpeg.args[1:]:
        assert _ARGS_CMD_CANNOT_MISREAD.fullmatch(argument), argument


# --- Stripping metadata -----------------------------------------------------------------


def test_stripping_re_encodes_and_drops_metadata_chapters_and_sound(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    args = ffmpeg.args
    assert args[args.index("-map_metadata") + 1] == "-1"
    assert args[args.index("-map_chapters") + 1] == "-1"
    assert args[args.index("-c:v") + 1] == "libx264"
    assert "copy" not in args
    assert "-an" in args  # a phone's own recorder may have picked up the room


def test_the_bundled_ffmpeg_runs_through_local_npx_from_remotion_work(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    args, kwargs = ffmpeg.calls[-1]
    assert args[0].endswith("npx.cmd")
    assert args[1:4] == ["--no", "remotion", "ffmpeg"]  # --no: never download from the registry
    assert Path(kwargs["cwd"]) == paths.remotion_work


def test_a_configured_ffmpeg_exe_is_used_instead(ffmpeg, tmp_path, data_root, paths):
    tool = tmp_path / "tools" / "ffmpeg.exe"
    tool.parent.mkdir()
    tool.write_bytes(b"MZ")
    data = shipped_data()
    data["paths"]["data_root"] = str(data_root)
    data["render"]["ffmpeg_path"] = str(tool)
    drop(paths, "payday_cycle")
    ingest(EngineConfig.model_validate(data), signed_answers())
    assert ffmpeg.args[0] == str(tool)
    assert "remotion" not in ffmpeg.args


@pytest.mark.parametrize("value", ["ffmpeg.exe", "C:/tools/ffmpeg.cmd", "C:/gone/ffmpeg.exe"])
def test_an_unusable_configured_ffmpeg_is_refused(ffmpeg, data_root, paths, value):
    data = shipped_data()
    data["paths"]["data_root"] = str(data_root)
    data["render"]["ffmpeg_path"] = value
    with pytest.raises(CaptureError, match="ffmpeg_path"):
        strip_metadata(
            paths.raw_recordings / "x.mp4",
            paths.raw_recordings / "y.mp4",
            EngineConfig.model_validate(data),
            paths,
        )
    assert ffmpeg.calls == []


def test_ffmpeg_gets_a_scrubbed_environment(ffmpeg, config, paths, monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "not-for-ffmpeg")
    drop(paths, "payday_cycle")
    ingest(config, signed_answers())
    assert "TELEGRAM_BOT_TOKEN" not in ffmpeg.calls[-1][1]["env"]


def test_no_remotion_work_folder_says_how_to_make_one(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    paths.remotion_work.rmdir()
    report = ingest(config, Answers())
    assert report.signed == []
    assert any("remotion_sync" in reason for reason in report.failed.values())


def test_npx_missing_is_reported(ffmpeg, config, paths, monkeypatch):
    def nothing(name):
        return None

    monkeypatch.setattr(ingest_module, "find_on_path", nothing)
    drop(paths, "payday_cycle")
    report = ingest(config, Answers())
    assert any("npx" in reason for reason in report.failed.values())


@pytest.mark.parametrize(
    "breakage", [{"returncode": 1}, {"writes_output": False}, {"timeout": True}]
)
def test_a_failed_strip_leaves_the_file_unsigned_and_in_place(ffmpeg, config, paths, breakage):
    for name, value in breakage.items():
        setattr(ffmpeg, name, value)
    source = drop(paths, "payday_cycle")
    report = ingest(config, Answers())
    assert report.signed == []
    assert report.failed
    assert source.read_bytes() == SOURCE_BYTES
    assert manifest_of(paths).clips == []
    assert not (paths.data_root / "assets" / "ingest_tmp").exists() or not list(
        (paths.data_root / "assets" / "ingest_tmp").iterdir()
    )


def test_ffmpeg_output_stays_out_of_the_failure_message(ffmpeg, config, paths):
    ffmpeg.returncode = 1
    drop(paths, "payday_cycle")
    report = ingest(config, Answers())
    assert not any("secret-ish" in reason for reason in report.failed.values())


def test_one_bad_file_does_not_stop_the_others(ffmpeg, config, paths):
    ffmpeg.fails_on_call = 1  # folders go in shot list order, so payday_cycle comes first
    drop(paths, "payday_cycle", "bad.mp4")
    drop(paths, "app_experience", "good.mp4")
    report = ingest(config, signed_answers())
    assert report.signed == ["app_experience/clip_01.mp4"]
    assert list(report.failed) == ["payday_cycle/bad.mp4"]


# --- Sign-off: nothing is recorded before the owner's answer ----------------------------


@pytest.mark.parametrize("line_number", range(len(CHECKLIST)))
def test_refusing_any_checklist_line_leaves_the_file_unusable(ffmpeg, config, paths, line_number):
    source = drop(paths, "payday_cycle")
    report = ingest(config, Answers(*["yes"] * line_number, "no"))
    assert report.signed == []
    assert report.declined == ["payday_cycle/Screen_Recording.mp4"]
    assert manifest_of(paths).clips == []
    assert source.exists()
    assert not (paths.raw_recordings / "payday_cycle" / "clip_01.mp4").exists()


@pytest.mark.parametrize("reply", ["no", "", "y", "later"])
def test_no_privacy_answer_leaves_the_file_unusable(ffmpeg, config, paths, reply):
    source = drop(paths, "payday_cycle")
    report = ingest(config, Answers(*ALL_LINES, reply))
    assert report.signed == []
    assert manifest_of(paths).clips == []
    assert source.exists()
    with pytest.raises(ClipRejected, match="not in the manifest"):
        manifest_of(paths).verified_clip("payday_cycle/clip_01.mp4", paths.raw_recordings)


def test_a_closed_input_signs_nothing(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    report = ingest(config, Answers(*ALL_LINES, EOFError))
    assert report.signed == []
    assert manifest_of(paths).clips == []


def test_an_unsigned_file_is_asked_about_again_next_time(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, Answers("no"))
    assert ingest(config, signed_answers()).signed == ["payday_cycle/clip_01.mp4"]


def test_ctrl_c_signs_nothing_and_cleans_up(ffmpeg, config, paths):
    source = drop(paths, "payday_cycle")
    with pytest.raises(KeyboardInterrupt):
        ingest(config, Answers(*ALL_LINES, KeyboardInterrupt))
    assert manifest_of(paths).clips == []
    assert source.exists()
    temp = paths.data_root / "assets" / "ingest_tmp"
    assert not temp.exists() or not list(temp.iterdir())


def test_a_file_changed_after_the_owner_watched_it_is_not_signed(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    answers = signed_answers()
    temp = paths.data_root / "assets" / "ingest_tmp"

    def swap_the_cleaned_copy():
        next(temp.rglob("output.mp4")).write_bytes(b"something else entirely")
        return "yes"

    answers.replies[len(CHECKLIST)] = swap_the_cleaned_copy
    report = ingest(config, answers)
    assert report.signed == []
    assert report.failed
    assert manifest_of(paths).clips == []


def test_an_original_that_cannot_be_moved_does_not_undo_the_sign_off(
    ffmpeg, config, paths, monkeypatch
):
    def locked(*args):
        raise PermissionError("in use")

    monkeypatch.setattr(ingest_module, "_keep_original", locked)
    source = drop(paths, "payday_cycle")
    lines = []
    report = ingest(config, signed_answers(), lines=lines)
    assert report.signed == ["payday_cycle/clip_01.mp4"]
    assert report.failed == {}
    assert source.exists()
    assert any(source.name in line for line in lines)


def test_the_app_version_is_recorded_and_a_bad_one_signs_nothing(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    report = ingest(config, signed_answers(version="1.0;reboot"))
    assert report.signed == []
    assert manifest_of(paths).clips == []
    assert ingest(config, signed_answers(version="1.4.2+9")).signed
    assert manifest_of(paths).clips[0].app_version == "1.4.2+9"


def test_the_app_version_can_be_given_once_for_the_whole_run(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    ingest(config, Answers(*ALL_LINES, "yes"), app_version="3.0.0")
    assert manifest_of(paths).clips[0].app_version == "3.0.0"


# --- The sign-off cannot be reached without the checklist -------------------------------


def _record(paths, config, confirmation, feature="payday_cycle", name="clip_01.mp4", **overrides):
    file = paths.raw_recordings / feature / name
    if not file.exists():
        file.write_bytes(SOURCE_BYTES)
    options = {
        "sha256": sha256_file(file),
        "answers": OwnerAnswers(privacy_clean=True),
        "app_version": "1.4.2",
        "config": config,
        "final": False,
    }
    options.update(overrides)
    return record_clip(paths, file, confirmation=confirmation, **options)


@pytest.mark.parametrize("confirmation", [None, True, "yes", object()])
def test_a_clip_cannot_be_signed_without_a_checklist_confirmation(config, paths, confirmation):
    with pytest.raises(ClipRejected, match="checklist"):
        _record(paths, config, confirmation)
    assert manifest_of(paths).clips == []


def test_a_partly_confirmed_checklist_gives_no_confirmation():
    checklist = Checklist("payday_cycle")
    checklist.confirm(CHECKLIST[:-1], ask=lambda prompt: "yes")
    with pytest.raises(ChecklistRefused):
        checklist.confirmation()


def test_a_confirmation_for_another_feature_does_not_count(config, paths):
    with pytest.raises(ClipRejected, match="checklist"):
        _record(paths, config, confirmed("app_experience"))


def test_a_no_privacy_answer_cannot_be_recorded(config, paths):
    with pytest.raises(ClipRejected, match="privacy"):
        _record(paths, config, confirmed(), answers=OwnerAnswers(privacy_clean=False))
    assert manifest_of(paths).clips == []


def test_a_hash_that_differs_from_the_file_is_refused(config, paths):
    with pytest.raises(ClipRejected, match="signed hash"):
        _record(paths, config, confirmed(), sha256="0" * 64)
    assert manifest_of(paths).clips == []


def test_a_file_outside_the_recordings_folder_cannot_be_signed(config, paths, tmp_path):
    outside = tmp_path / "x.mp4"
    outside.write_bytes(SOURCE_BYTES)
    with pytest.raises(ClipRejected, match="feature folder"):
        record_clip(
            paths,
            outside,
            sha256=sha256_file(outside),
            confirmation=confirmed(),
            answers=OwnerAnswers(privacy_clean=True),
            app_version="1.4.2",
            config=config,
            final=False,
        )


def _functions_named_in_source(name: str) -> list[str]:
    found = []
    for path in (ENGINE_ROOT / "phone_capture").glob("*.py"):
        for node in ast.walk(ast.parse(path.read_bytes())):
            if isinstance(node, ast.Call) and getattr(node.func, "id", None) == name:
                found.append(path.name)
            if isinstance(node, ast.Call) and getattr(node.func, "attr", None) == name:
                found.append(path.name)
    return found


def test_only_the_checklist_issues_a_confirmation_and_only_ingest_signs():
    assert _functions_named_in_source("ChecklistConfirmation") == ["ingest.py"]
    assert _functions_named_in_source("add_clip") == ["ingest.py"]
    assert _functions_named_in_source("ClipEntry") == ["ingest.py"]


# --- smart_basket: masks are part of the sign-off ---------------------------------------


def smart_answers(*mask_replies, version="1.4.2"):
    return Answers(*ALL_LINES, "yes", *mask_replies, version)


def test_a_smart_basket_clip_records_masks_and_their_confirmation(ffmpeg, config, paths):
    drop(paths, "smart_basket")
    report = ingest(config, smart_answers(MASK, "0.1,0.4,0.5,0.05", "", "yes"))
    assert report.signed == ["smart_basket/clip_01.mp4"]
    entry = manifest_of(paths).clips[0]
    assert entry.store_names_masked is True
    assert [region.y for region in entry.mask_regions] == [0.2, 0.4]


def test_a_smart_basket_clip_with_no_masks_is_not_signed(ffmpeg, config, paths):
    drop(paths, "smart_basket")
    report = ingest(config, Answers(*ALL_LINES, "yes", ""))
    assert report.signed == []
    assert report.declined == ["smart_basket/Screen_Recording.mp4"]
    assert manifest_of(paths).clips == []


@pytest.mark.parametrize("reply", ["no", "", "y"])
def test_a_smart_basket_clip_with_masks_not_confirmed_is_not_signed(ffmpeg, config, paths, reply):
    drop(paths, "smart_basket")
    report = ingest(config, Answers(*ALL_LINES, "yes", MASK, "", reply))
    assert report.signed == []
    assert manifest_of(paths).clips == []


@pytest.mark.parametrize(
    "bad",
    [
        "abc",
        "0.1 0.2 0.5",
        "0.1 0.2 0.5 0.05 9",
        "nan 0.2 0.5 0.05",
        "inf 0.2 0.5 0.05",
        "0.9 0.2 0.5 0.05",  # runs off the clip
        "0.1 0.2 0.001 0.001",  # too small to hide a name
        "-1 0.2 0.5 0.05",
        "0.1 0.2 1e999 0.05",
    ],
)
def test_a_bad_mask_is_asked_again_and_never_stored(ffmpeg, config, paths, bad):
    drop(paths, "smart_basket")
    report = ingest(config, smart_answers(bad, MASK, "", "yes"))
    assert report.signed == ["smart_basket/clip_01.mp4"]
    assert len(manifest_of(paths).clips[0].mask_regions) == 1


def test_only_bad_masks_mean_no_sign_off(ffmpeg, config, paths):
    drop(paths, "smart_basket")
    report = ingest(config, Answers(*ALL_LINES, "yes", "abc", ""))
    assert report.signed == []


def test_a_smart_basket_record_without_masks_is_refused_at_the_last_step(config, paths):
    for answers in (
        OwnerAnswers(privacy_clean=True),
        OwnerAnswers(privacy_clean=True, store_names_masked=True),
    ):
        with pytest.raises((ClipRejected, ValueError)):
            _record(
                paths,
                config,
                confirmed("smart_basket"),
                feature="smart_basket",
                answers=answers,
            )
    assert manifest_of(paths).clips == []


def test_other_folders_are_not_asked_about_masks(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    answers = signed_answers()
    ingest(config, answers)
    assert not any("mask region" in prompt.casefold() for prompt in answers.prompts)
    assert manifest_of(paths).clips[0].mask_regions == []


def test_the_owner_is_told_the_label_comes_later(ffmpeg, config, paths):
    drop(paths, "smart_basket")
    lines = []
    ingest(config, smart_answers(MASK, "", "yes"), lines=lines)
    assert any("illustrative prices" in line for line in lines)


# --- The launch gate: everything before it is a test clip -------------------------------


def test_files_ingested_while_the_gate_is_closed_are_test_clips(ffmpeg, config, paths):
    drop(paths, "payday_cycle", "final_clip_07.mp4")
    report = ingest(config, signed_answers())
    assert report.signed == ["payday_cycle/clip_08.mp4"]
    assert not is_final_clip(report.signed[0])


def test_asking_for_final_clips_while_the_gate_is_closed_is_refused(ffmpeg, config, paths):
    drop(paths, "payday_cycle")
    with pytest.raises(CaptureError, match="launch gate"):
        ingest(config, Answers(), final=True)
    assert ffmpeg.calls == []


def test_final_clips_are_possible_once_the_gate_is_met(
    ffmpeg, data_root, paths, tmp_path, monkeypatch
):
    config = build_gate_met_config(monkeypatch, tmp_path, data_root)
    drop(paths, "payday_cycle")
    report = ingest(config, signed_answers(), final=True)
    assert report.signed == ["payday_cycle/final_clip_01.mp4"]
    assert is_final_clip("payday_cycle/final_clip_01.mp4")


def test_a_final_clip_cannot_be_recorded_while_the_gate_is_closed(config, paths):
    with pytest.raises(ClipRejected, match="launch gate"):
        _record(paths, config, confirmed(), name="final_clip_01.mp4", final=True)
    with pytest.raises(ClipRejected, match="launch gate"):
        _record(paths, config, confirmed(), name="clip_01.mp4", final=True)
    assert manifest_of(paths).clips == []


def test_a_test_clip_cannot_carry_the_final_name(config, paths):
    with pytest.raises(ClipRejected, match="final"):
        _record(paths, config, confirmed(), name="final_clip_01.mp4", final=False)


@pytest.mark.parametrize(
    ("path", "final"),
    [
        ("payday_cycle/clip_01.mp4", False),
        ("payday_cycle/final_clip_01.mp4", True),
        ("payday_cycle/Screen_Recording.mp4", False),
        ("payday_cycle/final_clip_x.mp4", False),
        ("payday_cycle/final_clip_01.mov", False),
        ("payday_cycle/not_final_clip_01.mp4", False),
    ],
)
def test_a_clip_is_final_only_with_the_exact_final_name(path, final):
    assert is_final_clip(path) is final


def test_a_public_reel_refuses_a_test_clip_and_a_test_reel_takes_either(
    ffmpeg, data_root, paths, tmp_path, monkeypatch
):
    config = build_gate_met_config(monkeypatch, tmp_path, data_root)
    drop(paths, "payday_cycle", "a.mp4")
    ingest(config, signed_answers(), final=True)
    drop(paths, "payday_cycle", "b.mp4")
    ingest(config, signed_answers())
    final, test = manifest_of(paths).clips
    assert (final.path, test.path) == ("payday_cycle/final_clip_01.mp4", "payday_cycle/clip_02.mp4")
    check_clip_for_reel(final, paths, test_reel=False)
    check_clip_for_reel(final, paths, test_reel=True)
    check_clip_for_reel(test, paths, test_reel=True)
    with pytest.raises(ClipRejected, match="test clip"):
        check_clip_for_reel(test, paths, test_reel=False)


def test_the_saved_entries_still_satisfy_the_shared_schema(ffmpeg, config, paths):
    drop(paths, "smart_basket")
    ingest(config, smart_answers(MASK, "", "yes"))
    entry = manifest_of(paths).clips[0]
    assert ClipEntry.model_validate(entry.model_dump()) == entry
