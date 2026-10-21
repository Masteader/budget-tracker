"""
Observation in docs/review/audit/fable_review.md section C: auth._get_user_membership fell back to
the legacy users.household_id column when the household_memberships query itself errored, i.e. an
infrastructure error widened access. It now fails closed: no membership, no access.
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from fable_world import World


def _break_memberships(fake, monkeypatch):
    real_table = fake.table

    def table(name):
        if name == "household_memberships":
            raise RuntimeError("memberships query failed (simulated outage)")
        return real_table(name)

    monkeypatch.setattr(fake, "table", table)


def test_membership_query_error_denies_instead_of_falling_back(fake_supabase, monkeypatch):
    import auth

    w = World(fake_supabase, {"ahmed": ("admin", "peer")})  # users.household_id == w.hid
    assert auth._get_user_membership(w.users["ahmed"], w.hid)["role"] == "admin"
    _break_memberships(fake_supabase, monkeypatch)
    assert auth._get_user_membership(w.users["ahmed"], w.hid) is None


def test_route_is_refused_during_the_outage(fake_supabase, monkeypatch):
    from main import app

    w = World(fake_supabase, {"ahmed": ("admin", "peer")})
    _break_memberships(fake_supabase, monkeypatch)
    with TestClient(app) as api:
        r = api.get("/budgets/installments", params={"household_id": w.hid}, headers=w.hdr("ahmed"))
    assert r.status_code == 403, r.text
