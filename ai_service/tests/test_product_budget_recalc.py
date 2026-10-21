"""
Product review 3.3 / 4.1: no full-history scan per insert.

``insert_transaction`` used to call ``InstallmentService.recalculate_budgets`` after every insert,
which selected every transaction of the household. The database triggers (BUG-02 and the
20261020800000 / 20261020900000 budget triggers) already keep ``budgets.spent_amount`` current,
so the insert no longer recalculates anything.
"""
from __future__ import annotations

import supabase_client

HH = "f860188e-23b5-4749-b180-868c956151a6"


def test_insert_does_not_recalculate_budgets(fake_supabase, monkeypatch):
    import installment_service

    calls = []
    monkeypatch.setattr(installment_service.InstallmentService, "recalculate_budgets",
                        classmethod(lambda cls, *a, **k: calls.append(a)))
    fake_supabase.seed("households", [{"id": HH, "payday_day": 27}])
    reads = []
    import fakes

    real_execute = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "transactions" and self._op == "select":
            reads.append(self._table)
        return real_execute(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)
    tx_id = supabase_client.insert_transaction(
        household_id=HH, amount=25.0, currency="SAR", merchant="Albaik", category_code="OPEX-DINING",
        timestamp="2026-10-21T10:00:00+00:00", raw_sms="Chat: test", sub_category="restaurants_dinners",
    )
    assert tx_id
    assert calls == [], "insert_transaction must not recalculate budgets"
    assert reads == [], "the insert read the transactions table"


# ─── explicit recalculation: one cycle, SQL first ──────────────────────────────

def _seed_two_cycles(fake):
    fake.seed("households", [{"id": HH, "payday_day": 27}])
    fake.seed("budgets", [
        {"id": "b-nov", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-11",
         "month": "2026-11-01", "allocated_amount": 500.0, "spent_amount": 999.0},
        {"id": "b-oct", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-10",
         "month": "2026-10-01", "allocated_amount": 500.0, "spent_amount": 777.0},
    ])
    fake.seed("transactions", [
        {"id": "t1", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-11", "amount": 40.0},
        {"id": "t2", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-11", "amount": 10.5},
        {"id": "t3", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-11", "amount": 30.0,
         "is_settlement": True},
        {"id": "t4", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-11", "amount": 70.0,
         "nafaqah_class": "wife_personal"},
        {"id": "t5", "household_id": HH, "category_code": "OPEX-DINING", "cycle_key": "2026-10", "amount": 5.0},
    ])


def _budget(fake, bid):
    return next(b for b in fake.tables["budgets"] if b["id"] == bid)


def test_recalculation_uses_the_sql_function_for_one_cycle(fake_supabase):
    from installment_service import InstallmentService

    _seed_two_cycles(fake_supabase)
    InstallmentService.recalculate_budgets(HH, "2026-11")
    assert ("recompute_budget_spent", {"p_household_id": HH, "p_cycle_keys": ["2026-11"]}) in fake_supabase.rpc_calls
    assert _budget(fake_supabase, "b-nov")["spent_amount"] == 50.5
    assert _budget(fake_supabase, "b-oct")["spent_amount"] == 777.0  # other cycles untouched


def test_recalculation_falls_back_to_python_for_the_cycle_only(fake_supabase, monkeypatch):
    from installment_service import InstallmentService
    import fakes

    def missing(_params):
        raise fakes.FakeSchemaError("Could not find the function public.recompute_budget_spent", "PGRST202")

    fake_supabase.rpc_handlers["recompute_budget_spent"] = missing
    _seed_two_cycles(fake_supabase)
    selects = []
    real_execute = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "transactions" and self._op == "select":
            selects.append(list(getattr(self, "_filters_columns", [])))
        return real_execute(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)
    InstallmentService.recalculate_budgets(HH, "2026-11")
    assert _budget(fake_supabase, "b-nov")["spent_amount"] == 50.5
    assert _budget(fake_supabase, "b-oct")["spent_amount"] == 777.0
    assert selects and all("cycle_key" in cols for cols in selects), selects


def test_recalculate_endpoint_still_works(fake_supabase):
    from fastapi.testclient import TestClient
    from main import app

    _seed_two_cycles(fake_supabase)
    res = TestClient(app).post(f"/budgets/recalculate?household_id={HH}&cycle_key=2026-11")
    assert res.status_code == 200, res.text
    assert _budget(fake_supabase, "b-nov")["spent_amount"] == 50.5
