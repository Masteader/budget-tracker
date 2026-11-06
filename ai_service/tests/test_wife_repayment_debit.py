"""
A repayment to the wife moves money out of the account he picks (owner decision 2026-11-06).

Migration 20261105001300_wife_repayment_debit.sql: a repayment of her wife_reimbursable advances,
or a payment of a former member's record, may name the account it is paid from. The database
debits it (and credits her personal account when she has one) as one transfer, never a budget;
without an account only the amount and method are recorded, as before. The API passes the account
and the client's request key to the RPC with the verified caller, keeps the old call for old app
builds, maps every refusal to a code the app translates and shows which repayments moved money.

The database suite (tests 56 and 57) proves the RPCs; here they are stand-ins that record their
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
PEER1 = "b2000000-0000-4000-8000-0000000000f1"
PEER2 = "b2000000-0000-4000-8000-0000000000f2"
ACCOUNT = "b5000000-0000-4000-8000-000000000001"
HER_ACCOUNT = "b5000000-0000-4000-8000-000000000002"
TRANSFER = "b6000000-0000-4000-8000-000000000001"
DEBT = "b3000000-0000-4000-8000-000000000001"
KEY = "b4000000-0000-4000-8000-000000000001"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def db_error(hint: str, code: str = "22023", message: str = "refused") -> APIError:
    return APIError({"code": code, "hint": hint, "details": None, "message": message})


@pytest.fixture()
def family(fake_supabase):
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": HH, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
        {"id": CHILD, "household_id": HH, "role": "member", "financial_role": "family_member", "display_name": "Fahad"},
        {"id": PEER1, "household_id": HH_ROOM, "role": "admin", "financial_role": "peer", "display_name": "Ali"},
        {"id": PEER2, "household_id": HH_ROOM, "role": "member", "financial_role": "peer", "display_name": "Saad"},
    ])
    fake_supabase.seed("household_memberships", [
        {"user_id": HUSBAND, "financial_role": "provider", "household_id": HH, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": WIFE, "financial_role": "spouse", "household_id": HH, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"user_id": CHILD, "financial_role": "family_member", "household_id": HH, "role": "member", "created_at": "2026-01-03T00:00:00+00:00"},
        {"user_id": PEER1, "financial_role": "peer", "household_id": HH_ROOM, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": PEER2, "financial_role": "peer", "household_id": HH_ROOM, "role": "member", "created_at": "2026-01-01T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": HH, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND, "household_type": "family"},
        {"id": HH_ROOM, "payday_day": 27, "owner_user_id": PEER1, "household_type": "roommates"},
    ])
    fake_supabase.seed("transactions", [
        {"id": "t1", "household_id": HH, "amount": 300.0, "merchant": "Panda", "timestamp": "2026-11-10T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
    ])
    fake_supabase.seed("spouse_reimbursements", [
        # Before this release: amount only.
        {"id": "r-old", "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 50.0,
         "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-11T10:00:00+00:00"},
        # From his account.
        {"id": "r-new", "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 25.0,
         "payment_method": "bank_transfer", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-12T10:00:00+00:00",
         "transfer_id": TRANSFER, "request_key": KEY},
    ])
    fake_supabase.seed("account_transfers", [
        {"id": TRANSFER, "household_id": HH, "user_id": HUSBAND, "from_account_id": ACCOUNT, "to_account_id": HER_ACCOUNT,
         "amount": 25.0, "fee": 0.0},
    ])
    fake_supabase.seed("former_member_debts", [
        {"id": DEBT, "household_id": HH, "original_amount": 170.0, "paid_amount": 70.0, "status": "open",
         "created_at": "2026-11-05T10:00:00+00:00", "closed_at": None},
    ])
    fake_supabase.seed("former_member_debt_events", [
        {"id": "e1", "debt_id": DEBT, "kind": "payment", "amount": 40.0, "payment_method": "cash",
         "remaining_after": 130.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-06T10:00:00+00:00"},
        {"id": "e2", "debt_id": DEBT, "kind": "payment", "amount": 30.0, "payment_method": "bank_transfer",
         "remaining_after": 100.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-07T10:00:00+00:00",
         "transfer_id": TRANSFER},
    ])

    def repay(params):
        return {"success": True, "replayed": False, "reimbursement_id": "r-x", "amount": float(params["p_amount"]),
                "payment_method": params["p_payment_method"], "account_id": params.get("p_account_id"),
                "wife_account_credited": bool(params.get("p_account_id")),
                "outstanding_before": 225.0, "outstanding_after": 225.0 - float(params["p_amount"])}

    def pay(params):
        return {"success": True, "replayed": False, "event_id": "e-new", "debt_id": params["p_debt_id"],
                "amount": float(params["p_amount"]), "payment_method": params["p_payment_method"],
                "remaining": 100.0 - float(params["p_amount"]), "status": "open",
                "account_id": params.get("p_account_id")}

    fake_supabase.rpc_handlers["record_spouse_reimbursement"] = repay
    fake_supabase.rpc_handlers["record_former_member_debt_payment"] = pay
    fake_supabase.rpc_handlers["get_former_member_debt_deletion_notices"] = lambda _p: []
    return fake_supabase


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


def _repay(user, **body):
    payload = {"amount": 20, "payment_method": "bank_transfer", **body}
    return client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(user), json=payload)


def _pay(user, **body):
    payload = {"amount": 30, "payment_method": "bank_transfer", "request_key": KEY, **body}
    return client.post(f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/payments", headers=bearer(user), json=payload)


# ─── Repaying the wife ───────────────────────────────────────────────────────

def test_a_repayment_from_an_account_goes_to_the_rpc_with_the_account_and_the_key(family):
    resp = _repay(HUSBAND, amount=20.4, account_id=ACCOUNT, request_key=KEY)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "record_spouse_reimbursement") == [{
        "p_household_id": HH, "p_wife_user_id": WIFE, "p_amount": "20.40", "p_payment_method": "bank_transfer",
        "p_notes": None, "p_actor_user_id": HUSBAND, "p_account_id": ACCOUNT, "p_request_key": KEY}]
    body = resp.json()
    assert (body["account_id"], body["balance_moved"], body["wife_account_credited"], body["replayed"]) == (
        ACCOUNT, True, True, False)
    assert body["outstanding_after"] == 204.6


def test_not_tracked_in_the_app_sends_no_account(family):
    resp = _repay(HUSBAND, payment_method="cash", request_key=KEY)
    assert resp.status_code == 200, resp.text
    params = _calls(family, "record_spouse_reimbursement")[0]
    assert params["p_account_id"] is None and params["p_request_key"] == KEY
    assert (resp.json()["balance_moved"], resp.json()["account_id"]) == (False, None)


def test_an_old_app_keeps_the_old_call(family):
    """Neither field: the 6-argument function, exactly as before this release."""
    resp = _repay(HUSBAND)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "record_spouse_reimbursement") == [{
        "p_household_id": HH, "p_wife_user_id": WIFE, "p_amount": "20.00", "p_payment_method": "bank_transfer",
        "p_notes": None, "p_actor_user_id": HUSBAND}]
    assert resp.json()["balance_moved"] is False


def test_an_account_needs_a_request_key(family):
    resp = _repay(HUSBAND, account_id=ACCOUNT)
    assert resp.status_code == 422
    assert _calls(family, "record_spouse_reimbursement") == []


@pytest.mark.parametrize("body", [{"account_id": "not-a-uuid", "request_key": KEY}, {"request_key": "nope"}])
def test_malformed_ids_are_refused(family, body):
    assert _repay(HUSBAND, **body).status_code == 422
    assert _calls(family, "record_spouse_reimbursement") == []


def test_the_wife_never_picks_an_account(family):
    resp = _repay(WIFE, account_id=HER_ACCOUNT, request_key=KEY)
    assert resp.status_code == 403
    assert resp.json()["detail"]["code"] == "account_forbidden"
    assert _calls(family, "record_spouse_reimbursement") == []


def test_a_replay_is_answered_even_when_nothing_is_owed_any_more(family):
    """The first tap paid it all and its answer was lost: the database answers the replay."""
    family.tables["spouse_reimbursements"].append({
        "id": "r-full", "household_id": HH, "wife_user_id": WIFE, "amount": 225.0, "payment_method": "cash",
        "created_at": "2026-11-13T10:00:00+00:00"})
    family.rpc_handlers["record_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": True, "reimbursement_id": "r-full", "amount": 225.0, "payment_method": "cash",
        "account_id": ACCOUNT, "wife_account_credited": False, "outstanding_before": 225.0, "outstanding_after": 0.0}
    resp = _repay(HUSBAND, amount=10, account_id=ACCOUNT, request_key=KEY)  # the retry typed another amount
    assert resp.status_code == 200, resp.text
    assert (resp.json()["replayed"], resp.json()["amount"], resp.json()["outstanding_after"]) == (True, 225.0, 0.0)


def test_without_a_key_overpayment_is_still_refused_before_the_rpc(family):
    assert _repay(HUSBAND, amount=225.01).status_code == 409
    assert _calls(family, "record_spouse_reimbursement") == []


@pytest.mark.parametrize("hint, code, status_code, detail_code", [
    ("account_unavailable", "P0002", 422, "account_unavailable"),
    ("account_forbidden", "42501", 403, "account_forbidden"),
    ("insufficient_funds", "22000", 409, "insufficient_funds"),
    ("request_key_reused", "22023", 409, "request_key_reused"),
    ("request_key_required", "22023", 422, None),
    ("overpayment", "22023", 409, "overpayment"),
])
def test_database_refusals_map_to_codes_the_app_knows(family, hint, code, status_code, detail_code):
    def refuse(_params):
        raise db_error(hint, code=code)

    family.rpc_handlers["record_spouse_reimbursement"] = refuse
    resp = _repay(HUSBAND, account_id=ACCOUNT, request_key=KEY)
    assert resp.status_code == status_code, resp.text
    if detail_code:
        assert resp.json()["detail"]["code"] == detail_code
    assert "refused" not in resp.text, "the raw database text never reaches the client"


def test_the_legacy_route_passes_the_account_in_a_family(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(HUSBAND), json={
        "household_id": HH, "payer_id": "husband", "recipient_id": "wife", "amount": 10, "payment_method": "cash",
        "account_id": ACCOUNT, "request_key": KEY})
    assert resp.status_code == 200, resp.text
    params = _calls(family, "record_spouse_reimbursement")[0]
    assert (params["p_account_id"], params["p_request_key"]) == (ACCOUNT, KEY)
    assert resp.json()["balance_moved"] is True


def test_the_legacy_route_refuses_an_account_between_roommates(family):
    """A roommate settlement records no account: an account there would be ignored, so it is refused."""
    resp = client.post(f"/households/{HH_ROOM}/reimbursements", headers=bearer(PEER1), json={
        "household_id": HH_ROOM, "payer_id": PEER1, "recipient_id": PEER2, "amount": 10, "payment_method": "cash",
        "account_id": ACCOUNT, "request_key": KEY})
    assert resp.status_code == 422
    assert not [t for t in family.tables["transactions"] if t.get("is_settlement")]


def test_the_history_shows_which_repayments_moved_money(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    assert resp.status_code == 200, resp.text
    repayments = {h["id"]: h for h in resp.json()["history"] if h["type"] == "reimbursement"}
    assert (repayments["r-new"]["moved_balance"], repayments["r-new"]["account_id"]) == (True, ACCOUNT)
    assert (repayments["r-old"]["moved_balance"], repayments["r-old"]["account_id"]) == (False, None)
    assert all("request_key" not in h and "transfer_id" not in h for h in resp.json()["history"])
    assert resp.json()["balance"]["outstanding"] == 225.0, "outstanding sums are unchanged"


# ─── A former member's record ─────────────────────────────────────────────────

def test_a_former_member_payment_from_an_account(family):
    resp = _pay(HUSBAND, account_id=ACCOUNT)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "record_former_member_debt_payment") == [{
        "p_household_id": HH, "p_debt_id": DEBT, "p_amount": "30.00", "p_payment_method": "bank_transfer",
        "p_request_key": KEY, "p_actor_user_id": HUSBAND, "p_account_id": ACCOUNT}]
    assert (resp.json()["account_id"], resp.json()["balance_moved"]) == (ACCOUNT, True)


def test_a_former_member_payment_without_an_account_keeps_the_old_call(family):
    resp = _pay(HUSBAND)
    assert resp.status_code == 200, resp.text
    assert "p_account_id" not in _calls(family, "record_former_member_debt_payment")[0]
    assert resp.json()["balance_moved"] is False


@pytest.mark.parametrize("hint, code, status_code, detail_code", [
    ("account_unavailable", "P0002", 422, "account_unavailable"),
    ("account_forbidden", "42501", 403, "account_forbidden"),
    ("insufficient_funds", "22000", 409, "insufficient_funds"),
])
def test_former_member_account_refusals_map_to_codes(family, hint, code, status_code, detail_code):
    def refuse(_params):
        raise db_error(hint, code=code)

    family.rpc_handlers["record_former_member_debt_payment"] = refuse
    resp = _pay(HUSBAND, account_id=ACCOUNT)
    assert resp.status_code == status_code, resp.text
    assert resp.json()["detail"]["code"] == detail_code
    assert "refused" not in resp.text


def test_former_member_history_shows_which_payments_moved_money(family):
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(CHILD)).json()
    events = body["former_member_debts"][0]["events"]
    assert [(e["amount"], e["moved_balance"], e["account_id"]) for e in events] == [
        (40.0, False, None), (30.0, True, ACCOUNT)]
    assert all("transfer_id" not in e and "recorded_by" not in e for e in events)


def test_a_malformed_former_member_account_is_refused(family):
    assert _pay(HUSBAND, account_id="nope").status_code == 422
    assert _calls(family, "record_former_member_debt_payment") == []


# ─── The migration defines what the service calls ─────────────────────────────

def test_the_service_calls_the_signatures_the_migration_defines():
    text = MIGRATION.read_text(encoding="utf-8")
    signatures = [set(re.findall(r"\b(p_\w+)\b", m)) for m in
                  re.findall(r"CREATE OR REPLACE FUNCTION public\.record_spouse_reimbursement\((.*?)\)\s*RETURNS", text, re.S)]
    assert {"p_household_id", "p_wife_user_id", "p_amount", "p_payment_method", "p_notes", "p_actor_user_id",
            "p_account_id", "p_request_key"} in signatures
    assert {"p_household_id", "p_wife_user_id", "p_amount", "p_payment_method", "p_notes", "p_actor_user_id"} in signatures
    payments = [set(re.findall(r"\b(p_\w+)\b", m)) for m in
                re.findall(r"CREATE OR REPLACE FUNCTION public\.record_former_member_debt_payment\((.*?)\)\s*RETURNS", text, re.S)]
    assert {"p_household_id", "p_debt_id", "p_amount", "p_payment_method", "p_request_key", "p_actor_user_id",
            "p_account_id"} in payments
    for hint in ("account_unavailable", "account_forbidden", "insufficient_funds", "request_key_required", "request_key_reused"):
        assert f"HINT = '{hint}'" in text, hint
