"""Shared utility functions for route handlers."""

import hashlib
import hmac
import logging
import math
import os
import re
import uuid as _uuid
from datetime import date, datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
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


def bounded_text(body: dict, field: str, max_length: int) -> Optional[str]:
    """
    Optional free-text field of a JSON body: None when absent, else a string of at most
    ``max_length`` characters, otherwise HTTP 422 (FABLE-API-06: overrides were stored verbatim,
    up to ~24 MiB per row).
    """
    value = body.get(field)
    if value is None:
        return None
    if not isinstance(value, str):
        raise HTTPException(status_code=422, detail=f"{field} must be text.")
    if len(value) > max_length:
        raise HTTPException(status_code=422, detail=f"{field} must be at most {max_length} characters.")
    return value


MAX_EXPENSE_AMOUNT = Decimal("10000000")


def optional_amount(body: dict, field: str = "amount") -> Optional[float]:
    """
    Optional user-corrected expense amount of a JSON body (UX-12): None when absent, else a
    positive number of at most 10,000,000 SAR rounded to halalas, otherwise HTTP 422. Booleans,
    text, NaN and infinities are refused.
    """
    value = body.get(field)
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise HTTPException(status_code=422, detail=f"{field} must be a number.")
    if not math.isfinite(value):
        raise HTTPException(status_code=422, detail=f"{field} must be a finite number.")
    amount = Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if amount <= 0 or amount > MAX_EXPENSE_AMOUNT:
        raise HTTPException(status_code=422, detail=f"{field} must be more than 0 and at most 10,000,000.")
    return float(amount)


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


# The one LiteLLM model used when LITELLM_MODEL is unset (chat, receipt scanning and support
# used to fall back to three different models). Keep .env.example and docker-compose.yml in step.
DEFAULT_LITELLM_MODEL = "gemini/gemini-3.6-flash-lite"


def litellm_model() -> str:
    """LITELLM_MODEL when set (read per call, so a redeploy-free env change applies), else the default."""
    return os.environ.get("LITELLM_MODEL", "").strip() or DEFAULT_LITELLM_MODEL


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


_TRUE_ENV = {"1", "true", "yes", "on"}
_FALSE_ENV = {"0", "false", "no", "off"}


def trust_proxy_headers() -> bool:
    """
    Whether X-Forwarded-For from any peer is trusted (FABLE-API-03). TRUST_PROXY_HEADERS=1/0
    decides explicitly; unset, it is on when running on Railway (RAILWAY_ENVIRONMENT or
    RAILWAY_ENVIRONMENT_NAME is set), whose edge proxy is the only way into the service and
    appends the connecting client's address to X-Forwarded-For. Railway's edge addresses are not
    static, so TRUSTED_PROXY_IPS cannot list them.
    """
    explicit = os.environ.get("TRUST_PROXY_HEADERS", "").strip().lower()
    if explicit in _TRUE_ENV:
        return True
    if explicit in _FALSE_ENV:
        return False
    return bool(os.environ.get("RAILWAY_ENVIRONMENT") or os.environ.get("RAILWAY_ENVIRONMENT_NAME"))


def _trusted_proxy_hops() -> int:
    """Proxies that append to X-Forwarded-For in front of the app (TRUSTED_PROXY_HOPS, default 1)."""
    try:
        return min(5, max(1, int(os.environ.get("TRUSTED_PROXY_HOPS", "1"))))
    except ValueError:
        return 1


def _parse_ip(value: str):
    import ipaddress

    try:
        return ipaddress.ip_address(value.strip())
    except ValueError:
        return None


def client_ip_info(request) -> tuple[str, bool]:
    """
    ``(client_ip, reliable)`` for rate limiting. X-Forwarded-For is honoured when the direct peer
    is a configured trusted proxy (TRUSTED_PROXY_IPS, default loopback) or proxy headers are
    trusted (trust_proxy_headers); the client is the entry the trusted proxies appended: the
    TRUSTED_PROXY_HOPS-th from the right (anything left of it is client-supplied and spoofable).
    ``reliable`` is False when the address is not the client's own (an untrusted private or
    loopback proxy hop, or no address at all): one such address is shared by every visitor, so
    callers must not lock it out as if it were one person.
    """
    peer = request.client.host if request.client and request.client.host else ""
    xff = request.headers.get("X-Forwarded-For")
    if xff and (peer in _trusted_proxies() or trust_proxy_headers()):
        parts = [p.strip() for p in xff.split(",") if p.strip()]
        hops = _trusted_proxy_hops()
        if parts:
            candidate = parts[-hops] if len(parts) >= hops else parts[0]
            if _parse_ip(candidate) is not None:
                return candidate, True
    ip = _parse_ip(peer)
    if ip is not None and not (ip.is_private or ip.is_loopback or ip.is_link_local):
        return peer, True
    return peer or "unknown", False


def get_client_ip(request) -> str:
    """Client IP for rate limiting (see client_ip_info)."""
    return client_ip_info(request)[0]


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


# ─── Audit notes (transactions.raw_sms) ─────────────────────────────────────────
# The note is for humans. Money attribution lives in structured columns (spent_by,
# beneficiary_type, beneficiary_id); legacy rows written before that kept it in "Tag: value"
# parts of the note, so user text placed in a note must never look like a tag (FABLE-API-01).
AUDIT_TAG_KEYWORDS = ("paid by", "beneficiary", "spent by", "recipient", "items", "method", "note")
_AUDIT_TAG_RE = re.compile(
    r"(?:paid\s*by|beneficiary|spent\s*by|recipient|items|method|note)\s*:\s*", re.IGNORECASE
)


def sanitize_audit_text(value: object, limit: int = 500) -> str:
    """
    User text made safe for an audit note: no control characters, no ``|`` separator (becomes
    ``/``) and no ``<tag>:`` keyword (removed until none is left, so nested spellings such as
    ``PaiPaidBy:dBy:`` cannot reassemble one), whitespace collapsed, at most ``limit`` characters.
    """
    text = "".join(ch if ch.isprintable() else " " for ch in str(value or ""))
    text = text.replace("|", "/")
    while True:
        cleaned = _AUDIT_TAG_RE.sub("", text)
        if cleaned == text:
            break
        text = cleaned
    return " ".join(text.split())[:limit]


def build_audit_note(paid_by: str, beneficiary: str, spent_by: str, *parts: str) -> str:
    """
    ``PaidBy: … | Beneficiary: … | SpentBy: … | <parts>``: the server's tags first, then the
    caller's (already sanitised) descriptive parts. Tag values are sanitised too.
    """
    head = (
        f"PaidBy: {sanitize_audit_text(paid_by, 60)} | Beneficiary: {sanitize_audit_text(beneficiary, 60)} "
        f"| SpentBy: {sanitize_audit_text(spent_by, 20)}"
    )
    tail = [p for p in parts if p]
    return " | ".join([head, *tail])
