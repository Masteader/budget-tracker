"""The voice bake-off tool, with a fake client (spec Section 7.5, task E4). Azure voices only,
free tier only, and it counts what it would spend before it spends anything."""

import json
import random

import pytest
from voice_fakes import FakeSpeechClient, make_engine, spoken_text, wav_bytes, word

from content_engine import bakeoff
from content_engine.bakeoff import (
    DEFAULT_MAX_CHARS,
    DEFAULT_PROSODY,
    DEFAULT_VOICES,
    TEST_WORDS,
    BakeoffError,
    BakeoffScript,
    count_characters,
    load_scripts,
    plan_samples,
    run_bakeoff,
    timing_report,
)
from content_engine.voice_providers.azure_speech import SpeechOutcome
from content_engine.voiceover_engine import VoiceInputError, VoiceServiceError

HAMED, ZARIYAH = DEFAULT_VOICES


def script(name="hook", text="راتبك وين يروح", language="ar") -> BakeoffScript:
    return BakeoffScript(id=name, language=language, text=text)


TWO_SCRIPTS = [script("hook"), script("tier", "فاتورة ZATCA جاهزة")]
ONE_SETTING = (("0%", "0%"),)


def seeded(seed=1) -> random.Random:
    return random.Random(seed)


def plan(scripts=None, voices=DEFAULT_VOICES, prosody=DEFAULT_PROSODY, rng=None):
    return plan_samples(scripts or TWO_SCRIPTS, voices, prosody, rng or seeded())


def wavs(folder) -> list[str]:
    return sorted(path.name for path in folder.iterdir())


# --- Blind samples ----------------------------------------------------------------------


def test_every_script_meets_every_voice_and_setting():
    samples = plan()
    assert len(samples) == len(TWO_SCRIPTS) * len(DEFAULT_VOICES) * len(DEFAULT_PROSODY)
    combos = {(s.script.id, s.voice, s.rate, s.pitch) for s in samples}
    assert len(combos) == len(samples)


def test_the_defaults_are_two_voices_by_five_settings():
    """About 10 voice and prosody settings (spec Section 7.5)."""
    assert DEFAULT_VOICES == ("ar-SA-HamedNeural", "ar-SA-ZariyahNeural")
    assert len(DEFAULT_PROSODY) == 5


def test_labels_are_unique_and_give_nothing_away():
    samples = plan()
    labels = [sample.label for sample in samples]
    assert len(set(labels)) == len(labels)
    for sample in samples:
        for hint in ("hamed", "zariyah", "neural", "%", "hook", "tier", "ar-sa"):
            assert hint not in sample.label.casefold()


def test_the_order_is_shuffled_so_a_label_number_says_nothing():
    ordered = [(s.script.id, s.voice, s.rate, s.pitch) for s in plan(rng=seeded(1))]
    other = [(s.script.id, s.voice, s.rate, s.pitch) for s in plan(rng=seeded(2))]
    assert ordered != other
    assert sorted(ordered) == sorted(other)
    assert ordered != sorted(ordered)


def test_an_english_script_only_meets_a_voice_that_can_read_it():
    samples = plan_samples(
        [script("en", "hello there", "en")],
        ("ar-SA-HamedNeural", "en-US-AvaNeural", "en-US-AvaMultilingualNeural"),
        ONE_SETTING,
        seeded(),
    )
    assert {sample.voice for sample in samples} == {
        "en-US-AvaNeural",
        "en-US-AvaMultilingualNeural",
    }


def test_a_plan_with_nothing_to_voice_is_refused():
    with pytest.raises(BakeoffError):
        plan_samples([script("en", "hello there", "en")], (HAMED,), ONE_SETTING, seeded())


def test_samples_land_under_blind_names_with_a_separate_key(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client)
    samples = plan()
    summary = run_bakeoff(engine, samples, tmp_path / "run", max_chars=DEFAULT_MAX_CHARS)

    assert wavs(summary.samples_dir) == sorted(f"{s.label}.wav" for s in samples)
    assert summary.key_file.parent != summary.samples_dir
    assert not summary.key_file.is_relative_to(summary.samples_dir)
    key = json.loads(summary.key_file.read_text(encoding="utf-8"))
    assert key["samples"] == {
        s.label: {
            "script": s.script.id,
            "language": s.script.language,
            "voice": s.voice,
            "rate": s.rate,
            "pitch": s.pitch,
        }
        for s in samples
    }


def test_each_sample_really_uses_its_voice_and_setting(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    samples = plan(prosody=(("0%", "0%"), ("-5%", "+2%")))
    run_bakeoff(make_engine(tmp_path, client), samples, tmp_path / "run", max_chars=9_999)
    assert len(client.calls) == len(samples)
    for sample in samples:
        request = f'name="{sample.voice}"'
        setting = f'rate="{sample.rate}" pitch="{sample.pitch}"'
        assert any(
            request in call and setting in call and sample.script.text == spoken_text(call)
            for call in client.calls
        )


def test_a_sample_file_holds_its_own_audio(tmp_path):
    audio = wav_bytes(0.2)
    client = FakeSpeechClient([SpeechOutcome(audio, [word("راتبك", 0)])])
    samples = plan([script(text="راتبك")], voices=(HAMED,), prosody=ONE_SETTING)
    summary = run_bakeoff(
        make_engine(tmp_path, client), samples, tmp_path / "run", max_chars=9_999
    )
    assert (summary.samples_dir / f"{samples[0].label}.wav").read_bytes() == audio


# --- Counting first ---------------------------------------------------------------------


def test_characters_are_counted_before_any_call(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client)
    samples = plan()
    total = count_characters(engine, samples)
    assert total > sum(len(s.script.text) for s in samples)
    assert client.calls == []


def test_it_refuses_to_run_over_the_given_limit(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client)
    samples = plan()
    total = count_characters(engine, samples)
    with pytest.raises(BakeoffError, match=str(total)):
        run_bakeoff(engine, samples, tmp_path / "run", max_chars=total - 1)
    assert client.calls == []
    assert not (tmp_path / "run").exists()
    assert engine.ledger.used() == 0


def test_it_runs_exactly_at_the_limit(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client)
    samples = plan()
    total = count_characters(engine, samples)
    summary = run_bakeoff(engine, samples, tmp_path / "run", max_chars=total)
    assert summary.characters == total
    assert engine.ledger.used() == total


def test_it_refuses_up_front_if_the_monthly_cap_cannot_cover_the_whole_run(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    probe = make_engine(tmp_path, FakeSpeechClient())
    samples = plan()
    total = count_characters(probe, samples)
    engine = make_engine(tmp_path, client, voice={"monthly_char_cap": total - 1})
    with pytest.raises(BakeoffError, match="monthly_char_cap"):
        run_bakeoff(engine, samples, tmp_path / "run", max_chars=DEFAULT_MAX_CHARS)
    assert client.calls == []


def test_a_re_run_counts_nothing_and_bills_nothing(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client)
    samples = plan()
    run_bakeoff(engine, samples, tmp_path / "one", max_chars=DEFAULT_MAX_CHARS)
    calls, spent = len(client.calls), engine.ledger.used()

    assert count_characters(engine, samples) == 0
    again = run_bakeoff(engine, samples, tmp_path / "two", max_chars=1)
    assert again.characters == 0
    assert len(client.calls) == calls
    assert engine.ledger.used() == spent
    assert wavs(again.samples_dir) == wavs(tmp_path / "one" / "samples")


def test_the_default_limit_covers_the_planned_run(tmp_path):
    """Five scripts of about 400 characters across 10 settings is about 20,000 characters."""
    scripts = [script(f"s{n}", "ر" * 400) for n in range(5)]
    samples = plan(scripts=[*scripts, TEST_WORDS])
    total = count_characters(make_engine(tmp_path, FakeSpeechClient()), samples)
    assert 20_000 <= total <= DEFAULT_MAX_CHARS
    assert DEFAULT_MAX_CHARS <= 25_000  # 5% of the free allowance


# --- Free tier only ---------------------------------------------------------------------


def test_the_bake_off_refuses_a_paid_resource(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client, azure_tier="S0")
    with pytest.raises(BakeoffError, match="F0"):
        run_bakeoff(engine, plan(), tmp_path / "run", max_chars=DEFAULT_MAX_CHARS)
    assert client.calls == []


def test_the_timing_report_refuses_a_paid_resource(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    engine = make_engine(tmp_path, client, azure_tier="S0")
    with pytest.raises(BakeoffError, match="F0"):
        timing_report(engine, TWO_SCRIPTS, DEFAULT_VOICES, max_chars=DEFAULT_MAX_CHARS)
    assert client.calls == []


# --- Failures during a run --------------------------------------------------------------


def test_a_sample_with_bad_timing_is_still_there_to_listen_to(tmp_path):
    client = FakeSpeechClient([SpeechOutcome(wav_bytes(0.1), [word("راتبك", 0)])], seconds=0.1)
    samples = plan([script(text="راتبك وين")], voices=(HAMED,), prosody=ONE_SETTING)
    summary = run_bakeoff(
        make_engine(tmp_path, client), samples, tmp_path / "run", max_chars=9_999
    )
    assert (summary.samples_dir / f"{samples[0].label}.wav").is_file()


def test_azure_failing_stops_the_run_with_no_other_tool_tried(tmp_path):
    client = FakeSpeechClient([VoiceServiceError(401, "bad key")], seconds=0.1)
    with pytest.raises(VoiceServiceError):
        run_bakeoff(make_engine(tmp_path, client), plan(), tmp_path / "run", max_chars=9_999)
    assert len(client.calls) == 1


# --- The test words (spec Section 7.5) --------------------------------------------------


@pytest.mark.parametrize(
    "needed", ["راتب", "فاتورة", "مقاضي", "حسبتك", "ZATCA", "قوام المال", "Qawam Money"]
)
def test_the_test_words_cover_the_hard_ones(needed):
    assert needed in TEST_WORDS.text


# --- Timing report for spike S2 ---------------------------------------------------------


def test_the_report_lists_word_events_against_script_tokens(tmp_path):
    text = "مع قوام المال تخطط؟"
    engine = make_engine(tmp_path, FakeSpeechClient(seconds=0.1))
    report = timing_report(engine, [script("hook", text)], (HAMED,), max_chars=9_999)
    assert report.passed is True
    lines = report.text.splitlines()
    assert any("hook" in line and HAMED in line for line in lines)
    assert any(line.startswith("قوام المال\t2/2\t") for line in lines)
    assert any(line.startswith("تخطط؟\t1/1\t") for line in lines)
    assert any("PASS" in line for line in lines)


def test_a_word_with_no_event_fails_the_report_and_shows_the_raw_events(tmp_path):
    events = [word("راتبك", 0), word("يروح", 900)]
    client = FakeSpeechClient([SpeechOutcome(wav_bytes(0.1), events)])
    engine = make_engine(tmp_path, client)
    report = timing_report(engine, [script("hook", "راتبك وين يروح")], (HAMED,), max_chars=9_999)
    assert report.passed is False
    assert "FAIL" in report.text
    assert "وين" in report.text
    assert "راتبك\t0-100" in report.text
    assert "يروح\t900-1000" in report.text


def test_a_word_split_across_two_events_is_flagged_for_a_person_to_check(tmp_path):
    events = [word("دفعت", 0), word("1", 300), word("250", 600)]
    client = FakeSpeechClient([SpeechOutcome(wav_bytes(0.1), events)])
    engine = make_engine(tmp_path, client)
    report = timing_report(engine, [script("hook", "دفعت 1,250")], (HAMED,), max_chars=9_999)
    assert report.passed is False
    assert "CHECK" in report.text
    assert "1,250\t2/1\t" in report.text


def test_the_report_covers_both_voices_on_three_arabic_scripts_at_most(tmp_path):
    scripts = [script(f"s{n}", f"راتب{n}") for n in range(5)]
    scripts.append(script("english", "hello there", "en"))
    client = FakeSpeechClient(seconds=0.1)
    report = timing_report(
        make_engine(tmp_path, client), scripts, DEFAULT_VOICES, max_chars=9_999
    )
    assert len(client.calls) == 3 * 2
    assert "s2" in report.text
    assert "s3" not in report.text
    assert "english" not in report.text


def test_the_report_counts_before_it_spends(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    with pytest.raises(BakeoffError):
        timing_report(make_engine(tmp_path, client), TWO_SCRIPTS, DEFAULT_VOICES, max_chars=1)
    assert client.calls == []


def test_the_report_needs_an_arabic_script(tmp_path):
    with pytest.raises(BakeoffError, match="Arabic"):
        timing_report(
            make_engine(tmp_path, FakeSpeechClient()),
            [script("en", "hello", "en")],
            DEFAULT_VOICES,
            max_chars=9_999,
        )


def test_the_report_skips_a_voice_that_cannot_read_arabic(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    timing_report(
        make_engine(tmp_path, client),
        [script("hook")],
        (HAMED, "en-US-AvaNeural"),
        max_chars=9_999,
    )
    assert len(client.calls) == 1


# --- Script files -----------------------------------------------------------------------


def write_scripts(path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def test_scripts_load_from_a_json_file(tmp_path):
    path = tmp_path / "scripts.json"
    write_scripts(path, [{"id": "hook", "language": "ar", "text": "راتبك وين يروح"}])
    assert load_scripts(path) == [script("hook")]


@pytest.mark.parametrize(
    "content",
    [
        "not json",
        "{}",
        "[]",
        '[{"id": "a", "language": "ar"}]',
        '[{"id": "a", "language": "fr", "text": "x"}]',
        '[{"id": "a", "language": "ar", "text": "x", "surprise": 1}]',
        '[{"id": "a", "language": "ar", "text": "   "}]',
        '[{"id": "a", "language": "ar", "text": "a\\u202eb"}]',
        '[{"id": "a", "language": "ar", "text": "IBAN SA0380000000608010167519"}]',
    ],
)
def test_a_bad_scripts_file_is_refused(tmp_path, content):
    path = tmp_path / "scripts.json"
    path.write_text(content, encoding="utf-8")
    with pytest.raises(BakeoffError):
        load_scripts(path)


def test_a_missing_scripts_file_says_where_it_should_be(tmp_path):
    path = tmp_path / "scripts.json"
    with pytest.raises(BakeoffError, match="scripts.json"):
        load_scripts(path)


def test_an_unfilled_brand_token_is_refused_before_any_call(tmp_path):
    client = FakeSpeechClient(seconds=0.1)
    samples = plan([script(text="مع {brand_ar} اليوم")])
    with pytest.raises(VoiceInputError, match="token"):
        run_bakeoff(make_engine(tmp_path, client), samples, tmp_path / "run", max_chars=9_999)
    assert client.calls == []


# --- The command line -------------------------------------------------------------------


@pytest.fixture
def data_root(tmp_path):
    """Where the shipped config's %LOCALAPPDATA% path points during tests (see conftest.py)."""
    return tmp_path / "localappdata" / "SocialEngine"


@pytest.fixture
def client():
    return FakeSpeechClient(seconds=0.1)


@pytest.fixture
def factory(tmp_path, client):
    return lambda _config, _paths: make_engine(tmp_path / "engine", client)


def scripts_ready(data_root) -> None:
    write_scripts(
        data_root / "bakeoff" / "scripts.json",
        [{"id": "hook", "language": "ar", "text": "راتبك وين يروح"}],
    )


def test_the_command_runs_with_no_arguments_like_the_plan(data_root, client, factory, capsys):
    scripts_ready(data_root)
    assert bakeoff.main([], engine_factory=factory) == 0
    # One script plus the test words, for 2 voices and 5 settings.
    assert len(client.calls) == 2 * 2 * 5
    runs = list((data_root / "bakeoff").glob("run-*"))
    assert len(runs) == 1
    assert (runs[0] / "key.json").is_file()
    assert len(list((runs[0] / "samples").iterdir())) == 20
    assert "characters" in capsys.readouterr().out


def test_count_only_makes_no_call(data_root, client, factory, capsys):
    scripts_ready(data_root)
    assert bakeoff.main(["--count-only"], engine_factory=factory) == 0
    assert client.calls == []
    assert not list((data_root / "bakeoff").glob("run-*"))
    assert "characters" in capsys.readouterr().out


def test_the_limit_comes_from_the_command_line(data_root, client, factory, capsys):
    scripts_ready(data_root)
    assert bakeoff.main(["--max-chars", "10"], engine_factory=factory) == 2
    assert client.calls == []
    assert "10" in capsys.readouterr().err


def test_voices_come_from_the_command_line(data_root, client, factory):
    scripts_ready(data_root)
    voice = "ar-AE-FatimaNeural"
    assert bakeoff.main(["--voices", voice], engine_factory=factory) == 0
    assert all(voice in call for call in client.calls)


@pytest.mark.parametrize("voice", ['ar-SA-HamedNeural"><x', "ar-SA-Hamed", ""])
def test_a_bad_voice_is_refused_before_any_call(data_root, client, factory, voice):
    scripts_ready(data_root)
    assert bakeoff.main(["--voices", voice], engine_factory=factory) == 2
    assert client.calls == []


@pytest.mark.parametrize("prosody", ['0%"><x:0%', "0%", "fast:loud"])
def test_a_bad_setting_is_refused_before_any_call(data_root, client, factory, prosody):
    scripts_ready(data_root)
    assert bakeoff.main([f"--prosody={prosody}"], engine_factory=factory) == 2
    assert client.calls == []


def test_settings_come_from_the_command_line(data_root, client, factory):
    scripts_ready(data_root)
    assert bakeoff.main(["--prosody=-10%:+2%"], engine_factory=factory) == 0
    assert all('rate="-10%" pitch="+2%"' in call for call in client.calls)


def test_the_setting_flag_can_repeat(data_root, client, factory):
    scripts_ready(data_root)
    args = ["--prosody=-10%:0%", "--prosody=+10%:0%", "--voices", HAMED]
    assert bakeoff.main(args, engine_factory=factory) == 0
    assert len(client.calls) == 2 * 2  # one script plus the test words, for two settings


def test_the_timing_report_command_writes_a_file(data_root, client, factory, capsys):
    scripts_ready(data_root)
    assert bakeoff.main(["--timing-report"], engine_factory=factory) == 0
    assert len(client.calls) == 2
    reports = list((data_root / "bakeoff").glob("timing-report-*.txt"))
    assert len(reports) == 1
    assert "راتبك" in reports[0].read_text(encoding="utf-8")
    assert "PASS" in capsys.readouterr().out


def test_a_missing_scripts_file_stops_the_command(data_root, client, factory, capsys):
    assert bakeoff.main([], engine_factory=factory) == 2
    assert client.calls == []
    assert "scripts.json" in capsys.readouterr().err


def test_a_scripts_path_can_be_given(tmp_path, client, factory):
    path = tmp_path / "mine.json"
    write_scripts(path, [{"id": "mine", "language": "ar", "text": "راتبك"}])
    assert bakeoff.main([f"--scripts={path}", "--count-only"], engine_factory=factory) == 0


def test_with_no_env_file_the_real_factory_names_the_variable_and_loads_nothing(data_root, capsys):
    scripts_ready(data_root)
    assert bakeoff.main([]) == 2
    assert "AZURE_SPEECH_KEY" in capsys.readouterr().err


def test_a_forbidden_variable_stops_the_command(data_root, client, factory, monkeypatch, capsys):
    scripts_ready(data_root)
    monkeypatch.setenv("SUPA" + "BASE_URL", "x")
    assert bakeoff.main([], engine_factory=factory) == 2
    assert client.calls == []
