import os
import pytest
from unittest.mock import MagicMock
from fastapi import status
from fastapi.testclient import TestClient

def test_replace_category_endpoint(monkeypatch):
    from main import app
    import salary_cycle

    mock_replace = MagicMock(return_value={
        "status": "success",
        "old_code": "OPEX-GROCERY",
        "new_code": "CUSTOM-ELEC",
        "new_name": "Electronics & Gadgets",
        "allocated_transferred": 500.0,
    })
    monkeypatch.setattr(salary_cycle, "replace_household_category", mock_replace)
    monkeypatch.setattr("routes.budgets.replace_household_category", mock_replace)

    from unittest.mock import AsyncMock
    monkeypatch.setattr("routes.budgets.verify_household_admin_access", AsyncMock(return_value="admin-user"))

    client = TestClient(app)
    hid = "f860188e-23b5-4749-b180-868c956151a6"
    headers = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}

    payload = {
        "household_id": hid,
        "old_code": "OPEX-GROCERY",
        "new_name": "Electronics & Gadgets",
        "cycle_key": "2026-10"
    }

    try:
        resp = client.post("/budgets/categories/replace", json=payload, headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        data = resp.json()
        assert data["status"] == "success"
        assert data["new_name"] == "Electronics & Gadgets"
        assert data["new_code"] == "CUSTOM-ELEC"
    finally:
        app.dependency_overrides.clear()


def test_dynamic_household_category_matching(monkeypatch):
    import supabase_client
    from models import CostControlCode

    mock_active = [
        CostControlCode(
            code="CUSTOM-ELEC",
            category="Electronics & Gadgets",
            keywords=["jarir", "laptop"],
            is_flexible=False
        )
    ]
    monkeypatch.setattr(
        supabase_client,
        "fetch_household_cost_control_codes",
        lambda hh_id: mock_active
    )

    # Match merchant using household active codes
    matched = supabase_client.match_category("Jarir Bookstore", mock_active)
    assert matched is not None
    assert matched.code == "CUSTOM-ELEC"
