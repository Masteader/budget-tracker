"""Tests for chat intent scoping, off-topic detection, and 3-strike 15-minute lockout."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

from main import app
from rate_limiter import reset_rate_limiters, reset_offtopic_strikes
from chat_parser import ParsedChatExpense

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


def test_off_topic_message_triggers_strike_1_warning():
    res = client.post(
        "/agent/chat-transaction",
        json={"message": "tell me a bedtime story about dragons", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res.status_code == 200, res.text
    data = res.json()
    assert data.get("status") == "off_topic_warning"
    assert data.get("strikes") == 1
    assert data.get("max_strikes") == 3
    assert "warning" in data.get("message", "").lower() or "تنبيه" in data.get("message", "") or "مخصص" in data.get("message", "")


def test_off_topic_strike_progression_to_strike_3_lockout():
    # Strike 1
    res1 = client.post(
        "/agent/chat-transaction",
        json={"message": "tell me a bedtime story about dragons", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res1.status_code == 200
    assert res1.json().get("strikes") == 1

    # Strike 2
    res2 = client.post(
        "/agent/chat-transaction",
        json={"message": "what is the weather in Riyadh?", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res2.status_code == 200
    assert res2.json().get("strikes") == 2
    assert res2.json().get("status") == "off_topic_warning"

    # Strike 3 -> 429 Lockout
    res3 = client.post(
        "/agent/chat-transaction",
        json={"message": "write a python script to parse html", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res3.status_code == 429
    detail = res3.json().get("detail", {})
    if isinstance(detail, dict):
        assert detail.get("code") == "chat_locked_out"
        assert detail.get("retry_after_seconds", 0) > 0
    else:
        assert "locked" in str(detail).lower() or "limit" in str(detail).lower()


def test_locked_out_user_is_blocked_immediately_on_subsequent_request():
    # Trigger 3 strikes
    for msg in ["story", "weather", "poem"]:
        client.post(
            "/agent/chat-transaction",
            json={"message": msg, "household_id": HH_ID},
            headers={"Authorization": "Bearer mock-token"},
        )

    # Next attempt (even valid expense) should be blocked immediately with 429
    res = client.post(
        "/agent/chat-transaction",
        json={"message": "Panda 50 SAR", "household_id": HH_ID},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res.status_code == 429
    detail = res.json().get("detail", {})
    assert isinstance(detail, dict)
    assert detail.get("code") == "chat_locked_out"
    assert detail.get("retry_after_seconds", 0) > 0


def test_legitimate_expense_does_not_trigger_strike():
    res = client.post(
        "/agent/chat-transaction",
        json={"message": "عبيت بنزين 91 بـ 60 ريال من ساسكو", "household_id": HH_ID, "preview_only": True},
        headers={"Authorization": "Bearer mock-token"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data.get("status") != "off_topic_warning"
    assert data.get("amount") == 60.0

