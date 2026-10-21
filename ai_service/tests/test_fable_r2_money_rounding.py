"""
FABLE2-API-04 / O4: money exactness of roommate settlements.

- POST /households/{id}/reimbursements refuses sub-halala amounts with 422 (like the Nafaqah
  route) instead of rounding them half-even (10.005 -> 10.00 while the app rounds half-up).
- Amounts quantised server-side round half-up.
- v1 /settlement: the two shares of a shared expense always sum to the total, and a roommate
  balance is 'settled' only below one halala (as in v2 and the family ledger).
"""
from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient

import supabase_client
from fable_world import World


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def w(fake_supabase):
    return World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})


def _settle(api, w, amount):
    return api.post(f"/households/{w.hid}/reimbursements", json={
        "household_id": w.hid, "payer_id": w.users["omar"], "recipient_id": w.users["ahmed"], "amount": amount,
    }, headers=w.hdr("omar"))


@pytest.mark.parametrize("amount", [10.005, 10.015, 0.001, 99.999])
def test_sub_halala_settlement_is_422(api, fake_supabase, w, amount):
    r = _settle(api, w, amount)
    assert r.status_code == 422, r.text
    assert not [t for t in fake_supabase.tables.get("transactions", []) if t.get("is_settlement")]


def test_two_decimal_settlement_is_stored_exactly(api, fake_supabase, w):
    r = _settle(api, w, 10.01)
    assert r.status_code == 200, r.text
    assert r.json()["amount"] == 10.01
    stored = [t for t in fake_supabase.tables["transactions"] if t.get("is_settlement")][0]
    assert stored["amount"] == "10.01"


@pytest.mark.parametrize("amount, expected", [("10.005", "10.01"), ("10.015", "10.02"), ("0.125", "0.13")])
def test_service_quantises_half_up(fake_supabase, w, amount, expected):
    result = supabase_client.record_household_reimbursement(
        w.hid, w.users["omar"], w.users["ahmed"], amount, recorded_by=w.users["omar"])
    stored = [t for t in fake_supabase.tables["transactions"] if t["id"] == result["transaction_id"]][0]
    assert stored["amount"] == expected and result["amount"] == float(expected)


def _shared(fake, w, amount, who="omar"):
    from utils import riyadh_today

    fake.seed("transactions", [{
        "id": str(uuid.uuid4()), "household_id": w.hid, "user_id": w.users[who], "amount": amount, "merchant": "x",
        "category_code": "OPEX-MISC", "spent_by": "me", "timestamp": f"{riyadh_today().isoformat()}T09:00:00+00:00",
        "raw_sms": "", "source": "chat", "beneficiary_type": "household", "beneficiary_id": "household",
        "is_settlement": False, "settlement_target_id": None, "nafaqah_class": None, "nafaqah_spouse_id": None,
        "line_items": [],
    }])


@pytest.mark.parametrize("amount, ratio", [(0.01, 0.5), (0.03, 0.5), (100.01, 0.3), (10.0, 1 / 3)])
def test_v1_shares_sum_to_the_total(api, fake_supabase, w, amount, ratio):
    _shared(fake_supabase, w, amount)
    s = api.get(f"/households/{w.hid}/settlement", params={"split_ratio": ratio}, headers=w.hdr("omar")).json()
    assert round(s["fair_share_me"] + s["fair_share_partner"], 2) == round(amount, 2), s


def test_v1_roommate_settled_threshold_is_one_halala(api, fake_supabase, w):
    _shared(fake_supabase, w, 0.30)  # Ahmed owes Omar 0.15
    s = api.get(f"/households/{w.hid}/settlement", headers=w.hdr("omar")).json()
    assert s["who_owes"] == "partner_owes_me" and s["settlement_amount"] == 0.15, s
    v2 = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("omar")).json()
    assert [(d["from_id"], d["amount"]) for d in v2["pairwise_debts"]] == [(w.users["ahmed"], 0.15)]


def test_installment_amounts_round_half_up():
    from installment_service import calculate_installment_terms

    terms = calculate_installment_terms(0.5, installment_count=4)  # 0.125 per month
    assert terms["monthly_amount"] == 0.13 and terms["remaining_amount"] == 0.37
    assert calculate_installment_terms(10.005, installment_count=1)["total_amount"] == 10.01


def test_v1_half_halala_balance_rounds_half_up(api, fake_supabase, w):
    _shared(fake_supabase, w, 0.01)  # Ahmed owes Omar half a halala
    s = api.get(f"/households/{w.hid}/settlement", headers=w.hdr("omar")).json()
    assert s["who_owes"] == "partner_owes_me" and s["settlement_amount"] == 0.01, s
