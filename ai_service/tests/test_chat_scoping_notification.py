"""Tests for developer notification email dispatch on Strike 3 lockout."""

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


def test_strike_3_dispatches_email_alert_to_developer():
    with patch("routes.chat.send_email", new_callable=AsyncMock) as mock_send_email:
        # Strike 1
        client.post(
            "/agent/chat-transaction",
            json={"message": "tell me a story", "household_id": HH_ID},
            headers={"Authorization": "Bearer mock-token"},
        )
        assert mock_send_email.call_count == 0

        # Strike 2
        client.post(
            "/agent/chat-transaction",
            json={"message": "what is the weather?", "household_id": HH_ID},
            headers={"Authorization": "Bearer mock-token"},
        )
        assert mock_send_email.call_count == 0

        # Strike 3 -> triggers email and 429
        res3 = client.post(
            "/agent/chat-transaction",
            json={"message": "write python code", "household_id": HH_ID},
            headers={"Authorization": "Bearer mock-token"},
        )
        assert res3.status_code == 429
        assert mock_send_email.call_count == 1

        call_args = mock_send_email.call_args
        email_msg = call_args[0][0]
        to_override = call_args[1].get("to_override") or (call_args[0][1] if len(call_args[0]) > 1 else None)

        assert to_override == "fmscoinfo@fmsco.com.sa"
        assert "Lockout" in email_msg.subject or "Violation" in email_msg.subject
        assert USER_ID in email_msg.body
        assert "write python code" in email_msg.body
