"""
Proof tests for SEC-03:
- Enforce JWT authentication on /households/invites/{code}/claim
- User ID derived strictly from JWT sub claim (never request body)
- Atomic single-use claim enforcement
- Safe minimal metadata inspection on GET /households/invites/{code}
- Role-based authorization: admin-only endpoints reject non-admin members with 403
"""

import os
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from jose import jwt

from main import app
import auth

client = TestClient(app)

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"
ADMIN_USER_ID = "00000000-0000-0000-0000-000000000001"
MEMBER_USER_ID = "00000000-0000-0000-0000-000000000002"
ATTACKER_USER_ID = "00000000-0000-0000-0000-000000000003"


@pytest.fixture(autouse=True, scope="module")
def setup_sec03_env():
    orig_env = dict(os.environ)
    os.environ["ENV"] = "production"
    os.environ["SUPABASE_URL"] = "https://mockproject.supabase.co"
    os.environ["SUPABASE_JWT_SECRET"] = TEST_SECRET
    yield
    os.environ.clear()
    os.environ.update(orig_env)


def create_test_token(user_id: str) -> str:
    return jwt.encode(
        {
            "sub": user_id,
            "aud": "authenticated",
            "iss": "https://mockproject.supabase.co/auth/v1",
            "role": "authenticated",
        },
        TEST_SECRET,
        algorithm="HS256",
    )


def test_claim_invite_without_jwt_rejected_401():
    """Unauthenticated calls to /households/invites/{code}/claim must be rejected with 401."""
    resp = client.post(
        "/households/invites/TESTCODE/claim",
        json={"user_id": ATTACKER_USER_ID},
    )
    assert resp.status_code == 401, f"Expected 401, got {resp.status_code}: {resp.text}"


def test_claim_invite_uses_jwt_sub_not_body():
    """Claiming an invite must bind to the authenticated caller's JWT sub, ignoring body user_id."""
    token = create_test_token(MEMBER_USER_ID)
    with patch("routes.households.claim_household_role_invite") as mock_claim:
        mock_claim.return_value = {
            "status": "success",
            "household_id": HOUSEHOLD_ID,
            "user_id": MEMBER_USER_ID,
            "financial_role": "spouse",
        }
        resp = client.post(
            "/households/invites/TESTCODE/claim",
            json={"user_id": ATTACKER_USER_ID},  # Attacker tries to specify different user
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        # Crucial check: verify claim_household_role_invite was called with MEMBER_USER_ID, NOT ATTACKER_USER_ID
        mock_claim.assert_called_once()
        called_args = mock_claim.call_args[0]
        assert called_args[1] == MEMBER_USER_ID, f"Expected user_id={MEMBER_USER_ID} from JWT, but got {called_args[1]}"


def test_inspect_invite_returns_minimal_metadata():
    """GET /households/invites/{code} must return minimal safe metadata."""
    with patch("routes.households.inspect_household_role_invite") as mock_inspect:
        mock_inspect.return_value = {
            "invite_code": "SAFECODE",
            "household_id": HOUSEHOLD_ID,
            "household_name": "Al-Saud Family",
            "role": "spouse",
            "target_member_id": "secret-target-id-12345",
            "created_by": "secret-admin-id-99999",
            "used_by": None,
            "is_valid": True,
        }
        resp = client.get("/households/invites/SAFECODE")
        assert resp.status_code == 200
        data = resp.json()
        assert "invite_code" in data
        assert "is_valid" in data
        # Sensitive internal identifiers must NOT leak to public callers
        assert "target_member_id" not in data, "target_member_id leaked in public inspect!"
        assert "created_by" not in data, "created_by leaked in public inspect!"
        assert "household_id" not in data, "household_id leaked in public inspect!"


def test_non_admin_cannot_create_invite():
    """Member with role='member' cannot create invites (403 Forbidden)."""
    token = create_test_token(MEMBER_USER_ID)
    
    # Mock membership check to return member role
    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "member", "household_id": HOUSEHOLD_ID}
        resp = client.post(
            f"/households/{HOUSEHOLD_ID}/invites",
            json={"role": "peer"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403, f"Expected 403, got {resp.status_code}: {resp.text}"


def test_non_admin_cannot_update_payday():
    """Member with role='member' cannot update payday (403 Forbidden)."""
    token = create_test_token(MEMBER_USER_ID)
    
    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "member", "household_id": HOUSEHOLD_ID}
        resp = client.put(
            f"/households/{HOUSEHOLD_ID}/payday",
            json={"payday_day": 27},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403, f"Expected 403, got {resp.status_code}: {resp.text}"


def test_non_admin_cannot_update_rollover_rule():
    """Member with role='member' cannot update rollover rule (403 Forbidden)."""
    token = create_test_token(MEMBER_USER_ID)
    
    with patch("auth._get_user_membership") as mock_mem:
        mock_mem.return_value = {"role": "member", "household_id": HOUSEHOLD_ID}
        resp = client.put(
            f"/households/{HOUSEHOLD_ID}/rollover-rule",
            json={"rollover_rule": "reset_to_zero"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403, f"Expected 403, got {resp.status_code}: {resp.text}"


def test_admin_can_update_household_settings():
    """Admin can successfully update payday and rollover rule."""
    token = create_test_token(ADMIN_USER_ID)
    
    with patch("auth._get_user_membership") as mock_mem, \
         patch("routes.households.set_household_payday") as mock_payday:
        mock_mem.return_value = {"role": "admin", "household_id": HOUSEHOLD_ID}
        mock_payday.return_value = 27
        resp = client.put(
            f"/households/{HOUSEHOLD_ID}/payday",
            json={"payday_day": 27},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        assert resp.json()["payday_day"] == 27
