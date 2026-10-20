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


@pytest.fixture(autouse=True)
def mock_supabase_for_invites(monkeypatch):
    db_tables = {
        "household_invites": [],
        "household_reimbursements": [],
        # The caller is a (non-admin) member: a member may record a settlement they are party to.
        "household_memberships": [{"household_id": HOUSEHOLD_ID, "user_id": USER_ID, "role": "member"}],
    }

    class MockQuery:
        def __init__(self, table_name):
            self.table_name = table_name
            self.items = db_tables.setdefault(table_name, [])
            self._filtered = list(self.items)

        def select(self, *args, **kwargs):
            return self

        def eq(self, col, val):
            self._filtered = [x for x in self._filtered if x.get(col) == val]
            return self

        def order(self, *args, **kwargs):
            return self

        def maybe_single(self):
            return self

        def limit(self, n):
            self._filtered = self._filtered[:n]
            return self

        def insert(self, payload):
            if isinstance(payload, list):
                self.items.extend(payload)
                self._res = payload
            else:
                self.items.append(payload)
                self._res = [payload]
            return self

        def execute(self):
            from unittest.mock import MagicMock
            res = MagicMock()
            if hasattr(self, "_res"):
                res.data = self._res
            else:
                res.data = self._filtered[0] if (hasattr(self, "_is_single") or len(self._filtered) == 1) else self._filtered
            return res

    class MockClient:
        def table(self, name):
            return MockQuery(name)

    mock_client = MockClient()
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_client)


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
        assert len(code) == 16
        assert data["role"] == "spouse"

        # Inspect invite code
        inspect_res = client.get(f"/households/invites/{code}", headers=AUTH)
        assert inspect_res.status_code == 200
        inspect_data = inspect_res.json()
        assert inspect_data["role"] == "spouse"
        assert "household_id" not in inspect_data
        assert inspect_data.get("is_valid") is True


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


def test_reimbursement_record_endpoint(monkeypatch, fake_supabase):
    hid = HOUSEHOLD_ID
    # Both parties must be members of the household (FR-B-01).
    fake_supabase.seed("household_memberships", [
        {"household_id": hid, "user_id": "00000000-0000-0000-0000-000000000001", "role": "member"},
        {"household_id": hid, "user_id": "00000000-0000-0000-0000-000000000002", "role": "member"},
    ])
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

