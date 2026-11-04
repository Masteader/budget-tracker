"""The pure-Python MP4 reader (spec Section 8.6, plan Section 2.4, task G2), with no FFmpeg."""

import struct

import pytest
from render_support import MB, box, build_mp4, large_box, moov, mvhd, trak, write_mp4_of_size

from core.mp4_check import (
    Mp4Error,
    Mp4NotConformed,
    Mp4TooLarge,
    NotMp4,
    TruncatedMp4,
    check_output,
    read_mp4,
)

LIMIT = 48 * MB
FTYP = box(b"ftyp", b"isom" + bytes(4) + b"isomavc1")


@pytest.fixture
def file(tmp_path):
    return tmp_path / "reel.mp4"


def check(path, **overrides):
    expected = {"width": 1080, "height": 1920, "duration_ms": 30_000, "max_bytes": LIMIT}
    expected.update(overrides)
    return check_output(path, **expected)


# --- What it reads ---------------------------------------------------------------------


@pytest.mark.parametrize("version", [0, 1], ids=["32-bit fields", "64-bit fields"])
def test_it_reads_size_duration_and_codecs(file, version):
    data = build_mp4(width=1080, height=1920, duration_ms=30_500, version=version)
    file.write_bytes(data)
    info = read_mp4(file)
    assert info.width == 1080
    assert info.height == 1920
    assert info.duration_ms == 30_500
    assert info.size_bytes == len(data)
    assert info.video_codec == "avc1"
    assert info.audio_codec == "mp4a"


def test_it_uses_the_video_track_when_the_audio_track_comes_first(file):
    audio = trak(b"soun", b"mp4a")
    video = trak(b"vide", b"avc1", width=1080, height=1920)
    file.write_bytes(FTYP + box(b"moov", mvhd(1000) + audio + video) + box(b"mdat", bytes(8)))
    info = read_mp4(file)
    assert (info.width, info.height) == (1080, 1920)


def test_duration_uses_the_file_timescale(file):
    header = box(b"moov", mvhd(45_000, timescale=1500) + trak(b"vide", b"avc1"))
    file.write_bytes(FTYP + header + box(b"mdat"))
    assert read_mp4(file).duration_ms == 30_000


def test_moov_before_mdat_is_reported(file):
    file.write_bytes(build_mp4(moov_first=True))
    assert read_mp4(file).moov_before_mdat is True
    file.write_bytes(build_mp4(moov_first=False))
    assert read_mp4(file).moov_before_mdat is False


def test_an_edit_list_in_any_track_is_reported(file):
    file.write_bytes(build_mp4())
    assert read_mp4(file).has_edit_list is False
    file.write_bytes(build_mp4(edit_list=True))
    assert read_mp4(file).has_edit_list is True


def test_a_64_bit_mdat_and_free_boxes_are_fine(file):
    data = FTYP + box(b"free", bytes(8)) + moov() + box(b"free")
    file.write_bytes(data + large_box(b"mdat", bytes(32)))
    assert check(file).moov_before_mdat is True


def test_a_last_box_running_to_the_end_of_the_file_is_fine(file):
    file.write_bytes(FTYP + moov() + struct.pack(">I", 0) + b"mdat" + bytes(32))
    assert read_mp4(file).moov_before_mdat is True


# --- Output that passes and output that does not ---------------------------------------


def test_a_conforming_file_passes(file):
    file.write_bytes(build_mp4())
    assert check(file).size_bytes == file.stat().st_size


@pytest.mark.parametrize(
    ("options", "problem"),
    [
        ({"moov_first": False}, "moov"),
        ({"edit_list": True}, "edit list"),
        ({"width": 720}, "1080"),
        ({"height": 1280}, "1920"),
        ({"width": 1920, "height": 1080}, "1080"),
        ({"duration_ms": 12_000}, "long"),
        ({"duration_ms": 31_000}, "long"),
        ({"video_codec": b"hvc1"}, "H.264"),
        ({"audio": False}, "AAC"),
    ],
)
def test_output_that_does_not_conform_is_refused(file, options, problem):
    file.write_bytes(build_mp4(**options))
    with pytest.raises(Mp4NotConformed, match=problem):
        check(file)


def test_small_rounding_in_the_duration_is_fine(file):
    file.write_bytes(build_mp4(duration_ms=30_400))
    assert check(file).duration_ms == 30_400


def test_a_file_with_no_video_track_is_refused(file):
    file.write_bytes(FTYP + box(b"moov", mvhd(30_000) + trak(b"soun", b"mp4a")) + box(b"mdat"))
    with pytest.raises(Mp4NotConformed, match="video"):
        check(file)


# --- Oversized -------------------------------------------------------------------------


def test_exactly_the_limit_passes(file):
    write_mp4_of_size(file, LIMIT)
    assert check(file).size_bytes == LIMIT


def test_one_byte_over_the_limit_is_too_large(file):
    write_mp4_of_size(file, LIMIT + 1)
    with pytest.raises(Mp4TooLarge):
        check(file)


def test_a_file_over_the_telegram_limit_is_too_large(file):
    write_mp4_of_size(file, 50 * MB + 1)
    with pytest.raises(Mp4TooLarge):
        check(file)


def test_a_file_that_is_wrong_as_well_as_too_large_is_reported_as_wrong(file):
    # A lower bitrate cannot fix the wrong size of picture, so it must not cause a re-render.
    write_mp4_of_size(file, LIMIT + 1, width=720)
    with pytest.raises(Mp4NotConformed):
        check(file)


# --- Truncated -------------------------------------------------------------------------


@pytest.mark.parametrize("moov_first", [True, False], ids=["moov first", "mdat first"])
def test_a_file_cut_at_any_byte_is_never_accepted(file, moov_first):
    data = build_mp4(moov_first=moov_first)
    for cut in range(len(data)):
        file.write_bytes(data[:cut])
        with pytest.raises(Mp4Error):
            read_mp4(file)


def test_a_cut_inside_mdat_is_truncated(file):
    file.write_bytes(build_mp4()[:-10])
    with pytest.raises(TruncatedMp4, match="mdat"):
        read_mp4(file)


def test_a_cut_inside_moov_is_truncated(file):
    file.write_bytes(build_mp4(moov_first=False)[:-10])
    with pytest.raises(TruncatedMp4, match="moov"):
        read_mp4(file)


def test_a_file_cut_just_after_moov_is_truncated(file):
    file.write_bytes(FTYP + moov())
    with pytest.raises(TruncatedMp4, match="mdat"):
        read_mp4(file)


def test_a_file_cut_just_after_mdat_is_truncated(file):
    file.write_bytes(FTYP + box(b"mdat", bytes(8)))
    with pytest.raises(TruncatedMp4, match="moov"):
        read_mp4(file)


def test_a_truncated_file_stays_truncated_through_the_output_check(file):
    file.write_bytes(build_mp4()[:-1])
    with pytest.raises(TruncatedMp4):
        check(file)


# --- Not an MP4 ------------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw",
    [
        b"",
        b"\x00",
        b"not a video",
        b"plain text that is long enough to read a header from",
        b"\x1a\x45\xdf\xa3" + bytes(32),  # WebM
        b"\x89PNG\r\n\x1a\n" + bytes(32),
        b"RIFF\x00\x00\x00\x00AVI " + bytes(32),
        bytes(64),
        moov() + box(b"mdat"),  # right boxes, but no ftyp
    ],
)
def test_other_files_are_not_mp4(file, raw):
    file.write_bytes(raw)
    with pytest.raises(NotMp4):
        read_mp4(file)


def test_a_missing_file_is_an_mp4_error(file):
    with pytest.raises(Mp4Error, match="read"):
        read_mp4(file)


def test_a_folder_is_an_mp4_error(tmp_path):
    with pytest.raises(Mp4Error):
        read_mp4(tmp_path)


# --- Broken boxes never crash or hang the reader ---------------------------------------


@pytest.mark.parametrize(
    "tail",
    [
        struct.pack(">I", 4) + b"free",  # smaller than its own header
        struct.pack(">I", 1) + b"free" + struct.pack(">Q", 8),  # 64-bit size under its header
        struct.pack(">I", 1) + b"free",  # 64-bit size cut off
        b"mo",  # less than a header
    ],
)
def test_a_broken_top_level_box_is_refused(file, tail):
    file.write_bytes(FTYP + moov() + box(b"mdat") + tail)
    with pytest.raises(Mp4Error):
        read_mp4(file)


@pytest.mark.parametrize(
    "payload",
    [
        struct.pack(">I", 0) + b"trak",  # to-end size is for the top level only
        struct.pack(">I", 4) + b"trak",  # would never move forward
        struct.pack(">I", 500) + b"trak",  # runs past its parent
        struct.pack(">I", 8) + b"mvhd",  # too short to hold a duration
        box(b"mvhd", bytes(4)) + trak(b"vide", b"avc1"),
        box(b"mvhd", bytes(30)) + trak(b"vide", b"avc1"),  # timescale of zero
        mvhd(1000) + box(b"trak", box(b"tkhd", bytes(8)) + box(b"mdia")),
    ],
)
def test_a_broken_box_inside_moov_is_refused(file, payload):
    file.write_bytes(FTYP + box(b"moov", payload) + box(b"mdat"))
    with pytest.raises(Mp4Error):
        read_mp4(file)


def test_a_moov_with_no_movie_header_is_refused(file):
    file.write_bytes(FTYP + box(b"moov", trak(b"vide", b"avc1")) + box(b"mdat"))
    with pytest.raises(Mp4Error, match="mvhd"):
        read_mp4(file)


def test_two_moov_boxes_are_refused(file):
    file.write_bytes(FTYP + moov() + moov(width=720) + box(b"mdat"))
    with pytest.raises(Mp4Error, match="moov"):
        read_mp4(file)
