"""Research, write and review: three separate Claude sessions (spec Sections 3.5, 6.4, 6.5).

Each step gets 3 tries with a growing delay, then `GenerationFailed`. A usage limit, an expired
login or the budget cap stops at once, so those are not counted as failures and the reel can wait
for a later tick. A review that fails raises `ReviewBlocked`, which is not retried.

The checks here hold the job in place whatever a page or the model said: output must keep the
job's topic and language, cite only pages fetched in this run, and copy no long passage. The
deterministic guardrails run after this, in `guardrails.py`, and receive `Research.excerpts`.
"""

from __future__ import annotations

import re
import time
import unicodedata
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, timedelta
from urllib.parse import urlsplit

from content_engine.llm_backends import LlmBackend, LlmError, LlmResult, LlmRunFailed, SpendTracker
from content_engine.prompts import (
    BRAND_TOKENS,
    ClaimsRegister,
    ReelBrief,
    research_request,
    review_request,
    writer_request,
)
from content_engine.schemas import ResearchResult, ReviewVerdict, Script
from core.brand_gate import contains_real_brand, letters_only
from core.config import EngineConfig, strings_in

__all__ = [
    "Draft",
    "Excerpt",
    "GenerationFailed",
    "ReelBrief",
    "Research",
    "ResearchRejected",
    "ReviewBlocked",
    "ScriptRejected",
    "check_research",
    "generate_script",
    "review_script",
    "run_research",
    "write_script",
]

_RETRY_DELAYS_SECONDS = (30, 120)  # three tries, so two waits
_WORD = re.compile(r"\w+")
_TOKEN = re.compile(r"\{[^{}]*\}")
_GUARDIANSHIP_WORD = re.compile(r"\S*قوامة\S*")  # a different word, a soft flag under G18
_OLD_APP_NAME = letters_only("Budget" + "Tracker")  # G12


class GenerationFailed(LlmError):
    """All tries of a step are used up, so the reel moves to `failed` with one notice."""


class ResearchRejected(LlmRunFailed):
    """The research came back but breaks Section 6.4. Uses up a try."""


class ScriptRejected(LlmRunFailed):
    """The script came back but left its job or its token rules. Uses up a try."""


class ReviewBlocked(Exception):
    """The separate review failed the script, so the reel moves to `blocked_guardrails`."""

    def __init__(self, reasons: tuple[str, ...]) -> None:
        super().__init__(f"the review failed the script, {len(reasons)} reasons")
        self.reasons = reasons


@dataclass(frozen=True)
class Excerpt:
    """Text of a fetched page. Untrusted, and only ever compared against, for the copy check."""

    url: str
    text: str


@dataclass(frozen=True)
class Research:
    result: ResearchResult
    excerpts: tuple[Excerpt, ...]


@dataclass(frozen=True)
class Draft:
    research: Research
    script: Script
    verdict: ReviewVerdict


def _with_tries[T](step: str, attempt: Callable[[], T], sleep: Callable[[float], None]) -> T:
    for delay in _RETRY_DELAYS_SECONDS:
        try:
            return attempt()
        except LlmRunFailed:
            sleep(delay)
    try:
        return attempt()
    except LlmRunFailed as error:
        raise GenerationFailed(f"{step} failed on every try. Last: {error}") from error


def _same_page_key(url: str) -> tuple[str, str | None, int | None, str, str] | None:
    """Only differences that cannot change the page: host case, a fragment, a final slash. An
    address that cannot be parsed gives None, and so matches nothing that was fetched."""
    try:
        parts = urlsplit(url)
        return (parts.scheme, parts.hostname, parts.port, parts.path.rstrip("/"), parts.query)
    except ValueError:
        return None


def _words(text: str) -> list[str]:
    composed = unicodedata.normalize("NFKC", text).casefold()
    unmarked = "".join(
        ch for ch in unicodedata.normalize("NFD", composed) if unicodedata.category(ch) != "Mn"
    )
    return _WORD.findall(unmarked)


def _runs_of(words: list[str], length: int) -> set[tuple[str, ...]]:
    return {tuple(words[i : i + length]) for i in range(len(words) - length + 1)}


def check_research(run: LlmResult, *, today: date, max_copied_words: int) -> Research:
    """Spec Section 6.4, for output that already passed the schema."""
    result: ResearchResult = run.output
    pages = tuple(
        Excerpt(call.url, call.text)
        for call in run.tool_log
        if call.name == "web_fetch" and call.succeeded and call.url
    )
    fetched = {_same_page_key(page.url) for page in pages} - {None}
    copied = set().union(*(_runs_of(_words(page.text), max_copied_words) for page in pages), set())
    earliest = today - timedelta(days=1)  # a run can cross midnight
    for number, fact in enumerate(result.facts, start=1):
        if _same_page_key(fact.source_url) not in fetched:
            raise ResearchRejected(f"fact {number} cites a URL missing from the tool log")
        if not earliest <= fact.accessed <= today:
            raise ResearchRejected(f"fact {number} has an access date other than this run")
        for text in (fact.claim, fact.paraphrase_ar, fact.paraphrase_en):
            if _runs_of(_words(text), max_copied_words) & copied:
                raise ResearchRejected(f"fact {number} holds a copied passage")
    return Research(result, pages)


def run_research(
    backend: LlmBackend,
    brief: ReelBrief,
    spend: SpendTracker,
    *,
    today: date,
    max_copied_words: int,
    sleep: Callable[[float], None] = time.sleep,
) -> Research:
    request = research_request(brief, today=today)

    def attempt() -> Research:
        run = backend.run(request, spend)
        return check_research(run, today=today, max_copied_words=max_copied_words)

    return _with_tries("research", attempt, sleep)


def _check_tokens_and_names(script: Script) -> None:
    """G12 as far as it decides whether the output is usable at all."""
    for where, text in strings_in(script.model_dump(mode="json"), ""):
        leftover = text
        for match in _TOKEN.finditer(text):
            if match.group() not in BRAND_TOKENS:
                raise ScriptRejected(f"{where} holds a token that is not a brand token")
            leftover = leftover.replace(match.group(), " ")
        if "{" in leftover or "}" in leftover:
            raise ScriptRejected(f"{where} holds a stray curly brace")
        plain = _GUARDIANSHIP_WORD.sub(" ", leftover)
        if contains_real_brand(plain) or _OLD_APP_NAME in letters_only(plain):
            raise ScriptRejected(f"{where} holds a hard-coded brand name")


def _check_script(
    script: Script, brief: ReelBrief, research: Research, register: ClaimsRegister
) -> None:
    job = (brief.topic_id, brief.tier, brief.template, brief.language, brief.feature_clip_folder)
    made = (
        script.topic_id,
        script.tier,
        script.template,
        script.language,
        script.feature_clip_folder,
    )
    if made != job:
        raise ScriptRejected("the script does not match its job")
    _check_tokens_and_names(script)
    approved = {claim.id for claim in register.approved}
    if not set(script.claim_ids) <= approved:
        raise ScriptRejected("the script uses a claim id that is not approved")
    found = {_same_page_key(fact.source_url) for fact in research.result.facts} - {None}
    cited = [number.source_url for number in script.numbers]
    cited += [source.url for source in script.sources]
    if any(_same_page_key(url) not in found for url in cited):
        raise ScriptRejected("the script cites a source the research did not find")


def write_script(
    backend: LlmBackend,
    brief: ReelBrief,
    research: Research,
    register: ClaimsRegister,
    config: EngineConfig,
    spend: SpendTracker,
    *,
    sleep: Callable[[float], None] = time.sleep,
) -> Script:
    request = writer_request(brief, research.result, register, config)

    def attempt() -> Script:
        script: Script = backend.run(request, spend).output
        _check_script(script, brief, research, register)
        return script

    return _with_tries("script", attempt, sleep)


def review_script(
    backend: LlmBackend,
    script: Script,
    register: ClaimsRegister,
    spend: SpendTracker,
    *,
    sleep: Callable[[float], None] = time.sleep,
) -> ReviewVerdict:
    request = review_request(script, register)
    verdict: ReviewVerdict = _with_tries(
        "review", lambda: backend.run(request, spend).output, sleep
    )
    if not verdict.passed:
        raise ReviewBlocked(tuple(verdict.reasons))
    return verdict


def generate_script(
    backend: LlmBackend,
    brief: ReelBrief,
    register: ClaimsRegister,
    config: EngineConfig,
    spend: SpendTracker,
    *,
    today: date,
    sleep: Callable[[float], None] = time.sleep,
) -> Draft:
    """Steps 2 to 4 of the daily flow, up to the deterministic guardrails. The caller makes one
    `SpendTracker` per reel, so the cap covers every step and every retry."""
    research = run_research(
        backend,
        brief,
        spend,
        today=today,
        max_copied_words=config.guardrails.max_copied_words,
        sleep=sleep,
    )
    script = write_script(backend, brief, research, register, config, spend, sleep=sleep)
    verdict = review_script(backend, script, register, spend, sleep=sleep)
    return Draft(research, script, verdict)
