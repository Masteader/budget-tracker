import os
import sys
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from settlement_engine import (
    calculate_family_nafaqah,
    calculate_roommate_pairwise_debts,
    simplify_debts,
)


def test_family_nafaqah_husband_pays_no_debt_to_wife():
    # Husband paying for groceries or kids should produce 0 debt against wife
    txs = [
        {"paid_by": "husband", "beneficiary_type": "household", "amount": 500.0, "is_settlement": False},
        {"paid_by": "husband", "beneficiary_type": "individual", "beneficiary_id": "child_sarah", "amount": 150.0, "is_settlement": False},
    ]
    res = calculate_family_nafaqah(txs, husband_id="husband", wife_id="wife")
    assert res["wife_reimbursement_owed"] == 0.0
    assert res["spent_on_children"] == 150.0
    assert res["family_general_total"] == 500.0
    assert res["spent_on_wife"] == 0.0


def test_family_nafaqah_wife_pays_husband_owes_100_percent():
    # Wife paying for household/kids creates 100% reimbursement debt for husband
    txs = [
        {"paid_by": "wife", "beneficiary_type": "household", "amount": 350.0, "is_settlement": False},
        {"paid_by": "husband", "beneficiary_type": "household", "amount": 500.0, "is_settlement": False},
    ]
    res = calculate_family_nafaqah(txs, husband_id="husband", wife_id="wife")
    assert res["wife_reimbursement_owed"] == 350.0
    assert res["family_general_total"] == 850.0


def test_family_nafaqah_partial_reimbursement_settlement():
    # Wife paid 350 SAR. Husband reimbursed 200 SAR via STC Pay.
    txs = [
        {"paid_by": "wife", "beneficiary_type": "household", "amount": 350.0, "is_settlement": False},
        {"paid_by": "husband", "beneficiary_type": "individual", "beneficiary_id": "wife", "settlement_target_id": "wife", "amount": 200.0, "is_settlement": True},
    ]
    res = calculate_family_nafaqah(txs, husband_id="husband", wife_id="wife")
    assert res["wife_reimbursement_owed"] == 150.0
    assert res["reimbursed_total"] == 200.0


def test_roommate_pairwise_and_simplification():
    # Roommates: Ahmed, Omar, Ibrahim, Tariq
    # Omar owes Ahmed 100, Ibrahim owes Ahmed 200, Tariq owes Omar 200
    debts = [
        {"from_id": "omar", "to_id": "ahmed", "amount": 100.0},
        {"from_id": "ibrahim", "to_id": "ahmed", "amount": 200.0},
        {"from_id": "tariq", "to_id": "omar", "amount": 200.0},
    ]
    simplified = simplify_debts(debts)
    # Total cash transferred in simplified must not exceed original
    assert sum(d["amount"] for d in simplified) <= sum(d["amount"] for d in debts)
    # Check net balance preservation for Omar:
    # Original net: received from Tariq (+200), paid to Ahmed (-100) -> net = +100
    omar_net = sum(d["amount"] for d in simplified if d["to_id"] == "omar") - sum(d["amount"] for d in simplified if d["from_id"] == "omar")
    assert omar_net == 100.0

    # Check net balance for Ahmed:
    # Original net: +100 from Omar, +200 from Ibrahim -> net = +300
    ahmed_net = sum(d["amount"] for d in simplified if d["to_id"] == "ahmed") - sum(d["amount"] for d in simplified if d["from_id"] == "ahmed")
    assert ahmed_net == 300.0


def test_calculate_roommate_pairwise_debts_with_line_items():
    # Ahmed paid 400 total:
    # 200 shared equally among Ahmed, Omar, Tariq (3 people -> 66.67 each)
    # 200 personal for Omar
    txs = [
        {
            "paid_by": "ahmed",
            "amount": 400.0,
            "is_settlement": False,
            "line_items": [
                {"name": "Shared Grocery", "amount": 200.0, "beneficiary": "all_peers"},
                {"name": "Omar Protein", "amount": 200.0, "beneficiary": "omar"},
            ],
        }
    ]
    peers = ["ahmed", "omar", "tariq"]
    debts = calculate_roommate_pairwise_debts(txs, peers)

    # Omar owes Ahmed 200 (personal) + 66.67 (shared) = 266.67
    omar_debt = next(d for d in debts if d["from_id"] == "omar" and d["to_id"] == "ahmed")
    assert pytest.approx(omar_debt["amount"], 0.1) == 266.67

    # Tariq owes Ahmed 66.67 (shared)
    tariq_debt = next(d for d in debts if d["from_id"] == "tariq" and d["to_id"] == "ahmed")
    assert pytest.approx(tariq_debt["amount"], 0.1) == 66.67
