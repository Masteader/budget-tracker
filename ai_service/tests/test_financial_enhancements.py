"""
Unit and integration tests for:
- Phase 1: Salary cycle forecaster and affordability simulation
- Phase 2: Partner settlement engine
- Phase 3: Grocery price intelligence
"""
from datetime import date
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

from salary_cycle import get_salary_cycle_dates, adjust_saudi_payday, simulate_affordability
from settlement_engine import calculate_partner_settlement
from price_tracker import get_grocery_price_history, _normalize_item_name
from main import app

client = TestClient(app)
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"

def test_saudi_payday_weekend_adjustment():
    # Friday 2026-11-27 -> should shift to Thursday 2026-11-26
    fri_27 = date(2026, 11, 27)
    assert fri_27.weekday() == 4  # Friday
    adjusted = adjust_saudi_payday(fri_27)
    assert adjusted == date(2026, 11, 26)

    # Saturday 2026-06-27 -> should shift to Sunday 2026-06-28
    sat_27 = date(2026, 6, 27)
    assert sat_27.weekday() == 5  # Saturday
    adjusted_sat = adjust_saudi_payday(sat_27)
    assert adjusted_sat == date(2026, 6, 28)

    # Sunday 2026-09-27 -> remains Sunday 2026-09-27
    sun_27 = date(2026, 9, 27)
    assert sun_27.weekday() == 6
    assert adjust_saudi_payday(sun_27) == sun_27

def test_salary_cycle_dates():
    # Test day after 27th (e.g. 29th)
    d = date(2026, 9, 29)
    res = get_salary_cycle_dates(d)
    assert res["cycle_start"] == "2026-09-27"
    assert res["days_elapsed"] >= 1
    assert "payday" in res

@patch("salary_cycle.get_salary_cycle_forecast")
@patch("salary_cycle.fetch_flexible_budgets")
@patch("salary_cycle.get_client")
def test_simulate_affordability(mock_client, mock_flexible, mock_forecast):
    mock_forecast.return_value = {
        "total_remaining": 5000.0,
        "daily_remaining_allowance": 250.0,
        "cycle": {"days_remaining": 20},
    }
    mock_flexible.return_value = []
    mock_table = MagicMock()
    mock_client.return_value.table.return_value = mock_table
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = {
        "remaining_amount": 2000.0
    }

    # Within category budget
    res = simulate_affordability(HOUSEHOLD_ID, target_amount=1200.0, item_name="iPad", category_code="OPEX-SHOPPING")
    assert res["verdict"] == "comfortable"
    assert res["is_affordable"] is True
    assert "1200" in str(res["target_amount"])

    # Unaffordable
    res_unaffordable = simulate_affordability(HOUSEHOLD_ID, target_amount=8000.0, item_name="Car", category_code="OPEX-SHOPPING")
    assert res_unaffordable["verdict"] == "unaffordable"
    assert res_unaffordable["is_affordable"] is False

@patch("settlement_engine.get_client")
def test_partner_settlement_calculation(mock_client):
    mock_table = MagicMock()
    mock_client.return_value.table.return_value = mock_table
    mock_table.select.return_value.eq.return_value.gte.return_value.order.return_value.execute.return_value.data = [
        {"id": "1", "amount": 300.0, "category_code": "OPEX-GROCERY", "spent_by": "me", "timestamp": "2026-09-28T10:00:00Z"},
        {"id": "2", "amount": 100.0, "category_code": "OPEX-GROCERY", "spent_by": "partner", "timestamp": "2026-09-28T12:00:00Z"},
    ]

    res = calculate_partner_settlement(HOUSEHOLD_ID, split_ratio=0.50)
    assert res["total_shared_expenses"] == 400.0
    assert res["shared_paid_by_me"] == 300.0
    assert res["shared_paid_by_partner"] == 100.0
    assert res["fair_share_me"] == 200.0
    assert res["who_owes"] == "partner_owes_me"
    assert res["settlement_amount"] == 100.0
    assert "STC Pay" in res["stc_pay_note"] or "Settlement" in res["stc_pay_note"]

def test_item_normalization_and_price_history():
    assert _normalize_item_name("حليب المراعي 2 لتر") == "Milk"
    assert _normalize_item_name("fresh eggs 30 pack") == "Eggs"
    assert _normalize_item_name("صدور دجاج اليوم") == "Chicken"

@patch("price_tracker.get_client")
def test_get_grocery_price_history(mock_client):
    mock_table = MagicMock()
    mock_client.return_value.table.return_value = mock_table
    mock_table.select.return_value.eq.return_value.not_.is_.return_value.order.return_value.execute.return_value.data = [
        {
            "id": "1",
            "merchant": "Panda",
            "timestamp": "2026-09-01T10:00:00Z",
            "items": [{"name": "حليب المراعي", "price": 14.0, "quantity": 1}],
        },
        {
            "id": "2",
            "merchant": "Danube",
            "timestamp": "2026-09-15T10:00:00Z",
            "items": [{"name": "Almarai Milk", "price": 16.0, "quantity": 1}],
        },
    ]

    summary = get_grocery_price_history(HOUSEHOLD_ID, item_filter="Milk")
    assert len(summary) == 1
    assert summary[0]["item_name"] == "Milk"
    assert summary[0]["min_price"] == 14.0
    assert summary[0]["max_price"] == 16.0
    assert summary[0]["cheapest_store"] == "Panda"
    assert summary[0]["inflation_pct"] > 0
