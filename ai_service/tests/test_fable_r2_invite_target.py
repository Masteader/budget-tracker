"""
FABLE2-API-06: POST /households/{id}/invites with ``target_member_id``.

The id is checked before the insert: not a UUID → 400; not a dependent (manual member) of this
household → 404. A database refusal of the insert (the validate_invite_target_member trigger,
23503; RLS 42501; ...) is a 4xx, never a 500. Inspecting an invite only names a dependent of the
invite's own household.
"""
from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

import fakes
from fable_world import World


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def homes(fake_supabase):
    a = World(fake_supabase, {"ahmed": ("admin", "peer")})
    b = World(fake_supabase, {"badr": ("admin", "provider"), "huda": ("member", "spouse")})
    own_dep, foreign_dep = str(uuid.uuid4()), str(uuid.uuid4())
    fake_supabase.seed("household_dependents", [
        {"id": own_dep, "household_id": a.hid, "name": "Kid A"},
        {"id": foreign_dep, "household_id": b.hid, "name": "Secret Kid"},
    ])
    return a, b, own_dep, foreign_dep


def _invite(api, w, target, who="ahmed", role="family_member"):
    return api.post(f"/households/{w.hid}/invites", json={"role": role, "target_member_id": target},
                    headers=w.hdr(who))


@pytest.mark.parametrize("target", ["not-a-uuid", pytest.param("x" * 5000, id="long"), "1; drop table"])
def test_malformed_target_is_400(api, fake_supabase, homes, target):
    a, *_ = homes
    r = _invite(api, a, target)
    assert r.status_code == 400, r.text
    assert not fake_supabase.tables.get("household_invites")


def test_foreign_or_unknown_dependent_is_404(api, fake_supabase, homes):
    a, b, _own, foreign = homes
    for target in (foreign, str(uuid.uuid4()), a.users["ahmed"]):
        r = _invite(api, a, target)
        assert r.status_code == 404, r.text
        assert "Secret Kid" not in r.text
    assert not fake_supabase.tables.get("household_invites")


def test_own_dependent_is_accepted_and_named(api, fake_supabase, homes):
    a, _b, own, _foreign = homes
    r = _invite(api, a, own)
    assert r.status_code == 200, r.text
    code = r.json()["invite_code"]
    ins = api.get(f"/households/invites/{code}", headers=a.hdr("ahmed")).json()
    assert ins["target_member_name"] == "Kid A"


def test_untargeted_invite_unchanged(api, fake_supabase, homes):
    a, *_ = homes
    r = api.post(f"/households/{a.hid}/invites", json={"role": "family_member"}, headers=a.hdr("ahmed"))
    assert r.status_code == 200 and r.json()["target_member_id"] is None


@pytest.mark.parametrize("code, status", [("23503", 404), ("42501", 403), ("23514", 422), ("23505", 409)])
def test_database_refusal_is_4xx(api, fake_supabase, homes, monkeypatch, code, status):
    a, _b, own, _foreign = homes
    original = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "household_invites" and self._op == "insert":
            raise APIError({"code": code, "message": "internal db text", "hint": None, "details": None})
        return original(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)
    r = _invite(api, a, own)
    assert r.status_code == status, r.text
    assert "internal db text" not in r.text


def test_inspect_never_names_a_dependent_of_another_household(api, fake_supabase, homes):
    """An invite row bound to a foreign dependent (written before the trigger existed)."""
    a, _b, _own, foreign = homes
    fake_supabase.seed("household_invites", [{
        "household_id": a.hid, "invite_code": "ABCDEF0123456789", "role": "family_member",
        "target_member_id": foreign, "expires_at": None,
    }])
    ins = api.get("/households/invites/ABCDEF0123456789", headers=a.hdr("ahmed")).json()
    assert ins["target_member_name"] is None
