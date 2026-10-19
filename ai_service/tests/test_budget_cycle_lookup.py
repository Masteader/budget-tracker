"""API-31: budget lookups for chat/receipt reallocation must use the salary cycle, not the calendar month."""

from datetime import date

from supabase_client import fetch_budget, fetch_flexible_budgets

HH = "aaaaaaaa-0000-4000-8000-000000000001"


def _budget(bid, cat, cycle_key, month, allocated, spent):
    return {"id": bid, "household_id": HH, "category_code": cat, "cycle_key": cycle_key, "month": month,
            "allocated_amount": allocated, "spent_amount": spent, "remaining_amount": allocated - spent}


def test_fetch_budget_after_payday_returns_new_cycle_row(fake_supabase):
    # Both rows carry month 2026-10-01 (ensure_household_cycle_budgets uses the date's month).
    fake_supabase.seed("budgets", [
        _budget("old", "OPEX-DINING", "2026-10", "2026-10-01", 500, 490),
        _budget("new", "OPEX-DINING", "2026-11", "2026-10-01", 500, 0),
    ])
    assert fetch_budget(HH, "OPEX-DINING", date(2026, 10, 28)).id == "new"
    assert fetch_budget(HH, "OPEX-DINING", date(2026, 10, 20)).id == "old"


def test_fetch_budget_falls_back_to_month_for_rows_without_cycle_key(fake_supabase):
    fake_supabase.seed("budgets", [_budget("legacy", "OPEX-FUEL", None, "2026-10-01", 300, 0)])
    assert fetch_budget(HH, "OPEX-FUEL", date(2026, 10, 20)).id == "legacy"


def test_flexible_budgets_are_taken_from_current_cycle(fake_supabase):
    fake_supabase.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-SHOPPING", "category": "Shopping", "keywords": [], "is_flexible": True},
        {"id": "c2", "code": "OPEX-DINING", "category": "Dining", "keywords": [], "is_flexible": True},
    ])
    fake_supabase.seed("budgets", [
        _budget("shop-old", "OPEX-SHOPPING", "2026-10", "2026-10-01", 900, 0),
        _budget("shop-new", "OPEX-SHOPPING", "2026-11", "2026-10-01", 200, 0),
    ])
    rows = fetch_flexible_budgets(HH, date(2026, 10, 28), exclude_code="OPEX-DINING")
    assert [r.id for r in rows] == ["shop-new"]
