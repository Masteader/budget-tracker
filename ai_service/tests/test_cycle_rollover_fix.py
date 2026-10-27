from datetime import date
from unittest.mock import MagicMock
import pytest
from supabase_client import ensure_household_cycle_budgets
import salary_cycle

def test_ensure_household_cycle_budgets_never_overwrites_previous_cycle(monkeypatch):
    """
    On Oct 27 (payday 27), the new cycle is 2026-11.
    If the household has an existing budget row with month='2026-10-01' and cycle_key='2026-10'
    having spent_amount=3287.0, ensure_household_cycle_budgets MUST NOT update its cycle_key to 2026-11.
    It must create a new row for 2026-11 with spent_amount=0.0.
    """
    mock_sb = MagicMock()
    # 1. Check existing for cycle_key='2026-11' -> None
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.is_.return_value.execute.return_value.data = []
    
    # 2. Latest previous cycle rows
    prev_rows = [
        {
            "id": "b-prev-1",
            "household_id": "hh-test-1",
            "category_code": "OPEX-UTIL",
            "month": "2026-10-01",
            "cycle_key": "2026-10",
            "allocated_amount": 3362.0,
            "spent_amount": 3287.0,
            "is_active": True,
        }
    ]
    mock_sb.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = prev_rows
    
    inserted_records = []
    def capture_insert(rows):
        inserted_records.extend(rows)
        m = MagicMock()
        m.data = rows
        return m
    mock_sb.table.return_value.insert.side_effect = capture_insert
    
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)
    monkeypatch.setattr("supabase_client.get_household_payday", lambda hid: 27)
    monkeypatch.setattr("supabase_client.get_household_rollover_rule", lambda hid: "fresh_start")

    # Run for target date 2026-10-27
    res = ensure_household_cycle_budgets("hh-test-1", target_date=date(2026, 10, 27), payday_day=27)

    # Verify update was NEVER called on cycle_key
    mock_sb.table.return_value.update.assert_not_called()
    
    # Verify new row was inserted with cycle_key='2026-11' and spent_amount=0.0
    assert len(inserted_records) == 1
    assert inserted_records[0]["cycle_key"] == "2026-11"
    assert inserted_records[0]["spent_amount"] == 0.0
    assert inserted_records[0]["allocated_amount"] == 3362.0
    assert inserted_records[0]["month"] == "2026-11-01"


def test_ensure_household_cycle_budgets_preserves_sub_allocations_and_fills_missing(monkeypatch):
    """
    Verifies that when rolling over from previous cycle:
    1. Sub-allocations (like Zain, electricity, rent) are preserved.
    2. If the new cycle already has 1 category (e.g. from an auto-created expense),
       the remaining categories from previous cycle are still rolled over.
    """
    mock_sb = MagicMock()
    # Household already has 1 budget in new cycle (2026-11)
    existing_in_new_cycle = [
        {
            "id": "b-new-dining",
            "household_id": "hh-test-1",
            "category_code": "OPEX-DINING",
            "month": "2026-11-01",
            "cycle_key": "2026-11",
            "allocated_amount": 0.0,
            "spent_amount": 45.0,
            "is_active": True,
        }
    ]
    # Previous cycle (2026-10) had OPEX-DINING, OPEX-UTILITIES (with sub_allocations), and OPEX-GROCERY
    prev_rows = [
        {
            "id": "b-prev-util",
            "household_id": "hh-test-1",
            "category_code": "OPEX-UTILITIES",
            "month": "2026-10-01",
            "cycle_key": "2026-10",
            "allocated_amount": 1500.0,
            "spent_amount": 1200.0,
            "sub_allocations": {"housing_rent": 1000.0, "zain_sim": 287.0},
            "account_id": "acc-123",
            "is_active": True,
        },
        {
            "id": "b-prev-groc",
            "household_id": "hh-test-1",
            "category_code": "OPEX-GROCERY",
            "month": "2026-09-28",  # Different month date in same cycle!
            "cycle_key": "2026-10",
            "allocated_amount": 2000.0,
            "spent_amount": 1800.0,
            "sub_allocations": {"meat": 500.0},
            "is_active": True,
        },
    ]

    all_db_rows = existing_in_new_cycle + prev_rows
    mock_sb.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = all_db_rows

    inserted_records = []
    def capture_insert(rows):
        inserted_records.extend(rows)
        m = MagicMock()
        m.execute.return_value.data = rows
        return m
    mock_sb.table.return_value.insert.side_effect = capture_insert

    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)
    monkeypatch.setattr("supabase_client.get_household_payday", lambda hid: 27)
    monkeypatch.setattr("supabase_client.get_household_rollover_rule", lambda hid: "fresh_start")

    res = ensure_household_cycle_budgets("hh-test-1", target_date=date(2026, 10, 27), payday_day=27)

    # OPEX-DINING was already present in new cycle, so OPEX-UTILITIES and OPEX-GROCERY should be inserted
    assert len(inserted_records) == 2
    inserted_codes = {r["category_code"] for r in inserted_records}
    assert inserted_codes == {"OPEX-UTILITIES", "OPEX-GROCERY"}

    # Sub allocations and account_id must be preserved
    util_row = next(r for r in inserted_records if r["category_code"] == "OPEX-UTILITIES")
    assert util_row["sub_allocations"] == {"housing_rent": 1000.0, "zain_sim": 287.0}
    assert util_row["account_id"] == "acc-123"
    assert util_row["allocated_amount"] == 1500.0
    assert util_row["spent_amount"] == 0.0

    groc_row = next(r for r in inserted_records if r["category_code"] == "OPEX-GROCERY")
    assert groc_row["sub_allocations"] == {"meat": 500.0}
    assert groc_row["allocated_amount"] == 2000.0

    # Total result contains existing + newly rolled over
    assert len(res) == 3


def test_get_available_cycles_includes_past_cycles_and_transactions(monkeypatch):
    """
    get_available_cycles_for_household should:
    1. Include the current cycle.
    2. Include past cycles from budgets.
    3. Include past cycles from transactions.
    4. Include at least the prior 3 cycles so the user can always navigate backward.
    5. Be sorted descending by cycle_key.
    """
    mock_sb = MagicMock()
    # Mock budgets table returning only current cycle
    def table_router(name):
        mock_table = MagicMock()
        if name == "budgets":
            mock_table.select.return_value.eq.return_value.execute.return_value.data = [
                {"cycle_key": "2026-11", "month": "2026-11-01"}
            ]
        elif name == "transactions":
            mock_table.select.return_value.eq.return_value.execute.return_value.data = [
                {"cycle_key": "2026-07"}  # historical transaction from July
            ]
        return mock_table

    mock_sb.table.side_effect = table_router
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)
    monkeypatch.setattr("supabase_client.ensure_household_cycle_budgets", lambda hid, payday_day=None: None)
    monkeypatch.setattr("supabase_client.get_household_payday", lambda hid: 27)

    # Freeze today to 2026-10-27
    monkeypatch.setattr(
        "salary_cycle.get_cycle_for_date",
        lambda d=None, payday_day=27: salary_cycle.get_cycle_info_for_key("2026-11", payday_day=27)
    )

    res = salary_cycle.get_available_cycles_for_household("hh-test-1", payday_day=27)

    cycle_keys = [c["cycle_key"] for c in res["cycles"]]
    # Must include current cycle
    assert "2026-11" in cycle_keys
    # Must include 3 prior cycles: 2026-10, 2026-09, 2026-08
    assert "2026-10" in cycle_keys
    assert "2026-09" in cycle_keys
    assert "2026-08" in cycle_keys
    # Must include cycle from transactions
    assert "2026-07" in cycle_keys

    # Must be sorted descending
    assert cycle_keys == sorted(cycle_keys, reverse=True)
    # Check is_current flag
    for c in res["cycles"]:
        if c["cycle_key"] == "2026-11":
            assert c["is_current"] is True
        else:
            assert c["is_current"] is False

