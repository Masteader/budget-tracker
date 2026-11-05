"""The grace-period guards in the database reach API callers as 409 with a machine code.

The hints come from supabase/migrations/20261105000100_account_deletion_schema.sql. The app maps the
code to a localized message, and database text is never echoed.
"""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt
from postgrest.exceptions import APIError

from main import app

SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

ROOM = "aaaa0000-0000-4000-8000-000000000001"
FAMILY = "bbbb0000-0000-4000-8000-000000000002"
PRIMARY = "00000000-0000-4000-8000-0000000000a1"
MEMBER = "00000000-0000-4000-8000-0000000000a2"
HUSBAND = "00000000-0000-4000-8000-0000000000b1"
UNCLE = "00000000-0000-4000-8000-0000000000b2"
DB_TEXT = "secret database wording for t47@example.com"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, SECRET, algorithm='HS256')}"}


def refusal(hint: str) -> APIError:
    return APIError({"code": "22023", "hint": hint, "details": None, "message": DB_TEXT})


def _raises(hint: str):
    def handler(_params):
        raise refusal(hint)
    return handler


@pytest.fixture()
def homes(fake_supabase):
    fake_supabase.seed("households", [
        {"id": ROOM, "name": "Flat", "owner_user_id": PRIMARY, "household_type": "roommates"},
        {"id": FAMILY, "name": "Home", "owner_user_id": HUSBAND, "household_type": "family",
         "nafaqah_provider_user_id": HUSBAND},
    ])
    fake_supabase.seed("users", [
        {"id": PRIMARY, "household_id": ROOM, "role": "admin", "financial_role": "peer", "display_name": "P"},
        {"id": MEMBER, "household_id": ROOM, "role": "member", "financial_role": "peer", "display_name": "M"},
        {"id": HUSBAND, "household_id": FAMILY, "role": "admin", "financial_role": "provider", "display_name": "H"},
        {"id": UNCLE, "household_id": FAMILY, "role": "member", "financial_role": "family_member", "display_name": "U"},
    ])
    fake_supabase.seed("household_memberships", [
        {"household_id": ROOM, "user_id": PRIMARY, "role": "admin", "financial_role": "peer", "created_at": "2026-01-01T00:00:00+00:00"},
        {"household_id": ROOM, "user_id": MEMBER, "role": "member", "financial_role": "peer", "created_at": "2026-01-02T00:00:00+00:00"},
        {"household_id": FAMILY, "user_id": HUSBAND, "role": "admin", "financial_role": "provider", "created_at": "2026-01-01T00:00:00+00:00"},
        {"household_id": FAMILY, "user_id": UNCLE, "role": "member", "financial_role": "family_member", "created_at": "2026-01-02T00:00:00+00:00"},
    ])
    return fake_supabase


def _assert_guard(res, code: str):
    assert res.status_code == 409, res.text
    detail = res.json()["detail"]
    assert detail["code"] == code
    assert detail["message"]
    assert DB_TEXT not in res.text


def test_new_invite_on_a_marked_household_is_409(homes, monkeypatch):
    real_table = homes.table

    class Refusing:
        def insert(self, _row):
            return self

        def execute(self):
            raise refusal("household_pending_deletion")

    monkeypatch.setattr(homes, "table", lambda name: Refusing() if name == "household_invites" else real_table(name))
    res = client.post(f"/households/{ROOM}/invites", headers=bearer(PRIMARY), json={"role": "peer"})
    _assert_guard(res, "household_pending_deletion")


def test_other_invite_refusals_keep_their_status(homes, monkeypatch):
    real_table = homes.table

    class Refusing:
        def insert(self, _row):
            return self

        def execute(self):
            raise APIError({"code": "22023", "hint": None, "details": None, "message": DB_TEXT})

    monkeypatch.setattr(homes, "table", lambda name: Refusing() if name == "household_invites" else real_table(name))
    res = client.post(f"/households/{ROOM}/invites", headers=bearer(PRIMARY), json={"role": "peer"})
    assert res.status_code == 422
    assert DB_TEXT not in res.text


@pytest.mark.parametrize("hint", ["account_pending_deletion", "household_pending_deletion"])
def test_claiming_an_invite_is_409_when_a_guard_refuses(homes, hint):
    homes.rpc_handlers["claim_household_role_invite"] = _raises(hint)
    res = client.post("/households/invites/ABCD1234/claim", headers=bearer(MEMBER))
    _assert_guard(res, hint)


def test_other_claim_failures_are_still_400(homes):
    homes.rpc_handlers["claim_household_role_invite"] = _raises("something_else")
    res = client.post("/households/invites/ABCD1234/claim", headers=bearer(MEMBER))
    assert res.status_code == 400
    assert DB_TEXT not in res.text


def test_promoting_a_pending_member_is_409(homes):
    homes.rpc_handlers["promote_member_to_admin"] = _raises("account_pending_deletion")
    res = client.post(f"/households/{ROOM}/members/{MEMBER}/admin", headers=bearer(PRIMARY))
    _assert_guard(res, "account_pending_deletion")


def test_transferring_primary_admin_to_a_pending_member_is_409(homes):
    """The database's message mentions the primary admin, which must not read as a 403."""
    def handler(_params):
        raise APIError({"code": "22023", "hint": "successor_pending_deletion", "details": None,
                        "message": "This member is scheduled for deletion and cannot become the primary admin"})

    homes.rpc_handlers["transfer_primary_admin"] = handler
    res = client.post(f"/households/{ROOM}/primary-admin", headers=bearer(PRIMARY),
                      json={"new_primary_user_id": MEMBER})
    assert res.status_code == 409, res.text
    assert res.json()["detail"]["code"] == "successor_pending_deletion"


def test_naming_a_pending_member_as_nafaqah_provider_is_409(homes):
    homes.rpc_handlers["set_nafaqah_provider"] = _raises("account_pending_deletion")
    res = client.put(f"/households/{FAMILY}/nafaqah/provider", headers=bearer(HUSBAND), json={"user_id": UNCLE})
    _assert_guard(res, "account_pending_deletion")
