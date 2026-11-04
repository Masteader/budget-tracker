"""The voice bake-off and the timing report for spike S2 (spec Sections 7.4 and 7.5).

Azure voices only, on the free tier. Listeners get blind-labelled samples, and the key sits in
a separate file. Characters are counted before the first call, and a run that would pass the
given limit or the monthly cap never starts. Real use is plan step LIVE-1, on the owner's go-ahead:

    python -m content_engine.bakeoff --count-only
    python -m content_engine.bakeoff --timing-report
    python -m content_engine.bakeoff

Scripts come from `<data_root>/bakeoff/scripts.json`: a list of `{id, language, text}`, with any
brand token already filled in.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import sys
import uuid
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated

from pydantic import BaseModel, ConfigDict, TypeAdapter, ValidationError

from content_engine.voiceover_engine import (
    VoiceEngine,
    VoiceError,
    VoiceResult,
    VoiceTimingError,
    build_voice_engine,
)
from core.config import ConfigError, EngineConfig, Voice, load_config
from core.paths import EnginePaths, PathConfigError, resolve_data_root
from core.render_props import ReelLanguage
from core.safe_text import bounded_text, display_text
from core.secrets import ForbiddenEnvironment, check_startup_environment

DEFAULT_VOICES = ("ar-SA-HamedNeural", "ar-SA-ZariyahNeural")
DEFAULT_PROSODY = (("0%", "0%"), ("-5%", "0%"), ("+5%", "0%"), ("0%", "-5%"), ("0%", "+5%"))
DEFAULT_MAX_CHARS = 25_000  # the planned 20,000, plus markup and the test words
TIMING_REPORT_SCRIPTS = 3  # spike S2 uses 3 full scripts

_ONLY_TIER = "F0"
_MULTILINGUAL = "Multilingual"


class BakeoffError(RuntimeError):
    """The bake-off will not run. Nothing was sent."""


class BakeoffScript(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    id: Annotated[str, bounded_text(64)]
    language: ReelLanguage
    text: Annotated[str, display_text(2000)]


TEST_WORDS = BakeoffScript(
    id="test_words",
    language="ar",
    text=(
        "راتب. فاتورة. مقاضي. حسبتك. ZATCA. "
        "ألف ومئتين وخمسين ريال. قوام المال. Qawam Money."
    ),
)


@dataclass(frozen=True)
class Sample:
    label: str
    script: BakeoffScript
    voice: str
    rate: str
    pitch: str


@dataclass(frozen=True)
class BakeoffSummary:
    samples_dir: Path
    key_file: Path
    characters: int


@dataclass(frozen=True)
class TimingReport:
    text: str
    passed: bool


def load_scripts(path: Path) -> list[BakeoffScript]:
    try:
        raw = Path(path).read_bytes()
    except OSError as error:
        raise BakeoffError(f"Cannot read the bake-off scripts in {path}: {error}") from error
    try:
        scripts = TypeAdapter(list[BakeoffScript]).validate_json(raw)
    except ValidationError as error:
        raise BakeoffError(f"The bake-off scripts in {path} are not valid: {error}") from error
    if not scripts:
        raise BakeoffError(f"{path} holds no scripts")
    return scripts


def _can_read(voice: str, language: str) -> bool:
    return voice.startswith(f"{language}-") or _MULTILINGUAL in voice


def plan_samples(
    scripts: Sequence[BakeoffScript],
    voices: Sequence[str],
    prosody: Sequence[tuple[str, str]],
    rng: random.Random | None = None,
) -> list[Sample]:
    """Every script with every voice that can read it and every setting. Labels are given out
    after a shuffle, so a label's number says nothing about what it holds."""
    combos = [
        (script, voice, rate, pitch)
        for script in scripts
        for voice in voices
        if _can_read(voice, script.language)
        for rate, pitch in prosody
    ]
    if not combos:
        raise BakeoffError("None of the voices can read any of the scripts")
    (rng or random.SystemRandom()).shuffle(combos)
    return [
        Sample(f"sample_{number:03d}", script, voice, rate, pitch)
        for number, (script, voice, rate, pitch) in enumerate(combos, start=1)
    ]


def _sample_engine(engine: VoiceEngine, sample: Sample) -> VoiceEngine:
    return engine.with_prosody(sample.rate, sample.pitch)


def count_characters(engine: VoiceEngine, samples: Sequence[Sample]) -> int:
    """What this run would add to the bill. Samples whose file already exists cost nothing."""
    return sum(
        _sample_engine(engine, sample).pending_characters(
            sample.script.text, sample.script.language, voice_name=sample.voice
        )
        for sample in samples
    )


def _check_spend(engine: VoiceEngine, characters: int, max_chars: int) -> None:
    if engine.provider.azure_tier != _ONLY_TIER:
        raise BakeoffError(f"The bake-off runs on the free tier only: {_ONLY_TIER} (decision D19)")
    if characters > max_chars:
        raise BakeoffError(f"This run needs {characters} characters, over the limit of {max_chars}")
    cap = engine.settings.monthly_char_cap
    used = engine.ledger.used()
    if used + characters > cap:
        raise BakeoffError(
            f"This run needs {characters} characters, with {used} used this month, "
            f"and voice.monthly_char_cap is {cap}"
        )


def _key_document(samples: Sequence[Sample]) -> str:
    entries = {
        sample.label: {
            "script": sample.script.id,
            "language": sample.script.language,
            "voice": sample.voice,
            "rate": sample.rate,
            "pitch": sample.pitch,
        }
        for sample in samples
    }
    return json.dumps({"samples": entries}, ensure_ascii=False, indent=2)


def _voiced(engine: VoiceEngine, text: str, language: str, voice: str) -> tuple[VoiceResult, str]:
    """The audio, plus the timing failure if there was one. Bad timing does not stop a listener
    from scoring the voice, so the audio is still used."""
    try:
        return engine.voice(text, language, voice_name=voice, check_length=False), ""
    except VoiceTimingError as error:
        if error.result is None:
            raise
        return error.result, str(error)


def run_bakeoff(
    engine: VoiceEngine, samples: Sequence[Sample], run_dir: Path, *, max_chars: int
) -> BakeoffSummary:
    characters = count_characters(engine, samples)
    _check_spend(engine, characters, max_chars)
    samples_dir = run_dir / "samples"
    samples_dir.mkdir(parents=True)
    key_file = run_dir / "key.json"
    key_file.write_text(_key_document(samples), encoding="utf-8")
    for sample in samples:
        result, _ = _voiced(
            _sample_engine(engine, sample),
            sample.script.text,
            sample.script.language,
            sample.voice,
        )
        shutil.copyfile(result.audio_path, samples_dir / f"{sample.label}.wav")
    return BakeoffSummary(samples_dir, key_file, characters)


def _timing_lines(engine: VoiceEngine, script: BakeoffScript, voice: str) -> tuple[list[str], bool]:
    result, failure = _voiced(engine, script.text, script.language, voice)
    lines = [f"script {script.id} voice {voice}"]
    if failure:
        lines.append(f"FAIL: {failure}")
        lines.append("raw word events:")
        lines += [f"{w.text}\t{w.start_ms}-{w.end_ms}" for w in result.raw_words]
        return lines, False
    all_single = True
    for match in engine.provider.match_tokens(script.text, result.raw_words):
        events = len(match.events)
        all_single = all_single and events == match.word_count
        start = match.events[0].start_ms
        end = max(event.end_ms for event in match.events)
        lines.append(f"{match.text}\t{events}/{match.word_count}\t{start}-{end}")
    if all_single:
        lines.append("PASS: every word has one event, in order")
    else:
        lines.append("CHECK: some words do not have exactly one event (events/words above)")
    return lines, all_single


def timing_report(
    engine: VoiceEngine,
    scripts: Sequence[BakeoffScript],
    voices: Sequence[str],
    *,
    max_chars: int,
) -> TimingReport:
    """Word events against script tokens for spike S2. Judging sync by eye and ear stays with
    the owner (spec Section 7.4)."""
    arabic = [script for script in scripts if script.language == "ar"][:TIMING_REPORT_SCRIPTS]
    readers = [voice for voice in voices if _can_read(voice, "ar")]
    if not arabic or not readers:
        raise BakeoffError("The timing report needs an Arabic script and a voice that reads it")
    characters = sum(
        engine.pending_characters(script.text, script.language, voice_name=voice)
        for script in arabic
        for voice in readers
    )
    _check_spend(engine, characters, max_chars)
    lines: list[str] = []
    passed = True
    for script in arabic:
        for voice in readers:
            section, section_passed = _timing_lines(engine, script, voice)
            lines += [*section, ""]
            passed = passed and section_passed
    return TimingReport("\n".join(lines), passed)


def _checked_settings(
    settings: Voice, voices: Sequence[str], prosody: Sequence[tuple[str, str]]
) -> None:
    """The config's own rules, so a bad value stops here rather than at Azure."""
    base = settings.model_dump()
    try:
        for voice in voices:
            field = "english_voice" if voice.startswith("en-") else "arabic_voice"
            Voice.model_validate({**base, field: voice})
        for rate, pitch in prosody:
            Voice.model_validate({**base, "rate": rate, "pitch": pitch})
    except ValidationError as error:
        problems = "; ".join(item["msg"] for item in error.errors())
        raise BakeoffError(f"Bad bake-off setting: {problems}") from error


def _prosody_setting(value: str) -> tuple[str, str]:
    rate, separator, pitch = value.partition(":")
    if not separator:
        raise BakeoffError(f"A prosody setting looks like -5%:0%, got {value!r}")
    return rate, pitch


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m content_engine.bakeoff")
    parser.add_argument("--scripts", type=Path, help="default: <data_root>/bakeoff/scripts.json")
    parser.add_argument("--voices", nargs="+", default=list(DEFAULT_VOICES))
    parser.add_argument(
        "--prosody", action="append", metavar="RATE:PITCH", help="repeatable: --prosody=-5%%:0%%"
    )
    parser.add_argument("--max-chars", type=int, default=DEFAULT_MAX_CHARS)
    parser.add_argument("--timing-report", action="store_true", help="the report for spike S2")
    parser.add_argument("--count-only", action="store_true", help="count, make no call")
    return parser


def _stamp() -> str:
    return f"{datetime.now(UTC):%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}"


def _run(
    args: argparse.Namespace,
    engine_factory: Callable[[EngineConfig, EnginePaths], VoiceEngine],
    rng: random.Random | None,
) -> None:
    check_startup_environment()
    config = load_config()
    data_root = resolve_data_root(config.paths.data_root)
    bakeoff_root = data_root / "bakeoff"
    prosody = (
        [_prosody_setting(value) for value in args.prosody] if args.prosody else DEFAULT_PROSODY
    )
    _checked_settings(config.voice, args.voices, prosody)
    scripts = load_scripts(args.scripts or bakeoff_root / "scripts.json")
    engine = engine_factory(config, EnginePaths.from_root(data_root))

    if args.timing_report:
        report = timing_report(engine, scripts, args.voices, max_chars=args.max_chars)
        bakeoff_root.mkdir(parents=True, exist_ok=True)
        path = bakeoff_root / f"timing-report-{_stamp()}.txt"
        path.write_text(report.text, encoding="utf-8")
        print(f"{'PASS' if report.passed else 'CHECK OR FAIL'}: timing report in {path}")
        return

    samples = plan_samples([*scripts, TEST_WORDS], args.voices, prosody, rng)
    if args.count_only:
        print(f"{count_characters(engine, samples)} characters for {len(samples)} samples")
        return
    summary = run_bakeoff(
        engine, samples, bakeoff_root / f"run-{_stamp()}", max_chars=args.max_chars
    )
    print(f"{summary.characters} characters for {len(samples)} samples")
    print(f"For listeners: {summary.samples_dir}")
    print(f"Key, not for listeners: {summary.key_file}")


def main(
    argv: Sequence[str] | None = None,
    *,
    engine_factory: Callable[[EngineConfig, EnginePaths], VoiceEngine] = build_voice_engine,
    rng: random.Random | None = None,
) -> int:
    args = _parser().parse_args(argv)
    try:
        _run(args, engine_factory, rng)
    except (BakeoffError, VoiceError, ConfigError, PathConfigError, ForbiddenEnvironment) as error:
        print(f"bakeoff: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
