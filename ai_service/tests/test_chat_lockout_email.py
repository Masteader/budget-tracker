"""Tests for chat lockout alert privacy controls (Item 11)."""

import os
import time
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from jose import jwt
import pytest

from main import app
from rate_limiter import reset_offtopic_strikes

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"


def bearer(sub: str, email: str | None = None) -> dict:
    now = int(time.time())
    claims = {
        "sub": sub,
        "aud": "authenticated",
        "iss": ISSUER,
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    if email:
        claims["email"] = email
    token = jwt.encode(claims, TEST_SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(autouse=True)
def clear_strikes():
    reset_offtopic_strikes()
    yield
    reset_offtopic_strikes()


@pytest.fixture
def client():
    return TestClient(app)


def test_lockout_email_not_sent_when_env_unset(client):
    user_id = "11111111-1111-4111-8111-111111111111"
    household_id = "22222222-2222-4222-8222-222222222222"
    headers = bearer(user_id, email="victim@example.com")

    payload = {
        "message": "tell me a funny bedtime joke",
        "household_id": household_id,
    }

    env = dict(os.environ)
    env.pop("ABUSE_ALERT_EMAIL", None)

    with patch.dict(os.environ, env, clear=True), patch("routes.chat.send_email", new_callable=AsyncMock) as mock_send, \
         patch("chat_parser.process_chat_transaction", return_value={"status": "off_topic", "intent": "off_topic", "message": "offtopic"}), \
         patch("routes.chat.verify_household_access", return_value={"household_id": household_id}):

        # Trigger strikes 1, 2, and 3
        client.post("/agent/chat-transaction", json=payload, headers=headers)
        client.post("/agent/chat-transaction", json=payload, headers=headers)
        resp = client.post("/agent/chat-transaction", json=payload, headers=headers)

        assert resp.status_code == 429
        assert resp.json()["detail"]["code"] == "chat_locked_out"
        mock_send.assert_not_called()


def test_lockout_email_sent_without_pii_when_env_set(client):
    user_id = "11111111-1111-4111-8111-111111111111"
    household_id = "22222222-2222-4222-8222-222222222222"
    user_email = "sensitive_owner@private-domain.sa"
    headers = bearer(user_id, email=user_email)

    payload = {
        "message": "what is the recipe for chocolate cake?",
        "household_id": household_id,
    }

    env = dict(os.environ)
    env["ABUSE_ALERT_EMAIL"] = "security-alerts@internal.local"

    with patch.dict(os.environ, env, clear=True), patch("routes.chat.send_email", new_callable=AsyncMock) as mock_send, \
         patch("chat_parser.process_chat_transaction", return_value={"status": "off_topic", "intent": "off_topic", "message": "offtopic"}), \
         patch("routes.chat.verify_household_access", return_value={"household_id": household_id}):

        client.post("/agent/chat-transaction", json=payload, headers=headers)
        client.post("/agent/chat-transaction", json=payload, headers=headers)
        resp = client.post("/agent/chat-transaction", json=payload, headers=headers)

        assert resp.status_code == 429
        assert resp.json()["detail"]["code"] == "chat_locked_out"

        mock_send.assert_called_once()
        call_email = mock_send.call_args[0][0]
        to_override = mock_send.call_args[1].get("to_override")

        assert to_override == "security-alerts@internal.local"
        assert user_id not in call_email.body
        assert user_email not in call_email.body
        assert user_id not in call_email.subject
        assert user_email not in call_email.subject
        assert household_id not in call_email.body
