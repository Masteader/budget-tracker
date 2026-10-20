"""
Scenario 3: Islamic Nafaqah end to end. A wife-paid shared expense is a debt the husband owes her;
partial and full reimbursement; overpayment → 409 (API and database); the wife's personal spend is
charged to her allowance (spent/remaining); she cannot set her own allowance; the settlement
endpoints in family mode reflect the ledger and never split 50/50. Also the roommate settlement
paths that share these endpoints.
"""

from __future__ import annotations

import pytest


def _ledger(user, hh):
    res = user.api.get(f"/households/{hh.id}/nafaqah/reimbursements")
    assert res.status_code == 200, res.text
    return res.json()


def test_wife_advance_partial_full_and_overpayment(world, db, llm):
    hh = world.family("N1")
    husband, wife = hh.admin, hh.members[0]

    # Wife pays 300 for the household (shared) and 45.50 for groceries: both her advances.
    for merchant, amount in (("Carrefour Family Shop", 300), ("Tamimi Markets", 45.5)):
        res = world.chat_commit(wife, hh, llm, merchant=merchant, amount=amount, category_code="OPEX-GROCERY",
                                paid_by="me", beneficiary="both")
        assert res.status_code == 200 and res.json()["nafaqah_class"] == "wife_reimbursable", res.text
    # The husband's own spending creates no debt.
    res = world.chat_commit(husband, hh, llm, merchant="Danube", amount=500, category_code="OPEX-GROCERY")
    assert res.json()["nafaqah_class"] is None

    ledger = _ledger(husband, hh)
    assert ledger["wife_user_id"] == wife.id and ledger["husband_user_id"] == husband.id
    assert ledger["balance"] == {"gross_advanced": 345.5, "reimbursed": 0.0, "outstanding": 345.5, "overpaid": 0.0}
    # The wife sees the same balance (husband owes her).
    assert _ledger(wife, hh)["balance"]["outstanding"] == 345.5

    # Partial repayment by the husband.
    part = husband.api.post(f"/households/{hh.id}/nafaqah/reimbursements",
                            json={"amount": 100.25, "payment_method": "stc_pay", "notes": "part 1"})
    assert part.status_code == 200, part.text
    assert part.json()["outstanding_before"] == 345.5 and part.json()["outstanding_after"] == 245.25

    # Overpayment is refused with 409 and the outstanding amount, and nothing is recorded.
    over = husband.api.post(f"/households/{hh.id}/nafaqah/reimbursements", json={"amount": 245.26})
    assert over.status_code == 409, over.text
    assert over.json()["detail"]["code"] == "overpayment" and over.json()["detail"]["outstanding"] == 245.25
    # The database re-checks overpayment independently of the API (direct PostgREST RPC).
    direct = husband.rpc("record_spouse_reimbursement", {
        "p_household_id": hh.id, "p_wife_user_id": wife.id, "p_amount": "245.26",
        "p_payment_method": "cash", "p_notes": None, "p_actor_user_id": husband.id,
    })
    assert direct.status_code >= 400 and "outstanding" in direct.text.lower(), direct.text
    assert db.scalar("SELECT count(*) FROM public.spouse_reimbursements WHERE household_id = %s", (hh.id,)) == 1

    # The generic reimbursement endpoint routes family repayments to the same ledger.
    full = husband.api.post(f"/households/{hh.id}/reimbursements", json={
        "household_id": hh.id, "payer_id": husband.id, "recipient_id": wife.id, "amount": 245.25,
        "payment_method": "cash",
    })
    assert full.status_code == 200, full.text
    assert full.json()["mode"] == "family_nafaqah" and full.json()["outstanding_after"] == 0.0
    assert _ledger(wife, hh)["balance"] == {"gross_advanced": 345.5, "reimbursed": 345.5, "outstanding": 0.0,
                                            "overpaid": 0.0}
    # Settled: any further repayment is an overpayment, also through the generic endpoint.
    again = husband.api.post(f"/households/{hh.id}/reimbursements", json={
        "household_id": hh.id, "payer_id": husband.id, "recipient_id": wife.id, "amount": 0.01})
    assert again.status_code == 409
    # A "wife pays husband" settlement does not exist in a family.
    reverse = wife.api.post(f"/households/{hh.id}/reimbursements", json={
        "household_id": hh.id, "payer_id": wife.id, "recipient_id": husband.id, "amount": 10})
    assert reverse.status_code == 409
    history = _ledger(husband, hh)["history"]
    assert sorted(h["type"] for h in history) == ["advance", "advance", "reimbursement", "reimbursement"]


def test_wife_personal_allowance_spent_and_remaining(world, db, llm):
    hh = world.family("N2")
    husband, wife = hh.admin, hh.members[0]

    # Only the husband/admin sets it; the wife is refused via API and via the RPC directly.
    own = wife.api.put(f"/households/{hh.id}/nafaqah/allowance", json={"amount": 9999})
    assert own.status_code == 403, own.text
    direct = wife.rpc("set_member_allowance", {
        "p_household_id": hh.id, "p_member_user_id": wife.id, "p_amount": "9999", "p_cycle_key": None,
        "p_actor_user_id": wife.id,
    })
    assert direct.status_code >= 400, direct.text
    assert db.scalar("SELECT count(*) FROM public.member_allowances WHERE household_id = %s", (hh.id,)) == 0

    setres = husband.api.put(f"/households/{hh.id}/nafaqah/allowance", json={"amount": 500})
    assert setres.status_code == 200, setres.text
    cycle = setres.json()["cycle_key"]
    assert setres.json()["allocated"] == 500.0 and setres.json()["spent"] == 0.0

    # Wife's personal purchases (paid by her, for her) are charged to the allowance.
    for merchant, amount in (("Zara Riyadh Park", 120), ("Nahdi Pharmacy", 30.75)):
        res = world.chat_commit(wife, hh, llm, merchant=merchant, amount=amount, category_code="OPEX-SHOPPING",
                                paid_by="me", beneficiary="me")
        assert res.status_code == 200 and res.json()["nafaqah_class"] == "wife_personal", res.text
    # A shared advance is NOT allowance spending.
    world.chat_commit(wife, hh, llm, merchant="Lulu", amount=60, category_code="OPEX-GROCERY")

    allowance = wife.api.get(f"/households/{hh.id}/nafaqah/allowance").json()
    assert allowance["cycle_key"] == cycle
    assert (allowance["allocated"], allowance["spent"], allowance["remaining"]) == (500.0, 150.75, 349.25)
    assert allowance["transaction_count"] == 2

    # Overspend is reported, not blocked.
    world.chat_commit(wife, hh, llm, merchant="Abaya House", amount=400, category_code="OPEX-SHOPPING",
                      paid_by="me", beneficiary="me")
    allowance = husband.api.get(f"/households/{hh.id}/nafaqah/allowance").json()
    assert allowance["remaining"] == -50.75

    summary = wife.api.get(f"/households/{hh.id}/nafaqah").json()
    assert summary["caller_role"] == "wife" and summary["can_set_allowance"] is False
    assert summary["wives"][0]["reimbursement"]["outstanding"] == 60.0
    assert summary["wives"][0]["allowance"]["spent"] == 550.75


def test_family_settlement_reflects_ledger_never_fifty_fifty(world, db, llm):
    hh = world.family("N3")
    husband, wife = hh.admin, hh.members[0]
    world.chat_commit(wife, hh, llm, merchant="Othaim", amount=200, category_code="OPEX-GROCERY")
    world.chat_commit(husband, hh, llm, merchant="Panda", amount=1000, category_code="OPEX-GROCERY")
    husband.api.post(f"/households/{hh.id}/nafaqah/reimbursements", json={"amount": 50})

    # ?split_ratio is ignored for families; the debt is exactly the ledger outstanding (150).
    for user, expect_who in ((husband, "me_owes_partner"), (wife, "partner_owes_me")):
        res = user.api.get(f"/households/{hh.id}/settlement", params={"split_ratio": 0.5})
        assert res.status_code == 200, res.text
        s = res.json()
        assert s["mode"] == "family_nafaqah"
        assert s["settlement_amount"] == 150.0 and s["who_owes"] == expect_who
        assert s["nafaqah"]["outstanding"] == 150.0
        # No spousal split of the husband's 1000 or the wife's 200.
        assert s["settlement_amount"] not in (600.0, 400.0, 500.0, 100.0)

    v2 = husband.api.get(f"/households/{hh.id}/settlement-v2")
    assert v2.status_code == 200, v2.text
    fam = v2.json()["family_summary"]
    assert v2.json()["mode"] == "family_nafaqah"
    assert fam["wife_reimbursement_owed"] == 150.0 and fam["reimbursed_total"] == 50.0
    assert fam["gross_wife_advances"] == 200.0 and fam["status"] == "reimbursement_pending"


# ── Roommates (same endpoints, shared_split / multi_roommate modes) ─────────────

def test_roommate_settlement_reimbursement_is_recorded(world, db, llm):
    hh = world.roommates("N4", n_members=2)
    a, b = hh.members
    res = a.api.post(f"/households/{hh.id}/reimbursements", json={
        "household_id": hh.id, "payer_id": a.id, "recipient_id": b.id, "amount": 75, "payment_method": "stc_pay"})
    assert res.status_code == 200, res.text
    assert db.scalar("SELECT count(*) FROM public.transactions WHERE household_id = %s AND is_settlement", (hh.id,)) == 1


def test_roommate_settlement_permissions(world, db):
    hh = world.roommates("N5", n_members=2)
    a, b = hh.members
    # A third party (not payer, not recipient, not admin) cannot record someone else's settlement.
    res = b.api.post(f"/households/{hh.id}/reimbursements", json={
        "household_id": hh.id, "payer_id": a.id, "recipient_id": hh.admin.id, "amount": 10})
    assert res.status_code == 403, res.text


def test_roommate_multi_party_settlement_reports_debts(world, db, llm):
    hh = world.roommates("N6", n_members=2)
    payer = hh.members[0]
    res = world.chat_commit(payer, hh, llm, merchant="Electricity SEC", amount=300, category_code="OPEX-UTILITIES")
    assert res.status_code == 200, res.text
    v2 = payer.api.get(f"/households/{hh.id}/settlement-v2")
    assert v2.status_code == 200, v2.text
    body = v2.json()
    assert body["mode"] == "multi_roommate"
    owed_to_payer = sum(d["amount"] for d in body["simplified_debts"] if d["to_id"] == payer.id)
    assert owed_to_payer == 200.0
