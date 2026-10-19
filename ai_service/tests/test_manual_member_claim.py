import os
import sys
import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient
from jose import jwt

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import app

client = TestClient(app)

TEST_SECRET = os.environ.get("SUPABASE_JWT_SECRET", "super-secret-test-jwt-key-32bytes-long!")
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"
USER_ID = "00000000-0000-0000-0000-000000000001"
FATIMA_USER_ID = "00000000-0000-0000-0000-000000000002"

supabase_url = os.environ.get("SUPABASE_URL", "https://mockproject.supabase.co").rstrip("/")
expected_issuer = f"{supabase_url}/auth/v1"

AUTH_TOKEN = jwt.encode(
    {"sub": USER_ID, "aud": "authenticated", "iss": expected_issuer, "role": "authenticated"},
    TEST_SECRET,
    algorithm="HS256",
)
AUTH_HEADERS = {"Authorization": f"Bearer {AUTH_TOKEN}"}

FATIMA_TOKEN = jwt.encode(
    {"sub": FATIMA_USER_ID, "aud": "authenticated", "iss": expected_issuer, "role": "authenticated"},
    TEST_SECRET,
    algorithm="HS256",
)
FATIMA_HEADERS = {"Authorization": f"Bearer {FATIMA_TOKEN}"}


def test_create_manual_member_with_role_and_allowance(monkeypatch):
    hid = HOUSEHOLD_ID
    db_tables = {
        "household_dependents": [],
        "household_invites": [],
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

        def insert(self, payload):
            if isinstance(payload, list):
                self.items.extend(payload)
                self._res = payload
            else:
                self.items.append(payload)
                self._res = [payload]
            return self

        def update(self, payload):
            for item in self._filtered:
                item.update(payload)
            self._res = list(self._filtered)
            return self

        def delete(self):
            for item in list(self._filtered):
                if item in self.items:
                    self.items.remove(item)
            self._res = []
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

        def rpc(self, fn_name, params):
            from unittest.mock import MagicMock
            res = MagicMock()
            if fn_name == "claim_household_role_invite":
                code = params.get("p_invite_code", "").upper().strip()
                uid = params.get("p_user_id")
                invites = db_tables.get("household_invites", [])
                target = next((i for i in invites if i.get("invite_code", "").upper().strip() == code), None)
                if target:
                    target["used_by"] = uid
                    res.data = {
                        "success": True,
                        "household_id": target.get("household_id"),
                        "household_name": "Test Household",
                        "role": target.get("role"),
                        "target_member_id": target.get("target_member_id"),
                    }
                else:
                    res.data = {"success": False, "error": "Invite not found"}
            return MagicMock(execute=lambda: res)

    mock_client = MockClient()
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_client)

    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "admin", "household_id": hid}
        
        # Create manual wife profile
        res = client.post(
            f"/households/{hid}/dependents",
            json={
                "name": "Fatima",
                "relationship": "spouse",
                "avatar_icon": "wife",
                "monthly_allowance": 1500.0,
            },
            headers=AUTH_HEADERS,
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
            headers=AUTH_HEADERS,
        )
        assert inv_res.status_code == 200
        inv_data = inv_res.json()
        assert inv_data["target_member_id"] == member_id
        code = inv_data["invite_code"]

        # Inspect invite code
        inspect_res = client.get(f"/households/invites/{code}", headers=AUTH_HEADERS)
        assert inspect_res.status_code == 200
        inspect_data = inspect_res.json()
        assert inspect_data["role"] == "spouse"

        # Claim profile when Fatima joins with her account
        claim_res = client.post(
            f"/households/invites/{code}/claim",
            headers=FATIMA_HEADERS,
        )
        assert claim_res.status_code == 200
        claim_data = claim_res.json()
        assert claim_data["status"] == "success"
        assert claim_data["linked_member_id"] == member_id
        assert claim_data["financial_role"] == "spouse"

