import os
import sys
import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient
from jose import jwt

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import app

client = TestClient(app)

TEST_SECRET = "test_secret_for_ci_only_do_not_use_in_prod"
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"
USER_ID = "00000000-0000-0000-0000-000000000001"

AUTH_TOKEN = jwt.encode(
    {"sub": USER_ID, "aud": "authenticated", "iss": "https://mockproject.supabase.co/auth/v1", "role": "authenticated"},
    TEST_SECRET,
    algorithm="HS256",
)
AUTH = {"Authorization": f"Bearer {AUTH_TOKEN}"}


def test_create_and_inspect_role_invite():
    hid = HOUSEHOLD_ID
    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "admin", "household_id": hid}
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
    hid = HOUSEHOLD_ID
    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "admin", "household_id": hid}
        res = client.post(
            f"/households/{hid}/invites",
            json={"role": "peer"},
            headers=AUTH,
        )
        assert res.status_code == 200
        data = res.json()
        assert data["role"] == "peer"


def test_reimbursement_record_endpoint(monkeypatch):
    hid = HOUSEHOLD_ID
    payload = {
        "household_id": hid,
        "payer_id": "00000000-0000-0000-0000-000000000001",
        "recipient_id": "00000000-0000-0000-0000-000000000002",
        "amount": 250.0,
        "payment_method": "stc_pay",
        "notes": "Weekly Panda Groceries Reimbursement",
    }
    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "member", "household_id": hid}
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

