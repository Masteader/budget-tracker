"""mail_service: provider selection, Resend and SMTP delivery, header safety. No network."""

from __future__ import annotations

import json

import httpx
import pytest
import respx

import mail_service
from mail_service import MailDeliveryError, MailNotConfiguredError, OutboundEmail

MESSAGE = OutboundEmail(
    subject="[Budget Tracker] VIP early access — fan@example.com",
    body="New VIP early access request\nEmail: fan@example.com",
    reply_to="fan@example.com",
)


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for key in (
        "RESEND_API_KEY", "RESEND_FROM", "SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME",
        "SMTP_PASSWORD", "SMTP_FROM", "SMTP_SECURITY", "CONTACT_RECIPIENT_EMAIL", "MAIL_FROM",
    ):
        monkeypatch.delenv(key, raising=False)


def test_no_provider_configured():
    assert mail_service.active_provider() is None


@pytest.mark.asyncio
async def test_send_without_provider_raises_not_configured():
    with pytest.raises(MailNotConfiguredError):
        await mail_service.send_email(MESSAGE)


def test_resend_preferred_when_both_configured(monkeypatch):
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    assert mail_service.active_provider() == "smtp"
    monkeypatch.setenv("RESEND_API_KEY", "re_dummy")
    assert mail_service.active_provider() == "resend"


def test_invalid_recipient_config_is_rejected(monkeypatch):
    monkeypatch.setenv("CONTACT_RECIPIENT_EMAIL", "nobody")
    with pytest.raises(MailNotConfiguredError):
        mail_service.recipient()


@pytest.mark.asyncio
@respx.mock
async def test_resend_request_shape(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_dummy")
    route = respx.post("https://api.resend.com/emails").mock(
        return_value=httpx.Response(200, json={"id": "abc"})
    )
    assert await mail_service.send_email(MESSAGE) == "resend"
    request = route.calls.last.request
    assert request.headers["Authorization"] == "Bearer re_dummy"
    payload = json.loads(request.content)
    assert payload["to"] == ["abedmowafaq@gmail.com"]
    assert payload["subject"] == MESSAGE.subject
    assert payload["text"] == MESSAGE.body
    assert payload["reply_to"] == "fan@example.com"
    assert payload["from"] == "Budget Tracker <fmscoinfo@fmsco.com.sa>"


def test_default_sender_is_company_mailbox():
    assert mail_service.DEFAULT_SENDER == "Budget Tracker <fmscoinfo@fmsco.com.sa>"
    assert mail_service.sender("SMTP_FROM") == "Budget Tracker <fmscoinfo@fmsco.com.sa>"
    assert mail_service.sender("RESEND_FROM") == "Budget Tracker <fmscoinfo@fmsco.com.sa>"


def test_mail_from_overrides_default_and_provider_var_overrides_mail_from(monkeypatch):
    monkeypatch.setenv("MAIL_FROM", "Budget <hello@fmsco.com.sa>")
    assert mail_service.sender("SMTP_FROM") == "Budget <hello@fmsco.com.sa>"
    monkeypatch.setenv("RESEND_FROM", "Budget <noreply@fmsco.com.sa>")
    assert mail_service.sender("RESEND_FROM") == "Budget <noreply@fmsco.com.sa>"
    assert mail_service.sender("SMTP_FROM") == "Budget <hello@fmsco.com.sa>"


@pytest.mark.parametrize("bad", ["not-an-address", "Budget <a@fmsco.com.sa>\r\nBcc: x@evil.test"])
def test_invalid_sender_config_is_not_configured(monkeypatch, bad):
    monkeypatch.setenv("MAIL_FROM", bad)
    with pytest.raises(MailNotConfiguredError):
        mail_service.sender("SMTP_FROM")


@pytest.mark.asyncio
@respx.mock
async def test_resend_error_raises_delivery_error(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_dummy")
    respx.post("https://api.resend.com/emails").mock(return_value=httpx.Response(403, json={"message": "bad"}))
    with pytest.raises(MailDeliveryError):
        await mail_service.send_email(MESSAGE)


@pytest.mark.asyncio
@respx.mock
async def test_resend_network_error_raises_delivery_error(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_dummy")
    respx.post("https://api.resend.com/emails").mock(side_effect=httpx.ConnectError("down"))
    with pytest.raises(MailDeliveryError):
        await mail_service.send_email(MESSAGE)


class FakeSMTP:
    instances: list["FakeSMTP"] = []

    def __init__(self, host, port, timeout=None, context=None):
        self.host, self.port, self.timeout, self.context = host, port, timeout, context
        self.calls: list = []
        self.sent = []
        FakeSMTP.instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.calls.append("quit")
        return False

    def ehlo(self):
        self.calls.append("ehlo")

    def starttls(self, context=None):
        self.calls.append("starttls")

    def login(self, user, password):
        self.calls.append(("login", user))

    def send_message(self, msg):
        self.sent.append(msg)


@pytest.fixture()
def fake_smtp(monkeypatch):
    FakeSMTP.instances = []
    monkeypatch.setattr(mail_service.smtplib, "SMTP", FakeSMTP)
    monkeypatch.setattr(mail_service.smtplib, "SMTP_SSL", type("FakeSSL", (FakeSMTP,), {}))
    return FakeSMTP


@pytest.mark.asyncio
async def test_smtp_starttls_delivery(monkeypatch, fake_smtp):
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_PORT", "587")
    monkeypatch.setenv("SMTP_USERNAME", "fmscoinfo@fmsco.com.sa")
    monkeypatch.setenv("SMTP_PASSWORD", "app-password")
    assert await mail_service.send_email(MESSAGE) == "smtp"
    smtp = fake_smtp.instances[-1]
    assert (smtp.host, smtp.port) == ("smtp.example.com", 587)
    assert "starttls" in smtp.calls
    assert ("login", "fmscoinfo@fmsco.com.sa") in smtp.calls
    sent = smtp.sent[0]
    assert sent["To"] == "abedmowafaq@gmail.com"
    # No SMTP_FROM / MAIL_FROM set: the company mailbox is the default sender.
    assert sent["From"] == "Budget Tracker <fmscoinfo@fmsco.com.sa>"
    assert sent["Message-ID"].endswith("@fmsco.com.sa>")
    assert sent["Reply-To"] == "fan@example.com"
    assert sent["Subject"] == MESSAGE.subject
    assert "fan@example.com" in sent.get_content()


@pytest.mark.asyncio
async def test_smtp_ssl_on_port_465(monkeypatch, fake_smtp):
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_PORT", "465")
    monkeypatch.setenv("SMTP_FROM", "Budget Tracker <noreply@example.com>")
    await mail_service.send_email(MESSAGE)
    smtp = fake_smtp.instances[-1]
    assert type(smtp).__name__ == "FakeSSL"
    assert "starttls" not in smtp.calls
    assert smtp.sent[0]["From"] == "Budget Tracker <noreply@example.com>"


@pytest.mark.asyncio
async def test_smtp_failure_raises_delivery_error(monkeypatch, fake_smtp):
    import smtplib

    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_FROM", "noreply@example.com")

    def boom(self, msg):
        raise smtplib.SMTPAuthenticationError(535, b"auth failed")

    monkeypatch.setattr(FakeSMTP, "send_message", boom)
    with pytest.raises(MailDeliveryError):
        await mail_service.send_email(MESSAGE)


@pytest.mark.asyncio
async def test_smtp_with_invalid_sender_is_not_configured(monkeypatch, fake_smtp):
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_FROM", "Budget Tracker")
    with pytest.raises(MailNotConfiguredError):
        await mail_service.send_email(MESSAGE)


@pytest.mark.asyncio
async def test_smtp_rejects_unknown_security_mode(monkeypatch, fake_smtp):
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_FROM", "noreply@example.com")
    monkeypatch.setenv("SMTP_SECURITY", "plaintext")
    with pytest.raises(MailNotConfiguredError):
        await mail_service.send_email(MESSAGE)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "message",
    [
        OutboundEmail(subject="Hi\r\nBcc: x@evil.test", body="b", reply_to=None),
        OutboundEmail(subject="Hi", body="b", reply_to="a@example.com\nBcc: x@evil.test"),
    ],
)
async def test_header_injection_is_refused_before_any_provider_call(monkeypatch, fake_smtp, message):
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_FROM", "noreply@example.com")
    with pytest.raises(ValueError):
        await mail_service.send_email(message)
    assert fake_smtp.instances == []
