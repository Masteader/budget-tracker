import pytest
from httpx import AsyncClient, ASGITransport
from main import app

@pytest.mark.asyncio
async def test_support_chat_general_faq():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.post("/support/chat", json={
            "message": "How does the salary cycle work in this app?",
            "household_id": "test-house-1",
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
        })
    assert res.status_code == 200
    data = res.json()
    assert data["escalate_to_developer"] is True
    assert data["summary"] is not None
