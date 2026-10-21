"""
Outbound email for contact, support and VIP early-access inquiries.

Providers (picked from the environment at send time; Resend wins when both are set):
- Resend HTTP API: RESEND_API_KEY. Works on hosts that block outbound SMTP ports, such as
  Railway's non-Pro plans. The sender domain (fmsco.com.sa) must be verified in Resend.
- SMTP: SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_SECURITY ("starttls" or
  "ssl"; defaults to "ssl" on port 465, otherwise "starttls"). TLS is mandatory. The login must
  be the mailbox of the sender address (fmscoinfo@fmsco.com.sa by default).

Sender: MAIL_FROM, default "Budget Tracker <fmscoinfo@fmsco.com.sa>". SMTP_FROM / RESEND_FROM
override it for one provider only.

Every message goes to CONTACT_RECIPIENT_EMAIL (default abedmowafaq@gmail.com) with Reply-To
set to the submitter. Nothing here ever reports success unless the provider accepted the
message: a missing provider raises MailNotConfiguredError, a provider failure raises
MailDeliveryError.
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from email.utils import formatdate, make_msgid, parseaddr
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

DEFAULT_RECIPIENT = "abedmowafaq@gmail.com"
RESEND_ENDPOINT = "https://api.resend.com/emails"
# Every inquiry email is sent from the company mailbox unless MAIL_FROM (or the
# provider-specific SMTP_FROM / RESEND_FROM) says otherwise.
DEFAULT_SENDER = "Budget Tracker <fmscoinfo@fmsco.com.sa>"
SEND_TIMEOUT_SECONDS = 15.0

_SIMPLE_EMAIL_RE = re.compile(r"^[^@\s<>,;\"]+@[^@\s<>,;\"]+\.[^@\s<>,;\"]+$")
_HEADER_UNSAFE_RE = re.compile(r"[\r\n\x00]")


class MailNotConfiguredError(RuntimeError):
    """No usable email provider (or recipient) is configured."""


class MailDeliveryError(RuntimeError):
    """The provider was reachable/configured but did not accept the message."""


@dataclass(frozen=True)
class OutboundEmail:
    subject: str
    body: str
    reply_to: Optional[str] = None


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def recipient() -> str:
    value = _env("CONTACT_RECIPIENT_EMAIL") or DEFAULT_RECIPIENT
    if not _SIMPLE_EMAIL_RE.match(value):
        raise MailNotConfiguredError("CONTACT_RECIPIENT_EMAIL is not a valid email address.")
    return value


def sender(provider_override_var: str) -> str:
    """The From header: provider override, then MAIL_FROM, then DEFAULT_SENDER."""
    value = _env(provider_override_var) or _env("MAIL_FROM") or DEFAULT_SENDER
    if _HEADER_UNSAFE_RE.search(value) or not _SIMPLE_EMAIL_RE.match(parseaddr(value)[1] or ""):
        raise MailNotConfiguredError("MAIL_FROM (or SMTP_FROM / RESEND_FROM) must be a valid sender address.")
    return value


def active_provider() -> Optional[str]:
    """Name of the provider that send_email would use, or None when none is configured."""
    if _env("RESEND_API_KEY"):
        return "resend"
    if _env("SMTP_HOST"):
        return "smtp"
    return None


def _assert_header_safe(name: str, value: Optional[str]) -> None:
    if value is not None and _HEADER_UNSAFE_RE.search(value):
        raise ValueError(f"{name} contains line breaks or NUL characters.")


async def send_email(message: OutboundEmail) -> str:
    """Deliver *message* to the configured recipient. Returns the provider name used."""
    _assert_header_safe("subject", message.subject)
    _assert_header_safe("reply_to", message.reply_to)

    provider = active_provider()
    if provider is None:
        raise MailNotConfiguredError("No email provider configured (set RESEND_API_KEY or SMTP_HOST).")
    to_address = recipient()

    if provider == "resend":
        await _send_via_resend(message, to_address)
    else:
        # smtplib is blocking; keep it off the event loop.
        await asyncio.to_thread(_send_via_smtp, message, to_address)
    return provider


async def _send_via_resend(message: OutboundEmail, to_address: str) -> None:
    payload = {
        "from": sender("RESEND_FROM"),
        "to": [to_address],
        "subject": message.subject,
        "text": message.body,
    }
    if message.reply_to:
        payload["reply_to"] = message.reply_to
    try:
        async with httpx.AsyncClient(timeout=SEND_TIMEOUT_SECONDS) as client:
            response = await client.post(
                RESEND_ENDPOINT,
                json=payload,
                headers={"Authorization": f"Bearer {_env('RESEND_API_KEY')}"},
            )
    except httpx.HTTPError as exc:
        raise MailDeliveryError(f"Resend request failed ({type(exc).__name__}).") from exc
    if response.status_code not in (200, 201, 202):
        raise MailDeliveryError(f"Resend rejected the message (HTTP {response.status_code}).")


def _smtp_settings() -> tuple[str, int, str, str, str, str]:
    host = _env("SMTP_HOST")
    raw_port = _env("SMTP_PORT")
    security = _env("SMTP_SECURITY").lower()
    try:
        port = int(raw_port) if raw_port else (465 if security == "ssl" else 587)
    except ValueError as exc:
        raise MailNotConfiguredError("SMTP_PORT must be an integer.") from exc
    if not security:
        security = "ssl" if port == 465 else "starttls"
    if security not in ("ssl", "starttls"):
        raise MailNotConfiguredError("SMTP_SECURITY must be 'starttls' or 'ssl'.")
    username = _env("SMTP_USERNAME")
    password = os.environ.get("SMTP_PASSWORD", "")
    return host, port, security, username, password, sender("SMTP_FROM")


def _send_via_smtp(message: OutboundEmail, to_address: str) -> None:
    host, port, security, username, password, from_header = _smtp_settings()

    email = EmailMessage()
    email["From"] = from_header
    email["To"] = to_address
    email["Subject"] = message.subject
    if message.reply_to:
        email["Reply-To"] = message.reply_to
    email["Date"] = formatdate(usegmt=True)
    email["Message-ID"] = make_msgid(domain=parseaddr(from_header)[1].rsplit("@", 1)[-1])
    email.set_content(message.body)

    context = ssl.create_default_context()
    try:
        if security == "ssl":
            smtp = smtplib.SMTP_SSL(host, port, timeout=SEND_TIMEOUT_SECONDS, context=context)
        else:
            smtp = smtplib.SMTP(host, port, timeout=SEND_TIMEOUT_SECONDS)
        with smtp:
            if security == "starttls":
                smtp.ehlo()
                smtp.starttls(context=context)
                smtp.ehlo()
            if username:
                smtp.login(username, password)
            smtp.send_message(email)
    except (smtplib.SMTPException, OSError) as exc:
        raise MailDeliveryError(f"SMTP delivery failed ({type(exc).__name__}).") from exc
