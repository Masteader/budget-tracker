"""What keeps the voice step from spending or re-billing (spec Sections 3.5, 6.2, 7.3, task E3)."""

import json
import threading
from datetime import UTC, datetime

import pytest
from voice_fakes import (
    NOVEMBER,
    Clock,
    FakeSpeechClient,
    make_engine,
    spoken_text,
    wav_bytes,
    word,
)

from content_engine.voice_providers.azure_speech import SpeechOutcome
from content_engine.voiceover_engine import (
    MAX_SPEECH_SECONDS,
    MAX_TRIES,
    MIN_SPEECH_SECONDS,
    CharLedger,
    VoiceCapReached,
    VoiceConfigError,
    VoiceInputError,
    VoiceLengthError,
    VoiceServiceError,
    VoiceTimingError,
    VoiceUsageError,
    check_script_length,
)

SCRIPT =" ".join(["راتبك"] * 50)  # 299 characters, about 33 s at 9 characters a second
DECEMBER = datetime(2026, 12, 1, tzinfo=UTC)


def used(engine) -> int:
    return engine.ledger.used()


def cost(engine, text=SCRIPT) -> int:
    return engine.provider.billable_characters(text, "ar-SA-HamedNeural", "ar")


def cache_files(tmp_path) -> list[str]:
    return sorted(path.name for path in (tmp_path / "voiceovers").iterdir())


# --- monthly_char_cap -------------------------------------------------------------------


def test_the_cap_stops_synthesis_before_the_call(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client, voice={"monthly_char_cap": 10})
    with pytest.raises(VoiceCapReached, match="10"):
        engine.voice(SCRIPT, "ar")
    assert client.calls == []
    assert used(engine) == 0


def test_the_cap_uses_the_configured_value_and_is_inclusive(tmp_path):
    probe = make_engine(tmp_path, FakeSpeechClient())
    exact = cost(probe)

    client = FakeSpeechClient()
    fits = make_engine(tmp_path / "fits", client, voice={"monthly_char_cap": exact})
    fits.voice(SCRIPT, "ar")
    assert len(client.calls) == 1
    assert used(fits) == exact

    client = FakeSpeechClient()
    over = make_engine(tmp_path / "over", client, voice={"monthly_char_cap": exact - 1})
    with pytest.raises(VoiceCapReached):
        over.voice(SCRIPT, "ar")
    assert client.calls == []


def test_the_cap_counts_everything_already_used_this_month(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    cap = cost(engine) + 10
    engine = make_engine(tmp_path, client, voice={"monthly_char_cap": cap})
    engine.voice(SCRIPT, "ar")
    with pytest.raises(VoiceCapReached):
        engine.voice(SCRIPT + " راتبك", "ar")
    assert len(client.calls) == 1


def test_usage_survives_a_restart(tmp_path):
    client = FakeSpeechClient()
    first = make_engine(tmp_path, client)
    first.voice(SCRIPT, "ar")
    second = make_engine(tmp_path, client)
    assert used(second) == cost(first)


def test_a_new_month_starts_at_zero_and_the_old_one_is_kept(tmp_path):
    clock = Clock()
    engine = make_engine(tmp_path, FakeSpeechClient(), clock=clock)
    engine.voice(SCRIPT, "ar")
    spent = used(engine)
    clock.now = DECEMBER
    assert used(engine) == 0
    clock.now = NOVEMBER
    assert used(engine) == spent


@pytest.mark.parametrize("tier", ["F0", "S0"])
def test_the_cap_applies_on_either_tier(tmp_path, tier):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client, voice={"monthly_char_cap": 10}, azure_tier=tier)
    with pytest.raises(VoiceCapReached):
        engine.voice(SCRIPT, "ar")
    assert client.calls == []


def test_characters_are_charged_before_the_call_so_a_crash_cannot_lose_them(tmp_path):
    class CrashingClient(FakeSpeechClient):
        def speak_ssml(self, ssml):
            self.calls.append(ssml)
            raise KeyboardInterrupt

    engine = make_engine(tmp_path, CrashingClient())
    with pytest.raises(KeyboardInterrupt):
        engine.voice(SCRIPT, "ar")
    assert used(engine) == cost(engine)


def test_a_broken_usage_file_stops_synthesis_rather_than_reading_as_zero(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    path = tmp_path / "state" / "voice_usage.db"
    path.parent.mkdir(parents=True)
    path.write_bytes(b"this is not a database, and it is long enough to be read as one" * 20)
    with pytest.raises(VoiceUsageError):
        engine.voice(SCRIPT, "ar")
    assert client.calls == []


def test_two_processes_racing_cannot_pass_the_cap_together(tmp_path):
    path = tmp_path / "voice_usage.db"
    allowed, refused = [], []

    def spend():
        ledger = CharLedger(path, Clock())
        try:
            allowed.append(ledger.reserve(100, 500))
        except VoiceCapReached:
            refused.append(1)

    threads = [threading.Thread(target=spend) for _ in range(12)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert len(allowed) == 5
    assert len(refused) == 7
    assert CharLedger(path, Clock()).used() == 500


def test_a_release_gives_the_characters_back(tmp_path):
    ledger = CharLedger(tmp_path / "voice_usage.db", Clock())
    held = ledger.reserve(100, 500)
    ledger.release(held)
    assert ledger.used() == 0


@pytest.mark.parametrize("chars", [0, -1])
def test_a_reservation_must_be_for_something(tmp_path, chars):
    with pytest.raises(ValueError):
        CharLedger(tmp_path / "voice_usage.db", Clock()).reserve(chars, 500)


# --- Files keyed by a hash, so a re-run does not re-bill --------------------------------


def test_a_re_run_does_not_call_or_charge_again(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    first = engine.voice(SCRIPT, "ar")
    charged = used(engine)
    second = engine.voice(SCRIPT, "ar")
    assert len(client.calls) == 1
    assert used(engine) == charged
    assert second.audio_path == first.audio_path
    assert second.words == first.words
    assert second.azure_tier == first.azure_tier
    assert second.billable_characters == first.billable_characters
    assert (first.cached, second.cached) == (False, True)


def test_a_restarted_engine_finds_the_file(tmp_path):
    client = FakeSpeechClient()
    make_engine(tmp_path, client).voice(SCRIPT, "ar")
    make_engine(tmp_path, client).voice(SCRIPT, "ar")
    assert len(client.calls) == 1


def test_the_file_is_named_by_the_hash_and_no_temp_file_stays(tmp_path):
    engine = make_engine(tmp_path, FakeSpeechClient())
    result = engine.voice(SCRIPT, "ar")
    key = engine.provider.fingerprint(SCRIPT, "ar-SA-HamedNeural", "ar")
    assert result.audio_path.name == f"{key}.wav"
    assert cache_files(tmp_path) == [f"{key}.json", f"{key}.wav"]


def test_cached_audio_still_plays_when_the_cap_is_used_up(tmp_path):
    client = FakeSpeechClient()
    first = make_engine(tmp_path, client)
    first.voice(SCRIPT, "ar")
    capped = make_engine(tmp_path, client, voice={"monthly_char_cap": 1})
    assert capped.voice(SCRIPT, "ar").cached is True
    assert len(client.calls) == 1


@pytest.mark.parametrize(
    ("first", "second"),
    [
        ({}, {"region": "eastus"}),
        ({}, {"azure_tier": "S0"}),
        ({}, {"rate": "+5%"}),
        ({}, {"pitch": "+5%"}),
        ({}, {"pronunciation": {"راتبك": "رااتبك"}}),
    ],
)
def test_a_change_that_changes_the_audio_is_a_new_file(tmp_path, first, second):
    client = FakeSpeechClient()
    one = make_engine(tmp_path, client, **first).voice(SCRIPT, "ar")
    two = make_engine(tmp_path, client, **second).voice(SCRIPT, "ar")
    assert len(client.calls) == 2
    assert one.audio_path != two.audio_path


def test_different_text_and_voice_are_new_files(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    engine.voice(SCRIPT, "ar")
    engine.voice(SCRIPT + " راتبك", "ar")
    engine.voice(SCRIPT, "ar", voice_name="ar-SA-ZariyahNeural")
    assert len(client.calls) == 3


def test_re_voicing_on_s0_makes_new_audio_recorded_as_s0(tmp_path):
    """The Re-voice button (spec Section 9.3): F0 audio must not come back labelled S0."""
    client = FakeSpeechClient()
    free = make_engine(tmp_path, client, azure_tier="F0").voice(SCRIPT, "ar")
    paid = make_engine(tmp_path, client, azure_tier="S0").voice(SCRIPT, "ar")
    assert (free.azure_tier, paid.azure_tier) == ("F0", "S0")
    assert free.audio_path != paid.audio_path
    assert len(client.calls) == 2


def _sidecar(tmp_path):
    return next((tmp_path / "voiceovers").glob("*.json"))


def _audio(tmp_path):
    return next((tmp_path / "voiceovers").glob("*.wav"))


def _flip_audio(tmp_path):
    path = _audio(tmp_path)
    path.write_bytes(path.read_bytes()[:-2] + b"\x01\x01")


def _edit_sidecar(tmp_path, **changes):
    path = _sidecar(tmp_path)
    data = json.loads(path.read_text(encoding="utf-8"))
    data.update(changes)
    path.write_text(json.dumps(data), encoding="utf-8")


@pytest.mark.parametrize(
    "damage",
    [
        _flip_audio,
        lambda tmp_path: _audio(tmp_path).unlink(),
        lambda tmp_path: _sidecar(tmp_path).unlink(),
        lambda tmp_path: _sidecar(tmp_path).write_text("{not json", encoding="utf-8"),
        lambda tmp_path: _sidecar(tmp_path).write_bytes(b"\xff\xfe\x00"),
        lambda tmp_path: _sidecar(tmp_path).write_text("[]", encoding="utf-8"),
        lambda tmp_path: _edit_sidecar(tmp_path, azure_tier="S0"),
        lambda tmp_path: _edit_sidecar(tmp_path, key="0" * 64),
        lambda tmp_path: _edit_sidecar(tmp_path, voice="ar-SA-ZariyahNeural"),
        lambda tmp_path: _edit_sidecar(tmp_path, provider="other"),
        lambda tmp_path: _edit_sidecar(tmp_path, raw_words="x"),
        lambda tmp_path: _edit_sidecar(tmp_path, surprise=1),
    ],
    ids=[
        "changed_audio",
        "no_audio",
        "no_sidecar",
        "bad_json",
        "bad_utf8",
        "wrong_shape",
        "forged_tier",
        "wrong_key",
        "wrong_voice",
        "wrong_provider",
        "bad_words",
        "unknown_field",
    ],
)
def test_a_damaged_or_forged_cache_entry_is_not_trusted(tmp_path, damage):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    engine.voice(SCRIPT, "ar")
    damage(tmp_path)
    again = engine.voice(SCRIPT, "ar")
    assert len(client.calls) == 2
    assert again.cached is False
    assert again.azure_tier == "F0"


def test_a_timing_failure_is_billed_once_and_keeps_the_audio(tmp_path):
    client = FakeSpeechClient([SpeechOutcome(wav_bytes(30), [word("راتبك", 0)])])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceTimingError) as first:
        engine.voice(SCRIPT, "ar")
    charged = used(engine)
    assert first.value.result.audio_path.is_file()

    with pytest.raises(VoiceTimingError) as second:
        engine.voice(SCRIPT, "ar")
    assert len(client.calls) == 1
    assert used(engine) == charged == cost(engine)
    assert second.value.result.audio_path == first.value.result.audio_path
    assert [item.text for item in second.value.result.raw_words] == ["راتبك"]


def test_a_cache_hit_applies_the_current_caption_phrases(tmp_path):
    """Audio stays valid when only the caption grouping changes, so no new bill."""
    text = "علامة تجريبية " + SCRIPT
    client = FakeSpeechClient()
    plain = make_engine(tmp_path, client).voice(text, "ar")
    assert plain.words[0].text == "علامة"

    grouped = make_engine(
        tmp_path, client, caption_phrases=("قوام المال", "علامة تجريبية")
    ).voice(text, "ar")
    assert grouped.words[0].text == "علامة تجريبية"
    assert len(client.calls) == 1


# --- Audio that is not what was asked for -----------------------------------------------


@pytest.mark.parametrize(
    "audio",
    [b"this is not audio", wav_bytes(30, rate=24_000)],
    ids=["not_a_wav", "not_48khz"],
)
def test_unusable_audio_fails_and_is_not_kept(tmp_path, audio):
    client = FakeSpeechClient([SpeechOutcome(audio, [word("راتبك", 0)])])
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceServiceError):
        engine.voice(SCRIPT, "ar")
    assert cache_files(tmp_path) == []
    assert len(client.calls) == 1


# --- Retries ----------------------------------------------------------------------------


def refused(status: int | None) -> VoiceServiceError:
    return VoiceServiceError(status, f"status {status}")


def ok() -> SpeechOutcome:
    return SpeechOutcome(wav_bytes(30), [word("راتبك", i * 300) for i in range(50)])


@pytest.mark.parametrize("status", [429, 500, 503, 504, 599])
def test_429_and_server_errors_retry_with_growing_delay(tmp_path, status):
    sleeps = []
    client = FakeSpeechClient([refused(status), refused(status), ok()])
    result = make_engine(tmp_path, client, sleeps=sleeps).voice(SCRIPT, "ar")
    assert len(client.calls) == 3
    assert len(sleeps) == 2
    assert sleeps[0] > 0
    assert sleeps[1] > sleeps[0]
    assert result.cached is False


@pytest.mark.parametrize("status", [429, 500, 503])
def test_three_tries_is_the_limit(tmp_path, status):
    sleeps = []
    client = FakeSpeechClient([refused(status)] * 5)
    with pytest.raises(VoiceServiceError) as caught:
        make_engine(tmp_path, client, sleeps=sleeps).voice(SCRIPT, "ar")
    assert MAX_TRIES == 3
    assert len(client.calls) == 3
    assert len(sleeps) == 2
    assert caught.value.status == status
    assert "3 tries" in str(caught.value)


@pytest.mark.parametrize("status", [None, 400, 401, 403, 404, 408, 499, 300, 600])
def test_every_other_failure_is_not_retried(tmp_path, status):
    sleeps = []
    client = FakeSpeechClient([refused(status), ok()])
    with pytest.raises(VoiceServiceError):
        make_engine(tmp_path, client, sleeps=sleeps).voice(SCRIPT, "ar")
    assert len(client.calls) == 1
    assert sleeps == []


def test_an_unexpected_exception_is_not_retried(tmp_path):
    client = FakeSpeechClient([ValueError("bug"), ok()])
    with pytest.raises(ValueError):
        make_engine(tmp_path, client).voice(SCRIPT, "ar")
    assert len(client.calls) == 1


def test_no_other_provider_is_tried_when_azure_keeps_failing(tmp_path):
    client = FakeSpeechClient([refused(503)] * 3)
    engine = make_engine(tmp_path, client)
    with pytest.raises(VoiceServiceError):
        engine.voice(SCRIPT, "ar")
    assert engine.provider.name == "azure_speech"
    assert {spoken_text(call) for call in client.calls} == {SCRIPT}
    assert len(client.calls) == 3
    assert not hasattr(engine, "fallback")


def test_a_definite_refusal_gives_the_characters_back(tmp_path):
    for status in (429, 401, 403):
        engine = make_engine(
            tmp_path / str(status), FakeSpeechClient([refused(status)] * 3), sleeps=[]
        )
        with pytest.raises(VoiceServiceError):
            engine.voice(SCRIPT, "ar")
        assert used(engine) == 0, status


def test_a_server_error_stays_charged_because_azure_may_have_done_the_work(tmp_path):
    engine = make_engine(tmp_path, FakeSpeechClient([refused(503)] * 3))
    with pytest.raises(VoiceServiceError):
        engine.voice(SCRIPT, "ar")
    assert used(engine) == 3 * cost(engine)


def test_a_retry_is_stopped_by_the_cap_too(tmp_path):
    probe = make_engine(tmp_path, FakeSpeechClient())
    client = FakeSpeechClient([refused(503)] * 3)
    engine = make_engine(
        tmp_path / "capped", client, voice={"monthly_char_cap": cost(probe) * 2 - 1}
    )
    with pytest.raises(VoiceCapReached):
        engine.voice(SCRIPT, "ar")
    assert len(client.calls) == 1


# --- Length -----------------------------------------------------------------------------


def test_the_limits_match_the_spec():
    assert (MIN_SPEECH_SECONDS, MAX_SPEECH_SECONDS) == (15, 45)


@pytest.mark.parametrize(
    ("characters", "per_second", "fits"),
    [
        (135, 9.0, True),
        (405, 9.0, True),
        (134, 9.0, False),
        (406, 9.0, False),
        (299, 5.0, False),
        (320, 20.0, True),
        (299, 40.0, False),
    ],
)
def test_the_length_check_uses_the_configured_rate(characters, per_second, fits):
    text = "ر" * characters
    if fits:
        assert check_script_length(text, per_second) == pytest.approx(characters / per_second)
    else:
        with pytest.raises(VoiceLengthError):
            check_script_length(text, per_second)


def test_runs_of_spaces_do_not_count_as_speech():
    assert check_script_length("ر" * 135 + " " * 500, 9.0) == pytest.approx(15)


@pytest.mark.parametrize("change", [{"chars_per_second": 1.0}, {"chars_per_second": 40.0}])
def test_a_script_of_the_wrong_length_never_reaches_azure(tmp_path, change):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client, voice=change)
    with pytest.raises(VoiceLengthError):
        engine.voice(SCRIPT, "ar")
    assert client.calls == []
    assert used(engine) == 0


@pytest.mark.parametrize("seconds", [46.0, 14.0])
def test_real_audio_of_the_wrong_length_fails_without_a_second_bill(tmp_path, seconds):
    client = FakeSpeechClient(seconds=seconds)
    engine = make_engine(tmp_path, client)
    for _ in range(2):
        with pytest.raises(VoiceLengthError):
            engine.voice(SCRIPT, "ar")
    assert len(client.calls) == 1


def test_the_bake_off_can_skip_the_length_checks(tmp_path):
    client = FakeSpeechClient(seconds=0.5)
    result = make_engine(tmp_path, client).voice("راتبك", "ar", check_length=False)
    assert [item.text for item in result.words] == ["راتبك"]


# --- Which voice ------------------------------------------------------------------------


def test_each_language_uses_its_configured_voice(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(
        tmp_path,
        client,
        voice={"arabic_voice": "ar-SA-ZariyahNeural", "english_voice": "en-US-AvaNeural"},
    )
    assert engine.voice(SCRIPT, "ar").voice == "ar-SA-ZariyahNeural"
    assert engine.voice("word " * 60, "en").voice == "en-US-AvaNeural"


def test_an_english_reel_with_no_english_voice_says_which_setting_to_fill(tmp_path):
    client = FakeSpeechClient()
    engine = make_engine(tmp_path, client)
    assert engine.settings.english_voice == ""
    with pytest.raises(VoiceConfigError, match="voice.english_voice"):
        engine.voice("word " * 60, "en")
    assert client.calls == []


def test_an_unknown_language_is_refused(tmp_path):
    client = FakeSpeechClient()
    with pytest.raises(VoiceInputError):
        make_engine(tmp_path, client).voice(SCRIPT, "fr")
    assert client.calls == []


def test_the_result_carries_aligned_words_and_the_tier(tmp_path):
    text = "قوام المال " + SCRIPT
    client = FakeSpeechClient()
    result = make_engine(tmp_path, client, azure_tier="S0").voice(text, "ar")
    assert result.words[0].text == "قوام المال"
    assert result.azure_tier == "S0"
    assert result.provider == "azure_speech"
    assert result.billable_characters > len(text)


# --- What the bake-off reads before it spends -------------------------------------------


def test_pending_characters_are_zero_once_the_file_exists(tmp_path):
    engine = make_engine(tmp_path, FakeSpeechClient())
    voice = "ar-SA-HamedNeural"
    assert engine.pending_characters(SCRIPT, "ar", voice_name=voice) == cost(engine)
    engine.voice(SCRIPT, "ar", voice_name=voice)
    assert engine.pending_characters(SCRIPT, "ar", voice_name=voice) == 0


def test_with_prosody_keeps_the_same_ledger_and_folder(tmp_path):
    engine = make_engine(tmp_path, FakeSpeechClient())
    slower = engine.with_prosody("-5%", "0%")
    assert slower.provider.rate == "-5%"
    assert slower.ledger is engine.ledger
    assert slower.cache_dir == engine.cache_dir
