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
