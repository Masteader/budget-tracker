from unittest.mock import MagicMock
import pytest
from salary_cycle import replace_household_category

def test_replace_category_rename_only_custom_code():
    mock_sb = MagicMock()
    # Execute chain for update
    mock_sb.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value.data = [{"code": "CUSTOM-TEST", "category": "Brand New Name"}]

    res = replace_household_category(
        household_id="hh-1",
        old_code="CUSTOM-TEST",
        new_name="Brand New Name",
        update_past_transactions=True,
        supabase_client=mock_sb,
    )

    assert res["status"] == "success"
    assert res["old_code"] == "CUSTOM-TEST"
    assert res["new_code"] == "CUSTOM-TEST"
    assert res["new_name"] == "Brand New Name"

    mock_sb.table.assert_called_with("cost_control_codes")
    mock_sb.table.return_value.update.assert_called_with({"category": "Brand New Name"})


def test_replace_category_rename_only_system_code():
    mock_sb = MagicMock()
    mock_sb.table.return_value.insert.return_value.execute.return_value.data = []
    mock_sb.table.return_value.upsert.return_value.execute.return_value.data = []
    mock_sb.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value.data = []

    res = replace_household_category(
        household_id="hh-1",
        old_code="OPEX-GROCERY",
        new_name="Groceries And Mart",
        update_past_transactions=True,
        supabase_client=mock_sb,
    )

    assert res["status"] == "success"
    assert res["old_code"] == "OPEX-GROCERY"
    assert res["new_code"].startswith("CUSTOM-")
    assert res["new_name"] == "Groceries And Mart"

    # Transactions and budgets tables must have been updated to migrate to new code
    tables_updated = [call[0][0] for call in mock_sb.table.call_args_list]
    assert "transactions" in tables_updated
    assert "budgets" in tables_updated


def test_replace_category_archive_mode():
    mock_sb = MagicMock()
    # Mock old budget query
    mock_sb.table.return_value.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
        {"id": "b-old", "allocated_amount": 500.0, "spent_amount": 100.0}
    ]
    mock_sb.table.return_value.upsert.return_value.execute.return_value.data = []
    mock_sb.table.return_value.update.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    mock_sb.table.return_value.insert.return_value.execute.return_value.data = []

    res = replace_household_category(
        household_id="hh-1",
        old_code="OPEX-GROCERY",
        new_name="Fresh Food",
        update_past_transactions=False,
        supabase_client=mock_sb,
    )

    assert res["status"] == "success"
    assert res["allocated_transferred"] == 500.0
    # Old budget envelope was deactivated
    mock_sb.table.return_value.update.assert_called_with({"is_active": False})
