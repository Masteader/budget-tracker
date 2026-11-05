"""
Budgets of a category the household keeps inactive (owner decision 2026-11-05, migration
20261105001000): its expenses count in totals and reports but in no budget, and budgeting the
category through the API activates it for the household.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

import salary_cycle
from installment_service import InstallmentService

HH = "f860188e-23b5-4749-b180-868c956151a6"


@pytest.fixture
def cycle(fake_supabase):
    fake_supabase.seed("households", [{"id": HH, "payday_day": 27}])
    fake_supabase.seed("cost_control_codes", [
        {"id": c, "code": c, "category": c.title(), "keywords": [], "is_flexible": False, "household_id": None,
         "is_system": True}
        for c in ("OPEX-GROCERY", "OPEX-HOUSING", "OPEX-CHARITY", "OPEX-MISC")
    ])
    return salary_cycle.current_household_cycle(HH)["cycle_key"]


def _budget(code, key, active, spent=0.0, allocated=500.0):
    return {"id": f"b-{code}", "household_id": HH, "category_code": code, "cycle_key": key,
            "month": f"{key}-01", "allocated_amount": allocated, "spent_amount": spent, "is_active": active}


def _tx(code, key, amount, **extra):
    return {"id": f"t-{code}-{amount}", "household_id": HH, "category_code": code, "cycle_key": key,
            "amount": amount, "timestamp": f"{key}-01T12:00:00+03:00", **extra}


def _spent(fake, code):
    return {b["category_code"]: b["spent_amount"] for b in fake.tables["budgets"]}.get(code)


def _seed_spending(fake, key):
    fake.seed("budgets", [_budget("OPEX-GROCERY", key, True), _budget("OPEX-HOUSING", key, False, spent=7.0)])
    fake.seed("transactions", [
        _tx("OPEX-GROCERY", key, 120.0),
        _tx("OPEX-GROCERY", key, 30.0, nafaqah_class="wife_personal"),
        _tx("OPEX-GROCERY", key, 40.0, is_settlement=True),
        _tx("OPEX-HOUSING", key, 2500.0),
    ])


def test_recompute_leaves_inactive_rows(fake_supabase, cycle):
    _seed_spending(fake_supabase, cycle)
    InstallmentService.recalculate_budgets(HH, cycle)
    assert _spent(fake_supabase, "OPEX-GROCERY") == 120.0
    assert _spent(fake_supabase, "OPEX-HOUSING") == 7.0


def test_python_fallback_leaves_inactive_rows(fake_supabase, cycle):
    def missing(_params):
        raise RuntimeError("function public.recompute_budget_spent does not exist")

    fake_supabase.rpc_handlers["recompute_budget_spent"] = missing
    _seed_spending(fake_supabase, cycle)
    InstallmentService.recalculate_budgets(HH, cycle)
    assert _spent(fake_supabase, "OPEX-GROCERY") == 120.0
    assert _spent(fake_supabase, "OPEX-HOUSING") == 7.0


def test_breakdown_reports_inactive_spending_without_making_it_a_budget(fake_supabase, cycle):
    fake_supabase.seed("household_category_settings", [
        {"household_id": HH, "category_code": "OPEX-HOUSING", "is_active": False},
    ])
    fake_supabase.seed("transactions", [_tx("OPEX-HOUSING", cycle, 2500.0), _tx("OPEX-GROCERY", cycle, 50.0)])
    res = salary_cycle.get_cycle_breakdown(HH, cycle)
    items = {c["category_code"]: c for c in res["categories"]}
    assert items["OPEX-HOUSING"]["spent_amount"] == 2500.0  # counts in the report
    budget_codes = {b["category_code"] for b in fake_supabase.tables.get("budgets", [])}
    assert "OPEX-HOUSING" not in budget_codes  # but no budget row is made for it
    assert "OPEX-GROCERY" in budget_codes  # an active category keeps its auto-created row, as before


@pytest.mark.parametrize("how", ["add_category", "sub_allocations"])
def test_budgeting_a_category_activates_it(fake_supabase, cycle, how):
    fake_supabase.seed("household_category_settings", [
        {"household_id": HH, "category_code": "OPEX-HOUSING", "is_active": False},
    ])
    if how == "add_category":
        salary_cycle.add_category_and_budget(SimpleNamespace(
            household_id=HH, code="OPEX-HOUSING", category="Housing & Rent", allocated_amount=3000.0,
            keywords=None, is_flexible=False))
    else:
        salary_cycle.save_sub_allocations(HH, "OPEX-HOUSING", {"housing_rent": 3000.0}, cycle)
    settings = [s for s in fake_supabase.tables["household_category_settings"] if s["category_code"] == "OPEX-HOUSING"]
    assert [s["is_active"] for s in settings] == [True]
    rows = [b for b in fake_supabase.tables["budgets"] if b["category_code"] == "OPEX-HOUSING"]
    assert [(b["cycle_key"], b["is_active"], b["allocated_amount"]) for b in rows] == [(cycle, True, 3000.0)]
    assert "OPEX-HOUSING" in {c["code"] for c in salary_cycle.get_household_categories(HH)["active"]}
