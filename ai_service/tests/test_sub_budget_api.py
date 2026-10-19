import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from dotenv import load_dotenv
load_dotenv()

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)
AUTH_HEADERS = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"


def test_get_cycles_endpoint():
    resp = client.get(f"/budgets/cycles?household_id={HOUSEHOLD_ID}", headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert "current_cycle" in data
    assert data["current_cycle"]["cycle_key"] == "2026-10"
    assert "cycles" in data
    assert len(data["cycles"]) >= 1


def test_get_category_breakdown(monkeypatch):
    mock_data = {
        "cycle_key": "2026-10",
        "categories": [
            {
                "category_code": "OPEX-UTILITIES",
                "allocated_amount": 500.0,
                "sub_categories": [],
            }
        ],
    }
    monkeypatch.setattr("routes.budgets.get_cycle_breakdown", lambda *args, **kw: mock_data)

    resp = client.get(f"/budgets/breakdown?household_id={HOUSEHOLD_ID}&cycle_key=2026-10", headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert "cycle_key" in data
    assert "categories" in data
    assert len(data["categories"]) >= 1

    # Check structure of each category
    cat = data["categories"][0]
    assert "category_code" in cat
    assert "allocated_amount" in cat
    assert "sub_categories" in cat


def test_add_and_archive_category(monkeypatch):
    monkeypatch.setattr("routes.budgets.add_category_and_budget", lambda req: {"status": "success", "category_code": req.code})
    monkeypatch.setattr("routes.budgets.archive_category_for_household", lambda hid, code: {"status": "success"})

    payload = {
        "household_id": HOUSEHOLD_ID,
        "code": "OPEX-TESTING",
        "category": "Testing Category",
        "allocated_amount": 350.0,
        "is_flexible": True,
        "keywords": ["testitem", "testing"],
    }
    resp = client.post("/budgets/categories", json=payload, headers=AUTH_HEADERS)
    assert resp.status_code == 200
    assert resp.json()["category_code"] == "OPEX-TESTING"

    # Archive category
    del_resp = client.delete(f"/budgets/categories/OPEX-TESTING?household_id={HOUSEHOLD_ID}", headers=AUTH_HEADERS)
    assert del_resp.status_code == 200
    assert del_resp.json()["status"] == "success"


def test_add_sub_category_endpoint(monkeypatch):
    mock_res = {
        "status": "success",
        "category_code": "OPEX-UTILITIES",
        "sub_allocations": {"sub-district-cooling": 120.0},
    }
    monkeypatch.setattr("routes.budgets.add_sub_category_for_household", lambda **kw: mock_res)

    payload = {
        "household_id": HOUSEHOLD_ID,
        "parent_code": "OPEX-UTILITIES",
        "name_en": "District Cooling",
        "allocated_amount": 120.0,
        "cycle_key": "2026-10",
    }
    resp = client.post("/budgets/sub-categories", json=payload, headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "success"
    assert data["category_code"] == "OPEX-UTILITIES"
    assert "sub_allocations" in data
    assert "sub-district-cooling" in data["sub_allocations"]
    assert data["sub_allocations"]["sub-district-cooling"] == 120.0


def test_rename_and_remove_sub_category(monkeypatch, fake_supabase):
    # Renaming is only allowed under a household-owned custom parent category (API-03).
    fake_supabase.seed("cost_control_codes", [
        {"id": "c-utils", "code": "OPEX-UTILITIES", "category": "Utilities", "keywords": [],
         "is_flexible": False, "household_id": HOUSEHOLD_ID, "is_system": False},
    ])
    monkeypatch.setattr("routes.budgets.add_sub_category_for_household", lambda **kw: {"status": "success"})
    monkeypatch.setattr("routes.budgets.rename_sub_category", lambda **kw: {"status": "success", "name_en": kw.get("name_en")})
    monkeypatch.setattr("routes.budgets.remove_sub_category_for_household", lambda **kw: {"status": "success"})

    # 1. Add custom sub-category
    add_payload = {
        "household_id": HOUSEHOLD_ID,
        "parent_code": "OPEX-UTILITIES",
        "name_en": "Chilled Water",
        "allocated_amount": 75.0,
        "cycle_key": "2026-10",
    }
    resp = client.post("/budgets/sub-categories", json=add_payload, headers=AUTH_HEADERS)
    assert resp.status_code == 200

    # 2. Rename sub-category
    rename_payload = {
        "parent_code": "OPEX-UTILITIES",
        "sub_code": "sub-chilled-water",
        "name_en": "Central Chilled Water",
    }
    patch_resp = client.patch("/budgets/sub-categories", json=rename_payload, headers=AUTH_HEADERS)
    assert patch_resp.status_code == 200
    assert patch_resp.json()["name_en"] == "Central Chilled Water"

    # 3. Remove sub-category
    del_resp = client.delete(
        f"/budgets/sub-categories?household_id={HOUSEHOLD_ID}&parent_code=OPEX-UTILITIES&sub_code=sub-chilled-water&cycle_key=2026-10",
        headers=AUTH_HEADERS,
    )
    assert del_resp.status_code == 200
    assert del_resp.json()["status"] == "success"


