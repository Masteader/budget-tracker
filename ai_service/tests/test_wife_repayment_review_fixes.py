"""
Round 1 review fixes of tracked repayments (owner decisions 2026-11-06), at the API.

  * R1-01: only the husband, or a household admin who is not a wife, records, approves, declines,
    pays or waives a former member's record, or reverses; a wife never does, even as an admin, for
    a co-wife or a former member, and never pays from a pool.
  * R1-02: a retried former-member payment or waiver reaches the database, which answers the
    replay; the API no longer refuses it from what the record looks like now.
  * R1-07: who reverses follows the account: a personal account's owner while he is a member and
    not a wife, whatever his role now; a pool, any admin who is not a wife.
  * R1-08: the history names who paid.
  * R1-10: the former-member routes are a family's only.
  * R1-09: the decline reason is at most 200 Unicode code points, as the database counts.

The database suite (test 59) proves the RPCs; here they are stand-ins, as in the modules whose
fixtures this reuses.
"""

from __future__ import annotations

import pytest

import nafaqah_service as ns
from test_wife_repayment_debit import (  # noqa: F401  (pytest fixture)
    ACCOUNT,
    COADMIN,
    CHILD,
    DEBT,
    DEBT_WAIVED,
    E_TRACKED,
    HH,
    HH_ROOM,
    HUSBAND,
    KEY,
    PEER1,
    POOL,
    Q_PENDING,
    R_NEW,
    WIFE,
    husband_leaves,
    _calls,
    bearer,
    client,
    db_error,
    family,
)

WIFE2 = "b2000000-0000-4000-8000-0000000000aa"
WIFE2_ACCOUNT = "b5000000-0000-4000-8000-0000000000aa"
COADMIN_ACCOUNT = "b5000000-0000-4000-8000-0000000000cd"
T_COADMIN = "b6000000-0000-4000-8000-0000000000cd"
R_COADMIN = "b9000000-0000-4000-8000-0000000000cd"
E_COADMIN = "b8000000-0000-4000-8000-0000000000cd"
T_FMD_COADMIN = "b6000000-0000-4000-8000-0000000000ce"


@pytest.fixture()
def co_wife(family):
    """A second wife who is also a household admin, with an account of her own."""
    family.tables["users"].append(
        {"id": WIFE2, "household_id": HH, "role": "admin", "financial_role": "spouse", "display_name": "Mona"})
    family.tables["household_memberships"].append(
        {"user_id": WIFE2, "financial_role": "spouse", "household_id": HH, "role": "admin", "created_at": "2026-01-05T00:00:00+00:00"})
    family.tables["accounts"].append(
        {"id": WIFE2_ACCOUNT, "household_id": HH, "owner_user_id": WIFE2, "is_shared_pool": False, "is_archived": False, "currency": "SAR"})
    return family


@pytest.fixture()
def demoted(family):
    """The co-admin paid her and a former member from his own account, then lost his admin rights."""
    family.tables["accounts"].append(
        {"id": COADMIN_ACCOUNT, "household_id": HH, "owner_user_id": COADMIN, "is_shared_pool": False, "is_archived": False, "currency": "SAR"})
    family.tables["account_transfers"] += [
        {"id": T_COADMIN, "household_id": HH, "from_account_id": COADMIN_ACCOUNT, "to_account_id": None, "amount": 15.0},
        {"id": T_FMD_COADMIN, "household_id": HH, "from_account_id": COADMIN_ACCOUNT, "to_account_id": None, "amount": 5.0},
    ]
    family.tables["spouse_reimbursements"].append(
        {"id": R_COADMIN, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": COADMIN, "amount": 15.0,
         "payment_method": "cash", "notes": None, "recorded_by": COADMIN, "created_at": "2026-11-16T10:00:00+00:00",
         "transfer_id": T_COADMIN, "kind": "payment", "reverses_id": None})
    family.tables["former_member_debt_events"].append(
        {"id": E_COADMIN, "debt_id": DEBT, "kind": "payment", "amount": 5.0, "payment_method": "cash",
         "remaining_after": 95.0, "recorded_by": COADMIN, "request_key": KEY, "created_at": "2026-11-08T10:00:00+00:00",
         "transfer_id": T_FMD_COADMIN})
    for m in family.tables["household_memberships"]:
        if m["user_id"] == COADMIN:
            m["role"] = "member"
    return family


R_POOL2 = "b9000000-0000-4000-8000-0000000000ee"
T_POOL2 = "b6000000-0000-4000-8000-0000000000ee"


def _pool_repayment(fake):
    """A repayment from the shared pool, not reversed."""
    fake.tables["account_transfers"].append(
        {"id": T_POOL2, "household_id": HH, "from_account_id": POOL, "to_account_id": None, "amount": 12.0})
    fake.tables["spouse_reimbursements"].append(
        {"id": R_POOL2, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 12.0,
         "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-17T10:00:00+00:00",
         "transfer_id": T_POOL2, "kind": "payment", "reverses_id": None})


def _reverse(user, row=R_NEW):
    return client.post(f"/households/{HH}/nafaqah/reimbursements/{row}/reversal", headers=bearer(user), json={"request_key": KEY})


def _fmd(path, user, **body):
    return client.post(f"/households/{HH}/nafaqah/former-member-debts/{path}", headers=bearer(user), json=body)


# ─── R1-01: a wife never pays, approves, declines or reverses ─────────────────

def test_r1_01_a_wife_admin_cannot_repay_her_co_wife_from_a_pool_or_her_own_account(co_wife):
    for account in (POOL, WIFE2_ACCOUNT):
        resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE2), json={
            "amount": 10, "payment_method": "cash", "wife_user_id": WIFE, "account_id": account, "request_key": KEY})
        assert resp.status_code == 403, resp.text
    assert _calls(co_wife, "record_spouse_reimbursement") == []


def test_r1_01_a_wife_admin_neither_approves_nor_declines_her_co_wifes_request(co_wife):
    base = f"/households/{HH}/nafaqah/reimbursement-requests/{Q_PENDING}"
    assert client.post(f"{base}/approve", headers=bearer(WIFE2), json={"account_id": POOL, "request_key": KEY}).status_code == 403
    assert client.post(f"{base}/decline", headers=bearer(WIFE2), json={"reason": "no"}).status_code == 403
    assert _calls(co_wife, "approve_spouse_reimbursement_request") == _calls(co_wife, "decline_spouse_reimbursement_request") == []


def test_r1_01_a_wife_admin_neither_pays_nor_waives_nor_reverses_a_former_members_record(co_wife):
    assert _fmd(f"{DEBT}/payments", WIFE2, amount=10, payment_method="cash", request_key=KEY, account_id=POOL).status_code == 403
    assert _fmd(f"{DEBT}/waiver", WIFE2, request_key=KEY).status_code == 403
    assert _fmd(f"{DEBT}/payments/{E_TRACKED}/reversal", WIFE2, request_key=KEY).status_code == 403
    assert _calls(co_wife, "record_former_member_debt_payment") == _calls(co_wife, "waive_former_member_debt") == []
    assert _calls(co_wife, "reverse_former_member_debt_payment") == []


def test_r1_01_a_wife_admin_reverses_no_pool_repayment(co_wife):
    _pool_repayment(co_wife)
    assert _reverse(WIFE2, R_POOL2).status_code == 403
    assert _calls(co_wife, "reverse_spouse_reimbursement") == []


def test_r1_01_a_wife_reverses_nothing_even_where_no_account_is_checked(co_wife):
    """A row with no transfer has no account to check: she is refused as a wife, before the database."""
    legacy = "b9000000-0000-4000-8000-0000000000ab"
    co_wife.tables["spouse_reimbursements"].append(
        {"id": legacy, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 5.0,
         "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-01T10:00:00+00:00"})
    for caller in (WIFE, WIFE2):
        resp = _reverse(caller, legacy)
        assert resp.status_code == 403, (caller, resp.text)
    assert _calls(co_wife, "reverse_spouse_reimbursement") == []


def test_r1_01_the_summary_offers_a_wife_admin_nothing_to_decide(co_wife):
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(WIFE2)).json()
    assert body["can_record_reimbursement"] is False
    assert body["can_manage_former_member_debts"] is False
    assert all(w["can_decide"] is False for w in body["wives"])
    assert not any(e["can_reverse"] for d in body["former_member_debts"] for e in d["events"])
    # Her co-wife's ledger is not hers to read at all (review R3-01); her own offers no reversal.
    assert client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE2), params={"wife_user_id": WIFE}).status_code == 403
    history = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE2)).json()["history"]
    assert not any(h.get("can_reverse") for h in history)


def test_r1_01_a_pool_is_never_a_wifes_to_pay_from(co_wife):
    ctx = ns.load_family_context(HH)
    pool = next(a for a in co_wife.tables["accounts"] if a["id"] == POOL)
    assert ns._account_usable_by(ctx, pool, WIFE2) is False
    assert ns._account_usable_by(ctx, pool, COADMIN) is True
    assert ns.can_record_reimbursement(ctx, WIFE2) is False
    assert ns.can_record_reimbursement(ctx, WIFE2, WIFE) is False
    assert ns.can_manage_former_member_debts(ctx, WIFE2) is False


# ─── R1-02: a retry reaches the database's replay ─────────────────────────────

def _replay_payment(amount, remaining, status):
    return lambda p: {"success": True, "replayed": True, "event_id": "e-first", "debt_id": p["p_debt_id"],
                      "amount": amount, "payment_method": "bank_transfer", "remaining": remaining, "status": status,
                      "account_id": ACCOUNT}


def test_r1_02_a_settled_records_payment_replays(family):
    debt = next(d for d in family.tables["former_member_debts"] if d["id"] == DEBT)
    debt.update(paid_amount=170.0, status="settled", closed_at="2026-11-09T10:00:00+00:00")
    family.rpc_handlers["record_former_member_debt_payment"] = _replay_payment(100.0, 0.0, "settled")
    resp = _fmd(f"{DEBT}/payments", HUSBAND, amount=100, payment_method="bank_transfer", request_key=KEY, account_id=ACCOUNT)
    assert resp.status_code == 200, resp.text
    assert (resp.json()["replayed"], resp.json()["amount"], resp.json()["status"]) == (True, 100.0, "settled")
    assert len(_calls(family, "record_former_member_debt_payment")) == 1


def test_r1_02_a_partial_replay_larger_than_what_remains_now(family):
    debt = next(d for d in family.tables["former_member_debts"] if d["id"] == DEBT)
    debt.update(paid_amount=150.0)  # 80 of the 100 went through; 20 remain now
    family.rpc_handlers["record_former_member_debt_payment"] = _replay_payment(80.0, 20.0, "open")
    resp = _fmd(f"{DEBT}/payments", HUSBAND, amount=80, payment_method="bank_transfer", request_key=KEY, account_id=ACCOUNT)
    assert resp.status_code == 200, resp.text
    assert (resp.json()["replayed"], resp.json()["amount"], resp.json()["remaining"]) == (True, 80.0, 20.0)


def test_r1_02_a_waiver_replays(family):
    family.rpc_handlers["waive_former_member_debt"] = lambda p: {
        "success": True, "replayed": True, "event_id": "e-w", "debt_id": p["p_debt_id"], "waived_amount": 15.0,
        "remaining": 0.0, "status": "waived"}
    resp = _fmd(f"{DEBT_WAIVED}/waiver", HUSBAND, request_key=KEY)
    assert resp.status_code == 200, resp.text
    assert (resp.json()["replayed"], resp.json()["status"]) == (True, "waived")


@pytest.mark.parametrize("hint, code, status_code", [
    ("debt_closed", "22023", 409), ("overpayment", "22023", 409), ("debt_not_found", "P0002", 404),
    ("request_key_reused", "22023", 409),
])
def test_r1_02_the_database_decides_closed_overpaid_and_unknown(family, hint, code, status_code):
    def refuse(_p):
        raise db_error(hint, code=code, details="20.00")

    family.rpc_handlers["record_former_member_debt_payment"] = refuse
    resp = _fmd(f"{DEBT}/payments", HUSBAND, amount=30, payment_method="cash", request_key=KEY, account_id=ACCOUNT)
    assert resp.status_code == status_code and resp.json()["detail"]["code"] == hint
    if hint == "overpayment":
        assert resp.json()["detail"]["outstanding"] == 20.0


# ─── R1-04: a key reused for something else ────────────────────────────────────

@pytest.mark.parametrize("rpc, call", [
    ("record_spouse_reimbursement", lambda: client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND), json={
        "amount": 20, "payment_method": "cash", "account_id": ACCOUNT, "request_key": KEY})),
    ("approve_spouse_reimbursement_request", lambda: client.post(
        f"/households/{HH}/nafaqah/reimbursement-requests/{Q_PENDING}/approve", headers=bearer(HUSBAND),
        json={"account_id": ACCOUNT, "request_key": KEY})),
    ("reverse_spouse_reimbursement", lambda: _reverse(HUSBAND)),
    ("waive_former_member_debt", lambda: _fmd(f"{DEBT}/waiver", HUSBAND, request_key=KEY)),
    ("reverse_former_member_debt_payment", lambda: _fmd(f"{DEBT}/payments/{E_TRACKED}/reversal", HUSBAND, request_key=KEY)),
])
def test_r1_04_a_reused_key_is_a_conflict_with_its_code(family, rpc, call):
    def refuse(_p):
        raise db_error("request_key_reused")

    family.rpc_handlers[rpc] = refuse
    resp = call()
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "request_key_reused"


# ─── R1-07: reversal by the account's owner, whatever his role now ─────────────

def test_r1_07_a_former_co_admin_reverses_his_own_repayment(demoted):
    resp = _reverse(COADMIN, R_COADMIN)
    assert resp.status_code == 200, resp.text
    assert [p["p_actor_user_id"] for p in _calls(demoted, "reverse_spouse_reimbursement")] == [COADMIN]
    # He reads none of her ledger while the husband is there (review R3-01); the reversal of his
    # own account's repayment stays his (R1-07), the husband's account stays the husband's.
    assert client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COADMIN)).status_code == 403
    ctx = ns.load_family_context(HH)
    accounts = {a["id"]: a for a in demoted.tables["accounts"]}
    own = next(a for a in demoted.tables["accounts"] if a.get("owner_user_id") == COADMIN and not a.get("is_shared_pool"))
    assert ns.can_reverse_repayment(ctx, COADMIN, own) is True
    assert ns.can_reverse_repayment(ctx, COADMIN, accounts[ACCOUNT]) is False, "the husband's account is his"


def test_r1_07_a_former_co_admin_reverses_his_own_former_member_payment(demoted):
    resp = _fmd(f"{DEBT}/payments/{E_COADMIN}/reversal", COADMIN, request_key=KEY)
    assert resp.status_code == 200, resp.text
    # The record is the husband's to read (review R3-01); the husband sees which he may reverse.
    assert client.get(f"/households/{HH}/nafaqah", headers=bearer(COADMIN)).json()["former_member_debts"] == []
    debts = {d["id"]: d for d in client.get(f"/households/{HH}/nafaqah", headers=bearer(HUSBAND)).json()["former_member_debts"]}
    events = {e["id"]: e for e in debts[DEBT]["events"]}
    assert events[E_COADMIN]["can_reverse"] is False, "C's account is C's"
    assert events[E_TRACKED]["can_reverse"] is True


def test_r1_07_a_former_husband_reverses_his_own_repayment(family):
    for m in family.tables["household_memberships"]:
        if m["user_id"] == HUSBAND:
            m["role"] = "member"
    family.tables["households"][0].update(owner_user_id=COADMIN, nafaqah_provider_user_id=CHILD)
    assert _reverse(HUSBAND).status_code == 200
    assert [p["p_actor_user_id"] for p in _calls(family, "reverse_spouse_reimbursement")] == [HUSBAND]


def test_r1_07_a_member_cannot_reverse_another_members_account(family):
    resp = _reverse(CHILD)
    assert resp.status_code == 403 and resp.json()["detail"]["code"] == "account_forbidden"
    assert _calls(family, "reverse_spouse_reimbursement") == []


def test_r1_07_an_admin_who_is_not_a_wife_reverses_a_pool_repayment_once_the_husband_is_gone(family):
    """Review R3-01: a pool's repayment is the husband's (an admin) to reverse; an admin's once he
    is gone."""
    _pool_repayment(family)
    assert _reverse(COADMIN, R_POOL2).status_code == 403
    assert _calls(family, "reverse_spouse_reimbursement") == []
    husband_leaves(family)
    history = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COADMIN)).json()["history"]
    assert {h["id"]: h for h in history if h["type"] == "reimbursement"}[R_POOL2]["can_reverse"] is True
    assert _reverse(COADMIN, R_POOL2).status_code == 200


# ─── R1-08: the history names who paid ─────────────────────────────────────────

def test_r1_08_the_history_names_who_paid(demoted):
    history = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND)).json()["history"]
    rows = {h["id"]: h for h in history if h["type"] == "reimbursement"}
    assert rows[R_COADMIN]["paid_by_user_id"] == COADMIN
    assert rows[R_NEW]["paid_by_user_id"] == HUSBAND


def test_r1_08_the_answer_names_who_paid_never_assumes_the_husband(family):
    husband_leaves(family)  # an admin pays once the husband is gone (review R3-01)
    family.rpc_handlers["record_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": False, "reimbursement_id": "r-x", "amount": 20.0, "payment_method": "cash",
        "account_id": POOL, "paid_by_user_id": COADMIN, "outstanding_before": 225.0, "outstanding_after": 205.0}
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COADMIN), json={
        "amount": 20, "payment_method": "cash", "account_id": POOL, "request_key": KEY})
    assert resp.status_code == 200 and resp.json()["paid_by_user_id"] == COADMIN
    family.rpc_handlers["record_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": False, "reimbursement_id": "r-y", "amount": 20.0, "payment_method": "cash",
        "account_id": POOL, "outstanding_before": 225.0, "outstanding_after": 205.0}
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COADMIN), json={
        "amount": 20, "payment_method": "cash", "account_id": POOL, "request_key": KEY})
    assert resp.json()["paid_by_user_id"] != HUSBAND


# ─── R1-03: a request closed because it no longer fits ─────────────────────────

def test_r1_03_an_already_repaid_request_is_shown_and_not_pending(family):
    family.tables["spouse_reimbursement_request_outcomes"].append(
        {"request_id": Q_PENDING, "outcome": "already_repaid", "reason": None, "reimbursement_id": None,
         "decided_by": None, "created_at": "2026-11-16T12:00:00+00:00"})
    body = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE)).json()
    assert {q["id"]: q["status"] for q in body["requests"]}[Q_PENDING] == "already_repaid"
    assert (body["balance"]["pending_requested"], body["balance"]["pending_count"]) == (0.0, 0)


# ─── R1-10: the former-member routes are a family's ────────────────────────────

@pytest.mark.parametrize("path, body", [
    (f"{DEBT}/payments", {"amount": 10, "payment_method": "cash", "request_key": KEY, "account_id": ACCOUNT}),
    (f"{DEBT}/waiver", {"request_key": KEY}),
    (f"{DEBT}/payments/{E_TRACKED}/reversal", {"request_key": KEY}),
])
def test_r1_10_former_member_routes_refuse_a_roommates_household(family, path, body):
    resp = client.post(f"/households/{HH_ROOM}/nafaqah/former-member-debts/{path}", headers=bearer(PEER1), json=body)
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "not_family"
    assert not any(n.endswith("former_member_debt_payment") or n == "waive_former_member_debt" for n, _ in family.rpc_calls)


# ─── R1-09: the decline reason counts Unicode code points ──────────────────────

def test_r1_09_the_decline_reason_is_counted_in_code_points(family):
    base = f"/households/{HH}/nafaqah/reimbursement-requests/{Q_PENDING}/decline"
    marked = "بِ" * 100  # 100 letters with a kasra each: 200 code points, 100 graphemes
    assert len(marked) == 200
    assert client.post(base, headers=bearer(HUSBAND), json={"reason": marked}).status_code == 200
    resp = client.post(base, headers=bearer(HUSBAND), json={"reason": marked + "ب"})
    assert resp.status_code == 422
