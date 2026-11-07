"""
Budgeting a category (sub-allocations) and switching one on take a category code from the
request. Only a system category or one of the household's own custom categories is accepted:
another household's custom code or an unknown code would leave budget rows and settings under
a code the household cannot see. Both refusals give the same answer, so nothing is revealed
about other households' codes.
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
def households(fake_supabase):
    a = World(fake_supabase, {"admin_a": ("admin", "peer")})
    b = World(fake_supabase, {"admin_b": ("admin", "peer")})
    fake_supabase.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-UTILITIES", "category": "Utilities", "household_id": None, "is_system": True},
        {"id": "c2", "code": "CUSTOM-PETS", "category": "Pets", "household_id": a.hid, "is_system": False},
        {"id": "c3", "code": "CUSTOM-SECRET", "category": "Secret", "household_id": b.hid, "is_system": False},
    ])
    return fake_supabase, a, b


def _rows(fake, table, hid, code):
    return [r for r in fake.tables.get(table, []) if r.get("household_id") == hid and r.get("category_code") == code]


def _save_sub_allocations(api, world, code):
    return api.post(
        "/budgets/sub-allocations",
        json={"household_id": world.hid, "category_code": code, "sub_allocations": {"sub-one": 100.0}},
        headers=world.hdr("admin_a"),
    )


def _toggle(api, world, code, is_active):
    return api.post(
        f"/households/{world.hid}/categories/toggle",
        json={"category_code": code, "is_active": is_active},
        headers=world.hdr("admin_a"),
    )


@pytest.mark.parametrize("code", ["CUSTOM-SECRET", "CUSTOM-NOWHERE"])
def test_sub_allocations_refuse_a_code_the_household_cannot_use(api, households, code):
    from salary_cycle import CATEGORY_FORBIDDEN

    fake, a, _ = households
    r = _save_sub_allocations(api, a, code)
    assert r.status_code == 403 and r.json()["detail"] == CATEGORY_FORBIDDEN
    assert _rows(fake, "budgets", a.hid, code) == []
    assert _rows(fake, "household_category_settings", a.hid, code) == []


@pytest.mark.parametrize("code", ["OPEX-UTILITIES", "CUSTOM-PETS"])
def test_sub_allocations_accept_system_and_own_codes(api, households, code):
    fake, a, _ = households
    r = _save_sub_allocations(api, a, code)
    assert r.status_code == 200, r.text
    assert [b["allocated_amount"] for b in _rows(fake, "budgets", a.hid, code)] == [100.0]


@pytest.mark.parametrize("code", ["CUSTOM-SECRET", "CUSTOM-NOWHERE"])
def test_switching_on_refuses_a_code_the_household_cannot_use(api, households, code):
    from salary_cycle import CATEGORY_FORBIDDEN

    fake, a, _ = households
    r = _toggle(api, a, code, True)
    assert r.status_code == 403 and r.json()["detail"] == CATEGORY_FORBIDDEN
    assert _rows(fake, "household_category_settings", a.hid, code) == []
    assert _rows(fake, "budgets", a.hid, code) == []


@pytest.mark.parametrize("code", ["OPEX-UTILITIES", "CUSTOM-PETS"])
def test_switching_on_accepts_system_and_own_codes(api, households, code):
    fake, a, _ = households
    r = _toggle(api, a, code, True)
    assert r.status_code == 200, r.text
    assert [s["is_active"] for s in _rows(fake, "household_category_settings", a.hid, code)] == [True]


def test_switching_off_is_not_restricted(api, households):
    """Switching off only touches the household's own rows, so any code may be switched off."""
    fake, a, _ = households
    r = _toggle(api, a, "CUSTOM-NOWHERE", False)
    assert r.status_code == 200, r.text
