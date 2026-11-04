"""Round 2's attacks on the voice step, and what they led to (spec Sections 7.4 and 7.5). Word times
must fit the audio, spike S2 must not pass on bad timing, cut-off audio and wordless scripts are
refused, and the brand stays one token and one pronunciation however it is written."""

import random
import xml.etree.ElementTree as ET
from dataclasses import replace
from datetime import UTC, datetime, timedelta, timezone

import pytest
from voice_fakes import (
    Clock,
    FakeSpeechClient,
    make_engine,
    spoken_text,
    wav_bytes,
    word,
    words_for,
)

from content_engine import bakeoff
from content_engine import voiceover_engine as ve
from content_engine.aligner import TimedWord, align_words, caption_tokens
from content_engine.bakeoff import BakeoffError, BakeoffScript, plan_samples
from content_engine.guardrails import check_caption_words
from content_engine.voice_providers.azure_speech import SpeechOutcome, build_ssml
from content_engine.voiceover_engine import (
    CharLedger,
    VoiceAudioCutOff,
    VoiceError,
    VoiceInputError,
    VoiceLengthError,
    VoiceServiceError,
    VoiceTimingError,
    check_script_length,
)
from core.brand_gate import letters_only

TEXT = "هذا نص قصير للاختبار فقط"
LONG_TEXT = " ".join([TEXT] * 12)
HAMED = "ar-SA-HamedNeural"
MSTTS = "{https://www.w3.org/2001/mstts}"
BAD_HEADER = bytes.fromhex(
    "52494646a425000057415645666d7420100044000100010080bb00000077010002001017646174618025000000000000"
)
BARE_FORMS = ("قوام", "بقوام", "لقوام", "وقوام", "qawam")


def ev(text):
    return [TimedWord(t, i * 300, i * 300 + 100) for i, t in enumerate(text.split())]


def script(text=TEXT, name="a") -> BakeoffScript:
    return BakeoffScript(id=name, language="ar", text=text)


def report_for(engine, text=TEXT):
    return bakeoff.timing_report(engine, [script(text)], [HAMED], max_chars=10_000)


# --- 7. A bad answer from Azure does not block a text for good ------------------------------


def test_transient_bad_events_do_not_poison_cache_forever(tmp_path):
    client = FakeSpeechClient(
        outcomes=[SpeechOutcome(wav_bytes(), [word("فقط", 900), word("هذا", 0)])]
    )
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceTimingError):
        engine.voice(TEXT, "ar", check_length=False)
    assert len(engine.voice(TEXT, "ar", check_length=False).words) == 5


def test_missing_events_do_not_poison_cache_forever(tmp_path):
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(), [word("هذا", 0)])])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceTimingError):
        engine.voice(TEXT, "ar", check_length=False)
    assert len(engine.voice(TEXT, "ar", check_length=False).words) == 5


def test_an_entry_already_cached_with_bad_timing_is_not_believed(tmp_path):
    """One written before this check, which would otherwise block the text with no Azure call."""
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    first = engine.voice(TEXT, "ar", check_length=False)
    entry = first.audio_path.with_suffix(".json")
    data = ve._CacheEntry.model_validate_json(entry.read_bytes())
    entry.write_text(
        data.model_copy(update={"raw_words": data.raw_words[:1]}).model_dump_json(),
        encoding="utf-8",
    )
    assert engine.pending_characters(TEXT, "ar", voice_name=HAMED) > 0
    assert len(engine.voice(TEXT, "ar", check_length=False).words) == 5
    assert len(client.calls) == 2


def test_cached_audio_that_is_not_a_usable_wav_is_not_believed(tmp_path):
    """Mutation V08. The word ends within the rounding of an empty file, so only this check can
    catch it."""
    client = FakeSpeechClient(
        [
            SpeechOutcome(wav_bytes(1.0), [word("هذا", 0, 40)]),
            SpeechOutcome(wav_bytes(1.0), words_for("هذا")),
        ]
    )
    engine = make_engine(tmp_path, client)
    first = engine.voice("هذا", "ar", check_length=False)
    first.audio_path.write_bytes(b"not a wav")
    entry = first.audio_path.with_suffix(".json")
    data = ve._CacheEntry.model_validate_json(entry.read_bytes())
    entry.write_text(
        data.model_copy(update={"audio_sha256": ve._sha256_of(first.audio_path)}).model_dump_json(),
        encoding="utf-8",
    )
    assert engine.voice("هذا", "ar", check_length=False).cached is False
    assert len(client.calls) == 2


# --- 2. Spike S2 reports what really happened -----------------------------------------------


def test_s2_report_keeps_raw_events_when_they_are_out_of_order(tmp_path):
    client = FakeSpeechClient(
        outcomes=[SpeechOutcome(wav_bytes(), [word("فقط", 900), word("هذا", 0)])]
    )
    report = report_for(make_engine(tmp_path, client))
    assert report.passed is False
    assert "فقط\t900-1000" in report.text
    assert "هذا\t0-100" in report.text


def test_one_event_over_two_words_is_flagged_and_does_not_pass_s2(tmp_path):
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(1.0), [word("راتبك وين", 0, 400)])])
    report = report_for(make_engine(tmp_path, client), "راتبك وين")
    assert report.passed is False
    assert "PASS" not in report.text
    assert "CHECK" in report.text
    assert "راتبك\t1/1*\t0-400" in report.text
    assert "وين\t1/1*\t0-400" in report.text


def test_an_event_over_part_of_two_words_is_flagged_too(tmp_path):
    events = [word("راتبك و", 0), word("ين", 300)]
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(1.0), events)])
    report = report_for(make_engine(tmp_path, client), "راتبك وين")
    assert report.passed is False
    assert "راتبك\t1/1*" in report.text
    assert "وين\t2/1*" in report.text


def test_one_event_for_each_word_still_passes_s2(tmp_path):
    report = report_for(make_engine(tmp_path, FakeSpeechClient(seconds=2.0)))
    assert report.passed is True
    assert "*" not in report.text


def test_s2_report_does_not_pass_all_zero_times(tmp_path):
    client = FakeSpeechClient(
        outcomes=[SpeechOutcome(wav_bytes(), [word(t, 0, 0) for t in TEXT.split()])]
    )
    report = report_for(make_engine(tmp_path, client))
    assert report.passed is False
    assert "FAIL" in report.text


def test_s2_report_does_not_pass_times_past_the_end_of_the_audio(tmp_path):
    client = FakeSpeechClient(
        outcomes=[SpeechOutcome(wav_bytes(1.0), words_for(TEXT, step_ms=60_000))]
    )
    assert report_for(make_engine(tmp_path, client)).passed is False


# --- 1. Word times have to fit the audio ----------------------------------------------------


def test_word_times_past_the_end_of_the_audio_fail(tmp_path):
    client = FakeSpeechClient(
        outcomes=[SpeechOutcome(wav_bytes(30.0), words_for(LONG_TEXT, step_ms=60_000))]
    )
    with pytest.raises(VoiceTimingError, match="audio ends"):
        make_engine(tmp_path, client).voice(LONG_TEXT, "ar")


def test_every_word_at_time_zero_fails(tmp_path):
    client = FakeSpeechClient(
        outcomes=[SpeechOutcome(wav_bytes(30.0), [word(t, 0, 0) for t in LONG_TEXT.split()])]
    )
    with pytest.raises(VoiceTimingError) as caught:
        make_engine(tmp_path, client).voice(LONG_TEXT, "ar")
    assert caught.value.result.audio_path.is_file()


@pytest.mark.parametrize(
    ("events", "message"),
    [
        ([word("هذا", 0), word("نص", 0), word("قصير", 600)], "not after"),
        ([word("هذا", 500), word("نص", 100), word("قصير", 600)], "back in time|not after"),
        ([word("هذا", 0), word("نص", 300, 0), word("قصير", 600)], "no time"),
        ([word("هذا", 0), word("نص", 300), word("قصير", 2000)], "audio ends"),
    ],
)
def test_impossible_word_times_fail(tmp_path, events, message):
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(1.0), events)])
    with pytest.raises(VoiceTimingError, match=message):
        make_engine(tmp_path, client).voice("هذا نص قصير", "ar", check_length=False)


def test_the_last_word_may_end_within_the_rounding_of_the_audio_end(tmp_path):
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(1.0), [word("هذا", 900, 140)])])
    engine = make_engine(tmp_path, client)
    assert [w.end_ms for w in engine.voice("هذا", "ar", check_length=False).words] == [1040]


def test_a_word_event_with_no_letters_needs_no_time(tmp_path):
    events = [word("هذا", 0), word("،", 100, 0), word("نص", 300)]
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(1.0), events)])
    result = make_engine(tmp_path, client).voice("هذا، نص", "ar", check_length=False)
    assert [w.text for w in result.words] == ["هذا،", "نص"]


# --- 3. Cut-off and corrupt audio -----------------------------------------------------------


def test_truncated_wav_is_refused_and_not_kept(tmp_path):
    wav = wav_bytes(30.0)
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav[: len(wav) // 3], words_for(TEXT))])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceAudioCutOff):
        engine.voice(TEXT, "ar", check_length=False)
    assert list((tmp_path / "voiceovers").iterdir()) == []


def test_truncated_wav_cannot_pass_the_length_check(tmp_path):
    wav = wav_bytes(30.0)  # a 30 s header over 3 s of data, under the 15 s minimum
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav[: len(wav) // 10], words_for(LONG_TEXT))])
    with pytest.raises(VoiceLengthError):
        make_engine(tmp_path, client).voice(LONG_TEXT, "ar", check_length=True)


def test_a_truncated_wav_on_disk_reports_the_sound_it_holds(tmp_path):
    wav = wav_bytes(30.0)
    path = tmp_path / "cut.wav"
    path.write_bytes(wav[: len(wav) // 10])
    assert ve._audio_length_ms(path) == pytest.approx(3000, abs=5)
    assert ve._is_cut_off(path)


def test_a_new_call_after_truncated_audio_can_succeed(tmp_path):
    wav = wav_bytes(30.0)
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav[:1000], words_for(TEXT))])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceError):
        engine.voice(TEXT, "ar", check_length=False)
    assert len(engine.voice(TEXT, "ar", check_length=False).words) == 5


@pytest.mark.parametrize(
    "shape", [{"channels": 2}, {"sample_bytes": 1}], ids=["stereo", "8_bit"]
)
def test_a_wav_of_another_shape_is_not_what_was_asked_for(tmp_path, shape):
    import io
    import wave

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(shape.get("channels", 1))
        output.setsampwidth(shape.get("sample_bytes", 2))
        output.setframerate(48_000)
        output.writeframes(b"\x00\x00\x00\x00" * 4800)
    client = FakeSpeechClient(outcomes=[SpeechOutcome(buffer.getvalue(), words_for("هذا"))])
    with pytest.raises(VoiceServiceError):
        make_engine(tmp_path, client).voice("هذا", "ar", check_length=False)


def test_wav_fuzz_only_raises_handled_errors(tmp_path):
    rng = random.Random(7)
    base = bytearray(wav_bytes(0.1))
    path = tmp_path / "f.wav"
    bad = {}
    for number in range(6000):
        changed = bytearray(base)
        for _ in range(rng.randint(1, 4)):
            changed[rng.randint(0, 47)] = rng.randint(0, 255)
        path.write_bytes(bytes(changed))
        try:
            ve._audio_length_ms(path)
        except Exception as error:
            bad[type(error).__name__] = (number, str(error)[:80])
    assert not bad, bad


def test_a_corrupt_wav_header_is_a_voice_error_and_leaves_no_file(tmp_path):
    client = FakeSpeechClient(outcomes=[SpeechOutcome(BAD_HEADER, words_for(TEXT))])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceError):
        engine.voice(TEXT, "ar", check_length=False)
    assert not list((tmp_path / "voiceovers").glob(".incoming-*"))


# --- 4. Nothing to say, nothing billed ------------------------------------------------------


@pytest.mark.parametrize(
    "text", ["... ؟؟ !!! ،،،", "\u200b\u200b\u200b", "\u200f", "ـــ", "😀😀"]
)
def test_script_with_no_words_is_refused_before_billing(tmp_path, text):
    client = FakeSpeechClient(outcomes=[SpeechOutcome(wav_bytes(), [])])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceInputError, match="no words"):
        engine.voice(text, "ar", check_length=False)
    with pytest.raises(VoiceInputError, match="no words"):
        engine.pending_characters(text, "ar", voice_name=HAMED)
    assert client.calls == []
    assert engine.ledger.used() == 0


def test_diacritics_do_not_change_the_length_estimate():
    plain = "بسم " * 60
    marked = "بِسْمِ " * 60
    assert check_script_length(plain, 15.0) == pytest.approx(check_script_length(marked, 15.0))


# --- 6. The brand is one token, however it is glued -----------------------------------------


GLUED_FORMS = [
    ("تطبيق:قوام المال", ["تطبيق:", "قوام المال"]),
    ("جرب قوام المال،وفر فلوسك", ["جرب", "قوام المال،", "وفر", "فلوسك"]),
    ("جرب قوام المال.وفر فلوسك", ["جرب", "قوام المال.", "وفر", "فلوسك"]),
    ("Try Qawam Money-powered budgets", ["Try", "Qawam Money-", "powered", "budgets"]),
    ("Qawam Money/قوام المال today", ["Qawam Money/", "قوام المال", "today"]),
    ("Qawam Money,the app", ["Qawam Money,", "the", "app"]),
    ("قوام المال/Qawam Money", ["قوام المال/", "Qawam Money"]),
    ("جرب قوام\nالمال الآن", ["جرب", "قوام المال", "الآن"]),
    ("جرب بقوام المال الآن", ["جرب", "بقوام المال", "الآن"]),
    ("جرب وبقوام المال، الآن", ["جرب", "وبقوام المال،", "الآن"]),
    ("جرب قَوَّام الْمَال الآن", ["جرب", "قَوَّام الْمَال", "الآن"]),
    ("جرب قوامِ المالِ الآن", ["جرب", "قوامِ المالِ", "الآن"]),
    ("«قوام المال» الآن", ["«قوام المال»", "الآن"]),
    ("Qawam Money's budget", ["Qawam Money's", "budget"]),
    ("QAWAM MONEY budget", ["QAWAM MONEY", "budget"]),
    ("Qawam\u00a0Money budget", ["Qawam Money", "budget"]),
]


@pytest.mark.parametrize(("text", "tokens"), GLUED_FORMS)
def test_the_brand_stays_one_token_and_the_glued_word_gets_its_own(text, tokens):
    assert caption_tokens(text) == tokens
    assert [w.text for w in align_words(text, ev(text))] == tokens


@pytest.mark.parametrize(("text", "_tokens"), GLUED_FORMS)
def test_no_token_is_the_bare_name(text, _tokens):
    for token in caption_tokens(text):
        assert letters_only(token) not in BARE_FORMS, token


@pytest.mark.parametrize(("text", "_tokens"), GLUED_FORMS)
def test_the_caption_check_passes_a_brand_kept_whole(text, _tokens):
    report = check_caption_words(caption_tokens(text))
    assert not [f for f in report.hard_failures if f.rule == "G18"], report


def test_a_dash_between_the_words_is_kept_together_and_still_fails_g18():
    """Not the full name to a reader, so G18 stops it, and قوام is never left alone either way."""
    tokens = caption_tokens("قوام — المال الآن")
    assert tokens == ["قوام — المال", "الآن"]
    assert [f for f in check_caption_words(tokens).hard_failures if f.rule == "G18"]


def test_the_caption_check_still_catches_a_split_it_is_handed():
    report = check_caption_words(["جرب", "قوام", "المال،وفر"])
    assert [f for f in report.hard_failures if f.rule == "G18"]


@pytest.mark.parametrize(
    "text",
    [
        "قوام الجسم",
        "قوام المالية",
        "Qawam Moneybags",
        "نقوام المال",
        "المال قوام",
        "قواما لمال",
    ],
)
def test_other_words_stay_apart(text):
    assert caption_tokens(text) == text.split()


def test_an_event_that_crosses_a_glued_word_times_both_tokens():
    text = "قوام المال،وفر"
    result = align_words(text, [TimedWord("قوام", 0, 90), TimedWord("المال،وفر", 100, 400)])
    assert [(w.text, w.start_ms, w.end_ms) for w in result] == [
        ("قوام المال،", 0, 400),
        ("وفر", 100, 400),
    ]


@pytest.mark.parametrize("text", ["جرب قوام الآن كثير كثير", "خذ Qawam الآن كثير كثير"])
def test_voice_refuses_a_bare_name_before_any_call(tmp_path, text):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceInputError, match="G18"):
        engine.voice(text, "ar", check_length=False)
    with pytest.raises(VoiceInputError, match="G18"):
        engine.pending_characters(text, "ar", voice_name=HAMED)
    assert client.calls == []
    assert engine.ledger.used() == 0


def test_the_caption_gate_reads_g18_only_because_the_rest_needs_the_reels_context(tmp_path):
    """A figure with no source fails G-rules that only the caller can judge, so voice lets it by."""
    engine = make_engine(tmp_path, FakeSpeechClient(seconds=2.0))
    assert engine.voice("وفرت 1,250 ريال", "ar", check_length=False).words


# --- 5. The brand's pronunciation fix reaches every form G18 allows -------------------------


PHONEME = {"قوام المال": "ipa:qa.waːm"}
ALIAS = {"قوام المال": "كوام المال"}


@pytest.mark.parametrize(
    ("text", "ph"),
    [
        ("جرب قوام المال", "qa.waːm"),
        ("جرب بقوام المال", "bi.qa.waːm"),
        ("جرب وقوام المال", "wa.qa.waːm"),
        ("جرب وبقوام المال", "wa.bi.qa.waːm"),
        ("جرب قَوام المال", "qa.waːm"),
        ("جرب قوام\nالمال", "qa.waːm"),
    ],
)
def test_a_phoneme_fix_reaches_prefixed_or_diacritic_forms(text, ph):
    document = build_ssml(text, HAMED, "ar", "0%", "0%", PHONEME).document
    prosody = ET.fromstring(document)[0][0]
    assert [child.attrib["ph"] for child in prosody] == [ph]
    assert spoken_text(document) == text


def test_a_sub_fix_says_the_attached_letter_too():
    document = build_ssml("جرب بقوام المال،وفر", HAMED, "ar", "0%", "0%", ALIAS).document
    prosody = ET.fromstring(document)[0][0]
    assert [child.attrib["alias"] for child in prosody] == ["بكوام المال"]
    assert [child.text for child in prosody] == ["بقوام المال"]


def test_the_english_name_is_fixed_in_any_case():
    document = build_ssml("Try QAWAM MONEY", "en-US-AvaNeural", "en", "0%", "0%", {
        "Qawam Money": "Kawam Money"
    }).document
    assert 'alias="Kawam Money"' in document


@pytest.mark.parametrize("text", ["راتبك", "لراتب", "رَاتب"])
def test_an_ordinary_fix_stays_on_the_exact_whole_word(text):
    assert "<sub" not in build_ssml(text, HAMED, "ar", "0%", "0%", {"راتب": "رااتب"}).document


def test_events_that_report_a_prefixed_alias_still_map_to_the_written_form():
    text = "جرب بقوام المال"
    events = [TimedWord("جرب", 0, 90), TimedWord("بكوام", 100, 190), TimedWord("المال", 200, 290)]
    result = align_words(text, events, aliases=ALIAS)
    assert [w.text for w in result] == ["جرب", "بقوام المال"]


# --- SSML stays tight -----------------------------------------------------------------------


PAYLOADS = [
    '</prosody></voice><voice name="x">',
    "]]>",
    '<!ENTITY x "y">',
    "&amp;",
    "<?xml?>",
    "\"'",
    '<break time="9s"/>',
    '<audio src="http://x/"/>',
    "&#x41;",
    "<!--",
    "--&gt;",
    "\u202e",
    '<mstts:express-as style="x">',
]


@pytest.mark.parametrize("payload", PAYLOADS)
def test_ssml_injection_holds(payload):
    for text, pronunciation in (
        (f"كلمة {payload} كلمة", {}),
        (f"كلمة {payload} كلمة", {payload: "ipa:x"}),
        ("كلمة ZATCA كلمة", {"ZATCA": payload}),
        ("كلمة ZATCA كلمة", {"ZATCA": "ipa:" + payload}),
    ):
        document = build_ssml(text, HAMED, "ar", "0%", "0%", pronunciation).document
        root = ET.fromstring(document)
        tags = {element.tag.split("}")[-1] for element in root.iter()}
        assert tags <= {"speak", "voice", "prosody", "sub", "phoneme"}, (tags, document)
        assert len(list(root)) == 1 and len(list(root[0])) == 1


# --- 8. Pauses and styles (spec Section 7.5) ------------------------------------------------


def ssml(**delivery):
    return build_ssml("راتبك وين", HAMED, "ar", "0%", "0%", {}, **delivery)


def test_with_no_pause_or_style_the_document_is_the_plain_one():
    document = ssml().document
    assert "mstts" not in document
    assert list(ET.fromstring(document)[0])[0].tag.endswith("prosody")


def test_a_pause_is_silence_between_sentences():
    voice = ET.fromstring(ssml(pause="400ms").document)[0]
    silence, prosody = list(voice)
    assert silence.tag == f"{MSTTS}silence"
    assert silence.attrib == {"type": "Sentenceboundary-exact", "value": "400ms"}
    assert prosody.text == "راتبك وين"


def test_a_style_wraps_the_prosody():
    voice = ET.fromstring(ssml(style="cheerful").document)[0]
    style = list(voice)[0]
    assert style.tag == f"{MSTTS}express-as"
    assert style.attrib == {"style": "cheerful"}
    assert list(style)[0].text == "راتبك وين"


def test_markup_counts_towards_the_bill():
    plain = ssml().billable_characters
    assert ssml(pause="400ms").billable_characters > plain
    assert ssml(style="cheerful").billable_characters > plain


@pytest.mark.parametrize(
    "bad",
    [
        *PAYLOADS,
        "400",
        "9999ms",
        "5001ms",
        "-1ms",
        "1.5s",
        "400ms ",
        "cheerful\x00",
    ],
)
def test_a_pause_outside_its_shape_is_refused(bad):
    with pytest.raises(VoiceInputError):
        ssml(pause=bad)


@pytest.mark.parametrize(
    "bad", [*PAYLOADS, "a b", "1a", "-a", "a" * 41, "cheerful\n", "مرح", "a\x00"]
)
def test_a_style_outside_its_shape_is_refused(bad):
    with pytest.raises(VoiceInputError):
        ssml(style=bad)


@pytest.mark.parametrize("change", [{"pause": "400ms"}, {"style": "cheerful"}])
def test_a_pause_or_style_makes_a_new_file(tmp_path, change):
    client = FakeSpeechClient(seconds=2.0)
    engine = make_engine(tmp_path, client)
    plain = engine.voice(TEXT, "ar", check_length=False)
    other = engine.with_prosody("0%", "0%", **change).voice(TEXT, "ar", check_length=False)
    assert plain.audio_path != other.audio_path
    assert len(client.calls) == 2


def test_each_pause_and_listed_style_is_tried_once_on_the_first_setting():
    samples = plan_samples(
        [script()],
        (HAMED, "ar-XX-OtherNeural"),
        (("-5%", "0%"), ("+5%", "0%")),
        random.Random(1),
        pauses=("400ms",),
        styles={"ar-XX-OtherNeural": ("cheerful",)},
    )
    settings = sorted((s.voice, s.rate, s.pitch, s.pause, s.style) for s in samples)
    assert settings == sorted(
        [
            (HAMED, "-5%", "0%", "", ""),
            (HAMED, "+5%", "0%", "", ""),
            (HAMED, "-5%", "0%", "400ms", ""),
            ("ar-XX-OtherNeural", "-5%", "0%", "", ""),
            ("ar-XX-OtherNeural", "+5%", "0%", "", ""),
            ("ar-XX-OtherNeural", "-5%", "0%", "400ms", ""),
            ("ar-XX-OtherNeural", "-5%", "0%", "", "cheerful"),
        ]
    )


def test_a_sample_really_uses_its_pause_and_style_and_the_key_names_them(tmp_path):
    client = FakeSpeechClient(seconds=2.0)
    samples = plan_samples(
        [script()],
        (HAMED,),
        (("0%", "0%"),),
        random.Random(1),
        pauses=("400ms",),
        styles={HAMED: ("cheerful",)},
    )
    summary = bakeoff.run_bakeoff(
        make_engine(tmp_path, client), samples, tmp_path / "run", max_chars=9_999
    )
    assert sum('value="400ms"' in call for call in client.calls) == 1
    assert sum('style="cheerful"' in call for call in client.calls) == 1
    key = summary.key_file.read_text(encoding="utf-8")
    assert '"pause": "400ms"' in key
    assert '"style": "cheerful"' in key


# --- 8. The bake-off keeps to F0's rate limit -----------------------------------------------


class Limiter:
    """20 requests in any 60 seconds, on a clock only the fake's sleep and work move."""

    def __init__(self, work_seconds):
        self.now = 0.0
        self.times = []
        self.work_seconds = work_seconds

    def sleep(self, seconds):
        self.now += seconds

    def __call__(self):
        self.now += self.work_seconds
        self.times = [t for t in self.times if self.now - t < 60]
        if len(self.times) >= 20:
            return False
        self.times.append(self.now)
        return True


def limited_client(limiter):
    class Limited(FakeSpeechClient):
        def speak_ssml(self, ssml):
            if not limiter():
                raise VoiceServiceError(429, "too many")
            return super().speak_ssml(ssml)

    return Limited(seconds=5.0)


@pytest.mark.parametrize("work_seconds", [0.0, 1.0])
def test_bakeoff_survives_the_documented_f0_rate_limit(tmp_path, work_seconds):
    limiter = Limiter(work_seconds)
    client = limited_client(limiter)
    engine = replace(make_engine(tmp_path, client), sleep=limiter.sleep)
    scripts = [script(f"{TEXT} {i}", f"s{i}") for i in range(6)]
    samples = plan_samples(
        scripts, bakeoff.DEFAULT_VOICES, bakeoff.DEFAULT_PROSODY, random.Random(1)
    )
    assert len(samples) == 60
    bakeoff.run_bakeoff(engine, samples, tmp_path / "run", max_chars=25_000)
    assert len(client.calls) == 60  # never once refused, so never retried


def test_a_re_run_from_cached_files_does_not_wait(tmp_path):
    sleeps = []
    engine = make_engine(tmp_path, FakeSpeechClient(seconds=2.0), sleeps=sleeps)
    samples = plan_samples([script()], (HAMED,), (("0%", "0%"),), random.Random(1))
    bakeoff.run_bakeoff(engine, samples, tmp_path / "one", max_chars=9_999)
    assert sleeps == [bakeoff.F0_SECONDS_PER_REQUEST]
    bakeoff.run_bakeoff(engine, samples, tmp_path / "two", max_chars=9_999)
    assert sleeps == [bakeoff.F0_SECONDS_PER_REQUEST]


def test_the_timing_report_paces_itself_too(tmp_path):
    sleeps = []
    engine = make_engine(tmp_path, FakeSpeechClient(seconds=2.0), sleeps=sleeps)
    report_for(engine)
    assert sleeps == [bakeoff.F0_SECONDS_PER_REQUEST]


# --- The command line for pauses and styles -------------------------------------------------


@pytest.fixture
def data_root(tmp_path):
    return tmp_path / "localappdata" / "SocialEngine"


@pytest.fixture
def scripts_file(data_root):
    file = data_root / "bakeoff" / "scripts.json"
    file.parent.mkdir(parents=True)
    file.write_text('[{"id": "hook", "language": "ar", "text": "راتبك وين"}]', encoding="utf-8")
    return file


def run_command(tmp_path, client, *args):
    return bakeoff.main(
        ["--voices", HAMED, "--prosody=0%:0%", *args],
        engine_factory=lambda _config, _paths: make_engine(tmp_path / "engine", client),
    )


def test_the_pause_flag_replaces_the_default(tmp_path, scripts_file):
    client = FakeSpeechClient(seconds=2.0)
    assert run_command(tmp_path, client, "--pause=250ms") == 0
    assert any('value="250ms"' in call for call in client.calls)
    assert not any('value="400ms"' in call for call in client.calls)


def test_the_style_flag_names_its_voice(tmp_path, scripts_file):
    client = FakeSpeechClient(seconds=2.0)
    assert run_command(tmp_path, client, f"--style={HAMED}:cheerful") == 0
    assert any('style="cheerful"' in call for call in client.calls)


@pytest.mark.parametrize(
    "bad",
    [
        "--pause=400",
        '--pause=400ms"/><x y="',
        "--style=cheerful",
        "--style=ar-XX-OtherNeural:cheerful",
        f'--style={HAMED}:a"><x',
    ],
)
def test_a_bad_pause_or_style_is_refused_before_any_call(tmp_path, scripts_file, capsys, bad):
    client = FakeSpeechClient(seconds=2.0)
    assert run_command(tmp_path, client, bad) == 2
    assert client.calls == []


def test_a_style_for_a_voice_not_in_the_run_is_a_bakeoff_error():
    with pytest.raises(BakeoffError, match="VOICE:STYLE"):
        bakeoff._style_settings(["ar-XX-OtherNeural:cheerful"], [HAMED])


# --- 9. Survivors of the mutation run -------------------------------------------------------


def test_the_month_is_the_utc_month_whatever_clock_the_ledger_is_given(tmp_path):
    """22:30 on 30 November in UTC is already 1 December in Riyadh, and the cap counts in UTC."""
    riyadh = timezone(timedelta(hours=3))
    clock = Clock(datetime(2026, 12, 1, 1, 30, tzinfo=riyadh))
    ledger = CharLedger(tmp_path / "voice_usage.db", clock)
    ledger.reserve(100, 500)
    clock.now = datetime(2026, 11, 30, 22, 45, tzinfo=UTC)
    assert ledger.used() == 100
    clock.now = datetime(2026, 12, 1, 0, 0, tzinfo=UTC)
    assert ledger.used() == 0


def test_a_cut_off_entry_is_not_believed(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    first = engine.voice(TEXT, "ar", check_length=False)
    # 10 s of a 30 s file: every word still fits, so only the cut-off check can catch it.
    first.audio_path.write_bytes(first.audio_path.read_bytes()[:960_000])
    entry = first.audio_path.with_suffix(".json")
    data = ve._CacheEntry.model_validate_json(entry.read_bytes())
    entry.write_text(
        data.model_copy(update={"audio_sha256": ve._sha256_of(first.audio_path)}).model_dump_json(),
        encoding="utf-8",
    )
    assert engine.voice(TEXT, "ar", check_length=False).cached is False
