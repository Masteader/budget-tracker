"""The `anthropic_api` backend, with an injected fake client (plan task D2, spec Section 6.3)."""

import json
from types import SimpleNamespace

import anthropic
import httpx2
import pytest

from content_engine.llm_backends import (
    AnthropicApiBackend,
    BudgetExceeded,
    LlmRequest,
    LlmRunFailed,
    LlmSetupError,
    LoginExpired,
    SpendTracker,
    UsageLimitReached,
    make_backend,
)
from content_engine.schemas import ReviewVerdict, Script
from core.config import load_config
from core.paths import EnginePaths

GOOD_TEXT = json.dumps({"passed": True, "reasons": []})
URL = "https://stats.example.org/report"


def text_block(text: str = GOOD_TEXT):
    return SimpleNamespace(type="text", text=text)


def usage(input_tokens=1000, output_tokens=500, searches=0, **fields):
    return SimpleNamespace(
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_creation_input_tokens=fields.get("cache_writes", 0),
        cache_read_input_tokens=fields.get("cache_reads", 0),
        server_tool_use=SimpleNamespace(web_search_requests=searches, web_fetch_requests=0),
    )


def message(*content, stop_reason="end_turn", used=None):
    return SimpleNamespace(
        content=list(content) or [text_block()],
        stop_reason=stop_reason,
        usage=usage() if used is None else used,
    )


class _Stream:
    def __init__(self, reply):
        self._reply = reply

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def get_final_message(self):
        if isinstance(self._reply, Exception):
            raise self._reply
        return self._reply


class FakeClient:
    def __init__(self, *replies):
        self.replies = list(replies) or [message()]
        self.requests = []
        self.messages = self

    def stream(self, **kwargs):
        # A copy, because the backend appends to its message list on a paused turn.
        self.requests.append({**kwargs, "messages": list(kwargs["messages"])})
        reply = self.replies[min(len(self.requests) - 1, len(self.replies) - 1)]
        return _Stream(reply)


def llm_settings(**changes):
    return load_config().llm.model_copy(update={"backend": "anthropic_api", **changes})


def backend_with(client, **changes) -> AnthropicApiBackend:
    return AnthropicApiBackend(llm_settings(**changes), client)


def request(step="write") -> LlmRequest:
    return LlmRequest(step=step, instructions="Do the job.", data="the data", schema=ReviewVerdict)


def spend(limit=2.0) -> SpendTracker:
    return SpendTracker(limit)


# --- Models ------------------------------------------------------------------------------


@pytest.mark.parametrize("bad_model", ["other-model-4", "", "claude", "CLAUDE-opus", "x-claude-1"])
def test_non_claude_models_are_refused_before_any_call(bad_model):
    client = FakeClient()
    with pytest.raises(LlmSetupError, match="Claude"):
        backend_with(client, model=bad_model)
    assert client.requests == []


@pytest.mark.parametrize(
    ("configured", "sent"),
    [
        ("opus", "claude-opus-5-5"),
        ("sonnet", "claude-sonnet-5-5"),
        ("haiku", "claude-haiku-5-5"),
        ("fable", "claude-fable-5-1"),
        ("claude-opus-4-8", "claude-opus-4-8"),
    ],
)
def test_aliases_become_full_model_names(configured, sent):
    client = FakeClient()
    backend_with(client, model=configured).run(request(), spend())
    assert client.requests[0]["model"] == sent


# --- The request -------------------------------------------------------------------------


def test_the_request_uses_structured_output_and_an_explicit_effort():
    client = FakeClient()
    backend_with(client).run(request(), spend())
    sent = client.requests[0]
    assert sent["output_config"]["effort"] == "high"
    assert sent["output_config"]["format"]["type"] == "json_schema"
    assert sent["output_config"]["format"]["schema"]["additionalProperties"] is False
    assert sent["system"] == "Do the job."
    assert sent["messages"] == [{"role": "user", "content": "the data"}]


def test_thinking_is_not_disabled():
    client = FakeClient()
    backend_with(client).run(request(), spend())
    assert client.requests[0].get("thinking", {"type": "adaptive"}) == {"type": "adaptive"}


def test_constraints_the_api_refuses_are_moved_out_of_the_schema():
    client = FakeClient(message(text_block("{}")))
    bad = LlmRequest(step="write", instructions="i", data="d", schema=Script)
    with pytest.raises(LlmRunFailed):
        backend_with(client).run(bad, spend())
    field = client.requests[0]["output_config"]["format"]["schema"]["properties"]
    assert "exclusiveMinimum" not in field["speech_seconds_estimate"]
    assert "maximum" not in field["speech_seconds_estimate"]


@pytest.mark.parametrize("step", ["write", "review"])
def test_writing_and_review_send_no_tools(step):
    client = FakeClient()
    backend_with(client).run(request(step), spend())
    assert "tools" not in client.requests[0]


def test_research_sends_the_two_web_tools_only():
    client = FakeClient()
    backend_with(client).run(request("research"), spend())
    tools = client.requests[0]["tools"]
    assert [(tool["type"], tool["name"]) for tool in tools] == [
        ("web_search_20260209", "web_search"),
        ("web_fetch_20260209", "web_fetch"),
    ]
    assert all(tool["max_uses"] > 0 for tool in tools)
    assert "tool_choice" not in client.requests[0]


# --- Results -----------------------------------------------------------------------------


def test_a_good_result_is_validated_and_returned():
    outcome = backend_with(FakeClient()).run(request(), spend())
    assert outcome.output == ReviewVerdict(passed=True, reasons=[])


def test_a_refusal_is_a_failure_and_its_content_is_not_read():
    client = FakeClient(message(text_block(GOOD_TEXT), stop_reason="refusal"))
    with pytest.raises(LlmRunFailed, match="refus"):
        backend_with(client).run(request(), spend())


@pytest.mark.parametrize("stop_reason", ["max_tokens", "tool_use", "model_context_window_exceeded"])
def test_any_other_unfinished_stop_is_a_failure(stop_reason):
    client = FakeClient(message(text_block(GOOD_TEXT), stop_reason=stop_reason))
    with pytest.raises(LlmRunFailed):
        backend_with(client).run(request(), spend())


@pytest.mark.parametrize(
    "bad_reply",
    [
        message(SimpleNamespace(type="thinking", thinking="")),
        message(text_block("not json")),
        message(text_block("[]")),
        message(text_block('{"passed": "yes", "reasons": []}')),
        message(text_block('{"passed": true, "reasons": [], "extra": 1}')),
    ],
)
def test_invalid_output_is_a_failure(bad_reply):
    with pytest.raises(LlmRunFailed):
        backend_with(FakeClient(bad_reply)).run(request(), spend())


def test_the_final_text_block_is_the_output():
    reply = message(text_block("Let me look that up."), text_block(GOOD_TEXT))
    outcome = backend_with(FakeClient(reply)).run(request("research"), spend())
    assert outcome.output.passed is True


# --- Tools in the reply ------------------------------------------------------------------


def fetch_call(tool_id="f1", url=URL):
    return SimpleNamespace(type="server_tool_use", id=tool_id, name="web_fetch", input={"url": url})


def fetch_result(tool_id="f1", url=URL, text="The page said this."):
    source = SimpleNamespace(type="text", data=text)
    document = SimpleNamespace(type="document", source=source)
    content = SimpleNamespace(type="web_fetch_result", url=url, content=document)
    return SimpleNamespace(type="web_fetch_tool_result", tool_use_id=tool_id, content=content)


def test_the_tool_log_holds_each_fetched_page():
    reply = message(fetch_call(), fetch_result(), text_block())
    log = backend_with(FakeClient(reply)).run(request("research"), spend()).tool_log
    assert [(call.name, call.url, call.text, call.succeeded) for call in log] == [
        ("web_fetch", URL, "The page said this.", True)
    ]


def test_a_fetch_error_object_is_logged_as_failed():
    error = SimpleNamespace(type="web_fetch_tool_result_error", error_code="url_not_accessible")
    result = SimpleNamespace(type="web_fetch_tool_result", tool_use_id="f1", content=error)
    reply = message(fetch_call(), result, text_block())
    log = backend_with(FakeClient(reply)).run(request("research"), spend()).tool_log
    assert log[0].url == URL
    assert not log[0].succeeded


def test_a_search_error_object_does_not_crash_and_a_good_search_is_logged():
    error = SimpleNamespace(type="web_search_tool_result_error", error_code="max_uses_exceeded")
    hit = SimpleNamespace(type="web_search_result", url=URL, title="A title")
    call_1 = SimpleNamespace(
        type="server_tool_use", id="s1", name="web_search", input={"query": "q"}
    )
    call_2 = SimpleNamespace(
        type="server_tool_use", id="s2", name="web_search", input={"query": "q"}
    )
    result_1 = SimpleNamespace(type="web_search_tool_result", tool_use_id="s1", content=error)
    result_2 = SimpleNamespace(type="web_search_tool_result", tool_use_id="s2", content=[hit])
    reply = message(call_1, result_1, call_2, result_2, text_block())
    log = backend_with(FakeClient(reply)).run(request("research"), spend()).tool_log
    assert [(call.name, call.succeeded) for call in log] == [
        ("web_search", False),
        ("web_search", True),
    ]


@pytest.mark.parametrize(
    "block",
    [
        SimpleNamespace(type="tool_use", id="t1", name="bash", input={}),
        SimpleNamespace(type="mcp_tool_use", id="t1", name="query", input={}),
        SimpleNamespace(type="server_tool_use", id="t1", name="tool_search_tool_regex", input={}),
    ],
)
def test_any_other_tool_in_the_reply_rejects_the_run(block):
    client = FakeClient(message(block, text_block()))
    with pytest.raises(LlmRunFailed, match="tool"):
        backend_with(client).run(request("research"), spend())


def test_a_tool_block_in_a_no_tool_step_rejects_the_run():
    client = FakeClient(message(fetch_call(), fetch_result(), text_block()))
    with pytest.raises(LlmRunFailed, match="tool"):
        backend_with(client).run(request("write"), spend())


def test_a_paused_turn_resumes_with_the_reply_appended_and_the_same_settings():
    paused = message(fetch_call(), fetch_result(), stop_reason="pause_turn")
    client = FakeClient(paused, message(text_block()))
    outcome = backend_with(client).run(request("research"), spend())
    first, second = client.requests
    assert second["messages"] == [
        {"role": "user", "content": "the data"},
        {"role": "assistant", "content": paused.content},
    ]
    assert second["tools"] == first["tools"]
    assert second["system"] == first["system"]
    assert len(outcome.tool_log) == 1


def test_paused_turns_cannot_go_on_for_ever():
    client = FakeClient(message(text_block("still going"), stop_reason="pause_turn"))
    with pytest.raises(LlmRunFailed, match="paus"):
        backend_with(client, max_turns=3).run(request("research"), spend())
    assert len(client.requests) == 3


# --- The budget cap ----------------------------------------------------------------------


def test_cost_comes_from_usage_at_the_models_price():
    used = usage(input_tokens=1_000_000, output_tokens=1_000_000, searches=10)
    tracker = spend(100.0)
    outcome = backend_with(FakeClient(message(used=used))).run(request(), tracker)
    # Opus at $4 in and $20 out per million, plus ten searches at one cent.
    assert outcome.cost_usd == pytest.approx(24.10)
    assert tracker.spent_usd == pytest.approx(24.10)


def test_cached_tokens_count_towards_the_cost():
    used = usage(input_tokens=0, output_tokens=0, cache_writes=1_000_000, cache_reads=1_000_000)
    outcome = backend_with(FakeClient(message(used=used))).run(request(), spend(100.0))
    assert outcome.cost_usd == pytest.approx(5.0 + 0.4)


def test_an_unknown_claude_model_is_priced_at_the_highest_rate():
    used = usage(input_tokens=1_000_000, output_tokens=0)
    outcome = backend_with(FakeClient(message(used=used)), model="claude-next-9").run(
        request(), spend(100.0)
    )
    assert outcome.cost_usd == pytest.approx(10.0)


def test_going_over_the_cap_discards_the_output():
    expensive = message(used=usage(input_tokens=0, output_tokens=200_000))
    with pytest.raises(BudgetExceeded):
        backend_with(FakeClient(expensive)).run(request(), spend(2.0))


def test_the_cap_covers_several_runs_and_paused_turns():
    pause = message(text_block("x"), stop_reason="pause_turn", used=usage(0, 60_000))
    client = FakeClient(pause, pause, pause)
    with pytest.raises(BudgetExceeded):
        backend_with(client).run(request("research"), spend(2.0))
    assert len(client.requests) == 2  # $1.20 then $2.40, so no third request

    tracker = spend(2.0)
    tracker.add(2.0)
    idle = FakeClient()
    with pytest.raises(BudgetExceeded):
        backend_with(idle).run(request(), tracker)
    assert idle.requests == []


def test_max_tokens_never_allows_more_output_than_the_money_left():
    client = FakeClient()
    tracker = spend(0.10)
    backend_with(client).run(request(), tracker)
    assert client.requests[0]["max_tokens"] <= 5000  # $0.10 at $20 per million


def test_too_little_money_for_a_useful_reply_starts_nothing():
    client = FakeClient()
    with pytest.raises(BudgetExceeded):
        backend_with(client).run(request(), spend(0.001))
    assert client.requests == []


def test_a_reply_with_no_usage_cannot_prove_the_cap_so_it_stops():
    reply = message()
    reply.usage = None
    with pytest.raises(BudgetExceeded, match="usage"):
        backend_with(FakeClient(reply)).run(request(), spend())


# --- SDK errors --------------------------------------------------------------------------


def api_error(kind, status, text="error text"):
    http_request = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
    response = httpx2.Response(status, request=http_request)
    return kind(text, response=response, body=None)


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (api_error(anthropic.RateLimitError, 429), UsageLimitReached),
        (
            api_error(anthropic.BadRequestError, 400, "Your credit balance is too low"),
            UsageLimitReached,
        ),
        (api_error(anthropic.AuthenticationError, 401), LoginExpired),
        (api_error(anthropic.PermissionDeniedError, 403), LoginExpired),
        (api_error(anthropic.BadRequestError, 400), LlmRunFailed),
        (api_error(anthropic.InternalServerError, 500), LlmRunFailed),
        (
            anthropic.APIConnectionError(request=httpx2.Request("POST", "https://x.example")),
            LlmRunFailed,
        ),
    ],
)
def test_sdk_errors_map_to_engine_outcomes(error, expected):
    with pytest.raises(expected):
        backend_with(FakeClient(error)).run(request(), spend())


# --- Choosing the backend ----------------------------------------------------------------


def config_for_api():
    return load_config().model_copy(update={"llm": llm_settings()})


@pytest.mark.parametrize("key", [None, "", "  "])
def test_no_key_is_refused(tmp_path, key):
    env = {} if key is None else {"ANTHROPIC_API_KEY": key}
    with pytest.raises(LlmSetupError, match="ANTHROPIC_API_KEY"):
        make_backend(config_for_api(), EnginePaths.from_root(tmp_path), env=env)


def test_a_scheduled_run_is_fine_because_the_api_always_uses_a_key(tmp_path):
    client = FakeClient()
    made = []

    def factory(key):
        made.append(key)
        return client

    backend = make_backend(
        config_for_api(),
        EnginePaths.from_root(tmp_path),
        env={"ANTHROPIC_API_KEY": "test-key"},
        scheduled=True,
        client_factory=factory,
    )
    backend.run(request(), spend())
    assert made == ["test-key"]


def test_the_real_client_ignores_a_base_url_from_the_environment(tmp_path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_BASE_URL", "https://elsewhere.example.com")
    backend = make_backend(
        config_for_api(),
        EnginePaths.from_root(tmp_path),
        env={"ANTHROPIC_API_KEY": "test-key"},
    )
    assert "api.anthropic.com" in str(backend.client.base_url)


# --- The real SDK, with a canned HTTP stream and no network -------------------------------


def _sse(*events: dict) -> bytes:
    lines = [f"event: {event['type']}\ndata: {json.dumps(event)}\n\n" for event in events]
    return "".join(lines).encode()


def test_the_real_sdk_accepts_this_request_and_this_stream():
    bodies = []

    def handler(http_request: httpx2.Request) -> httpx2.Response:
        bodies.append(json.loads(http_request.content))
        reply = {
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "content": [],
            "model": "claude-opus-5-5",
            "stop_reason": None,
            "stop_sequence": None,
            "usage": {"input_tokens": 10, "output_tokens": 1},
        }
        stream_body = _sse(
            {"type": "message_start", "message": reply},
            {
                "type": "content_block_start",
                "index": 0,
                "content_block": {"type": "text", "text": ""},
            },
            {
                "type": "content_block_delta",
                "index": 0,
                "delta": {"type": "text_delta", "text": GOOD_TEXT},
            },
            {"type": "content_block_stop", "index": 0},
            {
                "type": "message_delta",
                "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                "usage": {"output_tokens": 20},
            },
            {"type": "message_stop"},
        )
        headers = {"content-type": "text/event-stream"}
        return httpx2.Response(200, content=stream_body, headers=headers)

    client = anthropic.Anthropic(
        api_key="test-key",
        http_client=anthropic.DefaultHttpxClient(transport=httpx2.MockTransport(handler)),
    )
    outcome = AnthropicApiBackend(llm_settings(), client).run(request("research"), spend())
    assert outcome.output.passed is True
    body = bodies[0]
    assert body["model"] == "claude-opus-5-5"
    assert body["output_config"]["effort"] == "high"
    assert body["output_config"]["format"]["type"] == "json_schema"
    assert [tool["type"] for tool in body["tools"]] == ["web_search_20260209", "web_fetch_20260209"]
    assert body["thinking"] == {"type": "adaptive"}
    assert body["stream"] is True
