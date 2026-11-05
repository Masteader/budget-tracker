"""Canned Speech SDK events and a fake client, so voice tests never touch the real SDK.

The canned objects copy the shape of `SpeechSynthesisWordBoundaryEventArgs` in the pinned SDK:
`audio_offset` in ticks, `duration` as a timedelta, and an enum-like `boundary_type`.
`test_voice_azure.py` checks those names against the installed SDK without constructing it.
"""

import io
import wave
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from enum import Enum

from content_engine.voice_providers.azure_speech import AzureSpeechProvider, SpeechOutcome
from content_engine.voiceover_engine import CharLedger, VoiceEngine
from core.config import load_config

TICKS_PER_MS = 10_000
NOVEMBER = datetime(2026, 11, 15, tzinfo=UTC)


class CannedBoundary(Enum):
    Word = 0
    Punctuation = 1
    Sentence = 2


@dataclass(frozen=True)
class CannedEvent:
    text: str
    audio_offset: int
    duration: timedelta
    boundary_type: CannedBoundary = CannedBoundary.Word
    text_offset: int = 0
    word_length: int = 0


def word(text: str, start_ms: int, length_ms: int = 100) -> CannedEvent:
    return CannedEvent(text, start_ms * TICKS_PER_MS, timedelta(milliseconds=length_ms))


def punctuation(text: str, start_ms: int) -> CannedEvent:
    return CannedEvent(
        text, start_ms * TICKS_PER_MS, timedelta(milliseconds=10), CannedBoundary.Punctuation
    )


def sentence(text: str, start_ms: int) -> CannedEvent:
    return CannedEvent(
        text, start_ms * TICKS_PER_MS, timedelta(milliseconds=500), CannedBoundary.Sentence
    )


def words_for(text: str, step_ms: int = 300) -> list[CannedEvent]:
    return [word(token, index * step_ms) for index, token in enumerate(text.split())]


def spoken_text(ssml: str) -> str:
    return "".join(ElementTree.fromstring(ssml).itertext())


def wav_bytes(seconds: float = 30.0, rate: int = 48_000) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(b"\x00\x00" * int(seconds * rate))
    return buffer.getvalue()


@dataclass
class FakeSpeechClient:
    """Plays `outcomes` in order: an exception is raised, and a `SpeechOutcome` is returned.
    With nothing queued it speaks every word in the SSML it was given."""

    outcomes: list = field(default_factory=list)
    seconds: float = 30.0
    calls: list[str] = field(default_factory=list)

    def speak_ssml(self, ssml: str) -> SpeechOutcome:
        self.calls.append(ssml)
        if self.outcomes:
            outcome = self.outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        return SpeechOutcome(wav_bytes(self.seconds), words_for(spoken_text(ssml)))


class Clock:
    def __init__(self, now=NOVEMBER):
        self.now = now

    def __call__(self):
        return self.now


def make_engine(tmp_path, client, *, clock=None, sleeps=None, voice=None, **provider_changes):
    """The real engine and provider over a fake client, with its files under `tmp_path`."""
    settings = {
        "client": client,
        "region": "uaenorth",
        "azure_tier": "F0",
        "audio_dir": tmp_path / "voiceovers",
        "rate": "0%",
        "pitch": "0%",
        "output_format": "riff-48khz-16bit-mono-pcm",
        "pronunciation": {},
    }
    return VoiceEngine(
        provider=AzureSpeechProvider(**{**settings, **provider_changes}),
        settings=load_config().voice.model_copy(update=voice or {}),
        ledger=CharLedger(tmp_path / "state" / "voice_usage.db", clock or Clock()),
        cache_dir=tmp_path / "voiceovers",
        sleep=(sleeps if sleeps is not None else []).append,
    )
