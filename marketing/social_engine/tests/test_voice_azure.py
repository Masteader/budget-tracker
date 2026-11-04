"""The one voice provider, through the `SpeechClient` seam (spec Section 7, task E1).

No test here constructs the real SDK. Canned events come from `voice_fakes`, and the SDK client
runs against a stand-in module, so nothing reaches Azure.
"""

import inspect
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml
from voice_fakes import (
    CannedEvent,
    FakeSpeechClient,
    punctuation,
    sentence,
    spoken_text,
    wav_bytes,
    word,
)

from content_engine.aligner import TimedWord
from content_engine.voice_providers import azure_speech
from content_engine.voice_providers.azure_speech import (
    AzureSpeechProvider,
    SdkSpeechClient,
    SpeechOutcome,
    build_ssml,
    parse_word_events,
)
from content_engine.voiceover_engine import (
    VoiceConfigError,
    VoiceInputError,
    VoiceResult,
    VoiceServiceError,
    VoiceTimingError,
    build_voice_engine,
    reel_voice_may_be_approved,
)
from core.config import ConfigError, load_config
from core.paths import ENGINE_ROOT, EnginePaths

HAMED = "ar-SA-HamedNeural"
SSML_NAMESPACE = "{http://www.w3.org/2001/10/synthesis}"


def provider_for(client, tmp_path, **changes) -> AzureSpeechProvider:
    settings = {
        "client": client,
        "region": "uaenorth",
        "azure_tier": "F0",
        "audio_dir": tmp_path,
        "rate": "0%",
        "pitch": "0%",
        "output_format": "riff-48khz-16bit-mono-pcm",
        "pronunciation": {},
    }
    return AzureSpeechProvider(**{**settings, **changes})


def speak(*events) -> FakeSpeechClient:
    return FakeSpeechClient([SpeechOutcome(wav_bytes(1.0), list(events))])


# --- Word events ------------------------------------------------------------------------


def test_only_word_boundaries_are_kept():
    events = [
        sentence("راتبك وين يروح؟", 0),
        word("راتبك", 0),
        word("يروح", 400),
        punctuation("؟", 800),
    ]
    assert [item.text for item in parse_word_events(events)] == ["راتبك", "يروح"]


def test_ticks_convert_to_milliseconds():
    event = CannedEvent("راتبك", 12_340_000, timedelta(milliseconds=250))
    assert parse_word_events([event]) == [TimedWord("راتبك", 1234, 1484)]


def test_ten_thousand_ticks_are_one_millisecond():
    event = CannedEvent("x", 10_000, timedelta(0))
    assert parse_word_events([event]) == [TimedWord("x", 1, 1)]


@pytest.mark.parametrize(
    "events",
    [
        [word("a", 500), word("b", 100)],
        [CannedEvent("a", -1, timedelta(0))],
        [CannedEvent("a", 0, timedelta(milliseconds=-5))],
    ],
)
def test_impossible_timings_fail(events):
    with pytest.raises(VoiceTimingError):
        parse_word_events(events)


def test_an_event_that_is_not_a_word_never_becomes_a_caption():
    other = CannedEvent("x", 0, timedelta(0), boundary_type=SimpleNamespace(name="Other"))
    assert parse_word_events([other]) == []


def test_canned_events_have_the_shape_of_the_installed_sdk():
    """Importing is fine here: nothing is constructed, so nothing can reach Azure."""
    sdk = pytest.importorskip("azure.cognitiveservices.speech")
    for name in ("audio_offset", "duration", "text", "boundary_type"):
        assert hasattr(sdk.SpeechSynthesisWordBoundaryEventArgs, name)
    assert {"Word", "Punctuation", "Sentence"} <= set(sdk.SpeechSynthesisBoundaryType.__members__)
    assert {"subscription", "region"} <= set(inspect.signature(sdk.SpeechConfig).parameters)
    assert {"speech_config", "audio_config"} <= set(
        inspect.signature(sdk.SpeechSynthesizer).parameters
    )
    assert hasattr(sdk.SpeechSynthesizer, "speak_ssml_async")
    assert hasattr(sdk.SpeechSynthesizer, "synthesis_word_boundary")
    assert hasattr(sdk.SpeechConfig, "set_speech_synthesis_output_format")
    assert hasattr(sdk.SpeechSynthesisResult, "audio_data")
    assert hasattr(sdk.SpeechSynthesisResult, "cancellation_details")
    assert hasattr(sdk.SpeechSynthesisCancellationDetails, "error_code")
    assert hasattr(sdk.SpeechSynthesisCancellationDetails, "error_details")
    assert "SynthesizingAudioCompleted" in sdk.ResultReason.__members__
    assert "Canceled" in sdk.ResultReason.__members__
    assert "Riff48Khz16BitMonoPcm" in sdk.SpeechSynthesisOutputFormat.__members__
    assert set(azure_speech.STATUS_FOR_CANCEL_CODE) <= set(sdk.CancellationErrorCode.__members__)


# --- The provider -----------------------------------------------------------------------


def test_synthesize_returns_aligned_words_and_records_the_tier(tmp_path):
    script = "راتبك وين يروح؟"
    client = speak(word("راتبك", 0), word("وين", 300), word("يروح", 600))
    result = provider_for(client, tmp_path, azure_tier="S0").synthesize(script, HAMED, "ar")
    assert isinstance(result, VoiceResult)
    assert result.azure_tier == "S0"
    assert result.provider == "azure_speech"
    assert result.voice == HAMED
    assert [item.text for item in result.words] == ["راتبك", "وين", "يروح؟"]
    assert result.audio_path.read_bytes() == wav_bytes(1.0)
    assert result.billable_characters > len(script)


def test_the_brand_comes_back_as_one_token(tmp_path):
    script = "مع قوام المال تخطط"
    client = speak(word("مع", 0), word("قوام", 200), word("المال", 500), word("تخطط", 800))
    result = provider_for(client, tmp_path).synthesize(script, HAMED, "ar")
    assert [item.text for item in result.words] == ["مع", "قوام المال", "تخطط"]
    assert "قوام" not in [item.text for item in result.words]
    assert (result.words[1].start_ms, result.words[1].end_ms) == (200, 600)


def test_a_script_with_missing_word_events_fails_and_keeps_what_was_paid_for(tmp_path):
    script = "راتبك وين يروح"
    client = speak(word("راتبك", 0), word("يروح", 600))
    with pytest.raises(VoiceTimingError) as caught:
        provider_for(client, tmp_path).synthesize(script, HAMED, "ar")
    assert caught.value.result.audio_path.is_file()
    assert [item.text for item in caught.value.result.raw_words] == ["راتبك", "يروح"]


def test_a_script_with_no_word_events_at_all_fails(tmp_path):
    client = speak(sentence("راتبك", 0))
    with pytest.raises(VoiceTimingError):
        provider_for(client, tmp_path).synthesize("راتبك", HAMED, "ar")


def test_empty_audio_is_a_failure_not_a_silent_reel(tmp_path):
    client = FakeSpeechClient([SpeechOutcome(b"", [word("راتبك", 0)])])
    with pytest.raises(VoiceServiceError):
        provider_for(client, tmp_path).synthesize("راتبك", HAMED, "ar")
    assert list(tmp_path.iterdir()) == []


def test_a_sub_fix_does_not_break_timing_when_events_report_the_alias(tmp_path):
    script = "قال حسبتك"
    client = speak(word("قال", 0), word("حسبتكم", 300))
    provider = provider_for(client, tmp_path, pronunciation={"حسبتك": "حسبتكم"})
    result = provider.synthesize(script, HAMED, "ar")
    assert [item.text for item in result.words] == ["قال", "حسبتك"]


# --- SSML: every value is escaped -------------------------------------------------------


INJECTIONS = [
    "</prosody></voice></speak><speak><voice name='en-US-AvaNeural'>x",
    '"><break time="9s"/>',
    "'><break time='9s'/>",
    "<break time='9s'/>",
    '<voice name="en-US-AvaNeural">x</voice>',
    "&xxe;",
    "&amp;",
    '<!DOCTYPE s [<!ENTITY x "y">]>',
    "]]>",
    "<?xml version='1.0'?>",
    '<audio src="https://example.com/a.wav"/>',
    "a < b > c & d \" e ' f",
]


def parsed(ssml: str) -> tuple[ElementTree.Element, ElementTree.Element]:
    root = ElementTree.fromstring(ssml)
    assert root.tag == f"{SSML_NAMESPACE}speak"
    voices = list(root)
    assert len(voices) == 1
    assert voices[0].tag == f"{SSML_NAMESPACE}voice"
    prosodies = list(voices[0])
    assert len(prosodies) == 1
    assert prosodies[0].tag == f"{SSML_NAMESPACE}prosody"
    return voices[0], prosodies[0]


def build(text="راتبك وين", voice=HAMED, language="ar", rate="0%", pitch="0%", pronunciation=None):
    return build_ssml(text, voice, language, rate, pitch, pronunciation or {})


def test_plain_ssml_has_the_expected_shape():
    ssml = build().document
    voice, prosody = parsed(ssml)
    assert voice.attrib["name"] == HAMED
    assert prosody.attrib == {"rate": "0%", "pitch": "0%"}
    assert prosody.text == "راتبك وين"
    assert ElementTree.fromstring(ssml).attrib[
        "{http://www.w3.org/XML/1998/namespace}lang"
    ] == "ar-SA"


@pytest.mark.parametrize("payload", INJECTIONS)
def test_script_text_cannot_inject_markup(payload):
    _, prosody = parsed(build(text=f"قبل {payload} بعد").document)
    assert list(prosody) == []
    assert prosody.text == f"قبل {payload} بعد"


@pytest.mark.parametrize("payload", INJECTIONS)
def test_a_pronunciation_value_cannot_inject_markup(payload):
    """The audit finding: `Voice.pronunciation` values reach SSML as a `<sub>` alias."""
    ssml = build(text="قال راتبك", pronunciation={"راتبك": payload}).document
    _, prosody = parsed(ssml)
    children = list(prosody)
    assert [child.tag for child in children] == [f"{SSML_NAMESPACE}sub"]
    assert children[0].attrib == {"alias": payload}
    assert children[0].text == "راتبك"
    assert list(children[0]) == []


@pytest.mark.parametrize("payload", INJECTIONS)
def test_a_phoneme_value_cannot_inject_markup(payload):
    ssml = build(text="قال راتبك", pronunciation={"راتبك": f"ipa:{payload}"}).document
    _, prosody = parsed(ssml)
    children = list(prosody)
    assert [child.tag for child in children] == [f"{SSML_NAMESPACE}phoneme"]
    assert children[0].attrib == {"alphabet": "ipa", "ph": payload}
    assert list(children[0]) == []


@pytest.mark.parametrize("payload", INJECTIONS)
def test_a_pronunciation_key_cannot_inject_markup(payload):
    ssml = build(text=f"قال {payload} هنا", pronunciation={payload: "بديل"}).document
    _, prosody = parsed(ssml)
    # Whether the key matched depends on its edges. Only plain text or a <sub> may hold it.
    assert all(child.tag == f"{SSML_NAMESPACE}sub" for child in prosody)
    assert payload in spoken_text(ssml)


@pytest.mark.parametrize("payload", INJECTIONS)
@pytest.mark.parametrize("field", ["voice", "rate", "pitch"])
def test_voice_and_prosody_values_cannot_inject_markup(field, payload):
    voice, prosody = parsed(build(**{field: payload}).document)
    assert list(prosody) == []
    assert {"voice": voice.attrib["name"], **prosody.attrib}[field] == payload


def test_a_pronunciation_value_from_a_real_config_file_is_escaped_on_the_way_to_azure(
    tmp_path, monkeypatch
):
    """End to end: the shipped config shape, a hostile value, and what the client is handed."""
    data = yaml.safe_load((ENGINE_ROOT / "config.yaml").read_text(encoding="utf-8"))
    payload = '"><break time="9s"/><voice name="en-US-AvaNeural">x</voice>'
    data["voice"]["pronunciation"] = {"راتبك": payload}
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    config = load_config(path)

    client = FakeSpeechClient(seconds=1.0)
    provider = provider_for(
        client, tmp_path, pronunciation=config.voice.pronunciation, rate=config.voice.rate
    )
    provider.synthesize("قال راتبك", HAMED, "ar")
    _, prosody = parsed(client.calls[0])
    assert [child.tag for child in prosody] == [f"{SSML_NAMESPACE}sub"]
    assert list(prosody)[0].attrib == {"alias": payload}


@pytest.mark.parametrize("bad", ["a\x00b", "a\x0bb", "a\ud800b", "a￾b"])
@pytest.mark.parametrize("field", ["text", "voice", "rate", "pitch"])
def test_characters_xml_cannot_hold_are_refused_not_sent(field, bad):
    with pytest.raises(VoiceInputError):
        build(**{field: bad})


@pytest.mark.parametrize("bad", ["a\x00b", "ipa:a\x00b"])
def test_a_pronunciation_value_xml_cannot_hold_is_refused(bad):
    with pytest.raises(VoiceInputError):
        build(text="راتبك", pronunciation={"راتبك": bad})


@pytest.mark.parametrize("pronunciation", [{"": "x"}, {"  ": "x"}, {"راتبك": ""}, {"راتبك": " "}])
def test_blank_pronunciation_entries_are_refused(pronunciation):
    with pytest.raises(VoiceConfigError):
        build(pronunciation=pronunciation)


def test_a_blank_phoneme_is_refused():
    with pytest.raises(VoiceConfigError):
        build(pronunciation={"راتبك": "ipa: "})


@pytest.mark.parametrize("text", ["", "   ", "\n"])
def test_blank_text_is_refused(text):
    with pytest.raises(VoiceInputError):
        build(text=text)


@pytest.mark.parametrize("text", ["مع {brand_ar} اليوم", "{brand_en} soon", "{brand_hashtag}"])
def test_an_unfilled_brand_token_is_never_read_aloud(text):
    with pytest.raises(VoiceInputError, match="token"):
        build(text=text)


@pytest.mark.parametrize("language", ["", "fr", 'ar"><x', "AR"])
def test_an_unknown_language_is_refused(language):
    with pytest.raises(VoiceInputError):
        build(language=language)


def test_english_uses_an_english_locale():
    ssml = build(text="hello", voice="en-US-AvaNeural", language="en").document
    root = ElementTree.fromstring(ssml)
    assert root.attrib["{http://www.w3.org/XML/1998/namespace}lang"] == "en-US"


# --- SSML: pronunciation applies once, to whole words -----------------------------------


def test_replacements_run_in_one_pass_so_an_alias_is_never_rewritten():
    ssml = build(text="ألف باء", pronunciation={"ألف": "باء", "باء": "ألف"}).document
    _, prosody = parsed(ssml)
    assert [child.attrib["alias"] for child in prosody] == ["باء", "ألف"]
    assert [child.text for child in prosody] == ["ألف", "باء"]


def test_a_fix_applies_to_whole_words_only():
    _, prosody = parsed(build(text="راتبك راتب", pronunciation={"راتب": "رااتب"}).document)
    assert [child.text for child in prosody] == ["راتب"]
    assert prosody.text == "راتبك "


def test_the_longest_fix_wins():
    ssml = build(
        text="مع قوام المال", pronunciation={"قوام": "خطأ", "قوام المال": "صواب"}
    ).document
    _, prosody = parsed(ssml)
    assert [child.attrib["alias"] for child in prosody] == ["صواب"]


def test_text_around_a_fix_stays_in_order():
    ssml = build(text="قبل & راتب > بعد", pronunciation={"راتب": "ر"}).document
    assert spoken_text(ssml) == "قبل & راتب > بعد"


# --- Billable characters ----------------------------------------------------------------


def test_billing_counts_inner_markup_and_not_the_speak_and_voice_tags():
    """Microsoft bills markup inside the document, except `<speak>` and `<voice>`."""
    plain = build(text="راتبك")
    assert plain.billable_characters == len('<prosody rate="0%" pitch="0%">راتبك</prosody>')
    fixed = build(text="راتبك", pronunciation={"راتبك": "ر"})
    assert fixed.billable_characters > plain.billable_characters


def test_billing_counts_code_points():
    assert build(text="قوام").billable_characters - build(text="a").billable_characters == 3


# --- The fingerprint: what changes the audio changes the file ---------------------------


def fingerprint(tmp_path, *, text="راتبك", voice=HAMED, language="ar", **changes) -> str:
    provider = provider_for(FakeSpeechClient(), tmp_path, **changes)
    return provider.fingerprint(text, voice, language)


def test_the_same_request_gives_the_same_fingerprint(tmp_path):
    assert fingerprint(tmp_path) == fingerprint(tmp_path)
    assert len(fingerprint(tmp_path)) == 64


@pytest.mark.parametrize(
    "change",
    [
        {"text": "فاتورة"},
        {"voice": "ar-SA-ZariyahNeural"},
        {"region": "eastus"},
        {"azure_tier": "S0"},
        {"rate": "+5%"},
        {"pitch": "+5%"},
        {"pronunciation": {"راتبك": "ر"}},
        {"output_format": "other"},
    ],
)
def test_anything_that_changes_the_audio_changes_the_fingerprint(tmp_path, change):
    assert fingerprint(tmp_path, **change) != fingerprint(tmp_path)


def test_with_prosody_changes_only_the_prosody(tmp_path):
    client = FakeSpeechClient()
    provider = provider_for(client, tmp_path)
    slower = provider.with_prosody("-5%", "+2%")
    assert (slower.rate, slower.pitch) == ("-5%", "+2%")
    assert slower.client is client
    assert (provider.rate, provider.pitch) == ("0%", "0%")


# --- The SDK stays behind the seam ------------------------------------------------------


def run_python(code: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-c", code],
        cwd=ENGINE_ROOT,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )


@pytest.mark.parametrize(
    "module",
    [
        "content_engine.voice_providers.azure_speech",
        "content_engine.voiceover_engine",
        "content_engine.aligner",
        "content_engine.bakeoff",
    ],
)
def test_importing_the_voice_code_does_not_load_the_sdk(module):
    done = run_python(
        f"import sys, {module}\n"
        "assert not [m for m in sys.modules if m.startswith('azure')], 'SDK was imported'\n"
    )
    assert done.returncode == 0, done.stderr


class _Signal:
    def __init__(self):
        self.handlers = []

    def connect(self, handler):
        self.handlers.append(handler)


class _CancelCode:
    def __init__(self, name):
        self.name = name


def fake_sdk(result, created):
    """A stand-in module with the parts of the SDK the client touches."""

    class SpeechConfig:
        def __init__(self, subscription, region):
            created["key"], created["region"] = subscription, region

        def set_speech_synthesis_output_format(self, value):
            created["format"] = value

    class SpeechSynthesizer:
        def __init__(self, speech_config, audio_config="default speaker"):
            created["audio_config"] = audio_config
            self.synthesis_word_boundary = _Signal()

        def speak_ssml_async(self, ssml):
            created["ssml"] = ssml
            for handler in self.synthesis_word_boundary.handlers:
                handler(word("راتبك", 0))
            return SimpleNamespace(get=lambda: result)

    return SimpleNamespace(
        SpeechConfig=SpeechConfig,
        SpeechSynthesizer=SpeechSynthesizer,
        ResultReason=SimpleNamespace(SynthesizingAudioCompleted="done", Canceled="canceled"),
        SpeechSynthesisOutputFormat=SimpleNamespace(Riff48Khz16BitMonoPcm="riff48"),
    )


def sdk_client(result, created, key="fake-key-123") -> SdkSpeechClient:
    return SdkSpeechClient(
        key, "uaenorth", "riff-48khz-16bit-mono-pcm", sdk_loader=lambda: fake_sdk(result, created)
    )


def completed() -> SimpleNamespace:
    return SimpleNamespace(reason="done", audio_data=b"RIFFdata", cancellation_details=None)


def canceled(code: str, details: str = "details") -> SimpleNamespace:
    return SimpleNamespace(
        reason="canceled",
        audio_data=b"",
        cancellation_details=SimpleNamespace(error_code=_CancelCode(code), error_details=details),
    )


def test_the_sdk_client_wires_the_key_region_format_and_no_speaker():
    created = {}
    outcome = sdk_client(completed(), created).speak_ssml("<speak/>")
    assert created["key"] == "fake-key-123"
    assert created["region"] == "uaenorth"
    assert created["format"] == "riff48"
    assert created["ssml"] == "<speak/>"
    # The SDK's default is the laptop's speaker. None means audio comes back in the result.
    assert created["audio_config"] is None
    assert outcome.audio_data == b"RIFFdata"
    assert [event.text for event in outcome.events] == ["راتبك"]


@pytest.mark.parametrize(
    ("code", "status", "retryable"),
    [
        ("TooManyRequests", 429, True),
        ("ServiceError", 500, True),
        ("ServiceUnavailable", 503, True),
        ("ServiceTimeout", 504, True),
        ("BadRequest", 400, False),
        ("AuthenticationFailure", 401, False),
        ("Forbidden", 403, False),
        ("ConnectionFailure", None, False),
        ("RuntimeError", None, False),
        ("SomethingNew", None, False),
    ],
)
def test_cancellations_become_statuses_and_only_429_and_5xx_retry(code, status, retryable):
    with pytest.raises(VoiceServiceError) as caught:
        sdk_client(canceled(code), {}).speak_ssml("<speak/>")
    assert caught.value.status == status
    assert caught.value.retryable is retryable


def test_the_key_never_reaches_an_error_or_a_repr():
    key = "fake-key-123"
    client = sdk_client(canceled("AuthenticationFailure", f"bad key {key} in region"), {}, key=key)
    with pytest.raises(VoiceServiceError) as caught:
        client.speak_ssml("<speak/>")
    assert key not in str(caught.value)
    assert key not in repr(client)
    assert key not in repr(provider_for(client, Path(".")))


def test_a_native_sdk_failure_becomes_a_keyless_voice_error():
    key = "fake-key-123"
    sdk = fake_sdk(completed(), {})

    def explode(*_args, **_kwargs):
        raise RuntimeError(f"native failure using {key}")

    sdk.SpeechConfig = explode
    client = SdkSpeechClient(key, "uaenorth", "riff-48khz-16bit-mono-pcm", sdk_loader=lambda: sdk)
    with pytest.raises(VoiceServiceError) as caught:
        client.speak_ssml("<speak/>")
    assert caught.value.status is None
    assert caught.value.retryable is False
    assert key not in str(caught.value)
    assert caught.value.__cause__ is None
    assert caught.value.__suppress_context__ is True


def test_the_whole_path_runs_from_the_env_file_through_the_sdk_seam(tmp_path):
    created = {}
    result = SimpleNamespace(
        reason="done", audio_data=wav_bytes(1.0), cancellation_details=None
    )
    engine = build_voice_engine(
        load_config(), paths_with_env(tmp_path), sdk_loader=lambda: fake_sdk(result, created)
    )
    voiced = engine.voice("راتبك", "ar", check_length=False)
    assert created["key"] == "fake-key-123"
    assert created["region"] == "uaenorth"
    assert voiced.audio_path.parent == EnginePaths.from_root(tmp_path).voiceovers
    assert [item.text for item in voiced.words] == ["راتبك"]
    assert engine.ledger.used() == voiced.billable_characters
    assert (EnginePaths.from_root(tmp_path).state_db.parent / "voice_usage.db").is_file()


def test_a_long_error_from_the_service_is_cut_short():
    with pytest.raises(VoiceServiceError) as caught:
        sdk_client(canceled("ServiceError", "x" * 10_000), {}).speak_ssml("<speak/>")
    assert len(str(caught.value)) < 1000


@pytest.mark.parametrize("failure", [ImportError("no module"), OSError("WinError 206")])
def test_an_sdk_that_will_not_load_says_so(failure):
    def loader():
        raise failure

    client = SdkSpeechClient("k", "uaenorth", "riff-48khz-16bit-mono-pcm", sdk_loader=loader)
    with pytest.raises(VoiceConfigError, match="Speech SDK"):
        client.speak_ssml("<speak/>")


def test_building_the_client_does_not_load_the_sdk():
    def loader():
        raise AssertionError("loaded too early")

    SdkSpeechClient("k", "uaenorth", "riff-48khz-16bit-mono-pcm", sdk_loader=loader)


def test_an_unknown_output_format_is_refused():
    with pytest.raises(VoiceConfigError, match="output_format"):
        SdkSpeechClient("k", "uaenorth", "ogg-16khz", sdk_loader=lambda: None)


# --- Azure is the only provider (D8) ----------------------------------------------------


def shipped_data() -> dict:
    return yaml.safe_load((ENGINE_ROOT / "config.yaml").read_text(encoding="utf-8"))


@pytest.mark.parametrize("other", ["edge", "google", "polly", "", "AZURE_SPEECH", None])
def test_config_rejects_every_other_provider(tmp_path, other):
    data = shipped_data()
    data["voice"]["provider"] = other
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    with pytest.raises(ConfigError, match="voice.provider"):
        load_config(path)


def test_azure_speech_is_the_only_provider_on_disk():
    folder = ENGINE_ROOT / "content_engine" / "voice_providers"
    modules = sorted(path.name for path in folder.glob("*.py"))
    assert modules == ["__init__.py", "azure_speech.py"]


def paths_with_env(tmp_path, text="AZURE_SPEECH_KEY=fake-key-123\nAZURE_SPEECH_REGION=uaenorth\n"):
    (tmp_path / ".env").write_text(text, encoding="utf-8")
    return EnginePaths.from_root(tmp_path)


def test_the_engine_builds_only_azure_even_if_the_config_check_was_bypassed(tmp_path):
    config = load_config()
    forged = config.model_copy(
        update={"voice": config.voice.model_copy(update={"provider": "other"})}
    )
    with pytest.raises(VoiceConfigError, match="azure_speech"):
        build_voice_engine(forged, paths_with_env(tmp_path))


def test_the_engine_builds_azure_from_the_env_file_without_loading_the_sdk(tmp_path):
    def loader():
        raise AssertionError("loaded too early")

    engine = build_voice_engine(load_config(), paths_with_env(tmp_path), sdk_loader=loader)
    assert engine.provider.name == "azure_speech"
    assert engine.provider.azure_tier == "F0"
    assert engine.provider.region == "uaenorth"
    assert "fake-key-123" not in repr(engine)


@pytest.mark.parametrize(
    ("env", "named"),
    [
        ("", "AZURE_SPEECH_KEY"),
        ("AZURE_SPEECH_KEY=\nAZURE_SPEECH_REGION=uaenorth\n", "AZURE_SPEECH_KEY"),
        ("AZURE_SPEECH_KEY=secret-value\n", "AZURE_SPEECH_REGION"),
        ("AZURE_SPEECH_KEY=secret-value\nAZURE_SPEECH_REGION= \n", "AZURE_SPEECH_REGION"),
        ("AZURE_SPEECH_KEY=secret-value\nAZURE_SPEECH_REGION=../evil\n", "AZURE_SPEECH_REGION"),
    ],
)
def test_missing_azure_settings_name_the_variable_and_never_the_value(tmp_path, env, named):
    with pytest.raises(VoiceConfigError, match=named) as caught:
        build_voice_engine(load_config(), paths_with_env(tmp_path, env))
    assert "secret-value" not in str(caught.value)


def test_a_missing_env_file_names_the_variable(tmp_path):
    with pytest.raises(VoiceConfigError, match="AZURE_SPEECH_KEY"):
        build_voice_engine(load_config(), EnginePaths.from_root(tmp_path))


def test_the_engine_keeps_the_brand_and_test_brand_as_one_token(tmp_path):
    engine = build_voice_engine(load_config(), paths_with_env(tmp_path), sdk_loader=lambda: None)
    assert {"قوام المال", "Qawam Money", "علامة تجريبية", "TEST BRAND"} <= set(
        engine.provider.caption_phrases
    )


# --- F0 audio stays out of public reels (D19, spec Section 3.3 invariant 6) -------------


def voice_settings(allow: bool):
    return load_config().voice.model_copy(update={"allow_public_on_f0": allow})


def test_an_f0_reel_cannot_be_approved_while_public_f0_is_off():
    assert reel_voice_may_be_approved(voice_settings(False), "F0") is False


def test_an_s0_reel_can_be_approved():
    assert reel_voice_may_be_approved(voice_settings(False), "S0") is True


def test_the_owner_can_explicitly_allow_f0():
    assert reel_voice_may_be_approved(voice_settings(True), "F0") is True


def test_the_shipped_config_blocks_f0():
    config = load_config()
    assert reel_voice_may_be_approved(config.voice, "F0") is False


@pytest.mark.parametrize("tier", [None, "", "f0", "s0", "S1", "F0 ", "unknown", 0])
@pytest.mark.parametrize("allow", [True, False])
def test_an_unknown_tier_is_never_approved(allow, tier):
    assert reel_voice_may_be_approved(voice_settings(allow), tier) is False


def test_the_gate_reads_the_tier_recorded_with_the_reel_not_todays_config():
    """Switching the config to S0 later must not launder audio that was voiced on F0."""
    settings = load_config().voice.model_copy(update={"azure_tier": "S0"})
    assert reel_voice_may_be_approved(settings, "F0") is False
