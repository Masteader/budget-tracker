"""Tests for UUID validation on household_id parameters."""
import os
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_invalid_household_id_rejected():
    """Non-UUID household_id should return 422 or 400."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "not-a-uuid; DROP TABLE transactions;--"},
    )
    assert response.status_code in (400, 422)


def test_valid_uuid_household_id_accepted():
    """Valid UUID should pass validation (may fail for other reasons)."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "f860188e-23b5-4749-b180-868c956151a6"},
    )
    # Should not be a validation error
    assert response.status_code != 422
