"""Where batch C's register meets batch D's prompts: the writer and the review run on the real
`approved_claims.json`, through the one `ClaimsRegister`, and both batches agree on which claims
may be used. A claim the code does not back is never offered to the writer (spec Section 6.5)."""

from datetime import date

import pytest
from fixtures.llm_fakes import ScriptedBackend

from content_engine import prompts
from content_engine.guardrails import ClaimsRegister, check_claim_ids, load_claims_register
from content_engine.llm_backends import LlmResult, SpendTracker, ToolCall
from content_engine.prompts import review_request, writer_request
from content_engine.researcher import (
    GenerationFailed,
    ReelBrief,
    Research,
    generate_script,
    write_script,
)
from content_engine.schemas import ResearchResult, ReviewVerdict, Script
from core.config import load_config

CONFIG = load_config()
REGISTER = load_claims_register()
URL = "https://stats.example.org/report"
WINDOWS_COMMAND_LINE_BUDGET = 24_000  # the limit test_script_writer holds a normal reel to

BRIEF = ReelBrief(
    topic_id="ramadan_groceries",
    tier="regional",
    template="DailyTip",
    language="ar",
    topic_text="Grocery spending in Ramadan",
    feature_clip_folder=None,
    claim_ids=tuple(REGISTER.claims),
)
FACT = {
    "claim": "Grocery spending rises in Ramadan.",
    "source_url": URL,
    "publisher": "Stats Office",
    "accessed": "2026-11-03",
    "paraphrase_ar": "يزيد الإنفاق على البقالة في رمضان.",
    "paraphrase_en": "Households buy more food during Ramadan.",
}
FACTS = ResearchResult.model_validate({"facts": [FACT]})
RESEARCH = Research(result=FACTS, excerpts=())

SUPPORTED = [c for c in REGISTER.claims.values() if c.code_check == "supported"]
HELD = [c for c in REGISTER.claims.values() if c.code_check != "supported"]


def script(**changes) -> Script:
    return Script.model_validate(
        {
            "topic_id": BRIEF.topic_id,
            "tier": BRIEF.tier,
            "template": BRIEF.template,
            "language": BRIEF.language,
            "hook_ar": "راتبك وين يروح كل شهر؟",
            "voice_script": "مقاضي رمضان ترفع مصروفك. سجلها في {brand_ar}. {brand_ar}، قريبًا.",
            "on_screen_en": ["Where does your salary go?"],
            "subtitles_en": "Ramadan shopping raises your spending. Log it in {brand_en}.",
            "feature_clip_folder": None,
            "claim_ids": [SUPPORTED[0].id],
            "numbers": [{"value": "12%", "source_url": URL}],
            "sources": [{"publisher": "Stats Office", "url": URL}],
            "caption_ar": "{brand_ar} {brand_en} قريبًا. نجهّز الوصول المبكر.",
            "caption_en": "{brand_en} {brand_ar} is coming soon. Early access is on the way.",
            "hashtags": ["{brand_hashtag}", "#رمضان"],
            "speech_seconds_estimate": 32.0,
            **changes,
        }
    )


def as_result(output) -> LlmResult:
    return LlmResult(output, (), 0.1)


def prompt_of(request) -> str:
    return request.instructions + request.data


REQUESTS = [
    pytest.param(lambda: writer_request(BRIEF, FACTS, REGISTER, CONFIG), id="writer"),
    pytest.param(lambda: review_request(script(), REGISTER, FACTS), id="review"),
]


def test_there_is_one_register_shape():
    assert prompts.ClaimsRegister is ClaimsRegister


def test_the_real_register_has_claims_of_both_kinds():
    # Otherwise the tests below could pass without proving anything.
    assert SUPPORTED
    assert HELD
    assert REGISTER.rejected


@pytest.mark.parametrize("build", REQUESTS)
def test_the_prompt_lists_every_supported_claim_from_the_real_register(build):
    prompt = prompt_of(build())
    for claim in SUPPORTED:
        assert f"- {claim.id}: " in prompt
        assert claim.wording_ar in prompt
        assert claim.wording_en in prompt


@pytest.mark.parametrize("build", REQUESTS)
def test_the_prompt_never_offers_a_claim_the_code_does_not_back(build):
    prompt = prompt_of(build())
    for claim in HELD:
        assert f"- {claim.id}: " not in prompt
        assert claim.wording_ar not in prompt
        assert claim.wording_en not in prompt


@pytest.mark.parametrize("build", REQUESTS)
def test_the_prompt_lists_every_rejected_claim_from_the_real_register(build):
    prompt = prompt_of(build())
    for rejected in REGISTER.rejected:
        assert f"- {rejected.id}: {rejected.claim}" in prompt


@pytest.mark.parametrize("claim", [*SUPPORTED, *HELD], ids=lambda claim: claim.id)
def test_batch_c_and_batch_d_agree_on_each_claim(claim):
    offered = claim in REGISTER.approved
    assert offered is (check_claim_ids([claim.id], REGISTER) == [])
    assert offered is (claim.code_check == "supported")


@pytest.mark.parametrize("claim", SUPPORTED, ids=lambda claim: claim.id)
def test_the_writer_step_accepts_each_supported_claim(claim):
    result = as_result(script(claim_ids=[claim.id]))
    written = write_script(
        ScriptedBackend(result), BRIEF, RESEARCH, REGISTER, CONFIG, SpendTracker(2.0)
    )
    assert written.claim_ids == [claim.id]


@pytest.mark.parametrize("claim", HELD, ids=lambda claim: claim.id)
def test_the_writer_step_refuses_a_claim_the_code_does_not_back(claim):
    results = [as_result(script(claim_ids=[claim.id])) for _ in range(3)]
    with pytest.raises(GenerationFailed):
        write_script(
            ScriptedBackend(*results),
            BRIEF,
            RESEARCH,
            REGISTER,
            CONFIG,
            SpendTracker(2.0),
            sleep=lambda seconds: None,
        )


def test_all_three_steps_run_on_the_real_register():
    backend = ScriptedBackend(
        LlmResult(FACTS, (ToolCall("web_fetch", URL, "The page text.", True),), 0.2),
        as_result(script()),
        as_result(ReviewVerdict(passed=True, reasons=[])),
    )
    draft = generate_script(
        backend,
        BRIEF,
        REGISTER,
        CONFIG,
        SpendTracker(2.0),
        today=date(2026, 11, 3),
        sleep=lambda seconds: None,
    )
    assert draft.verdict.passed
    assert [request.step for request in backend.requests] == ["research", "write", "review"]


def test_the_real_register_fits_a_windows_command_line_with_a_full_set_of_facts():
    facts = ResearchResult.model_validate({"facts": [FACT] * 8})
    request = writer_request(BRIEF, facts, REGISTER, CONFIG)
    assert len(prompt_of(request)) < WINDOWS_COMMAND_LINE_BUDGET
