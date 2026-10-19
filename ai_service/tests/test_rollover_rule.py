import os
import sys
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import app
from supabase_client import (
    get_household_rollover_rule,
    set_household_rollover_rule,
    get_household_savings_summary,
    add_household_savings_surplus,
)

client = TestClient(app)
AUTH_HEADERS = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}


def test_default_rollover_rule_is_send_to_savings(tmp_path, monkeypatch):
    test_file = str(tmp_path / "test_settings.json")
    monkeypatch.setattr("supabase_client.HOUSEHOLD_SETTINGS_FILE", test_file)

    rule = get_household_rollover_rule("hh_test_default_123")
    assert rule == "send_to_savings"


def test_set_and_get_rollover_rules(tmp_path, monkeypatch):
    test_file = str(tmp_path / "test_settings.json")
    monkeypatch.setattr("supabase_client.HOUSEHOLD_SETTINGS_FILE", test_file)
    hid = "hh_custom_rule_456"

    # Default
    assert get_household_rollover_rule(hid) == "send_to_savings"

    # Change to rollover_to_categories
    set_household_rollover_rule(hid, "rollover_to_categories")
    assert get_household_rollover_rule(hid) == "rollover_to_categories"

    # Change to fresh_start
    set_household_rollover_rule(hid, "fresh_start")
    assert get_household_rollover_rule(hid) == "fresh_start"

    # Invalid rule should fall back safely to send_to_savings
    set_household_rollover_rule(hid, "invalid_option")
    assert get_household_rollover_rule(hid) == "send_to_savings"


def test_savings_surplus_accumulation(tmp_path, monkeypatch):
    test_file = str(tmp_path / "test_settings.json")
    monkeypatch.setattr("supabase_client.HOUSEHOLD_SETTINGS_FILE", test_file)
    hid = "hh_savings_accum_789"

    summary0 = get_household_savings_summary(hid)
    assert summary0["accumulated_savings"] == 0.0
    assert summary0["rollover_rule"] == "send_to_savings"

    # Add surplus from cycle 1
    add_household_savings_surplus(hid, 450.50, "2026-09")
    summary1 = get_household_savings_summary(hid)
    assert summary1["accumulated_savings"] == 450.50
    assert summary1["last_rollover_surplus"] == 450.50

    # Add surplus from cycle 2
    add_household_savings_surplus(hid, 250.00, "2026-10")
    summary2 = get_household_savings_summary(hid)
    assert summary2["accumulated_savings"] == 700.50
    assert summary2["last_rollover_surplus"] == 250.00


def test_rollover_rule_api_endpoints(tmp_path, monkeypatch):
    test_file = str(tmp_path / "test_settings.json")
    monkeypatch.setattr("supabase_client.HOUSEHOLD_SETTINGS_FILE", test_file)
    hid = "f860188e-23b5-4749-b180-868c956151a6"

    # GET default
    resp = client.get(f"/households/{hid}/rollover-rule", headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert data["household_id"] == hid
    assert data["rollover_rule"] == "send_to_savings"

    # PUT update
    put_resp = client.put(
        f"/households/{hid}/rollover-rule",
        json={"rollover_rule": "rollover_to_categories"},
        headers=AUTH_HEADERS,
    )
    assert put_resp.status_code == 200
    assert put_resp.json()["rollover_rule"] == "rollover_to_categories"
    assert put_resp.json()["status"] == "success"

    # GET savings summary endpoint
    sum_resp = client.get(f"/households/{hid}/savings-summary", headers=AUTH_HEADERS)
    assert sum_resp.status_code == 200
    assert sum_resp.json()["household_id"] == hid
    assert sum_resp.json()["rollover_rule"] == "rollover_to_categories"


def test_savings_surplus_accumulates_on_existing_household_row(fake_supabase):
    """When the households row exists, the DB total is authoritative and incremented, not reset."""
    hid = "f860188e-23b5-4749-b180-868c956151a6"
    fake_supabase.seed("households", [{"id": hid, "accumulated_savings": 100.0}])
    assert add_household_savings_surplus(hid, 50.25, "2026-11") == 150.25
    row = fake_supabase.tables["households"][0]
    assert row["accumulated_savings"] == 150.25
    assert row["last_rollover_cycle"] == "2026-11"
