"""
FABLE2-API-02: /budgets/recurring-bills/toggle wrote member-supplied keys into the admin-only
budgets row without bounds (a 500 kB ``sub_code`` per request grew budgets.sub_allocations without
limit). ``category_code`` / ``sub_code`` are Code fields (1-60 characters) and ``sub_code`` must be
an allocation key of that budget or a known sub-category of that category: 422 otherwise.
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
def w(api, fake_supabase):
    w = World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})
    fake_supabase.seed("cost_control_codes", [
        {"id": "c-util", "code": "OPEX-UTILITIES", "category": "Utilities", "keywords": ["stc"],
         "is_flexible": False, "household_id": None, "is_system": True},
    ])
    fake_supabase.seed("cost_control_sub_categories", [
        {"parent_code": "OPEX-UTILITIES", "sub_code": "water_municipal", "name_en": "Water", "name_ar": "ماء"},
        {"parent_code": "OPEX-GROCERY", "sub_code": "meat", "name_en": "Meat", "name_ar": "لحم"},
    ])
    r = api.post("/budgets/sub-allocations", json={
        "household_id": w.hid, "category_code": "OPEX-UTILITIES", "sub_allocations": {"electricity_sec": 300},
    }, headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    return w


def _toggle(api, w, who="omar", **body):
    return api.post("/budgets/recurring-bills/toggle", json={"household_id": w.hid, "is_recurring": True, **body},
                    headers=w.hdr(who))


def _config(fake):
    budget = next(b for b in fake.tables["budgets"] if b["category_code"] == "OPEX-UTILITIES")
    return budget["sub_allocations"].get("_recurring_config") or {}


def test_oversized_codes_are_422(api, fake_supabase, w):
    r = _toggle(api, w, category_code="OPEX-UTILITIES", sub_code="S" * 500_000)
    assert r.status_code == 422
    r = _toggle(api, w, category_code="X" * 100_000, sub_code="electricity_sec")
    assert r.status_code == 422
    r = _toggle(api, w, category_code="OPEX-UTILITIES", sub_code="S" * 61)
    assert r.status_code == 422
    r = _toggle(api, w, category_code="OPEX-UTILITIES", sub_code="")
    assert r.status_code == 422
    assert _config(fake_supabase) == {}


def test_unknown_sub_code_is_422_and_nothing_is_stored(api, fake_supabase, w):
    for sub in ("not_a_sub", "meat", "_recurring_config", "_meta"):
        r = _toggle(api, w, category_code="OPEX-UTILITIES", sub_code=sub)
        assert r.status_code == 422, (sub, r.text)
    assert _config(fake_supabase) == {}


def test_allocation_key_and_known_sub_category_are_accepted(api, fake_supabase, w):
    r = _toggle(api, w, category_code="OPEX-UTILITIES", sub_code="electricity_sec", due_day=5)
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    r = _toggle(api, w, category_code="OPEX-UTILITIES", sub_code="water_municipal", is_recurring=False)
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    cfg = _config(fake_supabase)
    assert cfg["electricity_sec"] == {"enabled": True, "due_day": 5}
    assert cfg["water_municipal"] == {"enabled": False}
