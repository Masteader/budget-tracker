"""
Household permissions (owner decision on audit items DB-16 / DB-18), roommate and family mode.

- A member creates transactions and edits/deletes only their own; only an admin edits or deletes
  another member's. The creator is the verified JWT user.
- Admins promote/revoke co-admins; co-admins cannot demote the primary admin; only the primary
  admin transfers primary ownership.

Requests carry real HS256 JWTs (excluded from the conftest auth mock) and memberships come from
the in-memory FakeSupabaseClient, so authorization and IDOR checks are real. The role RPCs are
emulated here; supabase/tests/20_admin_permissions_and_co_admins.sql proves the real ones.
"""

from __future__ import annotations

import base64
import io
import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt

import household_permissions as hp
from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

ROOM = "aaaa0000-0000-4000-8000-000000000001"
FAMILY = "bbbb0000-0000-4000-8000-000000000002"
OTHER = "cccc0000-0000-4000-8000-000000000003"

PRIMARY = "00000000-0000-4000-8000-0000000000a1"
CO = "00000000-0000-4000-8000-0000000000a2"
MEM = "00000000-0000-4000-8000-0000000000a3"
HUSBAND = "00000000-0000-4000-8000-0000000000b1"
WIFE = "00000000-0000-4000-8000-0000000000b2"
UNCLE = "00000000-0000-4000-8000-0000000000b3"
OUTSIDER = "00000000-0000-4000-8000-0000000000c1"

TX_PRIMARY = "dddd0000-0000-4000-8000-000000000001"
TX_MEM = "dddd0000-0000-4000-8000-000000000002"
TX_HUSBAND = "dddd0000-0000-4000-8000-000000000003"
TX_WIFE = "dddd0000-0000-4000-8000-000000000004"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


class FakeDbError(Exception):
    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.message = message
        self.code = code


def _membership(fake, household_id, user_id):
    return next(
        m for m in fake.tables["household_memberships"]
        if m["household_id"] == household_id and m["user_id"] == user_id
    )


def _install_role_rpcs(fake):
    """Stand-ins for the SECURITY DEFINER role RPCs: apply the change to the fake tables."""

    def promote(params):
        _membership(fake, params["p_household_id"], params["p_user_id"])["role"] = "admin"
        return {"success": True}

    def revoke(params):
        _membership(fake, params["p_household_id"], params["p_user_id"])["role"] = "member"
        return {"success": True}

    def transfer(params):
        _membership(fake, params["p_household_id"], params["p_new_primary_user_id"])["role"] = "admin"
        for h in fake.tables["households"]:
            if h["id"] == params["p_household_id"]:
                h["owner_user_id"] = params["p_new_primary_user_id"]
        return {"success": True}

    fake.rpc_handlers["promote_member_to_admin"] = promote
    fake.rpc_handlers["revoke_admin"] = revoke
    fake.rpc_handlers["transfer_primary_admin"] = transfer


@pytest.fixture()
def homes(fake_supabase):
    fake_supabase.seed("users", [
        {"id": PRIMARY, "household_id": ROOM, "role": "admin", "financial_role": "peer", "display_name": "Ali"},
        {"id": CO, "household_id": ROOM, "role": "member", "financial_role": "peer", "display_name": "Saad"},
        {"id": MEM, "household_id": ROOM, "role": "member", "financial_role": "peer", "display_name": "Majed"},
        {"id": HUSBAND, "household_id": FAMILY, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": FAMILY, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
        {"id": UNCLE, "household_id": FAMILY, "role": "member", "financial_role": "provider", "display_name": "Khalid"},
        {"id": OUTSIDER, "household_id": OTHER, "role": "admin", "financial_role": "peer", "display_name": "Omar"},
    ])
    fake_supabase.seed("household_memberships", [
        {"household_id": ROOM, "user_id": PRIMARY, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"household_id": ROOM, "user_id": CO, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"household_id": ROOM, "user_id": MEM, "role": "member", "created_at": "2026-01-03T00:00:00+00:00"},
        # The uncle joined first, but the husband created the household (primary admin).
        {"household_id": FAMILY, "user_id": UNCLE, "role": "member", "created_at": "2025-12-01T00:00:00+00:00"},
        {"household_id": FAMILY, "user_id": HUSBAND, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"household_id": FAMILY, "user_id": WIFE, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"household_id": OTHER, "user_id": OUTSIDER, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": ROOM, "payday_day": 27, "owner_user_id": PRIMARY},
        {"id": FAMILY, "payday_day": 27, "owner_user_id": HUSBAND},
        {"id": OTHER, "payday_day": 27, "owner_user_id": OUTSIDER},
    ])
    fake_supabase.seed("transactions", [
        {"id": TX_PRIMARY, "household_id": ROOM, "user_id": PRIMARY, "amount": 120.0, "merchant": "Rent", "raw_sms": "", "items": []},
        {"id": TX_MEM, "household_id": ROOM, "user_id": MEM, "amount": 40.0, "merchant": "Panda", "raw_sms": "", "items": []},
        {"id": TX_HUSBAND, "household_id": FAMILY, "user_id": HUSBAND, "amount": 300.0, "merchant": "Danube", "raw_sms": "", "items": []},
        {"id": TX_WIFE, "household_id": FAMILY, "user_id": WIFE, "amount": 80.0, "merchant": "Nahdi", "raw_sms": "", "items": []},
    ])
    _install_role_rpcs(fake_supabase)
    return fake_supabase


def _png_b64() -> str:
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def _tx(fake, tx_id):
    return next(t for t in fake.tables["transactions"] if t["id"] == tx_id)


def _promote(household_id, actor, target):
    return client.post(f"/households/{household_id}/members/{target}/admin", headers=bearer(actor))


# ─── Pure rules ───────────────────────────────────────────────────────────────

@pytest.mark.parametrize("actor,role,creator,allowed", [
    (MEM, "member", MEM, True),          # own transaction
    (MEM, "member", PRIMARY, False),     # someone else's
    (MEM, "member", None, False),        # unattributed legacy row: admins only
    (PRIMARY, "admin", MEM, True),       # admin: any transaction of the household
    (CO, "admin", PRIMARY, True),        # co-admin too
    (MEM, None, MEM, False),             # not a member of the household
    (None, "admin", MEM, False),
])
def test_can_modify_transaction(actor, role, creator, allowed):
    assert hp.can_modify_transaction(actor, role, creator) is allowed


@pytest.mark.parametrize("actor,role,payer,recipient,allowed", [
    (MEM, "member", MEM, PRIMARY, True),
    (MEM, "member", PRIMARY, MEM, True),
    (MEM, "member", PRIMARY, CO, False),
    (PRIMARY, "admin", CO, MEM, True),
    (MEM, None, MEM, CO, False),
])
def test_can_record_settlement(actor, role, payer, recipient, allowed):
    assert hp.can_record_settlement(actor, role, payer, recipient) is allowed


# ─── Members listing ──────────────────────────────────────────────────────────

def test_members_list_shows_roles_and_primary_first(homes):
    resp = client.get(f"/households/{ROOM}/members", headers=bearer(MEM))
    assert resp.status_code == 200
    body = resp.json()
    assert body["primary_admin_user_id"] == PRIMARY
    assert body["caller_role"] == "member"
    assert body["can_manage_admins"] is False and body["can_transfer_primary"] is False
    assert [m["user_id"] for m in body["members"]] == [PRIMARY, CO, MEM]
    assert body["members"][0]["is_primary"] is True and body["members"][0]["role"] == "admin"
    assert next(m for m in body["members"] if m["user_id"] == MEM)["is_self"] is True


def test_members_list_requires_membership_and_auth(homes):
    assert client.get(f"/households/{ROOM}/members").status_code == 401
    assert client.get(f"/households/{ROOM}/members", headers=bearer(OUTSIDER)).status_code == 403


def test_primary_admin_falls_back_to_longest_standing_admin(homes):
    for h in homes.tables["households"]:
        if h["id"] == ROOM:
            h.pop("owner_user_id")
    assert hp.load_roster(ROOM).primary_admin_id == PRIMARY


# ─── Promote / revoke co-admins ───────────────────────────────────────────────

def test_member_cannot_promote(homes):
    resp = _promote(ROOM, MEM, MEM)
    assert resp.status_code == 403
    assert homes.rpc_calls == []


def test_admin_from_another_household_cannot_promote(homes):
    resp = _promote(ROOM, OUTSIDER, MEM)
    assert resp.status_code == 403
    assert homes.rpc_calls == []


def test_primary_promotes_co_admin_and_co_admin_manages_members(homes):
    resp = _promote(ROOM, PRIMARY, CO)
    assert resp.status_code == 200
    assert homes.rpc_calls[-1] == ("promote_member_to_admin", {
        "p_household_id": ROOM, "p_user_id": CO, "p_actor_user_id": PRIMARY,
    })
    assert next(m for m in resp.json()["members"] if m["user_id"] == CO)["role"] == "admin"

    # The co-admin can do what admins do: promote and revoke other members...
    assert _promote(ROOM, CO, MEM).status_code == 200
    resp = client.delete(f"/households/{ROOM}/members/{MEM}/admin", headers=bearer(CO))
    assert resp.status_code == 200
    assert _membership(homes, ROOM, MEM)["role"] == "member"
    assert homes.rpc_calls[-1][1]["p_actor_user_id"] == CO


def test_co_admin_cannot_demote_primary_or_transfer_primary(homes):
    _membership(homes, ROOM, CO)["role"] = "admin"
    calls_before = len(homes.rpc_calls)

    resp = client.delete(f"/households/{ROOM}/members/{PRIMARY}/admin", headers=bearer(CO))
    assert resp.status_code == 403
    resp = client.post(f"/households/{ROOM}/primary-admin", headers=bearer(CO), json={"new_primary_user_id": CO})
    assert resp.status_code == 403

    assert len(homes.rpc_calls) == calls_before
    assert _membership(homes, ROOM, PRIMARY)["role"] == "admin"


def test_primary_cannot_demote_self_but_co_admin_can_step_down(homes):
    _membership(homes, ROOM, CO)["role"] = "admin"
    assert client.delete(f"/households/{ROOM}/members/{PRIMARY}/admin", headers=bearer(PRIMARY)).status_code == 403
    resp = client.delete(f"/households/{ROOM}/members/{CO}/admin", headers=bearer(CO))
    assert resp.status_code == 200
    assert resp.json()["caller_role"] == "member"


def test_promote_non_member_is_404_and_bad_ids_rejected(homes):
    assert _promote(ROOM, PRIMARY, OUTSIDER).status_code == 404
    assert client.post(f"/households/{ROOM}/members/not-a-uuid/admin", headers=bearer(PRIMARY)).status_code in (400, 422)


def test_database_refusals_are_mapped(homes):
    def forbidden(_params):
        raise FakeDbError("Forbidden: household admin privileges required", "42501")

    def sole_admin(_params):
        raise FakeDbError("Cannot demote the sole admin of a household", "P0001")

    homes.rpc_handlers["promote_member_to_admin"] = forbidden
    assert _promote(ROOM, PRIMARY, MEM).status_code == 403

    _membership(homes, ROOM, CO)["role"] = "admin"
    homes.rpc_handlers["revoke_admin"] = sole_admin
    assert client.delete(f"/households/{ROOM}/members/{CO}/admin", headers=bearer(PRIMARY)).status_code == 409


# ─── Transfer of primary admin ────────────────────────────────────────────────

def test_primary_transfers_ownership_and_new_primary_is_protected(homes):
    resp = client.post(f"/households/{ROOM}/primary-admin", headers=bearer(PRIMARY), json={"new_primary_user_id": MEM})
    assert resp.status_code == 200
    body = resp.json()
    assert body["primary_admin_user_id"] == MEM
    assert _membership(homes, ROOM, MEM)["role"] == "admin"
    assert _membership(homes, ROOM, PRIMARY)["role"] == "admin"  # previous primary stays a co-admin

    # The former primary is now a co-admin: they cannot demote the new primary.
    assert client.delete(f"/households/{ROOM}/members/{MEM}/admin", headers=bearer(PRIMARY)).status_code == 403
    assert client.delete(f"/households/{ROOM}/members/{PRIMARY}/admin", headers=bearer(MEM)).status_code == 200


def test_transfer_primary_rejects_self_outsider_and_bad_body(homes):
    url = f"/households/{ROOM}/primary-admin"
    assert client.post(url, headers=bearer(PRIMARY), json={"new_primary_user_id": PRIMARY}).status_code == 409
    assert client.post(url, headers=bearer(PRIMARY), json={"new_primary_user_id": OUTSIDER}).status_code == 404
    assert client.post(url, headers=bearer(PRIMARY), json={"new_primary_user_id": "nope"}).status_code == 422
    assert client.post(url, headers=bearer(MEM), json={"new_primary_user_id": MEM}).status_code == 403


# ─── Transactions: creator binding and owner-or-admin edits (DB-18) ───────────

def _patch_chat_parser(monkeypatch, merchant="Dunkin"):
    from chat_parser import ChatLineItem, ParsedChatExpense

    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda _msg: ParsedChatExpense(
        merchant=merchant, total_amount=19.0, category_code="OPEX-DINING",
        items=[ChatLineItem(name="Latte", quantity=1, price=19.0)],
    ))


def _enrich(actor, household_id, tx_id):
    return client.post("/agent/chat-transaction", headers=bearer(actor), json={
        "message": "latte 19", "household_id": household_id, "enrich_tx_id": tx_id,
    })


def test_member_cannot_enrich_another_members_transaction(homes, monkeypatch):
    _patch_chat_parser(monkeypatch)
    resp = _enrich(MEM, ROOM, TX_PRIMARY)
    assert resp.status_code == 403
    assert _tx(homes, TX_PRIMARY)["items"] == []


def test_member_enriches_own_and_admin_enriches_members_transaction(homes, monkeypatch):
    _patch_chat_parser(monkeypatch)
    resp = _enrich(MEM, ROOM, TX_MEM)
    assert resp.status_code == 200 and resp.json()["status"] == "enriched"
    assert _tx(homes, TX_MEM)["items"][0]["name"] == "Latte"

    _tx(homes, TX_MEM)["items"] = []
    resp = _enrich(PRIMARY, ROOM, TX_MEM)
    assert resp.status_code == 200 and resp.json()["status"] == "enriched"
    assert _tx(homes, TX_MEM)["items"][0]["name"] == "Latte"


def test_receipt_enrichment_follows_the_same_rule(homes, monkeypatch):
    from receipt_scanner import process_receipt_scan

    monkeypatch.setattr("receipt_scanner.parse_receipt_image", lambda *_a, **_k: {
        "merchant": "Danube", "total_amount": 300.0, "items": [{"name": "Rice", "quantity": 1, "price": 300.0}],
    })
    image = [_png_b64()]
    with pytest.raises(hp.PermissionDeniedError):
        process_receipt_scan(household_id=FAMILY, images_base64=image, user_id=WIFE, enrich_tx_id=TX_HUSBAND,
                             preview_only=True)
    assert _tx(homes, TX_HUSBAND)["items"] == []

    res = process_receipt_scan(household_id=FAMILY, images_base64=image, user_id=HUSBAND, enrich_tx_id=TX_WIFE,
                               preview_only=True)
    assert res["status"] == "enriched"
    assert _tx(homes, TX_WIFE)["items"][0]["name"] == "Rice"


def test_new_transactions_are_attributed_to_the_caller(homes, monkeypatch):
    from chat_parser import process_chat_transaction

    _patch_chat_parser(monkeypatch, merchant="Kudu")
    res = process_chat_transaction(household_id=ROOM, message="kudu 19", user_id=MEM, allow_duplicate=True)
    assert res["status"] == "success"
    assert _tx(homes, res["transaction_id"])["user_id"] == MEM


def test_installment_linking_is_an_edit(homes):
    payload = {
        "household_id": ROOM, "merchant": "eXtra", "provider": "Tamara", "total_amount": 120.0,
        "installment_count": 4, "adjust_original_transaction": True,
    }
    resp = client.post("/budgets/installments", headers=bearer(MEM), json={**payload, "original_transaction_id": TX_PRIMARY})
    assert resp.status_code == 403
    assert _tx(homes, TX_PRIMARY)["amount"] == 120.0

    resp = client.post("/budgets/installments", headers=bearer(MEM), json={**payload, "original_transaction_id": TX_MEM, "total_amount": 40.0})
    assert resp.status_code == 200
    assert _tx(homes, TX_MEM)["amount"] == 10.0

    _membership(homes, ROOM, CO)["role"] = "admin"
    homes.seed("transactions", [{"id": "dddd0000-0000-4000-8000-000000000009", "household_id": ROOM, "user_id": MEM,
                                 "amount": 80.0, "raw_sms": "", "items": []}])
    resp = client.post("/budgets/installments", headers=bearer(CO), json={
        **payload, "total_amount": 80.0, "original_transaction_id": "dddd0000-0000-4000-8000-000000000009"})
    assert resp.status_code == 200


def test_roommate_settlement_attribution(homes):
    url = f"/households/{ROOM}/reimbursements"
    body = {"household_id": ROOM, "amount": 50.0, "payment_method": "stc_pay"}

    resp = client.post(url, headers=bearer(MEM), json={**body, "payer_id": PRIMARY, "recipient_id": CO})
    assert resp.status_code == 403

    resp = client.post(url, headers=bearer(MEM), json={**body, "payer_id": MEM, "recipient_id": PRIMARY})
    assert resp.status_code == 200
    assert _tx(homes, resp.json()["transaction_id"])["user_id"] == MEM

    resp = client.post(url, headers=bearer(PRIMARY), json={**body, "payer_id": CO, "recipient_id": MEM})
    assert resp.status_code == 200
    assert _tx(homes, resp.json()["transaction_id"])["user_id"] == PRIMARY


# ─── Family mode: same admin concept, Nafaqah keeps working ───────────────────

def test_family_husband_is_primary_admin_and_co_admin_sets_allowance(homes):
    import nafaqah_service as ns

    ctx = ns.load_family_context(FAMILY)
    assert ctx.husband_id == HUSBAND  # the earlier-joined provider uncle is not the husband

    homes.rpc_handlers["set_member_allowance"] = lambda params: None
    url = f"/households/{FAMILY}/nafaqah/allowance"
    body = {"wife_user_id": WIFE, "amount": 500, "cycle_key": "2026-11"}
    assert client.put(url, headers=bearer(UNCLE), json=body).status_code == 403

    assert _promote(FAMILY, HUSBAND, UNCLE).status_code == 200
    assert client.put(url, headers=bearer(UNCLE), json=body).status_code == 200
    assert ns.load_family_context(FAMILY).husband_id == HUSBAND

    # A wife made co-admin still never sets her own allowance, nor demotes the husband.
    assert _promote(FAMILY, HUSBAND, WIFE).status_code == 200
    assert client.put(url, headers=bearer(WIFE), json={**body, "amount": 9000}).status_code == 403
    assert client.delete(f"/households/{FAMILY}/members/{HUSBAND}/admin", headers=bearer(WIFE)).status_code == 403


def test_family_member_edits_follow_admin_rule(homes, monkeypatch):
    _patch_chat_parser(monkeypatch)
    assert _enrich(WIFE, FAMILY, TX_HUSBAND).status_code == 403
    assert _enrich(WIFE, FAMILY, TX_WIFE).status_code == 200
    assert _enrich(HUSBAND, FAMILY, TX_WIFE).status_code == 200
