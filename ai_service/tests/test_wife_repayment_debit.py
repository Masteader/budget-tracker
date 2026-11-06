"""
Every repayment to the wife is tracked; she asks, he approves; corrections are reversals
(owner decisions 2026-11-06, migration 20261105001300).

  * A repayment (or a payment of a former member's record) always names the account it leaves.
    Without one the caller is an app that predates this: HTTP 426, code app_update_required, and
    nothing is recorded. It credits the wife account the payer names (test_wife_account); her own
    accounts are never credited.
  * The wife does not record a repayment (403, wife_must_request). She creates a request; the
    husband or an admin approves it from an account or declines it; she can cancel it.
  * A tracked repayment or payment is reversed in full; the ledger shows which were reversed and
    who may reverse what. What is owed is net of reversals; pending requests do not count.

The database suite (tests 56, 57 and 58) proves the RPCs; here they are stand-ins that record their
parameters, and the HTTP layer runs with real JWTs and membership checks.
"""

from __future__ import annotations

import pathlib
import re
import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt
from postgrest.exceptions import APIError

import nafaqah_service as ns
from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"
MIGRATION = (pathlib.Path(__file__).resolve().parents[2] / "supabase" / "migrations"
             / "20261105001300_wife_repayment_debit.sql")

HH = "b1000000-0000-4000-8000-000000000001"
HH_ROOM = "b1000000-0000-4000-8000-000000000003"
HUSBAND = "b2000000-0000-4000-8000-00000000000a"
WIFE = "b2000000-0000-4000-8000-00000000000b"
CHILD = "b2000000-0000-4000-8000-00000000000c"
COADMIN = "b2000000-0000-4000-8000-00000000000d"
PEER1 = "b2000000-0000-4000-8000-0000000000f1"
PEER2 = "b2000000-0000-4000-8000-0000000000f2"
ACCOUNT = "b5000000-0000-4000-8000-000000000001"
POOL = "b5000000-0000-4000-8000-000000000002"
HER_ACCOUNT = "b5000000-0000-4000-8000-000000000003"
WIFE_WA = "b5000000-0000-4000-8000-000000000004"
T_NEW = "b6000000-0000-4000-8000-000000000001"
T_POOL = "b6000000-0000-4000-8000-000000000002"
T_BACK = "b6000000-0000-4000-8000-000000000003"
T_FMD = "b6000000-0000-4000-8000-000000000004"
T_WAIVED = "b6000000-0000-4000-8000-000000000005"
DEBT = "b3000000-0000-4000-8000-000000000001"
DEBT_WAIVED = "b3000000-0000-4000-8000-000000000002"
KEY = "b4000000-0000-4000-8000-000000000001"
Q_PENDING = "b7000000-0000-4000-8000-000000000001"
Q_DECLINED = "b7000000-0000-4000-8000-000000000002"
Q_APPROVED = "b7000000-0000-4000-8000-000000000003"
E_LEGACY = "b8000000-0000-4000-8000-000000000001"
E_TRACKED = "b8000000-0000-4000-8000-000000000002"
E_WAIVED = "b8000000-0000-4000-8000-000000000003"
R_NEW = "b9000000-0000-4000-8000-000000000001"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def db_error(hint: str, code: str = "22023", message: str = "refused", details: str = "") -> APIError:
    return APIError({"code": code, "hint": hint, "details": details, "message": message})


@pytest.fixture()
def family(fake_supabase):
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": HH, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
        {"id": CHILD, "household_id": HH, "role": "member", "financial_role": "family_member", "display_name": "Fahad"},
        {"id": COADMIN, "household_id": HH, "role": "admin", "financial_role": "family_member", "display_name": "Nora"},
        {"id": PEER1, "household_id": HH_ROOM, "role": "admin", "financial_role": "peer", "display_name": "Ali"},
        {"id": PEER2, "household_id": HH_ROOM, "role": "member", "financial_role": "peer", "display_name": "Saad"},
    ])
    fake_supabase.seed("household_memberships", [
        {"user_id": HUSBAND, "financial_role": "provider", "household_id": HH, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": WIFE, "financial_role": "spouse", "household_id": HH, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"user_id": CHILD, "financial_role": "family_member", "household_id": HH, "role": "member", "created_at": "2026-01-03T00:00:00+00:00"},
        {"user_id": COADMIN, "financial_role": "family_member", "household_id": HH, "role": "admin", "created_at": "2026-01-04T00:00:00+00:00"},
        {"user_id": PEER1, "financial_role": "peer", "household_id": HH_ROOM, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": PEER2, "financial_role": "peer", "household_id": HH_ROOM, "role": "member", "created_at": "2026-01-01T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": HH, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND, "household_type": "family"},
        {"id": HH_ROOM, "payday_day": 27, "owner_user_id": PEER1, "household_type": "roommates"},
    ])
    fake_supabase.seed("accounts", [
        {"id": ACCOUNT, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": False, "is_archived": False, "currency": "SAR"},
        {"id": POOL, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "currency": "SAR"},
        {"id": HER_ACCOUNT, "household_id": HH, "owner_user_id": WIFE, "is_shared_pool": False, "is_archived": False, "currency": "SAR"},
        # Her wife account (section 12 of 20261105001300): every repayment credits it.
        {"id": WIFE_WA, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": False, "is_archived": False,
         "currency": "SAR", "account_type": "wife", "assigned_wife_id": WIFE, "name": "Sara card", "balance": 0},
    ])
    fake_supabase.seed("transactions", [
        {"id": "t1", "household_id": HH, "amount": 300.0, "merchant": "Panda", "timestamp": "2026-11-10T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
    ])
    fake_supabase.seed("spouse_reimbursements", [
        # Before this release: amount only, never reversible.
        {"id": "r-old", "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 50.0,
         "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-11T10:00:00+00:00"},
        # From his account, approved from her request.
        {"id": R_NEW, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 25.0,
         "payment_method": "bank_transfer", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-12T10:00:00+00:00",
         "transfer_id": T_NEW, "request_key": KEY, "kind": "payment", "reverses_id": None},
        # From the pool, then reversed.
        {"id": "r-pool", "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 40.0,
         "payment_method": "cash", "notes": None, "recorded_by": COADMIN, "created_at": "2026-11-13T10:00:00+00:00",
         "transfer_id": T_POOL, "kind": "payment", "reverses_id": None},
        {"id": "r-back", "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 40.0,
         "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-14T10:00:00+00:00",
         "transfer_id": T_BACK, "kind": "reversal", "reverses_id": "r-pool"},
    ])
    fake_supabase.seed("account_transfers", [
        {"id": T_NEW, "household_id": HH, "from_account_id": ACCOUNT, "to_account_id": None, "amount": 25.0},
        {"id": T_POOL, "household_id": HH, "from_account_id": POOL, "to_account_id": None, "amount": 40.0},
        {"id": T_BACK, "household_id": HH, "from_account_id": None, "to_account_id": POOL, "amount": 40.0},
        {"id": T_FMD, "household_id": HH, "from_account_id": ACCOUNT, "to_account_id": None, "amount": 30.0},
        {"id": T_WAIVED, "household_id": HH, "from_account_id": ACCOUNT, "to_account_id": None, "amount": 5.0},
    ])
    fake_supabase.seed("spouse_reimbursement_requests", [
        {"id": Q_PENDING, "household_id": HH, "wife_user_id": WIFE, "amount": 30.0, "payment_method": "cash",
         "created_at": "2026-11-15T10:00:00+00:00"},
        {"id": Q_DECLINED, "household_id": HH, "wife_user_id": WIFE, "amount": 10.0, "payment_method": "cash",
         "created_at": "2026-11-14T09:00:00+00:00"},
        {"id": Q_APPROVED, "household_id": HH, "wife_user_id": WIFE, "amount": 25.0, "payment_method": "bank_transfer",
         "created_at": "2026-11-12T09:00:00+00:00"},
    ])
    fake_supabase.seed("spouse_reimbursement_request_outcomes", [
        {"request_id": Q_DECLINED, "outcome": "declined", "reason": "Not received yet", "reimbursement_id": None,
         "decided_by": HUSBAND, "created_at": "2026-11-14T12:00:00+00:00"},
        {"request_id": Q_APPROVED, "outcome": "approved", "reason": None, "reimbursement_id": R_NEW,
         "decided_by": HUSBAND, "created_at": "2026-11-12T10:00:00+00:00"},
    ])
    fake_supabase.seed("former_member_debts", [
        {"id": DEBT, "household_id": HH, "original_amount": 170.0, "paid_amount": 70.0, "status": "open",
         "created_at": "2026-11-05T10:00:00+00:00", "closed_at": None},
        {"id": DEBT_WAIVED, "household_id": HH, "original_amount": 20.0, "paid_amount": 5.0, "status": "waived",
         "created_at": "2026-11-04T10:00:00+00:00", "closed_at": "2026-11-04T12:00:00+00:00"},
    ])
    fake_supabase.seed("former_member_debt_events", [
        {"id": E_LEGACY, "debt_id": DEBT, "kind": "payment", "amount": 40.0, "payment_method": "cash",
         "remaining_after": 130.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-06T10:00:00+00:00"},
        {"id": E_TRACKED, "debt_id": DEBT, "kind": "payment", "amount": 30.0, "payment_method": "bank_transfer",
         "remaining_after": 100.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-07T10:00:00+00:00",
         "transfer_id": T_FMD},
        {"id": E_WAIVED, "debt_id": DEBT_WAIVED, "kind": "payment", "amount": 5.0, "payment_method": "cash",
         "remaining_after": 15.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-04T11:00:00+00:00",
         "transfer_id": T_WAIVED},
        {"id": "e-w", "debt_id": DEBT_WAIVED, "kind": "waiver", "amount": 15.0, "payment_method": None,
         "remaining_after": 0.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-04T12:00:00+00:00"},
    ])

    def repay(params):
        return {"success": True, "replayed": False, "reimbursement_id": "r-x", "amount": float(params["p_amount"]),
                "payment_method": params["p_payment_method"], "account_id": params.get("p_account_id"),
                "outstanding_before": 225.0, "outstanding_after": 225.0 - float(params["p_amount"])}

    def pay(params):
        return {"success": True, "replayed": False, "event_id": "e-new", "debt_id": params["p_debt_id"],
                "amount": float(params["p_amount"]), "payment_method": params["p_payment_method"],
                "remaining": 100.0 - float(params["p_amount"]), "status": "open",
                "account_id": params.get("p_account_id")}

    fake_supabase.rpc_handlers["record_spouse_reimbursement"] = repay
    fake_supabase.rpc_handlers["record_former_member_debt_payment"] = pay
    fake_supabase.rpc_handlers["request_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": False, "request_id": "q-new", "status": "pending", "amount": float(p["p_amount"]),
        "payment_method": p["p_payment_method"], "outstanding": 225.0}
    fake_supabase.rpc_handlers["cancel_spouse_reimbursement_request"] = lambda p: {
        "success": True, "replayed": False, "request_id": p["p_request_id"], "outcome": "cancelled"}
    fake_supabase.rpc_handlers["decline_spouse_reimbursement_request"] = lambda p: {
        "success": True, "replayed": False, "request_id": p["p_request_id"], "outcome": "declined", "reason": p["p_reason"]}
    fake_supabase.rpc_handlers["approve_spouse_reimbursement_request"] = lambda p: {
        "success": True, "replayed": False, "reimbursement_id": "r-appr", "request_id": p["p_request_id"], "amount": 30.0,
        "payment_method": "cash", "account_id": p["p_account_id"], "outstanding_before": 225.0, "outstanding_after": 195.0}
    fake_supabase.rpc_handlers["reverse_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": False, "reimbursement_id": "r-rev", "kind": "reversal",
        "reverses_id": p["p_reimbursement_id"], "amount": 25.0, "payment_method": "bank_transfer", "account_id": ACCOUNT,
        "outstanding_before": 225.0, "outstanding_after": 250.0}
    fake_supabase.rpc_handlers["reverse_former_member_debt_payment"] = lambda p: {
        "success": True, "replayed": False, "event_id": "e-rev", "debt_id": p["p_debt_id"],
        "reverses_event_id": p["p_event_id"], "amount": 30.0, "remaining": 130.0, "status": "open", "account_id": ACCOUNT}
    fake_supabase.rpc_handlers["get_former_member_debt_deletion_notices"] = lambda _p: []
    return fake_supabase


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


def husband_leaves(fake):
    """He left the household: his membership ends and the provider is cleared. An admin who is not a
    wife then sees and settles her ledger (review R3-01)."""
    fake.tables["household_memberships"][:] = [m for m in fake.tables["household_memberships"] if m["user_id"] != HUSBAND]
    for h in fake.tables["households"]:
        if h["id"] == HH:
            h["nafaqah_provider_user_id"] = None
            h["owner_user_id"] = COADMIN


def _repay(user, **body):
    payload = {"amount": 20, "payment_method": "bank_transfer", "wife_account_id": WIFE_WA, **body}
    return client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(user), json=payload)


def _pay(user, **body):
    payload = {"amount": 30, "payment_method": "bank_transfer", "request_key": KEY, **body}
    return client.post(f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/payments", headers=bearer(user), json=payload)


def _q(path=""):
    return f"/households/{HH}/nafaqah/reimbursement-requests{path}"


# ─── Every repayment leaves an account ───────────────────────────────────────

def test_a_repayment_goes_to_the_rpc_with_the_account_and_the_key(family):
    resp = _repay(HUSBAND, amount=20.4, account_id=ACCOUNT, request_key=KEY)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "record_spouse_reimbursement") == [{
        "p_household_id": HH, "p_wife_user_id": WIFE, "p_amount": "20.40", "p_payment_method": "bank_transfer",
        "p_notes": None, "p_actor_user_id": HUSBAND, "p_account_id": ACCOUNT, "p_request_key": KEY, "p_wife_account_id": WIFE_WA}]
    body = resp.json()
    assert (body["account_id"], body["balance_moved"], body["replayed"], body["outstanding_after"]) == (ACCOUNT, True, False, 204.6)
    assert body["wife_account_id"] == WIFE_WA, "it credits the wife account he named, never one of her own"


@pytest.mark.parametrize("body", [{}, {"request_key": KEY}, {"payment_method": "cash"}])
def test_an_old_app_without_an_account_is_told_to_update(family, body):
    resp = _repay(HUSBAND, **body)
    assert resp.status_code == 426, resp.text
    assert resp.json()["detail"]["code"] == "app_update_required"
    assert _calls(family, "record_spouse_reimbursement") == [], "nothing is recorded without an account"


def test_the_old_wife_confirmation_is_told_to_update(family):
    """The released app let the wife confirm what she received: no account, so update the app."""
    resp = _repay(WIFE, amount=10, payment_method="cash")
    assert resp.status_code == 426 and resp.json()["detail"]["code"] == "app_update_required"


def test_the_legacy_route_without_an_account_is_told_to_update(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(HUSBAND), json={
        "household_id": HH, "payer_id": "husband", "recipient_id": "wife", "amount": 10, "payment_method": "cash"})
    assert resp.status_code == 426 and resp.json()["detail"]["code"] == "app_update_required"
    assert _calls(family, "record_spouse_reimbursement") == []


def test_the_legacy_route_passes_the_account_in_a_family(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(HUSBAND), json={
        "household_id": HH, "payer_id": "husband", "recipient_id": "wife", "amount": 10, "payment_method": "cash",
        "account_id": ACCOUNT, "request_key": KEY, "wife_account_id": WIFE_WA})
    assert resp.status_code == 200, resp.text
    params = _calls(family, "record_spouse_reimbursement")[0]
    assert (params["p_account_id"], params["p_request_key"]) == (ACCOUNT, KEY)
    assert resp.json()["balance_moved"] is True


def test_the_legacy_route_refuses_an_account_between_roommates(family):
    resp = client.post(f"/households/{HH_ROOM}/reimbursements", headers=bearer(PEER1), json={
        "household_id": HH_ROOM, "payer_id": PEER1, "recipient_id": PEER2, "amount": 10, "payment_method": "cash",
        "account_id": ACCOUNT, "request_key": KEY})
    assert resp.status_code == 422
    assert not [t for t in family.tables["transactions"] if t.get("is_settlement")]


def test_an_account_needs_a_request_key(family):
    resp = _repay(HUSBAND, account_id=ACCOUNT)
    assert resp.status_code == 422 and resp.json()["detail"]["code"] == "request_key_required"
    assert _calls(family, "record_spouse_reimbursement") == []


@pytest.mark.parametrize("body", [{"account_id": "not-a-uuid", "request_key": KEY}, {"account_id": ACCOUNT, "request_key": "nope"}])
def test_malformed_ids_are_refused(family, body):
    assert _repay(HUSBAND, **body).status_code == 422
    assert _calls(family, "record_spouse_reimbursement") == []


def test_the_wife_asks_instead_of_recording(family):
    resp = _repay(WIFE, account_id=HER_ACCOUNT, request_key=KEY)
    assert resp.status_code == 403
    assert resp.json()["detail"]["code"] == "wife_must_request"
    assert _calls(family, "record_spouse_reimbursement") == []


def test_a_member_cannot_record(family):
    assert _repay(CHILD, account_id=ACCOUNT, request_key=KEY).status_code == 403
    assert _calls(family, "record_spouse_reimbursement") == []


def test_a_replay_answers_with_what_the_first_tap_stored(family):
    family.rpc_handlers["record_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": True, "reimbursement_id": "r-full", "amount": 225.0, "payment_method": "cash",
        "account_id": ACCOUNT, "outstanding_before": 225.0, "outstanding_after": 0.0}
    resp = _repay(HUSBAND, amount=10, account_id=ACCOUNT, request_key=KEY)  # the retry typed another amount
    assert resp.status_code == 200, resp.text
    assert (resp.json()["replayed"], resp.json()["amount"], resp.json()["outstanding_after"]) == (True, 225.0, 0.0)


@pytest.mark.parametrize("hint, code, status_code, extra", [
    ("app_update_required", "0A000", 426, {}),
    ("wife_must_request", "42501", 403, {}),
    ("account_unavailable", "P0002", 422, {}),
    ("account_forbidden", "42501", 403, {}),
    ("insufficient_funds", "22000", 409, {}),
    ("request_key_reused", "22023", 409, {}),
    ("request_key_required", "22023", 422, {}),
    ("overpayment", "22023", 409, {"outstanding": 12.5}),
])
def test_database_refusals_of_a_repayment_map_to_codes(family, hint, code, status_code, extra):
    def refuse(_params):
        raise db_error(hint, code=code, details="12.50")

    family.rpc_handlers["record_spouse_reimbursement"] = refuse
    resp = _repay(HUSBAND, account_id=ACCOUNT, request_key=KEY)
    assert resp.status_code == status_code, resp.text
    if status_code != 422 or hint == "request_key_required":
        assert resp.json()["detail"]["code"] == hint
    for key, value in extra.items():
        assert resp.json()["detail"][key] == value
    assert "refused" not in resp.text, "the raw database text never reaches the client"


# ─── Her requests ─────────────────────────────────────────────────────────────

def test_she_asks_and_nothing_else_happens(family):
    resp = client.post(_q(), headers=bearer(WIFE), json={"amount": 30.5, "payment_method": "cash", "request_key": KEY,
                                                          "wife_account_id": WIFE_WA})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "request_spouse_reimbursement") == [{
        "p_household_id": HH, "p_amount": "30.50", "p_payment_method": "cash", "p_request_key": KEY, "p_actor_user_id": WIFE,
        "p_wife_account_id": WIFE_WA}]
    assert (resp.json()["request_status"], resp.json()["request_id"]) == ("pending", "q-new")
    assert _calls(family, "record_spouse_reimbursement") == []


@pytest.mark.parametrize("caller", [HUSBAND, CHILD, COADMIN])
def test_only_the_wife_asks(family, caller):
    resp = client.post(_q(), headers=bearer(caller), json={"amount": 5, "payment_method": "cash", "request_key": KEY})
    assert resp.status_code == 403
    assert _calls(family, "request_spouse_reimbursement") == []


@pytest.mark.parametrize("body", [{"amount": 0}, {"amount": 1.001}, {"request_key": "x"}, {"payment_method": "gold"}, {"account_id": ACCOUNT}])
def test_a_malformed_request_is_refused(family, body):
    payload = {"amount": 5, "payment_method": "cash", "request_key": KEY, **body}
    assert client.post(_q(), headers=bearer(WIFE), json=payload).status_code == 422
    assert _calls(family, "request_spouse_reimbursement") == []


def test_a_request_beyond_what_is_owed_says_what_is_left(family):
    def refuse(_p):
        raise db_error("pending_exceeds_outstanding", details="195.00")

    family.rpc_handlers["request_spouse_reimbursement"] = refuse
    resp = client.post(_q(), headers=bearer(WIFE), json={"amount": 200, "payment_method": "cash", "request_key": KEY,
                                                          "wife_account_id": WIFE_WA})
    assert resp.status_code == 409
    assert resp.json()["detail"]["code"] == "pending_exceeds_outstanding" and resp.json()["detail"]["available"] == 195.0


def test_she_cancels_her_own(family):
    resp = client.post(_q(f"/{Q_PENDING}/cancel"), headers=bearer(WIFE))
    assert resp.status_code == 200, resp.text
    assert _calls(family, "cancel_spouse_reimbursement_request") == [{
        "p_household_id": HH, "p_request_id": Q_PENDING, "p_actor_user_id": WIFE}]
    assert resp.json()["outcome"] == "cancelled"


@pytest.mark.parametrize("caller", [HUSBAND, COADMIN, CHILD])
def test_nobody_else_cancels_it(family, caller):
    assert client.post(_q(f"/{Q_PENDING}/cancel"), headers=bearer(caller)).status_code == 403
    assert _calls(family, "cancel_spouse_reimbursement_request") == []


def test_an_unknown_request_is_not_found(family):
    resp = client.post(_q("/b7000000-0000-4000-8000-0000000000ff/cancel"), headers=bearer(WIFE))
    assert resp.status_code == 404 and resp.json()["detail"]["code"] == "request_not_found"


@pytest.mark.parametrize("caller", [HUSBAND, COADMIN])
def test_the_husband_or_an_admin_approves_from_an_account(family, caller):
    """The husband; an admin who is not a wife once he is gone (review R3-01)."""
    if caller == COADMIN:
        husband_leaves(family)
    account = ACCOUNT if caller == HUSBAND else POOL
    resp = client.post(_q(f"/{Q_PENDING}/approve"), headers=bearer(caller), json={"account_id": account, "request_key": KEY})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "approve_spouse_reimbursement_request") == [{
        "p_household_id": HH, "p_request_id": Q_PENDING, "p_account_id": account, "p_request_key": KEY, "p_actor_user_id": caller,
        "p_wife_account_id": None}]
    body = resp.json()
    assert (body["request_id"], body["amount"], body["outstanding_after"], body["balance_moved"]) == (Q_PENDING, 30.0, 195.0, True)


@pytest.mark.parametrize("caller", [WIFE, CHILD])
def test_she_and_members_do_not_approve(family, caller):
    resp = client.post(_q(f"/{Q_PENDING}/approve"), headers=bearer(caller), json={"account_id": HER_ACCOUNT, "request_key": KEY})
    assert resp.status_code == 403
    assert _calls(family, "approve_spouse_reimbursement_request") == []


@pytest.mark.parametrize("body", [{"request_key": KEY}, {"account_id": ACCOUNT}, {"account_id": "x", "request_key": KEY}])
def test_an_approval_needs_an_account_and_a_key(family, body):
    assert client.post(_q(f"/{Q_PENDING}/approve"), headers=bearer(HUSBAND), json=body).status_code == 422
    assert _calls(family, "approve_spouse_reimbursement_request") == []


@pytest.mark.parametrize("hint, status_code, extra", [
    ("request_not_pending", 409, {}),
    ("request_exceeds_outstanding", 409, {"outstanding": 12.5}),
    ("insufficient_funds", 409, {}),
    ("account_forbidden", 403, {}),
    ("request_not_found", 404, {}),
])
def test_approval_refusals_map_to_codes(family, hint, status_code, extra):
    def refuse(_p):
        raise db_error(hint, details="12.50")

    family.rpc_handlers["approve_spouse_reimbursement_request"] = refuse
    resp = client.post(_q(f"/{Q_PENDING}/approve"), headers=bearer(HUSBAND), json={"account_id": ACCOUNT, "request_key": KEY})
    assert resp.status_code == status_code, resp.text
    assert resp.json()["detail"]["code"] == hint
    for key, value in extra.items():
        assert resp.json()["detail"][key] == value


def test_the_husband_declines_with_a_reason(family):
    resp = client.post(_q(f"/{Q_PENDING}/decline"), headers=bearer(HUSBAND), json={"reason": "  Not yet  "})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "decline_spouse_reimbursement_request") == [{
        "p_household_id": HH, "p_request_id": Q_PENDING, "p_reason": "Not yet", "p_actor_user_id": HUSBAND}]
    assert resp.json()["outcome"] == "declined"


def test_a_decline_without_a_reason(family):
    assert client.post(_q(f"/{Q_PENDING}/decline"), headers=bearer(HUSBAND), json={}).status_code == 200
    assert _calls(family, "decline_spouse_reimbursement_request")[0]["p_reason"] is None


@pytest.mark.parametrize("caller, body, status_code", [
    (WIFE, {}, 403), (CHILD, {}, 403), (COADMIN, {}, 403), (HUSBAND, {"reason": "x" * 201}, 422),
])
def test_decline_refusals(family, caller, body, status_code):
    assert client.post(_q(f"/{Q_PENDING}/decline"), headers=bearer(caller), json=body).status_code == status_code
    assert _calls(family, "decline_spouse_reimbursement_request") == []


# ─── Reversals ───────────────────────────────────────────────────────────────

def test_the_husband_reverses_a_tracked_repayment(family):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_NEW}/reversal", headers=bearer(HUSBAND), json={"request_key": KEY})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "reverse_spouse_reimbursement") == [{
        "p_household_id": HH, "p_reimbursement_id": R_NEW, "p_request_key": KEY, "p_actor_user_id": HUSBAND}]
    body = resp.json()
    assert (body["kind"], body["reverses_id"], body["amount"], body["outstanding_after"], body["account_id"]) == (
        "reversal", R_NEW, 25.0, 250.0, ACCOUNT)


@pytest.mark.parametrize("caller", [WIFE, CHILD])
def test_she_and_members_do_not_reverse(family, caller):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_NEW}/reversal", headers=bearer(caller), json={"request_key": KEY})
    assert resp.status_code == 403
    assert _calls(family, "reverse_spouse_reimbursement") == []


def test_an_unknown_repayment_is_not_found(family):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/b9000000-0000-4000-8000-0000000000ff/reversal",
                       headers=bearer(HUSBAND), json={"request_key": KEY})
    assert resp.status_code == 404 and resp.json()["detail"]["code"] == "reimbursement_not_found"


@pytest.mark.parametrize("hint", list(ns.REVERSAL_REFUSALS))
def test_reversal_refusals_map_to_codes(family, hint):
    def refuse(_p):
        raise db_error(hint)

    family.rpc_handlers["reverse_spouse_reimbursement"] = refuse
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_NEW}/reversal", headers=bearer(HUSBAND), json={"request_key": KEY})
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == hint


def test_a_reversal_needs_a_key(family):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_NEW}/reversal", headers=bearer(HUSBAND), json={})
    assert resp.status_code == 422


# ─── What the ledger shows ────────────────────────────────────────────────────

def test_what_is_owed_is_net_of_reversals_and_ignores_pending_requests(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    assert resp.status_code == 200, resp.text
    balance = resp.json()["balance"]
    # 300 advanced; repaid 50 + 25 + 40 - 40 (reversed) = 75; her 30 pending does not count.
    assert (balance["gross_advanced"], balance["reimbursed"], balance["outstanding"]) == (300.0, 75.0, 225.0)
    assert (balance["pending_requested"], balance["pending_count"]) == (30.0, 1)


def test_the_history_marks_reversals_and_who_may_reverse(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND))
    repayments = {h["id"]: h for h in resp.json()["history"] if h["type"] == "reimbursement"}
    assert (repayments[R_NEW]["kind"], repayments[R_NEW]["reversed"], repayments[R_NEW]["can_reverse"]) == ("payment", False, True)
    assert (repayments["r-pool"]["reversed"], repayments["r-pool"]["reversed_by_id"], repayments["r-pool"]["can_reverse"]) == (True, "r-back", False)
    assert (repayments["r-back"]["kind"], repayments["r-back"]["reverses_id"], repayments["r-back"]["account_id"]) == ("reversal", "r-pool", POOL)
    assert (repayments["r-old"]["moved_balance"], repayments["r-old"]["can_reverse"]) == (False, False), "a legacy row is not reversed"
    assert all("request_key" not in h and "transfer_id" not in h for h in resp.json()["history"])


def test_a_co_admin_may_not_reverse_his_personal_account_payment(family):
    """While the husband is there the admin reads none of her ledger (review R3-01); once he is
    gone the admin reads it, and still may not reverse what left the husband's own account."""
    assert client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COADMIN)).status_code == 403
    husband_leaves(family)
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COADMIN))
    repayments = {h["id"]: h for h in resp.json()["history"] if h["type"] == "reimbursement"}
    assert repayments[R_NEW]["can_reverse"] is False


def test_the_wife_may_reverse_nothing(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    assert not any(h.get("can_reverse") for h in resp.json()["history"])


def test_the_ledger_lists_her_requests_with_their_outcomes(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    requests = [(q["id"], q["status"], q["amount"], q["reason"]) for q in resp.json()["requests"]]
    assert requests == [(Q_PENDING, "pending", 30.0, None), (Q_DECLINED, "declined", 10.0, "Not received yet"),
                        (Q_APPROVED, "approved", 25.0, None)]
    assert all("decided_by" not in q for q in resp.json()["requests"])


def test_the_requests_route_lists_them_too(family):
    resp = client.get(_q(), headers=bearer(HUSBAND))
    assert resp.status_code == 200
    assert [q["status"] for q in resp.json()["requests"]] == ["pending", "declined", "approved"]


@pytest.mark.parametrize("caller, can_request, can_decide", [(WIFE, True, False), (HUSBAND, False, True)])
def test_the_summary_says_who_asks_and_who_decides(family, caller, can_request, can_decide):
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(caller)).json()
    wife = body["wives"][0]
    assert (wife["can_request"], wife["can_decide"]) == (can_request, can_decide)
    assert body["can_request_reimbursement"] is can_request
    assert body["can_record_reimbursement"] is can_decide
    assert [q["status"] for q in wife["requests"]][0] == "pending"
    assert wife["reimbursement"]["outstanding"] == 225.0 and wife["reimbursement"]["pending_requested"] == 30.0


@pytest.mark.parametrize("caller", [COADMIN, CHILD])
def test_the_summary_gives_anyone_else_no_entry_for_her(family, caller):
    """Review R3-01: no entry for her, no total, nothing to decide."""
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(caller)).json()
    assert body["wives"] == []
    assert body["can_record_reimbursement"] is False and body["can_request_reimbursement"] is False


def test_a_wife_who_is_an_admin_still_asks_and_decides_nothing_of_her_own(family):
    """Admin rights never let her record, approve or reverse repayments to herself."""
    for m in family.tables["household_memberships"]:
        if m["user_id"] == WIFE:
            m["role"] = "admin"
    wife = client.get(f"/households/{HH}/nafaqah", headers=bearer(WIFE)).json()["wives"][0]
    assert (wife["can_request"], wife["can_decide"]) == (True, False)
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    assert not any(h.get("can_reverse") for h in resp.json()["history"])
    assert _repay(WIFE, account_id=HER_ACCOUNT, request_key=KEY).json()["detail"]["code"] == "wife_must_request"
    assert client.post(_q(f"/{Q_PENDING}/approve"), headers=bearer(WIFE),
                       json={"account_id": POOL, "request_key": KEY}).status_code == 403
    assert client.post(f"/households/{HH}/nafaqah/reimbursements/{R_NEW}/reversal", headers=bearer(WIFE),
                       json={"request_key": KEY}).status_code == 403
    assert _calls(family, "record_spouse_reimbursement") == _calls(family, "approve_spouse_reimbursement_request") == []


def test_the_settlement_figures_are_net_of_reversals(family):
    from settlement_engine import _nafaqah_balance

    balance = _nafaqah_balance(ns.load_family_context(HH), [WIFE])
    assert (balance["reimbursed"], balance["outstanding"]) == (75.0, 225.0)


# ─── A former member's record ─────────────────────────────────────────────────

def test_a_former_member_payment_from_an_account(family):
    resp = _pay(HUSBAND, account_id=ACCOUNT)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "record_former_member_debt_payment") == [{
        "p_household_id": HH, "p_debt_id": DEBT, "p_amount": "30.00", "p_payment_method": "bank_transfer",
        "p_request_key": KEY, "p_actor_user_id": HUSBAND, "p_account_id": ACCOUNT}]
    assert (resp.json()["account_id"], resp.json()["balance_moved"]) == (ACCOUNT, True)


def test_a_former_member_payment_without_an_account_is_told_to_update(family):
    resp = _pay(HUSBAND)
    assert resp.status_code == 426 and resp.json()["detail"]["code"] == "app_update_required"
    assert _calls(family, "record_former_member_debt_payment") == []


@pytest.mark.parametrize("hint, code, status_code", [
    ("account_unavailable", "P0002", 422),
    ("account_forbidden", "42501", 403),
    ("insufficient_funds", "22000", 409),
    ("app_update_required", "0A000", 426),
])
def test_former_member_account_refusals_map_to_codes(family, hint, code, status_code):
    def refuse(_params):
        raise db_error(hint, code=code)

    family.rpc_handlers["record_former_member_debt_payment"] = refuse
    resp = _pay(HUSBAND, account_id=ACCOUNT)
    assert resp.status_code == status_code, resp.text
    assert resp.json()["detail"]["code"] == hint
    assert "refused" not in resp.text


def test_former_member_history_shows_reversal_state(family):
    debts = {d["id"]: d for d in client.get(f"/households/{HH}/nafaqah", headers=bearer(HUSBAND)).json()["former_member_debts"]}
    events = {e["id"]: e for e in debts[DEBT]["events"]}
    assert (events[E_TRACKED]["moved_balance"], events[E_TRACKED]["account_id"], events[E_TRACKED]["can_reverse"]) == (True, ACCOUNT, True)
    assert (events[E_LEGACY]["moved_balance"], events[E_LEGACY]["can_reverse"]) == (False, False)
    waived = {e["id"]: e for e in debts[DEBT_WAIVED]["events"]}
    assert waived[E_WAIVED]["can_reverse"] is False, "not after her waiver"
    assert all("transfer_id" not in e and "recorded_by" not in e for d in debts.values() for e in d["events"])


def test_a_member_sees_no_reverse_action(family):
    debts = client.get(f"/households/{HH}/nafaqah", headers=bearer(CHILD)).json()["former_member_debts"]
    assert not any(e["can_reverse"] for d in debts for e in d["events"])


def test_the_husband_reverses_a_former_member_payment(family):
    url = f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/payments/{E_TRACKED}/reversal"
    resp = client.post(url, headers=bearer(HUSBAND), json={"request_key": KEY})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "reverse_former_member_debt_payment") == [{
        "p_household_id": HH, "p_debt_id": DEBT, "p_event_id": E_TRACKED, "p_request_key": KEY, "p_actor_user_id": HUSBAND}]
    assert (resp.json()["status"], resp.json()["remaining"], resp.json()["account_id"]) == ("open", 130.0, ACCOUNT)


@pytest.mark.parametrize("caller", [WIFE, CHILD])
def test_members_do_not_reverse_a_former_member_payment(family, caller):
    url = f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/payments/{E_TRACKED}/reversal"
    assert client.post(url, headers=bearer(caller), json={"request_key": KEY}).status_code == 403
    assert _calls(family, "reverse_former_member_debt_payment") == []


def test_a_former_member_reversal_after_her_waiver_is_refused(family):
    def refuse(_p):
        raise db_error("reversal_after_waiver")

    family.rpc_handlers["reverse_former_member_debt_payment"] = refuse
    url = f"/households/{HH}/nafaqah/former-member-debts/{DEBT_WAIVED}/payments/{E_WAIVED}/reversal"
    resp = client.post(url, headers=bearer(HUSBAND), json={"request_key": KEY})
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "reversal_after_waiver"


# ─── The migration defines what the service calls ─────────────────────────────

def _signatures(text, name):
    return [set(re.findall(r"\b(p_\w+)\b", m)) for m in
            re.findall(rf"CREATE OR REPLACE FUNCTION public\.{name}\((.*?)\)\s*RETURNS", text, re.S)]


def test_the_service_calls_the_signatures_the_migration_defines():
    text = MIGRATION.read_text(encoding="utf-8")
    assert {"p_household_id", "p_wife_user_id", "p_amount", "p_payment_method", "p_notes", "p_actor_user_id",
            "p_account_id", "p_request_key", "p_wife_account_id"} in _signatures(text, "record_spouse_reimbursement")
    assert {"p_household_id", "p_debt_id", "p_amount", "p_payment_method", "p_request_key", "p_actor_user_id",
            "p_account_id"} in _signatures(text, "record_former_member_debt_payment")
    assert {"p_household_id", "p_amount", "p_payment_method", "p_request_key", "p_actor_user_id",
            "p_wife_account_id"} in _signatures(text, "request_spouse_reimbursement")
    assert {"p_household_id", "p_request_id", "p_actor_user_id"} in _signatures(text, "cancel_spouse_reimbursement_request")
    assert {"p_household_id", "p_request_id", "p_reason", "p_actor_user_id"} in _signatures(text, "decline_spouse_reimbursement_request")
    assert {"p_household_id", "p_request_id", "p_account_id", "p_request_key", "p_actor_user_id",
            "p_wife_account_id"} in _signatures(text, "approve_spouse_reimbursement_request")
    for name, params in (("create_wife_account", {"p_household_id", "p_wife_user_id", "p_name", "p_actor_user_id"}),
                         ("assign_wife_account", {"p_household_id", "p_account_id", "p_wife_user_id", "p_actor_user_id"}),
                         ("archive_wife_account", {"p_household_id", "p_account_id", "p_actor_user_id"})):
        assert params in _signatures(text, name), name
    assert {"p_household_id", "p_reimbursement_id", "p_request_key", "p_actor_user_id"} in _signatures(text, "reverse_spouse_reimbursement")
    assert {"p_household_id", "p_debt_id", "p_event_id", "p_request_key", "p_actor_user_id"} in _signatures(text, "reverse_former_member_debt_payment")
    for hint in ("app_update_required", "wife_must_request", "account_unavailable", "account_forbidden", "insufficient_funds",
                 "request_key_required", "request_key_reused", "request_not_found", "request_not_pending",
                 "request_exceeds_outstanding", "pending_exceeds_outstanding", "reimbursement_not_found", "payment_not_found",
                 "account_required", "invalid_reason", *ns.REVERSAL_REFUSALS,
                 "wife_account_required", "wife_account_invalid", "wife_account_insufficient_funds", "wife_account_forbidden",
                 "wife_account_has_history", "not_a_wife", "invalid_name", "account_not_found"):
        assert f"HINT = '{hint}'" in text, hint
