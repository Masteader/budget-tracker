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


# ── Public account deletion page (store requirement) ───────────────────────────

_PROXIED = {"X-Forwarded-For": "198.51.100.7"}

# web_app has no unit tests, so the served bundle is where the page's promises are held to.
# One sentence per promise, in each language the page offers.
_DELETE_PAGE_COPY = {
    "en": (
        "Delete your Qawam Money account",  # names the app as on the store listing
        "deleted 30 days after you confirm",  # the 30-day window
        "Signing in alone does not cancel the deletion.",
        "show as “Deleted member”",  # what is kept, without a name
        "Free text other members typed",  # what is not edited
        "Household names stay as they are",
        "Copies of emails in the developer’s mailbox",  # out of reach
        "Railway server logs",
        "Supabase database backups",
        "Supabase authentication audit log entries",
        "assign another member as primary admin, or delete the household",
        "including other members’ accounts and entries in that household and the wife’s ledger",
        "Members keep their logins",
        "We keep the stored request for 90 days",
        "We may email you",  # reminders are never promised
        "This form does not delete anything",
        "Your account has not been deleted",
        "could not be sent right now",  # the 'captured' answer
    ),
    "ar": (
        "حذف حسابك في قوام المال",
        "بعد 30 يوماً من تأكيدك",
        "تسجيل الدخول وحده لا يلغي الحذف.",
        "باسم «عضو محذوف»",
        "النصوص التي كتبها الأعضاء الآخرون",
        "أسماء المنازل تبقى كما هي",
        "نسخ الرسائل الموجودة في بريد المطوّر",
        "سجلات خوادم Railway",
        "النسخ الاحتياطية لقاعدة بيانات Supabase",
        "سجلات تدقيق المصادقة في Supabase",
        "تعيين عضو آخر مشرفاً أساسياً أو حذف المنزل",
        "ومنها حسابات الأعضاء الآخرين ومصروفاتهم في هذا المنزل ودفتر الزوجة",
        "يحتفظ الأعضاء بحساباتهم",
        "نحتفظ بالطلب المخزّن 90 يوماً",
        "قد نراسلك",
        "هذا النموذج لا يحذف شيئاً",
        "لم يُحذف حسابك",
        "تعذّر إرسالها حالياً",
    ),
    "ur": (
        "قوام المال میں اپنا اکاؤنٹ حذف کریں",
        "تصدیق کے 30 دن بعد",
        "صرف سائن ان کرنے سے حذف منسوخ نہیں ہوتا۔",
        "«حذف شدہ رکن»",
        "دوسرے ارکان کی لکھی ہوئی عبارت",
        "گھرانوں کے نام جوں کے توں رہتے ہیں",
        "ڈویلپر کے میل باکس میں ای میلز کی نقول",
        "Railway کے سرور لاگز",
        "Supabase ڈیٹا بیس کے بیک اپس",
        "Supabase کے تصدیقی آڈٹ لاگ کے اندراجات",
        "کسی دوسرے رکن کو بنیادی منتظم بنائیں یا گھرانہ حذف کریں",
        "جس میں اس گھرانے میں دوسرے ارکان کے اکاؤنٹس اور اندراجات اور بیوی کا کھاتہ بھی شامل ہے",
        "ارکان کے لاگ اِن برقرار رہتے ہیں",
        "محفوظ درخواست ہم 90 دن تک رکھتے ہیں",
        "ہم آپ کو ای میل کر سکتے ہیں",
        "یہ فارم کچھ حذف نہیں کرتا",
        "آپ کا اکاؤنٹ حذف نہیں ہوا",
        "ابھی نہیں بھیجی جا سکی",
    ),
}


@pytest.mark.parametrize("lang", sorted(_DELETE_PAGE_COPY))
def test_served_deletion_page_states_its_promises_in_each_language(lang):
    bundle = _served_bundle()
    missing = [phrase for phrase in _DELETE_PAGE_COPY[lang] if phrase not in bundle]
    assert not missing, f"{lang}: {missing}"


def test_served_bundle_routes_the_deletion_page_and_supports_urdu():
    bundle = _served_bundle()
    assert "/delete-account" in bundle
    # Page-scoped Urdu with RTL, reachable with ?lang=ur.
    assert "اردو" in bundle
    assert "ur-PK-u-ca-gregory-nu-latn" in bundle
    assert "account_deletion" in bundle


def test_served_deletion_page_uses_the_same_rpcs_as_the_app():
    bundle = _served_bundle()
    for rpc in (
        "get_account_deletion_preflight",
        "request_account_deletion",
        "cancel_account_deletion",
    ):
        assert rpc in bundle, rpc
    # Every hint the request and cancel RPCs can answer with has a message.
    for hint in (
        "reauthentication_required",
        "confirmation_mismatch",
        "household_choice_missing",
        "household_choice_invalid",
        "successor_invalid",
        "successor_pending_deletion",
        "deletion_in_progress",
    ):
        assert hint in bundle, hint


def test_served_confirmation_words_are_the_ones_the_server_accepts():
    sql = (
        pathlib.Path(__file__).resolve().parents[2]
        / "supabase" / "migrations" / "20261105000200_account_deletion_rpcs.sql"
    ).read_text(encoding="utf-8")
    bundle = _served_bundle()
    for word in ("delete", "حذف", "حذف کریں"):
        assert f"'{word}'" in sql, word
        assert word in bundle, word
    assert "DELETE" in bundle  # the word English visitors are shown


def test_served_deletion_page_never_claims_an_outcome_the_form_cannot_deliver():
    bundle = _served_bundle()
    for phrase in (
        "Your account has been deleted",
        "Your account will be deleted within",
        "We will email you a reminder",
        "تم حذف حسابك",
        "آپ کا اکاؤنٹ حذف ہو گیا ہے",
    ):
        assert phrase not in bundle, phrase


def test_served_privacy_section_discloses_retention_and_deletion_in_each_language():
    bundle = _served_bundle()
    for phrase in (
        # English
        "Delete your account, with 30 days to change your mind",
        "What stays after deletion",
        "Requests sent through the deletion form are kept for 90 days.",
        # Arabic
        "احذف حسابك، ومعك 30 يوماً للتراجع",
        "وش يبقى بعد الحذف",
        "طلبات نموذج الحذف تبقى 90 يوماً.",
    ):
        assert phrase in bundle, phrase


def test_served_footer_links_to_the_deletion_page():
    bundle = _served_bundle()
    assert "/delete-account?lang=en" in bundle
    assert "Delete account" in bundle
    assert "حذف الحساب" in bundle


async def _proxied(method: str, path: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.request(method, path, headers=_PROXIED)


@pytest.mark.asyncio
async def test_delete_account_page_is_public_through_the_proxy():
    res = await _proxied("GET", "/delete-account")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    assert res.text == (STATIC / "index.html").read_text(encoding="utf-8")


@pytest.mark.asyncio
async def test_delete_account_page_still_answers_when_the_build_is_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(landing_page, "STATIC_INDEX", tmp_path / "index.html")
    res = await _proxied("GET", "/delete-account")
    assert res.status_code == 200
    assert "fmscoinfo@fmsco.com.sa" in res.text


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/delete-accounts", "/delete-account/confirm", "/account", "/privacy", "/admin", "/households"])
async def test_other_unknown_paths_stay_closed_through_the_proxy(path):
    res = await _proxied("GET", path)
    assert res.status_code == 401
    assert "<div id=\"root\">" not in res.text


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/delete-accounts", "/delete-account/confirm", "/account", "/privacy"])
async def test_no_generic_spa_fallback_was_added(path):
    res = await _get(path)
    assert res.status_code == 404


@pytest.mark.asyncio
@pytest.mark.parametrize("method", ["POST", "PUT", "PATCH", "DELETE"])
async def test_delete_account_page_is_read_only(method):
    res = await _proxied(method, "/delete-account")
    assert res.status_code == 405
