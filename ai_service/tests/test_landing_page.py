import pytest
from httpx import AsyncClient, ASGITransport
from main import app

@pytest.mark.asyncio
async def test_root_landing_page():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    html = res.text
    # Verify core branding and features
    assert "Budget Tracker" in html
    assert "ميزانية الأسرة" in html
    # Verify coming soon badges for all three app stores
    assert "Google Play" in html
    assert "App Store" in html
    assert "AppGallery" in html
    assert "قريباً" in html
    # Verify developer email
    assert "fmscoinfo@fmsco.com.sa" in html
    # Verify feature descriptions
    assert "دورة الراتب" in html  # Flexible salary cycle
    assert "الذكاء الاصطناعي" in html  # AI
    assert "الادخار" in html  # Savings reserve

@pytest.mark.asyncio
async def test_auth_confirm_landing():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/auth/confirm")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    html = res.text
    assert "تم تأكيد البريد الإلكتروني بنجاح" in html
    assert "budgettracker://login" in html
    assert "fmscoinfo@fmsco.com.sa" in html

@pytest.mark.asyncio
async def test_auth_callback_landing():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/auth/callback")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]

@pytest.mark.asyncio
async def test_hero_background_images():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res_webp = await ac.get("/hero-bg.webp")
        res_jpg = await ac.get("/hero-bg.jpg")
    assert res_webp.status_code == 200
    assert "image/webp" in res_webp.headers["content-type"]
    assert res_jpg.status_code == 200
    assert "image/jpeg" in res_jpg.headers["content-type"]


# ── VIP early-access form (WEB-09) ─────────────────────────────────────────────

def _i18n_block(html: str, lang: str) -> str:
    table = html.split("const T = {", 1)[1]
    ar_block, en_block = table.split("\n  en: {", 1)
    return ar_block if lang == "ar" else en_block


def test_fallback_landing_has_vip_form_posting_to_inquiries_endpoint():
    from _landing_impl import LANDING_HTML

    assert 'id="vip-form"' in LANDING_HTML
    assert "'/public/inquiries'" in LANDING_HTML  # same-origin endpoint
    assert "vip_early_access" in LANDING_HTML
    assert 'name="company_website"' in LANDING_HTML  # honeypot
    assert "res.ok" in LANDING_HTML  # success only on 2xx
    assert 'href="mailto:fmscoinfo@fmsco.com.sa"' in LANDING_HTML  # fallback kept
    for lang in ("ar", "en"):
        block = _i18n_block(LANDING_HTML, lang)
        for key in ("vipl", "vipb", "vipsend", "vipok", "viperr", "viperr422", "viperr429", "vipnet"):
            assert f"{key}:" in block, f"{lang}:{key}"


def test_build_script_is_in_sync_with_generated_files():
    """Running _build_landing.py must reproduce the committed files (no silent regressions)."""
    import pathlib

    import _build_landing
    import _landing_impl

    assert _build_landing.LANDING_HTML_CONTENT == _landing_impl.LANDING_HTML
    here = pathlib.Path(_build_landing.__file__).parent
    assert _build_landing.LANDING_PAGE_PY == (here / "landing_page.py").read_text(encoding="utf-8")



def test_served_web_bundle_posts_vip_signups_to_same_origin_endpoint():
    """`/` serves the committed web_app build; it must contain the real VIP submit, not a fake one."""
    import pathlib
    import re

    static = pathlib.Path(__file__).resolve().parent.parent / "static"
    index = (static / "index.html").read_text(encoding="utf-8")
    scripts = re.findall(r'src="/assets/(index-[^"]+\.js)"', index)
    assert scripts, "static/index.html must reference its bundled script"
    bundle = (static / "assets" / scripts[0]).read_text(encoding="utf-8")
    assert "/public/inquiries" in bundle
    assert "vip_early_access" in bundle
    # Built with VITE_API_BASE_URL= (same origin), so no hard-coded production host.
    assert "budget.fmsco.com.sa/public/inquiries" not in bundle


# ── Public copy: Nafaqah family mode, privacy and technical claims ─────────────

# Phrases that must never return to the public landing copy (translation QA):
# a spousal cost split in family mode, "sovereign" (state-backed) wording in
# Arabic, SMS being processed, and encryption claims the system does not meet.
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


def _served_bundle() -> str:
    import pathlib
    import re

    static = pathlib.Path(__file__).resolve().parent.parent / "static"
    index = (static / "index.html").read_text(encoding="utf-8")
    script = re.findall(r'src="/assets/(index-[^"]+\.js)"', index)[0]
    return index + (static / "assets" / script).read_text(encoding="utf-8")


@pytest.mark.parametrize("source", ["served_bundle", "fallback_landing"])
def test_public_copy_has_no_spousal_split_or_false_claims(source):
    if source == "served_bundle":
        text = _served_bundle()
    else:
        from _landing_impl import LANDING_HTML as text
    found = [p for p in _FORBIDDEN_PUBLIC_COPY if p in text]
    assert not found, f"{source} contains: {found}"


def test_served_family_demo_shows_husband_owes_wife():
    bundle = _served_bundle()
    assert "مستحق لها على الزوج" in bundle
    assert "Owed back by husband" in bundle
    assert "من مصروفها الشخصي" in bundle  # her personal purchases come from her allowance


def test_fallback_arabic_privacy_matches_english_no_training():
    from _landing_impl import LANDING_HTML

    ar = _i18n_block(LANDING_HTML, "ar")
    en = _i18n_block(LANDING_HTML, "en")
    assert "ولا يُحتفظ بها لتدريب نماذج عامة" in ar
    assert "not retained for general model training" in en
