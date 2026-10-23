"""
FABLE-API-03 (docs/review/audit/fable_review.md): behind Railway's proxy (an address that is not in
TRUSTED_PROXY_IPS) every visitor shared one per-IP bucket, so 5 inquiries/hour or 20 invite
inspections/minute locked out the whole site.

Now: the forwarded header is trusted when configured (TRUST_PROXY_HEADERS=1) or detected (Railway
sets RAILWAY_ENVIRONMENT), taking the client hop Railway's edge appends (right-most, or
TRUSTED_PROXY_HOPS from the right); a per-IP limit only applies to an address that really is the
client's; and the limits are keyed per identity (e-mail, verified user) under a generous global
ceiling.
"""
from __future__ import annotations

import types
import uuid

import pytest
from fastapi.testclient import TestClient

from fable_world import bearer


@pytest.fixture
def api(monkeypatch):
    for var in ("TRUST_PROXY_HEADERS", "TRUSTED_PROXY_HOPS", "RAILWAY_ENVIRONMENT", "RAILWAY_ENVIRONMENT_NAME"):
        monkeypatch.delenv(var, raising=False)
    from main import app

    with TestClient(app) as c:
        yield c


def _req(peer, xff=None):
    headers = {"X-Forwarded-For": xff} if xff else {}
    return types.SimpleNamespace(client=types.SimpleNamespace(host=peer), headers=headers)


def _inquiry(api, email, xff):
    return api.post("/public/inquiries", json={"type": "vip_early_access", "email": email, "source": "web"},
                    headers={"X-Forwarded-For": xff})


# ─── client IP resolution ──────────────────────────────────────────────────────

def test_untrusted_peer_ignores_forwarded_header(monkeypatch):
    from utils import client_ip_info

    monkeypatch.delenv("TRUST_PROXY_HEADERS", raising=False)
    monkeypatch.delenv("RAILWAY_ENVIRONMENT", raising=False)
    assert client_ip_info(_req("10.1.2.3", "203.0.113.9")) == ("10.1.2.3", False)  # private proxy hop
    assert client_ip_info(_req("8.8.4.4", "203.0.113.9")) == ("8.8.4.4", True)  # direct client


@pytest.mark.parametrize("env", [{"TRUST_PROXY_HEADERS": "1"}, {"RAILWAY_ENVIRONMENT": "production"}])
def test_railway_edge_hop_is_the_client(monkeypatch, env):
    from utils import client_ip_info

    monkeypatch.delenv("TRUST_PROXY_HEADERS", raising=False)
    monkeypatch.delenv("RAILWAY_ENVIRONMENT", raising=False)
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    # The client forged "1.1.1.1"; Railway's edge appended the real address on the right.
    assert client_ip_info(_req("10.0.0.7", "1.1.1.1, 203.0.113.9")) == ("203.0.113.9", True)
    assert client_ip_info(_req("10.0.0.7", "not-an-ip")) == ("10.0.0.7", False)


def test_trust_can_be_disabled_on_railway_and_hops_configured(monkeypatch):
    from utils import client_ip_info

    monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
    monkeypatch.setenv("TRUST_PROXY_HEADERS", "0")
    assert client_ip_info(_req("10.0.0.7", "203.0.113.9"))[1] is False
    monkeypatch.setenv("TRUST_PROXY_HEADERS", "1")
    monkeypatch.setenv("TRUSTED_PROXY_HOPS", "2")  # e.g. a CDN in front of Railway
    assert client_ip_info(_req("10.0.0.7", "1.1.1.1, 203.0.113.9, 198.51.100.1")) == ("203.0.113.9", True)


# ─── public inquiries ──────────────────────────────────────────────────────────

def test_reviewer_case_one_proxy_address_no_longer_locks_everyone_out(api):
    for i in range(5):
        assert _inquiry(api, f"user{i}@example.com", f"203.0.113.{i + 1}").status_code in (200, 503)
    # A sixth, unrelated visitor is not locked out by the others.
    assert _inquiry(api, "someone-else@example.org", "198.51.100.77").status_code in (200, 503)


def test_per_email_limit_still_applies(api):
    for i in range(3):
        assert _inquiry(api, "same@example.com", f"203.0.113.{i + 1}").status_code in (200, 503)
    r = _inquiry(api, "same@example.com", "203.0.113.50")
    assert r.status_code == 429 and r.headers.get("Retry-After")


def test_per_ip_limit_applies_to_real_client_addresses(api, monkeypatch):
    monkeypatch.setenv("TRUST_PROXY_HEADERS", "1")
    for i in range(5):
        assert _inquiry(api, f"u{i}@example.com", "203.0.113.20").status_code in (200, 503)
    assert _inquiry(api, "u9@example.com", "203.0.113.20").status_code == 429
    # Another client behind the same proxy is unaffected.
    assert _inquiry(api, "v1@example.com", "203.0.113.21").status_code in (200, 503)


def test_global_ceiling_caps_the_mailbox(api, monkeypatch):
    import routes.inquiries as inquiries

    monkeypatch.setattr(inquiries, "GLOBAL_LIMIT", 4)
    for i in range(4):
        assert _inquiry(api, f"g{i}@example.com", f"203.0.113.{i + 1}").status_code in (200, 503)
    assert _inquiry(api, "g9@example.com", "203.0.113.99").status_code == 429


# ─── invite inspection ─────────────────────────────────────────────────────────

def test_invite_inspection_is_limited_per_user_not_per_proxy(api):
    for i in range(20):
        r = api.get("/households/invites/ABCDEF0123456789",
                    headers={"X-Forwarded-For": f"203.0.113.{i + 1}", **bearer(str(uuid.uuid4()))})
        assert r.status_code == 200, r.text
    # A 21st signed-in user behind the same proxy is still served ...
    me = str(uuid.uuid4())
    r = api.get("/households/invites/ABCDEF0123456789", headers={"X-Forwarded-For": "198.51.100.77", **bearer(me)})
    assert r.status_code == 200, r.text
    # ... while one user hammering the endpoint is limited.
    for _ in range(19):
        api.get("/households/invites/ABCDEF0123456789", headers=bearer(me))
    assert api.get("/households/invites/ABCDEF0123456789", headers=bearer(me)).status_code == 429
