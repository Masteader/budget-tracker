"""
Product review 4.1 / "Stop doing" (API-33): no container-local state.

Household settings (payday, income, rollover rule, savings), invites and dependents used to fall
back to ``ai_service/data/*.json`` or to process memory when the database call failed. On Railway
that state was ephemeral and differed per instance: a payday "saved" to one container's file was
invisible to the next request. The database is now the only store, and a database failure is an
error response, never a silent local write or a stale local read.
"""
from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

import dependents_service
import supabase_client
from main import app

HID = "f860188e-23b5-4749-b180-868c956151a6"
AI_SERVICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
client = TestClient(app)


@pytest.fixture()
def db_down(monkeypatch):
    def unreachable():
        raise ConnectionError("database unreachable")

    monkeypatch.setattr(supabase_client, "get_client", unreachable)


def test_no_file_fallbacks_remain():
    assert not hasattr(supabase_client, "HOUSEHOLD_SETTINGS_FILE")
    assert not hasattr(supabase_client, "HOUSEHOLD_INVITES_FILE")
    assert not hasattr(dependents_service, "_memory_dependents")
    for name in ("household_settings.json", "household_invites.json"):
        assert not os.path.exists(os.path.join(AI_SERVICE, "data", name)), name


@pytest.mark.parametrize("call", [
    lambda: supabase_client.get_household_payday(HID),
    lambda: supabase_client.set_household_payday(HID, 10),
    lambda: supabase_client.get_household_income(HID),
    lambda: supabase_client.set_household_income(HID, 9000),
    lambda: supabase_client.get_household_rollover_rule(HID),
    lambda: supabase_client.set_household_rollover_rule(HID, "fresh_start"),
    lambda: supabase_client.add_household_savings_surplus(HID, 100.0, "2026-11"),
    lambda: supabase_client.get_household_savings_summary(HID),
])
def test_settings_raise_when_the_database_fails(db_down, call):
    with pytest.raises(supabase_client.HouseholdSettingsUnavailable):
        call()


def test_settings_routes_answer_an_error_not_a_local_success(db_down, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    put = client.put(f"/households/{HID}/payday", json={"payday_day": 10})
    assert put.status_code == 500 and "Failed to update household payday" in put.json()["detail"]
    get = client.get(f"/households/{HID}/payday")
    assert get.status_code == 500
    assert list(tmp_path.iterdir()) == []


def test_settings_round_trip_through_the_database(fake_supabase):
    fake_supabase.seed("households", [{"id": HID, "payday_day": 27}])
    assert supabase_client.set_household_payday(HID, 10) == 10
    assert fake_supabase.tables["households"][0]["payday_day"] == 10
    assert supabase_client.get_household_payday(HID) == 10
    assert supabase_client.set_household_income(HID, 12000) == 12000.0
    assert supabase_client.get_household_income(HID) == 12000.0


def test_missing_household_row_uses_defaults_without_files(fake_supabase):
    assert supabase_client.get_household_payday(HID) == 27
    assert supabase_client.get_household_income(HID) == 0.0
    assert supabase_client.get_household_rollover_rule(HID) == "send_to_savings"
    with pytest.raises(supabase_client.HouseholdSettingsUnavailable):
        supabase_client.add_household_savings_surplus(HID, 50.0, "2026-11")


@pytest.mark.parametrize("call", [
    lambda: dependents_service.get_household_dependents(HID),
    lambda: dependents_service.create_household_dependent(HID, "Sarah"),
    lambda: dependents_service.delete_household_dependent(HID, "d1"),
    lambda: dependents_service.link_dependent_user(HID, "d1", "u1"),
])
def test_dependents_raise_when_the_database_fails(db_down, call):
    with pytest.raises(dependents_service.DependentsUnavailable):
        call()


def test_dependent_created_while_the_database_is_down_is_not_listed_later(fake_supabase, monkeypatch):
    real = supabase_client.get_client

    def unreachable():
        raise ConnectionError("database unreachable")

    monkeypatch.setattr(supabase_client, "get_client", unreachable)
    res = client.post(f"/households/{HID}/dependents", json={"name": "Sarah", "avatar_icon": "child"})
    assert res.status_code == 500
    monkeypatch.setattr(supabase_client, "get_client", real)
    listed = client.get(f"/households/{HID}/dependents")
    assert listed.status_code == 200 and listed.json()["dependents"] == []


def test_dependents_round_trip_through_the_database(fake_supabase):
    dep = dependents_service.create_household_dependent(HID, " Fahad ", relationship="child")
    assert dep["name"] == "Fahad" and dep["household_id"] == HID
    assert [d["id"] for d in dependents_service.get_household_dependents(HID)] == [dep["id"]]
    assert dependents_service.link_dependent_user(HID, dep["id"], "user-1")["linked_user_id"] == "user-1"
    assert dependents_service.link_dependent_user("another-household", dep["id"], "user-2") is None
    assert dependents_service.delete_household_dependent(HID, dep["id"]) is True
    assert dependents_service.get_household_dependents(HID) == []


def test_invites_never_use_a_local_file(db_down, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    with pytest.raises(Exception):
        supabase_client.create_household_role_invite(HID, "peer")
    with pytest.raises(Exception):
        supabase_client.inspect_household_role_invite("ABCDEF0123456789")
    claim = supabase_client.claim_household_role_invite("ABCDEF0123456789", "u1")
    assert claim["status"] == "error"
    assert list(tmp_path.iterdir()) == []


def test_invite_round_trip_through_the_database(fake_supabase):
    inv = supabase_client.create_household_role_invite(HID, "spouse")
    assert fake_supabase.tables["household_invites"][0]["invite_code"] == inv["invite_code"]
    seen = supabase_client.inspect_household_role_invite(inv["invite_code"].lower())
    assert seen["is_valid"] is True and seen["role"] == "spouse"
    unknown = supabase_client.inspect_household_role_invite("0000000000000000")
    assert unknown["is_valid"] is False
