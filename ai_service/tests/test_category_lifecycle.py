import os
import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient

def test_get_household_categories_split(monkeypatch):
    import salary_cycle
    mock_sb = MagicMock()
    
    # Mock cost_control_codes
    mock_sb.table("cost_control_codes").select("*").execute.return_value.data = [
        {"code": "OPEX-DINING", "category": "Dining", "is_system": True, "household_id": None, "keywords": ["al baik"]},
        {"code": "OPEX-FUEL", "category": "Fuel", "is_system": True, "household_id": None, "keywords": ["petrol"]},
        {"code": "OPEX-PETS", "category": "Pets", "is_system": True, "household_id": None, "keywords": ["cat"]},
    ]
    
    # Mock settings: Dining active, Fuel inactive, Pets has no record (new developer category defaults to inactive)
    mock_sb.table("household_category_settings").select("*").eq("household_id", "hh-123").execute.return_value.data = [
        {"category_code": "OPEX-DINING", "is_active": True},
        {"category_code": "OPEX-FUEL", "is_active": False},
    ]
    
    monkeypatch.setattr(salary_cycle, "get_client", lambda: mock_sb)
    
    result = salary_cycle.get_household_categories("hh-123")
    assert "active" in result
    assert "inactive" in result
    assert len(result["active"]) == 1
    assert result["active"][0]["code"] == "OPEX-DINING"
    
    inactive_codes = [c["code"] for c in result["inactive"]]
    assert "OPEX-FUEL" in inactive_codes
    assert "OPEX-PETS" in inactive_codes  # New developer category defaults to inactive

def test_toggle_category_activation(monkeypatch):
    import salary_cycle
    mock_sb = MagicMock()
    mock_sb.table("household_category_settings").upsert.return_value.execute.return_value.data = [{"status": "ok"}]
    mock_sb.table("budgets").update.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    monkeypatch.setattr(salary_cycle, "get_client", lambda: mock_sb)
    
    res = salary_cycle.toggle_category_status("hh-123", "OPEX-FUEL", True)
    assert res["status"] == "success"
    assert res["is_active"] is True

def test_create_household_custom_category(monkeypatch):
    import salary_cycle
    mock_sb = MagicMock()
    mock_sb.table("cost_control_codes").insert.return_value.execute.return_value.data = [{"status": "ok"}]
    mock_sb.table("household_category_settings").upsert.return_value.execute.return_value.data = [{"status": "ok"}]
    mock_sb.table("budgets").insert.return_value.execute.return_value.data = [{"status": "ok"}]
    monkeypatch.setattr(salary_cycle, "get_client", lambda: mock_sb)
    
    res = salary_cycle.create_household_custom_category(
        household_id="hh-123",
        code="FARM",
        category="Farm & Livestock",
        keywords=["goat", "hay"],
        allocated_amount=500.0,
    )
    assert res["status"] == "success"
    assert res["code"] == "CUSTOM-FARM"
    assert res["is_active"] is True

def test_categories_api_endpoints(monkeypatch):
    from main import app
    client = TestClient(app)
    hid = "f860188e-23b5-4749-b180-868c956151a6"
    headers = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}
    
    mock_data = {
        "active": [{"code": "OPEX-DINING", "category": "Dining"}],
        "inactive": [{"code": "OPEX-FUEL", "category": "Fuel"}],
    }
    monkeypatch.setattr("salary_cycle.get_household_categories", lambda household_id: mock_data)
    monkeypatch.setattr("routes.households.get_household_categories", lambda household_id: mock_data)
    monkeypatch.setattr("salary_cycle.toggle_category_status", lambda household_id, category_code, is_active: {"status": "success", "is_active": is_active})
    monkeypatch.setattr("routes.households.toggle_category_status", lambda household_id, category_code, is_active: {"status": "success", "is_active": is_active})
    monkeypatch.setattr("salary_cycle.create_household_custom_category", lambda **kw: {"status": "success", "code": kw["code"]})
    monkeypatch.setattr("routes.households.create_household_custom_category", lambda **kw: {"status": "success", "code": kw["code"]})
    
    # GET /households/{id}/categories
    resp = client.get(f"/households/{hid}/categories", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["active"][0]["code"] == "OPEX-DINING"
    
    # POST /households/{id}/categories/toggle
    resp = client.post(f"/households/{hid}/categories/toggle", json={"category_code": "OPEX-FUEL", "is_active": True}, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_active"] is True
    
    # POST /households/{id}/categories/custom
    resp = client.post(f"/households/{hid}/categories/custom", json={"code": "FARM", "category": "Farm", "allocated_amount": 200.0}, headers=headers)
    assert resp.status_code == 200


def test_archive_category_never_deletes_even_with_zero_transactions(monkeypatch):
    import salary_cycle
    mock_sb = MagicMock()
    mock_sb.table("budgets").select.return_value.eq.return_value.eq.return_value.execute.return_value.data = [
        {"id": "b-1", "category_code": "CUSTOM-FARM", "allocated_amount": 200.0}
    ]
    mock_sb.table("budgets").update.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    mock_sb.table("household_category_settings").upsert.return_value.execute.return_value.data = [{"status": "ok"}]
    
    monkeypatch.setattr(salary_cycle, "get_client", lambda: mock_sb)
    
    res = salary_cycle.archive_category_for_household("hh-123", "CUSTOM-FARM")
    assert res["status"] == "success"
    assert res["category_code"] == "CUSTOM-FARM"
    
    # Verify no delete operations were performed on any category table
    assert mock_sb.table("cost_control_codes").delete.called is False
    assert mock_sb.table("budgets").delete.called is False
    assert mock_sb.table("cost_control_sub_categories").delete.called is False


def test_entertainment_and_gov_active_by_default(monkeypatch):
    import salary_cycle
    mock_sb = MagicMock()
    mock_sb.table("cost_control_codes").select("*").execute.return_value.data = [
        {"code": "OPEX-ENTERTAINMENT", "category": "Entertainment", "is_system": True, "household_id": None},
        {"code": "OPEX-GOV", "category": "Government & Fees", "is_system": True, "household_id": None},
        {"code": "CUSTOM-TESTING", "category": "testing", "is_system": False, "household_id": "hh-123"},
    ]
    mock_sb.table("household_category_settings").select("*").eq("household_id", "hh-123").execute.return_value.data = []
    monkeypatch.setattr(salary_cycle, "get_client", lambda: mock_sb)

    result = salary_cycle.get_household_categories("hh-123")
    active_codes = [c["code"] for c in result["active"]]
    inactive_codes = [c["code"] for c in result["inactive"]]

    # Entertainment and Gov must be active by default
    assert "OPEX-ENTERTAINMENT" in active_codes
    assert "OPEX-GOV" in active_codes
    # Testing categories must be purged completely
    assert "CUSTOM-TESTING" not in active_codes
    assert "CUSTOM-TESTING" not in inactive_codes


def test_toggle_reactivates_budgets_table(monkeypatch):
    import salary_cycle
    mock_sb = MagicMock()
    mock_sb.table("household_category_settings").upsert.return_value.execute.return_value.data = [{"status": "ok"}]
    mock_sb.table("budgets").update.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
    monkeypatch.setattr(salary_cycle, "get_client", lambda: mock_sb)

    # Activating category
    res = salary_cycle.toggle_category_status("hh-123", "OPEX-ENTERTAINMENT", True)
    assert res["status"] == "success"
    # Ensure budgets update was called with is_active = True
    mock_sb.table("budgets").update.assert_called_with({"is_active": True})

