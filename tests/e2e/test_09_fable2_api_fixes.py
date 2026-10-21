"""
Scenario 9: fixes for the second Fable review round (backend), proved on the real stack
(PostgREST 12 + Postgres 16 built from every migration): FABLE2-API-01..06, FABLE2-LOGIC-01, O4.
"""

from __future__ import annotations

import re
import uuid

from e2e_harness.zatca import tlv_qr

REPR = {"Prefer": "return=representation"}


def _debts(res):
    assert res.status_code == 200, res.text
    return sorted((d["from_id"], d["to_id"], float(d["amount"])) for d in res.json()["pairwise_debts"])


# ─── FABLE2-API-01: a family without a provider → 409 no_provider ─────────────

def test_api01_wife_chat_commit_without_provider_is_409_no_provider(world, db, llm):
    family = world.family("F9a1")
    wife = family.members[0]
    db.query("UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = %s", (family.id,))
    res = world.chat_commit(wife, family, llm, merchant="Panda", amount=300, category_code="OPEX-GROCERY",
                            paid_by="me", beneficiary="both")
    assert res.status_code == 409, res.text
    assert res.json()["detail"]["code"] == "no_provider" and res.json()["detail"]["message"]
    assert db.scalar("SELECT count(*) FROM public.transactions WHERE household_id = %s", (family.id,)) == 0


def test_api01_wife_receipt_commit_without_provider_is_409_no_provider(world, db):
    family = world.family("F9a1r")
    wife = family.members[0]
    db.query("UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = %s", (family.id,))
    qr = tlv_qr("Panda", "300000000000003", "2026-10-21T10:00:00Z", "300.00", "39.13")
    res = wife.api.post("/agent/scan-receipt", json={"household_id": family.id, "qr_code_raw": qr,
                                                     "paid_by": "me", "beneficiary": "both"})
    assert res.status_code == 409, res.text
    assert res.json()["detail"]["code"] == "no_provider"
    assert db.scalar("SELECT count(*) FROM public.transactions WHERE household_id = %s", (family.id,)) == 0


def test_api01_husband_expense_without_provider_is_still_recorded(world, db, llm):
    """No class, no provider needed: only classified wife expenses are refused."""
    family = world.family("F9a1h")
    db.query("UPDATE public.households SET nafaqah_provider_user_id = NULL WHERE id = %s", (family.id,))
    res = world.chat_commit(family.admin, family, llm, merchant="Dinner", amount=90, paid_by="me",
                            beneficiary="both")
    assert res.status_code == 200, res.text
    assert res.json()["nafaqah_class"] is None


# ─── FABLE2-LOGIC-01: rows re-saved by the old edit sheet ─────────────────────

def _edit_like_the_old_app(user, tx_id, raw, paid_by, beneficiary, merchant="Groceries"):
    """edit_transaction_sheet.dart at 84e264f: structured attempt (fails), then the raw_sms fallback."""
    if beneficiary == "both":
        spent_by = "both"
    elif paid_by == beneficiary:
        spent_by = paid_by
    else:
        spent_by = beneficiary
    clean = re.sub(r"\|\s*SpentBy:\s*(me|partner|both)", "", raw, flags=re.I)
    clean = re.sub(r"\|\s*PaidBy:\s*(me|partner)", "", clean, flags=re.I)
    clean = re.sub(r"\|\s*Beneficiary:\s*([^\s\|]+)", "", clean, flags=re.I)
    clean = re.sub(r"\|\s*SubCategory:\s*([^\s\|]+)", "", clean, flags=re.I).strip()
    new_raw = f"{clean} | PaidBy: {paid_by} | Beneficiary: {beneficiary} | SubCategory:  | SpentBy: {spent_by}"
    first = user.rest.patch(f"/transactions?id=eq.{tx_id}", json={
        "merchant": merchant, "paid_by": paid_by, "beneficiary": beneficiary, "spent_by": spent_by}, headers=REPR)
    assert first.status_code >= 400, first.text  # paid_by / beneficiary are not columns
    second = user.rest.patch(f"/transactions?id=eq.{tx_id}", json={
        "merchant": merchant, "raw_sms": new_raw, "spent_by": spent_by}, headers=REPR)
    assert second.status_code == 200, second.text
    return second.json()[0]


def test_logic01_old_app_edit_of_a_chat_row_keeps_the_payer(world, db, llm):
    flat = world.roommates("F9l1", n_members=1)
    ahmed, omar = flat.admin, flat.members[0]
    res = world.chat_commit(omar, flat, llm, merchant="Groceries", amount=200, paid_by="partner", beneficiary="both")
    assert res.status_code == 200, res.text
    tx_id = res.json()["transaction_id"]
    row = db.one("SELECT raw_sms FROM public.transactions WHERE id = %s", (tx_id,))
    edited = _edit_like_the_old_app(omar, tx_id, row["raw_sms"], paid_by="partner", beneficiary="both")
    assert edited["spent_by"] == "both"
    v1 = omar.api.get(f"/households/{flat.id}/settlement").json()
    assert v1["who_owes"] == "me_owes_partner" and v1["settlement_amount"] == 100.0, v1
    assert _debts(omar.api.get(f"/households/{flat.id}/settlement-v2")) == [(omar.id, ahmed.id, 100.0)]


def test_logic01_old_app_edit_of_a_manual_row_keeps_the_new_payer(world, db):
    flat = world.roommates("F9l1m", n_members=1)
    ahmed, omar = flat.admin, flat.members[0]
    row = {  # buildManualExpenseRow(), roommate mode: Omar paid 200 for all
        "id": str(uuid.uuid4()), "household_id": flat.id, "user_id": omar.id, "amount": 200, "currency": "SAR",
        "merchant": "Groceries", "category_code": "OPEX-GROCERY", "spent_by": "both", "beneficiary_type": "all_peers",
        "beneficiary_id": "all_peers", "account_id": None, "source": "manual", "timestamp": "2026-10-21T10:00:00Z",
        "raw_sms": f"Manual: Groceries | PaidBy: {omar.id} | Beneficiary: all_peers | SpentBy: both",
        "items": [{"name": "Groceries", "price": 200, "quantity": 1}],
    }
    assert omar.rest.post("/transactions", json=row, headers=REPR).status_code == 201
    assert _debts(omar.api.get(f"/households/{flat.id}/settlement-v2")) == [(ahmed.id, omar.id, 100.0)]
    # Old sheet: "partner paid, for both" → Ahmed paid the shared 200.
    _edit_like_the_old_app(omar, row["id"], row["raw_sms"], paid_by="partner", beneficiary="both")
    assert _debts(omar.api.get(f"/households/{flat.id}/settlement-v2")) == [(omar.id, ahmed.id, 100.0)]


# ─── FABLE2-API-02: recurring toggle bounded to known sub-budgets ─────────────

def test_api02_recurring_toggle_refuses_unknown_and_oversized_codes(world, db):
    flat = world.roommates("F9a2", n_members=1)
    admin, member = flat.admin, flat.members[0]
    r = admin.api.post("/budgets/sub-allocations", json={"household_id": flat.id, "category_code": "OPEX-UTILITIES",
                                                         "sub_allocations": {"electricity_sec": 300}})
    assert r.status_code == 200, r.text
    url = "/budgets/recurring-bills/toggle"
    for sub in ("S" * 500_000, "not_a_sub", "_recurring_config"):
        r = member.api.post(url, json={"household_id": flat.id, "category_code": "OPEX-UTILITIES", "sub_code": sub,
                                       "is_recurring": True})
        assert r.status_code == 422, (sub[:20], r.status_code, r.text[:200])
    r = member.api.post(url, json={"household_id": flat.id, "category_code": "X" * 100_000, "sub_code": "y",
                                   "is_recurring": True})
    assert r.status_code == 422
    r = member.api.post(url, json={"household_id": flat.id, "category_code": "OPEX-UTILITIES",
                                   "sub_code": "electricity_sec", "is_recurring": True, "due_day": 5})
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    size = db.scalar("SELECT octet_length(sub_allocations::text) FROM public.budgets WHERE household_id = %s "
                     "AND category_code = 'OPEX-UTILITIES'", (flat.id,))
    assert size < 1000


# ─── FABLE2-API-04 / O4: roommate settlement money ────────────────────────────

def test_api04_sub_halala_roommate_settlement_is_422(world, db):
    flat = world.roommates("F9a4", n_members=1)
    ahmed, omar = flat.admin, flat.members[0]
    url = f"/households/{flat.id}/reimbursements"
    body = {"household_id": flat.id, "payer_id": omar.id, "recipient_id": ahmed.id}
    assert omar.api.post(url, json={**body, "amount": 10.005}).status_code == 422
    assert db.scalar("SELECT count(*) FROM public.transactions WHERE household_id = %s", (flat.id,)) == 0
    r = omar.api.post(url, json={**body, "amount": 10.01})
    assert r.status_code == 200 and r.json()["amount"] == 10.01, r.text
    assert str(db.scalar("SELECT amount FROM public.transactions WHERE household_id = %s AND is_settlement",
                         (flat.id,))) == "10.01"


def test_o4_v1_small_roommate_balance_is_not_settled(world, db, llm):
    flat = world.roommates("F9o4", n_members=1)
    ahmed, omar = flat.admin, flat.members[0]
    assert world.chat_commit(omar, flat, llm, merchant="Gum", amount=0.30, beneficiary="both").status_code == 200
    v1 = omar.api.get(f"/households/{flat.id}/settlement").json()
    assert v1["who_owes"] == "partner_owes_me" and v1["settlement_amount"] == 0.15, v1
    assert _debts(omar.api.get(f"/households/{flat.id}/settlement-v2")) == [(ahmed.id, omar.id, 0.15)]


# ─── FABLE2-API-05: installment over a repaid wife advance ────────────────────

def test_api05_installment_on_repaid_advance_is_409_and_leaves_no_plan(world, db, llm):
    family = world.family("F9a5")
    husband, wife = family.admin, family.members[0]
    res = world.chat_commit(wife, family, llm, merchant="Extra", amount=300, category_code="OPEX-SHOPPING",
                            paid_by="me", beneficiary="both")
    assert res.status_code == 200 and res.json()["nafaqah_class"] == "wife_reimbursable", res.text
    tx_id = res.json()["transaction_id"]
    r = husband.api.post(f"/households/{family.id}/nafaqah/reimbursements", json={"amount": 200})
    assert r.status_code == 200, r.text
    plan = wife.api.post("/budgets/installments", json={"household_id": family.id, "merchant": "Extra",
                                                        "total_amount": 300, "installment_count": 4,
                                                        "original_transaction_id": tx_id})
    assert plan.status_code == 409, plan.text
    assert plan.json()["detail"]["code"] == "ledger_would_be_overpaid"
    assert db.scalar("SELECT count(*) FROM public.installment_plans WHERE original_transaction_id = %s",
                     (tx_id,)) == 0
    assert float(db.scalar("SELECT amount FROM public.transactions WHERE id = %s", (tx_id,))) == 300.0


def test_api05_installment_on_unrepaid_advance_still_works(world, db, llm):
    family = world.family("F9a5b")
    wife = family.members[0]
    res = world.chat_commit(wife, family, llm, merchant="Fridge", amount=2000, category_code="OPEX-SHOPPING",
                            paid_by="me", beneficiary="both")
    tx_id = res.json()["transaction_id"]
    plan = wife.api.post("/budgets/installments", json={"household_id": family.id, "merchant": "Fridge",
                                                        "total_amount": 2000, "installment_count": 4,
                                                        "original_transaction_id": tx_id})
    assert plan.status_code == 200, plan.text
    assert float(db.scalar("SELECT amount FROM public.transactions WHERE id = %s", (tx_id,))) == 500.0


# ─── FABLE2-API-06: invite target validated before the insert ─────────────────

def test_api06_invite_target_must_be_a_dependent_of_this_household(world, db):
    # Family household: spouse / family_member invites fit its type (owner decision D1).
    a = world.family("F9a6a")
    b = world.family("F9a6b")
    dep = b.admin.api.post(f"/households/{b.id}/dependents", json={"name": "Secret Kid"})
    assert dep.status_code == 200, dep.text
    foreign = dep.json()["dependent"]["id"]
    r = a.admin.api.post(f"/households/{a.id}/invites", json={"role": "spouse", "target_member_id": foreign})
    assert r.status_code == 404, r.text
    assert "Secret Kid" not in r.text
    r = a.admin.api.post(f"/households/{a.id}/invites", json={"role": "spouse", "target_member_id": "nope"})
    assert r.status_code == 400, r.text
    assert db.scalar("SELECT count(*) FROM public.household_invites WHERE household_id = %s "
                     "AND target_member_id IS NOT NULL", (a.id,)) == 0
    own = a.admin.api.post(f"/households/{a.id}/dependents", json={"name": "Own Kid"}).json()["dependent"]["id"]
    r = a.admin.api.post(f"/households/{a.id}/invites", json={"role": "family_member", "target_member_id": own})
    assert r.status_code == 200, r.text
    ins = a.admin.api.get(f"/households/invites/{r.json()['invite_code']}").json()
    assert ins["target_member_name"] == "Own Kid"
