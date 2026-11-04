"""Azure Speech, the only voice provider (decision D8, spec Section 7).

The SDK sits behind the `SpeechClient` seam and loads only when a real call is made, so tests
never construct it. Every value that goes into SSML is escaped here: script text, voice,
prosody and each `voice.pronunciation` key and value.
"""

from __future__ import annotations

import hashlib
import importlib
import json
import re
import uuid
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, replace
from datetime import timedelta
from pathlib import Path
from typing import Any, ClassVar, Protocol
from xml.sax.saxutils import escape

from content_engine.aligner import (
    BRAND_PHRASES,
    AlignmentError,
    TimedWord,
    TokenMatch,
    match_tokens,
    timed_tokens,
    whole_word_pattern,
)
from content_engine.voiceover_engine import (
    VoiceConfigError,
    VoiceInputError,
    VoiceResult,
    VoiceServiceError,
    VoiceTimingError,
)

_SDK_MODULE = "azure.cognitiveservices.speech"
_TICKS_PER_MS = 10_000
_MAX_ERROR_DETAIL_CHARS = 300
_WAV_SUFFIX = ".wav"

_LOCALE_FOR_LANGUAGE = {"ar": "ar-SA", "en": "en-US"}
_SDK_FORMAT_FOR_CONFIG = {"riff-48khz-16bit-mono-pcm": "Riff48Khz16BitMonoPcm"}
_PHONEME_PREFIX = "ipa:"

# Everything else stays without a status, so it is not retried: only 429 and server errors are.
STATUS_FOR_CANCEL_CODE = {
    "BadRequest": 400,
    "AuthenticationFailure": 401,
    "Forbidden": 403,
    "TooManyRequests": 429,
    "ServiceError": 500,
    "ServiceUnavailable": 503,
    "ServiceTimeout": 504,
}

# Characters XML 1.0 cannot hold at all, so no escaping can carry them.
_NOT_XML = re.compile(r"[^\t\n\r\x20-퟿-�\U00010000-\U0010ffff]")
_UNFILLED_TOKEN = re.compile(r"\{[^{}\s]*\}")
_ATTRIBUTE_QUOTES = {'"': "&quot;", "'": "&apos;"}


def _xml_safe(value: str, what: str) -> str:
    found = _NOT_XML.search(value)
    if found:
        raise VoiceInputError(f"{what} holds U+{ord(found.group()):04X}, which SSML cannot carry")
    return escape(value, _ATTRIBUTE_QUOTES)


def _pronunciation_element(key: str, value: str) -> str:
    """A `voice.pronunciation` value is the spoken text for `<sub>`, or `ipa:` and a phoneme."""
    written = _xml_safe(key, "voice.pronunciation key")
    if value.startswith(_PHONEME_PREFIX):
        phoneme = value.removeprefix(_PHONEME_PREFIX)
        if not phoneme.strip():
            raise VoiceConfigError(f"voice.pronunciation has an empty phoneme for {key!r}")
        ph = _xml_safe(phoneme, "voice.pronunciation value")
        return f'<phoneme alphabet="ipa" ph="{ph}">{written}</phoneme>'
    alias = _xml_safe(value, "voice.pronunciation value")
    return f'<sub alias="{alias}">{written}</sub>'


def _check_pronunciation(pronunciation: Mapping[str, str]) -> None:
    for key, value in pronunciation.items():
        if not key.strip() or not value.strip():
            raise VoiceConfigError("voice.pronunciation has a blank entry")


def _escaped_body(text: str, pronunciation: Mapping[str, str]) -> str:
    """One pass over the raw text, so an alias is never rewritten by another entry, and the
    text between matches is escaped on its own."""
    pattern = whole_word_pattern(pronunciation)
    if pattern is None:
        return _xml_safe(text, "script text")
    by_written_form = {" ".join(key.split()): value for key, value in pronunciation.items()}
    parts = []
    position = 0
    for found in pattern.finditer(text):
        parts.append(_xml_safe(text[position : found.start()], "script text"))
        written = found.group()
        parts.append(_pronunciation_element(written, by_written_form[" ".join(written.split())]))
        position = found.end()
    parts.append(_xml_safe(text[position:], "script text"))
    return "".join(parts)


@dataclass(frozen=True, slots=True)
class Ssml:
    document: str
    billable_characters: int


def build_ssml(
    text: str,
    voice: str,
    language: str,
    rate: str,
    pitch: str,
    pronunciation: Mapping[str, str],
) -> Ssml:
    if not text.strip():
        raise VoiceInputError("the script text is empty")
    if _UNFILLED_TOKEN.search(text):
        raise VoiceInputError("the script text still holds an unfilled token such as {brand_ar}")
    locale = _LOCALE_FOR_LANGUAGE.get(language)
    if locale is None:
        raise VoiceInputError(f"unknown reel language: {language!r}")
    _check_pronunciation(pronunciation)
    body = _escaped_body(text, pronunciation)
    rate_value = _xml_safe(rate, "voice.rate")
    pitch_value = _xml_safe(pitch, "voice.pitch")
    inner = f'<prosody rate="{rate_value}" pitch="{pitch_value}">{body}</prosody>'
    voice_name = _xml_safe(voice, "voice name")
    document = (
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
        f'xml:lang="{locale}"><voice name="{voice_name}">{inner}</voice></speak>'
    )
    # Microsoft bills markup inside the document as well, except <speak> and <voice>. Counting
    # the escaped form can only overstate the bill, which is the safe side for the monthly cap.
    return Ssml(document, len(inner))


def parse_word_events(events: Iterable[Any]) -> list[TimedWord]:
    """Keeps `Word` boundaries and drops `Punctuation` and `Sentence` (spec Section 7.4)."""
    words: list[TimedWord] = []
    for event in events:
        if getattr(event.boundary_type, "name", None) != "Word":
            continue
        length_ms = round(event.duration / timedelta(milliseconds=1))
        if event.audio_offset < 0 or length_ms < 0:
            raise VoiceTimingError(f"word event {event.text!r} has an impossible time")
        start_ms = event.audio_offset // _TICKS_PER_MS
        if words and start_ms < words[-1].start_ms:
            raise VoiceTimingError(f"word event {event.text!r} goes back in time")
        words.append(TimedWord(event.text, start_ms, start_ms + length_ms))
    return words


@dataclass(frozen=True, slots=True)
class SpeechOutcome:
    audio_data: bytes
    events: list[Any]


class SpeechClient(Protocol):
    """The seam around the SDK."""

    def speak_ssml(self, ssml: str) -> SpeechOutcome: ...


def _load_sdk() -> Any:
    return importlib.import_module(_SDK_MODULE)


class SdkSpeechClient:
    """The real SDK, loaded on first use. One synthesizer per call, one call at a time."""

    def __init__(
        self,
        key: str,
        region: str,
        output_format: str,
        *,
        sdk_loader: Callable[[], Any] | None = None,
    ) -> None:
        if output_format not in _SDK_FORMAT_FOR_CONFIG:
            raise VoiceConfigError(f"voice.output_format is not supported: {output_format!r}")
        self._key = key
        self._region = region
        self._output_format = _SDK_FORMAT_FOR_CONFIG[output_format]
        self._sdk_loader = sdk_loader or _load_sdk

    def __repr__(self) -> str:
        return f"SdkSpeechClient(region={self._region!r})"

    def _sdk(self) -> Any:
        try:
            return self._sdk_loader()
        except (ImportError, OSError) as error:
            # WinError 206 and a missing Visual C++ runtime both land here (spec Section 7.2).
            raise VoiceConfigError(
                f"The Azure Speech SDK will not load ({type(error).__name__}). "
                "Check the venv path length and the Visual C++ Redistributable."
            ) from error

    def speak_ssml(self, ssml: str) -> SpeechOutcome:
        sdk = self._sdk()
        events: list[Any] = []
        try:
            speech_config = sdk.SpeechConfig(subscription=self._key, region=self._region)
            speech_config.set_speech_synthesis_output_format(
                getattr(sdk.SpeechSynthesisOutputFormat, self._output_format)
            )
            # audio_config=None returns the audio in the result. The SDK's default plays it aloud.
            synthesizer = sdk.SpeechSynthesizer(speech_config=speech_config, audio_config=None)
            synthesizer.synthesis_word_boundary.connect(events.append)
            result = synthesizer.speak_ssml_async(ssml).get()
        except RuntimeError as error:  # how the SDK reports a native failure
            detail = self._clean(str(error))
            raise VoiceServiceError(None, f"The Azure Speech SDK failed: {detail}") from None
        if result.reason == sdk.ResultReason.SynthesizingAudioCompleted:
            return SpeechOutcome(result.audio_data, events)
        raise self._failure(result, sdk)

    def _clean(self, detail: str) -> str:
        """Text from the service goes into logs and notices, so it stays short and keyless."""
        return detail.replace(self._key, "[redacted]")[:_MAX_ERROR_DETAIL_CHARS]

    def _failure(self, result: Any, sdk: Any) -> VoiceServiceError:
        if result.reason != sdk.ResultReason.Canceled or result.cancellation_details is None:
            return VoiceServiceError(None, f"Azure Speech ended with {result.reason}")
        details = result.cancellation_details
        code = getattr(details.error_code, "name", str(details.error_code))
        message = self._clean(str(details.error_details or ""))
        return VoiceServiceError(
            STATUS_FOR_CANCEL_CODE.get(code),
            f"Azure Speech refused the request ({code}): {message}",
        )


@dataclass(frozen=True)
class AzureSpeechProvider:
    client: SpeechClient
    region: str
    azure_tier: str
    audio_dir: Path
    rate: str
    pitch: str
    output_format: str
    pronunciation: Mapping[str, str]
    caption_phrases: tuple[str, ...] = BRAND_PHRASES

    name: ClassVar[str] = "azure_speech"

    def _ssml(self, text: str, voice: str, language: str) -> Ssml:
        return build_ssml(text, voice, language, self.rate, self.pitch, self.pronunciation)

    def billable_characters(self, text: str, voice: str, language: str) -> int:
        return self._ssml(text, voice, language).billable_characters

    def fingerprint(self, text: str, voice: str, language: str) -> str:
        """A hash of the script text, voice, region and tier. The SSML carries the text and the
        voice, and also the prosody and pronunciation fixes, because a changed fix has to
        produce new audio rather than bring the old audio back."""
        request = {
            "provider": self.name,
            "ssml": self._ssml(text, voice, language).document,
            "region": self.region,
            "tier": self.azure_tier,
            "output_format": self.output_format,
        }
        encoded = json.dumps(request, ensure_ascii=False, sort_keys=True).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()

    def with_prosody(self, rate: str, pitch: str) -> AzureSpeechProvider:
        return replace(self, rate=rate, pitch=pitch)

    def _spoken_aliases(self) -> dict[str, str]:
        return {
            key: value
            for key, value in self.pronunciation.items()
            if not value.startswith(_PHONEME_PREFIX)
        }

    def match_tokens(self, text: str, raw_words: list[TimedWord]) -> list[TokenMatch]:
        try:
            return match_tokens(
                text, raw_words, phrases=self.caption_phrases, aliases=self._spoken_aliases()
            )
        except AlignmentError as error:
            raise VoiceTimingError(str(error)) from error

    def synthesize(self, text: str, voice: str, language: str) -> VoiceResult:
        ssml = self._ssml(text, voice, language)
        outcome = self.client.speak_ssml(ssml.document)
        if not outcome.audio_data:
            raise VoiceServiceError(None, "Azure Speech returned no audio")
        self.audio_dir.mkdir(parents=True, exist_ok=True)
        audio_path = self.audio_dir / f".incoming-{uuid.uuid4().hex}{_WAV_SUFFIX}"
        audio_path.write_bytes(outcome.audio_data)
        result = VoiceResult(
            audio_path=audio_path,
            words=[],
            provider=self.name,
            voice=voice,
            azure_tier=self.azure_tier,
            billable_characters=ssml.billable_characters,
        )
        try:
            raw_words = parse_word_events(outcome.events)
            result = replace(result, raw_words=raw_words)
            words = timed_tokens(self.match_tokens(text, raw_words))
        except VoiceTimingError as error:
            # The audio is already paid for, so the caller gets it along with the failure.
            raise VoiceTimingError(str(error), result=result) from error
        return replace(result, words=words)
