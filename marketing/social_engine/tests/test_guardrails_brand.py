"""Brand and truth rules G12, G13, G14, G17 and G18 (spec Section 6.5, task C4).

Includes the "Full brand name" row of spec Section 12: قوام alone can also mean body shape, so
the bare name fails in captions, hashtags, handles, on-screen text and voiceover.
"""

import pytest
from guardrail_helpers import EVASIONS

from content_engine import denylists
from content_engine.guardrails import (
    GuardrailContext,
    check_caption_words,
    check_script,
    check_text,
)
from content_engine.schemas import Script
from core.brand_gate import ReelBrand, brand_for_reel
from core.config import Captions, load_config

LIVE_BRAND = ReelBrand("قوام المال", "Qawam Money", "#QawamMoney", "logo.svg", is_test=False)

BARE_NAMES = [
    "قوام",
    "بقوام",
    "لقوام",
    "وقوام",
    "فقوام",
    "القوام",
    "بالقوام",
    "قوامك",
    "قوام مال",
    "قوام الأموال",
    "قوام المالية",
    "Qawam",
    "qawam",
    "QAWAM",
    "#قوام",
    "@qawam",
    "#Qawam",
    "Qawam Finance",
    "Qawamify",
    "Money Qawam",
    "قوام\nالمال",
    "Qawam\nMoney",
]
FULL_NAMES = [
    "قوام المال",
    "بقوام المال",
    "لقوام المال",
    "Qawam Money",
    "qawam money",
    "#قوام_المال",
    "#QawamMoney",
    "@qawam.money",
    "@qawam_money",
    "قَوَام المَال",
    "قــوام المــال",
    "قوام   المال",
    "ﻗﻮﺍﻡ ﺍﻟﻤﺎﻝ",
]
BODY_SHAPE_COPY = [
    "قوام المال للرشاقة",
    "قوام المال يخفف وزن",
    "قوام المال وصحة الجسم",
    "Qawam Money for fitness",
    "Qawam Money keeps you slim",
    "{brand_ar} {brand_en} للرشاقة",
    "{brand_en} {brand_ar} keeps you slim",
]


def _hard(text: str, **context) -> set[str]:
    report = check_text(text, GuardrailContext(**context))
    return {finding.rule for finding in report.hard_failures}


def _soft(text: str, **context) -> set[str]:
    report = check_text(text, GuardrailContext(**context))
    return {finding.rule for finding in report.soft_flags}


def _rules(report) -> set[str]:
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
        "hashtags": ["#budgeting"],
        "speech_seconds_estimate": 32.5,
    }
    return Script(**{**values, **changes})


def _check(script: Script):
    return check_script(script, config=load_config(), brand=LIVE_BRAND)


# --- G18 -----------------------------------------------------------------------------------


@pytest.mark.parametrize("text", BARE_NAMES)
def test_a_bare_name_fails_g18(text):
    assert "G18" in _hard(text)


@pytest.mark.parametrize("evasion", EVASIONS, ids=str)
@pytest.mark.parametrize("text", ["قوام", "بقوام", "Qawam", "#قوام", "@qawam"])
def test_no_evasion_hides_a_bare_name(text, evasion):
    changed = EVASIONS[evasion](text)
    assert "G18" in _hard(changed), f"{evasion} hid {text!r}: {changed!r}"


@pytest.mark.parametrize(
    "text",
    [
        "قو ام",
        "قو-ام",
        "ق.و.ا.م",
        "ق و ا م",
        "قـوام",
        "ٯوام",
        "Qa wam",
        "Q-a-w-a-m",
        "Qawaam",
        "Qawwam",
        "Q4wam",
        "Qаwаm",
    ],
)
def test_broken_up_or_altered_spellings_still_fail_g18(text):
    assert "G18" in _hard(text)


@pytest.mark.parametrize("text", FULL_NAMES)
def test_the_full_name_passes_g18(text):
    assert "G18" not in _hard(text)


@pytest.mark.parametrize("evasion", ["fatha", "kashida", "zero_width", "joiners", "extra_spaces"])
@pytest.mark.parametrize("text", ["قوام المال", "Qawam Money", "#قوام_المال", "#QawamMoney"])
def test_a_marked_up_full_name_still_passes_g18(text, evasion):
    assert "G18" not in _hard(EVASIONS[evasion](text))


@pytest.mark.parametrize(
    "text",
    [
        "وقوا ميزانيتكم",
        "قواميس اللغة",
        "الأقوام",
        "Qatar and Oman",
    ],
)
def test_a_word_that_only_resembles_the_name_passes_g18(text):
    assert "G18" not in _hard(text)


@pytest.mark.parametrize("text", BODY_SHAPE_COPY)
def test_body_shape_copy_near_the_name_fails_g18(text):
    assert "G18" in _hard(text)


@pytest.mark.parametrize("term", denylists.BODY_SHAPE_TERMS)
def test_every_body_shape_word_fails_near_the_name(term):
    assert "G18" in _hard(f"قوام المال {term}")


def test_body_shape_wording_far_from_the_name_is_not_this_rule():
    assert "G18" not in _hard("Fitness costs money")


def test_the_word_for_family_headship_gets_a_soft_flag_only():
    for text in ("القوامة في الأسرة", "قوامة الرجل"):
        assert "G18" not in _hard(text, family=True)
        assert "G18" in _soft(text, family=True)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("voice_script", "قوام يساعدك"),
        ("voice_script", "بقوام تعرف"),
        ("hook_ar", "قوام"),
        ("caption_ar", "جرب قوام"),
        ("caption_en", "Meet Qawam"),
        ("subtitles_en", "Qawam helps"),
        ("on_screen_en", ["Qawam"]),
        ("hashtags", ["#قوام"]),
        ("hashtags", ["@qawam"]),
    ],
)
def test_a_bare_name_fails_in_every_place_it_can_show(field, value):
    assert "G18" in _rules(_check(_script(**{field: value})))


@pytest.mark.parametrize(
    "value",
    [["Qawam", "Money"], ["قوام", "المال"], ["Qa", "wam"], ["ق", "و", "ا", "م"]],
)
def test_a_name_split_across_on_screen_lines_fails_g18(value):
    assert "G18" in _rules(_check(_script(on_screen_en=value)))


# --- Word-by-word captions ------------------------------------------------------------------


@pytest.mark.parametrize(
    "words",
    [
        ["هذا", "قوام", "المال"],
        ["this", "is", "Qawam", "Money"],
        ["قوام"],
        ["Qawam"],
    ],
)
def test_a_split_name_in_word_by_word_captions_fails_g18(words):
    report = check_caption_words(words)
    assert "G18" in _rules(report)


@pytest.mark.parametrize(
    "words",
    [
        ["هذا", "قوام المال"],
        ["this", "is", "Qawam Money"],
        ["#قوام_المال"],
    ],
)
def test_a_name_kept_in_one_token_passes_g18(words):
    assert "G18" not in _rules(check_caption_words(words))


@pytest.mark.parametrize("evasion", ["fatha", "kashida", "zero_width", "joiners"])
def test_marks_on_a_caption_word_do_not_hide_a_split_name(evasion):
    words = [EVASIONS[evasion]("قوام"), "المال"]
    assert "G18" in _rules(check_caption_words(words))


@pytest.mark.parametrize(
    ("words", "rule"),
    [
        (["link", "in", "bio"], "G11"),
        (["save", "30%"], "G2"),
        (["3", "clicks"], "G22"),
        (["راتب", "27"], "G5"),
    ],
)
def test_other_rules_also_read_across_caption_words(words, rule):
    assert rule in _rules(check_caption_words(words))


# --- G12 -----------------------------------------------------------------------------------


def _withdrawn_names() -> tuple[str, str]:
    return ("Wa" + "feer", "وف" + "يير")


@pytest.mark.parametrize(
    "text",
    [
        "BudgetTracker",
        "#BudgetTracker",
        "budget tracker",
        *_withdrawn_names(),
        *denylists.OLD_APP_NAMES,
        "Wá" + "feer",
    ],
)
def test_old_and_withdrawn_names_fail_g12(text):
    assert "G12" in _hard(text)
    assert "G12" in _hard(text, stage="filled", brand=LIVE_BRAND)


@pytest.mark.parametrize(
    "text", ["قوام المال", "Qawam Money", "#QawamMoney", "#قوام_المال", "قوام", "Qawam"]
)
def test_a_script_cannot_hard_code_the_name(text):
    assert "G12" in _hard(text)


@pytest.mark.parametrize(
    "text",
    ["{brand}", "{brand_x}", "{ brand_ar }", "{brand_ar", "brand_ar}", "brand_ar", "{BRAND_AR}"],
)
def test_a_mistyped_token_fails_g12(text):
    assert "G12" in _hard(text)


def test_a_look_alike_token_fails_g12():
    assert "G12" in _hard("{brand\u200d_ar}")
    assert "G12" in _hard("｛brand_ar｝")


def test_a_valid_token_passes_g12():
    assert "G12" not in _hard("{brand_ar} {brand_en}")
    assert "G12" not in _hard("{brand_en} {brand_ar}")
    assert "G12" not in _hard("{brand_hashtag}")


def test_a_script_cannot_hard_code_the_test_brand():
    config = load_config()
    script = _script(subtitles_en=f"This is {config.test_brand.name_en}")
    assert "G12" in _rules(_check(script))


@pytest.mark.parametrize(
    ("text", "language"),
    [
        ("{brand_en} {brand_ar}", "ar"),
        ("{brand_ar} {brand_en}", "en"),
        ("{brand_ar}", "ar"),
        ("{brand_en}", "en"),
        ("{brand_en}", "ar"),
    ],
)
def test_on_screen_text_shows_both_tokens_in_language_order(text, language):
    assert "G12" in _hard(text, language=language)


@pytest.mark.parametrize(
    ("text", "language"),
    [
        ("{brand_ar} {brand_en}", "ar"),
        ("{brand_en} {brand_ar}", "en"),
    ],
)
def test_the_right_order_passes_g12(text, language):
    assert "G12" not in _hard(text, language=language)


def test_voiceover_may_say_only_the_name_of_its_language():
    assert "G12" not in _hard("{brand_ar}، قريبًا.", language="ar", spoken=True)
    assert "G12" not in _hard("{brand_en}, coming soon.", language="en", spoken=True)
    assert "G12" in _hard("{brand_en}, قريبًا.", language="ar", spoken=True)


def test_a_hashtag_only_takes_the_hashtag_token():
    assert "G12" in _hard("{brand_ar}", hashtag=True)
    assert "G12" not in _hard("{brand_hashtag}", hashtag=True)


@pytest.mark.parametrize(
    ("text", "language"),
    [
        ("Qawam Money قوام المال", "ar"),
        ("قوام المال Qawam Money", "en"),
        ("قوام المال", "ar"),
        ("Qawam Money", "en"),
    ],
)
def test_filled_text_shows_both_names_in_language_order(text, language):
    assert "G12" in _hard(text, stage="filled", brand=LIVE_BRAND, language=language)


@pytest.mark.parametrize(
    ("text", "language"),
    [
        ("قوام المال Qawam Money", "ar"),
        ("Qawam Money قوام المال", "en"),
    ],
)
def test_filled_text_in_language_order_passes(text, language):
    assert _hard(text, stage="filled", brand=LIVE_BRAND, language=language) == set()


def test_a_test_reel_must_not_show_the_real_name():
    brand = brand_for_reel(load_config(), test_reel=True)
    assert "G12" in _hard("قوام المال", stage="filled", brand=brand)


def test_a_filled_test_reel_passes_the_brand_rules():
    brand = brand_for_reel(load_config(), test_reel=True)
    text = f"{brand.name_ar} {brand.name_en}"
    rules = _hard(text, stage="filled", brand=brand, language="ar")
    assert not rules & {"G12", "G18"}


def test_a_script_with_tokens_passes_at_both_stages():
    script = _script(
        voice_script="{brand_ar} يساعدك.",
        caption_ar="{brand_ar} {brand_en} يساعدك.",
        caption_en="{brand_en} {brand_ar} helps.",
        hashtags=["{brand_hashtag}"],
        claim_ids=["C10"],
    )
    assert _check(script).hard_failures == []


def test_a_test_reel_script_passes_with_the_test_brand():
    config = load_config()
    script = _script(voice_script="{brand_ar} يساعدك.", claim_ids=["C10"])
    report = check_script(script, config=config, brand=brand_for_reel(config, test_reel=True))
    assert report.hard_failures == []


# --- G13 -----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "Panda is cheaper than Lulu",
        "بنده أرخص من لولو",
        "Better than Mint",
        "أفضل من الراجحي",
        "Better than other apps",
        "أفضل تطبيق",
        "Tamimi vs Danube",
    ],
)
def test_comparisons_fail_g13(text):
    assert "G13" in _hard(text)


@pytest.mark.parametrize("name", denylists.COMPETING_APPS)
def test_every_competing_app_shown_as_better_fails_g13(name):
    assert "G13" in _hard(f"Better than {name}")


@pytest.mark.parametrize("evasion", ["fatha", "kashida", "zero_width", "extra_spaces", "upper"])
@pytest.mark.parametrize("text", ["Panda is cheaper", "بنده أرخص"])
def test_no_evasion_hides_a_comparison(text, evasion):
    assert "G13" in _hard(EVASIONS[evasion](text))


@pytest.mark.parametrize(
    "text",
    [
        "Compare a list before you shop",
        "Cheaper is not always better",
        "قارن قبل أن تشتري",
    ],
)
def test_general_shopping_tips_pass_g13(text):
    assert "G13" not in _hard(text)


# --- G14 -----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "Your receipts never leave your phone",
        "Never leaves your phone",
        "No AI sees your receipts",
        "لا يغادر جوالك",
        "الفواتير ما يطلع من جوالك",
        "لا يراها الذكاء الاصطناعي",
        "Your receipts stay on your device",
        "صور الفواتير على جهازك",
    ],
)
def test_privacy_overclaims_fail_g14(text):
    assert "G14" in _hard(text)


@pytest.mark.parametrize("evasion", ["fatha", "kashida", "zero_width", "extra_spaces", "upper"])
@pytest.mark.parametrize("text", ["No AI sees your receipts", "لا يغادر جوالك"])
def test_no_evasion_hides_a_privacy_overclaim(text, evasion):
    assert "G14" in _hard(EVASIONS[evasion](text))


@pytest.mark.parametrize(
    "text",
    [
        "The QR on the receipt is decoded on the device",
        "رمز QR في الفاتورة يُقرأ على الجهاز",
        "You review the receipt before saving",
        "Photograph a receipt and review it",
    ],
)
def test_true_privacy_statements_pass_g14(text):
    assert "G14" not in _hard(text)


# --- G17 -----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "Indistinguishable from a real creator",
        "Saudi voices sound human",
        "صوت بشري",
    ],
)
def test_claims_that_hide_the_synthetic_voice_fail_g17(text):
    assert "G17" in _hard(text)


def test_check_script_requires_the_disclosure_in_the_posted_caption():
    # compose_caption always adds it, so the final check sees it.
    assert "G17" not in _rules(_check(_script()))


@pytest.mark.parametrize("disclosure", ["", "   "])
def test_the_config_refuses_an_empty_disclosure(disclosure):
    with pytest.raises(ValueError):
        Captions(
            digits="western",
            disclaimer="x",
            ai_voice_disclosure=disclosure,
            max_hashtags={"instagram": 1, "facebook": 1, "tiktok": 1, "youtube": 1},
        )
