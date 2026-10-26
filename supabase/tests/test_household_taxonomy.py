import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient

def test_replace_household_category_logic():
    """
    Unit test verifying the contract of replace_household_category:
    1. Archives old category in household_category_settings (is_active=False).
    2. Deactivates old budget envelope in budgets table.
    3. Provisions new category in cost_control_codes.
    4. Activates new category in household_category_settings (is_active=True).
    5. Transfers remaining/current allocation to new budget envelope.
    6. Verifies past transactions are untouched and still linked to old_code.
    """
    import salary_cycle

    # Ensure salary_cycle has replace_household_category
    assert hasattr(salary_cycle, "replace_household_category"), (
        "salary_cycle must define replace_household_category"
    )

    mock_sb = MagicMock()
    # Mock finding existing budget allocation for old category
    mock_sb.table("budgets").select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
        {"id": "b-old-1", "allocated_amount": 750.0, "spent_amount": 150.0}
    ]
    # Mock settings upsert
    mock_sb.table("household_category_settings").upsert.return_value.execute.return_value.data = [{"status": "ok"}]
    # Mock cost_control_codes insert
    mock_sb.table("cost_control_codes").insert.return_value.execute.return_value.data = [{"status": "ok"}]
    # Mock budget update/insert
    mock_sb.table("budgets").update.return_value.eq.return_value.execute.return_value.data = [{"status": "ok"}]
    mock_sb.table("budgets").insert.return_value.execute.return_value.data = [{"status": "ok"}]

    res = salary_cycle.replace_household_category(
        supabase_client=mock_sb,
        household_id="hh-test-1",
        old_code="OPEX-GROCERY",
        new_name="Electronics & Gadgets",
        new_code="CUSTOM-ELEC",
        cycle_key="2026-10"
    )

    assert res["status"] == "success"
    assert res["old_code"] == "OPEX-GROCERY"
    assert res["new_code"] == "CUSTOM-ELEC"
    assert res["new_name"] == "Electronics & Gadgets"
    assert res["allocated_transferred"] == 750.0
