"""Contact / support / VIP early-access inquiries are delivered by email (WEB-09).

The mailer is always mocked: no test opens a socket to an email provider.
"""

from __future__ import annotations

import time
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient
from jose import jwt

import mail_service
from main import app

SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"
USER_ID = "00000000-0000-4000-8000-0000000000b7"

PUBLIC_URL = "/public/inquiries"
APP_URL = "/support/inquiries"


@pytest.fixture()
def client():
    return TestClient(app)


@pytest.fixture()
def mailer(monkeypatch):
    """A configured provider with the actual send replaced by a mock."""
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")
    monkeypatch.delenv("SMTP_HOST", raising=False)
    monkeypatch.delenv("CONTACT_RECIPIENT_EMAIL", raising=False)
    send = AsyncMock(return_value="resend")
    monkeypatch.setattr(mail_service, "send_email", send)
    return send


@pytest.fixture()
def no_provider(monkeypatch):
    for key in ("RESEND_API_KEY", "SMTP_HOST"):
        monkeypatch.delenv(key, raising=False)
    send = AsyncMock(side_effect=AssertionError("must not send without a provider"))
    monkeypatch.setattr(mail_service, "send_email", send)
    return send


def _token(**overrides) -> str:
    now = int(time.time())
    claims = {
        "sub": USER_ID,
        "aud": "authenticated",
        "iss": ISSUER,
        "role": "authenticated",
        "iat": now,
        "exp": now + 600,
        "email": "member@example.com",
    }
    claims.update(overrides)
    return jwt.encode({k: v for k, v in claims.items() if v is not None}, SECRET, algorithm="HS256")


def _sent_message(send: AsyncMock) -> mail_service.OutboundEmail:
    assert send.await_count == 1
    return send.await_args.args[0]


# ── Public endpoint: success ────────────────────────────────────────────────


def test_vip_signup_is_emailed_with_reply_to_and_clear_subject(client, mailer):
    res = client.post(
        PUBLIC_URL,
        json={"type": "vip_early_access", "email": "Fan@Example.COM", "locale": "ar", "source": "web"},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "sent"
    assert body["reference"]

    msg = _sent_message(mailer)
    assert msg.subject == "[Qawam Money] VIP early access — Fan@example.com"
    assert msg.reply_to == "Fan@example.com"
    assert "VIP early access" in msg.body
    assert "Locale: ar" in msg.body
    assert "Source: web" in msg.body
    assert body["reference"] in msg.body


def test_support_request_is_emailed_with_message(client, mailer):
    res = client.post(
        PUBLIC_URL,
        json={
            "type": "support",
            "email": "user@example.com",
            "name": "Sara",
            "message": "The app crashes when I scan a receipt.\nPlease help.",
            "source": "landing",
        },
    )
    assert res.status_code == 200, res.text
    msg = _sent_message(mailer)
    assert msg.subject == "[Qawam Money] Support — user@example.com"
    assert msg.reply_to == "user@example.com"
    assert "Name: Sara" in msg.body
    assert "The app crashes when I scan a receipt.\nPlease help." in msg.body


def test_recipient_defaults_to_owner_address(monkeypatch):
    monkeypatch.delenv("CONTACT_RECIPIENT_EMAIL", raising=False)
    assert mail_service.recipient() == "abedmowafaq@gmail.com"
    monkeypatch.setenv("CONTACT_RECIPIENT_EMAIL", "ops@example.com")
    assert mail_service.recipient() == "ops@example.com"


# ── Validation ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "payload",
    [
        {"type": "vip_early_access", "email": "not-an-email"},
        {"type": "vip_early_access", "email": "a@b"},
        {"type": "vip_early_access", "email": ("x" * 250) + "@example.com"},
        {"type": "vip_early_access"},
        {"type": "newsletter", "email": "a@example.com"},
        {"type": "support", "email": "a@example.com"},  # message required
        {"type": "support", "email": "a@example.com", "message": "x" * 4001},
        {"type": "contact", "email": "a@example.com", "message": "hi", "name": "n" * 101},
        {"type": "vip_early_access", "email": "a@example.com", "source": "sms"},
        {"type": "vip_early_access", "email": "a@example.com", "locale": "ar\nBcc: x@evil.test"},
        {"type": "vip_early_access", "email": "a@example.com", "is_admin": True},
    ],
)
def test_invalid_payloads_are_rejected_without_sending(client, mailer, payload):
    res = client.post(PUBLIC_URL, json=payload)
    assert res.status_code == 422
    mailer.assert_not_awaited()


def test_validation_errors_do_not_echo_input(client, mailer):
    res = client.post(PUBLIC_URL, json={"type": "vip_early_access", "email": "secret-probe-value"})
    assert res.status_code == 422
    assert "secret-probe-value" not in res.text


@pytest.mark.parametrize(
    "email",
    [
        "victim@example.com\r\nBcc: list@evil.test",
        "victim@example.com\nSubject: hacked",
        "victim@example.com%0d%0aBcc:x@evil.test",
        "victim@example.com, other@evil.test",
        "\"Name\" <victim@example.com>",
    ],
)
def test_header_injection_via_email_is_rejected(client, mailer, email):
    res = client.post(PUBLIC_URL, json={"type": "vip_early_access", "email": email})
    assert res.status_code == 422
    mailer.assert_not_awaited()


def test_control_characters_are_stripped_from_name_and_message(client, mailer):
    res = client.post(
        PUBLIC_URL,
        json={
            "type": "contact",
            "email": "a@example.com",
            "name": "Ali\r\nBcc: x@evil.test\x00",
            "message": "Hello\x07 there\r\nline two\x1b[31m",
        },
    )
    assert res.status_code == 200, res.text
    msg = _sent_message(mailer)
    assert "Name: Ali Bcc: x@evil.test" in msg.body
    assert "\x00" not in msg.body and "\x07" not in msg.body and "\x1b" not in msg.body
    assert "Hello there\nline two[31m" in msg.body
    assert "\r" not in msg.subject and "\n" not in msg.subject


# ── Honeypot ────────────────────────────────────────────────────────────────


def test_honeypot_submission_is_discarded_silently(client, mailer):
    res = client.post(
        PUBLIC_URL,
        json={"type": "vip_early_access", "email": "bot@example.com", "company_website": "http://spam.test"},
    )
    assert res.status_code == 200
    assert res.json()["status"] == "sent"
    mailer.assert_not_awaited()


# ── Rate limiting ───────────────────────────────────────────────────────────


def test_per_ip_rate_limit(client, mailer, monkeypatch):
    import routes.inquiries as inquiries

    # A real client address (FABLE-API-03: an untrusted proxy hop gets no per-IP bucket).
    monkeypatch.setattr(inquiries, "client_ip_info", lambda _request: ("203.0.113.5", True))
    statuses = [
        client.post(PUBLIC_URL, json={"type": "vip_early_access", "email": f"u{i}@example.com"}).status_code
        for i in range(7)
    ]
    assert statuses[:5] == [200] * 5
    assert statuses[5:] == [429, 429]
    assert mailer.await_count == 5


def test_per_email_rate_limit_across_ips(client, mailer, monkeypatch):
    import routes.inquiries as inquiries

    ips = iter(f"203.0.113.{i}" for i in range(1, 20))
    monkeypatch.setattr(inquiries, "client_ip_info", lambda _request: (next(ips), True))
    statuses = [
        client.post(PUBLIC_URL, json={"type": "vip_early_access", "email": "same@example.com"}).status_code
        for _ in range(5)
    ]
    assert statuses == [200, 200, 200, 429, 429]
    assert mailer.await_count == 3


def test_rate_limiter_failure_fails_closed(client, mailer, monkeypatch):
    import rate_limiter

    async def broken(*_a, **_k):
        raise RuntimeError("limiter backend exploded")

    monkeypatch.setattr(rate_limiter.default_rate_limiter, "check_rate_limit", broken)
    res = client.post(PUBLIC_URL, json={"type": "vip_early_access", "email": "a@example.com"})
    assert res.status_code == 503
    assert "exploded" not in res.text
    mailer.assert_not_awaited()


# ── Provider missing / delivery failure ─────────────────────────────────────


def test_missing_provider_returns_503_and_never_pretends_success(client, no_provider, caplog):
    with caplog.at_level("ERROR"):
        res = client.post(PUBLIC_URL, json={"type": "support", "email": "a@example.com", "message": "Help needed with app"})
    assert res.status_code == 503
    assert "not configured" in res.json()["detail"].lower()
    assert "sent" not in res.json().get("status", "")
    no_provider.assert_not_awaited()
    assert any("not delivered" in r.getMessage().lower() for r in caplog.records)


def test_provider_failure_returns_502_with_sanitized_detail(client, mailer):
    mailer.side_effect = mail_service.MailDeliveryError("SMTP 535 auth failed for user owner@internal")
    res = client.post(PUBLIC_URL, json={"type": "support", "email": "a@example.com", "message": "Help needed with app"})
    assert res.status_code == 502
    assert "owner@internal" not in res.text
    assert "535" not in res.text
    assert "reference" in res.json()["detail"].lower()


# ── Firewall and CORS ───────────────────────────────────────────────────────


def test_public_endpoint_is_reachable_through_the_proxy_without_app_token(client, mailer):
    res = client.post(
        PUBLIC_URL,
        json={"type": "vip_early_access", "email": "a@example.com"},
        headers={"X-Forwarded-For": "198.51.100.7"},
    )
    assert res.status_code == 200, res.text


@pytest.mark.parametrize("origin", ["https://budget.fmsco.com.sa", "https://www.budget.fmsco.com.sa"])
def test_cors_preflight_allows_live_origin(client, origin):
    res = client.options(
        PUBLIC_URL,
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert res.status_code == 200
    assert res.headers.get("access-control-allow-origin") == origin


def test_cors_preflight_rejects_unknown_origin(client):
    res = client.options(
        PUBLIC_URL,
        headers={
            "Origin": "https://evil.example",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert res.headers.get("access-control-allow-origin") is None


# ── Authenticated in-app variant ────────────────────────────────────────────


def test_app_support_uses_verified_jwt_identity(client, mailer):
    res = client.post(
        APP_URL,
        json={"message": "Escalation: sync fails after login", "locale": "ur"},
        headers={"Authorization": f"Bearer {_token()}"},
    )
    assert res.status_code == 200, res.text
    msg = _sent_message(mailer)
    assert msg.subject == "[Qawam Money] Support — member@example.com"
    assert msg.reply_to == "member@example.com"
    assert f"Verified user ID: {USER_ID}" in msg.body
    assert "Locale: ur" in msg.body
    assert "Source: app" in msg.body
    assert "Escalation: sync fails after login" in msg.body


def test_app_support_rejects_client_supplied_identity(client, mailer):
    res = client.post(
        APP_URL,
        json={"message": "hello there", "email": "ceo@example.com", "user_id": "someone-else"},
        headers={"Authorization": f"Bearer {_token()}"},
    )
    assert res.status_code == 422
    mailer.assert_not_awaited()


def test_app_support_requires_valid_token(client, mailer):
    assert client.post(APP_URL, json={"message": "hello there"}).status_code == 401
    forged = jwt.encode({"sub": "x", "aud": "authenticated", "iss": ISSUER, "role": "authenticated",
                         "iat": int(time.time()), "exp": int(time.time()) + 600}, "wrong-secret", algorithm="HS256")
    res = client.post(APP_URL, json={"message": "hello there"}, headers={"Authorization": f"Bearer {forged}"})
    assert res.status_code == 401
    mailer.assert_not_awaited()


def test_app_support_without_email_claim_identifies_user_by_id(client, mailer):
    res = client.post(
        APP_URL,
        json={"message": "Need help with my budget"},
        headers={"Authorization": f"Bearer {_token(email=None)}"},
    )
    assert res.status_code == 200, res.text
    msg = _sent_message(mailer)
    assert msg.reply_to is None
    assert USER_ID in msg.subject


def test_app_support_rejects_invalid_household_id(client, mailer):
    res = client.post(
        APP_URL,
        json={"message": "Need help", "household_id": "not-a-uuid"},
        headers={"Authorization": f"Bearer {_token()}"},
    )
    assert res.status_code == 422
    mailer.assert_not_awaited()


def test_app_support_per_user_rate_limit(client, mailer):
    headers = {"Authorization": f"Bearer {_token()}"}
    statuses = [client.post(APP_URL, json={"message": f"issue {i}"}, headers=headers).status_code for i in range(7)]
    assert statuses[:5] == [200] * 5
    assert statuses[5:] == [429, 429]


def test_app_support_missing_provider_returns_503(client, no_provider):
    res = client.post(APP_URL, json={"message": "hello there"}, headers={"Authorization": f"Bearer {_token()}"})
    assert res.status_code == 503


# ── The public account deletion form ────────────────────────────────────────

_DELETION = {"type": "account_deletion", "email": "leaving@example.com", "name": "Sara", "message": "Please delete it.", "locale": "ur"}


class _InquiriesOnlyClient:
    """Anything but the inquiries table fails the test: the form must not look up an account."""

    def __init__(self, fail_insert=False):
        self.rows = []
        self.updates = []
        self.fail_insert = fail_insert

    def table(self, name):
        assert name == "inquiries", f"the deletion form touched {name}"
        return self

    def insert(self, row):
        if self.fail_insert:
            raise RuntimeError("insert failed for leaving@example.com")
        self.rows.append(row)
        return self

    def update(self, row):
        self.updates.append(row)
        return self

    def eq(self, *_args):
        return self

    def execute(self):
        return None

    def __getattr__(self, name):
        raise AssertionError(f"the deletion form used client.{name}")


@pytest.fixture()
def form_db(monkeypatch):
    import routes.inquiries as inquiries

    db = _InquiriesOnlyClient()
    monkeypatch.setattr(inquiries, "get_client", lambda: db)
    return db


def test_deletion_request_is_stored_and_emailed_to_the_developer_only(client, mailer, form_db):
    res = client.post(PUBLIC_URL, json=_DELETION, headers={"X-Forwarded-For": "198.51.100.7"})
    assert res.status_code == 200, res.text
    assert res.json()["status"] == "sent"

    assert len(form_db.rows) == 1
    row = form_db.rows[0]
    assert (row["type"], row["email"], row["locale"]) == ("account_deletion", "leaving@example.com", "ur")

    msg = _sent_message(mailer)
    assert "Account deletion" in msg.subject
    assert "Please delete it." in msg.body
    assert mailer.await_args.kwargs.get("to_override") is None, "never mails the submitted address"
    assert len(mailer.await_args.args) == 1


def test_deletion_request_needs_no_message(client, mailer, form_db):
    res = client.post(PUBLIC_URL, json={"type": "account_deletion", "email": "leaving@example.com"})
    assert res.status_code == 200, res.text


def test_deletion_form_answer_never_varies_by_account(client, mailer, form_db, fake_supabase):
    fake_supabase.seed("users", [{"id": USER_ID, "display_name": "Known", "email": "known@example.com"}])
    known = client.post(PUBLIC_URL, json={**_DELETION, "email": "known@example.com"})
    unknown = client.post(PUBLIC_URL, json={**_DELETION, "email": "nobody-here@example.com"})
    assert known.status_code == unknown.status_code == 200
    assert set(known.json()) == set(unknown.json()) == {"status", "reference"}
    assert known.json()["status"] == unknown.json()["status"]


def test_deletion_form_honeypot_stores_and_sends_nothing(client, mailer, form_db):
    res = client.post(PUBLIC_URL, json={**_DELETION, "company_website": "http://spam.test"})
    assert res.status_code == 200
    assert res.json()["status"] == "sent"
    assert form_db.rows == []
    mailer.assert_not_awaited()


def test_deletion_form_shares_the_per_email_limit(client, mailer, form_db, monkeypatch):
    import routes.inquiries as inquiries

    ips = iter(f"203.0.113.{n}" for n in range(1, 50))
    monkeypatch.setattr(inquiries, "client_ip_info", lambda _request: (next(ips), True))
    statuses = [client.post(PUBLIC_URL, json=_DELETION).status_code for _ in range(4)]
    assert statuses == [200, 200, 200, 429]


def test_deletion_form_shares_the_per_ip_limit(client, mailer, form_db, monkeypatch):
    import routes.inquiries as inquiries

    monkeypatch.setattr(inquiries, "client_ip_info", lambda _request: ("203.0.113.5", True))
    statuses = [
        client.post(PUBLIC_URL, json={**_DELETION, "email": f"u{n}@example.com"}).status_code for n in range(6)
    ]
    assert statuses == [200, 200, 200, 200, 200, 429]


def test_a_stored_deletion_request_is_received_even_without_a_mail_provider(client, no_provider, form_db):
    """The row is what the developer acts on, so this is true, not a pretended success."""
    res = client.post(PUBLIC_URL, json=_DELETION)
    assert res.status_code == 200, res.text
    assert res.json()["status"] == "captured"
    assert len(form_db.rows) == 1
    no_provider.assert_not_awaited()


def test_a_stored_deletion_request_is_received_when_the_provider_fails(client, mailer, form_db):
    mailer.side_effect = mail_service.MailDeliveryError("down")
    res = client.post(PUBLIC_URL, json=_DELETION)
    assert res.status_code == 200, res.text
    assert res.json()["status"] == "captured"
    assert form_db.updates == [{"status": "failed"}]


def test_a_deletion_request_neither_stored_nor_sent_is_an_error(client, no_provider, monkeypatch):
    import routes.inquiries as inquiries

    monkeypatch.setattr(inquiries, "get_client", lambda: _InquiriesOnlyClient(fail_insert=True))
    res = client.post(PUBLIC_URL, json=_DELETION)
    assert res.status_code == 503


def test_a_deletion_request_that_was_not_stored_is_an_error_even_if_mail_works(client, mailer, monkeypatch):
    """The page says "stored and sent" for 'sent'. A row the 90-day removal and the operator rely
    on must exist, so a failed insert answers 503, sends nothing, and the person can retry."""
    import routes.inquiries as inquiries

    monkeypatch.setattr(inquiries, "get_client", lambda: _InquiriesOnlyClient(fail_insert=True))
    res = client.post(PUBLIC_URL, json=_DELETION)
    assert res.status_code == 503
    assert "sent" not in res.text
    mailer.assert_not_awaited()


def test_other_inquiry_types_still_send_when_the_row_is_not_stored(client, mailer, monkeypatch):
    import routes.inquiries as inquiries

    monkeypatch.setattr(inquiries, "get_client", lambda: _InquiriesOnlyClient(fail_insert=True))
    res = client.post(PUBLIC_URL, json={"type": "support", "email": "leaving@example.com", "message": "help"})
    assert res.status_code == 200
    assert res.json()["status"] == "sent"


def test_a_failed_insert_never_logs_the_address(client, mailer, monkeypatch, caplog):
    import routes.inquiries as inquiries

    monkeypatch.setattr(inquiries, "get_client", lambda: _InquiriesOnlyClient(fail_insert=True))
    with caplog.at_level("DEBUG"):
        res = client.post(PUBLIC_URL, json=_DELETION)
    assert res.status_code == 503
    assert "leaving@example.com" not in caplog.text


def test_deletion_form_is_reachable_through_the_proxy_without_any_token(client, mailer, form_db):
    res = client.post(PUBLIC_URL, json=_DELETION, headers={"X-Forwarded-For": "198.51.100.7"})
    assert res.status_code == 200


def test_the_other_types_still_refuse_a_missing_provider(client, no_provider):
    res = client.post(PUBLIC_URL, json={"type": "support", "email": "a@example.com", "message": "hi"})
    assert res.status_code == 503
