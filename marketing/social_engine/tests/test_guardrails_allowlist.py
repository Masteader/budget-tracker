"""What a script must match: figures against the facts, product statements against the claims.

These are the first layer of G1 and G2 (spec Section 6.5). A word list says what is banned and
misses the rest, so here anything that cannot be matched is refused.
"""

from datetime import date

import pytest
from guardrail_helpers import EVASIONS

from content_engine.cta import compose_caption, compose_voice, without_engine_lines
from content_engine.guardrails import (
    Claim,
    ClaimsRegister,
    GuardrailContext,
    check_script,
    check_text,
    figures_missing_from,
    load_claims_register,
)
from content_engine.schemas import ResearchResult, Script
from core.brand_gate import ReelBrand
from core.config import load_config

CONFIG = load_config()
BRAND = ReelBrand("قوام المال", "Qawam Money", "#QawamMoney", "logo.svg", is_test=False)
URL = "https://stats.example.org/report"
OTHER_URL = "https://stats.example.org/other"


def _facts(claim: str, url: str = URL):
    return ResearchResult.model_validate(
        {
            "facts": [
                {
                    "claim": claim,
                    "source_url": url,
                    "publisher": "Stats Office",
                    "accessed": date.today().isoformat(),
                    "paraphrase_ar": "يزيد الإنفاق في رمضان.",
                    "paraphrase_en": "Households buy more during Ramadan.",
                }
            ]
        }
    ).facts


def _script(**changes) -> Script:
    values = {
        "topic_id": "g001",
        "tier": "global",
        "template": "DailyTip",
        "language": "ar",
        "hook_ar": "وين تروح فلوسك؟",
        "voice_script": "اكتب مصاريفك كل أسبوع.",
        "on_screen_en": ["Where does it go?"],
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


def _rules(script: Script, facts=(), **kwargs) -> set[str]:
    report = check_script(script, config=CONFIG, brand=BRAND, facts=facts, **kwargs)
    return {finding.rule for finding in report.hard_failures}


def _cited(text: str, value: str, url: str = URL) -> Script:
    return _script(
        voice_script=text,
        numbers=[{"value": value, "source_url": url}],
        sources=[{"publisher": "Stats Office", "url": url}],
    )


def _hard(text: str, **context) -> set[str]:
    report = check_text(text, GuardrailContext(**context))
    return {finding.rule for finding in report.hard_failures}


def _soft(text: str, **context) -> set[str]:
    report = check_text(text, GuardrailContext(**context))
    return {finding.rule for finding in report.soft_flags}


# --- G2: a figure must match a fact ---------------------------------------------------------


@pytest.mark.parametrize(
    ("fact", "text", "value"),
    [
        ("Food prices rose 12% last year.", "الأسعار ارتفعت ١٢٪", "12%"),
        ("Food prices rose 12 percent.", "الأسعار ارتفعت 12%", "12%"),
        ("Prices rose twelve percent.", "Prices rose 12%", "12%"),
        ("A basket costs 500 riyals.", "السلة تكلف 500 ريال", "500 SAR"),
        ("A basket costs SAR 500.", "A basket costs 500 riyals", "500 ريال"),
        ("A basket costs 5,000 SAR.", "A basket costs 5000 SAR", "5,000 SAR"),
        ("A basket costs 5,000 SAR.", "تكلف 5 آلاف ريال", "5000 ريال"),
        ("A basket costs 1.2 million riyals.", "It costs 1.2 million SAR", "1.2 million SAR"),
        ("Bills rose 25 percent.", "ارتفعت خمسة وعشرين بالمية", "25%"),
        ("It costs 2x as much.", "It costs 2x as much", "2x"),
        ("About 1,500 households replied.", "1,500 households replied", "1500 households"),
    ],
)
def test_a_figure_that_a_fact_states_passes(fact, text, value):
    assert "G2" not in _rules(_cited(text, value), _facts(fact))


@pytest.mark.parametrize(
    ("fact", "text", "value"),
    [
        pytest.param("Prices rose 12%.", "Prices rose 70%", "70%", id="another value"),
        pytest.param("Prices rose 12%.", "Prices rose 12%", "70%", id="numbers holds another"),
        pytest.param("Prices rose 12%.", "A rise of 12 riyals", "12%", id="percent is not money"),
        pytest.param("It costs 12 SAR.", "A rise of 12%", "12 SAR", id="money is not percent"),
        pytest.param("It costs 12 SAR.", "Grew 12x", "12 SAR", id="money is not a multiplier"),
        pytest.param("It costs 500 SAR.", "It costs 500 دولار", "500 SAR", id="another currency"),
        pytest.param("It costs 500 USD.", "It costs 500 USD", "500 SAR", id="fact's currency"),
        pytest.param("It costs 500 SAR.", "It costs 500 SAR", "500", id="a bare value"),
        pytest.param("Prices rose.", "Prices rose 12%", "12%", id="a fact with no figure"),
        pytest.param("Prices rose 12%.", "Prices rose 12%", "a lot", id="no figure in the value"),
    ],
)
def test_a_figure_no_fact_states_fails(fact, text, value):
    assert "G2" in _rules(_cited(text, value), _facts(fact))


def test_a_fact_from_another_source_does_not_prove_a_figure():
    assert "G2" in _rules(_cited("Prices rose 12%", "12%"), _facts("Prices rose 12%.", OTHER_URL))


def test_a_plain_number_in_the_list_must_be_in_the_fact_but_clears_no_figure():
    # The list reaches the owner on Telegram, so what it shows must be true as well.
    assert "G2" not in _rules(_cited("اكتب مصاريفك.", "70"), _facts("Of the 70 households."))
    assert "G2" in _rules(_cited("اكتب مصاريفك.", "71"), _facts("Of the 70 households."))
    assert "G2" in _rules(_cited("وفر 70 ريال", "70"), _facts("Of the 70 households."))


def test_an_unproved_entry_in_the_list_fails_even_if_the_text_never_says_it():
    assert "G2" in _rules(_cited("اكتب مصاريفك.", "70%"), _facts("Prices rose 12%."))


def test_a_30_percent_fact_is_still_refused():
    assert "G2" in _rules(_cited("Prices rose 30%", "30%"), _facts("Prices rose 30%."))


def test_a_figure_in_an_approved_claim_the_script_uses_passes():
    claim = Claim(
        id="C90",
        meaning="VAT rate",
        wording_ar="الضريبة 15%",
        wording_en="VAT is 15%",
        evidence=(),
        last_checked=date(2026, 11, 4),
        code_check="supported",
        code_note="",
        clip_folders=(),
    )
    register = ClaimsRegister({"C90": claim}, ())
    script = _script(voice_script="{brand_ar}: VAT is 15%", claim_ids=["C90"])
    assert "G2" not in _rules(script, register=register)
    other = _script(voice_script="{brand_ar}: VAT is 16%", claim_ids=["C90"])
    assert "G2" in _rules(other, register=register)


@pytest.mark.parametrize(
    "text",
    [
        "مثال: إيجار 3000 ريال",
        "Example: a rent of SAR 3,000",
        "راتبك 27,000 ريال مثلا",
        "e.g. a rent of SAR 3,000",
    ],
)
def test_an_example_label_in_the_sentence_covers_a_figure(text):
    assert "G2" not in _hard(text)


@pytest.mark.parametrize(
    "text",
    [
        "Here is an example. Save 70% every month.",
        "مثال بسيط! وفر 70% كل شهر",
        "An example\nSave 70%",
    ],
)
def test_an_example_label_does_not_reach_into_another_sentence(text):
    assert "G2" in _hard(text)


@pytest.mark.parametrize(
    "text",
    [
        "وفر 500 ريالاً كل شهر",
        "وفر خمسين ريال",
        "Save 500$ a month",
        "Save $ 500",
        "Save 20€",
        "Save ﷼ 500",
        "500 ⃁",
        "ريالين",
        "خمسمية ريال",
        "ألف وخمسمية ريال",
        "Save five hundred and fifty riyals",
        "Save fifty SAR",
        "SAR fifty",
        "Save 1,000 every month",
        "Save 1,000",
        "Save a thousand",
        "Save half your salary",
        "نص راتبك توفير",
        "وفر ٥٠٠ كل شهر",
        "وفر ٥٫٥ ٪",
        "Pay 50 a month",
        "ادفع 200 كل شهر",
        "Cut it by 2,500",
        "5 آلاف ريال",
        "5k SAR",
        "ثلاثين ٪ من راتبك",
        "% خمسين",
        "نسبة 40",
        "بنسبة ٤٠",
        "خمسة بالمية",
        "ثلاثين بلمية",
        "Save twenty five percent",
        "ضعف راتبك",
        "ضعف الراتب",
        "3 أضعاف",
        "3×",
        "3-fold",
        "four times cheaper",
    ],
)
def test_a_figure_with_no_source_fails_however_it_is_written(text):
    assert "G2" in _hard(text)


@pytest.mark.parametrize("evasion", EVASIONS, ids=str)
@pytest.mark.parametrize("text", ["وفر خمسين ريال", "Save fifty riyals", "ضعف راتبك", "Save 1,000"])
def test_no_evasion_hides_a_written_out_figure(text, evasion):
    changed = EVASIONS[evasion](text)
    assert "G2" in _hard(changed), f"{evasion} hid {text!r}: {changed!r}"


@pytest.mark.parametrize(
    "text",
    [
        "Keep 3 months of expenses aside",
        "Spend 10 minutes a week on this",
        "Save 10 minutes a week",
        "Pay 3 bills on time",
        "3 خطوات قبل التسوق",
        "Review 365 days of spending",
        "The 2026 budget",
        "ميزانية 1447",
        "ضعف الشبكة مو عذر",
        "كل ريال له مهمة",
        "Give every riyal a job",
        "عشر دقايق كل أسبوع",
    ],
)
def test_ordinary_numbers_and_words_are_no_figures(text):
    assert "G2" not in _hard(text)


def test_figures_missing_from_compares_numbers_only():
    assert figures_missing_from("Rose 12%", "up by 12 percent") == []
    assert figures_missing_from("Rose 12%", "up by twelve percent") == []
    assert figures_missing_from("Rose 12%", "up by 13 percent")
    assert figures_missing_from("No figure here", "") == []


# --- G1: a product statement must stay within its claims ------------------------------------


def test_a_general_tip_with_no_claims_passes_every_rule():
    assert _rules(_script(hashtags=["{brand_hashtag}", "#budgeting"])) == set()


def test_a_script_that_ignored_the_prompt_and_wrote_the_closing_lines_still_passes():
    wording = CONFIG.cta.coming_soon
    disclaimer = CONFIG.captions.disclaimer
    disclosure = CONFIG.captions.ai_voice_disclosure
    script = _script(
        voice_script=f"اكتب مصاريفك كل أسبوع. {wording.voice_ar}",
        caption_ar=f"اكتب مصاريفك.\n{wording.caption_ar}\n{disclaimer}\n{disclosure}",
        caption_en=f"Write it down.\n{wording.caption_en}\n{disclaimer}\n{disclosure}",
    )
    assert _rules(script) == set()


def test_a_brand_token_with_no_claim_is_still_a_product_statement():
    assert "G1" in _rules(_script(voice_script="{brand_ar} يساعدك تكتب مصاريفك."))
    assert "G1" in _rules(_script(caption_en="{brand_en} {brand_ar} tracks your spending."))


def _check_claim(text: str, *claim_ids: str) -> set[str]:
    return _hard(text, claim_ids=frozenset(claim_ids))


@pytest.mark.parametrize(
    ("text", "claim"),
    [
        ("{brand_ar} يساعدك.", "C10"),
        ("{brand_en} helps you.", "C10"),
        ("Type an expense in {brand_en} and confirm it.", "C07"),
        ("اكتب مصروفك في {brand_ar} بلغتك اليومية وأكده.", "C07"),
        ("{brand_ar} يتابع خطط الأقساط والقسط القادم.", "C14"),
        ("{brand_ar} يحجز الفواتير الشهرية قبل الراتب القادم.", "C13"),
        ("سجل مصروفك بالعربية في التطبيق.", "C07"),
        ("The app shows how the price of an item changed, from your own receipts.", "C15"),
        ("Tracks installment plans and the next due date.", "C14"),
        ("يتابع خطط الأقساط.", "C14"),
    ],
)
def test_a_statement_close_to_its_claim_passes_g1(text, claim):
    assert "G1" not in _check_claim(text, claim)


@pytest.mark.parametrize(
    ("text", "claim"),
    [
        ("{brand_en} predicts your salary and invests it for you.", "C07"),
        ("The app negotiates your rent with the landlord.", "C10"),
        ("{brand_ar} يتفاوض مع المالك على الايجار.", "C10"),
        ("Reads your bank alerts automatically", "C07"),
        ("It imports your history from anywhere.", "C14"),
        ("يستورد سجلك من أي مكان.", "C14"),
    ],
)
def test_a_statement_beyond_its_claim_fails_g1(text, claim):
    assert "G1" in _check_claim(text, claim)


@pytest.mark.parametrize("text", ["Reads your bank alerts automatically", "يستورد مصاريفك كلها"])
def test_a_statement_with_its_subject_left_out_is_still_about_the_app(text):
    assert "G1" in _hard(text)


def test_every_claim_wording_stays_within_its_own_claim():
    for claim in load_claims_register().approved:
        for wording in (claim.wording_ar, claim.wording_en):
            assert "G1" not in _check_claim(wording, claim.id), wording


# --- Soft where it should be hard ------------------------------------------------------------


@pytest.mark.parametrize(
    ("rule", "text"),
    [
        ("G8", "Don't wait, get a low-interest loan today"),
        ("G8", "A personal loan is the smart way to cover Eid"),
        ("G8", "Get the best loan, no risk"),
        ("G8", "قرض بدون خطر"),
        ("G8", "Why not take a loan?"),
        ("G8", "Loans, get them today"),
        ("G21", "الرمز يكشف غلاء الأسعار"),
        ("G21", "Scan the barcode to track prices"),
        ("G6", "You and your wife each pay half of the rent"),
        ("G6", "Your wife pays half"),
        ("G4", "Reads your bank alerts automatically"),
        ("G4", "It scans your notifications"),
    ],
)
def test_each_now_fails_hard(rule, text):
    assert rule in _hard(text)


@pytest.mark.parametrize(
    "text",
    [
        "Don't take a loan, get a budget instead",
        "A loan is not the solution",
        "القرض مو حل",
        "Use the tracker to pay your loan on time",
        "Avoid high-interest loans",
    ],
)
def test_a_warning_stays_soft(text):
    assert "G8" not in _hard(text)
    assert "G8" in _soft(text)


def test_the_word_for_a_month_is_not_a_rate():
    assert "G8" not in _hard("Get paid in Apr or May") | _soft("Get paid in Apr or May")
    assert "G8" in _hard("Get a low APR card")


def test_ones_best_interest_is_not_a_charge():
    assert not {"G8"} & (_hard("Get what is in your best interest") | _soft("Your best interest"))


# --- False positives, against the real rules --------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        # Rule 02 section 3: the household's expenses are the husband's.
        "A wife does not have to pay household expenses.",
        "She should not have to pay for the home.",
        "The husband must pay the household expenses, not his wife.",
        "الزوجة مو لازم تدفع مصاريف البيت",
        "الزوج لازم يدفع، وزوجته تدفع إذا تبي",
    ],
)
def test_the_family_rule_itself_passes_g7(text):
    assert "G7" not in _hard(text)


@pytest.mark.parametrize(
    "text",
    [
        "Your wife should pay",
        "Your wife? She must pay!",
        "لازم زوجتك تدفع",
        "Let your wife pay the rent",
    ],
)
def test_a_wife_being_told_to_pay_still_fails_g7(text):
    assert "G7" in _hard(text)


@pytest.mark.parametrize(
    "text", ["The default is the 27th, and you can always change it", "ويمكنك تغييره، الافتراضي 27"]
)
def test_default_and_change_wording_still_passes_g5(text):
    assert "G5" not in _hard(text)


@pytest.mark.parametrize(
    "text",
    [
        "The default is the 27th and it is fixed",
        "Payday is always the 27th, no default, no changes.",
    ],
)
def test_default_wording_that_takes_it_back_fails_g5(text):
    assert "G5" in _hard(text)


@pytest.mark.parametrize(
    "text",
    [
        "راتبك 27,000 ريال مثلا",
        "the 27 items you bought",
        "يوم 27 رمضان ترتفع المصاريف",
        "On the 27 of April the shop opens",
        "A salary of 27 thousand, for example",
    ],
)
def test_27_as_something_else_is_not_a_payday(text):
    assert "G5" not in _hard(text)


def test_an_allowance_is_not_a_contrast_with_banks():
    text = "بدل السكن ينزل في البنك"
    assert "G20" not in _hard(text)
    assert "G20" in _soft(text)
    assert "G20" in _hard("بدل البنك")


def test_ordinary_advice_near_the_word_bank_is_soft():
    text = "Best practice: check your bank statement monthly"
    assert "G20" not in _hard(text)
    assert "G20" in _soft(text)
    assert "G20" in _hard("The best bank")


def test_a_check_before_buying_is_not_advice_to_buy():
    assert "G9" not in _hard("Before you buy this, check your budget")
    assert "G9" not in _hard("قبل ما تشتري ذهب، راجع ميزانيتك")
    assert "G9" in _hard("Buy this now")
    assert "G9" in _hard("Buy Aramco shares")


def test_its_line_item_is_not_the_store():
    assert "G19" not in _hard("كل مصروف له بنده في الميزانية")
    assert "G19" in _hard("سعرها في بنده")


def test_the_contents_of_a_bill_are_not_a_guarantee():
    assert "G1" not in _hard("مضمون الفاتورة واضح", claim_ids=frozenset({"C10"}))
    assert "G1" in _hard("التوفير مضمون", claim_ids=frozenset({"C10"}))


def test_available_only_counts_with_a_place_to_get_the_app():
    assert "G11" not in _hard("Check the cash available on payday.")
    assert "G11" in _hard("Available on Android")


def test_loading_someone_with_costs_is_not_download_wording():
    assert "G11" not in _hard("لا يجوز تحميل الزوجة مصاريف البيت")
    assert "G11" in _hard("تحميل التطبيق")


# --- One owner for the closing lines ------------------------------------------------------------


@pytest.mark.parametrize("language", ["ar", "en"])
def test_a_compliant_script_speaks_its_closing_line_once(language):
    cta = {"ar": "قوام المال، قريبًا.", "en": "Qawam Money, coming soon."}[language]
    voice = compose_voice("Write it down every week.", language, CONFIG, BRAND)
    assert voice == f"Write it down every week. {cta}"
    assert voice.count(cta) == 1


@pytest.mark.parametrize("language", ["ar", "en"])
def test_a_compliant_caption_carries_each_line_once(language):
    caption = compose_caption("Write it down.", language, CONFIG, BRAND)
    assert caption.count(CONFIG.captions.disclaimer) == 1
    assert caption.count(CONFIG.captions.ai_voice_disclosure) == 1


@pytest.mark.parametrize(
    "copy",
    [
        "{brand_en}, coming soon.",
        "{brand_en} coming soon",
        "{brand_en}, COMING SOON!",
        "{brand_en},  coming   soon .",
    ],
)
def test_a_copy_of_the_closing_line_is_dropped_however_it_is_punctuated(copy):
    voice = compose_voice(f"Write it down. {copy}", "en", CONFIG, BRAND)
    assert voice == "Write it down. Qawam Money, coming soon."


def test_composing_twice_changes_nothing():
    body = "Write it down."
    once = compose_voice(body, "en", CONFIG, BRAND)
    wording = CONFIG.cta.coming_soon
    assert compose_voice(f"{body} {wording.voice_en}", "en", CONFIG, BRAND) == once


def test_a_script_of_only_the_closing_line_is_just_that_line():
    assert compose_voice(CONFIG.cta.coming_soon.voice_en, "en", CONFIG, BRAND) == (
        "Qawam Money, coming soon."
    )


def test_text_without_the_closing_lines_is_left_as_it_was():
    text = "First line.\n\nSecond  line."
    assert without_engine_lines(text, CONFIG) == text


def test_a_sentence_that_only_resembles_the_closing_line_stays():
    text = "It is not coming soon."
    assert without_engine_lines(text, CONFIG) == text


# --- Rules that hold across the hook and the voice ---------------------------------------------


@pytest.mark.parametrize(
    ("hook", "voice", "rule"),
    [
        ("متى ينزل راتبك؟", "٢٧ دايم.", "G5"),
        ("زوجتك؟", "لازم تدفع.", "G7"),
        ("سلتك كل اسبوع غالية؟", "وفر فلوسك هذا الشهر.", "G19"),
    ],
)
def test_a_rule_holds_across_the_hook_and_the_voice(hook, voice, rule):
    assert rule in _rules(_script(hook_ar=hook, voice_script=voice))
