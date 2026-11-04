"""Map timed word events back onto script tokens (spec Sections 7.4 and 8.4).

A caption token is a run of text between spaces, so punctuation stays on its word. The brand is
one token (G18), so قوام is never on screen alone. A word glued to the brand by punctuation, as in
`قوام المال،وفر` or `Qawam Money-powered`, gets a token of its own, and the punctuation stays on the
brand. Matching compares letters only, in order, and every letter of the script has to be covered:
a missing, extra or out-of-order event fails rather than leaving captions that drift from the voice.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass

from core.brand_gate import FULL_NAME_AR, FULL_NAME_EN, letters_only

BRAND_PHRASES = (FULL_NAME_AR, FULL_NAME_EN)

_TOKEN = re.compile(r"\S+")
_POSSESSIVE = re.compile(r"['’]s(?!\w)", re.IGNORECASE)
_ATTACHED_PREFIX_LETTERS = frozenset("وفبلك")  # و ف ب ل ك
_MAX_ATTACHED_PREFIX = 2
_KASHIDA = "\u0640"
_SILENT_CATEGORIES = {"Mn", "Me", "Cf"}
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


@dataclass(frozen=True, slots=True)
class PhraseSpan:
    """Where a phrase stands in the raw text. `start` includes an attached prefix such as ب."""

    start: int
    name_start: int
    end: int


@dataclass(frozen=True, slots=True)
class PronunciationHit:
    start: int
    end: int
    key: str
    prefix: str  # the attached letters in front of the brand, which the fix has to say as well


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


def has_words(text: str) -> bool:
    return bool(_fold(text))


def _letter_map(text: str) -> tuple[str, list[int]]:
    """The folded letters of the text, and the raw position each one came from."""
    letters: list[str] = []
    positions: list[int] = []
    for position, ch in enumerate(text):
        for letter in _fold(ch):
            letters.append(letter)
            positions.append(position)
    return "".join(letters), positions


def _is_silent(ch: str) -> bool:
    """A mark on a letter, kashida or an invisible character: not a gap between two letters."""
    return ch == _KASHIDA or unicodedata.category(ch) in _SILENT_CATEGORIES


def _glued(text: str, left: int, right: int) -> bool:
    return all(_is_silent(ch) for ch in text[left + 1 : right])


def _attached_prefix(text: str, letters: str, positions: list[int], name: int) -> int | None:
    """How many letters are attached in front of the name at letter `name`. None if they make
    it another word, as ن does in نقوام."""
    first = name
    while (
        first > 0
        and letters[first - 1].isalpha()
        and _glued(text, positions[first - 1], positions[first])
    ):
        first -= 1
    attached = letters[first:name]
    if len(attached) > _MAX_ATTACHED_PREFIX or set(attached) - _ATTACHED_PREFIX_LETTERS:
        return None
    return len(attached)


def _words_are_whole(text: str, positions: list[int], name: int, words: list[str]) -> bool:
    """Spaces may stand between the phrase's words and never inside one, so قواما لمال is not it."""
    index = name
    for word in words:
        for offset in range(1, len(word)):
            gap = text[positions[index + offset - 1] : positions[index + offset]]
            if any(ch.isspace() for ch in gap):
                return False
        index += len(word)
    return True


def _span_at(
    text: str, letters: str, positions: list[int], name: int, words: list[str]
) -> PhraseSpan | None:
    if not _words_are_whole(text, positions, name, words):
        return None
    prefix = _attached_prefix(text, letters, positions, name)
    if prefix is None:
        return None
    after = name + sum(len(word) for word in words)
    last = positions[after - 1]
    if after < len(letters) and letters[after].isalpha() and _glued(text, last, positions[after]):
        return None
    end = last + 1
    while end < len(text) and _is_silent(text[end]):
        end += 1
    return PhraseSpan(positions[name - prefix], positions[name], end)


def phrase_spans(text: str, phrases: Iterable[str]) -> list[PhraseSpan]:
    """Finds phrases by their letters, so diacritics, kashida, case, look-alike letters, line
    breaks and punctuation cannot hide one. The longest wins where two overlap."""
    letters, positions = _letter_map(text)
    found: list[PhraseSpan] = []
    for phrase in phrases:
        words = [_fold(word) for word in phrase.split()]
        target = "".join(words)
        if not target:
            continue
        name = letters.find(target)
        while name != -1:
            span = _span_at(text, letters, positions, name, words)
            if span is not None:
                found.append(span)
            name = letters.find(target, name + 1)
    chosen: list[PhraseSpan] = []
    for span in sorted(found, key=lambda item: item.start - item.end):
        if all(span.end <= other.start or other.end <= span.start for other in chosen):
            chosen.append(span)
    return sorted(chosen, key=lambda item: item.start)


def pronunciation_hits(text: str, keys: Iterable[str]) -> list[PronunciationHit]:
    """Where each pronunciation fix applies. An ordinary key has to match as a whole word. The
    brand also applies with an attached prefix or diacritics, the forms G18 allows, because the
    name must be said the same way in all of them."""
    keys = list(keys)
    hits: list[PronunciationHit] = []
    pattern = whole_word_pattern(keys)
    if pattern is not None:
        by_written_form = {" ".join(key.split()): key for key in keys}
        for found in pattern.finditer(text):
            key = by_written_form[" ".join(found.group().split())]
            hits.append(PronunciationHit(found.start(), found.end(), key, ""))
    brand = {_fold(phrase) for phrase in BRAND_PHRASES}
    for key in keys:
        if _fold(key) in brand:
            for span in phrase_spans(text, [key]):
                prefix = _fold(text[span.start : span.name_start])
                hits.append(PronunciationHit(span.start, span.end, key, prefix))
    chosen: list[PronunciationHit] = []
    for hit in sorted(hits, key=lambda item: item.start - item.end):
        if all(hit.end <= other.start or other.end <= hit.start for other in chosen):
            chosen.append(hit)
    return sorted(chosen, key=lambda item: item.start)


def _token_spans(text: str, protected: list[PhraseSpan]) -> list[tuple[int, int]]:
    """Runs of text between spaces, cut where a word is glued to a phrase by punctuation. The
    punctuation stays on the phrase, except what comes first, which stays on the word before."""
    tokens: list[tuple[int, int]] = []
    for token in _TOKEN.finditer(text):
        start, end = token.span()
        cuts: set[int] = set()
        for span in protected:
            if start < span.start < end and _fold(text[start : span.start]):
                cuts.add(span.start)
            possessive = _POSSESSIVE.match(text, span.end)
            tail = possessive.end() if possessive else span.end
            if start < tail < end:
                next_letter = next((i for i in range(tail, end) if _fold(text[i])), None)
                if next_letter is not None:
                    cuts.add(next_letter)
        edges = [start, *sorted(cuts), end]
        tokens += list(zip(edges, edges[1:], strict=False))
    return tokens


def _spoken_letters(
    text: str, start: int, end: int, hits: list[PronunciationHit], aliases: Mapping[str, str]
) -> str:
    parts: list[str] = []
    position = start
    for hit in hits:
        if start <= hit.start and hit.end <= end:
            parts += [text[position : hit.start], hit.prefix, aliases[hit.key]]
            position = hit.end
    parts.append(text[position:end])
    return _fold("".join(parts))


def _units(text: str, phrases: Iterable[str], aliases: Mapping[str, str]) -> list[_Unit]:
    protected = phrase_spans(text, phrases)
    spans = _token_spans(text, protected)
    hits = pronunciation_hits(text, aliases)
    links = [False] * len(spans)
    for together in (*protected, *hits):
        covered = [
            index
            for index, (start, end) in enumerate(spans)
            if start < together.end and end > together.start
        ]
        for link in covered[:-1]:
            links[link] = True

    units: list[_Unit] = []
    first = 0
    for index in range(len(spans)):
        if links[index] and index + 1 < len(spans):
            continue
        group = [text[start:end] for start, end in spans[first : index + 1]]
        letters = _spoken_letters(text, spans[first][0], spans[index][1], hits, aliases)
        units.append(_Unit(" ".join(group), letters, sum(1 for part in group if _fold(part))))
        first = index + 1
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


def caption_tokens(text: str, phrases: Iterable[str] = BRAND_PHRASES) -> list[str]:
    """The tokens this script will show, which are known before anything is paid for."""
    return [unit.text for unit in _units(text, tuple(phrases), {})]


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
