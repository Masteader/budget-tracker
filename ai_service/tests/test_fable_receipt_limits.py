"""
FABLE-API-02 (docs/review/audit/fable_review.md): receipt stitching amplified a small request
(4 blank 6000x6660 JPEGs, 3.2 MiB) into ~1.7 GiB of RSS. Pages are now bounded in combined
pixels and stitched-canvas height before anything is decoded (413), decoded in JPEG draft mode
and downscaled to at most 1600 px wide one page at a time.
"""
from __future__ import annotations

import base64
import io
import os
import subprocess
import sys
import textwrap

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from fable_world import World

AI_SERVICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _jpeg_b64(w: int, h: int) -> str:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), (255, 255, 255)).save(buf, format="JPEG", quality=30)
    return base64.b64encode(buf.getvalue()).decode()


@pytest.fixture(scope="module")
def big_page():
    return _jpeg_b64(6000, 6660)  # 39.96 MP, just under the per-photo limit


def test_reviewer_case_four_huge_pages_is_rejected_before_decoding(big_page):
    import receipt_scanner

    with pytest.raises(receipt_scanner.ReceiptImageTooLarge):
        receipt_scanner.validate_receipt_images([big_page] * 4)
    # One such page alone is still a valid upload.
    receipt_scanner.validate_receipt_images([big_page])


def test_stitched_canvas_height_is_capped():
    import receipt_scanner

    tall = _jpeg_b64(800, 10000)  # becomes 1600 x 20000 when widened to the canvas: 20400 in total
    with pytest.raises(receipt_scanner.ReceiptImageTooLarge):
        receipt_scanner.validate_receipt_images([_jpeg_b64(1600, 400), tall])


def test_stitched_pages_are_downscaled_to_a_bounded_width(big_page):
    import receipt_scanner

    out = receipt_scanner.stitch_images_vertically([big_page, big_page])
    img = Image.open(io.BytesIO(out))
    assert img.width == receipt_scanner.STITCH_MAX_WIDTH == 1600
    assert img.height == 2 * round(6660 * 1600 / 6000)
    assert img.height <= receipt_scanner.MAX_STITCHED_HEIGHT


def test_stitching_peak_memory_is_bounded(big_page, tmp_path):
    """Measured in a fresh interpreter: the RSS high-water mark gained while stitching two
    40 MP pages (the old code needed ~0.85 GiB for two, ~1.7 GiB for four)."""
    if sys.platform == "win32":
        pytest.skip("resource module is Unix-only")
    img_file = tmp_path / "page.b64"
    img_file.write_text(big_page)
    script = textwrap.dedent(f"""
        import resource, sys
        import dotenv
        dotenv.load_dotenv = lambda *a, **k: False
        sys.path.insert(0, {AI_SERVICE!r})
        import receipt_scanner
        page = open({str(img_file)!r}).read()
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
    gained_mib = int(res.stdout.strip().splitlines()[-1])
    assert gained_mib < 200, f"stitching raised peak RSS by {gained_mib} MiB"


def test_scan_route_answers_413_for_oversized_pages(fake_supabase, big_page):
    from main import app

    w = World(fake_supabase, {"ahmed": ("admin", "peer")})
    with TestClient(app) as api:
        r = api.post("/agent/scan-receipt", json={"household_id": w.hid, "images_base64": [big_page] * 4},
                     headers=w.hdr("ahmed"))
    assert r.status_code == 413, r.text
    assert not fake_supabase.tables.get("transactions")
    assert not fake_supabase.storage_objects
