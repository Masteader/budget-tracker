import os
import sys
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import app

client = TestClient(app)
AUTH = {"X-App-Token": "bt_sec_99a81f3d4c72e01b88e2"}


def test_create_and_inspect_role_invite():
    hid = "hh_test_inv_123"
    # Create spouse invite
    res = client.post(
        f"/households/{hid}/invites",
        json={"role": "spouse"},
        headers=AUTH,
    )
    assert res.status_code == 200
    data = res.json()
    code = data["invite_code"]
    assert len(code) == 8
    assert data["role"] == "spouse"

    # Inspect invite code
    inspect_res = client.get(f"/households/invites/{code}", headers=AUTH)
    assert inspect_res.status_code == 200
    inspect_data = inspect_res.json()
    assert inspect_data["role"] == "spouse"
    assert inspect_data["household_id"] == hid


def test_create_peer_roommate_invite():
    hid = "hh_flatmate_456"
    res = client.post(
        f"/households/{hid}/invites",
        json={"role": "peer"},
        headers=AUTH,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["role"] == "peer"


def test_reimbursement_record_endpoint(monkeypatch):
    hid = "hh_reimburse_789"
    payload = {
        "household_id": hid,
        "payer_id": "husband_01",
        "recipient_id": "wife_01",
        "amount": 250.0,
        "payment_method": "stc_pay",
        "notes": "Weekly Panda Groceries Reimbursement",
    }
    res = client.post(
        f"/households/{hid}/reimbursements",
        json=payload,
        headers=AUTH,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert data["amount"] == 250.0
    assert data["is_settlement"] is True
