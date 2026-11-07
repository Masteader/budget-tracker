"""
Verification review CHK (owner decisions 2026-11-07), with the repository's fakes.

* CHK-02: ``PUT /budgets/installments/{id}`` rewrote the linked purchase's amount for anyone who
  read the plan, through the service role, so an ordinary member, a co-wife or a co-wife admin moved
  another member's balance (his purchase on his own bank, 100 -> 1) or raised a wife's advance (what
  her husband owes, 100 -> 250). An edit that changes the linked purchase now needs what creating
  the plan needs (DB-18, ``assert_can_modify_transaction``): its creator or a household admin, and
  only someone who reads the purchase and sees its account. Anyone else gets the create path's
  answer (403; 404 for a purchase they do not read) and nothing moves, the plan included. An edit of
  the plan's own fields alone (notes, merchant, a paid count...) stays open to whoever reads the
  plan, as the installment_plans policy lets any member who reads it update it.
"""

from __future__ import annotations

import inspect

import pytest

from installment_service import InstallmentService
from test_wife_account import (  # noqa: F401  (pytest fixtures)
    ADMIN,
    COWIFE,
    HER_BANK,
    HH,
    HIS_BANK,
    HUSBAND,
    MEMBER,
    WIFE,
    WIFE_ADMIN,
    _set_provider,
    bearer,
    client,
    family,
)

PLAN = "c8000000-0000-4000-8000-0000000000f1"
TX_HIS = "c6000000-0000-4000-8000-0000000000f1"  # the husband's own purchase on his own bank
TX_ADV = "c6000000-0000-4000-8000-0000000000f2"  # her advance, paid from her own bank
NOTHING = "c8000000-0000-4000-8000-0000000000f9"


def _tx(tx_id, user, account, amount, cls=None):
    return {"id": tx_id, "household_id": HH, "user_id": user, "amount": amount, "merchant": "M" + tx_id[-2:],
            "category_code": "OPEX-GROCERY", "timestamp": "2026-11-10T09:00:00+00:00", "cycle_key": "2026-11",
            "nafaqah_class": cls, "nafaqah_spouse_id": WIFE if cls else None, "account_id": account,
            "notes": None, "items": None, "receipt_url": None}


def _plan(tx_id):
    return {"id": PLAN, "household_id": HH, "merchant": "Plan", "provider": "Tabby", "total_amount": 400.0,
            "installment_count": 4, "monthly_amount": 100.0, "paid_installments": 1, "day_of_month": 27,
            "start_date": "2026-11-01", "frequency": "monthly", "next_due_at": "2026-12-01", "status": "ACTIVE",
            "category_code": "OPEX-GROCERY", "original_transaction_id": tx_id, "notes": None,
            "created_at": "2026-11-01T10:00:00+00:00", "personal_owner_id": None, "former_member_personal": False}


@pytest.fixture()
def rows(family):
    family.tables["transactions"].extend([
        _tx(TX_HIS, HUSBAND, HIS_BANK, 100.0), _tx(TX_ADV, WIFE, HER_BANK, 100.0, "wife_reimbursable")])
    family.tables.setdefault("budgets", [])
    family.tables["installment_plans"] = []
    family.schemas["installment_plans"] = set(_plan(TX_HIS))
    return family


def _linked(fake, tx_id):
    fake.tables["installment_plans"] = [_plan(tx_id)]


def _tx_row(fake, tx_id):
    return dict(next(r for r in fake.tables["transactions"] if r["id"] == tx_id))


def _plan_row(fake):
    return dict(fake.tables["installment_plans"][0])


def _edit(who, body, plan=PLAN):
    return client.put(f"/budgets/installments/{plan}", headers=bearer(who), json=body)


def _create_linked(who, tx_id):
    return client.post("/budgets/installments", headers=bearer(who), json={
        "household_id": HH, "merchant": "x", "total_amount": 400.0, "installment_count": 4,
        "original_transaction_id": tx_id})


@pytest.mark.parametrize("who", [MEMBER, COWIFE])
@pytest.mark.parametrize("body", [{"monthly_amount": 1.0}, {"total_amount": 4.0}, {"installment_count": 8}])
def test_chk_02_who_may_not_edit_his_purchase_does_not_rewrite_it_through_its_plan(rows, who, body):
    """The auditor's case: they read the plan, and his purchase on his own bank went 100 -> 1. Now
    403, the answer creating a plan on that purchase gives them; the purchase and the plan stay as
    they were. (An admin, a wife who is one included, edits any purchase of the household, DB-18:
    see test_chk_02_its_creator_and_an_admin_still_edit_it.)"""
    _linked(rows, TX_HIS)
    before, plan_before = _tx_row(rows, TX_HIS), _plan_row(rows)
    resp = _edit(who, body)
    assert resp.status_code == 403, resp.text
    # The same answer as linking that purchase to a new plan.
    created = _create_linked(who, TX_HIS)
    assert (resp.status_code, resp.json()) == (created.status_code, created.json())
    assert _tx_row(rows, TX_HIS) == before
    assert _plan_row(rows) == plan_before


@pytest.mark.parametrize("who", [MEMBER, COWIFE])
def test_chk_02_a_member_does_not_raise_her_advance_through_its_plan(rows, who):
    """Her advance on her own bank is what her husband owes her (family rule 2): a member or a
    co-wife who reads its plan raised it 100 -> 250. Now 403, and nothing moves."""
    _linked(rows, TX_ADV)
    before, plan_before = _tx_row(rows, TX_ADV), _plan_row(rows)
    resp = _edit(who, {"monthly_amount": 250.0})
    assert resp.status_code == 403, resp.text
    assert resp.json() == _create_linked(who, TX_ADV).json()
    assert _tx_row(rows, TX_ADV) == before
    assert _plan_row(rows) == plan_before


@pytest.mark.parametrize("who", [HUSBAND, ADMIN, WIFE_ADMIN])
def test_chk_02_its_creator_and_an_admin_still_edit_it(rows, who):
    _linked(rows, TX_HIS)
    resp = _edit(who, {"monthly_amount": 90.0})
    assert resp.status_code == 200, resp.text
    assert _tx_row(rows, TX_HIS)["amount"] == 90.0
    assert _plan_row(rows)["monthly_amount"] == 90.0


@pytest.mark.parametrize("who", [WIFE, HUSBAND, ADMIN, WIFE_ADMIN])
def test_chk_02_her_advance_is_edited_by_her_and_by_an_admin(rows, who):
    _linked(rows, TX_ADV)
    resp = _edit(who, {"monthly_amount": 80.0})
    assert resp.status_code == 200, resp.text
    assert _tx_row(rows, TX_ADV)["amount"] == 80.0


@pytest.mark.parametrize("who", [MEMBER, COWIFE])
def test_chk_02_the_plan_s_own_fields_stay_open_to_whoever_reads_it(rows, who):
    """Nothing of the purchase changes: whoever reads the plan edits its own fields, as the
    installment_plans policy lets them (rule unchanged)."""
    _linked(rows, TX_HIS)
    before = _tx_row(rows, TX_HIS)
    resp = _edit(who, {"notes": "due soon", "merchant": "Renamed", "paid_installments": 2})
    assert resp.status_code == 200, resp.text
    assert _tx_row(rows, TX_HIS) == before
    plan = _plan_row(rows)
    assert (plan["notes"], plan["merchant"], plan["paid_installments"]) == ("due soon", "Renamed", 2)


def test_chk_02_the_same_amounts_again_are_no_change_of_the_purchase(rows):
    """Amounts sent unchanged move nothing, so they are the plan's own edit."""
    _linked(rows, TX_HIS)
    before = _tx_row(rows, TX_HIS)
    resp = _edit(MEMBER, {"monthly_amount": 100.0, "total_amount": 400.0, "notes": "same"})
    assert resp.status_code == 200, resp.text
    assert _tx_row(rows, TX_HIS) == before


def test_chk_02_a_demoted_admin_no_longer_edits_it(rows):
    """The rule is the caller's role now, not when the plan was made."""
    for m in rows.tables["household_memberships"]:
        if m["user_id"] == ADMIN:
            m["role"] = "member"
    _linked(rows, TX_HIS)
    before = _tx_row(rows, TX_HIS)
    resp = _edit(ADMIN, {"monthly_amount": 1.0})
    assert resp.status_code == 403, resp.text
    assert _tx_row(rows, TX_HIS) == before


def test_chk_02_an_unknown_plan_is_still_404(rows):
    resp = _edit(MEMBER, {"monthly_amount": 1.0}, plan=NOTHING)
    assert resp.status_code == 404, resp.text


def test_chk_02_the_service_names_who_acts():
    """No caller of the edit can leave out who acts (the route passes the verified JWT subject)."""
    param = inspect.signature(InstallmentService.update_plan).parameters["actor_user_id"]
    assert param.default is inspect.Parameter.empty


def test_chk_02_without_an_actor_the_service_changes_no_purchase(rows):
    _linked(rows, TX_HIS)
    from household_permissions import PermissionDeniedError
    from installment_service import InstallmentPlanUpdate

    before, plan_before = _tx_row(rows, TX_HIS), _plan_row(rows)
    with pytest.raises(PermissionDeniedError):
        InstallmentService.update_plan(PLAN, HH, InstallmentPlanUpdate(monthly_amount=1.0), None)
    assert _tx_row(rows, TX_HIS) == before
    assert _plan_row(rows) == plan_before


def test_chk_02_husband_gone_changes_nothing_of_the_rule(rows):
    """Who edits a purchase does not depend on the husband: a member is still refused."""
    _set_provider(rows, None)
    _linked(rows, TX_ADV)
    before = _tx_row(rows, TX_ADV)
    assert _edit(MEMBER, {"monthly_amount": 5.0}).status_code == 403
    assert _tx_row(rows, TX_ADV) == before
