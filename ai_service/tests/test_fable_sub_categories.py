"""
FABLE-API-04, FABLE-API-05 and FABLE-API-08 (docs/review/audit/fable_review.md).

Sub-category definitions have no household column. Households can therefore no longer create
definitions under a SYSTEM category through the API (only allocate to the seeded ones), keywords
shorter than 3 characters are never stored or matched, keyword matching only considers seeded
system definitions plus definitions under a custom category the transaction's household owns
alone, and rename/purge need the caller's household to be the sole owner of the parent code.
Every refusal uses one message, so the answers reveal nothing about other households' codes.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from fable_world import World, zatca_qr


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def seeded(fake_supabase):
    fake_supabase.seed("cost_control_codes", [{
        "id": "c1", "code": "OPEX-GROCERY", "category": "Groceries", "keywords": ["panda", "tamimi"],
        "is_flexible": True, "household_id": None, "is_system": True,
    }])
    fake_supabase.seed("cost_control_sub_categories", [
        {"parent_code": "OPEX-GROCERY", "sub_code": "meat", "name_en": "Meat", "name_ar": "لحوم", "keywords": ["meat", "لحم"]},
    ])
    return fake_supabase


def _two_households(fake):
    a = World(fake, {"attacker": ("admin", "peer"), "a2": ("member", "peer")})
    b = World(fake, {"victim": ("admin", "peer"), "v2": ("member", "peer")})
    return a, b


# ─── FABLE-API-04 ─────────────────────────────────────────────────────────────

def test_no_new_definitions_under_a_system_category(api, seeded):
    from salary_cycle import SUB_CATEGORY_FORBIDDEN

    a, _ = _two_households(seeded)
    r = api.post("/budgets/sub-categories",
                 json={"household_id": a.hid, "parent_code": "OPEX-GROCERY", "name_en": "e", "sub_code": "sub-planted-by-a"},
                 headers=a.hdr("attacker"))
    assert r.status_code == 403 and r.json()["detail"] == SUB_CATEGORY_FORBIDDEN
    assert [s["sub_code"] for s in seeded.tables["cost_control_sub_categories"]] == ["meat"]
    # Allocating to a seeded system sub-category is still allowed.
    r = api.post("/budgets/sub-categories",
                 json={"household_id": a.hid, "parent_code": "OPEX-GROCERY", "name_en": "Meat", "sub_code": "meat",
                       "allocated_amount": 150},
                 headers=a.hdr("attacker"))
    assert r.status_code == 200, r.text
    assert r.json()["sub_allocations"]["meat"] == 150.0


def test_planted_definition_no_longer_reclassifies_other_households(api, seeded):
    """A definition planted before this fix (live data) under a system parent with a one-letter
    keyword: B's ZATCA receipt is no longer filed under it."""
    a, b = _two_households(seeded)
    seeded.seed("cost_control_sub_categories", [{
        "parent_code": "OPEX-GROCERY", "sub_code": "sub-planted-by-a", "name_en": "e", "name_ar": "e", "keywords": ["e"],
    }])
    r = api.post("/agent/scan-receipt", json={"household_id": b.hid, "qr_code_raw": zatca_qr("115.00", vat="15.00")},
                 headers=b.hdr("victim"))
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    tx = next(t for t in seeded.tables["transactions"] if t["household_id"] == b.hid)
    assert tx["category_code"] == "OPEX-GROCERY"
    assert tx.get("sub_category") != "sub-planted-by-a"


def test_match_sub_category_scope_and_keyword_length(seeded):
    from salary_cycle import match_sub_category

    a, b = _two_households(seeded)
    seeded.seed("cost_control_codes", [
        {"id": "c2", "code": "CUSTOM-PETS", "category": "Pets", "household_id": a.hid, "is_system": False},
    ])
    seeded.seed("cost_control_sub_categories", [
        {"parent_code": "OPEX-GROCERY", "sub_code": "planted", "name_en": "x", "name_ar": "x", "keywords": ["chicken"]},
        {"parent_code": "CUSTOM-PETS", "sub_code": "cat_food", "name_en": "Cat food", "name_ar": "x", "keywords": ["whiskas"]},
        {"parent_code": "CUSTOM-PETS", "sub_code": "short", "name_en": "x", "name_ar": "x", "keywords": ["ab"]},
    ])
    # Seeded system definitions match for everyone; a planted one under a system parent never does.
    assert match_sub_category("OPEX-GROCERY", "fresh meat", None, household_id=b.hid) == "meat"
    assert match_sub_category("OPEX-GROCERY", "grilled chicken", None, household_id=b.hid) != "planted"
    # A custom category's definitions only for the household that owns it.
    assert match_sub_category("CUSTOM-PETS", "whiskas 4kg", None, household_id=a.hid) == "cat_food"
    assert match_sub_category("CUSTOM-PETS", "whiskas 4kg", None, household_id=b.hid) is None
    # Keywords shorter than 3 characters never match.
    assert match_sub_category("CUSTOM-PETS", "ab ab ab", None, household_id=a.hid) is None


def test_short_names_store_no_keyword(api, seeded):
    a, _ = _two_households(seeded)
    r = api.post(f"/households/{a.hid}/categories/custom", json={"code": "PETS", "category": "Pets"},
                 headers=a.hdr("attacker"))
    assert r.status_code == 200, r.text
    r = api.post("/budgets/sub-categories",
                 json={"household_id": a.hid, "parent_code": "CUSTOM-PETS", "name_en": "e", "sub_code": "e1"},
                 headers=a.hdr("attacker"))
    assert r.status_code == 200, r.text
    row = next(s for s in seeded.tables["cost_control_sub_categories"] if s["sub_code"] == "e1")
    assert row["keywords"] == []


# ─── FABLE-API-05 / FABLE-API-08 ──────────────────────────────────────────────

def test_colliding_custom_code_cannot_rename_the_other_households_sub_category(api, seeded):
    from salary_cycle import SUB_CATEGORY_FORBIDDEN

    a, b = _two_households(seeded)
    for w, who in ((b, "victim"), (a, "attacker")):
        r = api.post(f"/households/{w.hid}/categories/custom", json={"code": "RENT", "category": "Rent"},
                     headers=w.hdr(who))
        assert r.status_code == 200, r.text
    seeded.seed("cost_control_sub_categories", [
        {"parent_code": "CUSTOM-RENT", "sub_code": "villa", "name_en": "Villa Riyadh", "name_ar": "x", "keywords": ["villa"]},
    ])
    r = api.patch("/budgets/sub-categories",
                  json={"parent_code": "CUSTOM-RENT", "sub_code": "villa", "name_en": "PWNED by A", "name_ar": "x"},
                  headers=a.hdr("attacker"))
    assert r.status_code == 403 and r.json()["detail"] == SUB_CATEGORY_FORBIDDEN
    assert seeded.tables["cost_control_sub_categories"][-1]["name_en"] == "Villa Riyadh"
    # Nor can either of them add definitions under the shared code.
    r = api.post("/budgets/sub-categories",
                 json={"household_id": a.hid, "parent_code": "CUSTOM-RENT", "name_en": "Flat"},
                 headers=a.hdr("attacker"))
    assert r.status_code == 403 and r.json()["detail"] == SUB_CATEGORY_FORBIDDEN


def test_sole_owner_admin_can_still_rename(api, seeded):
    a, _ = _two_households(seeded)
    assert api.post(f"/households/{a.hid}/categories/custom", json={"code": "SCHOOL", "category": "School"},
                    headers=a.hdr("attacker")).status_code == 200
    seeded.seed("cost_control_sub_categories", [
        {"parent_code": "CUSTOM-SCHOOL", "sub_code": "books", "name_en": "Books", "name_ar": "x", "keywords": ["books"]},
    ])
    r = api.patch("/budgets/sub-categories", json={"parent_code": "CUSTOM-SCHOOL", "sub_code": "books", "name_en": "Textbooks"},
                  headers=a.hdr("attacker"))
    assert r.status_code == 200, r.text
    # A plain member of the owning household gets the same refusal as everyone else.
    r = api.patch("/budgets/sub-categories", json={"parent_code": "CUSTOM-SCHOOL", "sub_code": "books", "name_en": "X"},
                  headers=a.hdr("a2"))
    from salary_cycle import SUB_CATEGORY_FORBIDDEN

    assert r.status_code == 403 and r.json()["detail"] == SUB_CATEGORY_FORBIDDEN


def test_rename_is_not_an_existence_oracle(api, seeded):
    a, b = _two_households(seeded)
    assert api.post(f"/households/{b.hid}/categories/custom", json={"code": "SCHOOL", "category": "School"},
                    headers=b.hdr("victim")).status_code == 200
    body = {"sub_code": "x", "name_en": "y"}
    answers = [
        api.patch("/budgets/sub-categories", json={**body, "parent_code": code}, headers=a.hdr("attacker"))
        for code in ("CUSTOM-NOPE", "CUSTOM-SCHOOL", "OPEX-GROCERY")
    ]
    assert {r.status_code for r in answers} == {403}
    assert len({r.json()["detail"] for r in answers}) == 1, [r.text for r in answers]
