"""
The wife account, review R3C (owner decisions 2026-11-07). The database (test 70) enforces the
same; here the API's own gates are tested, with the repository's fakes.

* R3C-01: only someone who may see a wife account (her, its owner, her ledger's managers) has the
  API edit or delete a transaction recorded on it. Her advance on it is read by the whole
  household, but a co-wife admin, an ordinary member, and an admin who is not a wife while her
  husband is there get the answer for a row they do not read ("not found"), on every path that
  rewrites it: the edit gate itself, the receipt enrichment, a new installment plan that adjusts
  it, and an edit of a plan linked to it. Its amount, and so the account's balance, do not move.
"""

from __future__ import annotations

import pytest

import household_permissions as hp
from test_wife_account import (  # noqa: F401  (pytest fixtures)
    ADMIN,
    COWIFE,
    HER_BANK,
    HH,
    HUSBAND,
    MEMBER,
    WA1,
    WIFE,
    WIFE_ADMIN,
    _set_provider,
    bearer,
    client,
    family,
)

ON_WA1 = "c6000000-0000-4000-8000-0000000000d1"  # her advance, paid from her wife account
ON_HER_BANK = "c6000000-0000-4000-8000-0000000000d2"  # her advance, paid from her own bank
NOTHING = "c6000000-0000-4000-8000-0000000000d9"
PLAN = "c8000000-0000-4000-8000-0000000000d1"

CALLERS = {"wife": WIFE, "husband": HUSBAND, "co-wife": COWIFE, "member": MEMBER, "admin": ADMIN,
           "wife-admin": WIFE_ADMIN}
# Who may see WA1 while her husband is there: she and its owner (him).
SEES = {"wife", "husband"}


def _tx(tx_id, account, amount):
    return {"id": tx_id, "household_id": HH, "user_id": WIFE, "amount": amount, "merchant": "Panda " + tx_id[-2:],
            "category_code": "OPEX-GROCERY", "timestamp": "2026-11-10T09:00:00+00:00", "cycle_key": "2026-11",
            "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE, "account_id": account, "notes": None,
            "items": None, "receipt_url": None}


@pytest.fixture()
def wife_rows(family):
    family.tables["transactions"].extend([_tx(ON_WA1, WA1, 70.0), _tx(ON_HER_BANK, HER_BANK, 40.0)])
    family.tables.setdefault("installment_plans", [])
    family.tables.setdefault("budgets", [])
    return family


def _row(fake, tx_id):
    return dict(next(r for r in fake.tables["transactions"] if r["id"] == tx_id))


def _gate(tx_id, caller):
    try:
        hp.assert_can_modify_transaction(HH, tx_id, caller)
        return "ok"
    except hp.TransactionNotFoundError:
        return "not_found"
    except hp.PermissionDeniedError:
        return "forbidden"


@pytest.mark.parametrize("who", list(CALLERS))
def test_r3c_01_the_edit_gate_answers_a_row_on_a_wife_account_she_does_not_see_as_not_found(wife_rows, who):
    caller = CALLERS[who]
    want = "ok" if who in SEES else "not_found"
    assert _gate(ON_WA1, caller) == want, who
    assert _gate(NOTHING, caller) == "not_found"
    # The same advance on her own bank keeps the general rule (its maker or an admin).
    assert _gate(ON_HER_BANK, caller) == ("ok" if who in {"wife", "husband", "admin", "wife-admin"} else "forbidden")


def test_r3c_01_once_her_husband_is_gone_the_admin_who_is_not_a_wife_edits_it(wife_rows):
    _set_provider(wife_rows, None)
    assert _gate(ON_WA1, ADMIN) == "ok"
    assert _gate(ON_WA1, WIFE_ADMIN) == "not_found"
    assert _gate(ON_WA1, MEMBER) == "not_found"


@pytest.mark.parametrize("who", ["co-wife", "member", "admin", "wife-admin"])
def test_r3c_01_the_receipt_enrichment_does_not_reach_it(wife_rows, who):
    from dedup_engine import enrich_transaction_items

    before = _row(wife_rows, ON_WA1)
    done = enrich_transaction_items(ON_WA1, [{"name": "x", "price": 1, "quantity": 1}], receipt_url=f"{HH}/x.jpg",
                                    household_id=HH, actor_user_id=CALLERS[who])
    assert done is False
    assert _row(wife_rows, ON_WA1) == before


@pytest.mark.parametrize("who", ["admin", "wife-admin"])
def test_r3c_01_a_new_plan_does_not_adjust_it(wife_rows, who):
    """Linking a plan adjusts the purchase's amount (her wife account's balance with it): refused
    exactly as a purchase that does not exist, and nothing is stored."""
    def create(tx):
        return client.post("/budgets/installments", headers=bearer(CALLERS[who]), json={
            "household_id": HH, "merchant": "Linked", "total_amount": 70.0, "installment_count": 4,
            "original_transaction_id": tx})

    before = _row(wife_rows, ON_WA1)
    hidden, nothing = create(ON_WA1), create(NOTHING)
    assert hidden.status_code == 404, hidden.text
    assert (hidden.status_code, hidden.json()) == (nothing.status_code, nothing.json())
    assert _row(wife_rows, ON_WA1) == before
    assert wife_rows.tables["installment_plans"] == []


def _linked_plan():
    return {
        "id": PLAN, "household_id": HH, "merchant": "Panda plan", "provider": "Tabby", "total_amount": 280.0,
        "installment_count": 4, "monthly_amount": 70.0, "paid_installments": 1, "day_of_month": 27,
        "start_date": "2026-11-01", "frequency": "monthly", "next_due_at": "2026-12-01", "status": "ACTIVE",
        "category_code": "OPEX-GROCERY", "original_transaction_id": ON_WA1, "notes": None,
        "created_at": "2026-11-01T10:00:00+00:00", "personal_owner_id": None, "former_member_personal": False,
    }


@pytest.mark.parametrize("who", ["co-wife", "member", "admin", "wife-admin"])
def test_r3c_01_an_edit_of_a_plan_linked_to_it_does_not_adjust_it(wife_rows, who):
    """Her advance's plan is read by the household (it is not a personal purchase); an edit of its
    amounts would rewrite her advance on her wife account. Refused as a plan that is not there."""
    wife_rows.tables["installment_plans"] = [_linked_plan()]
    wife_rows.schemas["installment_plans"] = set(_linked_plan())
    before, plan_before = _row(wife_rows, ON_WA1), dict(wife_rows.tables["installment_plans"][0])
    resp = client.put(f"/budgets/installments/{PLAN}", headers=bearer(CALLERS[who]), json={"monthly_amount": 90.0})
    absent = client.put(f"/budgets/installments/{NOTHING}", headers=bearer(CALLERS[who]), json={"monthly_amount": 90.0})
    assert resp.status_code == 404, resp.text
    assert (resp.status_code, resp.json()) == (absent.status_code, absent.json())
    assert _row(wife_rows, ON_WA1) == before
    assert wife_rows.tables["installment_plans"][0] == plan_before


def test_r3c_01_she_still_edits_her_plan_and_its_purchase(wife_rows):
    wife_rows.tables["installment_plans"] = [_linked_plan()]
    wife_rows.schemas["installment_plans"] = set(_linked_plan())
    resp = client.put(f"/budgets/installments/{PLAN}", headers=bearer(WIFE), json={"monthly_amount": 90.0})
    assert resp.status_code == 200, resp.text
    assert _row(wife_rows, ON_WA1)["amount"] == 90.0
    # A change that does not touch the amounts rewrites nothing of her advance, for anyone who reads the plan.
    before = _row(wife_rows, ON_WA1)
    resp = client.put(f"/budgets/installments/{PLAN}", headers=bearer(MEMBER), json={"notes": "due soon"})
    assert resp.status_code == 200, resp.text
    assert _row(wife_rows, ON_WA1) == before
