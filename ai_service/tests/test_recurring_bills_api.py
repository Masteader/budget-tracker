import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from unittest.mock import patch
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"
AUTH_HEADERS = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}


def test_recurring_bills_endpoint_missing_household():
    resp = client.get("/budgets/recurring-bills")
    assert resp.status_code == 422 or resp.status_code == 400


@patch("routes.budgets.fetch_household_recurring_bills")
@patch("recurring_detector.fetch_household_recurring_bills")
def test_recurring_bills_endpoint_success(mock_fetch, mock_routes_fetch):
    mock_data = {
        "cycle_key": "2026-10",
        "cycle_label": "October 2026 Budget",
        "total_recurring_monthly": 450.0,
        "paid_this_cycle": 350.0,
        "reserved_amount": 100.0,
        "bills": [
            {
                "merchant": "STC",
                "normalized_merchant": "STC",
                "category_code": "OPEX-UTILITIES",
                "average_amount": 350.0,
                "expected_day_of_month": 28,
                "status": "PAID_THIS_CYCLE",
                "last_paid_date": "2026-09-28",
                "cadence": "monthly",
            },
            {
                "merchant": "Netflix",
                "normalized_merchant": "Netflix",
                "category_code": "OPEX-ENTERTAINMENT",
                "average_amount": 100.0,
                "expected_day_of_month": 12,
                "status": "UPCOMING",
                "last_paid_date": "2026-09-12",
                "cadence": "monthly",
            },
        ],
    }
    mock_fetch.return_value = mock_data
    mock_routes_fetch.return_value = mock_data

    resp = client.get(f"/budgets/recurring-bills?household_id={HOUSEHOLD_ID}", headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert data["cycle_key"] == "2026-10"
    assert data["reserved_amount"] == 100.0
    assert len(data["bills"]) == 2
    assert data["bills"][0]["merchant"] == "STC"


def test_toggle_household_recurring_bill_selects_cycle_columns(monkeypatch):
    import recurring_detector
    from unittest.mock import MagicMock

    mock_sb = MagicMock()
    mock_select = mock_sb.table("budgets").select.return_value.eq.return_value.eq.return_value.execute
    mock_select.return_value.data = [
        {
            "id": "b-123",
            "category_code": "OPEX-UTILITIES",
            "cycle_key": "2026-10",
            "month": "2026-10-01",
            "sub_allocations": {},
        }
    ]
    mock_sb.table("budgets").update.return_value.eq.return_value.execute.return_value.data = [{"status": "ok"}]
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_sb)

    # When cycle_info returns 2026-10
    monkeypatch.setattr("recurring_detector.get_cycle_for_date", lambda: {"cycle_key": "2026-10"})

    res = recurring_detector.toggle_household_recurring_bill(
        household_id="hh-test",
        category_code="OPEX-UTILITIES",
        sub_code="ELECTRICITY",
        is_recurring=True,
    )

    # Verify that select was called with cycle_key and month
    mock_sb.table("budgets").select.assert_called_with("id, sub_allocations, cycle_key, month")
    assert res["status"] == "success"
    assert res["is_recurring"] is True
