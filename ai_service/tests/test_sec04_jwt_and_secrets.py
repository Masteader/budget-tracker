"""
Proof and verification test suite for SEC-04:
1. Strict Supabase JWT verification:
   - Enforce audience == 'authenticated'
   - Enforce issuer == {SUPABASE_URL}/auth/v1
   - Pin algorithms (ES256 / HS256)
   - Fail-closed: no unverified claims in dev
2. Secret scanner:
   - Working tree scan ensuring no hardcoded default secrets exist in source code
"""

import os
import re
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from jose import jwt

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
SUPABASE_URL = "https://mockproject.supabase.co"

from main import app
import auth

client = TestClient(app)

HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"
USER_ID = "00000000-0000-0000-0000-000000000001"


@pytest.fixture(autouse=True, scope="module")
def setup_sec04_env():
    orig_env = dict(os.environ)
    os.environ["ENV"] = "production"
    os.environ["SUPABASE_URL"] = SUPABASE_URL
    os.environ["SUPABASE_JWT_SECRET"] = TEST_SECRET
    yield
    os.environ.clear()
    os.environ.update(orig_env)


def test_jwt_with_invalid_audience_rejected():
    """Tokens with aud != 'authenticated' must be rejected with 401."""
    token = jwt.encode(
        {
            "sub": USER_ID,
            "aud": "wrong_audience",
            "iss": f"{SUPABASE_URL}/auth/v1",
            "role": "authenticated",
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    with pytest.raises(Exception) as exc_info:
        auth._decode_token(token)
    assert "401" in str(exc_info.value) or "aud" in str(exc_info.value).lower()


def test_jwt_with_invalid_issuer_rejected():
    """Tokens with an untrusted issuer must be rejected with 401."""
    token = jwt.encode(
        {
            "sub": USER_ID,
            "aud": "authenticated",
            "iss": "https://attacker-supabase.com/auth/v1",
            "role": "authenticated",
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    with pytest.raises(Exception) as exc_info:
        auth._decode_token(token)
    assert "401" in str(exc_info.value) or "issuer" in str(exc_info.value).lower()


def test_jwt_valid_audience_and_issuer_accepted():
    """Tokens with valid signature, audience 'authenticated', and Supabase issuer must be accepted."""
    token = jwt.encode(
        {
            "sub": USER_ID,
            "aud": "authenticated",
            "iss": f"{SUPABASE_URL}/auth/v1",
            "role": "authenticated",
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    payload = auth._decode_token(token)
    assert payload["sub"] == USER_ID
    assert payload["aud"] == "authenticated"


def test_no_unverified_claims_fallback_when_secret_unset(monkeypatch):
    """When secrets are unset, decoder must fail closed and NOT decode unverified claims."""
    monkeypatch.setattr(auth, "SUPABASE_JWT_SECRET", "")
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "")
    monkeypatch.setenv("ENV", "development")

    forged_token = jwt.encode(
        {"sub": USER_ID, "aud": "authenticated", "iss": f"{SUPABASE_URL}/auth/v1"},
        "wrong-secret",
        algorithm="HS256",
    )
    with pytest.raises(Exception) as exc_info:
        auth._decode_token(forged_token)
    # Must reject rather than returning unverified claims
    assert "401" in str(exc_info.value) or "500" in str(exc_info.value)


def test_working_tree_secret_scanner():
    """Scan source files for known leaked secret patterns and hardcoded default tokens."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    
    # Patterns of known leaked tokens and secrets
    secret_patterns = [
        re.compile(r"bt_sec_[a-f0-9]{16,}"),
        re.compile(r"239e6a9141efe77bd8193faba777496f2e5bf1c072edf65a20b07082b00b4cc7"),
        re.compile(r"dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400"),
    ]

    source_dirs = [
        repo_root / "flutter_app" / "lib",
        repo_root / "ai_service" / "routes",
    ]

    findings = []
    for sdir in source_dirs:
        if not sdir.exists():
            continue
        for fpath in sdir.rglob("*.dart"):
            content = fpath.read_text(encoding="utf-8", errors="ignore")
            for pat in secret_patterns:
                if pat.search(content):
                    findings.append(f"{fpath.relative_to(repo_root)} matched {pat.pattern}")

        for fpath in sdir.rglob("*.py"):
            content = fpath.read_text(encoding="utf-8", errors="ignore")
            for pat in secret_patterns:
                if pat.search(content):
                    findings.append(f"{fpath.relative_to(repo_root)} matched {pat.pattern}")

    assert not findings, f"Hardcoded secrets detected in source code: {findings}"
