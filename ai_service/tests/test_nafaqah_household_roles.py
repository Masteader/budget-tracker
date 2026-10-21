"""
Household roles and the explicit Nafaqah provider (Fable review, migration 20261020800000).

FABLE-LOGIC-01: the financial role is per membership. A wife who joins a roommate flat stays the
wife of her family; a spouse who joins a flat by code is a roommate there.
FABLE-LOGIC-04: the husband is households.nafaqah_provider_user_id (default: the primary admin;
an admin changes it to a non-spouse member); never inferred from roles or admin rights.
FABLE-LOGIC-02: the database guard's refusal (HINT ledger_would_be_overpaid) maps to HTTP 409,
and the ledger balance exposes ``overpaid``.

Requests carry real HS256 JWTs (the module name keeps it out of the conftest auth mock), and
membership is resolved from the in-memory FakeSupabaseClient.
"""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt

import nafaqah_service as ns
from household_permissions import list_members
from main import app
from routes.nafaqah import nafaqah_http_error
from settlement_engine import calculate_settlement_v2

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

FAMILY = "aaaa0000-0000-4000-8000-000000000001"
FLAT = "aaaa0000-0000-4000-8000-000000000002"
SON_HOUSE = "aaaa0000-0000-4000-8000-000000000003"
HUSBAND = "0000aaaa-0000-4000-8000-00000000000a"
WIFE = "0000aaaa-0000-4000-8000-00000000000b"
SON = "0000aaaa-0000-4000-8000-00000000000c"
MATE1 = "0000aaaa-0000-4000-8000-0000000000f1"
MATE2 = "0000aaaa-0000-4000-8000-0000000000f2"
OTHER_WIFE = "0000aaaa-0000-4000-8000-0000000000e1"
OUTSIDER = "0000aaaa-0000-4000-8000-0000000000d1"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def _m(user_id, household_id, role, financial_role, day):
    return {"user_id": user_id, "household_id": household_id, "role": role, "financial_role": financial_role,
            "created_at": f"2026-01-0{day}T00:00:00+00:00"}


@pytest.fixture()
def homes(fake_supabase):
    # users.financial_role is only the cache of the ACTIVE household: the wife's active household
    # is the flat ('peer' there), the other wife's cache says 'spouse' from her own family.
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": FAMILY, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": FLAT, "role": "member", "financial_role": "peer", "display_name": "Sara"},
        {"id": SON, "household_id": SON_HOUSE, "role": "admin", "financial_role": "provider", "display_name": "Fahad"},
        {"id": MATE1, "household_id": FLAT, "role": "admin", "financial_role": "peer", "display_name": "Ali"},
        {"id": MATE2, "household_id": FLAT, "role": "member", "financial_role": "peer", "display_name": "Saad"},
        {"id": OTHER_WIFE, "household_id": FLAT, "role": "member", "financial_role": "spouse", "display_name": "Huda"},
        {"id": OUTSIDER, "household_id": None, "role": "member", "financial_role": "provider", "display_name": "Omar"},
    ])
    fake_supabase.seed("household_memberships", [
        _m(HUSBAND, FAMILY, "admin", "provider", 1),
        _m(WIFE, FAMILY, "member", "spouse", 2),
        _m(SON, FAMILY, "member", "family_member", 3),
        _m(MATE1, FLAT, "admin", "peer", 1),
        _m(MATE2, FLAT, "member", "peer", 2),
        _m(WIFE, FLAT, "member", "peer", 3),        # the wife also shares a flat
        _m(OTHER_WIFE, FLAT, "member", "peer", 4),  # a spouse elsewhere, joined the flat by code
        _m(SON, SON_HOUSE, "admin", "provider", 1),  # the son created his own household
        _m(HUSBAND, SON_HOUSE, "member", "family_member", 2),
        _m(WIFE, SON_HOUSE, "member", "spouse", 3),
    ])
    fake_supabase.seed("households", [
        {"id": FAMILY, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND},
        {"id": FLAT, "payday_day": 27, "owner_user_id": MATE1, "nafaqah_provider_user_id": MATE1},
        {"id": SON_HOUSE, "payday_day": 27, "owner_user_id": SON, "nafaqah_provider_user_id": SON},
    ])
    fake_supabase.seed("transactions", [
        {"id": "adv", "household_id": FAMILY, "amount": 100.0, "merchant": "Panda", "cycle_key": "2026-11",
         "timestamp": "2026-11-10T09:00:00+00:00", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
    ])
    fake_supabase.seed("spouse_reimbursements", [
        {"id": "r1", "household_id": FAMILY, "wife_user_id": WIFE, "amount": 130.0, "payment_method": "cash",
         "created_at": "2026-11-12T09:00:00+00:00"},
    ])

    def set_provider(params):
        for h in fake_supabase.tables["households"]:
            if h["id"] == params["p_household_id"]:
                previous = h.get("nafaqah_provider_user_id")
                h["nafaqah_provider_user_id"] = params["p_user_id"]
                return {"success": True, "household_id": h["id"], "nafaqah_provider_user_id": params["p_user_id"],
                        "previous_provider_user_id": previous}
        raise AssertionError("unknown household")

    fake_supabase.rpc_handlers["set_nafaqah_provider"] = set_provider
    return fake_supabase


# ─── FABLE-LOGIC-01: per-household roles ──────────────────────────────────────

def test_wife_in_a_flat_stays_the_wife_of_her_family(homes):
    family = ns.load_family_context(FAMILY)
    assert family.is_family and [w["id"] for w in family.wives] == [WIFE]
    assert family.husband_id == HUSBAND

    flat = ns.load_family_context(FLAT)
    assert not flat.is_family and flat.husband_id is None
    assert {m["financial_role"] for m in flat.members.values()} == {"peer"}


def test_flat_settles_as_roommates_despite_a_spouse_member_elsewhere(homes):
    assert calculate_settlement_v2(FLAT)["mode"] == "multi_roommate"
    assert calculate_settlement_v2(FAMILY)["mode"] == "family_nafaqah"


def test_members_list_shows_the_role_in_that_household(homes):
    flat = {m["user_id"]: m["financial_role"] for m in list_members(FLAT, MATE1)["members"]}
    assert flat[WIFE] == "peer" and flat[OTHER_WIFE] == "peer"
    family = {m["user_id"]: m["financial_role"] for m in list_members(FAMILY, HUSBAND)["members"]}
    assert family[WIFE] == "spouse"


def test_missing_membership_role_is_never_read_as_spouse(homes):
    for m in homes.tables["household_memberships"]:
        if m["household_id"] == FAMILY and m["user_id"] == WIFE:
            del m["financial_role"]
    ctx = ns.load_family_context(FAMILY)
    assert not ctx.is_family and ctx.members[WIFE]["financial_role"] == "family_member"


# ─── FABLE-LOGIC-04: explicit provider ────────────────────────────────────────

def test_son_who_created_the_household_is_the_default_provider(homes):
    ctx = ns.load_family_context(SON_HOUSE)
    assert ctx.husband_id == SON and ctx.role_of(SON) == "husband" and ctx.role_of(HUSBAND) == "member"


def test_admin_changes_the_provider_through_the_rpc(homes):
    res = client.put(f"/households/{SON_HOUSE}/nafaqah/provider", headers=bearer(SON), json={"user_id": HUSBAND})
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["provider_user_id"] == HUSBAND and body["previous_provider_user_id"] == SON
    assert body["summary"]["husband"]["id"] == HUSBAND and body["summary"]["provider_user_id"] == HUSBAND
    name, params = homes.rpc_calls[-1]
    assert name == "set_nafaqah_provider"
    assert params == {"p_household_id": SON_HOUSE, "p_user_id": HUSBAND, "p_actor_user_id": SON}
    assert ns.load_family_context(SON_HOUSE).husband_id == HUSBAND


@pytest.mark.parametrize("actor,target,status", [
    (HUSBAND, HUSBAND, 403),   # a member (not an admin) of SON_HOUSE
    (OUTSIDER, HUSBAND, 403),  # not a member at all
    (SON, WIFE, 422),          # a wife cannot be the provider
    (SON, MATE1, 422),         # not a member of this household
])
def test_provider_change_is_refused(homes, actor, target, status):
    calls = len(homes.rpc_calls)
    res = client.put(f"/households/{SON_HOUSE}/nafaqah/provider", headers=bearer(actor), json={"user_id": target})
    assert res.status_code == status, res.text
    assert len(homes.rpc_calls) == calls


def test_provider_body_must_be_a_uuid(homes):
    res = client.put(f"/households/{SON_HOUSE}/nafaqah/provider", headers=bearer(SON), json={"user_id": "husband"})
    assert res.status_code == 422


def test_database_refusal_of_the_provider_is_mapped(homes):
    class FakeApiError(Exception):
        code = "22023"
        hint = "provider_is_spouse"

    def refuse(_params):
        raise FakeApiError("A spouse member cannot be the Nafaqah provider")

    homes.rpc_handlers["set_nafaqah_provider"] = refuse
    res = client.put(f"/households/{SON_HOUSE}/nafaqah/provider", headers=bearer(SON), json={"user_id": HUSBAND})
    assert res.status_code == 422


def test_family_without_provider_needs_one(homes):
    for h in homes.tables["households"]:
        if h["id"] == FAMILY:
            h["nafaqah_provider_user_id"] = None
    ctx = ns.load_family_context(FAMILY)
    assert ctx.is_family and ctx.husband_id is None and ctx.needs_provider
    body = client.get(f"/households/{FAMILY}/nafaqah", headers=bearer(HUSBAND)).json()
    assert body["needs_provider"] is True and body["provider_user_id"] is None and body["husband"] is None
    assert body["can_set_provider"] is True
    # The settlement still never splits the spouses (no husband id: nothing he paid is a debt).
    assert calculate_settlement_v2(FAMILY)["mode"] == "family_nafaqah"


def test_a_wife_is_never_the_husband_even_if_stored_as_provider(homes):
    for h in homes.tables["households"]:
        if h["id"] == FAMILY:
            h["nafaqah_provider_user_id"] = WIFE
    assert ns.load_family_context(FAMILY).husband_id is None


def test_members_list_exposes_the_provider(homes):
    body = client.get(f"/households/{SON_HOUSE}/members", headers=bearer(SON)).json()
    assert body["nafaqah_provider_user_id"] == SON and body["can_set_nafaqah_provider"] is True
    assert {m["user_id"] for m in body["members"] if m["is_nafaqah_provider"]} == {SON}
    member_view = client.get(f"/households/{SON_HOUSE}/members", headers=bearer(HUSBAND)).json()
    assert member_view["can_set_nafaqah_provider"] is False


# ─── FABLE-LOGIC-02: overpaid ledger ──────────────────────────────────────────

def test_summary_exposes_overpaid_and_provider(homes):
    body = client.get(f"/households/{FAMILY}/nafaqah", headers=bearer(WIFE)).json()
    assert body["provider_user_id"] == HUSBAND and body["needs_provider"] is False
    assert body["can_set_provider"] is False
    balance = body["wives"][0]["reimbursement"]
    assert balance["outstanding"] == 0.0 and balance["overpaid"] == 30.0


def test_ledger_guard_refusal_maps_to_409():
    class FakeApiError(Exception):
        code = "22023"
        hint = "ledger_would_be_overpaid"
        message = "This change would leave the wife's reimbursement ledger overpaid: 200 SAR already repaid"

    exc = FakeApiError(FakeApiError.message)
    assert ns.is_ledger_overpaid_error(exc)
    mapped = ns._map_db_error(exc)
    assert isinstance(mapped, ns.LedgerWouldBeOverpaid)
    http = nafaqah_http_error(mapped)
    assert http.status_code == 409 and http.detail["code"] == "ledger_would_be_overpaid"


def test_no_provider_refusal_maps_to_409():
    class FakeApiError(Exception):
        code = "23514"
        hint = "no_nafaqah_provider"
        message = "Household x has no Nafaqah provider"

    mapped = ns._map_db_error(FakeApiError(FakeApiError.message))
    assert isinstance(mapped, ns.NoProviderError)
    http = nafaqah_http_error(mapped)
    assert http.status_code == 409 and http.detail["code"] == "no_provider"


def test_unrelated_errors_are_not_taken_for_the_ledger_guard():
    assert not ns.is_ledger_overpaid_error(Exception("connection reset"))


# ─── FABLE-LOGIC-06: wife_personal stays out of the category budgets ─────────

def _seed_budget_case(fake):
    fake.seed("budgets", [{"id": "b-shop", "household_id": FAMILY, "category_code": "OPEX-SHOPPING", "cycle_key": "2026-11",
                           "month": "2026-11-01", "allocated_amount": 1000.0, "spent_amount": 0.0, "is_active": True}])
    fake.seed("transactions", [
        {"id": "abaya", "household_id": FAMILY, "amount": 400.0, "category_code": "OPEX-SHOPPING", "cycle_key": "2026-11",
         "timestamp": "2026-11-05T09:00:00+00:00", "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE},
        {"id": "towels", "household_id": FAMILY, "amount": 100.0, "category_code": "OPEX-SHOPPING", "cycle_key": "2026-11",
         "timestamp": "2026-11-06T09:00:00+00:00"},
    ])


def test_budget_recalculation_skips_wife_personal(homes):
    from installment_service import InstallmentService

    _seed_budget_case(homes)
    InstallmentService.recalculate_budgets(FAMILY, "2026-11")
    budget = next(b for b in homes.tables["budgets"] if b["id"] == "b-shop")
    assert budget["spent_amount"] == 100.0


def test_cycle_breakdown_skips_wife_personal(homes):
    from salary_cycle import get_cycle_breakdown

    _seed_budget_case(homes)
    homes.tables["budgets"][0]["spent_amount"] = 100.0  # what the database triggers keep
    breakdown = get_cycle_breakdown(FAMILY, "2026-11")
    shopping = next(c for c in breakdown["categories"] if c["category_code"] == "OPEX-SHOPPING")
    assert shopping["spent_amount"] == 100.0
