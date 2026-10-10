import pytest
from unittest.mock import patch, MagicMock
from httpx import AsyncClient, ASGITransport
from main import app
from support_agent import handle_support_query

@pytest.mark.asyncio
async def test_support_chat_general_faq():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.post("/support/chat", json={
            "message": "How does the salary cycle work in this app?",
            "household_id": "test-house-1",
            "language": "en",
        })
    assert res.status_code == 200
    data = res.json()
    assert "reply" in data
    assert data["support_email"] == "fmscoinfo@fmsco.com.sa"
    assert data["escalate_to_developer"] is False

@pytest.mark.asyncio
async def test_support_chat_bug_escalation():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.post("/support/chat", json={
            "message": "The app crashed when scanning invoice, please fix this bug or let me talk to developer",
            "household_id": "test-house-1",
            "language": "en",
        })
    assert res.status_code == 200
    data = res.json()
    assert data["escalate_to_developer"] is True
    assert data["summary"] is not None

@pytest.mark.asyncio
async def test_support_chat_with_litellm_mock():
    fake_choice = MagicMock()
    fake_choice.message.content = "[ESCALATE: FALSE]\n[SUMMARY: NONE]\nThis is a mock AI response in Urdu."
    fake_res = MagicMock()
    fake_res.choices = [fake_choice]

    with patch("support_agent.litellm.completion", return_value=fake_res):
        reply, escalate, summary = await handle_support_query(
            message="تنخواہ کا دن کب ہے؟",
            language="ur",
        )
        assert escalate is False
        assert summary is None
        assert "This is a mock AI response in Urdu." in reply

@pytest.mark.asyncio
async def test_support_chat_litellm_failure_graceful_fallback():
    with patch("support_agent.litellm.completion", side_effect=RuntimeError("API Quota exceeded")):
        reply_en, escalate_en, _ = await handle_support_query(
            message="How do I scan a receipt?",
            language="en",
        )
        assert escalate_en is False
        assert "Welcome to Budget Tracker Support!" in reply_en

        reply_ur, escalate_ur, _ = await handle_support_query(
            message="کیسے استعمال کریں؟",
            language="ur",
        )
        assert escalate_ur is False
        assert "بجٹ ٹریکر سپورٹ میں خوش آمدید" in reply_ur

