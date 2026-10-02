import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from dotenv import load_dotenv
load_dotenv()

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)
AUTH_HEADERS = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "bt_sec_99a81f3d4c72e01b88e2")}
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"


def test_get_cycles_endpoint():
    resp = client.get(f"/budgets/cycles?household_id={HOUSEHOLD_ID}", headers=AUTH_HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert "current_cycle" in data
    assert data["current_cycle"]["cycle_key"] == "2026-10"
    assert "cycles" in data
    assert len(data["cycles"]) >= 1


def test_get_category_breakdown():
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


def test_add_and_archive_category():
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

