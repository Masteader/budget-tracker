"""Deterministic guardrails G1 to G10 (spec Section 6.5, task C2).

Exact strings are not enough, because word lists are easy to walk around. Every failing
sample also runs through the evasions in `EVASIONS`: diacritics, kashida, spacing, hidden
characters, look-alike letters and digit forms.
"""

import pytest
from guardrail_helpers import EVASIONS, with_fatha, with_kashida

from content_engine import denylists
from content_engine.guardrails import (
    GuardrailContext,
    check_claim_ids,
    check_research_use,
    check_script,
    check_text,
    lexicon_form,
    load_claims_register,
)
from content_engine.schemas import ResearchFact, Script
from core.brand_gate import ReelBrand
from core.config import load_config

LIVE_BRAND = ReelBrand("قوام المال", "Qawam Money", "#QawamMoney", "logo.svg", is_test=False)


def hard(text: str, **context) -> set[str]:
    report = check_text(text, GuardrailContext(**context))
    return {finding.rule for finding in report.hard_failures}


def soft(text: str, **context) -> set[str]:
    report = check_text(text, GuardrailContext(**context))
    return {finding.rule for finding in report.soft_flags}


FAILING = {
    "G2": [
        "Save 30%",
        "Save 25% on groceries",
        "costs you 30% more",
        "كيف توفر 30% من مقاضي البيت؟",
        "وفر 20 بالمئة من راتبك",
        "Spend SAR 500 less",
        "وفر 500 ريال",
        "Grow your money 3x",
    ],
    "G4": [
        "Messy notes and unorganized bank SMS",
        "The app reads your messages",
        "It auto-imports from your bank",
        "SMS",
        "رسائل البنك",
        "رسالة البنك",
        "يقرأ رسائلك",
        "بدل مسجات البنك",
    ],
    "G5": [
        "Payday cycle 27",
        "Payday 27th HUD",
        "27th-to-27th",
        "Your salary comes on the 27th",
        "#راتب_27",
        "راتبك ينزل يوم 27",
        "الراتب كل 27 من الشهر",
        "دورة الراتب من 27 إلى 27",
    ],
    "G6": [
        "Split the bills with your wife",
        "Go 50/50 with your husband",
        "Your wife pays 40% of the rent",
        "A 70/30 split between husband and wife",
        "نص بنص مع زوجتك",
        "مناصفة بين الزوج والزوجة",
        "زوجتك تدفع 30 بالمئة",
        "قسم المصاريف مع زوجك",
        "بالنص مع المدام",
    ],
    "G7": [
        "Your wife should pay her share of the rent",
        "A wife must contribute to the bills",
        "She sets her own allowance",
        "The wife owes her husband for the groceries",
        "زوجتك لازم تدفع الإيجار",
        "المفروض الزوجة تساهم في مصاريف البيت",
        "حصة الزوجة من الإيجار",
        "هي تحدد مصروفها بنفسها",
    ],
    "G8": [
        "Get the best personal loan today",
        "Apply for a credit card with low APR",
        "Earn interest on your savings",
        "Use buy now pay later for your shopping",
        "احصل على قرض فوري",
        "قدم على بطاقة ائتمان بأفضل عرض",
        "اربح فوائد على مدخراتك",
    ],
    "G9": [
        "You should invest in gold",
        "Buy this stock now",
        "Put your savings in crypto",
        "The best investment for you",
        "لازم تستثمر في الذهب",
        "اشتر هذا السهم",
        "ننصحك تشتري عقار",
        "حط فلوسك في الذهب",
        "Buy gold today",
    ],
    "G10": [
        "Sharia-certified budgeting",
        "A halal-approved app",
        "ZATCA-approved receipts",
        "SAMA-licensed",
        "Licensed by SAMA",
        "معتمد من هيئة الزكاة",
        "مرخص من ساما",
        "متوافق مع الشريعة ومعتمد",
    ],
}

PASSING = {
    "G2": [
        "Your salary goes faster than you think",
        "Keep 3 months of expenses aside",
        "Example: a rent of SAR 3,000",
        "مثال: إيجار 3000 ريال",
        "مثلًا: 500 ريال للمقاضي",
        "50/30/20 versus zero-based",
        "30 days in a month",
        "ثلاثين يوم في الشهر",
    ],
    "G4": [
        "Messy notes and memory",
        "ملاحظات مبعثرة والذاكرة",
        "A settle message you can copy",
        "رسالة تسوية يمكنك نسخها",
    ],
    "G5": [
        "Your household's payday",
        "The default is the 27th, and you can change it",
        "الافتراضي يوم 27، ويمكنك تغييره",
        "Rent is due in 27 days",
        "يوم راتب أسرتك",
    ],
    "G6": [
        "Split rent fairly with your roommates",
        "Go 50/50 with your flatmate",
        "قسم الإيجار مع زملاء السكن بالتساوي",
        "Shared expenses are the husband's",
        "نفقة البيت على الزوج",
        "Fair rent splits between roommates",
    ],
    "G7": [
        "Nafaqah is the husband's responsibility",
        "What the wife pays for shared needs is a debt he owes her",
        "Her personal spending comes from her allowance",
        "Her husband or an admin sets her allowance",
        "النفقة على الزوج",
        "ما تدفعه الزوجة للبيت دين عليه لها",
        "Any contribution she makes is voluntary",
        "Her voluntary contribution is her own choice",
    ],
    "G8": [
        "Track your installment plan",
        "تابع أقساطك",
        "Know when your next installment is due",
    ],
    "G9": [
        "Write your spending down every week",
        "A general tip: review your subscriptions",
        "General information, not financial advice",
        "معلومات عامة وليست نصيحة مالية",
    ],
    "G10": [
        "Reads the QR on Saudi e-invoices",
        "The app records Nafaqah",
        "معلومات عامة",
    ],
}


def _failing_cases():
    for rule, samples in FAILING.items():
        for sample in samples:
            yield rule, sample


@pytest.mark.parametrize(("rule", "text"), list(_failing_cases()))
def test_each_failing_sample_fails_its_rule(rule, text):
    assert rule in hard(text)


@pytest.mark.parametrize("evasion", EVASIONS, ids=str)
@pytest.mark.parametrize(("rule", "text"), list(_failing_cases()))
def test_no_evasion_gets_a_failing_sample_past_its_rule(rule, text, evasion):
    changed = EVASIONS[evasion](text)
    assert rule in hard(changed), f"{evasion} hid {text!r} from {rule}: {changed!r}"


@pytest.mark.parametrize(
    ("rule", "text"),
    [(rule, sample) for rule, samples in PASSING.items() for sample in samples],
)
def test_each_passing_sample_passes_its_rule(rule, text):
    assert rule not in hard(text)


# --- Every transcript line in spec Section 6.6 -------------------------------------------


@pytest.mark.parametrize(
    ("line", "rule"),
    [
        ("Scanning digital ZATCA tax receipts to spot price inflation", "G21"),
        ("Tracking multiple bank/e-wallet accounts", "G20"),
        ("Tracking Al Rajhi, SNB, Riyad Bank and STC Pay", "G20"),
        ("Why grocery shopping without an envelope budget costs you 30% more", "G2"),
        ("كيف توفر 30% من مقاضي البيت؟", "G2"),
        ("Demonstrates the app feature solving it in 3 clicks", "G22"),
        ("Payday cycle 27", "G5"),
        ("Payday 27th HUD", "G5"),
        ("27th-to-27th", "G5"),
        ("#راتب_27", "G5"),
        ("Messy notes and unorganized bank SMS", "G4"),
        ("Link in bio", "G11"),
        ("high app downloads", "G11"),
        ("Sleek iPhone/Android bezel", "G1"),
        ("indistinguishable from a real creator", "G17"),
        ("Saudi voices sound human", "G17"),
        ("Store Panda is cheaper", "G13"),
    ],
)
def test_each_rejected_transcript_line_fails(line, rule):
    assert rule in hard(line)


@pytest.mark.parametrize(
    "line",
    [
        "Zero-based liquidity ledger",
        "Smart envelope budgeting",
        "Transparent family maintenance (Nafaqah / household allowance)",
    ],
)
def test_each_transcript_line_the_spec_supports_passes(line):
    assert hard(line, claim_ids=frozenset({"C10", "C11"})) == set()


# --- G1 ----------------------------------------------------------------------------------


def _script(**changes) -> Script:
    values = {
        "topic_id": "g001",
        "tier": "global",
        "template": "DailyTip",
        "language": "ar",
        "hook_ar": "راتبك وين يروح كل شهر؟",
        "voice_script": "اكتب مصاريفك كل أسبوع وراجعها.",
        "on_screen_en": ["Where does your salary go?"],
        "subtitles_en": "Write your spending down every week and review it.",
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


def _check(script: Script, **kwargs):
    return check_script(script, config=load_config(), brand=LIVE_BRAND, **kwargs)


def _hard_rules(report) -> set[str]:
    return {finding.rule for finding in report.hard_failures}


def test_a_clean_education_script_passes_every_rule():
    report = _check(_script())
    assert report.hard_failures == []
    assert report.passed


def test_an_unknown_claim_id_fails_g1():
    assert "G1" in _hard_rules(_check(_script(claim_ids=["C99"])))


def test_a_claim_the_code_does_not_back_fails_g1():
    report = _check(_script(claim_ids=["C03"]))
    assert "G1" in _hard_rules(report)
    assert any("C03" in finding.message for finding in report.hard_failures)


@pytest.mark.parametrize("field", ["voice_script", "subtitles_en", "caption_ar", "caption_en"])
def test_a_product_statement_with_no_claim_id_fails_g1(field):
    text = {
        "voice_script": "{brand_ar} يساعدك.",
        "subtitles_en": "The app helps you.",
        "caption_ar": "التطبيق يساعدك.",
        "caption_en": "This app helps you.",
    }[field]
    assert "G1" in _hard_rules(_check(_script(**{field: text})))


def test_a_product_statement_with_a_claim_id_passes_g1():
    report = _check(_script(voice_script="{brand_ar} يساعدك.", claim_ids=["C10"]))
    assert "G1" not in _hard_rules(report)


def test_a_feature_named_without_its_claim_fails_g1():
    assert "G1" in hard("Smart Basket inside the app", claim_ids=frozenset({"C10"}))
    assert "G1" in hard("السلة الذكية داخل التطبيق", claim_ids=frozenset({"C10"}))
    assert "G1" not in hard("Smart Basket inside the app", claim_ids=frozenset({"C21"}))


def test_a_clip_from_another_feature_fails_g1():
    report = _check(_script(feature_clip_folder="price_tracker", claim_ids=["C10"]))
    assert "G1" in _hard_rules(report)
    report = _check(_script(feature_clip_folder="price_tracker", claim_ids=["C15"]))
    assert "G1" not in _hard_rules(report)


@pytest.mark.parametrize(
    "line",
    [
        "Open banking is here",
        "Price alerts on your phone",
        "Now on the Apple Watch",
        "It moves your money automatically",
        "تنبيهات الأسعار",
        "يحول فلوسك تلقائيا",
    ],
)
def test_roadmap_items_and_invented_features_fail_g1(line):
    assert "G1" in hard(line, claim_ids=frozenset({"C10"}))


def test_every_approved_claim_wording_passes_with_its_own_id():
    register = load_claims_register()
    for claim in register.claims.values():
        context = {
            "claim_ids": frozenset({claim.id}),
            "basket": claim.id == "C21",
            "family": claim.id == "C11",
        }
        for wording in (claim.wording_ar, claim.wording_en):
            report = check_text(wording, GuardrailContext(**context))
            held = {"G1"} if claim.code_check != "supported" else set()
            found = {finding.rule for finding in report.hard_failures}
            assert found <= held, f"{claim.id} wording fails {found}: {wording}"


def test_check_claim_ids_reports_each_unknown_and_held_id():
    hits = check_claim_ids(["C01", "C99", "C06"], load_claims_register())
    assert len(hits) == 2


# --- G2 ----------------------------------------------------------------------------------


def test_a_percentage_with_a_source_in_numbers_passes_g2():
    assert "G2" not in hard("Food prices rose 12% last year", numbers=("12%",))
    assert "G2" not in hard("الأسعار ارتفعت ١٢٪", numbers=("12%",))
    assert "G2" not in hard("Food prices rose 12%", numbers=("١٢٪",))


def test_a_different_figure_than_the_source_fails_g2():
    assert "G2" in hard("Food prices rose 15%", numbers=("12%",))


def test_a_figure_of_another_kind_than_the_source_fails_g2():
    assert "G2" in hard("A rise of 12 riyals", numbers=("12%",))


@pytest.mark.parametrize(
    "text",
    [
        "Save 30%",
        "Example: save 30%",
        "مثال: وفر 30%",
        "30% of your salary",
        "٣٠٪ من راتبك",
        "٪٣٠ من راتبك",
        "%30 من راتبك",
        "30 percent",
        "thirty percent",
        "ثلاثين بالمية",
        "30 في المئة",
        "Save 30",
        "#وفر30",
        "#save30",
    ],
)
def test_a_30_percent_figure_fails_even_with_a_source_or_an_example_label(text):
    assert "G2" in hard(text, numbers=("30%",))


def test_the_number_list_itself_refuses_a_30_percent_figure():
    report = _check(
        _script(
            numbers=[{"value": "30%", "source_url": "https://stats.example/report"}],
            sources=[{"publisher": "Stats Office", "url": "https://stats.example/report"}],
        )
    )
    assert "G2" in _hard_rules(report)


@pytest.mark.parametrize(
    "text",
    [
        "5,000 SAR",
        "SAR 5,000",
        "ر.س 5000",
        "5000 ر.س",
        "$20",
        "double your savings",
        "ضعفين راتبك",
        "3 times more",
        "ثلاث أضعاف",
        "ألف ريال",
    ],
)
def test_money_amounts_and_multipliers_need_a_source_or_a_label(text):
    assert "G2" in hard(text)


# --- G3 ----------------------------------------------------------------------------------


SOURCE_URL = "https://stats.example/report"
EXCERPT = (
    "household food prices rose sharply across the region during the second half of the "
    "year according to the national statistics office"
)


def _fact(url: str = SOURCE_URL) -> ResearchFact:
    return ResearchFact(
        claim="Food prices rose.",
        source_url=url,
        publisher="Stats Office",
        accessed="2026-11-03",
        paraphrase_ar="ارتفعت أسعار الغذاء.",
        paraphrase_en="Food prices went up.",
    )


def _g3(script: Script, *, facts=(), excerpts=(), max_copied_words: int = 12):
    return check_research_use(
        script, facts=facts, excerpts=excerpts, max_copied_words=max_copied_words
    )


def test_a_source_the_research_never_found_fails_g3():
    script = _script(sources=[{"publisher": "Elsewhere", "url": "https://other.example/x"}])
    assert _g3(script, facts=[_fact()])


def test_a_number_the_research_never_found_fails_g3():
    script = _script(numbers=[{"value": "12%", "source_url": "https://other.example/x"}])
    assert _g3(script, facts=[_fact()])


def test_a_cited_source_passes_g3():
    script = _script(sources=[{"publisher": "Stats Office", "url": SOURCE_URL}])
    assert _g3(script, facts=[_fact()]) == []


@pytest.mark.parametrize("field", ["subtitles_en", "caption_en", "voice_script"])
def test_twelve_copied_words_fail_g3(field):
    words = EXCERPT.split()
    assert _g3(_script(**{field: " ".join(words[:12])}), excerpts=[EXCERPT])


def test_eleven_copied_words_pass_g3():
    words = EXCERPT.split()
    assert _g3(_script(subtitles_en=" ".join(words[:11])), excerpts=[EXCERPT]) == []


def test_the_limit_comes_from_the_argument():
    words = EXCERPT.split()
    script = _script(subtitles_en=" ".join(words[:6]))
    assert _g3(script, excerpts=[EXCERPT], max_copied_words=6)
    assert _g3(script, excerpts=[EXCERPT], max_copied_words=7) == []


def test_copying_cannot_hide_behind_case_punctuation_or_arabic_marks():
    words = EXCERPT.split()
    changed = ", ".join(word.upper() for word in words[:12])
    assert _g3(_script(subtitles_en=changed), excerpts=[EXCERPT])

    arabic_excerpt = " ".join(f"كلمة{index}" for index in "ابتثجحخدذرزس")
    copied = with_kashida(with_fatha(arabic_excerpt))
    assert _g3(_script(voice_script=copied), excerpts=[arabic_excerpt])


def test_a_copied_paraphrase_fails_g3():
    words = EXCERPT.split()
    fact = ResearchFact(
        claim="Food prices rose.",
        source_url=SOURCE_URL,
        publisher="Stats Office",
        accessed="2026-11-03",
        paraphrase_ar="ارتفعت أسعار الغذاء.",
        paraphrase_en=" ".join(words[:12]),
    )
    assert _g3(_script(), facts=[fact], excerpts=[EXCERPT])


def test_check_script_runs_g3_with_the_configured_limit():
    words = EXCERPT.split()
    report = _check(_script(subtitles_en=" ".join(words[:12])), excerpts=[EXCERPT])
    assert "G3" in _hard_rules(report)


# --- G4 ----------------------------------------------------------------------------------


def test_the_approved_no_sms_claim_is_the_one_allowed_mention():
    english = "The app does not read your SMS."
    arabic = "التطبيق لا يقرأ رسائلك النصية."
    assert "G4" not in hard(english, claim_ids=frozenset({"C18"}))
    assert "G4" not in hard(arabic, claim_ids=frozenset({"C18"}))


def test_the_no_sms_claim_without_its_id_still_fails():
    assert "G4" in hard("The app does not read your SMS.")


def test_the_no_sms_claim_cannot_carry_another_mention_with_it():
    text = "The app does not read your SMS. Unlike bank SMS it is tidy."
    assert "G4" in hard(text, claim_ids=frozenset({"C18"}))


@pytest.mark.parametrize("text", ["It never reads your SMS", "ما يقرأ رسائلك"])
def test_a_paraphrase_of_the_no_sms_claim_fails(text):
    assert "G4" in hard(text, claim_ids=frozenset({"C18"}))


# --- G5 ----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "The default is the 27th",
        "You can change your plan on the 27th",
        "The default is the 27th and you cannot change it",
    ],
)
def test_the_27th_needs_both_default_and_change_wording(text):
    assert "G5" in hard(text)


# --- G6 ----------------------------------------------------------------------------------


def test_split_wording_anywhere_in_a_family_script_fails():
    assert "G6" in hard("A fair 50/50 for everyone", family=True)
    assert "G6" not in hard("A fair 50/50 for everyone", family=False)


# --- G8 ----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "Avoid high-interest loans",
        "Credit cards can trap you",
        "احذر من القروض",
        "الفوائد تأكل راتبك",
    ],
)
def test_a_neutral_warning_gets_a_soft_flag_only(text):
    assert "G8" not in hard(text)
    assert "G8" in soft(text)


def test_tracking_a_plan_is_not_promoting_one():
    assert "G8" not in hard("Track your BNPL plan")


# --- Normalisation -----------------------------------------------------------------------


def test_lexicon_form_folds_what_a_reader_would_not_notice():
    assert lexicon_form("بَنْكـــك") == lexicon_form("بنكك")
    assert lexicon_form("أرخص") == lexicon_form("ارخص")
    assert lexicon_form("مناصفة") == lexicon_form("مناصفه")
    assert lexicon_form("ﻗﻮﺍﻡ") == lexicon_form("قوام")
    assert lexicon_form("٣٠٪") == "30%"
    assert lexicon_form("۳۰٪") == "30%"
    assert lexicon_form("S\u200bM\u200dS") == "sms"
    assert lexicon_form("s m s") == "sms"
    assert lexicon_form("s-m-s") == "sms"


def test_look_alike_capitals_do_not_hide_a_word():
    assert "G4" in hard("\u0405\u041c\u0405")


def test_a_word_that_merely_contains_a_banned_word_is_not_flagged():
    assert "G4" not in hard("Teams message their friends")
    assert "G11" not in hard("Your installment plan")
    assert "G20" not in hard("Banker's hours aside, keep records")


def test_a_common_salary_phrase_is_not_download_wording():
    assert "G11" not in hard("الراتب نزل أمس")
    assert "G11" not in hard("نزل الراتب")


def test_no_lexicon_holds_a_term_that_folds_to_nothing():
    # A term that normalises to nothing would silently match nothing.
    for name in dir(denylists):
        value = getattr(denylists, name)
        if name.isupper() and isinstance(value, tuple):
            for term in value:
                assert lexicon_form(term), f"{name} holds an empty term: {term!r}"
