import os
import sys
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import app

client = TestClient(app)
AUTH = {"X-App-Token": "bt_sec_99a81f3d4c72e01b88e2"}


def test_create_manual_member_with_role_and_allowance():
    hid = "hh_manual_test_123"
    # Create manual wife profile
    res = client.post(
        f"/households/{hid}/dependents",
        json={
            "name": "Fatima",
            "relationship": "spouse",
            "avatar_icon": "wife",
            "monthly_allowance": 1500.0,
        },
        headers=AUTH,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["dependent"]["name"] == "Fatima"
    assert data["dependent"]["relationship"] == "spouse"
    assert data["dependent"]["monthly_allowance"] == 1500.0
    member_id = data["dependent"]["id"]

    # Generate targeted invite for Fatima
    inv_res = client.post(
        f"/households/{hid}/invites",
        json={
            "role": "spouse",
            "target_member_id": member_id,
        },
        headers=AUTH,
    )
    assert inv_res.status_code == 200
    inv_data = inv_res.json()
    assert inv_data["target_member_id"] == member_id
    code = inv_data["invite_code"]

    # Inspect invite code shows target member info
    inspect_res = client.get(f"/households/invites/{code}", headers=AUTH)
    assert inspect_res.status_code == 200
    inspect_data = inspect_res.json()
    assert inspect_data["target_member_id"] == member_id
    assert inspect_data["role"] == "spouse"

    # Claim profile when Fatima joins with her account
    claim_res = client.post(
        f"/households/invites/{code}/claim",
        json={"user_id": "usr_fatima_live_456"},
        headers=AUTH,
    )
    assert claim_res.status_code == 200
    claim_data = claim_res.json()
    assert claim_data["status"] == "success"
    assert claim_data["linked_member_id"] == member_id
    assert claim_data["financial_role"] == "spouse"
