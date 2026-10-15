"""Shared utility functions for route handlers."""

import hashlib
import hmac
import logging
import os
import uuid as _uuid
from uuid import UUID

from fastapi import HTTPException, status

logger = logging.getLogger(__name__)


def safe_error_response(
    exc: Exception,
    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR,
    public_message: str = "An internal error occurred.",
) -> HTTPException:
    """
    Create an HTTPException that logs the full error server-side
    but returns only a generic message + correlation ID to the client.
    """
    ref_id = _uuid.uuid4().hex[:12]
    logger.error("Error ref=%s: %s", ref_id, exc, exc_info=True)
    return HTTPException(
        status_code=status_code,
        detail=f"{public_message} Reference: {ref_id}",
    )


def validate_uuid(value: str, field_name: str = "household_id") -> str:
    """Validate a string is a valid UUID. Raises HTTPException(400) if not."""
    try:
        UUID(value)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid {field_name}: must be a valid UUID.",
        )
    return value


def verify_signature(body: bytes, signature_header: str | None) -> bool:
    """Return True if the HMAC-SHA256 signature matches, or if no secret is configured in dev."""
    webhook_secret = os.environ.get("WEBHOOK_SECRET", "").strip()
    is_production = os.environ.get("ENV", "development").lower() == "production"

    if not webhook_secret:
        if is_production:
            logger.error("WEBHOOK_SECRET is not set in production — rejecting request.")
            return False
        logger.warning("WEBHOOK_SECRET not set — skipping signature verification (dev mode).")
        return True

    if not signature_header:
        return False

    try:
        scheme, provided_sig = signature_header.split("=", 1)
        if scheme != "sha256":
            return False
        expected_sig = hmac.new(webhook_secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(provided_sig, expected_sig)
    except Exception:
        return False
