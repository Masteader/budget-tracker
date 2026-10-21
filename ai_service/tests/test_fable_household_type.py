"""
Household type, members' financial roles and who may classify (owner decisions D1/D2,
FABLE2-DB-07; migration 20261020900000).

D1: ``households.household_type`` ('family' | 'roommates') is exposed on the members list, an admin
switches it (PUT /households/{id}/type) and sets members' financial roles within it
(PUT /households/{id}/members/{user_id}/financial-role); role invites must fit the type; family
features (provider, Nafaqah classes) never apply to a roommates household.
D2: only the wife, the Nafaqah provider or a household admin classifies a chat/receipt expense.

Requests carry real HS256 JWTs (the ``test_fable_`` prefix keeps the conftest auth mock away);
membership is resolved from the in-memory FakeSupabaseClient.
"""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt

import nafaqah_service as ns
from main import app
from routes.nafaqah import nafaqah_http_error

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

FAMILY = "bbbb0000-0000-4000-8000-000000000001"
FLAT = "bbbb0000-0000-4000-8000-000000000002"
LEGACY_FLAT = "bbbb0000-0000-4000-8000-000000000003"
HUSBAND = "0000bbbb-0000-4000-8000-00000000000a"
WIFE = "0000bbbb-0000-4000-8000-00000000000b"
SON = "0000bbbb-0000-4000-8000-00000000000c"
COADMIN = "0000bbbb-0000-4000-8000-00000000000d"
MATE1 = "0000bbbb-0000-4000-8000-0000000000f1"
MATE2 = "0000bbbb-0000-4000-8000-0000000000f2"
OUTSIDER = "0000bbbb-0000-4000-8000-0000000000e1"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def _m(user_id, household_id, role, financial_role, day):
    return {"user_id": user_id, "household_id": household_id, "role": role, "financial_role": financial_role,
            "created_at": f"2026-01-0{day}T00:00:00+00:00"}


class FakeApiError(Exception):
    def __init__(self, message: str, code: str, hint: str = ""):
        super().__init__(message)
        self.message, self.code, self.hint = message, code, hint


@pytest.fixture()
def world(fake_supabase):
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": FAMILY, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": FAMILY, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
        {"id": SON, "household_id": FAMILY, "role": "member", "financial_role": "family_member", "display_name": "Fahad"},
        {"id": COADMIN, "household_id": FAMILY, "role": "admin", "financial_role": "family_member", "display_name": "Nora"},
        {"id": MATE1, "household_id": FLAT, "role": "admin", "financial_role": "peer", "display_name": "Ali"},
        {"id": MATE2, "household_id": FLAT, "role": "member", "financial_role": "peer", "display_name": "Saad"},
        {"id": OUTSIDER, "household_id": None, "role": "member", "financial_role": "provider", "display_name": "Omar"},
    ])
    fake_supabase.seed("household_memberships", [
        _m(HUSBAND, FAMILY, "admin", "provider", 1),
        _m(WIFE, FAMILY, "member", "spouse", 2),
        _m(SON, FAMILY, "member", "family_member", 3),
        _m(COADMIN, FAMILY, "admin", "family_member", 4),
        _m(MATE1, FLAT, "admin", "peer", 1),
        _m(MATE2, FLAT, "member", "peer", 2),
        _m(MATE1, LEGACY_FLAT, "admin", "peer", 1),
    ])
    fake_supabase.seed("households", [
        {"id": FAMILY, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND,
         "household_type": "family"},
        {"id": FLAT, "payday_day": 27, "owner_user_id": MATE1, "nafaqah_provider_user_id": None,
         "household_type": "roommates"},
        # A row read before the column exists: the migration's backfill rule (any peer -> roommates).
        {"id": LEGACY_FLAT, "payday_day": 27, "owner_user_id": MATE1, "nafaqah_provider_user_id": None},
    ])

    def set_type(params):
        for h in fake_supabase.tables["households"]:
            if h["id"] == params["p_household_id"]:
                previous = h.get("household_type")
                h["household_type"] = params["p_household_type"]
                return {"success": True, "household_id": h["id"], "household_type": params["p_household_type"],
                        "previous_household_type": previous, "changed": previous != params["p_household_type"]}
        raise AssertionError("unknown household")

    def set_role(params):
        for m in fake_supabase.tables["household_memberships"]:
            if m["household_id"] == params["p_household_id"] and m["user_id"] == params["p_user_id"]:
                previous = m["financial_role"]
                m["financial_role"] = params["p_financial_role"]
                return {"success": True, "household_id": m["household_id"], "user_id": m["user_id"],
                        "financial_role": params["p_financial_role"], "previous_financial_role": previous}
        raise FakeApiError("Target user is not a member of this household", "P0002")

    fake_supabase.rpc_handlers["set_household_type"] = set_type
    fake_supabase.rpc_handlers["set_member_financial_role"] = set_role
    return fake_supabase


# ─── D1: the type on the members list and in the family context ──────────────

def test_members_list_exposes_the_household_type(world):
    family = client.get(f"/households/{FAMILY}/members", headers=bearer(SON)).json()
    assert family["household_type"] == "family"
    assert family["can_change_household_type"] is False and family["can_set_financial_roles"] is False
    flat = client.get(f"/households/{FLAT}/members", headers=bearer(MATE1)).json()
    assert flat["household_type"] == "roommates" and flat["can_change_household_type"] is True
    assert flat["assignable_financial_roles"] == ["peer"]
    assert flat["can_set_nafaqah_provider"] is False  # no provider in a roommates household
    legacy = client.get(f"/households/{LEGACY_FLAT}/members", headers=bearer(MATE1)).json()
    assert legacy["household_type"] == "roommates"


def test_family_context_reads_the_type(world):
    family = ns.load_family_context(FAMILY)
    assert family.household_type == "family" and family.is_family and family.settlement_mode == "family_nafaqah"
    flat = ns.load_family_context(FLAT)
    assert flat.household_type == "roommates" and flat.is_roommates and not flat.is_family
    assert flat.settlement_mode == "multi_roommate"
    assert ns.load_family_context(LEGACY_FLAT).household_type == "roommates"


def test_roommates_household_is_never_a_family_even_with_a_spouse_row(world):
    # An inconsistent row (the database forbids it) must not turn the flat into a family.
    world.tables["household_memberships"].append(_m(OUTSIDER, FLAT, "member", "spouse", 5))
    ctx = ns.load_family_context(FLAT)
    assert not ctx.is_family and ctx.wives == [] and ctx.husband_id is None
    assert ns.resolve_expense_nafaqah(FLAT, MATE1, "partner", "both")["household_mode"] == "not_family"


def test_family_without_a_wife_is_not_a_nafaqah_family(world):
    world.tables["household_memberships"] = [
        m for m in world.tables["household_memberships"] if not (m["household_id"] == FAMILY and m["user_id"] == WIFE)
    ]
    ctx = ns.load_family_context(FAMILY)
    assert ctx.household_type == "family" and not ctx.is_family and ctx.settlement_mode == "family_nafaqah"


def test_nafaqah_summary_carries_the_type(world):
    body = client.get(f"/households/{FLAT}/nafaqah", headers=bearer(MATE2)).json()
    assert body["household_type"] == "roommates" and body["mode"] == "not_family"
    assert body["can_set_provider"] is False


def test_provider_cannot_be_set_in_a_roommates_household(world):
    res = client.put(f"/households/{FLAT}/nafaqah/provider", headers=bearer(MATE1), json={"user_id": MATE2})
    assert res.status_code == 409 and res.json()["detail"]["code"] == "not_family"
    assert not any(name == "set_nafaqah_provider" for name, _ in world.rpc_calls)


# ─── D1: PUT /households/{id}/type ──────────────────────────────────────────

def test_admin_switches_the_type(world):
    res = client.put(f"/households/{FLAT}/type", headers=bearer(MATE1), json={"household_type": "family"})
    assert res.status_code == 200, res.text
    assert res.json() == {"status": "success", "household_id": FLAT, "household_type": "family"}
    assert world.rpc_calls[-1] == (
        "set_household_type", {"p_household_id": FLAT, "p_household_type": "family", "p_actor_user_id": MATE1}
    )


@pytest.mark.parametrize("actor", [MATE2, OUTSIDER])
def test_type_change_needs_an_admin_of_the_household(world, actor):
    res = client.put(f"/households/{FLAT}/type", headers=bearer(actor), json={"household_type": "family"})
    assert res.status_code == 403
    assert not any(name == "set_household_type" for name, _ in world.rpc_calls)


def test_type_value_is_validated(world):
    res = client.put(f"/households/{FLAT}/type", headers=bearer(MATE1), json={"household_type": "hostel"})
    assert res.status_code == 422


def test_blocked_type_change_is_409_with_a_code(world):
    def refuse(_params):
        raise FakeApiError("A family household with a wife or Nafaqah records cannot become a roommates household",
                           "22023", "type_change_blocked")

    world.rpc_handlers["set_household_type"] = refuse
    res = client.put(f"/households/{FAMILY}/type", headers=bearer(HUSBAND), json={"household_type": "roommates"})
    assert res.status_code == 409
    detail = res.json()["detail"]
    assert detail["code"] == "type_change_blocked" and detail["message"]


# ─── FABLE2-DB-07: PUT /households/{id}/members/{user_id}/financial-role ──────

def test_admin_sets_a_financial_role(world):
    res = client.put(f"/households/{FAMILY}/members/{SON}/financial-role", headers=bearer(COADMIN),
                     json={"financial_role": "dependent"})
    assert res.status_code == 200, res.text
    assert res.json() == {"status": "success", "household_id": FAMILY, "user_id": SON, "financial_role": "dependent"}
    assert world.rpc_calls[-1] == ("set_member_financial_role", {
        "p_household_id": FAMILY, "p_user_id": SON, "p_financial_role": "dependent", "p_actor_user_id": COADMIN,
    })


@pytest.mark.parametrize("household,actor,target,role,status,code", [
    (FAMILY, SON, SON, "dependent", 403, None),                      # not an admin
    (FAMILY, OUTSIDER, SON, "dependent", 403, None),                 # not a member
    (FAMILY, HUSBAND, MATE1, "dependent", 404, None),                # target not in the household
    (FAMILY, HUSBAND, SON, "peer", 422, "financial_role_not_allowed"),
    (FAMILY, HUSBAND, SON, "provider", 422, "financial_role_not_allowed"),
    (FLAT, MATE1, MATE2, "spouse", 422, "financial_role_not_allowed"),
    (FAMILY, COADMIN, HUSBAND, "spouse", 409, "provider_is_spouse"),
    (FAMILY, HUSBAND, SON, "boss", 422, None),                       # not a financial role at all
])
def test_financial_role_change_is_refused(world, household, actor, target, role, status, code):
    calls = len(world.rpc_calls)
    res = client.put(f"/households/{household}/members/{target}/financial-role", headers=bearer(actor),
                     json={"financial_role": role})
    assert res.status_code == status, res.text
    if code:
        assert res.json()["detail"]["code"] == code
    assert len(world.rpc_calls) == calls


def test_roommates_peer_role_is_accepted(world):
    res = client.put(f"/households/{FLAT}/members/{MATE2}/financial-role", headers=bearer(MATE1),
                     json={"financial_role": "peer"})
    assert res.status_code == 200 and res.json()["financial_role"] == "peer"


def test_wife_with_a_ledger_keeps_her_role(world):
    def refuse(_params):
        raise FakeApiError("This wife has Nafaqah records", "22023", "spouse_has_ledger")

    world.rpc_handlers["set_member_financial_role"] = refuse
    res = client.put(f"/households/{FAMILY}/members/{WIFE}/financial-role", headers=bearer(HUSBAND),
                     json={"financial_role": "family_member"})
    assert res.status_code == 409 and res.json()["detail"]["code"] == "spouse_has_ledger"


# ─── D1: role invites must fit the type ─────────────────────────────────────

@pytest.mark.parametrize("household,actor,role,status", [
    (FLAT, MATE1, "spouse", 409),
    (FLAT, MATE1, "family_member", 409),
    (FAMILY, HUSBAND, "peer", 409),
    (FLAT, MATE1, "peer", 200),
    (FAMILY, HUSBAND, "spouse", 200),
])
def test_invite_role_must_fit_the_type(world, household, actor, role, status):
    res = client.post(f"/households/{household}/invites", headers=bearer(actor), json={"role": role})
    assert res.status_code == status, res.text
    if status == 409:
        assert res.json()["detail"]["code"] == "invite_role_mismatch"
        assert not world.tables.get("household_invites")


# ─── D2: who may classify a chat/receipt expense ────────────────────────────

def test_son_cannot_classify(world):
    with pytest.raises(ns.NafaqahClassificationForbidden):
        ns.resolve_expense_nafaqah(FAMILY, SON, "me", "both", override_class="wife_reimbursable",
                                   override_spouse_id=WIFE, require_spouse=True)
    # Not choosing a class is fine: the expense is ordinary.
    assert ns.resolve_expense_nafaqah(FAMILY, SON, "me", "both")["nafaqah_class"] is None
    assert ns.resolve_expense_nafaqah(FAMILY, SON, "me", "both", override_class="none")["nafaqah_class"] is None


def test_admin_who_is_not_a_spouse_classifies_explicitly(world):
    res = ns.resolve_expense_nafaqah(FAMILY, COADMIN, "me", "both", override_class="wife_personal",
                                     require_spouse=True)
    assert res["nafaqah_class"] == "wife_personal" and res["nafaqah_spouse_id"] == WIFE


def test_wife_and_provider_classify(world):
    wife = ns.resolve_expense_nafaqah(FAMILY, WIFE, "me", "both", require_spouse=True)
    assert wife["nafaqah_class"] == "wife_reimbursable" and wife["nafaqah_spouse_id"] == WIFE
    husband = ns.resolve_expense_nafaqah(FAMILY, HUSBAND, "partner", "partner", require_spouse=True)
    assert husband["nafaqah_class"] == "wife_personal"


def test_classification_refusal_maps_to_403_with_a_code():
    exc = ns.NafaqahClassificationForbidden("Only the wife, the Nafaqah provider or a household admin ...")
    http = nafaqah_http_error(exc)
    assert http.status_code == 403 and http.detail["code"] == "nafaqah_classification_forbidden"
    mapped = ns._map_db_error(FakeApiError("Only the wife ...", "42501", "nafaqah_class_not_allowed"))
    assert isinstance(mapped, ns.NafaqahClassificationForbidden)
    assert isinstance(ns._map_db_error(FakeApiError("x", "22023", "not_family_household")), ns.NotFamilyHousehold)
