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


def test_create_manual_member_with_role_and_allowance():
    hid = HOUSEHOLD_ID
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

