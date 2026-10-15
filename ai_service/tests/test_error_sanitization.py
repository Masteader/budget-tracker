"""Tests that internal errors don't leak exception details to API callers."""
import os
from unittest.mock import patch
from fastapi.testclient import TestClient

os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")


def test_500_error_does_not_leak_exception_message():
    """Internal errors should return a generic message, not str(exc)."""
    from main import app
    client = TestClient(app)

    with patch("routes.budgets.get_cycle_breakdown", side_effect=RuntimeError("Connection to database failed at 10.0.0.5:5432")):
        response = client.get("/budgets/breakdown", params={"household_id": "f860188e-23b5-4749-b180-868c956151a6"})
        assert response.status_code == 500
        data = response.json()
        # Must NOT contain the internal error details
        assert "10.0.0.5" not in data.get("detail", "")
        assert "database" not in data.get("detail", "").lower()
        # Should contain a reference ID for debugging
        assert "reference" in data.get("detail", "").lower() or "ref" in data.get("detail", "").lower()
