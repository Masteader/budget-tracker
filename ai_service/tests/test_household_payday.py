"""
External review (Gemini) HIGH 5: every computation with a household context must use the
household's payday (households.payday_day), not the hard-coded default of the 27th.

Fixture: a household paid on the 10th, "today" = 2026-10-28 in Riyadh.
  payday 10 → current cycle 2026-10 (Oct 10 – Nov 9)
  payday 27 → current cycle 2026-11 (Oct 27 – Nov 26)   ← what the old code used
"""

from __future__ import annotations

from datetime import date, datetime
from types import SimpleNamespace

import pytest

import utils

HH = "aaaaaaaa-0000-4000-8000-000000000010"
PAYDAY = 10
CYCLE = "2026-10"
WRONG_CYCLE = "2026-11"


@pytest.fixture()
def household(fake_supabase, monkeypatch):
    instant = datetime.fromisoformat("2026-10-28T09:00:00+00:00")
    monkeypatch.setattr(utils, "utc_now", lambda: instant)
    monkeypatch.setattr("installment_service.InstallmentService.recalculate_budgets", lambda *a, **k: None)
    fake_supabase.seed("households", [{"id": HH, "payday_day": PAYDAY}])
    return fake_supabase


def _budget_rows(fake, code):
    return [b for b in fake.tables.get("budgets", []) if b.get("category_code") == code]


def test_fixture_cycles_differ_between_household_payday_and_default():
    from salary_cycle import get_cycle_for_date

    assert get_cycle_for_date(date(2026, 10, 28), payday_day=PAYDAY)["cycle_key"] == CYCLE
    assert get_cycle_for_date(date(2026, 10, 28))["cycle_key"] == WRONG_CYCLE


def test_add_category_and_budget_uses_household_payday(household):
    from salary_cycle import add_category_and_budget

    req = SimpleNamespace(household_id=HH, code="CUSTOM-GYM", category="Gym", keywords=None,
                          is_flexible=False, allocated_amount=120.0)
    add_category_and_budget(req)
    rows = _budget_rows(household, "CUSTOM-GYM")
    assert [r["cycle_key"] for r in rows] == [CYCLE]


def test_add_category_and_budget_updates_the_budget_of_the_household_cycle(household):
    from salary_cycle import add_category_and_budget

    household.seed("budgets", [{"id": "b-1", "household_id": HH, "category_code": "CUSTOM-GYM",
                                "cycle_key": CYCLE, "month": "2026-10-01", "allocated_amount": 50.0}])
    req = SimpleNamespace(household_id=HH, code="CUSTOM-GYM", category="Gym", keywords=None,
                          is_flexible=False, allocated_amount=120.0)
    add_category_and_budget(req)
    rows = _budget_rows(household, "CUSTOM-GYM")
    assert len(rows) == 1 and rows[0]["allocated_amount"] == 120.0


def test_create_household_custom_category_uses_household_payday(household):
    from salary_cycle import create_household_custom_category

    res = create_household_custom_category(HH, "PETS", "Pets", ["cat food"], allocated_amount=80.0)
    rows = _budget_rows(household, res["code"])
    # One budget row for the household's cycle (activation creates it; the allocation updates it).
    assert [(r["cycle_key"], r["allocated_amount"]) for r in rows] == [(CYCLE, 80.0)]


def test_archive_category_uses_household_payday(household):
    from salary_cycle import archive_category_for_household

    archive_category_for_household(HH, "OPEX-DINING")
    rows = _budget_rows(household, "OPEX-DINING")
    assert [(r["cycle_key"], r["month"]) for r in rows] == [(CYCLE, f"{CYCLE}-01")]


def test_save_sub_allocations_defaults_to_household_cycle(household):
    from salary_cycle import save_sub_allocations

    res = save_sub_allocations(HH, "OPEX-UTILITIES", {"sub-electricity": 300})
    assert res["cycle_key"] == CYCLE
    assert [r["cycle_key"] for r in _budget_rows(household, "OPEX-UTILITIES")] == [CYCLE]


def test_add_sub_category_defaults_to_household_cycle(household):
    from salary_cycle import add_sub_category_for_household

    res = add_sub_category_for_household(HH, "OPEX-UTILITIES", "Water", allocated_amount=60)
    assert res["cycle_key"] == CYCLE


def test_remove_sub_category_targets_household_cycle(household):
    from salary_cycle import remove_sub_category_for_household

    household.seed("budgets", [{"id": "b-2", "household_id": HH, "category_code": "OPEX-UTILITIES",
                                "cycle_key": CYCLE, "month": "2026-10-01", "allocated_amount": 360.0,
                                "sub_allocations": {"sub-electricity": 300.0, "sub-water": 60.0}}])
    remove_sub_category_for_household(HH, "OPEX-UTILITIES", "sub-water")
    row = _budget_rows(household, "OPEX-UTILITIES")[0]
    assert row["sub_allocations"] == {"sub-electricity": 300.0}
    assert row["allocated_amount"] == 300.0


def test_cycle_breakdown_defaults_to_household_cycle(household):
    from salary_cycle import get_cycle_breakdown

    res = get_cycle_breakdown(HH)
    assert res["cycle_key"] == CYCLE


def test_affordability_advice_names_the_household_payday_not_the_27th(household):
    from salary_cycle import simulate_affordability

    res = simulate_affordability(HH, 5000.0, item_name="TV")
    assert res["verdict"] == "unaffordable"
    assert "27" not in res["advice_en"] and "27" not in res["advice_ar"]
    assert "2026-11-10" in res["advice_en"] and "2026-11-10" in res["advice_ar"]


# ─── recurring_detector ───────────────────────────────────────────────────────

def _utility_budget(due_day: int) -> dict:
    return {"id": "b-u", "household_id": HH, "category_code": "OPEX-UTILITIES", "cycle_key": CYCLE,
            "month": "2026-10-01", "is_active": True, "allocated_amount": 300.0,
            "sub_allocations": {"sub-electricity": 300.0,
                                "_recurring_config": {"sub-electricity": {"enabled": True, "due_day": due_day}}}}


def test_detect_recurring_bills_uses_the_given_payday_for_cycle_and_due_dates():
    from recurring_detector import detect_recurring_bills

    # Due on the 12th in a cycle Oct 10 – Nov 9: the due date is Oct 12, so on Oct 28 it is overdue.
    # The old ">= 27" heuristic put it on Nov 12, outside the cycle, and reported it upcoming.
    res = detect_recurring_bills([], as_of_date=date(2026, 10, 28), budgets=[_utility_budget(12)], payday_day=PAYDAY)
    assert res["cycle_key"] == CYCLE
    assert [(b["sub_code"], b["status"]) for b in res["bills"]] == [("sub-electricity", "OVERDUE")]

    res = detect_recurring_bills([], as_of_date=date(2026, 10, 28), budgets=[_utility_budget(5)], payday_day=PAYDAY)
    assert [b["status"] for b in res["bills"]] == ["UPCOMING"]  # Nov 5, still inside the cycle


def test_detect_recurring_bills_default_payday_keeps_previous_behaviour():
    from recurring_detector import detect_recurring_bills

    budget = dict(_utility_budget(27), cycle_key="2026-11")
    res = detect_recurring_bills([], as_of_date=date(2026, 10, 28), budgets=[budget])
    assert res["cycle_key"] == "2026-11"
    assert [b["status"] for b in res["bills"]] == ["OVERDUE"]  # due Oct 27 (cycle Oct 27 – Nov 26)
    budget = dict(_utility_budget(26), cycle_key="2026-11")
    res = detect_recurring_bills([], as_of_date=date(2026, 10, 28), budgets=[budget])
    assert [b["status"] for b in res["bills"]] == ["UPCOMING"]  # due Nov 26


def test_detect_recurring_bills_clamps_due_day_to_the_month_length():
    from recurring_detector import detect_recurring_bills

    # Payday 1 (calendar month), February 2027: a bill due on the 31st is due Feb 28.
    budget = dict(_utility_budget(31), cycle_key="2027-02")
    res = detect_recurring_bills([], as_of_date=date(2027, 2, 28), budgets=[budget], payday_day=1)
    assert [b["status"] for b in res["bills"]] == ["UPCOMING"]
    res = detect_recurring_bills([], as_of_date=date(2027, 2, 27), budgets=[budget], payday_day=1)
    assert [b["status"] for b in res["bills"]] == ["UPCOMING"]


def test_fetch_household_recurring_bills_uses_household_payday(household):
    from recurring_detector import fetch_household_recurring_bills

    household.seed("budgets", [_utility_budget(12)])
    res = fetch_household_recurring_bills(HH, as_of_date=date(2026, 10, 28))
    assert res["cycle_key"] == CYCLE
    assert [b["status"] for b in res["bills"]] == ["OVERDUE"]


def test_recurring_bill_candidates_use_household_cycle(household):
    from recurring_detector import get_recurring_bill_candidates

    household.seed("budgets", [_utility_budget(12)])
    res = get_recurring_bill_candidates(HH)
    assert [c["sub_code"] for c in res["candidates"]] == ["sub-electricity"]


def test_toggle_recurring_bill_targets_household_cycle(household):
    from recurring_detector import toggle_household_recurring_bill

    household.seed("budgets", [
        dict(_utility_budget(12), id="b-old", cycle_key="2026-09", month="2026-09-01"),
        _utility_budget(12),
    ])
    res = toggle_household_recurring_bill(HH, "OPEX-UTILITIES", "sub-electricity", False, due_day=15)
    assert res["status"] == "success"
    current = next(b for b in household.tables["budgets"] if b["id"] == "b-u")
    old = next(b for b in household.tables["budgets"] if b["id"] == "b-old")
    assert current["sub_allocations"]["_recurring_config"]["sub-electricity"] == {"enabled": False, "due_day": 15}
    assert old["sub_allocations"]["_recurring_config"]["sub-electricity"]["enabled"] is True


def test_pdf_statement_uses_household_payday_and_the_selected_cycle(household, monkeypatch):
    import pdf_statement_generator

    captured = {}
    real = pdf_statement_generator.get_cycle_info_for_key

    def spy(cycle_key, payday_day=27):
        captured["args"] = (cycle_key, payday_day)
        return real(cycle_key, payday_day=payday_day)

    monkeypatch.setattr(pdf_statement_generator, "get_cycle_info_for_key", spy)
    pdf = pdf_statement_generator.generate_monthly_pdf_statement(HH)
    assert pdf[:4] == b"%PDF"
    assert captured["args"] == (CYCLE, PAYDAY)

    pdf_statement_generator.generate_monthly_pdf_statement(HH, cycle_key="2026-08")
    assert captured["args"] == ("2026-08", PAYDAY)
