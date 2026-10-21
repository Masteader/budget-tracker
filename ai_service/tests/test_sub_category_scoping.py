"""
E2E-05 (docs/review/audit/e2e_results.md): sub-category definitions are global
(public.cost_control_sub_categories has no household_id). The API must only list, and only let
an admin add, definitions whose parent is a system category or a custom category of the
caller's household; another household's custom category behaves like an unknown code.

Requests carry real HS256 JWTs (this module is excluded from the conftest auth mock), so
membership and admin checks are real.
"""

from __future__ import annotations

import time
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from jose import jwt

from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

HH_A = "aaaa0000-0000-4000-8000-00000000e501"
HH_B = "bbbb0000-0000-4000-8000-00000000e502"
A_ADMIN = "00000000-0000-4000-8000-0000000005a1"
A_MEMBER = "00000000-0000-4000-8000-0000000005a2"
B_ADMIN = "00000000-0000-4000-8000-0000000005b1"
SECRET = "B private sub-category"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


@pytest.fixture()
def db(fake_supabase):
    fake_supabase.seed("users", [
        {"id": A_ADMIN, "household_id": HH_A, "role": "admin"},
        {"id": A_MEMBER, "household_id": HH_A, "role": "member"},
        {"id": B_ADMIN, "household_id": HH_B, "role": "admin"},
    ])
    fake_supabase.seed("household_memberships", [
        {"household_id": HH_A, "user_id": A_ADMIN, "role": "admin"},
        {"household_id": HH_A, "user_id": A_MEMBER, "role": "member"},
        {"household_id": HH_B, "user_id": B_ADMIN, "role": "admin"},
    ])
    fake_supabase.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-DINING", "category": "Dining", "keywords": [], "is_flexible": False,
         "household_id": None, "is_system": True},
        {"id": "c2", "code": "CUSTOM-A-ONLY", "category": "A only", "keywords": [], "is_flexible": False,
         "household_id": HH_A, "is_system": False},
        {"id": "c3", "code": "CUSTOM-B-ONLY", "category": "B only", "keywords": [], "is_flexible": False,
         "household_id": HH_B, "is_system": False},
    ])
    fake_supabase.seed("cost_control_sub_categories", [
        {"id": "s1", "parent_code": "OPEX-DINING", "sub_code": "coffee", "name_en": "Coffee", "name_ar": "قهوة"},
        {"id": "s2", "parent_code": "CUSTOM-A-ONLY", "sub_code": "a-sub", "name_en": "A sub", "name_ar": "A"},
        {"id": "s3", "parent_code": "CUSTOM-B-ONLY", "sub_code": "b-sub", "name_en": SECRET, "name_ar": SECRET},
    ])
    return fake_supabase


def _list(user, parent_code, **params):
    return client.get("/budgets/sub-categories", params={"parent_code": parent_code, **params},
                      headers=bearer(user))


def test_system_category_sub_categories_are_listed(db):
    res = _list(A_MEMBER, "OPEX-DINING")
    assert res.status_code == 200, res.text
    assert [s["sub_code"] for s in res.json()["sub_categories"]] == ["coffee"]


def test_own_custom_category_sub_categories_are_listed(db):
    assert [s["sub_code"] for s in _list(A_MEMBER, "CUSTOM-A-ONLY").json()["sub_categories"]] == ["a-sub"]
    res = _list(A_MEMBER, "CUSTOM-A-ONLY", household_id=HH_A)
    assert [s["sub_code"] for s in res.json()["sub_categories"]] == ["a-sub"]


def test_other_households_custom_sub_categories_are_not_listed(db):
    res = _list(A_MEMBER, "CUSTOM-B-ONLY")
    assert res.status_code == 200, res.text
    assert res.json()["sub_categories"] == [] and SECRET not in res.text
    # Naming the caller's own household does not widen it either.
    res = _list(A_MEMBER, "CUSTOM-B-ONLY", household_id=HH_A)
    assert res.json()["sub_categories"] == [] and SECRET not in res.text
    # The owner still sees them.
    assert SECRET in _list(B_ADMIN, "CUSTOM-B-ONLY").text


def test_listing_for_a_household_the_caller_is_not_in_is_403(db):
    res = _list(A_MEMBER, "CUSTOM-B-ONLY", household_id=HH_B)
    assert res.status_code == 403 and SECRET not in res.text


def test_unknown_parent_lists_nothing(db):
    assert _list(A_MEMBER, "CUSTOM-NOPE").json()["sub_categories"] == []


def _add(user, household_id, parent_code, sub_code=None):
    body = {"household_id": household_id, "parent_code": parent_code, "name_en": "Planted", "allocated_amount": 0}
    if sub_code:
        body["sub_code"] = sub_code
    with patch("routes.budgets.add_sub_category_for_household", return_value={"status": "success"}) as work:
        res = client.post("/budgets/sub-categories", headers=bearer(user), json=body)
    return res, work


@pytest.mark.parametrize("parent,sub_code", [("OPEX-DINING", "coffee_bakeries"), ("CUSTOM-A-ONLY", None)])
def test_admin_adds_under_system_or_own_category(db, parent, sub_code):
    # Under a system category: an allocation to a seeded sub-category only (FABLE-API-04).
    res, work = _add(A_ADMIN, HH_A, parent, sub_code)
    assert res.status_code == 200, res.text
    work.assert_called_once()


def test_admin_cannot_define_new_sub_categories_under_a_system_category(db):
    res, work = _add(A_ADMIN, HH_A, "OPEX-DINING")
    assert res.status_code == 403, res.text
    work.assert_not_called()


@pytest.mark.parametrize("parent", ["CUSTOM-B-ONLY", "CUSTOM-NOPE"])
def test_admin_cannot_add_under_foreign_or_unknown_category(db, parent):
    res, work = _add(A_ADMIN, HH_A, parent)
    assert res.status_code == 403, res.text
    work.assert_not_called()


def test_member_cannot_add_sub_categories(db):
    res, work = _add(A_MEMBER, HH_A, "OPEX-DINING")
    assert res.status_code == 403
    work.assert_not_called()


def test_get_sub_categories_for_parent_scopes_by_household(db):
    from salary_cycle import get_sub_categories_for_parent

    assert get_sub_categories_for_parent("CUSTOM-B-ONLY", [HH_A]) == []
    assert [s["sub_code"] for s in get_sub_categories_for_parent("CUSTOM-B-ONLY", [HH_B])] == ["b-sub"]
    assert [s["sub_code"] for s in get_sub_categories_for_parent("OPEX-DINING", [HH_A])] == ["coffee"]
    # Internal callers without a household keep the unrestricted lookup.
    assert [s["sub_code"] for s in get_sub_categories_for_parent("CUSTOM-B-ONLY")] == ["b-sub"]
