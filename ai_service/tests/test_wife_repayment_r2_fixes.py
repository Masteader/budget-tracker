"""
Round 2 review fixes of tracked repayments (owner decisions 2026-11-06), at the API.

  * R2-07: two calls with one request key at once. The database answers the second
    request_key_reused (test 61); should a raw unique violation of a key constraint still reach
    the API, it is named request_key_reused too (HTTP 409), never a 500.
  * R2-04: a family does not become a roommates household while a former member's record is open.
    The database names the blocker (test 60); the API gives it its own code, so the app can say to
    close the record first.
  * PostgREST answers at most its max-rows setting per request (1000 on Supabase) and says nothing
    when it cut the answer short. What is owed, repaid and pending, a cycle's allowance spend and the
    settlement engine's transactions are summed from every row, page by page.

The database suites (tests 60 and 61) prove the RPCs; here they are stand-ins.
"""

from __future__ import annotations

import pytest
from postgrest.exceptions import APIError

import nafaqah_service as ns
import settlement_engine
from test_fable_household_type import FAMILY, HUSBAND as FAMILY_HUSBAND, FakeApiError, world  # noqa: F401
from test_wife_repayment_debit import WIFE_WA  # noqa: F401
from test_wife_repayment_debit import (  # noqa: F401  (pytest fixture)
    ACCOUNT,
    HH,
    HUSBAND,
    KEY,
    WIFE,
    bearer,
    client,
    family,
)


# ─── R2-07: a raw unique violation of a key is request_key_reused ─────────────

KEY_CONSTRAINTS = (
    "nafaqah_request_keys_pkey",
    "uq_spouse_reimbursements_request",
    "uq_former_member_debt_events_request",
    "uq_spouse_reimbursement_requests_key",
)


@pytest.mark.parametrize("constraint", KEY_CONSTRAINTS)
def test_r2_07_a_key_constraint_violation_is_request_key_reused(constraint):
    exc = APIError({"code": "23505", "hint": None, "details": "Key (household_id, request_key)=(...) already exists.",
                    "message": f'duplicate key value violates unique constraint "{constraint}"'})
    assert isinstance(ns._map_db_error(exc), ns.RequestKeyReused)


def test_r2_07_another_unique_violation_is_not_called_a_reused_key():
    exc = APIError({"code": "23505", "hint": None, "details": "",
                    "message": 'duplicate key value violates unique constraint "uq_spouse_reimbursements_reverses"'})
    assert not isinstance(ns._map_db_error(exc), ns.RequestKeyReused)


def test_r2_07_the_route_answers_409_request_key_reused_not_500(family):
    def race(_params):
        raise APIError({"code": "23505", "hint": None, "details": "",
                        "message": 'duplicate key value violates unique constraint "uq_spouse_reimbursements_request"'})

    family.rpc_handlers["record_spouse_reimbursement"] = race
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND), json={
        "amount": 10, "payment_method": "cash", "wife_user_id": WIFE, "account_id": ACCOUNT, "request_key": KEY,
        "wife_account_id": WIFE_WA})
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"]["code"] == "request_key_reused"


# ─── R2-04: an open former member's record blocks the switch to roommates ─────

def _blocked(details: str):
    def refuse(_params):
        err = FakeApiError("A family household with a wife or Nafaqah records cannot become a roommates household",
                           "22023", "type_change_blocked")
        err.details = details
        raise err
    return refuse


def test_r2_04_an_open_record_has_its_own_code(world):
    world.rpc_handlers["set_household_type"] = _blocked("former_member_debt")
    res = client.put(f"/households/{FAMILY}/type", headers=bearer(FAMILY_HUSBAND), json={"household_type": "roommates"})
    assert res.status_code == 409, res.text
    assert res.json()["detail"]["code"] == "former_member_debt_open"


def test_r2_04_with_a_wife_still_there_it_is_the_general_refusal(world):
    world.rpc_handlers["set_household_type"] = _blocked("spouse_member,former_member_debt")
    res = client.put(f"/households/{FAMILY}/type", headers=bearer(FAMILY_HUSBAND), json={"household_type": "roommates"})
    assert res.status_code == 409, res.text
    assert res.json()["detail"]["code"] == "type_change_blocked"


# ─── PostgREST's row cap: every row is counted ─────────────────────────────────

MAX_ROWS = 1000


def _many(prefix: str, n: int, make):
    return [make(f"{prefix}-{i:05d}", i) for i in range(n)]


@pytest.fixture()
def big_ledger(family):
    """1,500 advances of 10.00 and 1,200 repayments of 5.00 (300 of them tracked), 1,100 pending
    requests of 0.50 and 1,100 answered ones, behind a 1000-row cap."""
    family.max_rows = MAX_ROWS
    family.tables["transactions"] = _many("adv", 1500, lambda i, n: {
        "id": i, "household_id": HH, "amount": 10.0, "merchant": "Panda", "timestamp": f"2026-10-01T00:{n % 60:02d}:00+00:00",
        "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE})
    family.tables["account_transfers"] = _many("tr", 300, lambda i, n: {
        "id": i, "household_id": HH, "from_account_id": ACCOUNT, "to_account_id": None, "amount": 5.0})
    family.tables["spouse_reimbursements"] = _many("rep", 1200, lambda i, n: {
        "id": i, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 5.0,
        "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-10-02T00:00:00+00:00",
        "transfer_id": f"tr-{n:05d}" if n < 300 else None, "kind": "payment", "reverses_id": None})
    family.tables["spouse_reimbursement_requests"] = _many("req", 2200, lambda i, n: {
        "id": i, "household_id": HH, "wife_user_id": WIFE, "amount": 0.5, "payment_method": "cash",
        "created_at": "2026-10-03T00:00:00+00:00"})
    family.tables["spouse_reimbursement_request_outcomes"] = [
        {"request_id": f"req-{n:05d}", "outcome": "declined", "reason": None, "reimbursement_id": None,
         "decided_by": HUSBAND, "created_at": "2026-10-04T00:00:00+00:00"} for n in range(1100, 2200)]
    return family


def test_caps_the_fake_like_postgrest(big_ledger):
    rows = big_ledger.table("transactions").select("id").eq("household_id", HH).execute().data
    assert len(rows) == MAX_ROWS


def test_caps_what_is_owed_counts_every_advance_and_repayment(big_ledger):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    balance = body["balance"]
    # 15,000 advanced, 6,000 repaid: 9,000 owed.
    assert (balance["gross_advanced"], balance["reimbursed"], balance["outstanding"]) == (15000.0, 6000.0, 9000.0)
    # 1,100 pending of 0.50: 550.00.
    assert (balance["pending_requested"], balance["pending_count"]) == (550.0, 1100)
    assert len(body["history"]) == 2700
    assert len(body["requests"]) == 2200
    # Each tracked repayment still names the account it left (the transfers are read in chunks).
    tracked = [h for h in body["history"] if h["type"] == "reimbursement" and h["moved_balance"]]
    assert len(tracked) == 300 and all(h["account_id"] == ACCOUNT for h in tracked)


def test_caps_the_summary_and_the_settlement_engine_agree(big_ledger):
    ctx = ns.load_family_context(HH)
    summary = ns.build_summary(ctx, HUSBAND)
    assert summary["wives"][0]["reimbursement"]["outstanding"] == 9000.0
    assert settlement_engine._nafaqah_balance(ctx, [WIFE])["outstanding"] == 9000.0


def test_caps_a_cycle_allowance_counts_every_purchase(family):
    family.max_rows = MAX_ROWS
    family.tables["transactions"] = _many("own", 1100, lambda i, n: {
        "id": i, "household_id": HH, "amount": 1.0, "timestamp": "2026-11-01T00:00:00+00:00", "cycle_key": "2026-11",
        "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE})
    family.tables.setdefault("member_allowances", []).append(
        {"household_id": HH, "member_user_id": WIFE, "cycle_key": "2026-11", "amount": 2000.0})
    ctx = ns.load_family_context(HH)
    status = ns.get_allowance(ctx, WIFE, "2026-11")
    assert status["spent"] == 1100.0


def test_caps_the_settlement_engine_reads_every_transaction_of_the_cycle(family):
    family.max_rows = MAX_ROWS
    family.tables["transactions"] = _many("cyc", 1500, lambda i, n: {
        "id": i, "household_id": HH, "amount": 1.0, "timestamp": f"2026-11-0{1 + n % 9}T00:00:00+00:00"})
    rows = settlement_engine._cycle_transactions(ns.get_client(), HH, "2026-10-27T00:00:00+00:00", "id, amount, timestamp")
    assert len(rows) == 1500
    # Newest first, as before.
    assert [r["timestamp"] for r in rows] == sorted((r["timestamp"] for r in rows), reverse=True)


def test_caps_every_event_of_a_former_member_record_is_listed(family):
    family.max_rows = MAX_ROWS
    debt = "b3000000-0000-4000-8000-0000000000ff"
    family.tables["former_member_debts"] = [
        {"id": debt, "household_id": HH, "original_amount": 2000.0, "paid_amount": 1200.0, "status": "open",
         "created_at": "2026-11-05T10:00:00+00:00", "closed_at": None}]
    family.tables["former_member_debt_events"] = _many("ev", 1200, lambda i, n: {
        "id": i, "debt_id": debt, "kind": "payment", "amount": 1.0, "payment_method": "cash",
        "remaining_after": 2000.0 - n - 1, "recorded_by": HUSBAND, "request_key": f"k-{n}", "created_at": "2026-11-06T10:00:00+00:00"})
    ctx = ns.load_family_context(HH)
    records = ns.list_former_member_debts(ctx, HUSBAND)
    assert len(records) == 1 and len(records[0]["events"]) == 1200
