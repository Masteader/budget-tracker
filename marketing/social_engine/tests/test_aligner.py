"""Timed words map back onto script tokens (spec Section 7.4), and the brand is one caption
token (spec Section 8.4 rule 12, G18), so قوام is never on screen alone."""

import pytest

from content_engine.aligner import (
    AlignmentError,
    TimedWord,
    align_words,
    match_tokens,
    whole_word_pattern,
)
from core.render_props import CaptionWord


def timed(*words: str, step: int = 100) -> list[TimedWord]:
    return [TimedWord(w, i * step, i * step + step - 10) for i, w in enumerate(words)]


def texts(result: list[TimedWord]) -> list[str]:
    return [word.text for word in result]


# --- Punctuation ------------------------------------------------------------------------


def test_arabic_punctuation_stays_on_its_word():
    result = align_words("راتبك وين يروح؟", timed("راتبك", "وين", "يروح"))
    assert texts(result) == ["راتبك", "وين", "يروح؟"]
    assert (result[2].start_ms, result[2].end_ms) == (200, 290)


def test_english_punctuation_stays_on_its_word():
    assert texts(align_words("Stop, now!", timed("Stop", "now"))) == ["Stop,", "now!"]


def test_a_standalone_mark_joins_the_word_before_it():
    assert texts(align_words("راتبك — وين", timed("راتبك", "وين"))) == ["راتبك —", "وين"]


def test_a_leading_mark_joins_the_word_after_it():
    assert texts(align_words("« راتبك", timed("راتبك"))) == ["« راتبك"]


def test_a_word_event_holding_only_punctuation_is_ignored():
    result = align_words("راتبك وين", timed("راتبك", "،", "وين"))
    assert texts(result) == ["راتبك", "وين"]


def test_text_with_no_words_cannot_align():
    with pytest.raises(AlignmentError):
        align_words("— ؟ !", timed("x"))


# --- Arabic and mixed English -----------------------------------------------------------


def test_mixed_arabic_and_english_map_back_to_script_tokens():
    script = "فاتورة ZATCA جاهزة الحين"
    assert texts(align_words(script, timed("فاتورة", "ZATCA", "جاهزة", "الحين"))) == script.split()


def test_events_that_split_one_token_take_the_whole_span():
    result = align_words("دفعت 1,250 ريال", timed("دفعت", "1", "250", "ريال"))
    assert texts(result) == ["دفعت", "1,250", "ريال"]
    assert (result[1].start_ms, result[1].end_ms) == (100, 290)


def test_one_event_over_two_tokens_times_both():
    result = align_words("real estate deal", timed("real estate", "deal"))
    assert texts(result) == ["real", "estate", "deal"]
    assert result[0].start_ms == result[1].start_ms == 0


@pytest.mark.parametrize(
    ("script", "event"),
    [
        ("راتب ٢٧", "27"),
        ("راتب 27", "٢٧"),
        ("قَوام", "قوام"),
        ("قوام", "قَوام"),
        ("فـــاتورة", "فاتورة"),
        ("ZATCA", "zatca"),
    ],
)
def test_digit_forms_diacritics_kashida_and_case_do_not_break_the_match(script, event):
    words = script.split()
    assert texts(align_words(script, timed(*words[:-1], event))) == words


def test_times_stay_whole_numbers_in_order():
    result = align_words("قوام المال يساعدك تخطط", timed("قوام", "المال", "يساعدك", "تخطط"))
    starts = [word.start_ms for word in result]
    assert starts == sorted(starts)
    assert all(isinstance(word.start_ms, int) and isinstance(word.end_ms, int) for word in result)


# --- The brand --------------------------------------------------------------------------


def test_the_arabic_name_is_one_token():
    result = align_words("قوام المال يساعدك", timed("قوام", "المال", "يساعدك"))
    assert texts(result) == ["قوام المال", "يساعدك"]
    assert (result[0].start_ms, result[0].end_ms) == (0, 190)
    assert "قوام" not in texts(result)


def test_the_english_name_is_one_token():
    result = align_words("Qawam Money helps", timed("Qawam", "Money", "helps"))
    assert texts(result) == ["Qawam Money", "helps"]


@pytest.mark.parametrize(
    ("script", "events", "expected"),
    [
        ("مع قوام المال،", ("مع", "قوام", "المال"), ["مع", "قوام المال،"]),
        ("بقوام المال تخطط", ("بقوام", "المال", "تخطط"), ["بقوام المال", "تخطط"]),
        ("لقوام المال", ("لقوام", "المال"), ["لقوام المال"]),
        ("وبقوام المال", ("وبقوام", "المال"), ["وبقوام المال"]),
        ("قوام\nالمال", ("قوام", "المال"), ["قوام المال"]),
        ("قَوام المَال", ("قوام", "المال"), ["قَوام المَال"]),
        ("قوام المال", ("قوام المال",), ["قوام المال"]),
        ("qawam money", ("qawam", "money"), ["qawam money"]),
        ("Qawam Money's plan", ("Qawam", "Money's", "plan"), ["Qawam Money's", "plan"]),
        ("(Qawam Money)", ("Qawam", "Money"), ["(Qawam Money)"]),
        (
            "قوام المال Qawam Money قريبًا",
            ("قوام", "المال", "Qawam", "Money", "قريبًا"),
            ["قوام المال", "Qawam Money", "قريبًا"],
        ),
        (
            "قوام المال ثم قوام المال",
            ("قوام", "المال", "ثم", "قوام", "المال"),
            ["قوام المال", "ثم", "قوام المال"],
        ),
        ("#قوام_المال اليوم", ("قوام", "المال", "اليوم"), ["#قوام_المال", "اليوم"]),
    ],
)
def test_the_name_merges_in_every_form_it_is_written(script, events, expected):
    assert texts(align_words(script, timed(*events))) == expected


@pytest.mark.parametrize(
    ("script", "events"),
    [
        ("قوام الجسم", ("قوام", "الجسم")),
        ("قوام المالية", ("قوام", "المالية")),
        ("Qawam Moneybags", ("Qawam", "Moneybags")),
        ("نقوام المال", ("نقوام", "المال")),
        ("المال قوام", ("المال", "قوام")),
    ],
)
def test_other_words_do_not_merge(script, events):
    assert texts(align_words(script, timed(*events))) == script.split()


def test_extra_phrases_such_as_the_test_brand_merge_too():
    result = align_words(
        "علامة تجريبية قريبًا",
        timed("علامة", "تجريبية", "قريبًا"),
        phrases=("قوام المال", "علامة تجريبية"),
    )
    assert texts(result) == ["علامة تجريبية", "قريبًا"]


def test_aligned_words_fit_the_render_props_contract():
    script = "مع قوام المال، Qawam Money تخطط 1,250؟"
    events = timed("مع", "قوام", "المال", "Qawam", "Money", "تخطط", "1,250")
    words = [
        CaptionWord(text=word.text, start_ms=word.start_ms, end_ms=word.end_ms)
        for word in align_words(script, events)
    ]
    assert [word.text for word in words][1:3] == ["قوام المال،", "Qawam Money"]


# --- A script with missing or wrong events fails ----------------------------------------


@pytest.mark.parametrize(
    ("script", "events", "named"),
    [
        ("راتبك وين يروح", ("راتبك", "يروح"), "يروح"),
        ("راتبك وين يروح", ("راتبك", "وين"), "يروح"),
        ("راتبك وين يروح", (), "راتبك"),
        ("راتبك وين", ("راتبك", "وين", "زيادة"), "زيادة"),
        ("راتبك وين", ("وين", "راتبك"), "وين"),
        ("راتبك وين", ("راتبك", "راتبك", "وين"), "راتبك"),
        ("Qawam Money", ("Qawam",), "Qawam Money"),
        ("قوام المال", ("قوام",), "قوام المال"),
        ("فاتورة", ("فات",), "فاتورة"),
    ],
)
def test_missing_extra_or_out_of_order_events_fail(script, events, named):
    with pytest.raises(AlignmentError) as caught:
        align_words(script, timed(*events))
    assert named in str(caught.value)


# --- Spoken forms from `<sub>` ----------------------------------------------------------


def test_events_that_report_the_sub_alias_still_map_to_the_written_word():
    result = align_words("قال حسبتك صح", timed("قال", "حسبتك2", "صح"), aliases={"حسبتك": "حسبتك2"})
    assert texts(result) == ["قال", "حسبتك", "صح"]


def test_events_that_report_the_written_word_still_match_with_an_alias_set():
    result = align_words("قال حسبتك", timed("قال", "حسبتك"), aliases={"حسبتك": "حسبتك2"})
    assert texts(result) == ["قال", "حسبتك"]


def test_an_alias_over_two_tokens_keeps_them_together():
    result = align_words(
        "مع قوام المال،",
        timed("مع", "كوام", "المال"),
        aliases={"قوام المال": "كوام المال"},
    )
    assert texts(result) == ["مع", "قوام المال،"]


def test_an_alias_over_two_ordinary_tokens_merges_them_too():
    result = align_words(
        "دفعت عشرة ريال", timed("دفعت", "عشره", "ريال"), aliases={"عشرة ريال": "عشره ريال"}
    )
    assert texts(result) == ["دفعت", "عشرة ريال"]


def test_an_alias_does_not_excuse_a_missing_word():
    with pytest.raises(AlignmentError):
        align_words("قال حسبتك صح", timed("قال", "حسبتك2"), aliases={"حسبتك": "حسبتك2"})


# --- What the timing report reads -------------------------------------------------------


def test_match_tokens_lists_the_events_behind_each_token():
    matches = match_tokens("قوام المال يساعدك", timed("قوام", "المال", "يساعدك"))
    assert [match.text for match in matches] == ["قوام المال", "يساعدك"]
    assert [[event.text for event in match.events] for match in matches] == [
        ["قوام", "المال"],
        ["يساعدك"],
    ]
    assert [match.word_count for match in matches] == [2, 1]


# --- Whole-word matching, shared with the SSML builder ----------------------------------


@pytest.mark.parametrize(
    ("text", "hit"),
    [
        ("راتب الشهر", True),
        ("الراتب", False),
        ("راتبك", False),
        ("راتبٌ", False),
        ("#راتب_27", False),
    ],
)
def test_keys_match_whole_words_only(text, hit):
    assert bool(whole_word_pattern(["راتب"]).search(text)) is hit


def test_the_longest_key_wins():
    found = whole_word_pattern(["قوام", "قوام المال"]).search("مع قوام المال")
    assert found.group() == "قوام المال"


def test_a_key_may_cross_any_whitespace():
    assert whole_word_pattern(["قوام المال"]).search("قوام\n المال")


def test_a_key_with_regex_characters_is_literal():
    assert not whole_word_pattern(["a.c"]).search("abc")
    assert whole_word_pattern(["a.c"]).search("a.c")


def test_no_keys_means_no_pattern():
    assert whole_word_pattern([]) is None
