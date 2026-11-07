"""
The budget dialog saves through POST /budgets/sub-allocations, also for a category budgeted
without sub-categories (one parent amount) and for sinking-fund settings. Before, the dialog
wrote those rows itself and fell back to the phone's calendar month when it had no cycle.

- ``allocated_amount``: the parent amount of a category without sub-category amounts (refused
  together with sub-category amounts, whose sum is the parent amount).
- ``sinking_fund``: the accumulate settings per sub-category (``_parent`` for the parent),
  stored under ``sub_allocations["_sinking_fund"]``; an empty object clears them, leaving it out
  keeps the stored ones. Inside ``sub_allocations`` an object was refused (422).

Named test_fable_* so the real JWT and admin checks run.
"""
from __future__ import annotations

from datetime import datetime

import pytest
from fastapi.testclient import TestClient

import utils
from fable_world import World


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def w(fake_supabase, api, monkeypatch):
    # 28 Nov in Riyadh, paid on the 27th: the open cycle is 2026-12, not the calendar month.
    instant = datetime.fromisoformat("2026-11-28T09:00:00+00:00")
    monkeypatch.setattr(utils, "utc_now", lambda: instant)
    w = World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")}, payday=27)
    fake_supabase.seed("cost_control_codes", [
        {"id": "c-char", "code": "OPEX-CHARITY", "category": "Charity", "keywords": [],
         "is_flexible": True, "household_id": None, "is_system": True},
        {"id": "c-groc", "code": "OPEX-GROCERY", "category": "Grocery", "keywords": [],
         "is_flexible": True, "household_id": None, "is_system": True},
    ])
    return w


def _post(api, w, body, who="ahmed"):
    return api.post("/budgets/sub-allocations", json={"household_id": w.hid, **body}, headers=w.hdr(who))


def _rows(fake, w, code):
    return [b for b in fake.tables.get("budgets", []) if b["household_id"] == w.hid and b["category_code"] == code]


def test_parent_amount_without_sub_categories_is_saved_in_the_household_cycle(api, fake_supabase, w):
    r = _post(api, w, {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "success"
    assert body["cycle_key"] == "2026-12"
    assert body["allocated_amount"] == 300.0
    [row] = _rows(fake_supabase, w, "OPEX-CHARITY")
    assert row["allocated_amount"] == 300.0
    assert row["cycle_key"] == "2026-12" and row["month"] == "2026-12-01"
    assert row["is_active"] is True
    assert row["sub_allocations"] == {}
    settings = [s for s in fake_supabase.tables["household_category_settings"]
                if s["household_id"] == w.hid and s["category_code"] == "OPEX-CHARITY"]
    assert [s["is_active"] for s in settings] == [True]


def test_parent_amount_updates_that_cycles_row_and_keeps_its_metadata(api, fake_supabase, w):
    fake_supabase.seed("budgets", [
        {"id": "b-nov", "household_id": w.hid, "category_code": "OPEX-CHARITY", "cycle_key": "2026-11",
         "month": "2026-11-01", "allocated_amount": 50.0, "spent_amount": 0.0, "is_active": True,
         "sub_allocations": {}},
        {"id": "b-dec", "household_id": w.hid, "category_code": "OPEX-CHARITY", "cycle_key": "2026-12",
         "month": "2026-12-01", "allocated_amount": 80.0, "spent_amount": 0.0, "is_active": False,
         "sub_allocations": {"_recurring_config": {"_parent": {"due_day": 3}}}},
    ])
    r = _post(api, w, {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 250})
    assert r.status_code == 200, r.text
    rows = {b["id"]: b for b in _rows(fake_supabase, w, "OPEX-CHARITY")}
    assert len(rows) == 2
    assert rows["b-nov"]["allocated_amount"] == 50.0, "another cycle's row is not taken over"
    assert rows["b-dec"]["allocated_amount"] == 250.0
    assert rows["b-dec"]["is_active"] is True
    assert rows["b-dec"]["sub_allocations"]["_recurring_config"] == {"_parent": {"due_day": 3}}


def test_parent_amount_together_with_sub_category_amounts_is_refused(api, fake_supabase, w):
    r = _post(api, w, {"category_code": "OPEX-GROCERY", "sub_allocations": {"meat": 100}, "allocated_amount": 300})
    assert r.status_code == 422
    assert _rows(fake_supabase, w, "OPEX-GROCERY") == []


@pytest.mark.parametrize("amount", [-1, 10_000_001])
def test_parent_amount_is_bounded(api, fake_supabase, w, amount):
    r = _post(api, w, {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": amount})
    assert r.status_code == 422
    assert _rows(fake_supabase, w, "OPEX-CHARITY") == []


def test_sub_category_amounts_still_sum_to_the_parent(api, fake_supabase, w):
    r = _post(api, w, {"category_code": "OPEX-GROCERY", "sub_allocations": {"meat": 100, "dairy_eggs": 50.5}})
    assert r.status_code == 200, r.text
    [row] = _rows(fake_supabase, w, "OPEX-GROCERY")
    assert row["allocated_amount"] == 150.5
    assert row["sub_allocations"] == {"meat": 100.0, "dairy_eggs": 50.5}


def test_sinking_fund_settings_are_stored(api, fake_supabase, w):
    r = _post(api, w, {
        "category_code": "OPEX-GROCERY",
        "sub_allocations": {"meat": 100},
        "sinking_fund": {"meat": {"accumulate": True, "base_amount": 100}},
    })
    assert r.status_code == 200, r.text
    [row] = _rows(fake_supabase, w, "OPEX-GROCERY")
    assert row["allocated_amount"] == 100.0
    assert row["sub_allocations"]["_sinking_fund"] == {"meat": {"accumulate": True, "base_amount": 100.0}}


def test_parent_sinking_fund_is_stored_with_the_parent_amount(api, fake_supabase, w):
    r = _post(api, w, {
        "category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300,
        "sinking_fund": {"_parent": {"accumulate": True, "base_amount": 300}},
    })
    assert r.status_code == 200, r.text
    [row] = _rows(fake_supabase, w, "OPEX-CHARITY")
    assert row["allocated_amount"] == 300.0
    assert row["sub_allocations"] == {"_sinking_fund": {"_parent": {"accumulate": True, "base_amount": 300.0}}}


def test_empty_sinking_fund_clears_and_leaving_it_out_keeps_it(api, fake_supabase, w):
    stored = {"_parent": {"accumulate": True, "base_amount": 300.0}}
    fake_supabase.seed("budgets", [
        {"id": "b-dec", "household_id": w.hid, "category_code": "OPEX-CHARITY", "cycle_key": "2026-12",
         "month": "2026-12-01", "allocated_amount": 300.0, "spent_amount": 0.0, "is_active": True,
         "sub_allocations": {"_sinking_fund": stored}},
    ])
    r = _post(api, w, {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300})
    assert r.status_code == 200, r.text
    assert _rows(fake_supabase, w, "OPEX-CHARITY")[0]["sub_allocations"]["_sinking_fund"] == stored

    r = _post(api, w, {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300,
                       "sinking_fund": {}})
    assert r.status_code == 200, r.text
    assert _rows(fake_supabase, w, "OPEX-CHARITY")[0]["sub_allocations"]["_sinking_fund"] == {}


@pytest.mark.parametrize("entry", [
    {"accumulate": True, "base_amount": -5},
    {"accumulate": True, "base_amount": 10_000_001},
    {"accumulate": True, "base_amount": 5, "extra": 1},
    {"accumulate": "maybe", "base_amount": 5},
])
def test_invalid_sinking_fund_settings_are_refused(api, fake_supabase, w, entry):
    r = _post(api, w, {"category_code": "OPEX-GROCERY", "sub_allocations": {"meat": 100},
                       "sinking_fund": {"meat": entry}})
    assert r.status_code == 422
    assert _rows(fake_supabase, w, "OPEX-GROCERY") == []


def test_a_member_cannot_save_a_parent_amount(api, fake_supabase, w):
    r = _post(api, w, {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300}, who="omar")
    assert r.status_code == 403
    assert _rows(fake_supabase, w, "OPEX-CHARITY") == []


@pytest.mark.parametrize("body", [
    # A parent-only save: only "_parent" is a sub-category of the category itself.
    {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300,
     "sinking_fund": {"ghost": {"accumulate": True, "base_amount": 0}}},
    {"category_code": "OPEX-CHARITY", "sub_allocations": {}, "allocated_amount": 300,
     "sinking_fund": {"_parent": {"accumulate": True, "base_amount": 300},
                      "ghost": {"accumulate": True, "base_amount": 0}}},
    # With sub-category amounts, every key is one of them.
    {"category_code": "OPEX-GROCERY", "sub_allocations": {"meat": 100},
     "sinking_fund": {"dairy_eggs": {"accumulate": True, "base_amount": 50}}},
    {"category_code": "OPEX-GROCERY", "sub_allocations": {"meat": 100},
     "sinking_fund": {"_parent": {"accumulate": True, "base_amount": 100}}},
])
def test_sinking_fund_for_a_sub_category_not_sent_is_refused(api, fake_supabase, w, body):
    # A key with no amount changed the next cycle's rollover (the parent got its base amount added).
    r = _post(api, w, body)
    assert r.status_code == 422, r.text
    assert _rows(fake_supabase, w, body["category_code"]) == []
