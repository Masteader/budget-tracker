"""Tests for in-chat app guidance routing and action descriptors."""

from __future__ import annotations

import pytest
from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient

from main import app
from rate_limiter import reset_rate_limiters, reset_offtopic_strikes

client = TestClient(app)
HH_ID = "00000000-0000-4000-8000-000000000001"
USER_ID = "00000000-0000-0000-0000-000000000001"


@pytest.fixture(autouse=True)
def cleanup():
    reset_rate_limiters()
    reset_offtopic_strikes()
    yield
    reset_rate_limiters()
    reset_offtopic_strikes()


def test_app_guidance_payday_question_returns_actions_and_no_strike():
    res = client.post(
        "/agent/chat-transaction",
        json={"message": "كيف اضبط دورة الراتب في التطبيق؟", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data.get("status") == "app_guidance"
    assert data.get("intent") == "app_guidance"
    assert data.get("message") is not None
    assert len(data.get("message")) > 0

    actions = data.get("actions", [])
    action_ids = [a.get("id") for a in actions]
    assert "open_tutor" in action_ids
    assert "open_payday" in action_ids


def test_app_guidance_nafaqah_question_returns_household_actions():
    res = client.post(
        "/agent/chat-transaction",
        json={"message": "explain Islamic nafaqah rules in family mode", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data.get("status") == "app_guidance"
    actions = data.get("actions", [])
    action_ids = [a.get("id") for a in actions]
    assert "open_tutor" in action_ids
    assert "open_roles" in action_ids
