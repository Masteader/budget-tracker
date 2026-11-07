"""
Budgeting a category (sub-allocations) and switching one on take a category code from the
request. Only a system category or one of the household's own custom categories is accepted:
another household's custom code or an unknown code would leave budget rows and settings under
a code the household cannot see. Both refusals give the same answer, so nothing is revealed
about other households' codes. Named test_fable_* so the real JWT and admin checks run.
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


def test_an_uppercase_household_id_still_owns_its_codes(households):
    """Postgres reads an uppercase UUID as the same household, so the check must too."""
    from salary_cycle import category_usable_by_household

    _, a, _ = households
    assert category_usable_by_household("CUSTOM-PETS", a.hid.upper())
    assert not category_usable_by_household("CUSTOM-SECRET", a.hid.upper())


def test_sub_category_ownership_checks_read_the_household_id_in_canonical_form(households):
    from salary_cycle import sub_category_parent_visible, sub_category_write_allowed

    _, a, b = households
    assert sub_category_write_allowed("CUSTOM-PETS", "cat_food", a.hid.upper())
    assert sub_category_parent_visible("CUSTOM-PETS", [a.hid.upper()])
    assert not sub_category_write_allowed("CUSTOM-PETS", "cat_food", b.hid.upper())


def test_a_household_row_flagged_system_is_not_shared(households):
    """Only rows without a household are shared, as the database trigger reads it
    (validate_category_code_exists): a household's row flagged is_system stays that household's."""
    from salary_cycle import category_usable_by_household

    fake, a, b = households
    fake.seed("cost_control_codes", [
        {"id": "c4", "code": "CUSTOM-FLAGGED", "category": "Flagged", "household_id": a.hid, "is_system": True},
    ])
    assert category_usable_by_household("CUSTOM-FLAGGED", a.hid)
    assert not category_usable_by_household("CUSTOM-FLAGGED", b.hid)


@pytest.mark.parametrize("code", ["CUSTOM-SECRET", "CUSTOM-NOWHERE"])
def test_switching_off_refuses_a_code_the_household_cannot_use(api, households, code):
    """The database trigger refuses the settings write for such a code; the route answers that
    with the same clean 403 as switching on, not a 500."""
    from salary_cycle import CATEGORY_FORBIDDEN

    fake, a, _ = households
    r = _toggle(api, a, code, False)
    assert r.status_code == 403 and r.json()["detail"] == CATEGORY_FORBIDDEN
    assert _rows(fake, "household_category_settings", a.hid, code) == []


def test_switching_off_an_own_code_works(api, households):
    fake, a, _ = households
    r = _toggle(api, a, "CUSTOM-PETS", False)
    assert r.status_code == 200, r.text
    assert [s["is_active"] for s in _rows(fake, "household_category_settings", a.hid, "CUSTOM-PETS")] == [False]


def test_an_uppercase_household_id_sees_and_edits_its_own_custom_category(households):
    from types import SimpleNamespace
    from salary_cycle import add_category_and_budget, get_household_categories

    fake, a, _ = households
    codes = {c["code"] for c in get_household_categories(a.hid.upper())["active"] + get_household_categories(a.hid.upper())["inactive"]}
    assert "CUSTOM-PETS" in codes
    add_category_and_budget(SimpleNamespace(
        household_id=a.hid.upper(), code="CUSTOM-PETS", category="Pets & Vet", allocated_amount=50.0,
        keywords=None, is_flexible=False))
    rows = [c for c in fake.tables["cost_control_codes"] if c["code"] == "CUSTOM-PETS"]
    assert [(r["household_id"], r["category"]) for r in rows] == [(a.hid, "Pets & Vet")], "edited, not duplicated"


def test_match_sub_category_reads_the_household_id_in_canonical_form(households):
    from salary_cycle import match_sub_category

    fake, a, _ = households
    fake.seed("cost_control_sub_categories", [
        {"parent_code": "CUSTOM-PETS", "sub_code": "cat_food", "name_en": "Cat food", "name_ar": "x", "keywords": ["whiskas"]},
    ])
    assert match_sub_category("CUSTOM-PETS", "WHISKAS 2kg", household_id=a.hid.upper()) == "cat_food"
