"""Tests confirming the SMS webhook endpoint has been removed."""
import os
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_sms_webhook_endpoint_removed():
    """POST /webhook/sms should return 404 (or 405) since SMS feature is removed."""
    response = client.post("/webhook/sms", json={"raw_sms": "test", "sender": "SNB", "received_at": "2026-01-01", "household_id": "test"})
    assert response.status_code in (404, 405)


def test_health_still_works():
    """Health endpoint must still work after SMS removal."""
    response = client.get("/health")
    assert response.status_code == 200
