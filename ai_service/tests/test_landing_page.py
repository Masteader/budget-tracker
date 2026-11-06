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


# The one use of the old Arabic name that stays: in the portal's Budgets view it means "household
# budget", not the brand. It is the ar `portal.subAllocationsDesc` value in
# web_app/src/i18n/translations.ts (flutter_app/test/screens/brand_identity_test.dart pins it there),
# so the served build may carry this sentence exactly once, in the app bundle, and nowhere else.
_HOUSEHOLD_BUDGET_SENTENCE = "توزيع المخصصات المحددة للأبناء والمصاريف المستقلة ضمن ميزانية الأسرة"


def _app_bundle_name() -> str:
    """The app script static/index.html loads, relative to static/ (e.g. assets/index-AbC123.js)."""
    scripts = re.findall(r'src="/(assets/index-[^"]+\.js)"', (STATIC / "index.html").read_text(encoding="utf-8"))
    assert len(scripts) == 1, scripts
    return scripts[0]


def _old_or_withdrawn_name_offenders(files: dict[str, str], app_bundle: str) -> list[str]:
    """Served files (by path under static/) naming the app by an old or withdrawn name.

    The household-budget sentence is allowed once, in the app bundle only; the bundle is an
    offender if it does not carry that sentence exactly once.
    """
    from test_qawam_money_branding import _has_old_name, _has_withdrawn_name

    offenders = []
    for name, text in files.items():
        if name == app_bundle:
            if text.count(_HOUSEHOLD_BUDGET_SENTENCE) != 1:
                offenders.append(name)
                continue
            text = text.replace(_HOUSEHOLD_BUDGET_SENTENCE, "", 1)
        if _has_old_name(text) or _has_withdrawn_name(text):
            offenders.append(name)
    return offenders


def _static_texts() -> dict[str, str]:
    return {p.relative_to(STATIC).as_posix(): p.read_text(encoding="utf-8") for p in _static_text_files()}


def test_served_build_has_neither_the_old_nor_the_withdrawn_name():
    files = _static_texts()
    assert len(files) >= 4, sorted(files)  # index.html, favicon.svg, the CSS and the JS chunks
    assert _old_or_withdrawn_name_offenders(files, _app_bundle_name()) == []


def test_the_household_budget_allowance_is_one_sentence_in_the_app_bundle():
    files = _static_texts()
    bundle = _app_bundle_name()

    def offenders_with(name: str, text: str) -> list[str]:
        return _old_or_withdrawn_name_offenders({**files, name: text}, bundle)

    # A second, unrelated use is caught, in the app bundle or in any other served file.
    assert offenders_with(bundle, files[bundle] + 'x="ميزانية الأسرة"') == [bundle]
    assert offenders_with(bundle, files[bundle] + f'x="{_HOUSEHOLD_BUDGET_SENTENCE}"') == [bundle]
    assert offenders_with("index.html", files["index.html"] + _HOUSEHOLD_BUDGET_SENTENCE) == ["index.html"]
    # Shorter fragments of the sentence are not allowed on their own.
    assert offenders_with("index.html", files["index.html"] + "ضمن ميزانية الأسرة") == ["index.html"]
    # The allowance is the sentence, not the bundle: without it the bundle no longer passes.
    assert offenders_with(bundle, files[bundle].replace(_HOUSEHOLD_BUDGET_SENTENCE, "")) == [bundle]


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
    # Built with VITE_API_BASE_URL= (same origin), so no hard-coded production host. The minifier
    # emits the default host on its own (E=`https://budget.fmsco.com.sa`), so look for the host
    # itself, in every served file: a plain `npm run build` bundle must fail here.
    assert "budget.fmsco.com.sa/public/inquiries" not in bundle
    hosts = [name for name, text in _static_texts().items() if "https://budget.fmsco.com.sa" in text]
    assert hosts == [], f"built without VITE_API_BASE_URL= (see README): {hosts}"


# ── The served build is refreshed with the web source (static/ is not stale) ───

_TRANSLATIONS = WEB_APP / "src" / "i18n" / "translations.ts"
_JS_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


def _ts_string_values(source: str) -> list[str]:
    """The decoded value of every string literal in a TypeScript source, comments skipped.

    A small lexer, not a regex: it follows quotes, escapes and comments, so an apostrophe inside a
    double-quoted string or a quote inside a comment cannot shift it. A template literal with
    `${…}` has no single value, so it raises rather than guess.
    """
    values: list[str] = []
    i, n = 0, len(source)
    while i < n:
        if source.startswith("//", i):
            i = source.find("\n", i)
            i = n if i < 0 else i
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            if end < 0:
                raise ValueError("unterminated comment")
            i = end + 2
        elif source[i] in "'\"`":
            quote, j, out = source[i], i + 1, []
            while True:
                if j >= n:
                    raise ValueError(f"unterminated string at {i}")
                c = source[j]
                if c == quote:
                    break
                if c == "\\":
                    nxt = source[j + 1]
                    if nxt == "u" and source[j + 2] == "{":
                        end = source.index("}", j)
                        out.append(chr(int(source[j + 3 : end], 16)))
                        j = end + 1
                    elif nxt == "u":
                        out.append(chr(int(source[j + 2 : j + 6], 16)))
                        j += 6
                    elif nxt == "x":
                        out.append(chr(int(source[j + 2 : j + 4], 16)))
                        j += 4
                    elif nxt in "\r\n":  # line continuation
                        j += 3 if source.startswith("\r\n", j + 1) else 2
                    else:
                        out.append(_JS_ESCAPES.get(nxt, nxt))
                        j += 2
                    continue
                if quote == "`" and source.startswith("${", j):
                    raise ValueError(f"template literal with ${{…}} at {i}: extend the extractor")
                if quote != "`" and c in "\r\n":
                    raise ValueError(f"line break in a string at {i}")
                out.append(c)
                j += 1
            values.append("".join(out))
            i = j + 1
        else:
            i += 1
    return values


def _translation_values() -> list[str]:
    source = _TRANSLATIONS.read_text(encoding="utf-8")
    start = source.index("export const translations")
    return _ts_string_values(source[start:])


def _js_literals(value: str) -> set[str]:
    """The ways a minifier can write `value` as a JS string literal, quotes included."""
    forms = set()
    for quote in "\"'`":
        body = value.replace("\\", "\\\\").replace(quote, "\\" + quote)
        if quote == "`":
            body = body.replace("${", "\\${")
            forms.add(quote + body + quote)  # a template literal may keep a real line break
        forms.add(quote + body.replace("\r", "\\r").replace("\n", "\\n") + quote)
    return forms


def test_the_translation_extractor_reads_every_kind_of_literal():
    source = r"""
    /* a 'quoted' comment */ export const translations = {
      a: 'plain', // an "inline" comment's quote
      b: "Don't stop",
      c: 'it\'s',
      d: `back ${'tick'.length ? '' : ''}`.length ? 'x' : 'y',
    };"""
    with pytest.raises(ValueError, match="template literal"):
        _ts_string_values(source)
    source = source.replace("`back ${'tick'.length ? '' : ''}`", "`back`")
    assert _ts_string_values(source) == ["plain", "Don't stop", "it's", "back", "x", "y"]
    assert _ts_string_values(r"""x = 'a\nb\u0041\u{1F600}\x41\\';""") == ["a\nbA\U0001F600A\\"]


def test_the_translation_extractor_finds_both_dictionaries():
    values = _translation_values()
    assert len(values) > 200, len(values)
    for known in ("الأسئلة", "FAQ", "Don't have an account? Sign up now", "Wife's Personal Allowance",
                  _HOUSEHOLD_BUDGET_SENTENCE):
        assert known in values, known
    assert "ar" not in values  # the `Language` type above the dictionary is not read


def test_served_bundle_carries_every_translation_string():
    """A copy change in translations.ts must ship with a refreshed static/ (README: refresh step)."""
    bundle = _served_bundle()
    missing = [v for v in dict.fromkeys(_translation_values()) if not any(f in bundle for f in _js_literals(v))]
    assert not missing, (
        f"ai_service/static/ is stale: {len(missing)} translations.ts strings are not in the served "
        f"bundle, e.g. {missing[:3]}. Rebuild with `VITE_API_BASE_URL= npm run build` and copy as in README.md."
    )


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
