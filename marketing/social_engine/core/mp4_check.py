"""Read an MP4's boxes without FFmpeg or ffprobe (spec Section 8.6, plan Section 2.4).

Only box headers and a few small fields are read, so a file of any size costs almost nothing.
A file that cannot be read in full is an error here, and never a pass.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO

_HEADER_BYTES = 8
_LARGE_HEADER_BYTES = 16
_LARGE_SIZE_MARKER = 1
_TO_END_OF_FILE_MARKER = 0
_FIXED_POINT_SHIFT = 16  # tkhd holds width and height as 16.16 numbers

_SAMPLE_ENTRY_SIZE_OFFSET = 40  # in stsd: its own 8, an 8-byte box header, then 24 bytes of fields
_SAMPLE_COUNT_OFFSET = 8  # in stsz: version and flags, then the fixed size, then the count

_H264 = "avc1"
_AAC = "mp4a"
# Rounding to a whole frame and to AAC packets moves the length a little. A render that stopped
# early, or that ignored the props, is out by far more.
_DURATION_TOLERANCE_MS = 500


class Mp4Error(ValueError):
    """The file cannot be used. The message says why."""


class NotMp4(Mp4Error):
    """The file is some other kind of file."""


class TruncatedMp4(Mp4Error):
    """The file stops before its own boxes say it should."""


class Mp4NotConformed(Mp4Error):
    """A readable MP4 in the wrong form. A lower bitrate would not change that."""


class Mp4TooLarge(Mp4Error):
    """A good file, over the size limit. A lower bitrate can fix this one."""


@dataclass(frozen=True)
class Mp4Info:
    size_bytes: int
    moov_before_mdat: bool
    has_edit_list: bool
    width: int | None
    height: int | None
    duration_ms: int
    video_codec: str | None
    audio_codec: str | None
    video_tracks: int
    audio_tracks: int
    stream_width: int | None  # what the video's own sample entry says, as tkhd can differ from it
    stream_height: int | None
    video_samples: int
    audio_samples: int
    media_bytes: int
    media_open_ended: bool  # an mdat "to the end of the file" can be cut anywhere and not show it


@dataclass(frozen=True)
class _Box:
    kind: bytes
    start: int  # the first byte after the header
    end: int
    open_ended: bool = False


def _next_box(handle: BinaryIO, position: int, limit: int, *, top_level: bool) -> _Box:
    if limit - position < _HEADER_BYTES:
        raise TruncatedMp4(f"a box header is cut off at byte {position}")
    handle.seek(position)
    size, kind = struct.unpack(">I4s", handle.read(_HEADER_BYTES))
    start = position + _HEADER_BYTES
    open_ended = False
    if size == _LARGE_SIZE_MARKER:
        if limit - position < _LARGE_HEADER_BYTES:
            raise TruncatedMp4(f"a box header is cut off at byte {position}")
        size = struct.unpack(">Q", handle.read(_HEADER_BYTES))[0]
        start = position + _LARGE_HEADER_BYTES
    elif size == _TO_END_OF_FILE_MARKER:
        if not top_level:
            raise Mp4Error(f"box {kind!r} at byte {position} has no size")
        size = limit - position
        open_ended = True
    if size < start - position:
        raise Mp4Error(f"box {kind!r} at byte {position} is smaller than its own header")
    end = position + size
    if end > limit:
        raise TruncatedMp4(f"box {_label(kind)} at byte {position} runs past where it can end")
    return _Box(kind, start, end, open_ended)


def _label(kind: bytes) -> str:
    return kind.decode("latin-1")


def _children(handle: BinaryIO, parent: _Box) -> list[_Box]:
    children = []
    position = parent.start
    while position < parent.end:
        child = _next_box(handle, position, parent.end, top_level=False)
        children.append(child)
        position = child.end
    return children


def _child(handle: BinaryIO, parent: _Box, kind: bytes) -> _Box | None:
    return next((box for box in _children(handle, parent) if box.kind == kind), None)


def _field(handle: BinaryIO, box: _Box, offset: int, layout: str) -> tuple:
    size = struct.calcsize(layout)
    if box.end - box.start < offset + size:
        raise Mp4Error(f"box {_label(box.kind)} is too short")
    handle.seek(box.start + offset)
    return struct.unpack(layout, handle.read(size))


def _duration_ms(handle: BinaryIO, mvhd: _Box) -> int:
    version = _field(handle, mvhd, 0, ">B")[0]
    if version == 1:
        timescale, duration = _field(handle, mvhd, 20, ">IQ")
    else:
        timescale, duration = _field(handle, mvhd, 12, ">II")
    if timescale == 0:
        raise Mp4Error("the movie header has a timescale of zero")
    return round(duration * 1000 / timescale)


def _picture_size(handle: BinaryIO, tkhd: _Box) -> tuple[int, int]:
    version = _field(handle, tkhd, 0, ">B")[0]
    offset = 88 if version == 1 else 76
    width, height = _field(handle, tkhd, offset, ">II")
    return width >> _FIXED_POINT_SHIFT, height >> _FIXED_POINT_SHIFT


def _sample_table(handle: BinaryIO, mdia: _Box) -> _Box | None:
    minf = _child(handle, mdia, b"minf")
    return _child(handle, minf, b"stbl") if minf else None


def _sample_codec(handle: BinaryIO, stbl: _Box | None) -> str | None:
    stsd = _child(handle, stbl, b"stsd") if stbl else None
    if stsd is None:
        return None
    return _field(handle, stsd, 12, ">4s")[0].decode("latin-1")


def _stream_size(handle: BinaryIO, stbl: _Box | None) -> tuple[int | None, int | None]:
    stsd = _child(handle, stbl, b"stsd") if stbl else None
    if stsd is None or stsd.end - stsd.start < _SAMPLE_ENTRY_SIZE_OFFSET + 4:
        return None, None
    return _field(handle, stsd, _SAMPLE_ENTRY_SIZE_OFFSET, ">HH")


def _sample_count(handle: BinaryIO, stbl: _Box | None) -> int:
    stsz = _child(handle, stbl, b"stsz") if stbl else None
    if stsz is None or stsz.end - stsz.start < _SAMPLE_COUNT_OFFSET + 4:
        return 0
    return _field(handle, stsz, _SAMPLE_COUNT_OFFSET, ">I")[0]


@dataclass
class _Tracks:
    has_edit_list: bool = False
    width: int | None = None
    height: int | None = None
    video_codec: str | None = None
    audio_codec: str | None = None
    video_tracks: int = 0
    audio_tracks: int = 0
    stream_width: int | None = None
    stream_height: int | None = None
    video_samples: int = 0
    audio_samples: int = 0


def _read_track(handle: BinaryIO, trak: _Box, tracks: _Tracks) -> None:
    children = _children(handle, trak)
    if any(box.kind == b"edts" for box in children):
        tracks.has_edit_list = True
    tkhd = next((box for box in children if box.kind == b"tkhd"), None)
    mdia = next((box for box in children if box.kind == b"mdia"), None)
    if tkhd is None or mdia is None:
        raise Mp4Error("a track has no header or no media box")
    hdlr = _child(handle, mdia, b"hdlr")
    if hdlr is None:
        raise Mp4Error("a track does not say what it holds")
    handler = _field(handle, hdlr, 8, ">4s")[0]
    if handler == b"vide":
        tracks.video_tracks += 1
        if tracks.video_tracks == 1:
            stbl = _sample_table(handle, mdia)
            tracks.width, tracks.height = _picture_size(handle, tkhd)
            tracks.video_codec = _sample_codec(handle, stbl)
            tracks.stream_width, tracks.stream_height = _stream_size(handle, stbl)
            tracks.video_samples = _sample_count(handle, stbl)
    elif handler == b"soun":
        tracks.audio_tracks += 1
        if tracks.audio_tracks == 1:
            stbl = _sample_table(handle, mdia)
            tracks.audio_codec = _sample_codec(handle, stbl)
            tracks.audio_samples = _sample_count(handle, stbl)


def _top_level_boxes(handle: BinaryIO, size: int) -> list[_Box]:
    head = handle.read(_HEADER_BYTES)
    if len(head) < _HEADER_BYTES or head[4:] != b"ftyp":
        raise NotMp4("the file does not start with an ftyp box")
    boxes = []
    position = 0
    while position < size:
        box = _next_box(handle, position, size, top_level=True)
        boxes.append(box)
        position = box.end
    return boxes


def _read(handle: BinaryIO, size: int) -> Mp4Info:
    boxes = _top_level_boxes(handle, size)
    moovs = [index for index, box in enumerate(boxes) if box.kind == b"moov"]
    mdats = [index for index, box in enumerate(boxes) if box.kind == b"mdat"]
    if not moovs:
        raise TruncatedMp4("the file has no moov box")
    if not mdats:
        raise TruncatedMp4("the file has no mdat box")
    if len(moovs) > 1:
        raise Mp4Error("the file has more than one moov box")

    moov = boxes[moovs[0]]
    tracks = _Tracks()
    mvhd = None
    for child in _children(handle, moov):
        if child.kind == b"mvhd":
            mvhd = child
        elif child.kind == b"trak":
            _read_track(handle, child, tracks)
    if mvhd is None:
        raise Mp4Error("the moov box has no mvhd movie header")
    return Mp4Info(
        size_bytes=size,
        moov_before_mdat=moovs[0] < mdats[0],
        has_edit_list=tracks.has_edit_list,
        width=tracks.width,
        height=tracks.height,
        duration_ms=_duration_ms(handle, mvhd),
        video_codec=tracks.video_codec,
        audio_codec=tracks.audio_codec,
        video_tracks=tracks.video_tracks,
        audio_tracks=tracks.audio_tracks,
        stream_width=tracks.stream_width,
        stream_height=tracks.stream_height,
        video_samples=tracks.video_samples,
        audio_samples=tracks.audio_samples,
        media_bytes=sum(boxes[index].end - boxes[index].start for index in mdats),
        media_open_ended=any(boxes[index].open_ended for index in mdats),
    )


def read_mp4(path: Path) -> Mp4Info:
    try:
        size = Path(path).stat().st_size
        with open(path, "rb") as handle:
            return _read(handle, size)
    except OSError as error:
        raise Mp4Error(f"could not read {Path(path).name}: {error}") from error


def _problem(info: Mp4Info, width: int, height: int, duration_ms: int) -> str | None:
    if info.video_codec is None:
        return "the file has no video track"
    if info.video_tracks > 1 or info.audio_tracks > 1:
        return f"the file has {info.video_tracks} video and {info.audio_tracks} audio tracks"
    if (info.width, info.height) != (width, height):
        return f"the picture is {info.width}x{info.height}, not {width}x{height}"
    if (info.stream_width, info.stream_height) != (width, height):
        return f"the video stream is {info.stream_width}x{info.stream_height}, not {width}x{height}"
    if info.video_codec != _H264:
        return f"the video is {info.video_codec}, not H.264"
    if info.audio_codec != _AAC:
        return f"the audio is {info.audio_codec}, not AAC"
    if abs(info.duration_ms - duration_ms) > _DURATION_TOLERANCE_MS:
        return f"the file is {info.duration_ms} ms long, not {duration_ms} ms"
    if not info.moov_before_mdat:
        return "the moov box comes after mdat"
    if info.has_edit_list:
        return "the file has an edit list"
    if info.media_open_ended:
        return "the mdat box has no size of its own, so a cut in the file would not show"
    if info.media_bytes == 0 or info.video_samples == 0 or info.audio_samples == 0:
        return "the file holds no media"
    return None


def check_output(
    path: Path, *, width: int, height: int, duration_ms: int, max_bytes: int
) -> Mp4Info:
    """Size comes last, so that only a good file over the limit asks for a lower bitrate."""
    info = read_mp4(path)
    problem = _problem(info, width, height, duration_ms)
    if problem:
        raise Mp4NotConformed(problem)
    if info.size_bytes > max_bytes:
        raise Mp4TooLarge(f"the file is {info.size_bytes} bytes, over the limit of {max_bytes}")
    return info
