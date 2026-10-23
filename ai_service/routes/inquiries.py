"""
Contact, support and VIP early-access inquiries, delivered by email to the developer.

- POST /public/inquiries   anonymous (web app, landing pages). Honeypot + per-IP, per-email
                           and global rate limits.
- POST /support/inquiries  in-app support/escalation. The sender identity comes only from the
                           verified Supabase JWT; the body cannot name a user or email.

A request answers 200 only after the email provider accepted the message. With no provider
configured the endpoint answers 503 and logs an error; it never pretends to have sent.
"""

from __future__ import annotations

import hashlib
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Iterable, Literal, Optional

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

import mail_service
from auth import get_verified_claims
from rate_limiter import default_rate_limiter
from supabase_client import get_client
from utils import client_ip_info, validate_uuid

logger = logging.getLogger(__name__)

router = APIRouter(tags=["inquiries"])

HOUR = 3600
PUBLIC_PER_IP_LIMIT = 5
PUBLIC_PER_EMAIL_LIMIT = 3
APP_PER_USER_LIMIT = 5
GLOBAL_LIMIT = 200  # caps mailbox flooding from many IPs

MAX_EMAIL = 254
MAX_NAME = 100
MAX_MESSAGE = 4000

TYPE_LABELS = {
    "vip_early_access": "VIP early access",
    "support": "Support",
    "contact": "Contact",
}

# Deliberately stricter than RFC 5322: no quotes, spaces, commas, angle brackets or line breaks,
# so the value is always safe as a Reply-To header and in a subject line.
_EMAIL_RE = re.compile(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r"@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$"
)
_LOCALE_RE = re.compile(r"^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$")
# C0/C1 control characters except tab and newline.
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")
_LINE_BREAKS_RE = re.compile(r"[\r\n\t  ]+")


def normalize_email(value: str) -> str:
    value = value.strip()
    if len(value) > MAX_EMAIL or not _EMAIL_RE.match(value):
        raise ValueError("must be a valid email address")
    local, domain = value.rsplit("@", 1)
    if len(local) > 64:
        raise ValueError("must be a valid email address")
    return f"{local}@{domain.lower()}"


def _single_line(value: str) -> str:
    value = _LINE_BREAKS_RE.sub(" ", value)
    value = _CONTROL_RE.sub("", value)
    return re.sub(r" {2,}", " ", value).strip()


def _multi_line(value: str) -> str:
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    return _CONTROL_RE.sub("", value).strip()


def check_locale(value: Optional[str]) -> Optional[str]:
    if value is None or value == "":
        return None
    if not _LOCALE_RE.match(value):
        raise ValueError("must be a language code such as 'ar' or 'en'")
    return value


class PublicInquiry(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["vip_early_access", "support", "contact"]
    email: str = Field(..., max_length=MAX_EMAIL + 8)
    name: Optional[str] = Field(None, max_length=MAX_NAME)
    message: Optional[str] = Field(None, max_length=MAX_MESSAGE)
    locale: Optional[str] = Field(None, max_length=16)
    source: Literal["web", "landing", "app"] = "web"
    # Honeypot: hidden from people, filled by naive bots.
    company_website: Optional[str] = Field(None, max_length=500)

    @field_validator("email")
    @classmethod
    def _check_email(cls, v: str) -> str:
        return normalize_email(v)

    @field_validator("locale")
    @classmethod
    def _check_locale(cls, v: Optional[str]) -> Optional[str]:
        return check_locale(v)

    @field_validator("name")
    @classmethod
    def _clean_name(cls, v: Optional[str]) -> Optional[str]:
        return (_single_line(v) or None) if v is not None else None

    @field_validator("message")
    @classmethod
    def _clean_message(cls, v: Optional[str]) -> Optional[str]:
        return (_multi_line(v) or None) if v is not None else None

    @model_validator(mode="after")
    def _message_required_for_support(self) -> "PublicInquiry":
        if self.type in ("support", "contact") and not self.message:
            raise ValueError("message is required for support and contact inquiries")
        return self


class AppSupportInquiry(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: str = Field(..., min_length=1, max_length=MAX_MESSAGE)
    locale: Optional[str] = Field(None, max_length=16)
    household_id: Optional[str] = Field(None, max_length=36)

    @field_validator("locale")
    @classmethod
    def _check_locale(cls, v: Optional[str]) -> Optional[str]:
        return check_locale(v)

    @field_validator("message")
    @classmethod
    def _clean_message(cls, v: str) -> str:
        cleaned = _multi_line(v)
        if not cleaned:
            raise ValueError("message must not be empty")
        return cleaned

    @field_validator("household_id")
    @classmethod
    def _check_household(cls, v: Optional[str]) -> Optional[str]:
        if v in (None, ""):
            return None
        try:
            validate_uuid(v)
        except HTTPException as exc:
            raise ValueError("must be a UUID") from exc
        return v


def _email_bucket(email: str) -> str:
    # Hash so raw addresses never appear in Redis keys or rate-limit log lines.
    return hashlib.sha256(email.lower().encode("utf-8")).hexdigest()[:32]


async def _enforce_limits(buckets: Iterable[tuple[str, int]]) -> None:
    for key, max_requests in buckets:
        try:
            await default_rate_limiter.check_rate_limit(key, max_requests=max_requests, window_seconds=HOUR)
        except HTTPException:
            raise
        except Exception as exc:  # fail closed: no limiter, no email
            logger.error("Inquiry rate limiter unavailable (%s); rejecting request.", type(exc).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Service temporarily unavailable. Please try again later.",
            )


def _compose(
    *,
    inquiry_type: str,
    reference: str,
    reply_to: Optional[str],
    subject_identity: str,
    fields: list[tuple[str, Optional[str]]],
    message: Optional[str],
) -> mail_service.OutboundEmail:
    label = TYPE_LABELS[inquiry_type]
    received = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines = [f"New {label} request from Budget Tracker", ""]
    lines.append(f"Type: {label}")
    for name, value in fields:
        lines.append(f"{name}: {value if value else '(not provided)'}")
    lines.append(f"Received: {received}")
    lines.append(f"Reference: {reference}")
    if message:
        lines += ["", "Message:", message]
    if reply_to:
        lines += ["", "Reply to this email to answer the sender directly."]
    return mail_service.OutboundEmail(
        subject=f"[Budget Tracker] {label} — {subject_identity}",
        body="\n".join(lines) + "\n",
        reply_to=reply_to,
    )


def _persist_inquiry(
    *,
    reference: str,
    inquiry_type: str,
    email: str,
    name: Optional[str] = None,
    message: Optional[str] = None,
    locale: Optional[str] = None,
    source: str = "web",
) -> bool:
    try:
        client = get_client()
        client.table("inquiries").insert({
            "reference": reference,
            "inquiry_type": inquiry_type,
            "email": email,
            "name": name,
            "message": message,
            "locale": locale,
            "source": source,
            "delivery_status": "pending",
        }).execute()
        return True
    except Exception as exc:
        logger.warning("Failed to persist inquiry ref=%s to database: %s", reference, exc)
        return False


def _update_inquiry_status(reference: str, status: str, provider: Optional[str] = None) -> None:
    try:
        client = get_client()
        update_data: dict[str, str] = {
            "delivery_status": status,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if provider:
            update_data["mail_provider"] = provider
        client.table("inquiries").update(update_data).eq("reference", reference).execute()
    except Exception as exc:
        logger.warning("Failed to update inquiry status for ref=%s: %s", reference, exc)


async def _deliver(
    message: mail_service.OutboundEmail,
    reference: str,
    inquiry_type: str,
    db_persisted: bool = False,
) -> dict:
    not_configured = HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Email delivery is not configured on the server, so your message was not sent. "
               "Please try again later.",
    )
    is_lead_capture = inquiry_type == "vip_early_access" and db_persisted

    if mail_service.active_provider() is None:
        if is_lead_capture:
            logger.info(
                "Inquiry ref=%s (%s) saved in DB; email delivery skipped (no provider configured).",
                reference, inquiry_type,
            )
            return {"status": "captured", "reference": reference}
        logger.error(
            "Inquiry ref=%s (%s) NOT delivered: no email provider configured "
            "(set RESEND_API_KEY or SMTP_HOST).", reference, inquiry_type,
        )
        raise not_configured
    try:
        provider = await mail_service.send_email(message)
    except mail_service.MailNotConfiguredError as exc:
        logger.error("Inquiry ref=%s (%s) NOT delivered: %s", reference, inquiry_type, exc)
        if is_lead_capture:
            _update_inquiry_status(reference, status="pending")
            return {"status": "captured", "reference": reference}
        raise not_configured
    except Exception as exc:
        logger.error(
            "Inquiry ref=%s (%s) NOT delivered: %s: %s", reference, inquiry_type, type(exc).__name__, exc,
        )
        if is_lead_capture:
            _update_inquiry_status(reference, status="failed")
            return {"status": "captured", "reference": reference}
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Your message could not be delivered right now. Please try again later. Reference: {reference}",
        )
    _update_inquiry_status(reference, status="delivered", provider=provider)
    logger.info("Inquiry ref=%s (%s) delivered via %s.", reference, inquiry_type, provider)
    return {"status": "sent", "reference": reference}


@router.post("/public/inquiries", summary="Submit a VIP early-access, support or contact inquiry")
async def submit_public_inquiry(payload: PublicInquiry, request: Request) -> dict:
    reference = uuid.uuid4().hex[:12]
    if payload.company_website:
        # Answer like a success so bots learn nothing; nothing is sent.
        logger.info("Inquiry ref=%s discarded: honeypot field filled (source=%s).", reference, payload.source)
        return {"status": "sent", "reference": reference}

    # Per identity under a global ceiling (FABLE-API-03): the per-IP bucket only applies to an
    # address that is really the client's; an untrusted proxy hop is shared by every visitor and
    # would lock the whole site out after a few requests.
    client_ip, ip_is_client = client_ip_info(request)
    buckets = [(f"inquiry:ip:{client_ip}", PUBLIC_PER_IP_LIMIT)] if ip_is_client else []
    buckets += [
        (f"inquiry:email:{_email_bucket(payload.email)}", PUBLIC_PER_EMAIL_LIMIT),
        ("inquiry:global", GLOBAL_LIMIT),
    ]
    await _enforce_limits(buckets)

    db_persisted = _persist_inquiry(
        reference=reference,
        inquiry_type=payload.type,
        email=payload.email,
        name=payload.name,
        message=payload.message,
        locale=payload.locale,
        source=payload.source,
    )

    message = _compose(
        inquiry_type=payload.type,
        reference=reference,
        reply_to=payload.email,
        subject_identity=payload.email,
        fields=[
            ("Email", payload.email),
            ("Name", payload.name),
            ("Locale", payload.locale),
            ("Source", payload.source),
        ],
        message=payload.message,
    )
    return await _deliver(message, reference, payload.type, db_persisted=db_persisted)


@router.post("/support/inquiries", summary="Send an in-app support request to the developer")
async def submit_app_support_inquiry(payload: AppSupportInquiry, request: Request) -> dict:
    claims = get_verified_claims(request)
    user_id = str(claims.get("sub") or "")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired authentication token.")

    account_email: Optional[str] = None
    raw_email = claims.get("email")
    if isinstance(raw_email, str) and raw_email:
        try:
            account_email = normalize_email(raw_email)
        except ValueError:
            logger.warning("Verified token for user=%s carries an unusable email claim.", user_id)

    reference = uuid.uuid4().hex[:12]
    await _enforce_limits([
        (f"inquiry:user:{user_id}", APP_PER_USER_LIMIT),
        ("inquiry:global", GLOBAL_LIMIT),
    ])

    db_persisted = _persist_inquiry(
        reference=reference,
        inquiry_type="support",
        email=account_email or f"{user_id}@auth.internal",
        name=f"User {user_id}",
        message=payload.message,
        locale=payload.locale,
        source="app",
    )

    message = _compose(
        inquiry_type="support",
        reference=reference,
        reply_to=account_email,
        subject_identity=account_email or f"user {user_id}",
        fields=[
            ("Verified user ID", user_id),
            ("Verified account email", account_email),
            ("Household (reported by app)", payload.household_id),
            ("Locale", payload.locale),
            ("Source", "app"),
        ],
        message=payload.message,
    )
    return await _deliver(message, reference, "support", db_persisted=db_persisted)
