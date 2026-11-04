"""The voice step behind one small provider interface (spec Section 7.1).

Phase 1 ships exactly one provider, Azure Speech (D8). There is no fallback: if Azure is down,
the voice step fails, and a later tick tries Azure again. This file holds what keeps the step
from spending or re-billing: the monthly character cap, audio files keyed by a hash, retries
on 429 and server errors only, and the length checks.
"""

from __future__ import annotations

import hashlib
import os
import re
import sqlite3
import time
import uuid
import wave
from collections.abc import Callable
from contextlib import closing
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any, Protocol

from pydantic import BaseModel, ConfigDict, ValidationError

from content_engine.aligner import TimedWord, TokenMatch, timed_tokens
from core.brand_gate import FULL_NAME_AR, FULL_NAME_EN
from core.secrets import load_env_file

if TYPE_CHECKING:
    from core.config import EngineConfig, Voice
    from core.paths import EnginePaths

ONLY_PROVIDER = "azure_speech"

MAX_TRIES = 3  # as Microsoft advises for 429s (spec Section 3.5)
_RETRY_DELAYS_SECONDS = (5.0, 20.0)  # F0 allows 20 requests per 60 seconds

MIN_SPEECH_SECONDS = 15  # "Keep reels 15-45 s" (spec Section 10.4)
MAX_SPEECH_SECONDS = 45

_AUDIO_RATE_HZ = 48_000
_USAGE_FILE_NAME = "voice_usage.db"
_AZURE_REGION = re.compile(r"[a-z][a-z0-9]*")
_APPROVABLE_WITHOUT_OPT_IN = "S0"
_NEEDS_OPT_IN = "F0"


class VoiceError(RuntimeError):
    """The voice step cannot finish. The message says why and holds no secret."""


class VoiceConfigError(VoiceError):
    """A setting is missing or unusable. The owner has to change it."""


class VoiceInputError(VoiceError):
    """The script cannot be sent as it stands. Nothing was sent or billed."""


class VoiceCapReached(VoiceError):
    """`voice.monthly_char_cap` would be passed, so the call was not made."""


class VoiceUsageError(VoiceError):
    """The usage record cannot be read. Without it the cap cannot hold, so nothing is sent."""


class VoiceLengthError(VoiceError):
    """The script or its audio is too long or too short for a reel."""


class VoiceServiceError(VoiceError):
    """Azure failed the request. `status` is an HTTP-style code, or None when unclear."""

    def __init__(self, status: int | None, message: str) -> None:
        super().__init__(message)
        self.status = status

    @property
    def retryable(self) -> bool:
        return self.status is not None and (self.status == 429 or 500 <= self.status < 600)

    @property
    def definitely_refused(self) -> bool:
        """Azure said no, so nothing was synthesized and nothing is billed. A server error
        or a lost connection leaves that unclear, so those stay charged."""
        return self.status is not None and 400 <= self.status < 500


class VoiceTimingError(VoiceError):
    """Word timing does not cover the script. `result` holds the audio that was paid for."""

    def __init__(self, message: str, *, result: VoiceResult | None = None) -> None:
        super().__init__(message)
        self.result = result


@dataclass(frozen=True)
class VoiceResult:
    audio_path: Path  # 48 kHz
    words: list[TimedWord]  # aligned to the script
    provider: str
    voice: str
    azure_tier: str  # F0 or S0, recorded with the reel
    billable_characters: int
    raw_words: list[TimedWord] = field(default_factory=list)  # as Azure reported them
    cached: bool = False


class VoiceProvider(Protocol):
    name: str
    azure_tier: str

    def synthesize(self, text: str, voice: str, language: str) -> VoiceResult: ...

    def billable_characters(self, text: str, voice: str, language: str) -> int: ...

    def fingerprint(self, text: str, voice: str, language: str) -> str: ...

    def match_tokens(self, text: str, raw_words: list[TimedWord]) -> list[TokenMatch]: ...

    def with_prosody(self, rate: str, pitch: str) -> VoiceProvider: ...


def reel_voice_may_be_approved(voice: Voice, azure_tier: Any) -> bool:
    """Spec Section 3.3 invariant 6. Pass the tier recorded with the reel, not the configured
    one: switching the config to S0 must not clear audio that was voiced on F0. The bot and the
    callback handler call this, and a tier it does not know is refused."""
    if azure_tier == _APPROVABLE_WITHOUT_OPT_IN:
        return True
    return azure_tier == _NEEDS_OPT_IN and voice.allow_public_on_f0


def check_script_length(text: str, chars_per_second: float) -> float:
    """The estimated seconds of speech, or a refusal before anything is sent (spec Section 6.2)."""
    seconds = len(" ".join(text.split())) / chars_per_second
    _check_seconds(seconds, "script", "at the configured voice.chars_per_second")
    return seconds


def _check_seconds(seconds: float, what: str, how: str) -> None:
    if not MIN_SPEECH_SECONDS <= seconds <= MAX_SPEECH_SECONDS:
        raise VoiceLengthError(
            f"The {what} runs {seconds:.1f} s {how}, and a reel keeps to "
            f"{MIN_SPEECH_SECONDS}-{MAX_SPEECH_SECONDS} s"
        )


class CharLedger:
    """Characters sent to Azure per calendar month, in a small SQLite file of its own, which
    keeps the cap correct when a tick and the bake-off run at once. A charge is committed
    before the call, so a crash during the call cannot lose it. Months are UTC: Microsoft does
    not say which clock resets the allowance, and the cap sits 100,000 below it."""

    def __init__(self, path: Path, clock: Callable[[], datetime] | None = None) -> None:
        self._path = Path(path)
        self._clock = clock or (lambda: datetime.now(UTC))

    def _month(self) -> str:
        return self._clock().astimezone(UTC).strftime("%Y-%m")

    def _connect(self) -> sqlite3.Connection:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        return sqlite3.connect(self._path, timeout=30, isolation_level=None)

    @staticmethod
    def _used(connection: sqlite3.Connection, month: str) -> int:
        connection.execute(
            "CREATE TABLE IF NOT EXISTS usage ("
            "id INTEGER PRIMARY KEY, month TEXT NOT NULL, characters INTEGER NOT NULL)"
        )
        row = connection.execute(
            "SELECT COALESCE(SUM(characters), 0) FROM usage WHERE month = ?", (month,)
        ).fetchone()
        return row[0]

    def used(self) -> int:
        try:
            with closing(self._connect()) as connection:
                return self._used(connection, self._month())
        except sqlite3.Error as error:
            raise VoiceUsageError(f"Cannot read voice usage in {self._path}: {error}") from error

    def reserve(self, characters: int, cap: int) -> int:
        """Charges the characters and returns a handle, or refuses if the cap would be passed."""
        if characters <= 0:
            raise ValueError("a reservation must be for at least one character")
        month = self._month()
        try:
            with closing(self._connect()) as connection:
                connection.execute("BEGIN IMMEDIATE")
                used = self._used(connection, month)
                if used + characters > cap:
                    connection.execute("ROLLBACK")
                    raise VoiceCapReached(
                        f"voice.monthly_char_cap is {cap}: {used} characters used in {month}, "
                        f"and this needs {characters} more"
                    )
                row = connection.execute(
                    "INSERT INTO usage (month, characters) VALUES (?, ?)", (month, characters)
                )
                connection.execute("COMMIT")
                return row.lastrowid
        except sqlite3.Error as error:
            raise VoiceUsageError(f"Cannot record voice usage in {self._path}: {error}") from error

    def release(self, handle: int) -> None:
        try:
            with closing(self._connect()) as connection:
                connection.execute("UPDATE usage SET characters = 0 WHERE id = ?", (handle,))
        except sqlite3.Error as error:
            raise VoiceUsageError(f"Cannot record voice usage in {self._path}: {error}") from error


class _CachedWord(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    text: str
    start_ms: int
    end_ms: int


class _CacheEntry(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    key: str
    provider: str
    voice: str
    azure_tier: str
    billable_characters: int
    audio_sha256: str
    raw_words: list[_CachedWord]


def _sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _audio_length_ms(path: Path) -> int | None:
    """None unless this is a non-empty 48 kHz WAV file, which is what voice.output_format asks.
    Whether the SDK's `audio_data` carries a full RIFF header is first seen in LIVE-1 [verify]:
    if it does not, this refuses loudly rather than passing bad audio on."""
    try:
        with wave.open(str(path), "rb") as audio:
            if audio.getframerate() != _AUDIO_RATE_HZ or audio.getnframes() == 0:
                return None
            return round(audio.getnframes() * 1000 / _AUDIO_RATE_HZ)
    except (wave.Error, EOFError, OSError):
        return None


@dataclass(frozen=True)
class VoiceEngine:
    """The voice step: cached audio first, then the cap, then the one provider."""

    provider: VoiceProvider
    settings: Voice
    ledger: CharLedger
    cache_dir: Path
    sleep: Callable[[float], None] = time.sleep

    def _voice_for(self, language: str) -> str:
        setting = {"ar": "arabic_voice", "en": "english_voice"}.get(language)
        if setting is None:
            raise VoiceInputError(f"unknown reel language: {language!r}")
        voice = getattr(self.settings, setting)
        if not voice:
            raise VoiceConfigError(f"voice.{setting} is not set")
        return voice

    def _audio_file(self, key: str) -> Path:
        return self.cache_dir / f"{key}.wav"

    def _entry_file(self, key: str) -> Path:
        return self.cache_dir / f"{key}.json"

    def _load(self, key: str, voice: str) -> VoiceResult | None:
        """A damaged or edited entry is a miss, so a forged tier cannot be read back."""
        audio_path = self._audio_file(key)
        try:
            entry = _CacheEntry.model_validate_json(self._entry_file(key).read_bytes())
            matches = (
                entry.key == key
                and entry.provider == self.provider.name
                and entry.voice == voice
                and entry.azure_tier == self.provider.azure_tier
                and entry.audio_sha256 == _sha256_of(audio_path)
                and _audio_length_ms(audio_path) is not None
            )
        except (OSError, ValidationError):
            return None
        if not matches:
            return None
        return VoiceResult(
            audio_path=audio_path,
            words=[],
            provider=entry.provider,
            voice=entry.voice,
            azure_tier=entry.azure_tier,
            billable_characters=entry.billable_characters,
            raw_words=[TimedWord(w.text, w.start_ms, w.end_ms) for w in entry.raw_words],
            cached=True,
        )

    def _store(self, key: str, result: VoiceResult) -> VoiceResult:
        """Audio first, then the entry that vouches for it, each moved into place whole."""
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        entry = _CacheEntry(
            key=key,
            provider=result.provider,
            voice=result.voice,
            azure_tier=result.azure_tier,
            billable_characters=result.billable_characters,
            audio_sha256=_sha256_of(result.audio_path),
            raw_words=[
                _CachedWord(text=w.text, start_ms=w.start_ms, end_ms=w.end_ms)
                for w in result.raw_words
            ],
        )
        audio_path = self._audio_file(key)
        os.replace(result.audio_path, audio_path)
        incoming = self.cache_dir / f".incoming-{uuid.uuid4().hex}.json"
        incoming.write_text(entry.model_dump_json(), encoding="utf-8")
        os.replace(incoming, self._entry_file(key))
        return replace(result, audio_path=audio_path)

    def _synthesize(self, text: str, voice: str, language: str) -> VoiceResult:
        """Each try is charged first, so the cap stops a retry as well as a first call."""
        characters = self.provider.billable_characters(text, voice, language)
        for attempt in range(1, MAX_TRIES + 1):
            held = self.ledger.reserve(characters, self.settings.monthly_char_cap)
            try:
                return self.provider.synthesize(text, voice, language)
            except VoiceTimingError as error:
                if error.result is None:
                    raise
                return error.result  # billed and kept, so a re-run costs nothing
            except VoiceServiceError as error:
                if error.definitely_refused:
                    self.ledger.release(held)
                if not error.retryable:
                    raise
                if attempt == MAX_TRIES:
                    raise VoiceServiceError(
                        error.status, f"{error} (gave up after {MAX_TRIES} tries)"
                    ) from error
                self.sleep(_RETRY_DELAYS_SECONDS[attempt - 1])
        raise AssertionError("the loop always returns or raises")

    def _finish(self, stored: VoiceResult, text: str, *, check_length: bool) -> VoiceResult:
        try:
            words = timed_tokens(self.provider.match_tokens(text, stored.raw_words))
        except VoiceTimingError as error:
            raise VoiceTimingError(str(error), result=stored) from error
        if check_length:
            length_ms = _audio_length_ms(stored.audio_path) or 0
            _check_seconds(length_ms / 1000, "audio", "as spoken")
        return replace(stored, words=words)

    def voice(
        self,
        text: str,
        language: str,
        *,
        voice_name: str | None = None,
        check_length: bool = True,
    ) -> VoiceResult:
        """The audio and caption words for this text, from the file if it already exists."""
        voice = voice_name or self._voice_for(language)
        if check_length:
            check_script_length(text, self.settings.chars_per_second)
        key = self.provider.fingerprint(text, voice, language)
        stored = self._load(key, voice)
        if stored is None:
            fresh = self._synthesize(text, voice, language)
            if _audio_length_ms(fresh.audio_path) is None:
                fresh.audio_path.unlink(missing_ok=True)
                raise VoiceServiceError(None, "Azure Speech did not return 48 kHz WAV audio")
            stored = replace(self._store(key, fresh), cached=False)
        return self._finish(stored, text, check_length=check_length)

    def pending_characters(
        self, text: str, language: str, *, voice_name: str | None = None
    ) -> int:
        """What this text would add to the bill: nothing if its file already exists."""
        voice = voice_name or self._voice_for(language)
        if self._load(self.provider.fingerprint(text, voice, language), voice) is not None:
            return 0
        return self.provider.billable_characters(text, voice, language)

    def with_prosody(self, rate: str, pitch: str) -> VoiceEngine:
        return replace(self, provider=self.provider.with_prosody(rate, pitch))


def _azure_setting(env: dict[str, str], name: str, paths: EnginePaths) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise VoiceConfigError(f"{name} is not set in {paths.env_file}")
    return value


def build_voice_engine(
    config: EngineConfig,
    paths: EnginePaths,
    *,
    sdk_loader: Callable[[], Any] | None = None,
) -> VoiceEngine:
    """Reads the key and region from `<data_root>/.env`, as values and never into the process
    environment. Makes no call and does not load the SDK."""
    from content_engine.voice_providers.azure_speech import AzureSpeechProvider, SdkSpeechClient

    settings = config.voice
    if settings.provider != ONLY_PROVIDER:
        raise VoiceConfigError(f"{ONLY_PROVIDER} is the only voice provider (decision D8)")
    env = load_env_file(paths.data_root)
    key = _azure_setting(env, "AZURE_SPEECH_KEY", paths)
    region = _azure_setting(env, "AZURE_SPEECH_REGION", paths)
    if not _AZURE_REGION.fullmatch(region):
        raise VoiceConfigError("AZURE_SPEECH_REGION must look like uaenorth")
    provider = AzureSpeechProvider(
        client=SdkSpeechClient(key, region, settings.output_format, sdk_loader=sdk_loader),
        region=region,
        azure_tier=settings.azure_tier,
        audio_dir=paths.voiceovers,
        rate=settings.rate,
        pitch=settings.pitch,
        output_format=settings.output_format,
        pronunciation=settings.pronunciation,
        caption_phrases=(
            FULL_NAME_AR,
            FULL_NAME_EN,
            config.test_brand.name_ar,
            config.test_brand.name_en,
        ),
    )
    return VoiceEngine(
        provider=provider,
        settings=settings,
        ledger=CharLedger(paths.state_db.parent / _USAGE_FILE_NAME),
        cache_dir=paths.voiceovers,
    )
