"""Tests for JWT-based household authorization."""
import asyncio
import os
import pytest
from unittest.mock import patch, MagicMock
from fastapi import HTTPException

# Ensure test env is configured before import
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")


@pytest.mark.asyncio
async def test_missing_authorization_header_raises_401():
    """Requests without Authorization header must be rejected."""
    from auth import verify_household_access
    from fastapi import Request

    mock_request = MagicMock(spec=Request)
    mock_request.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await verify_household_access(mock_request, "f860188e-23b5-4749-b180-868c956151a6")
    assert exc_info.value.status_code == 401


def test_mismatched_household_raises_403():
    """User requesting data for a household they don't belong to must get 403."""
    from auth import _check_household_membership

    # User belongs to household-A but requests household-B
    with pytest.raises(HTTPException) as exc_info:
        _check_household_membership(
            user_household_id="household-A",
            requested_household_id="household-B",
        )
    assert exc_info.value.status_code == 403


def test_matching_household_passes():
    """User requesting their own household data should pass."""
    from auth import _check_household_membership

    # Should not raise
    _check_household_membership(
        user_household_id="household-A",
        requested_household_id="household-A",
    )
