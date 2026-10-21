"""
Helpers for the regression tests of the independent (Fable) review, docs/review/audit/fable_review.md.

Requests carry real HS256 JWTs minted with the test secret (``test_fable_*`` modules are excluded
from the conftest auth mock), so membership and admin checks run exactly as in production.
"""
from __future__ import annotations

import base64
import json
import time
import types
import uuid
from typing import Dict, Tuple

from jose import jwt

SUPABASE_URL = "https://mockproject.supabase.co"
JWT_SECRET = "super-secret-test-jwt-key-32bytes-long!"


def mint(sub: str, ttl: int = 3600, **overrides) -> str:
    """GoTrue-shaped HS256 access token signed with the test secret."""
    now = int(time.time())
    claims = {
        "sub": sub,
        "aud": "authenticated",
        "role": "authenticated",
        "iss": f"{SUPABASE_URL}/auth/v1",
        "iat": now,
        "exp": now + ttl,
        "email": f"{sub[:8]}@review.test",
    }
    claims.update(overrides)
    return jwt.encode(claims, JWT_SECRET, algorithm="HS256")


def bearer(sub: str, **kw) -> dict:
    return {"Authorization": f"Bearer {mint(sub, **kw)}"}


class World:
    """One household with a configurable roster, seeded into the fake like the real tables."""

    def __init__(self, fake, roles: Dict[str, Tuple[str, str]], payday: int = 27):
        self.fake = fake
        self.hid = str(uuid.uuid4())
        self.users: Dict[str, str] = {}
        memberships, users = [], []
        owner = None
        for i, (name, (role, fin_role)) in enumerate(roles.items()):
            uid = str(uuid.uuid4())
            self.users[name] = uid
            if owner is None and role == "admin":
                owner = uid
            memberships.append({
                "household_id": self.hid, "user_id": uid, "role": role,
                "created_at": f"2026-01-0{i + 1}T00:00:00+00:00",
            })
            users.append({"id": uid, "display_name": name, "financial_role": fin_role, "household_id": self.hid,
                          "role": role})
        fake.seed("household_memberships", memberships)
        fake.seed("users", users)
        fake.seed("households", [{"id": self.hid, "payday_day": payday, "owner_user_id": owner,
                                  "rollover_rule": "fresh_start"}])

    def hdr(self, name: str) -> dict:
        return bearer(self.users[name])


def tlv(tag: int, value: str) -> bytes:
    b = value.encode()
    return bytes([tag, len(b)]) + b


def zatca_qr(total: str = "300.00", seller: str = "Panda", vat: str = "39.13") -> str:
    return base64.b64encode(
        tlv(1, seller) + tlv(2, "300000000000003") + tlv(3, "2026-10-21T10:00:00Z") + tlv(4, total) + tlv(5, vat)
    ).decode()


def fake_llm(monkeypatch, payload: dict) -> None:
    import litellm

    def completion(*_a, **_k):
        msg = types.SimpleNamespace(content=json.dumps(payload))
        return types.SimpleNamespace(choices=[types.SimpleNamespace(message=msg)])

    monkeypatch.setattr(litellm, "completion", completion)


PNG_1x1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)
