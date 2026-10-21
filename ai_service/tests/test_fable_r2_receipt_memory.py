"""
FABLE2-API-03: receipt stitching memory for formats without a reduced-size decode.

JPEG draft mode bounds a baseline JPEG's decode, but PNG, WebP and progressive JPEG pages are
always decoded at full size (two blank 40 MP WebP pages raised peak RSS by ~680 MiB, PNG ~380 MiB,
progressive JPEG ~175 MiB). Those pages are capped lower (12 MP each, 24 MP together), checked
from the headers before decoding, and at most two stitches decode at once in the process.
"""
from __future__ import annotations

import base64
import io
import os
import subprocess
import sys
import textwrap
import threading
import time

import pytest
from PIL import Image

import receipt_scanner as rs

AI_SERVICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _b64(kind: str, size) -> str:
    img = Image.new("RGB", size, (255, 255, 255))
    buf = io.BytesIO()
    if kind == "webp":
        img.save(buf, "WEBP", quality=30)
    elif kind == "png":
        img.save(buf, "PNG", optimize=True)
    else:
        img.save(buf, "JPEG", quality=30, progressive=(kind == "pjpeg"))
    return base64.b64encode(buf.getvalue()).decode()


def test_caps():
    assert rs.MAX_RECEIPT_PIXELS == 40_000_000  # baseline JPEG (draft-mode decode)
    assert rs.MAX_FULL_DECODE_PIXELS == 12_000_000
    assert rs.MAX_COMBINED_FULL_DECODE_PIXELS == 24_000_000
    assert rs.MAX_CONCURRENT_STITCHES == 2


@pytest.mark.parametrize("kind", ["png", "webp", "pjpeg"])
def test_full_decode_formats_are_capped_per_page(kind):
    with pytest.raises(rs.ReceiptImageTooLarge):
        rs.validate_receipt_images([_b64(kind, (4000, 3001))])  # 12.004 MP
    rs.validate_receipt_images([_b64(kind, (4000, 3000))])      # exactly 12 MP


@pytest.mark.parametrize("kind", ["png", "webp", "pjpeg"])
def test_full_decode_formats_are_capped_together(kind):
    page = _b64(kind, (4000, 3000))
    rs.validate_receipt_images([page, page])                    # 24 MP
    with pytest.raises(rs.ReceiptImageTooLarge):
        rs.validate_receipt_images([page, page, _b64(kind, (100, 100))])


def test_baseline_jpeg_keeps_the_draft_mode_limits():
    big = _b64("jpeg", (6000, 6660))  # 39.96 MP
    rs.validate_receipt_images([big, big])
    # A baseline page does not count against the full-decode budget.
    rs.validate_receipt_images([big, _b64("png", (4000, 3000)), _b64("webp", (4000, 3000))])


def test_at_most_two_stitches_decode_at_once(monkeypatch):
    active, peak, lock = [0], [0], threading.Lock()
    real = rs._decode_page

    def slow_decode(raw, target):
        with lock:
            active[0] += 1
            peak[0] = max(peak[0], active[0])
        time.sleep(0.05)
        try:
            return real(raw, target)
        finally:
            with lock:
                active[0] -= 1

    monkeypatch.setattr(rs, "_decode_page", slow_decode)
    page = _b64("jpeg", (200, 300))
    threads = [threading.Thread(target=rs.stitch_images_vertically, args=([page, page],)) for _ in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert 1 <= peak[0] <= rs.MAX_CONCURRENT_STITCHES


def test_stitch_output_unchanged_for_full_decode_pages():
    out = rs.stitch_images_vertically([_b64("webp", (3000, 4000)), _b64("png", (800, 600))])
    img = Image.open(io.BytesIO(out))
    assert img.mode == "RGB" and img.width == 1600
    assert img.height == round(4000 * 1600 / 3000) + round(600 * 1600 / 800)


@pytest.mark.parametrize("kind, budget_mib", [("webp", 300), ("png", 250), ("pjpeg", 200)])
def test_stitch_peak_memory_at_the_caps(kind, budget_mib, tmp_path):
    """The reviewer's method: RSS high-water mark gained in a fresh interpreter while stitching
    two pages at the per-page cap (before: 2 x 40 MP WebP +684 MiB, PNG +378, progressive +175)."""
    page_file = tmp_path / "page.b64"
    page_file.write_text(_b64(kind, (4000, 3000)))
    script = textwrap.dedent(f"""
        import resource, sys
        import dotenv
        dotenv.load_dotenv = lambda *a, **k: False
        sys.path.insert(0, {AI_SERVICE!r})
        import receipt_scanner
        page = open({str(page_file)!r}).read()
        receipt_scanner.validate_receipt_images([page, page])
        before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        receipt_scanner.stitch_images_vertically([page, page])
        after = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        print((after - before) // 1024)
    """)
    env = {k: v for k, v in os.environ.items() if k not in ("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY")}
    res = subprocess.run([sys.executable, "-I", "-c", script], capture_output=True, text=True, timeout=120,
                         env=env, cwd=str(tmp_path))
    assert res.returncode == 0, res.stderr[-2000:]
    gained = int(res.stdout.strip().splitlines()[-1])
    assert gained < budget_mib, f"{kind}: stitching raised peak RSS by {gained} MiB"
