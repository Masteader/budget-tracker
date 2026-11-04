"""Map timed word events back onto script tokens (spec Sections 7.4 and 8.4).

A caption token is a run of text between spaces, so punctuation stays on its word. The brand is
one token (G18), so قوام is never on screen alone. Matching compares letters only, in order, and
every letter of the script has to be covered: a missing, extra or out-of-order event fails
rather than leaving captions that drift from the voice.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass

from core.brand_gate import FULL_NAME_AR, FULL_NAME_EN, letters_only

BRAND_PHRASES = (FULL_NAME_AR, FULL_NAME_EN)

_TOKEN = re.compile(r"\S+")
_POSSESSIVE = re.compile(r"['’]s\W*$", re.IGNORECASE)
_ATTACHED_PREFIX_LETTERS = frozenset("وفبلك")  # و ف ب ل ك
_MAX_ATTACHED_PREFIX = 2
_COMBINING_MARKS = "̀-ͯؐ-ًؚ-ٰٟ"
_NOT_WORD_NEIGHBOUR = rf"[\w{_COMBINING_MARKS}]"


class AlignmentError(ValueError):
    """The word events do not cover the script. The message names the token."""


@dataclass(frozen=True, slots=True)
class TimedWord:
    text: str
    start_ms: int
    end_ms: int


@dataclass(frozen=True, slots=True)
class TokenMatch:
    text: str
    word_count: int
    events: tuple[TimedWord, ...]


@dataclass(frozen=True, slots=True)
class _Unit:
    text: str
    letters: str
    word_count: int


def _fold(text: str) -> str:
    """The letters and digits a listener hears, with digit forms made equal."""
    return "".join(
        str(unicodedata.decimal(ch)) if ch.isdecimal() else ch for ch in letters_only(text)
    )


def whole_word_pattern(keys: Iterable[str]) -> re.Pattern[str] | None:
    """Finds any key as whole words, longest first, across any whitespace."""
    ordered = sorted(keys, key=len, reverse=True)
    if not ordered:
        return None
    body = "|".join(r"\s+".join(re.escape(part) for part in key.split()) for key in ordered)
    return re.compile(rf"(?<!{_NOT_WORD_NEIGHBOUR})(?:{body})(?!{_NOT_WORD_NEIGHBOUR})")


def _starts_phrase(token: str, first_word: str) -> bool:
    letters = _fold(token)
    if letters == first_word:
        return True
    prefix = letters.removesuffix(first_word)
    return (
        prefix != letters
        and len(prefix) <= _MAX_ATTACHED_PREFIX
        and set(prefix) <= _ATTACHED_PREFIX_LETTERS
    )


def _continues_phrase(token: str, word: str) -> bool:
    return _fold(_POSSESSIVE.sub("", token)) == word


def _link_phrases(tokens: list[str], phrases: Iterable[str], links: list[bool]) -> None:
    for phrase in phrases:
        words = [_fold(word) for word in phrase.split()]
        if not words:
            continue
        for start in range(len(tokens) - len(words) + 1):
            if _starts_phrase(tokens[start], words[0]) and all(
                _continues_phrase(tokens[start + offset], word)
                for offset, word in enumerate(words[1:], start=1)
            ):
                for link in range(start, start + len(words) - 1):
                    links[link] = True


def _link_spans(spans: list[re.Match[str]], text: str, pattern, links: list[bool]) -> None:
    for found in pattern.finditer(text):
        covered = [
            index
            for index, span in enumerate(spans)
            if span.start() < found.end() and span.end() > found.start()
        ]
        for link in covered[:-1]:
            links[link] = True


def _units(text: str, phrases: Iterable[str], aliases: Mapping[str, str]) -> list[_Unit]:
    spans = list(_TOKEN.finditer(text))
    tokens = [span.group() for span in spans]
    links = [False] * len(tokens)
    _link_phrases(tokens, phrases, links)
    pattern = whole_word_pattern(aliases)
    spoken_by_key = {" ".join(key.split()): alias for key, alias in aliases.items()}
    if pattern:
        _link_spans(spans, text, pattern, links)

    def spoken(span_text: str) -> str:
        if pattern is None:
            return span_text
        return pattern.sub(lambda m: spoken_by_key[" ".join(m.group().split())], span_text)

    units: list[_Unit] = []
    start = 0
    for index in range(len(tokens)):
        if links[index] and index + 1 < len(tokens):
            continue
        group = tokens[start : index + 1]
        written = text[spans[start].start() : spans[index].end()]
        units.append(_Unit(" ".join(group), _fold(spoken(written)), len(group)))
        start = index + 1
    return _attach_marks(units)


def _attach_marks(units: list[_Unit]) -> list[_Unit]:
    """A token with no letters is punctuation, so it travels with its neighbour."""
    attached: list[_Unit] = []
    waiting: list[str] = []
    for unit in units:
        if not unit.letters:
            if attached:
                last = attached[-1]
                attached[-1] = _Unit(f"{last.text} {unit.text}", last.letters, last.word_count)
            else:
                waiting.append(unit.text)
            continue
        attached.append(_Unit(" ".join([*waiting, unit.text]), unit.letters, unit.word_count))
        waiting = []
    if not attached:
        raise AlignmentError("the script has no words to time")
    return attached


def _match(units: list[_Unit], events: Sequence[TimedWord]) -> list[TokenMatch]:
    stream = "".join(unit.letters for unit in units)
    owners = [index for index, unit in enumerate(units) for _ in unit.letters]
    matched: list[list[TimedWord]] = [[] for _ in units]
    position = 0
    for event in events:
        letters = _fold(event.text)
        if not letters:
            continue
        if not stream.startswith(letters, position):
            expected = units[owners[position]].text if position < len(stream) else "end of script"
            raise AlignmentError(f"word event {event.text!r} does not match {expected!r}")
        for owner in range(owners[position], owners[position + len(letters) - 1] + 1):
            matched[owner].append(event)
        position += len(letters)
    if position < len(stream):
        raise AlignmentError(f"no word event for {units[owners[position]].text!r}")
    return [
        TokenMatch(unit.text, unit.word_count, tuple(events_for))
        for unit, events_for in zip(units, matched, strict=True)
    ]


def match_tokens(
    text: str,
    events: Sequence[TimedWord],
    *,
    phrases: Iterable[str] = BRAND_PHRASES,
    aliases: Mapping[str, str] | None = None,
) -> list[TokenMatch]:
    """The events behind each caption token. `aliases` are `<sub>` values: the docs do not say
    whether a word event reports the written word or the alias, so both are accepted."""
    phrases = tuple(phrases)
    try:
        return _match(_units(text, phrases, {}), events)
    except AlignmentError:
        if not aliases:
            raise
    return _match(_units(text, phrases, aliases), events)


def align_words(
    text: str,
    events: Sequence[TimedWord],
    *,
    phrases: Iterable[str] = BRAND_PHRASES,
    aliases: Mapping[str, str] | None = None,
) -> list[TimedWord]:
    return timed_tokens(match_tokens(text, events, phrases=phrases, aliases=aliases))


def timed_tokens(matches: Iterable[TokenMatch]) -> list[TimedWord]:
    return [
        TimedWord(
            match.text,
            match.events[0].start_ms,
            max(event.end_ms for event in match.events),
        )
        for match in matches
    ]
