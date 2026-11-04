"""What Round 2's review of the render step and the MP4 check proved, and the fixes for it."""

import os
import struct

import pytest
from conftest import make_junction
from render_support import Rig, box, build_mp4, moov, mvhd, tkhd, trak
from state_support import Bench, Clock, make_video

from core.brand_gate import FULL_NAME_EN
from core.mp4_check import Mp4Error, Mp4NotConformed, check_output
from core.render import RenderError, RenderFailed, RenderRefused, render_reel
from core.state import (
    ActionRefused,
    ReelState,
    RefusalReason,
    StateStore,
    read_render_receipt,
    sha256_of_file,
)

LIMITS = {"width": 1080, "height": 1920, "duration_ms": 30_000, "max_bytes": 48_000_000}
FTYP = box(b"ftyp", b"isom\x00\x00\x02\x00isomiso2avc1mp41")


@pytest.fixture
def rig(tmp_path, monkeypatch) -> Rig:
    return Rig(tmp_path, monkeypatch)


def render(rig, request=None, *, store=None):
    return render_reel(
        request if request is not None else rig.request(),
        store=store or rig.reels,
        config=rig.config,
        paths=rig.paths,
        engine_root=rig.engine,
    )


# --- The MP4 check -------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "options",
    [{"mdat": b""}, {"video_samples": 0}, {"audio_samples": 0}],
    ids=["empty mdat", "no video samples", "no audio samples"],
)
def test_a_file_with_no_media_is_refused(tmp_path, options):
    file = tmp_path / "a.mp4"
    file.write_bytes(build_mp4(**options))
    with pytest.raises(Mp4NotConformed, match="no media"):
        check_output(file, **LIMITS)


def test_a_track_with_no_sample_table_counts_as_no_media(tmp_path):
    stsd = box(b"stsd", bytes(4) + struct.pack(">I", 1) + box(b"mp4a", bytes(16)))
    hdlr = box(b"hdlr", bytes(8) + b"soun" + bytes(13))
    audio = box(b"trak", tkhd(0, 0) + box(b"mdia", hdlr + box(b"minf", box(b"stbl", stsd))))
    video = trak(b"vide", b"avc1", width=1080, height=1920)
    file = tmp_path / "a.mp4"
    file.write_bytes(FTYP + box(b"moov", mvhd(30_000) + video + audio) + box(b"mdat", bytes(64)))
    with pytest.raises(Mp4NotConformed, match="no media"):
        check_output(file, **LIMITS)


def test_a_cut_off_file_with_an_open_ended_mdat_is_refused(tmp_path):
    # mdat with size 0 means "to the end of the file", so no cut can ever look short.
    file = tmp_path / "a.mp4"
    file.write_bytes(FTYP + moov() + struct.pack(">I", 0) + b"mdat" + b"x" * 10)
    with pytest.raises(Mp4NotConformed, match="no size"):
        check_output(file, **LIMITS)


@pytest.mark.parametrize(
    "extra",
    [
        trak(b"vide", b"hvc1", width=640, height=360),
        trak(b"vide", b"avc1", width=1080, height=1920),
    ],
    ids=["another size and codec", "the same size and codec"],
)
def test_a_second_video_track_is_refused(tmp_path, extra):
    tracks = trak(b"vide", b"avc1", width=1080, height=1920) + trak(b"soun", b"mp4a") + extra
    file = tmp_path / "a.mp4"
    file.write_bytes(FTYP + box(b"moov", mvhd(30_000) + tracks) + box(b"mdat", bytes(64)))
    with pytest.raises(Mp4NotConformed, match="2 video"):
        check_output(file, **LIMITS)


def test_a_second_audio_track_is_refused(tmp_path):
    tracks = (
        trak(b"vide", b"avc1", width=1080, height=1920)
        + trak(b"soun", b"mp4a")
        + trak(b"soun", b"mp4a")
    )
    file = tmp_path / "a.mp4"
    file.write_bytes(FTYP + box(b"moov", mvhd(30_000) + tracks) + box(b"mdat", bytes(64)))
    with pytest.raises(Mp4NotConformed, match="2 audio"):
        check_output(file, **LIMITS)


def test_a_landscape_stream_declared_portrait_in_tkhd_is_refused(tmp_path):
    entry = box(b"avc1", bytes(24) + struct.pack(">HH", 1920, 1080) + bytes(50))
    stsd = box(b"stsd", bytes(4) + struct.pack(">I", 1) + entry)
    stsz = box(b"stsz", bytes(4) + struct.pack(">II", 0, 1) + bytes(4))
    hdlr = box(b"hdlr", bytes(8) + b"vide" + bytes(13))
    mdia = box(b"mdia", hdlr + box(b"minf", box(b"stbl", stsd + stsz)))
    video = box(b"trak", tkhd(1080, 1920) + mdia)
    file = tmp_path / "a.mp4"
    file.write_bytes(
        FTYP + box(b"moov", mvhd(30_000) + video + trak(b"soun", b"mp4a")) + box(b"mdat", bytes(64))
    )
    with pytest.raises(Mp4NotConformed, match="1920x1080"):
        check_output(file, **LIMITS)


def test_a_stream_entry_too_short_to_give_a_size_is_refused(tmp_path):
    stsd = box(b"stsd", bytes(4) + struct.pack(">I", 1) + box(b"avc1", bytes(16)))
    stsz = box(b"stsz", bytes(4) + struct.pack(">II", 0, 1) + bytes(4))
    hdlr = box(b"hdlr", bytes(8) + b"vide" + bytes(13))
    mdia = box(b"mdia", hdlr + box(b"minf", box(b"stbl", stsd + stsz)))
    video = box(b"trak", tkhd(1080, 1920) + mdia)
    file = tmp_path / "a.mp4"
    file.write_bytes(
        FTYP + box(b"moov", mvhd(30_000) + video + trak(b"soun", b"mp4a")) + box(b"mdat", bytes(64))
    )
    with pytest.raises(Mp4NotConformed, match="stream"):
        check_output(file, **LIMITS)


@pytest.mark.parametrize("options", [{"edit_list": True}, {"audio_edit_list": True}], ids=str)
def test_an_edit_list_on_either_track_is_refused(tmp_path, options):
    file = tmp_path / "a.mp4"
    file.write_bytes(build_mp4(**options))
    with pytest.raises(Mp4Error, match="edit list"):
        check_output(file, **LIMITS)


# --- Reuse ---------------------------------------------------------------------------------------


def test_a_swapped_file_at_the_final_name_is_not_reused(rig):
    first = render(rig)
    assert first.reused is False
    first.path.write_bytes(build_mp4(mdat=b"a different video, say with no watermark"))

    second = render(rig)

    assert second.reused is False
    assert second.sha256 == first.sha256
    assert sha256_of_file(second.path) == first.sha256


def test_a_file_whose_receipt_is_gone_is_rendered_again(rig):
    first = render(rig)
    first.path.with_name(first.path.name + ".receipt.json").unlink()
    assert render(rig).reused is False
    assert read_render_receipt(first.path) is not None


def test_a_receipt_describes_the_finished_file(rig):
    result = render(rig)
    receipt = read_render_receipt(result.path)
    assert receipt.reel_id == rig.request().reel_id
    assert receipt.revision == rig.request().revision
    assert receipt.sha256 == result.sha256 == sha256_of_file(result.path)
    assert receipt.content_hash == result.content_hash
    assert receipt.watermark is True


def test_a_failed_move_leaves_neither_file_nor_receipt(rig, monkeypatch):
    real_replace = os.replace

    def replace_refusing_the_final_file(source, target):
        if str(target).endswith(".mp4"):
            raise PermissionError("locked")
        real_replace(source, target)

    monkeypatch.setattr("core.render.os.replace", replace_refusing_the_final_file)
    with pytest.raises(RenderFailed, match="locked"):
        render(rig)
    assert list(rig.paths.renders.iterdir()) == []


# --- The test flag comes from the stored row -----------------------------------------------------


def store_and_bench(rig, tmp_path):
    clock = Clock()
    store = StateStore(tmp_path / "state.db", clock=clock)
    return store, Bench(store, rig.config, make_video(tmp_path), clock)


def test_a_test_row_renders_watermarked_and_records_even_with_the_gate_met(rig, tmp_path):
    rig.use_live_config()
    store, bench = store_and_bench(rig, tmp_path)
    with store:
        reel = bench.voiced(is_test=True)
        request = rig.request(reel_id=reel.reel_id, revision=reel.revision)

        result = render(rig, request, store=store)

        assert rig.fake.renders[-1].props["watermark"] is True
        assert rig.fake.renders[-1].props["brand"]["name_en"] != FULL_NAME_EN
        assert store.record_rendered(
            reel.reel_id, reel.revision, result.path, result.content_hash, rig.config
        )
        assert store.get_reel(reel.reel_id).state == ReelState.RENDERED


def test_a_live_row_renders_clean_and_records(rig, tmp_path):
    rig.use_live_config()
    store, bench = store_and_bench(rig, tmp_path)
    with store:
        reel = bench.voiced(is_test=False)
        request = rig.request(reel_id=reel.reel_id, revision=reel.revision)

        result = render(rig, request, store=store)

        assert rig.fake.renders[-1].props["watermark"] is False
        assert store.record_rendered(
            reel.reel_id, reel.revision, result.path, result.content_hash, rig.config
        )


def test_a_file_rendered_for_a_test_row_cannot_be_recorded_on_a_live_one(rig, tmp_path):
    rig.use_live_config()
    store, bench = store_and_bench(rig, tmp_path)
    with store:
        test_reel = bench.voiced(is_test=True)
        live_reel = bench.voiced(is_test=False)
        request = rig.request(reel_id=test_reel.reel_id, revision=test_reel.revision)
        result = render(rig, request, store=store)
        with pytest.raises(ActionRefused) as refused:
            store.record_rendered(
                live_reel.reel_id, live_reel.revision, result.path, result.content_hash, rig.config
            )
        assert refused.value.reason == RefusalReason.RENDER_UNPROVEN
        assert store.get_reel(live_reel.reel_id).state == ReelState.VOICED


@pytest.mark.parametrize(
    "walk",
    [
        lambda bench: bench.new_reel(),
        lambda bench: bench.rendered(),
    ],
    ids=["not voiced yet", "already rendered"],
)
def test_a_reel_not_waiting_to_be_rendered_is_refused(rig, tmp_path, walk):
    rig.use_live_config()
    store, bench = store_and_bench(rig, tmp_path)
    with store:
        reel = walk(bench)
        with pytest.raises(RenderRefused, match="not waiting"):
            render(rig, rig.request(reel_id=reel.reel_id, revision=reel.revision), store=store)
    assert rig.fake.subprocess_count == 0


def test_an_unknown_reel_or_an_old_revision_is_refused(rig, tmp_path):
    rig.use_live_config()
    store, bench = store_and_bench(rig, tmp_path)
    with store:
        reel = bench.voiced()
        with pytest.raises(RenderRefused, match="not waiting"):
            render(rig, rig.request(reel_id="nosuchreel", revision=1), store=store)
        with pytest.raises(RenderRefused, match="not waiting"):
            render(rig, rig.request(reel_id=reel.reel_id, revision=2), store=store)
    assert rig.fake.subprocess_count == 0


# --- Inputs and the command ----------------------------------------------------------------------


def test_the_render_always_asks_for_an_audio_track(rig):
    render(rig)
    assert "--enforce-audio-track" in rig.fake.renders[0].command


@pytest.mark.parametrize(
    "bad",
    [
        "a&calc",
        "-x",
        "--props=evil",
        "a b",
        'a"b',
        "a|b",
        "a^b",
        "%PATH%",
        "a\nb",
        "a\n",
        "a/../b",
        "..",
        "a\\b",
        "CON",
        "nul",
        "COM1",
        "a.b",
        "a" * 41,
        "١٢٣",
        "a:b",
    ],
)
def test_a_reel_id_never_reaches_a_command_line(rig, bad):
    with pytest.raises(RenderError):
        render(rig, rig.request(reel_id=bad))
    assert rig.fake.subprocess_count == 0


def test_voiceover_and_music_cannot_collide_in_public(rig):
    def change(data):
        data["audio"]["music_enabled"] = True
        data["audio"]["music_library"] = "Licensed Library"

    rig.use_config(change)
    (rig.paths.voiceovers / "music").mkdir()
    (rig.paths.voiceovers / "music" / "x.wav").write_bytes(b"the narration")
    (rig.paths.bg_music / "x.wav").write_bytes(b"the music")
    with pytest.raises(RenderRefused, match="one path"):
        render(rig, rig.request(voiceover="music/x.wav", music="x.wav"))
    assert rig.fake.subprocess_count == 0


def test_a_renders_folder_swapped_during_the_render_is_noticed(rig, tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()

    def swap_then_write(target):
        rig.paths.renders.rmdir()
        make_junction(rig.paths.renders, outside)
        target.write_bytes(build_mp4())

    rig.fake.conform_writer = swap_then_write
    with pytest.raises(RenderFailed, match="renders"):
        render(rig)
    assert list(outside.iterdir()) == []


def test_only_allow_listed_files_reach_public(rig):
    stray = rig.engine / "remotion_studio" / "public" / "clips" / "unsigned"
    stray.mkdir(parents=True)
    (stray / "raw_with_account_data.mp4").write_bytes(b"raw")
    render(rig)
    assert not any("raw_with_account" in name for name in rig.fake.renders[-1].public_files)


def test_a_corrupt_stamp_means_a_clean_install_and_a_render(rig):
    render(rig)
    installs = len([call for call in rig.fake.run_calls if "ci" in call])
    (rig.paths.remotion_work / ".synced-lock.sha256").write_bytes(b"\xff\xfe\x00")
    render(rig, rig.request(reel_id="R-other"))  # another reel, so nothing is reused
    assert len([call for call in rig.fake.run_calls if "ci" in call]) == installs + 1
