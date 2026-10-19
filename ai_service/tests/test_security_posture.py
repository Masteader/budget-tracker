"""Comprehensive verification of security hardening across the AI service."""
import os
import pytest
from fastapi.testclient import TestClient

# Leaked values are never stored raw; any stale/unknown token must be rejected.
OLD_LEAKED_SECRET = "stale-webhook-secret-value-not-configured"
OLD_LEAKED_TOKEN = "stale-app-token-value-not-configured"

@pytest.fixture(autouse=True, scope="module")
def setup_security_posture_env():
    orig_env = os.environ.get("ENV")
    orig_secret = os.environ.get("WEBHOOK_SECRET")
    orig_token = os.environ.get("APP_AUTH_TOKEN")

    os.environ["WEBHOOK_SECRET"] = "new_secure_test_secret_32bytes_value"
    os.environ["APP_AUTH_TOKEN"] = "new_secure_app_token_value"
    os.environ["ENV"] = "production"

    yield

    if orig_env is not None:
        os.environ["ENV"] = orig_env
    else:
        os.environ.pop("ENV", None)

    if orig_secret is not None:
        os.environ["WEBHOOK_SECRET"] = orig_secret
    else:
        os.environ.pop("WEBHOOK_SECRET", None)

    if orig_token is not None:
        os.environ["APP_AUTH_TOKEN"] = orig_token
    else:
        os.environ.pop("APP_AUTH_TOKEN", None)


from main import app

client = TestClient(app)


def test_old_leaked_token_rejected_when_rotated():
    """Requests with the old leaked token must be rejected in production on protected routes."""
    response_protected = client.get(
        "/budgets/cycles?household_id=f860188e-23b5-4749-b180-868c956151a6",
        headers={"X-Forwarded-For": "1.2.3.4", "X-App-Token": OLD_LEAKED_TOKEN},
    )
    assert response_protected.status_code == 403


def test_oversized_payload_rejected_with_413():
    """Payloads exceeding 10MB limit must receive 413."""
    oversized = "a" * (11 * 1024 * 1024)
    response = client.post(
        "/agent/chat-transaction",
        content=oversized,
        headers={"Content-Type": "application/json", "X-App-Token": "new_secure_app_token_value"},
    )
    assert response.status_code == 413


def test_unauthenticated_household_endpoint_rejected_with_401():
    """Household endpoints require Authorization header."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "f860188e-23b5-4749-b180-868c956151a6"},
        headers={"X-App-Token": "new_secure_app_token_value"},
    )
    assert response.status_code in (401, 403)


def test_non_uuid_household_rejected():
    """Non-UUID values must return 400 or 422."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "malicious-injection-string"},
        headers={"X-App-Token": "new_secure_app_token_value", "Authorization": "Bearer test"},
    )
    assert response.status_code in (400, 422)


def test_sms_webhook_returns_404():
    """Dead SMS webhook must return 404."""
    response = client.post("/webhook/sms", json={})
    assert response.status_code in (404, 405)
