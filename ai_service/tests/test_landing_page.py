"""`/` serves the committed web_app build (the only landing page); auth pages stay inline."""

import pathlib
import re

import pytest
from httpx import ASGITransport, AsyncClient

import landing_page
from main import app

STATIC = pathlib.Path(__file__).resolve().parent.parent / "static"
WEB_APP = STATIC.parent.parent / "web_app"
NAME_EN = "Qawam Money"
NAME_AR = "قوام المال"


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
    assert "Qawam Money" in res.text
    assert "قوام المال" in res.text
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
async def test_served_favicon_is_the_portions_logo_from_web_app():
    res = await _get("/favicon.svg")
    assert res.status_code == 200
    assert res.content == (WEB_APP / "public" / "favicon.svg").read_bytes()
    # The Portions mark: gold rim and the coral slice; not the old teal calendar tile.
    assert "#F0B132" in res.text
    assert "#F0553F" in res.text
    assert "#006575" not in res.text
    assert '<link rel="icon" type="image/svg+xml" href="/favicon.svg" />' in (STATIC / "index.html").read_text(
        encoding="utf-8"
    )


def _static_text_files() -> list[pathlib.Path]:
    return sorted(p for p in STATIC.rglob("*") if p.is_file() and p.suffix in {".html", ".js", ".css", ".svg"})


def test_served_build_names_the_app_in_both_languages():
    index = (STATIC / "index.html").read_text(encoding="utf-8")
    assert f"<title>{NAME_AR} {NAME_EN} | " in index
    assert f'<meta property="og:site_name" content="{NAME_AR} {NAME_EN}" />' in index
    assert f"<h1>{NAME_AR} {NAME_EN}</h1>" in index
    bundle = _served_bundle()
    assert f"{NAME_EN} {NAME_AR}" in bundle  # English brand.name
    assert f"{NAME_AR} {NAME_EN}" in bundle  # Arabic brand.name


def test_served_build_matches_the_web_app_page_head():
    source = (WEB_APP / "index.html").read_text(encoding="utf-8")
    served = (STATIC / "index.html").read_text(encoding="utf-8")
    for tag in re.findall(r"<title>.*?</title>|<meta\b[^>]*?/>|<noscript>.*?</noscript>", source, re.DOTALL):
        assert tag in served, f"static/index.html is stale: {tag[:80]}"


@pytest.mark.parametrize("path", _static_text_files(), ids=lambda p: p.relative_to(STATIC).as_posix())
def test_served_build_has_neither_the_old_nor_the_withdrawn_name(path):
    from test_qawam_money_branding import _has_old_name, _has_withdrawn_name

    text = path.read_text(encoding="utf-8")
    assert not _has_old_name(text), path.name
    assert not _has_withdrawn_name(text), path.name


def test_served_assets_are_all_referenced_by_the_build():
    """A refresh replaces static/assets whole, so no stale hashed file stays behind."""
    assets = {p.name: p for p in (STATIC / "assets").iterdir()}
    reached: set[str] = set()
    pending = [(STATIC / "index.html").read_text(encoding="utf-8")]
    while pending:
        text = pending.pop()
        for name, path in assets.items():
            if name not in reached and name in text:
                reached.add(name)
                pending.append(path.read_text(encoding="utf-8", errors="ignore"))
    assert set(assets) == reached, f"stale assets: {sorted(set(assets) - reached)}"


def test_portal_brand_button_is_named_from_the_translations():
    """Below 640px the portal brand button shows only the decorative logo, so it needs its own name."""
    source = (WEB_APP / "src" / "components" / "portal" / "PortalHeader.tsx").read_text(encoding="utf-8")
    logo = source.index("<Logo ")
    button = source[source.rindex("<button", 0, logo) : source.index("</button>", logo)]
    label = re.search(r"aria-label=\{`\$\{dict\.brand\.shortName\}[^`]*`\}", button)
    assert label, "the brand button must take its aria-label from dict.brand.shortName"
    assert "hidden sm:inline" in button  # the visible name still hides below 640px
    bundle = "\n".join(p.read_text(encoding="utf-8") for p in (STATIC / "assets").glob("*.js"))
    assert re.search(r'"aria-label":`\$\{\w+\.brand\.shortName\}[^`]*\$\{\w+\.portal\.dashboard\}`', bundle)


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
    "Sovereign",
    "تُعالج الرسائل النصية",
    "دون موافقة",
    "end-to-end",
    "End-to-End",
    "256-BIT RLS",
    "AES-256",
    "cryptographic row-level",
    "فك تشفير ميزانياتك",
    "الإجمالي الصافي للفاتورة",
    "99.4",
    "٩٩٫٤",
    "1,500",
    "Telemetry",
    "12 Pillars",
    "Pillars of Financial Governance",
    "الركائز",
    "protected roommate aliases",
    "local salary calculations",
    "50/50",
)


def test_public_copy_has_no_spousal_split_invented_metrics_or_false_claims():
    text = _served_bundle()
    found = [p for p in _FORBIDDEN_PUBLIC_COPY if p in text]
    assert not found, f"served bundle contains: {found}"


def test_served_copy_states_the_real_benefits_in_arabic_and_english():
    bundle = _served_bundle()
    for phrase in (
        "اعرف كم باقي لك لين الراتب",
        "سجّل مصروفك بالكلام أو بتصوير الفاتورة",
        "النفقة بين الزوجين واضحة",
        "قسمة سكن الزملاء بالعدل",
        "Know what’s left until payday",
    ):
        assert phrase in bundle, phrase


def test_served_family_story_has_husband_owing_wife_and_her_allowance():
    bundle = _served_bundle()
    assert "مستحق لها على الزوج" in bundle
    assert "Still owed to her by her husband" in bundle
    assert "من مصروفها الشخصي" in bundle  # her personal purchases come from her allowance


def test_served_privacy_section_names_the_ai_processor_and_no_sms():
    bundle = _served_bundle()
    assert bundle.count("Google Gemini") >= 2  # ar + en
    assert "(RLS)" in bundle
    assert "ما نقرأ رسائلك النصية أبداً" in bundle
    assert "We never read your SMS" in bundle
