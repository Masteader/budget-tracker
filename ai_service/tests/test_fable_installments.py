"""
FABLE-API-09 / FABLE-API-10 (docs/review/audit/fable_review.md).

- ``start_date`` must be an ISO date (422); there is no container-local JSON fallback any more
  (a failed insert fails the request), and the original transaction is only adjusted after the
  plan was stored.
- A payment is one atomic conditional increment in the database (RPC pay_installment_plan,
  migration 20261020750000), never a read-modify-write in Python.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from fable_world import World


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def w(fake_supabase):
    w = World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})
    fake_supabase.seed("transactions", [{
        "id": "aaaaaaaa-0000-4000-8000-0000000000aa", "household_id": w.hid, "user_id": w.users["ahmed"],
        "amount": 1200.0, "merchant": "Jarir", "raw_sms": "Chat: Jarir 1200", "category_code": "OPEX-SHOPPING",
    }])
    return w


def _plan(w, **extra):
    return {"household_id": w.hid, "merchant": "Jarir", "provider": "Tamara", "total_amount": 1200,
            "installment_count": 4, "original_transaction_id": "aaaaaaaa-0000-4000-8000-0000000000aa", **extra}


def test_invalid_start_date_is_422_and_nothing_changes(api, fake_supabase, w):
    import installment_service

    r = api.post("/budgets/installments", json=_plan(w, start_date="not-a-date"), headers=w.hdr("ahmed"))
    assert r.status_code == 422, r.text
    assert not fake_supabase.tables.get("installment_plans")
    assert fake_supabase.tables["transactions"][0]["amount"] == 1200.0
    assert not hasattr(installment_service, "FALLBACK_FILE")


def test_valid_start_date_is_stored(api, fake_supabase, w):
    r = api.post("/budgets/installments", json=_plan(w, start_date="2026-11-01"), headers=w.hdr("ahmed"))
    assert r.status_code == 200, r.text
    assert fake_supabase.tables["installment_plans"][0]["start_date"] == "2026-11-01"
    assert fake_supabase.tables["transactions"][0]["amount"] == 300.0


def test_failed_insert_fails_the_request_and_keeps_the_transaction(api, fake_supabase, w, monkeypatch):
    real_table = fake_supabase.table

    class _Refusing:
        def __init__(self, query):
            self._query = query

        def insert(self, *_a, **_k):
            raise RuntimeError("installment_plans insert refused")

        def __getattr__(self, name):
            return getattr(self._query, name)

    monkeypatch.setattr(fake_supabase, "table",
                        lambda name: _Refusing(real_table(name)) if name == "installment_plans" else real_table(name))
    r = api.post("/budgets/installments", json=_plan(w), headers=w.hdr("ahmed"))
    assert r.status_code >= 500, r.text
    assert fake_supabase.tables["transactions"][0]["amount"] == 1200.0
    assert "Financed via" not in fake_supabase.tables["transactions"][0]["raw_sms"]


def test_pay_is_one_atomic_rpc_call(api, fake_supabase, w):
    fake_supabase.seed("installment_plans", [{
        "id": "dddddddd-0000-4000-8000-000000000001", "household_id": w.hid, "merchant": "eXtra",
        "provider": "Tamara", "total_amount": 300.0, "installment_count": 3, "monthly_amount": 100.0,
        "paid_installments": 1, "day_of_month": 27, "start_date": "2026-10-01", "status": "ACTIVE",
    }])
    url = "/budgets/installments/dddddddd-0000-4000-8000-000000000001/pay"
    assert api.post(url, headers=w.hdr("omar")).json()["paid_installments"] == 2
    last = api.post(url, headers=w.hdr("omar")).json()
    assert last["paid_installments"] == 3 and last["status"] == "COMPLETED"
    again = api.post(url, headers=w.hdr("omar")).json()
    assert again["paid_installments"] == 3  # never beyond the plan
    calls = [c for c in fake_supabase.rpc_calls if c[0] == "pay_installment_plan"]
    assert len(calls) == 3
    assert calls[0][1] == {"p_plan_id": "dddddddd-0000-4000-8000-000000000001", "p_household_id": w.hid,
                           "p_actor_user_id": w.users["omar"]}
    # No read-modify-write: the service never updates installment_plans itself.
    assert all(p["paid_installments"] == 3 for p in fake_supabase.tables["installment_plans"])


def test_pay_unknown_or_malformed_plan_is_404(api, w):
    assert api.post("/budgets/installments/not-a-uuid/pay", headers=w.hdr("omar")).status_code == 404
    assert api.post("/budgets/installments/dddddddd-0000-4000-8000-00000000ffff/pay",
                    headers=w.hdr("omar")).status_code == 404
