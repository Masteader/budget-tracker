"""A backend that replays canned outcomes, for tests above the subprocess boundary."""

from __future__ import annotations

from content_engine.llm_backends import LlmRequest, LlmResult, SpendTracker


class ScriptedBackend:
    """Each step is an exception to raise or an `LlmResult` to return. Runs out loudly."""

    def __init__(self, *steps) -> None:
        self.steps = list(steps)
        self.requests: list[LlmRequest] = []

    def run(self, request: LlmRequest, spend: SpendTracker) -> LlmResult:
        self.requests.append(request)
        step = self.steps.pop(0)
        if isinstance(step, Exception):
            raise step
        return step
