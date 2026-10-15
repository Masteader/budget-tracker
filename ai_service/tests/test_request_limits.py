"""Tests for request body size limits."""
import os
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_oversized_request_rejected():
    """Requests exceeding MAX_REQUEST_BODY_BYTES should return 413."""
    oversized_body = "x" * (11 * 1024 * 1024)  # 11MB
    response = client.post(
        "/agent/chat-transaction",
        content=oversized_body,
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413


def test_normal_sized_request_accepted():
    """Normal-sized requests should not be blocked by size limits."""
    response = client.get("/health")
    assert response.status_code == 200
