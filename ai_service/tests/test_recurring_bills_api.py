import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from unittest.mock import patch
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)
HOUSEHOLD_ID = "test-household-uuid"


def test_recurring_bills_endpoint_missing_household():
    resp = client.get("/budgets/recurring-bills")
    assert resp.status_code == 422 or resp.status_code == 400


@patch("recurring_detector.fetch_household_recurring_bills")
def test_recurring_bills_endpoint_success(mock_fetch):
    mock_fetch.return_value = {
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

    resp = client.get(f"/budgets/recurring-bills?household_id={HOUSEHOLD_ID}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["cycle_key"] == "2026-10"
    assert data["reserved_amount"] == 100.0
    assert len(data["bills"]) == 2
    assert data["bills"][0]["merchant"] == "STC"
