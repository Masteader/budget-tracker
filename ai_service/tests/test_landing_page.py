"""`/` serves the committed web_app build (the only landing page); auth pages stay inline."""

import pathlib
import re

import pytest
from httpx import ASGITransport, AsyncClient

import landing_page
from main import app

STATIC = pathlib.Path(__file__).resolve().parent.parent / "static"


async def _get(path: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.get(path)


def _served_bundle() -> str:
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    scripts = re.findall(r'src="/assets/(index-[^"]+\.js)"', index)
    assert scripts, "static/index.html must reference its bundled script"
    return index + (STATIC / "assets" / scripts[0]).read_text(encoding="utf-8")


@pytest.mark.asyncio
async def test_root_serves_the_committed_web_app_build():
    res = await _get("/")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    assert res.text == (STATIC / "index.html").read_text(encoding="utf-8")
    assert '<div id="root"></div>' in res.text


@pytest.mark.asyncio
async def test_bundle_assets_referenced_by_the_build_are_served():
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    assets = re.findall(r'(?:src|href)="(/assets/[^"]+)"', index)
    assert assets
    for asset in assets:
        res = await _get(asset)
        assert res.status_code == 200, asset


def test_fallback_page_is_used_only_when_the_build_is_missing(monkeypatch, tmp_path):
    assert landing_page.get_landing_page_html() == (STATIC / "index.html").read_text(encoding="utf-8")

    monkeypatch.setattr(landing_page, "STATIC_INDEX", tmp_path / "missing" / "index.html")
    html = landing_page.get_landing_page_html()
    assert html == landing_page.FALLBACK_LANDING_HTML
    assert 'dir="rtl"' in html
    assert 'href="mailto:fmscoinfo@fmsco.com.sa"' in html
    # Self-contained: no third-party scripts, styles or fonts.
    assert "<script" not in html
    assert "https://" not in html


@pytest.mark.asyncio
async def test_root_falls_back_inline_when_the_build_is_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(landing_page, "STATIC_INDEX", tmp_path / "index.html")
    res = await _get("/")
    assert res.status_code == 200
    assert "Budget Tracker" in res.text
    assert "fmscoinfo@fmsco.com.sa" in res.text


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/auth/confirm", "/auth/callback"])
async def test_auth_confirmation_pages(path):
    res = await _get(path)
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    html = res.text
    assert "تم تأكيد البريد الإلكتروني بنجاح" in html
    assert 'href="budgettracker://login"' in html
    assert "fmscoinfo@fmsco.com.sa" in html


@pytest.mark.asyncio
async def test_favicon_is_served():
    res = await _get("/favicon.svg")
    assert res.status_code == 200
    assert "image/svg+xml" in res.headers["content-type"]


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/hero-bg.webp", "/hero-bg.jpg", "/hero_glacier.png"])
async def test_removed_legacy_landing_images_are_gone(path):
    res = await _get(path)
    assert res.status_code == 404


# ── VIP early-access form (WEB-09) ─────────────────────────────────────────────

def test_served_web_bundle_posts_vip_signups_to_same_origin_endpoint():
    """The served build must contain the real VIP submit, not a fake one."""
    bundle = _served_bundle()
    assert "/public/inquiries" in bundle
    assert "vip_early_access" in bundle
    assert "company_website" in bundle  # honeypot
    assert "fmscoinfo@fmsco.com.sa" in bundle
    # Built with VITE_API_BASE_URL= (same origin), so no hard-coded production host.
    assert "budget.fmsco.com.sa/public/inquiries" not in bundle


# ── Public copy: Nafaqah family mode, privacy and technical claims ─────────────

# Phrases that must never return to the public landing copy (translation QA, product review
# §3.5 and "Stop doing"): a spousal cost split in family mode, "sovereign" (state-backed)
# wording, SMS being processed, invented metrics, and claims the system does not meet.
_FORBIDDEN_PUBLIC_COPY = (
    "proportional income allocation",
    "salary-weighted",
    "Budget 100% reconciled",
    "تكامل الميزانية",
    "تكامل ميزانية الأب والأم",
    "الشركاء والأبناء",
    "توزيع نسبي",
    "سيادي",
    "السيادية",
    "تُعالج الرسائل النصية",
    "دون موافقة",
    "end-to-end",
    "End-to-End",
    "256-BIT RLS",
    "cryptographic row-level",
    "فك تشفير ميزانياتك",
    "الإجمالي الصافي للفاتورة",
)


def test_public_copy_has_no_spousal_split_invented_metrics_or_false_claims():
    text = _served_bundle()
    found = [p for p in _FORBIDDEN_PUBLIC_COPY if p in text]
    assert not found, f"served bundle contains: {found}"
