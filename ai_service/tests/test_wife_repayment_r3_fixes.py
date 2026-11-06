"""
Round 3 review fixes of tracked repayments (owner decisions 2026-11-06), at the API.

R3-01: who sees and who acts on a wife's repayment ledger (what is owed, her advances' balance,
repayments, reversals, her requests, their outcomes, decline reasons and notes) and on a former
member's record. Normally only two people see her ledger: she herself and her husband (the
household's Nafaqah provider while he is a member who is not a wife). Only he records, approves,
declines and reverses; she only makes and cancels her own requests. When he is gone (he left or
his account was deleted: no current provider), an admin who is not a wife sees and settles it. A
wife never sees or acts for a co-wife, even as an admin; an ordinary member never. The former
member's record follows the same rule (her husband; an admin who is not a wife when he is gone).

The matrix: callers (the wife, her husband, a co-wife, an ordinary member, an admin who is not a
wife, a wife who is an admin) x (husband present, husband gone), for every read route and every
action. The database (test 62) enforces the same; here its RPCs are stand-ins and the API's own
gate is what is tested.
"""

from __future__ import annotations

import pytest

import nafaqah_service as ns
from test_wife_repayment_debit import (  # noqa: F401  (pytest fixture)
    ACCOUNT,
    CHILD,
    COADMIN,
    DEBT,
    E_TRACKED,
    HH,
    HUSBAND,
    KEY,
    POOL,
    Q_DECLINED,
    Q_PENDING,
    R_NEW,
    WIFE,
    bearer,
    client,
    family,
)

COWIFE = "b2000000-0000-4000-8000-00000000000e"
WIFE_ADMIN = "b2000000-0000-4000-8000-00000000000f"
COWIFE_REQUEST = "b7000000-0000-4000-8000-0000000000c1"
R_POOL = "b9000000-0000-4000-8000-0000000000c2"
T_POOL2 = "b6000000-0000-4000-8000-0000000000c3"

CALLERS = {
    "wife": WIFE,
    "husband": HUSBAND,
    "co-wife": COWIFE,
    "member": CHILD,
    "admin": COADMIN,
    "wife-admin": WIFE_ADMIN,
}


@pytest.fixture(params=["present", "gone"])
def household(request, family):
    """The family of test_wife_repayment_debit with a co-wife and a wife who is an admin. 'gone':
    the husband left the household (his membership ended, which clears the provider)."""
    family.tables["users"].extend([
        {"id": COWIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Huda"},
        {"id": WIFE_ADMIN, "household_id": HH, "role": "admin", "financial_role": "spouse", "display_name": "Mona"},
    ])
    family.tables["household_memberships"].extend([
        {"user_id": COWIFE, "financial_role": "spouse", "household_id": HH, "role": "member",
         "created_at": "2026-01-05T00:00:00+00:00"},
        {"user_id": WIFE_ADMIN, "financial_role": "spouse", "household_id": HH, "role": "admin",
         "created_at": "2026-01-06T00:00:00+00:00"},
    ])
    family.tables["transactions"].append(
        {"id": "t-cowife", "household_id": HH, "amount": 100.0, "merchant": "Tamimi", "timestamp": "2026-11-10T10:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": COWIFE})
    # A repayment from the pool by the husband (an admin), not reversed.
    family.tables["spouse_reimbursements"].append(
        {"id": R_POOL, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 15.0,
         "payment_method": "cash", "notes": "for the groceries", "recorded_by": HUSBAND,
         "created_at": "2026-11-15T09:00:00+00:00", "transfer_id": T_POOL2, "kind": "payment", "reverses_id": None})
    family.tables["account_transfers"].append(
        {"id": T_POOL2, "household_id": HH, "from_account_id": POOL, "to_account_id": None, "amount": 15.0})
    family.tables["spouse_reimbursement_requests"].append(
        {"id": COWIFE_REQUEST, "household_id": HH, "wife_user_id": COWIFE, "amount": 20.0, "payment_method": "cash",
         "created_at": "2026-11-16T10:00:00+00:00"})
    if request.param == "gone":
        family.tables["household_memberships"][:] = [
            m for m in family.tables["household_memberships"] if m["user_id"] != HUSBAND]
        for h in family.tables["households"]:
            if h["id"] == HH:
                h["nafaqah_provider_user_id"] = None
                h["owner_user_id"] = COADMIN
    family.state = request.param
    return family


def _viewers(state):
    """Who reads the wife's ledger: she and her husband; with him gone, she and the admin."""
    return {"wife", "husband"} if state == "present" else {"wife", "admin"}


def _managers(state):
    """Who acts on it (and reads and closes the former member's record)."""
    return {"husband"} if state == "present" else {"admin"}


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


# ─── Reads ────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_her_ledger_is_read_by_her_and_her_husband_only(household, who):
    """GET .../reimbursements and .../reimbursement-requests naming her: 403 for anyone else, so no
    co-wife or member reads her history, notes, requests or the husband's decline reason."""
    caller = CALLERS[who]
    ledger = client.get(f"/households/{HH}/nafaqah/reimbursements", params={"wife_user_id": WIFE}, headers=bearer(caller))
    requests = client.get(f"/households/{HH}/nafaqah/reimbursement-requests", params={"wife_user_id": WIFE},
                          headers=bearer(caller))
    if who in _viewers(household.state):
        assert ledger.status_code == 200, ledger.text
        assert requests.status_code == 200, requests.text
        assert any(q.get("reason") == "Not received yet" for q in requests.json()["requests"])
    else:
        assert ledger.status_code == 403, (ledger.status_code, ledger.text[:200])
        assert requests.status_code == 403, (requests.status_code, requests.text[:200])
        assert "Not received yet" not in ledger.text + requests.text


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_without_naming_her_a_wife_reads_her_own_and_nobody_else_guesses(household, who):
    """Without wife_user_id: a wife gets her own ledger; the managers must name one (several
    wives); anyone else is refused."""
    caller = CALLERS[who]
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(caller))
    if who in ("wife", "co-wife", "wife-admin"):
        assert resp.status_code == 200, resp.text
        assert resp.json()["wife_user_id"] == caller
    elif who in _managers(household.state):
        assert resp.status_code == 422, resp.text
    else:
        assert resp.status_code == 403, resp.text


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_the_summary_lists_only_the_wives_whose_ledger_the_caller_sees(household, who):
    """wives[]: a wife sees only her own entry; the managers every wife; nobody else any entry.
    former_member_debts: the managers only."""
    caller = CALLERS[who]
    resp = client.get(f"/households/{HH}/nafaqah", headers=bearer(caller))
    if who == "husband" and household.state == "gone":
        assert resp.status_code == 403, "he is no longer a member"
        return
    body = resp.json()
    ids = sorted(w["id"] for w in body["wives"])
    if who in ("wife", "co-wife", "wife-admin"):
        assert ids == [caller]
    elif who in _managers(household.state):
        assert ids == sorted([WIFE, COWIFE, WIFE_ADMIN])
    else:
        assert ids == []
    for w in body["wives"]:
        assert "reimbursement" in w and "requests" in w
    if who in _managers(household.state):
        assert body["can_manage_former_member_debts"] is True
        assert {d["id"] for d in body["former_member_debts"]} == {DEBT, "b3000000-0000-4000-8000-000000000002"}
    else:
        assert body["can_manage_former_member_debts"] is False
        assert body["former_member_debts"] == []
    assert body["can_record_reimbursement"] is (who in _managers(household.state))
    text = str(body)
    if who not in _viewers(household.state) and who != "wife":
        assert "Not received yet" not in text and Q_PENDING not in text


def test_r3_01_an_admin_still_sets_the_allowance_while_the_husband_is_there(household):
    """Her allowance is not her repayment ledger: the admins still set it (rule 04). While the
    husband is there an admin gets it in allowance_wives, without any of her ledger."""
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(COADMIN)).json()
    assert body["can_set_allowance"] is True
    if household.state == "present":
        assert body["wives"] == []
        allowance_ids = sorted(w["id"] for w in body["allowance_wives"])
        assert allowance_ids == sorted([WIFE, COWIFE, WIFE_ADMIN])
        for w in body["allowance_wives"]:
            assert set(w) == {"id", "display_name", "allowance"}, w
    else:
        assert body["allowance_wives"] == []
    for who in ("co-wife", "member", "wife"):
        other = client.get(f"/households/{HH}/nafaqah", headers=bearer(CALLERS[who])).json()
        assert other["allowance_wives"] == []


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_the_settlement_totals_only_what_the_caller_may_see(household, who):
    """GET .../settlement and .../settlement-v2: the Nafaqah totals are the caller's own (a wife),
    every wife's (the managers), or none (anyone else)."""
    caller = CALLERS[who]
    v1 = client.get(f"/households/{HH}/settlement", headers=bearer(caller))
    v2 = client.get(f"/households/{HH}/settlement-v2", headers=bearer(caller))
    if who == "husband" and household.state == "gone":
        assert (v1.status_code, v2.status_code) == (403, 403), "he is no longer a member"
        return
    assert v1.status_code == 200, v1.text
    assert v2.status_code == 200, v2.text
    nafaqah = v1.json()["nafaqah"]
    family_summary = v2.json()["family_summary"]
    if who == "wife":
        assert nafaqah["outstanding"] == 210.0
        assert family_summary["wife_reimbursement_owed"] == 210.0
    elif who == "co-wife":
        assert nafaqah["outstanding"] == 100.0
        assert family_summary["wife_reimbursement_owed"] == 100.0
    elif who == "wife-admin":
        # Her own ledger only (nothing advanced), never her co-wives'.
        assert nafaqah["outstanding"] == 0.0
        assert family_summary["wife_reimbursement_owed"] == 0.0
    elif who in _managers(household.state):
        assert nafaqah["outstanding"] == 310.0
        assert family_summary["wife_reimbursement_owed"] == 310.0
    else:
        assert nafaqah is None
        assert family_summary["wife_reimbursement_owed"] is None
        assert family_summary["reimbursed_total"] is None
        assert v1.json()["owed_to_partner"] == 0 and v1.json()["owed_to_me"] == 0


# ─── Actions ──────────────────────────────────────────────────────────────────

def _account_for(who):
    """The account each caller would pay from: the husband his own, everyone else the pool."""
    return ACCOUNT if who == "husband" else POOL


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_only_her_husband_records_a_repayment_and_an_admin_once_he_is_gone(household, who):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(CALLERS[who]),
                       json={"amount": 10, "payment_method": "cash", "wife_user_id": WIFE,
                             "account_id": _account_for(who), "request_key": KEY})
    if who in _managers(household.state):
        assert resp.status_code == 200, resp.text
        assert _calls(household, "record_spouse_reimbursement")
    else:
        assert resp.status_code == 403, resp.text
        assert _calls(household, "record_spouse_reimbursement") == []


@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("action", ["approve", "decline"])
def test_r3_01_only_her_husband_decides_her_request_and_an_admin_once_he_is_gone(household, who, action):
    body = {"account_id": _account_for(who), "request_key": KEY} if action == "approve" else {"reason": "no"}
    resp = client.post(f"/households/{HH}/nafaqah/reimbursement-requests/{Q_PENDING}/{action}",
                       headers=bearer(CALLERS[who]), json=body)
    rpc = f"{action}_spouse_reimbursement_request"
    if who in _managers(household.state):
        assert resp.status_code == 200, resp.text
        assert _calls(household, rpc)
    else:
        assert resp.status_code == 403, resp.text
        assert _calls(household, rpc) == []


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_a_pool_repayment_is_reversed_by_the_husband_if_admin_or_an_admin_once_he_is_gone(household, who):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_POOL}/reversal", headers=bearer(CALLERS[who]),
                       json={"request_key": KEY})
    if who in _managers(household.state):
        assert resp.status_code == 200, resp.text
    else:
        assert resp.status_code == 403, resp.text
        assert _calls(household, "reverse_spouse_reimbursement") == []


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_a_personal_repayment_stays_its_owners_to_reverse(household, who):
    """R1-07 kept: his own account's repayment is his, while he is a member; never an admin's."""
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_NEW}/reversal", headers=bearer(CALLERS[who]),
                       json={"request_key": KEY})
    if who == "husband" and household.state == "present":
        assert resp.status_code == 200, resp.text
    else:
        assert resp.status_code == 403, resp.text


@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("action", ["payments", "waiver"])
def test_r3_01_the_former_member_record_is_closed_by_her_husband_or_an_admin_once_he_is_gone(household, who, action):
    body = ({"amount": 10, "payment_method": "cash", "request_key": KEY, "account_id": _account_for(who)}
            if action == "payments" else {"request_key": KEY})
    resp = client.post(f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/{action}", headers=bearer(CALLERS[who]),
                       json=body)
    rpc = "record_former_member_debt_payment" if action == "payments" else "waive_former_member_debt"
    if who in _managers(household.state):
        assert resp.status_code == 200, resp.text
    else:
        assert resp.status_code == 403, resp.text
        assert _calls(household, rpc) == []


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3_01_her_requests_are_hers(household, who):
    """She makes and cancels her own; nobody else cancels hers or asks for her."""
    cancel = client.post(f"/households/{HH}/nafaqah/reimbursement-requests/{Q_PENDING}/cancel",
                         headers=bearer(CALLERS[who]))
    assert cancel.status_code == (200 if who == "wife" else 403), cancel.text
    ask = client.post(f"/households/{HH}/nafaqah/reimbursement-requests", headers=bearer(CALLERS[who]),
                      json={"amount": 5, "payment_method": "cash", "request_key": KEY})
    assert ask.status_code == (200 if who in ("wife", "co-wife", "wife-admin") else 403), ask.text


@pytest.mark.parametrize("who", ["co-wife", "wife-admin"])
def test_r3_01_a_wife_never_names_a_co_wife(household, who):
    """resolve_wife_id: a wife resolves herself only, for her ledger and her allowance too."""
    for path in ("reimbursements", "reimbursement-requests", "allowance"):
        resp = client.get(f"/households/{HH}/nafaqah/{path}", params={"wife_user_id": WIFE}, headers=bearer(CALLERS[who]))
        assert resp.status_code == 403, (path, resp.status_code, resp.text[:200])


# ─── The shared definition ────────────────────────────────────────────────────

def test_r3_01_one_definition_of_her_husband_and_of_him_gone(household):
    ctx = ns.load_family_context(HH)
    if household.state == "present":
        assert ctx.ledger_husband_id == HUSBAND and ctx.husband_gone is False
        assert ns.can_manage_wife_ledgers(ctx, HUSBAND) and not ns.can_manage_wife_ledgers(ctx, COADMIN)
    else:
        assert ctx.ledger_husband_id is None and ctx.husband_gone is True
        assert ns.can_manage_wife_ledgers(ctx, COADMIN) and not ns.can_manage_wife_ledgers(ctx, HUSBAND)
    for wife in (WIFE, COWIFE, WIFE_ADMIN, CHILD):
        assert not ns.can_manage_wife_ledgers(ctx, wife)
    assert ns.can_view_wife_ledger(ctx, WIFE, WIFE) and not ns.can_view_wife_ledger(ctx, COWIFE, WIFE)
    assert not ns.can_view_wife_ledger(ctx, WIFE_ADMIN, WIFE)


def test_r3_01_a_provider_who_is_a_wife_is_never_her_husband(household):
    for h in household.tables["households"]:
        if h["id"] == HH:
            h["nafaqah_provider_user_id"] = WIFE_ADMIN
    ctx = ns.load_family_context(HH)
    assert ctx.ledger_husband_id is None and ctx.husband_gone is True
    assert not ns.can_manage_wife_ledgers(ctx, WIFE_ADMIN)


def test_r3_01_the_decline_reason_is_not_in_a_co_wifes_answer(household):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(COWIFE))
    assert resp.status_code == 200
    assert Q_DECLINED not in resp.text and "Not received yet" not in resp.text
    assert {q["id"] for q in resp.json()["requests"]} == {COWIFE_REQUEST}
