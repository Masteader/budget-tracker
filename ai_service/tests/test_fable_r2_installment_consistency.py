"""
FABLE2-API-05: an installment plan over a wife advance that was already (partly) repaid.

Adjusting the original transaction down to the monthly amount is refused by the ledger guard
(SQLSTATE 22023, HINT ledger_would_be_overpaid). The adjustment error used to be swallowed: the
plan was stored, the transaction kept its full amount and the request answered 200. Now a refused
adjustment removes the plan again and the request answers 409 ``ledger_would_be_overpaid`` (other
refusals: their 4xx, anything else 5xx), never 200 with an inconsistent state.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

import fakes
from fable_world import World

TX = "aaaaaaaa-0000-4000-8000-0000000000e6"


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def family(fake_supabase):
    w = World(fake_supabase, {"husband": ("admin", "provider"), "wife": ("member", "spouse")})
    fake_supabase.tables["households"][0]["nafaqah_provider_user_id"] = w.users["husband"]
    fake_supabase.seed("transactions", [{
        "id": TX, "household_id": w.hid, "user_id": w.users["wife"], "amount": 300.0, "merchant": "Extra",
        "raw_sms": "PaidBy: me | Beneficiary: both | SpentBy: me | Chat: Extra 300", "category_code": "OPEX-SHOPPING",
        "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": w.users["wife"], "source": "chat",
    }])
    return w


def _refuse_tx_updates(monkeypatch, error):
    original = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "transactions" and self._op == "update":
            raise error
        return original(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)


def _plan(w):
    return {"household_id": w.hid, "merchant": "Extra", "provider": "Tamara", "total_amount": 300,
            "installment_count": 4, "original_transaction_id": TX}


def test_ledger_guard_refusal_is_409_and_no_plan_is_left(api, fake_supabase, family, monkeypatch):
    _refuse_tx_updates(monkeypatch, APIError({
        "code": "22023", "hint": "ledger_would_be_overpaid", "details": "repaid=200.00 advances_after=75.00",
        "message": "This change would leave the wife's reimbursement ledger overpaid",
    }))
    r = api.post("/budgets/installments", json=_plan(family), headers=family.hdr("wife"))
    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "ledger_would_be_overpaid"
    assert not fake_supabase.tables.get("installment_plans")
    tx = fake_supabase.tables["transactions"][0]
    assert tx["amount"] == 300.0 and "Financed via" not in tx["raw_sms"]


def test_other_adjustment_failure_removes_the_plan_and_is_not_200(api, fake_supabase, family, monkeypatch):
    _refuse_tx_updates(monkeypatch, RuntimeError("connection reset"))
    r = api.post("/budgets/installments", json=_plan(family), headers=family.hdr("wife"))
    assert r.status_code >= 500, r.text
    assert "connection reset" not in r.text
    assert not fake_supabase.tables.get("installment_plans")


def test_permission_refusal_of_the_adjustment_is_403(api, fake_supabase, family, monkeypatch):
    _refuse_tx_updates(monkeypatch, APIError({"code": "42501", "message": "rls", "hint": None, "details": None}))
    r = api.post("/budgets/installments", json=_plan(family), headers=family.hdr("wife"))
    assert r.status_code == 403, r.text
    assert not fake_supabase.tables.get("installment_plans")


def test_successful_adjustment_still_creates_the_plan(api, fake_supabase, family):
    r = api.post("/budgets/installments", json=_plan(family), headers=family.hdr("wife"))
    assert r.status_code == 200, r.text
    assert len(fake_supabase.tables["installment_plans"]) == 1
    assert fake_supabase.tables["transactions"][0]["amount"] == 75.0
