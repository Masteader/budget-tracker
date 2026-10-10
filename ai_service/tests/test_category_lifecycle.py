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
    
    mock_data = {
        "active": [{"code": "OPEX-DINING", "category": "Dining"}],
        "inactive": [{"code": "OPEX-FUEL", "category": "Fuel"}],
    }
    monkeypatch.setattr("salary_cycle.get_household_categories", lambda household_id: mock_data)
    monkeypatch.setattr("salary_cycle.toggle_category_status", lambda household_id, category_code, is_active: {"status": "success", "is_active": is_active})
    monkeypatch.setattr("salary_cycle.create_household_custom_category", lambda **kw: {"status": "success", "code": kw["code"]})
    
    # GET /households/{id}/categories
    resp = client.get("/households/hh-123/categories")
    assert resp.status_code == 200
    assert resp.json()["active"][0]["code"] == "OPEX-DINING"
    
    # POST /households/{id}/categories/toggle
    resp = client.post("/households/hh-123/categories/toggle", json={"category_code": "OPEX-FUEL", "is_active": True})
    assert resp.status_code == 200
    assert resp.json()["is_active"] is True
    
    # POST /households/{id}/categories/custom
    resp = client.post("/households/hh-123/categories/custom", json={"code": "FARM", "category": "Farm", "allocated_amount": 200.0})
    assert resp.status_code == 200

