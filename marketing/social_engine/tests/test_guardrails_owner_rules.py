"""Owner-decision rules G19, G20, G21 and G22 (decisions D29, D30, D32, task C5).

Also proves the rejected claims register: a dropped claim stays enforced, because every sample
in `rejected_claims` has to fail the guardrail the register names for it.
"""

import pytest
from guardrail_helpers import EVASIONS

from content_engine import denylists
from content_engine.guardrails import (
    GuardrailContext,
    check_script,
    check_text,
    load_claims_register,
)
from content_engine.schemas import Script
from core.brand_gate import ReelBrand
from core.config import load_config

LIVE_BRAND = ReelBrand("قوام المال", "Qawam Money", "#QawamMoney", "logo.svg", is_test=False)
MARKS = ["fatha", "kashida", "zero_width", "joiners", "spaced_letters", "extra_spaces", "upper"]


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
        "topic_id": "s001",
        "tier": "saudi",
        "template": "FeatureDemo",
        "language": "ar",
        "hook_ar": "قائمة مشترياتك كيف تطلع بين المتاجر؟",
        "voice_script": "السلة الذكية تقارن قائمة مشتريات بين المتاجر، وأسعارها توضيحية.",
        "on_screen_en": ["Compare a list across stores"],
        "subtitles_en": "Smart Basket compares a shopping list across stores inside the app.",
        "feature_clip_folder": "smart_basket",
        "claim_ids": ["C21"],
        "numbers": [],
        "sources": [],
        "caption_ar": "السلة الذكية تقارن قائمة مشتريات. أسعارها توضيحية.",
        "caption_en": "Smart Basket compares a shopping list. Its prices are illustrative.",
        "hashtags": ["#budgeting"],
        "speech_seconds_estimate": 20.0,
    }
    return Script(**{**values, **changes})


def _check(script: Script):
    return check_script(script, config=load_config(), brand=LIVE_BRAND)


# --- G19: Smart Basket (D30) ---------------------------------------------------------------


@pytest.mark.parametrize("name", denylists.STORE_NAMES)
def test_every_store_name_fails_g19(name):
    assert "G19" in _hard(f"Prices at {name}")


@pytest.mark.parametrize("evasion", MARKS, ids=str)
@pytest.mark.parametrize("name", ["Panda", "Danube", "بنده", "الدانوب", "التميمي", "كارفور"])
def test_no_evasion_hides_a_store_name(name, evasion):
    assert "G19" in _hard(EVASIONS[evasion](name))


@pytest.mark.parametrize(
    "text",
    [
        "وفرت من سلتي الذكية",
        "السلة الذكية وفرت لي",
        "You save with Smart Basket",
        "Smart Basket shows where it is cheaper",
        "Smart Basket: cheaper at the first store",
        "السلة الذكية تعرف الأرخص",
        "أرخص سلة",
        "Smart Basket saves you real money",
        "Your basket saved money",
    ],
)
def test_saving_wording_tied_to_the_basket_fails_g19(text):
    assert "G19" in _hard(text)


@pytest.mark.parametrize("evasion", MARKS, ids=str)
@pytest.mark.parametrize("text", ["السلة الذكية وفرت لي", "You save with Smart Basket"])
def test_no_evasion_hides_a_basket_saving_claim(text, evasion):
    assert "G19" in _hard(EVASIONS[evasion](text))


@pytest.mark.parametrize(
    "text",
    [
        "Smart Basket compares a shopping list across stores inside the app.",
        "Its prices are illustrative.",
        "السلة الذكية تقارن قائمة مشتريات بين المتاجر داخل التطبيق، وأسعارها توضيحية.",
    ],
)
def test_neutral_c21_wording_passes_g19(text):
    assert "G19" not in _hard(text, basket=True)


@pytest.mark.parametrize("text", ["Save a little every month", "كيف توفر من مقاضي البيت؟"])
def test_saving_wording_with_no_basket_is_not_this_rule(text):
    assert "G19" not in _hard(text)


@pytest.mark.parametrize("text", ["You save with this", "وفرت كثير", "It is cheaper this way"])
def test_saving_wording_anywhere_in_a_basket_reel_fails(text):
    assert "G19" in _hard(text, basket=True)


def test_a_neutral_smart_basket_script_passes():
    assert _check(_script()).hard_failures == []


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("voice_script", "وفرت كثير."),
        ("subtitles_en", "You save with this."),
        ("caption_ar", "الأرخص هنا."),
        ("caption_en", "Cheaper at the first store."),
        ("on_screen_en", ["You save"]),
    ],
)
def test_a_saving_claim_in_any_field_of_a_basket_reel_fails(field, value):
    assert "G19" in _rules(_check(_script(**{field: value})))


@pytest.mark.parametrize(
    "changes",
    [
        {"feature_clip_folder": "smart_basket", "claim_ids": ["C21"]},
        {"feature_clip_folder": None, "claim_ids": ["C21"], "template": "DailyTip"},
    ],
)
def test_a_reel_is_a_basket_reel_by_its_clip_or_its_claim(changes):
    script = _script(subtitles_en="You save with this.", **changes)
    assert "G19" in _rules(_check(script))


def test_a_reel_that_names_smart_basket_is_a_basket_reel():
    script = _script(
        template="DailyTip",
        feature_clip_folder=None,
        claim_ids=["C21"],
        voice_script="اكتب قائمة قبل التسوق.",
        subtitles_en="Smart Basket compares a shopping list.",
        caption_en="You save with this.",
    )
    assert "G19" in _rules(_check(script))


# --- G20: no banks (D29) -------------------------------------------------------------------


@pytest.mark.parametrize("name", denylists.BANK_AND_WALLET_NAMES)
def test_every_bank_and_wallet_name_fails_g20(name):
    assert "G20" in _hard(f"Your balance at {name}")


@pytest.mark.parametrize("evasion", MARKS, ids=str)
@pytest.mark.parametrize(
    "name", ["Al Rajhi", "STC Pay", "Urpay", "الراجحي", "بنك الرياض", "تمارا"]
)
def test_no_evasion_hides_a_bank_name(name, evasion):
    assert "G20" in _hard(EVASIONS[evasion](name))


@pytest.mark.parametrize(
    "text",
    [
        "Better than your bank app",
        "أفضل من تطبيق البنك",
        "Unlike your bank",
        "بدل البنك",
        "Instead of bank SMS",
        "Banks are worse at this",
        "Connect your bank",
        "اربط حسابك البنكي",
        "Tracking multiple bank accounts",
        "Tracking multiple bank/e-wallet accounts",
    ],
)
def test_bank_comparison_and_bank_features_fail_g20(text):
    assert "G20" in _hard(text)


@pytest.mark.parametrize("evasion", MARKS, ids=str)
@pytest.mark.parametrize("text", ["Better than your bank app", "أفضل من تطبيق البنك"])
def test_no_evasion_hides_a_bank_comparison(text, evasion):
    assert "G20" in _hard(EVASIONS[evasion](text))


@pytest.mark.parametrize("text", ["A bank", "بنك", "Your bank closes early", "البنوك مقفلة"])
def test_the_plain_word_bank_is_a_soft_flag(text):
    assert "G20" not in _hard(text)
    assert "G20" in _soft(text)


@pytest.mark.parametrize(
    "text",
    [
        "Main account, wallet and cash",
        "Add accounts by hand",
        "الوطن والبلاد والجزيرة",
        "Lightning and island",
    ],
)
def test_generic_account_wording_and_ordinary_words_pass_g20(text):
    assert "G20" not in _hard(text)
    assert "G20" not in _soft(text)


def test_contrast_with_bank_sms_fails_both_rules():
    assert {"G4", "G20"} <= _hard("Better than unorganized bank SMS")
    assert "G4" in _hard("بدل رسائل البنك")


# --- G21: price tracking source (D32) ------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "Scanning digital ZATCA tax receipts to spot price inflation",
        "Track prices with the QR",
        "Scan the QR to see inflation",
        "The QR tracks what you pay",
        "ZATCA-powered price tracker",
        "امسح رمز زاتكا لتتبع الأسعار",
        "رمز QR يكشف الغلاء",
        "الباركود يتابع الأسعار",
        "See how you compare with market prices",
        "Live prices from the market",
        "نقارن فواتيرك بأسعار السوق",
    ],
)
def test_qr_price_tracking_and_market_prices_fail_g21(text):
    assert "G21" in _hard(text)


@pytest.mark.parametrize("evasion", MARKS, ids=str)
@pytest.mark.parametrize("text", ["Track prices with the QR", "أسعار السوق", "market prices"])
def test_no_evasion_hides_a_price_source_claim(text, evasion):
    assert "G21" in _hard(EVASIONS[evasion](text))


def test_a_separate_sentence_does_not_hide_the_link():
    assert "G21" in _hard("Scan the QR. Then see your prices.")


@pytest.mark.parametrize(
    "text",
    [
        "Line items from your own receipts",
        "Shows how the price of an item you bought changed, using the line items from your own "
        "saved receipts, not the ZATCA QR.",
        "يعرض كيف تغيّر سعر سلعة اشتريتها، من بنود فواتيرك المحفوظة أنت، وليس من رمز زاتكا.",
        "The app decodes the QR on Saudi e-invoices on the device.",
        "يقرأ التطبيق رمز QR في الفواتير الإلكترونية السعودية على الجهاز.",
    ],
)
def test_approved_price_and_qr_wording_passes_g21(text):
    assert "G21" not in _hard(text)


def test_denying_the_qr_does_not_excuse_claiming_it_elsewhere():
    assert "G21" in _hard("Track prices with the QR, not the ZATCA QR")


# --- G22: no click counts (D32) ------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "3 clicks",
        "3 Clicks",
        "3clicks",
        "3-click budget",
        "three clicks",
        "one tap",
        "1-tap transfer",
        "two taps",
        "a single click",
        "tap 3 times",
        "a few taps",
        "a couple of clicks",
        "كم ضغطة",
        "3 نقرات",
        "٣ نقرات",
        "ثلاث نقرات",
        "بضغطة واحدة",
        "بضغطة زر",
        "ضغطتين",
        "نقرتين",
        "بكبسة زر",
    ],
)
def test_click_and_tap_counts_fail_g22(text):
    assert "G22" in _hard(text)


@pytest.mark.parametrize("evasion", MARKS, ids=str)
@pytest.mark.parametrize("text", ["3 clicks", "3 نقرات", "بضغطة واحدة"])
def test_no_evasion_hides_a_click_count(text, evasion):
    assert "G22" in _hard(EVASIONS[evasion](text))


@pytest.mark.parametrize(
    "text",
    [
        "3 خطوات",
        "ثلاث خطوات قبل التسوق",
        "3 steps before you shop",
        "Tap Approve to confirm",
        "Click here",
        "ضغط المصاريف",
    ],
)
def test_step_counts_and_ordinary_wording_pass_g22(text):
    assert "G22" not in _hard(text)


# --- The rejected claims register ----------------------------------------------------------


def _rejected_samples():
    for row in load_claims_register().rejected:
        for sample in (*row.samples_ar, *row.samples_en):
            yield row.id, row.caught_by, sample


REJECTED_SAMPLES = list(_rejected_samples())


@pytest.mark.parametrize(("rejected_id", "caught_by", "sample"), REJECTED_SAMPLES)
def test_every_rejected_sample_fails_a_guardrail_it_names(rejected_id, caught_by, sample):
    assert _hard(sample) & set(caught_by), f"{rejected_id} sample passed: {sample}"


@pytest.mark.parametrize("evasion", EVASIONS, ids=str)
@pytest.mark.parametrize(("rejected_id", "caught_by", "sample"), REJECTED_SAMPLES)
def test_no_evasion_gets_a_rejected_sample_through(rejected_id, caught_by, sample, evasion):
    changed = EVASIONS[evasion](sample)
    assert _hard(changed) & set(caught_by), f"{rejected_id} {evasion} passed: {changed}"


def test_every_rejected_row_has_a_sample_in_each_language():
    for row in load_claims_register().rejected:
        assert row.samples_ar
        assert row.samples_en


def test_the_config_holds_no_rejected_sample():
    config_text = load_config().model_dump_json()
    for _, _, sample in REJECTED_SAMPLES:
        assert sample not in config_text


def test_the_config_strings_pass_the_owner_rules():
    config = load_config()
    wording = config.cta.coming_soon
    for text in (
        wording.bio_ar,
        wording.bio_en,
        wording.caption_ar,
        wording.caption_en,
        wording.voice_ar,
        wording.voice_en,
        config.captions.disclaimer,
        config.captions.ai_voice_disclosure,
        config.brand.tagline_ar,
        config.brand.tagline_en,
    ):
        assert not _hard(text) & {"G2", "G4", "G5", "G11", "G19", "G20", "G21", "G22"}, text
