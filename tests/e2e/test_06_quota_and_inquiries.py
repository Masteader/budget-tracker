"""
Scenario 6: persistent quota / rate limiting with the database quota (no Redis), and the inquiry
endpoints with the mail provider absent (503) or present (a local fake of the Resend API).
"""

from __future__ import annotations

import os
import time

import pytest

from e2e_harness.zatca import tlv_qr


def _away_from_window_edge(window: int, margin: float = 45.0) -> None:
    """consume_quota uses fixed windows aligned to the epoch; don't straddle a boundary."""
    left = window - (time.time() % window)
    if left < margin:
        time.sleep(left + 1)


def test_chat_quota_is_persistent_in_database(world, db, llm):
    from rate_limiter import reset_rate_limiters

    flat = world.roommates("Q1", n_members=0)
    user = flat.admin
    _away_from_window_edge(600)
    body = {"household_id": flat.id, "message": "Shawarma 12 SAR", "preview_only": True}
    statuses = [user.api.post("/agent/chat-transaction", json=body).status_code for _ in range(30)]
    assert statuses == [200] * 30
    over = user.api.post("/agent/chat-transaction", json=body)
    assert over.status_code == 429, over.text
    assert over.headers.get("Retry-After")
    row = db.one("SELECT count FROM public.api_quota WHERE user_id = %s AND bucket = 'chat_transaction'", (user.id,))
    assert row["count"] == 31

    # Another app instance (fresh in-memory limiter, no Redis) still refuses: the DB is authoritative.
    reset_rate_limiters()
    again = user.api.post("/agent/chat-transaction", json=body)
    assert again.status_code == 429 and "chat_transaction" in again.text

    # Quotas are per verified user: a second member of the same household is unaffected.
    mate = world.signup("QuotaMate")
    world.join(mate, flat, world.invite(user, flat, "peer"))
    assert mate.api.post("/agent/chat-transaction", json=body).status_code == 200

    # Clients cannot reset or probe quotas through PostgREST (service-role-only functions/table).
    assert user.rpc("consume_quota", {"p_user_id": user.id, "p_bucket": "chat_transaction", "p_limit": 9999,
                                      "p_window_seconds": 1}).status_code in (401, 403, 404)
    wipe = user.rest.delete(f"/api_quota?user_id=eq.{user.id}")
    assert wipe.status_code in (401, 403, 404) or db.scalar(
        "SELECT count(*) FROM public.api_quota WHERE user_id = %s", (user.id,)) == 1


def test_receipt_scan_quota(world, db, llm):
    flat = world.roommates("Q2", n_members=0)
    user = flat.admin
    _away_from_window_edge(600)
    qr = tlv_qr("Panda", "300000000000003", "2026-10-19T10:00:00Z", "20.00", "2.61")
    body = {"household_id": flat.id, "qr_code_raw": qr, "preview_only": True}
    statuses = [user.api.post("/agent/scan-receipt", json=body).status_code for _ in range(10)]
    assert statuses == [200] * 10
    assert user.api.post("/agent/scan-receipt", json=body).status_code == 429
    assert db.scalar("SELECT count FROM public.api_quota WHERE user_id = %s AND bucket = 'scan_receipt'",
                     (user.id,)) == 11


@pytest.fixture()
def resend(stack, monkeypatch):
    """Configure the Resend provider against the gateway's local capture endpoint."""
    monkeypatch.setenv("RESEND_API_KEY", "re_e2e_fake_key")
    stack.gateway.emails.clear()
    stack.gateway.resend_status = 200
    yield stack.gateway
    stack.gateway.resend_status = 200


def _public(world, client_ip=None, **overrides):
    payload = {"type": "contact", "email": "visitor@example.com", "name": "Visitor", "message": "Hello there",
               "locale": "ar", "source": "web"}
    payload.update(overrides)
    # X-Forwarded-For names the client when proxy headers are trusted (TRUST_PROXY_HEADERS).
    headers = {"X-Forwarded-For": client_ip} if client_ip else {}
    return world.anonymous_api(**headers).post("/public/inquiries", json=payload)


def test_inquiries_without_mail_provider_answer_503(world, stack):
    assert not os.environ.get("RESEND_API_KEY") and not os.environ.get("SMTP_HOST")
    res = _public(world)
    assert res.status_code == 503, res.text
    user = world.signup("Asker")
    app = user.api.post("/support/inquiries", json={"message": "Need help"})
    assert app.status_code == 503, app.text
    assert stack.gateway.emails == []


def test_inquiries_with_mocked_provider(world, resend):
    res = _public(world, type="vip_early_access", message=None, email="VIP.Person@Example.COM")
    assert res.status_code == 200, res.text
    assert res.json()["status"] == "sent"
    assert len(resend.emails) == 1
    mail = resend.emails[0]
    assert mail["to"] == ["inbox@e2e.test"] and mail["reply_to"] == "VIP.Person@example.com"
    assert mail["_authorization"] == "Bearer re_e2e_fake_key"
    assert "VIP early access" in mail["subject"]

    # Honeypot: answered like a success, nothing sent.
    bot = _public(world, company_website="http://spam.example")
    assert bot.status_code == 200 and len(resend.emails) == 1

    # In-app support: identity comes from the verified JWT only.
    user = world.signup("Helpme")
    app = user.api.post("/support/inquiries", json={"message": "Crash on receipts", "locale": "en"})
    assert app.status_code == 200, app.text
    body = resend.emails[-1]["text"]
    assert f"Verified user ID: {user.id}" in body and user.email in body
    spoof = user.api.post("/support/inquiries", json={"message": "x", "user_id": "someone-else"})
    assert spoof.status_code == 422
    assert world.anonymous_api().post("/support/inquiries", json={"message": "x"}).status_code == 401

    # Provider failure is reported (502), never a fake success.
    resend.resend_status = 500
    failed = _public(world, email="other@example.com")
    assert failed.status_code == 502, failed.text


def test_public_inquiry_per_ip_limit(world, resend, monkeypatch):
    monkeypatch.setenv("TRUST_PROXY_HEADERS", "1")  # as on Railway (RAILWAY_ENVIRONMENT)
    statuses = [_public(world, "203.0.113.70", email=f"p{i}@example.com").status_code for i in range(5)]
    assert statuses == [200] * 5
    limited = _public(world, "203.0.113.70", email="p6@example.com")
    assert limited.status_code == 429
    assert len(resend.emails) == 5
    # FABLE-API-03: the limit is the client's, not everyone's behind the same proxy.
    assert _public(world, "203.0.113.71", email="p7@example.com").status_code == 200
    assert _public(world, email="p8@example.com").status_code == 200  # no client address: no per-IP bucket
