import pytest
from datetime import date
from unittest.mock import MagicMock
from supabase_client import ensure_household_cycle_budgets
from salary_cycle import is_allocation_metadata_key, numeric_sub_allocations

HID = "f860188e-23b5-4749-b180-868c956151a6"

def test_sinking_fund_metadata_key_recognized():
    assert is_allocation_metadata_key("_sinking_fund") is True
    assert is_allocation_metadata_key("_recurring_config") is True
    assert is_allocation_metadata_key("car_maintenance") is False


def test_numeric_sub_allocations_ignores_sinking_fund_dict():
    raw = {
        "car_maintenance": 100.0,
        "gas_fuel": 500.0,
        "_sinking_fund": {
            "car_maintenance": {"accumulate": True, "base_amount": 100.0}
        }
    }
    cleaned = numeric_sub_allocations(raw)
    assert cleaned == {"car_maintenance": 100.0, "gas_fuel": 500.0}


def test_sinking_fund_accumulates_and_resets(monkeypatch):
    """
    Test scenario:
    - Base car maintenance: 100 SAR, accumulate: True.
    - Month 1: 0 spent -> rolls over as 200 SAR (100 base + 100 carryover).
    - Month 2: 0 spent -> rolls over as 300 SAR (100 base + 200 carryover).
    - Month 3: spent 300 SAR -> rolls over as 100 SAR (resets to base!).
    """
    mock_sb = MagicMock()
    swept_surplus = []

    def mock_sweep(hid, amount, cycle):
        swept_surplus.append(amount)

    monkeypatch.setattr("supabase_client.add_household_savings_surplus", mock_sweep)
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)
    monkeypatch.setattr("supabase_client.get_household_payday", lambda hid: 27)
    monkeypatch.setattr("supabase_client.get_household_rollover_rule", lambda hid: "send_to_savings")

    # --- Step 1: Cycle 1 (2026-09) -> Cycle 2 (2026-10) ---
    c1_rows = [
        {
            "id": "b-c1-oil",
            "household_id": HID,
            "category_code": "OPEX-FUEL",
            "month": "2026-09-01",
            "cycle_key": "2026-09",
            "allocated_amount": 100.0,
            "spent_amount": 0.0,
            "sub_allocations": {
                "car_maintenance": 100.0,
                "_sinking_fund": {
                    "car_maintenance": {"accumulate": True, "base_amount": 100.0}
                }
            },
            "is_active": True,
        },
        {
            "id": "b-c1-dining",
            "household_id": HID,
            "category_code": "OPEX-DINING",
            "month": "2026-09-01",
            "cycle_key": "2026-09",
            "allocated_amount": 500.0,
            "spent_amount": 400.0,
            "sub_allocations": {},
            "is_active": True,
        }
    ]

    # Mock no existing rows in 2026-10
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.is_.return_value.execute.return_value.data = []
    # Previous rows returns c1_rows
    mock_sb.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = c1_rows
    def capture_insert(rows):
        m = MagicMock()
        m.execute.return_value.data = rows
        return m
    mock_sb.table.return_value.insert.side_effect = capture_insert

    res_c2 = ensure_household_cycle_budgets(HID, target_date=date(2026, 9, 27), payday_day=27)

    oil_c2 = next(b for b in res_c2 if b["category_code"] == "OPEX-FUEL")
    assert oil_c2["allocated_amount"] == 200.0
    assert oil_c2["sub_allocations"]["car_maintenance"] == 200.0

    dining_c2 = next(b for b in res_c2 if b["category_code"] == "OPEX-DINING")
    assert dining_c2["allocated_amount"] == 500.0

    # Verify surplus swept to savings: dining unspent (500 - 400 = 100) was swept.
    # Oil unspent (100) was NOT swept to savings because it rolled over!
    assert 100.0 in swept_surplus

    # --- Step 2: Cycle 2 (2026-10) -> Cycle 3 (2026-11) ---
    c2_rows = [
        {
            "id": "b-c2-oil",
            "household_id": HID,
            "category_code": "OPEX-FUEL",
            "month": "2026-10-01",
            "cycle_key": "2026-10",
            "allocated_amount": 200.0,
            "spent_amount": 0.0,
            "sub_allocations": {
                "car_maintenance": 200.0,
                "_sinking_fund": {
                    "car_maintenance": {"accumulate": True, "base_amount": 100.0}
                }
            },
            "is_active": True,
        }
    ]
    mock_sb.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = c2_rows
    res_c3 = ensure_household_cycle_budgets(HID, target_date=date(2026, 10, 27), payday_day=27)

    oil_c3 = next(b for b in res_c3 if b["category_code"] == "OPEX-FUEL")
    assert oil_c3["allocated_amount"] == 300.0
    assert oil_c3["sub_allocations"]["car_maintenance"] == 300.0

    # --- Step 3: Cycle 3 (2026-11) -> Cycle 4 (2026-12) ---
    # Spent all 300 SAR in Cycle 3!
    c3_rows = [
        {
            "id": "b-c3-oil",
            "household_id": HID,
            "category_code": "OPEX-FUEL",
            "month": "2026-11-01",
            "cycle_key": "2026-11",
            "allocated_amount": 300.0,
            "spent_amount": 300.0,
            "sub_allocations": {
                "car_maintenance": 300.0,
                "_sinking_fund": {
                    "car_maintenance": {"accumulate": True, "base_amount": 100.0}
                }
            },
            "is_active": True,
        }
    ]
    mock_sb.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = c3_rows
    res_c4 = ensure_household_cycle_budgets(HID, target_date=date(2026, 11, 27), payday_day=27)

    oil_c4 = next(b for b in res_c4 if b["category_code"] == "OPEX-FUEL")
    # Resets cleanly back to base 100.0!
    assert oil_c4["allocated_amount"] == 100.0
    assert oil_c4["sub_allocations"]["car_maintenance"] == 100.0
