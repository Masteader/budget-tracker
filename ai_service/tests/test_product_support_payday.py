"""
Product review 3.1 / "Stop doing": the support chatbot hard-coded a 27th payday and a 400 SAR
Iqama fee. It now reads the household's payday (households.payday_day) when the route passes a
household (membership already verified) and otherwise speaks generically; no fee amounts.
"""
from __future__ import annotations

import types

import pytest
from fastapi.testclient import TestClient

import supabase_client
import support_agent
from main import app

HID = "f860188e-23b5-4749-b180-868c956151a6"


class Capture:
    def __init__(self, monkeypatch):
        self.messages = None

        def completion(*_a, **kwargs):
            self.messages = kwargs["messages"]
            msg = types.SimpleNamespace(content="[ESCALATE: FALSE]\n[SUMMARY: NONE]\nok")
            return types.SimpleNamespace(choices=[types.SimpleNamespace(message=msg)])

        monkeypatch.setattr(support_agent.litellm, "completion", completion)

    @property
    def system(self) -> str:
        return self.messages[0]["content"]


def test_no_hard_coded_payday_or_fee_in_the_sources():
    for lang in ("ar", "en", "ur"):
        for text in (support_agent.SUPPORT_SYSTEM_PROMPTS[lang], support_agent.FALLBACK_MESSAGES[lang]["general"],
                     support_agent.PAYDAY_FACTS[lang]["generic"], support_agent.BILLS_FACTS[lang]):
            assert "27" not in text and "400" not in text, (lang, text)
            assert "Iqama" not in text and "اقامہ" not in text and "إقامة" not in text


@pytest.mark.asyncio
@pytest.mark.parametrize("lang", ["ar", "en", "ur"])
async def test_without_household_the_prompt_is_generic(monkeypatch, lang):
    llm = Capture(monkeypatch)
    await support_agent.handle_support_query("When is payday?", household_id=None, language=lang)
    assert "27" not in llm.system and "400" not in llm.system
    assert support_agent.PAYDAY_FACTS[lang]["generic"] in llm.system


@pytest.mark.asyncio
@pytest.mark.parametrize("lang", ["ar", "en", "ur"])
async def test_household_payday_is_read_from_the_database(fake_supabase, monkeypatch, lang):
    fake_supabase.seed("households", [{"id": HID, "payday_day": 10}])
    llm = Capture(monkeypatch)
    await support_agent.handle_support_query("When is payday?", household_id=HID, language=lang)
    assert support_agent.PAYDAY_FACTS[lang]["known"].format(day=10) in llm.system
    assert "27" not in llm.system


@pytest.mark.asyncio
async def test_database_failure_answers_generically(monkeypatch):
    def unreachable():
        raise ConnectionError("down")

    monkeypatch.setattr(supabase_client, "get_client", unreachable)
    llm = Capture(monkeypatch)
    reply, escalate, _ = await support_agent.handle_support_query("payday?", household_id=HID, language="en")
    assert reply == "ok" and escalate is False
    assert support_agent.PAYDAY_FACTS["en"]["generic"] in llm.system


@pytest.mark.asyncio
async def test_fallback_reply_uses_the_household_payday(fake_supabase, monkeypatch):
    fake_supabase.seed("households", [{"id": HID, "payday_day": 1}])

    def broken(*_a, **_k):
        raise RuntimeError("quota")

    monkeypatch.setattr(support_agent.litellm, "completion", broken)
    reply, _, _ = await support_agent.handle_support_query("hello", household_id=HID, language="en")
    assert "day 1 of each month" in reply
    reply, _, _ = await support_agent.handle_support_query("hello", household_id=None, language="en")
    assert "27" not in reply and "of each month" not in reply


def test_route_passes_the_verified_household(fake_supabase, monkeypatch):
    fake_supabase.seed("households", [{"id": HID, "payday_day": 5}])
    llm = Capture(monkeypatch)
    res = TestClient(app).post("/support/chat", json={"message": "payday?", "household_id": HID, "language": "en"})
    assert res.status_code == 200, res.text
    assert "day 5 of each month" in llm.system
