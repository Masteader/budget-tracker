"""
FABLE-API-07 (docs/review/audit/fable_review.md): the recurring-bill configuration is stored inside
budgets.sub_allocations["_recurring_config"]; adding/removing a sub-category then failed with 500
(float() of a dict) and saving sub-allocations erased the configuration. ``_``-prefixed keys are
metadata: skipped by every numeric path and preserved on save (clients cannot write them).
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from fable_world import World


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def w(fake_supabase, api):
    w = World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})
    fake_supabase.seed("cost_control_codes", [
        {"id": "c-util", "code": "OPEX-UTILITIES", "category": "Utilities", "keywords": ["stc"],
         "is_flexible": False, "household_id": None, "is_system": True},
        {"id": "c-home", "code": "CUSTOM-HOME", "category": "Home", "keywords": [],
         "is_flexible": False, "household_id": w.hid, "is_system": False},
    ])
    r = api.post("/budgets/sub-allocations", json={
        "household_id": w.hid, "category_code": "OPEX-UTILITIES",
        "sub_allocations": {"electricity_sec": 300, "fiber_internet": 250},
    }, headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    r = api.post("/budgets/recurring-bills/toggle", json={
        "household_id": w.hid, "category_code": "OPEX-UTILITIES", "sub_code": "electricity_sec",
        "is_recurring": True, "due_day": 5, "custom_name": "SEC bill",
    }, headers=w.hdr("omar"))
    assert r.status_code == 200, r.text
    return w


def _subs(fake):
    return next(b for b in fake.tables["budgets"] if b["category_code"] == "OPEX-UTILITIES")["sub_allocations"]


def test_add_sub_category_keeps_working_and_keeps_the_config(api, fake_supabase, w):
    r = api.post("/budgets/sub-categories", json={
        "household_id": w.hid, "parent_code": "OPEX-UTILITIES", "name_en": "Water", "sub_code": "water_municipal",
        "allocated_amount": 120,
    }, headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    assert r.json()["allocated_amount"] == 670.0
    subs = _subs(fake_supabase)
    assert subs["water_municipal"] == 120.0
    assert subs["_recurring_config"]["electricity_sec"]["due_day"] == 5


def test_remove_sub_category_keeps_working_and_keeps_the_config(api, fake_supabase, w):
    r = api.delete("/budgets/sub-categories", params={
        "household_id": w.hid, "parent_code": "OPEX-UTILITIES", "sub_code": "fiber_internet",
    }, headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    row = next(b for b in fake_supabase.tables["budgets"] if b["category_code"] == "OPEX-UTILITIES")
    assert row["allocated_amount"] == 300.0
    assert "fiber_internet" not in row["sub_allocations"]
    assert row["sub_allocations"]["_recurring_config"]["electricity_sec"]["due_day"] == 5


def test_saving_sub_allocations_preserves_the_config(api, fake_supabase, w):
    r = api.post("/budgets/sub-allocations", json={
        "household_id": w.hid, "category_code": "OPEX-UTILITIES",
        "sub_allocations": {"electricity_sec": 310, "fiber_internet": 250},
    }, headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    assert r.json()["allocated_amount"] == 560.0
    assert _subs(fake_supabase)["_recurring_config"]["electricity_sec"]["due_day"] == 5
    assert _subs(fake_supabase)["electricity_sec"] == 310.0


def test_clients_cannot_write_metadata_keys(api, fake_supabase, w):
    r = api.post("/budgets/sub-allocations", json={
        "household_id": w.hid, "category_code": "OPEX-UTILITIES",
        "sub_allocations": {"electricity_sec": 300, "_recurring_config": 1},
    }, headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    assert r.json()["allocated_amount"] == 300.0
    assert isinstance(_subs(fake_supabase)["_recurring_config"], dict)


def test_breakdown_succeeds_with_recurring_config_metadata(api, fake_supabase, w):
    # Verify that get_budget_breakdown ignores _recurring_config and doesn't throw TypeError (float of dict)
    r = api.get(f"/budgets/breakdown?household_id={w.hid}", headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    data = r.json()
    cats = data.get("categories", [])
    util_cat = next((c for c in cats if c.get("category_code") == "OPEX-UTILITIES"), None)
    assert util_cat is not None
    sub_codes = [s.get("sub_code") for s in util_cat.get("sub_categories", [])]
    assert "_recurring_config" not in sub_codes
    assert "electricity_sec" in sub_codes
