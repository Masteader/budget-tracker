"""
Round 3 follow-up (R3B) fixes at the API (owner decisions 2026-11-06). The database (test 67)
enforces the same; here its RPCs are stand-ins and the API's own gates are what is tested.

* R3B-06: reversing a personal account's repayment needs its owner to be a current manager of her
  ledger too (her husband; an admin who is not a wife when he is gone). A replaced husband or a
  demoted admin no longer reverses, even his own (superseding R1-07); nobody else does either.
  The same for a former member's record. Pools as before.
* R3B-01 (the API's own writes): a member who does not read a transaction (a wife's personal
  purchase, for a co-wife or an ordinary member) cannot have the API edit it either: it is "not
  found", as a plan of one is.
* R3B-03 and item 4: a plan is read by what it keeps (its owner, and a deleted wife's mark), as the
  database's policy: a deleted wife's plan only by her husband and the admins who are not wives.
* R3B-05: a new plan linked to a purchase the caller does not read is refused exactly like one
  linked to a purchase that does not exist, or to another household's.
"""

from __future__ import annotations

import pytest

import household_permissions as hp
import nafaqah_service as ns
from test_wife_personal_privacy import (  # noqa: F401  (pytest fixtures)
    CALLERS,
    COWIFE,
    WIFE_ADMIN,
    household,
)
from test_wife_repayment_debit import (  # noqa: F401  (pytest fixtures)
    ACCOUNT,
    CHILD,
    COADMIN,
    DEBT,
    E_TRACKED,
    HH,
    HUSBAND,
    KEY,
    POOL,
    R_NEW,
    WIFE,
    bearer,
    client,
    family,
)
from test_wife_repayment_review_fixes import (  # noqa: F401  (pytest fixtures)
    E_COADMIN,
    R_COADMIN,
    demoted,
)


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


def _reverse(user, row=R_NEW):
    return client.post(f"/households/{HH}/nafaqah/reimbursements/{row}/reversal", headers=bearer(user), json={"request_key": KEY})


def _reverse_fmd(user, event):
    return client.post(f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/payments/{event}/reversal",
                       headers=bearer(user), json={"request_key": KEY})


def _replace_husband(fake, new_provider=CHILD):
    for h in fake.tables["households"]:
        if h["id"] == HH:
            h["nafaqah_provider_user_id"] = new_provider


# ─── R3B-06: only her ledger's manager reverses ───────────────────────────────

def test_r3b_06_a_replaced_husband_does_not_reverse_his_own_repayment(family):
    """R_NEW left the husband's own account. Another member is the husband now: he is refused, as
    forbidden (not as an account he may not use), and nothing reaches the database."""
    _replace_husband(family)
    resp = _reverse(HUSBAND)
    assert resp.status_code == 403, resp.text
    assert "account_forbidden" not in resp.text, resp.text  # forbidden as a reverser, not over the account
    assert _calls(family, "reverse_spouse_reimbursement") == []
    ctx = ns.load_family_context(HH)
    accounts = {a["id"]: a for a in family.tables["accounts"]}
    assert ns.can_reverse_repayment(ctx, HUSBAND, accounts[ACCOUNT]) is False


def test_r3b_06_nor_does_the_new_husband_reverse_from_an_account_not_his(family):
    _replace_husband(family)
    resp = _reverse(CHILD)
    assert resp.status_code == 403, resp.text
    assert _calls(family, "reverse_spouse_reimbursement") == []
    # He reads her ledger now, and is offered no reversal of the replaced husband's repayment.
    history = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(CHILD)).json()["history"]
    row = next(e for e in history if e.get("id") == R_NEW)
    assert row["can_reverse"] is False


def test_r3b_06_a_replaced_husband_does_not_reverse_his_own_former_member_payment(family):
    _replace_husband(family)
    resp = _reverse_fmd(HUSBAND, E_TRACKED)
    assert resp.status_code == 403, resp.text
    assert _calls(family, "reverse_former_member_debt_payment") == []


def test_r3b_06_a_demoted_admin_does_not_reverse_his_own_repayment(demoted):
    """The co-admin paid from his own account, then lost his admin rights while the husband is
    there: no longer his to reverse (review R1-07 superseded)."""
    resp = _reverse(COADMIN, R_COADMIN)
    assert resp.status_code == 403, resp.text
    assert "account_forbidden" not in resp.text, resp.text  # forbidden as a reverser, not over the account
    assert _reverse_fmd(COADMIN, E_COADMIN).status_code == 403
    assert _calls(demoted, "reverse_spouse_reimbursement") == []
    assert _calls(demoted, "reverse_former_member_debt_payment") == []
    ctx = ns.load_family_context(HH)
    own = next(a for a in demoted.tables["accounts"] if a.get("owner_user_id") == COADMIN and not a.get("is_shared_pool"))
    assert ns.can_reverse_repayment(ctx, COADMIN, own) is False


def test_r3b_06_the_husband_still_reverses_his_own_and_the_admin_once_he_is_gone(demoted):
    ctx = ns.load_family_context(HH)
    accounts = {a["id"]: a for a in demoted.tables["accounts"]}
    own = next(a for a in demoted.tables["accounts"] if a.get("owner_user_id") == COADMIN and not a.get("is_shared_pool"))
    assert ns.can_reverse_repayment(ctx, HUSBAND, accounts[ACCOUNT]) is True
    assert ns.can_reverse_repayment(ctx, COADMIN, own) is False
    # The husband gone and the co-admin an admin again: he manages her ledger, and reverses his own.
    for m in demoted.tables["household_memberships"]:
        if m["user_id"] == COADMIN:
            m["role"] = "admin"
    demoted.tables["household_memberships"][:] = [m for m in demoted.tables["household_memberships"] if m["user_id"] != HUSBAND]
    _replace_husband(demoted, None)
    ctx = ns.load_family_context(HH)
    assert ns.can_reverse_repayment(ctx, COADMIN, own) is True
    assert ns.can_reverse_repayment(ctx, COADMIN, accounts[POOL]) is True
    assert _reverse(COADMIN, R_COADMIN).status_code == 200


# ─── R3B-01: the API edits no row the caller does not read ───────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_r3b_01_a_personal_purchase_the_caller_does_not_read_is_not_found_for_an_edit(household, who):
    """assert_can_modify_transaction (the receipt enrichment and a plan's link use it) answers a
    personal purchase the caller does not read as not found, before asking who made it."""
    if who == "husband" and household.state == "gone":
        return
    caller = CALLERS[who]
    readers = {"wife", "admin"} | ({"husband"} if household.state != "gone" else set())
    try:
        hp.assert_can_modify_transaction(HH, "p-w1", caller)
        outcome = "ok"
    except hp.TransactionNotFoundError:
        outcome = "not_found"
    except hp.PermissionDeniedError:
        outcome = "forbidden"
    if who not in readers:
        assert outcome == "not_found", (who, outcome)
    elif who == "wife" or who == "admin" or (who == "husband" and household.state == "present-admin"):
        assert outcome == "ok", (who, outcome)
    else:
        assert outcome == "forbidden", (who, outcome)
    # An ordinary row stays as before: its maker or an admin.
    try:
        hp.assert_can_modify_transaction(HH, "o-1", caller)
        ordinary = "ok"
    except hp.PermissionDeniedError:
        ordinary = "forbidden"
    admins = {"admin", "wife-admin"} | ({"husband"} if household.state == "present-admin" else set())
    assert ordinary == ("ok" if who in admins or who == "husband" else "forbidden"), (who, ordinary)


def test_r3b_01_a_wife_admin_cannot_enrich_her_co_wifes_personal_purchase(household):
    from dedup_engine import enrich_transaction_items

    before = next(r for r in household.tables["transactions"] if r["id"] == "p-w1")
    snapshot = dict(before)
    done = enrich_transaction_items("p-w1", [{"name": "x", "price": 1, "quantity": 1}], receipt_url=f"{HH}/x.jpg",
                                    household_id=HH, actor_user_id=WIFE_ADMIN)
    assert done is False
    assert next(r for r in household.tables["transactions"] if r["id"] == "p-w1") == snapshot


# ─── R3B-03 and item 4: a plan is read by what it keeps ──────────────────────

PLAN_FORMER = "b6000000-0000-4000-8000-0000000000f1"
PLAN_ORDINARY = "b6000000-0000-4000-8000-0000000000f2"


def _plan_row(pid, shop, **extra):
    row = {
        "id": pid, "household_id": HH, "merchant": shop, "provider": "Tabby", "total_amount": 800.0,
        "installment_count": 4, "monthly_amount": 200.0, "paid_installments": 1, "day_of_month": 27,
        "start_date": "2026-11-01", "frequency": "monthly", "next_due_at": "2026-12-01", "status": "ACTIVE",
        "category_code": "OPEX-SHOPPING", "original_transaction_id": None, "notes": f"note {shop}",
        "created_at": "2026-11-01T10:00:00+00:00", "personal_owner_id": None, "former_member_personal": False,
    }
    row.update(extra)
    return row


@pytest.fixture()
def former_plans(household):
    household.tables["installment_plans"] = [
        # A deleted wife's plan: no owner left, the mark kept.
        _plan_row(PLAN_FORMER, "Tabby Former Bag", former_member_personal=True),
        _plan_row(PLAN_ORDINARY, "Tabby Ordinary Lamp"),
    ]
    household.schemas["installment_plans"] = set(_plan_row(PLAN_FORMER, "x"))
    return household


def _sees_allowances(state, who):
    return who == "admin" or (who == "husband" and state != "gone")


@pytest.mark.parametrize("who", list(CALLERS))
def test_item4_a_deleted_wifes_plan_is_read_by_her_husband_and_the_admins_who_are_not_wives(former_plans, who):
    resp = client.get("/budgets/installments", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    if who == "husband" and former_plans.state == "gone" and resp.status_code == 403:
        return
    assert resp.status_code == 200, resp.text
    shops = {p["merchant"] for p in resp.json()["plans"]}
    assert "Tabby Ordinary Lamp" in shops
    assert ("Tabby Former Bag" in shops) == _sees_allowances(former_plans.state, who), (who, shops)
    assert "former_member_personal" not in resp.text


@pytest.mark.parametrize("who", list(CALLERS))
def test_item4_a_deleted_wifes_plan_is_not_found_for_a_payment_or_an_edit(former_plans, who):
    if who == "husband" and former_plans.state == "gone":
        return
    pay = client.post(f"/budgets/installments/{PLAN_FORMER}/pay", headers=bearer(CALLERS[who]))
    edit = client.put(f"/budgets/installments/{PLAN_FORMER}", headers=bearer(CALLERS[who]), json={"notes": "x"})
    if _sees_allowances(former_plans.state, who):
        assert pay.status_code != 404 and edit.status_code != 404, (pay.text, edit.text)
    else:
        assert (pay.status_code, edit.status_code) == (404, 404), (pay.text, edit.text)
        assert next(p for p in former_plans.tables["installment_plans"] if p["id"] == PLAN_FORMER)["notes"] == "note Tabby Former Bag"


def test_r3b_03_the_plan_rule_reads_only_what_the_plan_keeps(household):
    """No purchase is looked up to read a plan: its kept owner and mark decide, as the policy."""
    ctx = ns.load_family_context(HH)
    hers = _plan_row("p", "x", original_transaction_id="p-w1", personal_owner_id=WIFE)
    assert ns.can_view_installment_plan(ctx, COWIFE, hers) is False
    assert ns.can_view_installment_plan(ctx, WIFE, hers) is True
    marked = _plan_row("p", "x", former_member_personal=True)
    assert ns.can_view_installment_plan(ctx, WIFE_ADMIN, marked) is False
    assert ns.can_view_installment_plan(ctx, COADMIN, marked) is True
    ordinary = _plan_row("p", "x", original_transaction_id="o-1")
    assert ns.can_view_installment_plan(ctx, COWIFE, ordinary) is True


# ─── R3B-05: a new plan on a purchase she does not read: the same "not found" ─

@pytest.mark.parametrize("who", ["co-wife", "member", "wife-admin"])
def test_r3b_05_a_hidden_purchase_is_refused_as_one_that_does_not_exist(household, who):
    def create(tx):
        return client.post("/budgets/installments", headers=bearer(CALLERS[who]), json={
            "household_id": HH, "merchant": "Linked", "total_amount": 313.0, "installment_count": 4,
            "original_transaction_id": tx, "adjust_original_transaction": False})

    before = len(household.tables.get("installment_plans") or [])
    hidden, nothing = create("p-w1"), create("tx-that-does-not-exist")
    assert hidden.status_code == 404, hidden.text
    assert (hidden.status_code, hidden.json()) == (nothing.status_code, nothing.json())
    assert len(household.tables.get("installment_plans") or []) == before


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3b_05_the_purchase_check_itself(household, who):
    """InstallmentService.transaction_visible_to, the route's first check: a purchase the caller does
    not read, one that does not exist, and another household's are all unreadable."""
    from installment_service import InstallmentService

    caller = CALLERS[who]
    sees = who in ("wife", "admin") or (who == "husband" and household.state != "gone")
    assert InstallmentService.transaction_visible_to("p-w1", HH, caller) is sees
    assert InstallmentService.transaction_visible_to("tx-that-does-not-exist", HH, caller) is False
    assert InstallmentService.transaction_visible_to("o-1", "b1000000-0000-4000-8000-0000000000ff", caller) is False
    assert InstallmentService.transaction_visible_to("o-1", HH, caller) is True
