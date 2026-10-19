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
import time
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
            "iat": int(time.time()),
            "exp": int(time.time()) + 3600,
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
            "iat": int(time.time()),
            "exp": int(time.time()) + 3600,
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
            "iat": int(time.time()),
            "exp": int(time.time()) + 3600,
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
    """Scan the working tree for known-leaked secrets (by SHA-256 digest) and hardcoded credentials.

    Covers Python, Dart, TS/TSX/JS, Markdown, JSON and YAML across the client, the AI
    service (including tests and dev scripts) and the docs. Raw leaked values are never
    stored in the repo; see tests/secret_scan.py for the digest inventory.
    """
    from secret_scan import scan_paths

    repo_root = Path(__file__).resolve().parent.parent.parent
    roots = [
        repo_root / "flutter_app" / "lib",
        repo_root / "ai_service",
        repo_root / "web_app" / "src",
        repo_root / "docs",
        repo_root / "README.md",
        repo_root / "AGENTS.md",
    ]
    findings = scan_paths(roots, repo_root)
    assert not findings, "Hardcoded or known-leaked secrets detected:\n" + "\n".join(findings)


def test_secret_scanner_detects_leaked_digest_and_structural_patterns():
    """The scanner must flag a known-leaked value (matched by digest) and real-looking credentials."""
    import hashlib
    import secret_scan

    fresh = "ab" * 32
    digest = hashlib.sha256(fresh.encode()).hexdigest()
    original = secret_scan.LEAKED_SECRET_SHA256
    try:
        secret_scan.LEAKED_SECRET_SHA256 = frozenset(set(original) | {digest})
        hits = secret_scan.scan_text(f'WEBHOOK_SECRET = "{fresh}"')
    finally:
        secret_scan.LEAKED_SECRET_SHA256 = original
    assert hits and "known-leaked hex64" in hits[0]
    assert fresh not in hits[0], "scanner output must never echo the secret value"

    assert secret_scan.scan_text("token = 'bt_sec_" + "9f" * 10 + "'")
    assert secret_scan.scan_text("key = 'sb_secret_" + "Zq81" * 6 + "'")
    assert not secret_scan.scan_text("key = 'sb_secret_mock_service_role_key_for_testing'")
    assert not secret_scan.scan_text("sha = '" + "0" * 64 + "'")
