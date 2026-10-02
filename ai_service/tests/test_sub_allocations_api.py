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


def test_sub_allocations_save_and_breakdown():
    # 1. Post sub-allocations for OPEX-UTILITIES
    payload = {
        "household_id": HOUSEHOLD_ID,
        "category_code": "OPEX-UTILITIES",
        "cycle_key": "2026-10",
        "sub_allocations": {
            "housing_rent": 3000.0,
            "electricity_sec": 350.0,
            "fiber_internet": 250.0,
            "mobile_sims": 100.0,
            "water_municipal": 50.0,
        },
    }
    resp = client.post("/budgets/sub-allocations", json=payload, headers=AUTH_HEADERS)
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["status"] == "success"
    assert data["category_code"] == "OPEX-UTILITIES"
    assert data["allocated_amount"] == 3750.0
    assert data["sub_allocations"]["housing_rent"] == 3000.0

    # 2. Verify breakdown reflects sub-allocated amounts
    breakdown_resp = client.get(
        f"/budgets/breakdown?household_id={HOUSEHOLD_ID}&cycle_key=2026-10",
        headers=AUTH_HEADERS,
    )
    assert breakdown_resp.status_code == 200
    b_data = breakdown_resp.json()
    
    # Find OPEX-UTILITIES
    util_cat = next((c for c in b_data["categories"] if c["category_code"] == "OPEX-UTILITIES"), None)
    assert util_cat is not None
    assert util_cat["allocated_amount"] == 3750.0
    
    sub_map = {s["sub_code"]: s for s in util_cat["sub_categories"]}
    assert "housing_rent" in sub_map
    assert sub_map["housing_rent"]["allocated_amount"] == 3000.0
    assert "electricity_sec" in sub_map
    assert sub_map["electricity_sec"]["allocated_amount"] == 350.0
