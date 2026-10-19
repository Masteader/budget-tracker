"""Shared utility functions for route handlers."""

import hashlib
import hmac
import logging
import os
import uuid as _uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status

logger = logging.getLogger(__name__)

# Saudi Arabia is UTC+3 all year (no DST since 1979). A fixed offset avoids a runtime dependency
# on the tzdata package in slim containers and matches Postgres' AT TIME ZONE 'Asia/Riyadh'.
RIYADH_TZ = timezone(timedelta(hours=3), "Asia/Riyadh")


def utc_now() -> datetime:
    """Current UTC time (single seam for tests)."""
    return datetime.now(timezone.utc)


def riyadh_today() -> date:
    """
    Today's calendar date in Riyadh. Salary cycles are defined on Riyadh dates (the DB function
    get_saudi_cycle_for_timestamp converts to Asia/Riyadh); using the UTC date reported the
    previous cycle between 00:00 and 03:00 Riyadh time on payday.
    """
    return utc_now().astimezone(RIYADH_TZ).date()


def riyadh_date_for_timestamp(ts: Optional[str | datetime]) -> date:
    """Riyadh calendar date of an ISO-8601 timestamp (naive values are treated as UTC)."""
    if ts is None or ts == "":
        return riyadh_today()
    dt = ts if isinstance(ts, datetime) else datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(RIYADH_TZ).date()


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


_NON_PRODUCTION_ENVS = {"development", "dev", "local", "test", "testing"}


def is_production() -> bool:
    """
    True unless ENV explicitly names a development/test environment.

    Security-relevant relaxations (unsigned requests, quota fail-open, public API docs) must
    require an explicit opt-in: previously a deployment that simply forgot to set ENV ran in
    "development" mode and accepted unsigned requests when WEBHOOK_SECRET was empty.
    """
    return os.environ.get("ENV", "").strip().lower() not in _NON_PRODUCTION_ENVS


def _trusted_proxies() -> set[str]:
    raw = os.environ.get("TRUSTED_PROXY_IPS", "127.0.0.1,::1")
    return {p.strip() for p in raw.split(",") if p.strip()}


def get_client_ip(request) -> str:
    """
    Client IP for rate limiting. X-Forwarded-For is honoured only when the direct peer is a
    configured trusted proxy (TRUSTED_PROXY_IPS, default loopback); otherwise any caller could
    rotate the header to get a fresh rate-limit bucket per request. With a trusted proxy the
    rightmost entry (appended by that proxy) is used.
    """
    peer = request.client.host if request.client and request.client.host else ""
    xff = request.headers.get("X-Forwarded-For")
    if xff and peer in _trusted_proxies():
        parts = [p.strip() for p in xff.split(",") if p.strip()]
        if parts:
            return parts[-1]
    return peer or "unknown"


def verify_signature(body: bytes, signature_header: str | None) -> bool:
    """
    Return True if the HMAC-SHA256 signature matches, or if no secret is configured in an
    explicitly non-production ENV.

    NOTE: this is an integrity check, not authentication. The same WEBHOOK_SECRET is compiled
    into the mobile app and is extractable from the APK; callers are authenticated by the
    per-user Supabase JWT that every protected route verifies.
    """
    webhook_secret = os.environ.get("WEBHOOK_SECRET", "").strip()

    if not webhook_secret:
        if is_production():
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
