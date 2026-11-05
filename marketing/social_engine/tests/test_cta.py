"""CTA wording and availability, G11 (spec Section 6.7, decision D26, task C3).

The strings below are the approved text. If the owner changes the wording, only `config.yaml`
and these strings change (plan Section 6).
"""

import pytest
from guardrail_helpers import EVASIONS

from content_engine.cta import (
    UnknownTokenError,
    active_wording,
    compose_caption,
    compose_voice,
    cta_line,
    fill_tokens,
)
from content_engine.guardrails import (
    GuardrailContext,
    check_bio,
    check_cta_line,
    check_final_caption,
    check_script,
    check_text,
)
from content_engine.schemas import Script
from core.brand_gate import ReelBrand, brand_for_reel
from core.config import Cta, CtaWording, load_config

LIVE_BRAND = ReelBrand("قوام المال", "Qawam Money", "#QawamMoney", "logo.svg", is_test=False)

APPROVED = {
    "bio_ar": "{brand_ar} {brand_en} · لا إسراف ولا تقتير · قريبًا: الوصول المبكر",
    "bio_en": "{brand_en} {brand_ar} · Spend in balance · Early access coming soon",
    "caption_ar": "{brand_ar} {brand_en} قريبًا. نجهّز الوصول المبكر.",
    "caption_en": "{brand_en} {brand_ar} is coming soon. Early access is on the way.",
    "voice_ar": "{brand_ar}، قريبًا.",
    "voice_en": "{brand_en}, coming soon.",
}
LINES = [
    ("bio", "ar"),
    ("bio", "en"),
    ("caption", "ar"),
    ("caption", "en"),
    ("voice", "ar"),
    ("voice", "en"),
]
BANNED_WITH_NO_URL = [
    "https://qawam.money",
    "http://example.com/app",
    "www.example.com",
    "example.com",
    "qawam.money",
    "link in bio",
    "Link in my bio",
    "#linkinbio",
    "الرابط في البايو",
    "download",
    "Download the app",
    "high app downloads",
    "install it today",
    "حمّل التطبيق",
    "نزّل التطبيق",
    "حمله الآن",
    "App Store",
    "Google Play",
    "جوجل بلاي",
    "آب ستور",
    "available now",
    "Available on Android",
    "متوفر الآن",
    "Early access open",
]


def _brands():
    config = load_config()
    return {
        "test": brand_for_reel(config, test_reel=True),
        "live": LIVE_BRAND,
    }


def _hard(report) -> set[str]:
    return {finding.rule for finding in report.hard_failures}


def _script(**changes) -> Script:
    values = {
        "topic_id": "g001",
        "tier": "global",
        "template": "DailyTip",
        "language": "ar",
        "hook_ar": "راتبك وين يروح كل شهر؟",
        "voice_script": "اكتب مصاريفك كل أسبوع.",
        "on_screen_en": ["Where does your salary go?"],
        "subtitles_en": "Write your spending down every week.",
        "feature_clip_folder": None,
        "claim_ids": [],
        "numbers": [],
        "sources": [],
        "caption_ar": "اكتب مصاريفك كل أسبوع.",
        "caption_en": "Write your spending down every week.",
        "hashtags": ["{brand_hashtag}", "#budgeting"],
        "speech_seconds_estimate": 32.5,
    }
    return Script(**{**values, **changes})


def _early_access_config(url: str = "https://qawammoney.example/early"):
    config = load_config()
    wording = CtaWording(
        bio_ar="{brand_ar} {brand_en} · الوصول المبكر",
        bio_en="{brand_en} {brand_ar} · Early access",
        caption_ar="{brand_ar} {brand_en}: الوصول المبكر.",
        caption_en="{brand_en} {brand_ar}: early access.",
        voice_ar="{brand_ar}، الوصول المبكر.",
        voice_en="{brand_en}, early access.",
    )
    cta = Cta(
        mode="early_access",
        landing_url=url,
        coming_soon=config.cta.coming_soon,
        early_access=wording,
        store=None,
    )
    return config.model_copy(update={"cta": cta})


# --- The shipped strings -------------------------------------------------------------------


def test_the_shipped_mode_is_coming_soon_with_no_url():
    config = load_config()
    assert config.cta.mode == "coming_soon"
    assert config.cta.landing_url is None


@pytest.mark.parametrize("key", APPROVED)
def test_the_shipped_strings_equal_the_approved_text(key):
    assert getattr(load_config().cta.coming_soon, key) == APPROVED[key]


def test_every_approved_string_is_checked_here():
    assert set(APPROVED) == set(CtaWording.model_fields)


@pytest.mark.parametrize("brand_form", ["test", "live"])
@pytest.mark.parametrize(("kind", "language"), LINES)
def test_each_filled_string_passes_g11_g12_and_g18(brand_form, kind, language):
    config = load_config()
    brand = _brands()[brand_form]
    line = cta_line(config, brand, kind, language)
    report = check_cta_line(line, language, config, brand, spoken=kind == "voice")
    assert report.hard_failures == []


@pytest.mark.parametrize("language", ["ar", "en"])
def test_a_filled_live_bio_shows_both_names_in_language_order(language):
    line = cta_line(load_config(), LIVE_BRAND, "bio", language)
    pair = "قوام المال Qawam Money" if language == "ar" else "Qawam Money قوام المال"
    assert line.startswith(pair)


@pytest.mark.parametrize("language", ["ar", "en"])
def test_the_configured_disclaimer_and_disclosure_pass_every_rule(language):
    config = load_config()
    brand = LIVE_BRAND
    report = check_final_caption(
        compose_caption("اكتب مصاريفك." if language == "ar" else "Write it down.", language,
                        config, brand),
        language,
        config,
        brand,
    )
    assert report.hard_failures == []
    assert report.passed


# --- Filling -------------------------------------------------------------------------------


def test_filling_adds_nothing_but_the_brand():
    config = load_config()
    filled = cta_line(config, LIVE_BRAND, "voice", "en")
    assert filled == "Qawam Money, coming soon."


@pytest.mark.parametrize(("kind", "language"), LINES)
def test_filling_never_adds_a_link_even_with_a_url_set(kind, language):
    config = _early_access_config()
    assert config.cta.landing_url
    line = cta_line(config, LIVE_BRAND, kind, language)
    assert "http" not in line
    assert "example" not in line


@pytest.mark.parametrize("language", ["ar", "en"])
def test_composing_a_caption_never_adds_a_link(language):
    config = _early_access_config()
    caption = compose_caption("Body text", language, config, LIVE_BRAND)
    assert "http" not in caption


def test_composing_a_voice_line_appends_only_the_approved_line():
    config = load_config()
    assert compose_voice("{brand_en} helps.", "en", config, LIVE_BRAND) == (
        "Qawam Money helps. Qawam Money, coming soon."
    )


def test_filling_is_one_pass():
    brand = ReelBrand("{brand_en}", "x", "#x", "logo.svg", is_test=False)
    assert fill_tokens("{brand_ar}", brand) == "{brand_en}"


@pytest.mark.parametrize(
    "text",
    ["{brand}", "{brand_x}", "{ brand_ar }", "{brand_ar", "brand_ar}", "{BRAND_AR}", "{}"],
)
def test_filling_refuses_an_unknown_token(text):
    with pytest.raises(UnknownTokenError):
        fill_tokens(text, LIVE_BRAND)


def test_the_active_wording_follows_the_mode():
    assert active_wording(load_config()).voice_en == APPROVED["voice_en"]
    assert "early access" in active_wording(_early_access_config()).voice_en


# --- G11 with an empty URL ------------------------------------------------------------------


@pytest.mark.parametrize("text", BANNED_WITH_NO_URL)
def test_each_sample_fails_g11_with_an_empty_url(text):
    assert "G11" in _hard(check_text(text))


@pytest.mark.parametrize("evasion", EVASIONS, ids=str)
@pytest.mark.parametrize(
    "text",
    [
        "link in bio",
        "Download the app",
        "App Store",
        "Google Play",
        "available now",
        "حمّل التطبيق",
        "نزّل التطبيق",
        "الرابط في البايو",
        "جوجل بلاي",
    ],
)
def test_no_evasion_gets_cta_wording_past_g11(text, evasion):
    changed = EVASIONS[evasion](text)
    assert "G11" in _hard(check_text(changed)), f"{evasion} hid {text!r}: {changed!r}"


@pytest.mark.parametrize(
    ("field", "wrap"),
    [
        ("voice_script", str),
        ("hook_ar", str),
        ("subtitles_en", str),
        ("caption_ar", str),
        ("caption_en", str),
        ("on_screen_en", lambda text: [text]),
        ("hashtags", lambda text: [f"#{text.replace(' ', '_')}"]),
    ],
)
@pytest.mark.parametrize(
    "text",
    [
        "link in bio",
        "download",
        "حمّل التطبيق",
        "نزّل التطبيق",
        "App Store",
        "Google Play",
        "available now",
    ],
)
def test_each_sample_fails_in_every_text_field(field, wrap, text):
    script = _script(**{field: wrap(text)})
    report = check_script(script, config=load_config(), brand=LIVE_BRAND)
    assert "G11" in _hard(report), f"{field} let {text!r} through"


@pytest.mark.parametrize(
    "field", ["voice_script", "hook_ar", "subtitles_en", "caption_ar", "caption_en"]
)
def test_a_web_address_fails_in_every_field_that_can_hold_one(field):
    script = _script(**{field: "qawam.money"})
    report = check_script(script, config=load_config(), brand=LIVE_BRAND)
    assert "G11" in _hard(report), f"{field} let a web address through"


@pytest.mark.parametrize(
    "words",
    [["Link", "in", "bio"], ["Google", "Play"], ["Download", "it"], ["App", "Store"]],
)
def test_wording_split_across_on_screen_lines_still_fails(words):
    report = check_script(_script(on_screen_en=words), config=load_config(), brand=LIVE_BRAND)
    assert "G11" in _hard(report)


def test_a_url_in_the_approved_wording_would_fail():
    assert "G11" in _hard(check_text("Early access coming soon: https://example.com"))


@pytest.mark.parametrize(
    "text",
    [
        "Your installment plan",
        "الراتب نزل أمس",
        "Link a budget to the account that funds it",
        "اربط الميزانية بالحساب",
        "Budget carefully. Money goes fast.",
    ],
)
def test_ordinary_wording_is_not_mistaken_for_a_cta(text):
    assert "G11" not in _hard(check_text(text))


# --- G11 once the owner moves on --------------------------------------------------------------


def test_early_access_allows_its_own_link_and_no_other():
    url = "https://qawammoney.example/early"
    context = GuardrailContext(cta_mode="early_access", landing_url=url)
    assert "G11" not in _hard(check_text(f"Early access: {url}", context))
    assert "G11" in _hard(check_text("Early access: https://other.example/x", context))


def test_early_access_still_refuses_store_and_download_wording():
    context = GuardrailContext(cta_mode="early_access", landing_url="https://a.example/x")
    assert "G11" in _hard(check_text("Download the app", context))
    assert "G11" in _hard(check_text("Google Play", context))


def test_store_mode_allows_store_wording():
    context = GuardrailContext(cta_mode="store", landing_url="https://a.example/x")
    assert "G11" not in _hard(check_text("Download the app on Google Play", context))


def test_check_script_reads_the_mode_from_config():
    config = _early_access_config()
    script = _script(subtitles_en="See https://qawammoney.example/early")
    assert "G11" not in _hard(check_script(script, config=config, brand=LIVE_BRAND))
    script = _script(subtitles_en="See https://other.example/x")
    assert "G11" in _hard(check_script(script, config=config, brand=LIVE_BRAND))


# --- Bios use only the approved wording --------------------------------------------------------


@pytest.mark.parametrize("language", ["ar", "en"])
def test_the_approved_bio_passes(language):
    config = load_config()
    bio = cta_line(config, LIVE_BRAND, "bio", language)
    assert check_bio(bio, language, config, LIVE_BRAND).hard_failures == []


@pytest.mark.parametrize(
    ("language", "bio"),
    [
        ("en", "Qawam Money قوام المال · Spend in balance"),
        ("en", "Qawam Money قوام المال · Spend in balance · Early access open"),
        ("ar", "قوام المال Qawam Money · حمّل التطبيق"),
        ("en", "قوام المال Qawam Money · Spend in balance · Early access coming soon"),
    ],
)
def test_any_other_bio_fails(language, bio):
    report = check_bio(bio, language, load_config(), LIVE_BRAND)
    assert _hard(report) & {"G11", "G12"}


# --- G17, on the caption as posted --------------------------------------------------------------


def test_a_final_caption_without_the_disclosure_fails_g17():
    config = load_config()
    report = check_final_caption("Write it down.", "en", config, LIVE_BRAND)
    assert "G17" in _hard(report)


def test_a_composed_caption_carries_the_disclosure():
    config = load_config()
    for language in ("ar", "en"):
        caption = compose_caption("Body", language, config, LIVE_BRAND)
        assert config.captions.ai_voice_disclosure in caption
        assert config.captions.disclaimer in caption
        assert "G17" not in _hard(check_final_caption(caption, language, config, LIVE_BRAND))
