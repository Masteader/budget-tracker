"""API-16 / 17 / 18: Nafaqah rules, no 50/50 spousal split, exact halala arithmetic."""

from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from installment_service import InstallmentPlan
from settlement_engine import (
    calculate_family_nafaqah,
    calculate_partner_settlement,
    calculate_roommate_pairwise_debts,
    calculate_settlement_v2,
    simplify_debts,
)

HH = "f860188e-23b5-4749-b180-868c956151a6"
HUSBAND = "00000000-0000-4000-8000-00000000000a"
WIFE = "00000000-0000-4000-8000-00000000000b"
CHILD_DEP = "dddddddd-0000-4000-8000-0000000000c1"
NOW = datetime.now(timezone.utc).isoformat()


@pytest.fixture()
def family(fake_supabase):
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": HH, "role": "member", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": HH, "role": "admin", "financial_role": "spouse", "display_name": "Sara"},
    ])
    return fake_supabase


# ─── API-17: Nafaqah engine ─────────────────────────────────────────────────

def test_wife_paying_for_dependent_referenced_by_id_is_husband_debt():
    txs = [{"amount": 120.0, "paid_by": WIFE, "beneficiary_type": "individual", "beneficiary_id": CHILD_DEP}]
    res = calculate_family_nafaqah(txs, husband_id=HUSBAND, wife_id=WIFE)
    assert res["wife_reimbursement_owed"] == 120.0


def test_wife_tabarru_contribution_is_not_debt():
    txs = [
        {"amount": 80.0, "paid_by": WIFE, "beneficiary_type": "household", "is_tabarru": True},
        {"amount": 20.0, "paid_by": WIFE, "beneficiary_type": "household"},
    ]
    res = calculate_family_nafaqah(txs, husband_id=HUSBAND, wife_id=WIFE)
    assert res["wife_reimbursement_owed"] == 20.0


def test_husband_paying_for_wife_never_creates_wife_debt():
    txs = [{"amount": 500.0, "paid_by": HUSBAND, "beneficiary_type": "individual", "beneficiary_id": WIFE}]
    res = calculate_family_nafaqah(txs, husband_id=HUSBAND, wife_id=WIFE)
    assert res["wife_reimbursement_owed"] == 0.0


def test_v2_admin_wife_is_not_mistaken_for_husband(family):
    family.seed("transactions", [
        {"id": "t1", "household_id": HH, "amount": 100.0, "paid_by": WIFE, "beneficiary_type": "household",
         "timestamp": NOW},
    ])
    res = calculate_settlement_v2(HH, cycle_start="2000-01-01")
    assert res["mode"] == "family_nafaqah"
    assert res["family_summary"]["wife_reimbursement_owed"] == 100.0


# ─── API-16: legacy /settlement must not split spousal expenses 50/50 ──────

def test_partner_settlement_in_family_household_never_splits_50_50(family):
    family.seed("transactions", [
        {"id": "g1", "household_id": HH, "amount": 300.0, "category_code": "OPEX-GROCERY",
         "paid_by": "me", "beneficiary": "both", "timestamp": NOW},
    ])
    res = calculate_partner_settlement(HH, split_ratio=0.5, caller_user_id=HUSBAND)
    assert res["mode"] == "family_nafaqah"
    assert res["owed_to_me"] == 0.0 and res["net_balance"] == 0.0
    assert res["fair_share_partner"] == 0.0


def test_partner_settlement_family_wife_paid_household_is_owed_in_full(family):
    family.seed("transactions", [
        {"id": "g2", "household_id": HH, "amount": 300.0, "category_code": "OPEX-GROCERY",
         "paid_by": "me", "beneficiary": "both", "timestamp": NOW},
    ])
    res = calculate_partner_settlement(HH, split_ratio=0.5, caller_user_id=WIFE)
    assert res["who_owes"] == "partner_owes_me"
    assert res["settlement_amount"] == 300.0


def test_settlement_route_rejects_out_of_range_split_ratio():
    from main import app
    client = TestClient(app)
    assert client.get(f"/households/{HH}/settlement", params={"split_ratio": 7}).status_code == 422
    assert client.get(f"/households/{HH}/settlement", params={"split_ratio": -1}).status_code == 422


# ─── API-18: exact money arithmetic ─────────────────────────────────────────

def _net(debts):
    net = {}
    for d in debts:
        net[d["from_id"]] = round(net.get(d["from_id"], 0) - d["amount"], 2)
        net[d["to_id"]] = round(net.get(d["to_id"], 0) + d["amount"], 2)
    return net


def test_three_way_split_conserves_every_halala():
    debts = calculate_roommate_pairwise_debts(
        [{"amount": 100.0, "paid_by": "a", "beneficiary_type": "all_peers"}], ["a", "b", "c"]
    )
    owed = sorted(d["amount"] for d in debts)
    # 10000 halalas / 3 = 3333 r1: one participant carries the extra halala, none is lost.
    assert owed == [33.33, 33.33]
    a_share = round(100.0 - sum(owed), 2)
    assert a_share == 33.34
    assert round(a_share + sum(owed), 2) == 100.0
    # Five-way split of 0.03 SAR: three people owe 0.01, nobody owes a fraction of a halala.
    tiny = calculate_roommate_pairwise_debts(
        [{"amount": 0.03, "paid_by": "e", "beneficiary_type": "all_peers"}], ["a", "b", "c", "d", "e"]
    )
    assert sorted(d["amount"] for d in tiny) == [0.01, 0.01, 0.01]


def test_simplification_cancels_cycles_and_collapses_chains():
    cycle = [{"from_id": "a", "to_id": "b", "amount": 10.0}, {"from_id": "b", "to_id": "c", "amount": 10.0},
             {"from_id": "c", "to_id": "a", "amount": 10.0}]
    assert simplify_debts(cycle) == []
    chain = [{"from_id": "a", "to_id": "b", "amount": 30.0}, {"from_id": "b", "to_id": "c", "amount": 30.0}]
    assert simplify_debts(chain) == [{"from_id": "a", "to_id": "c", "amount": 30.0}]


def test_simplification_preserves_net_positions_exactly():
    debts = [
        {"from_id": "a", "to_id": "b", "amount": 0.1}, {"from_id": "a", "to_id": "b", "amount": 0.2},
        {"from_id": "c", "to_id": "b", "amount": 33.33}, {"from_id": "d", "to_id": "a", "amount": 66.67},
        {"from_id": "c", "to_id": "d", "amount": 0.01},
    ]
    simplified = simplify_debts(debts)
    assert _net(simplified) == {k: v for k, v in _net(debts).items() if v != 0}
    assert len(simplified) <= len({d["from_id"] for d in debts} | {d["to_id"] for d in debts}) - 1


def test_completed_installment_plan_has_no_residual_halala():
    plan = InstallmentPlan(id="p", household_id=HH, merchant="m", total_amount=100.0, installment_count=3,
                           monthly_amount=33.33, paid_installments=3, status="COMPLETED")
    assert plan.remaining_amount == 0.0
    partial = InstallmentPlan(id="p", household_id=HH, merchant="m", total_amount=100.0, installment_count=3,
                              monthly_amount=33.33, paid_installments=2)
    assert partial.remaining_amount == 33.34
