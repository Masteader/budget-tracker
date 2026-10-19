"""API-12 / API-13: JWT verification hardening and membership resolution."""

from __future__ import annotations

import asyncio
import time
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from jose import jwt

import auth

SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"
USER = "00000000-0000-4000-8000-0000000000a1"
HH = "aaaaaaaa-0000-4000-8000-000000000001"


@pytest.fixture(autouse=True)
def jwt_env(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.setenv("SUPABASE_URL", "https://mockproject.supabase.co")
    auth._reset_jwks_cache()
    yield
    auth._reset_jwks_cache()


def claims(**overrides):
    now = int(time.time())
    base = {"sub": USER, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 600}
    base.update(overrides)
    return {k: v for k, v in base.items() if v is not None}


def expect_401(token: str) -> HTTPException:
    with pytest.raises(HTTPException) as exc:
        auth._decode_token(token)
    assert exc.value.status_code == 401
    return exc.value


def test_valid_hs256_token_accepted():
    assert auth._decode_token(jwt.encode(claims(), SECRET, algorithm="HS256"))["sub"] == USER


def test_token_without_exp_rejected():
    expect_401(jwt.encode(claims(exp=None), SECRET, algorithm="HS256"))


def test_expired_token_rejected():
    expect_401(jwt.encode(claims(exp=int(time.time()) - 3600), SECRET, algorithm="HS256"))


@pytest.mark.parametrize("role", ["anon", "service_role", None])
def test_non_authenticated_role_rejected(role):
    expect_401(jwt.encode(claims(role=role), SECRET, algorithm="HS256"))


def test_alg_none_and_unpinned_algorithms_rejected():
    import base64
    import json

    def b64(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()

    expect_401(f"{b64({'alg': 'none', 'typ': 'JWT'})}.{b64(claims())}.")
    expect_401(jwt.encode(claims(), SECRET, algorithm="HS512"))


def test_rejection_detail_is_generic():
    err = expect_401(jwt.encode(claims(), "wrong-secret", algorithm="HS256"))
    assert err.detail == "Invalid or expired authentication token."


def test_empty_secret_fails_closed_for_hs256(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "")
    monkeypatch.setattr(auth, "SUPABASE_JWT_SECRET", "")
    expect_401(jwt.encode(claims(), SECRET, algorithm="HS256"))


def _ec_keypair():
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from jose import jwk

    private = ec.generate_private_key(ec.SECP256R1())
    pem = private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    public_jwk = jwk.construct(pem, algorithm="ES256").public_key().to_dict()
    return pem, public_jwk


def test_es256_token_verified_via_jwks_and_unknown_kid_refetch_is_throttled(monkeypatch):
    pem, public_jwk = _ec_keypair()
    public_jwk.update({"kid": "kid-1", "alg": "ES256", "use": "sig"})
    calls = []

    def fake_fetch(url):
        calls.append(url)
        return {"keys": [public_jwk]}

    monkeypatch.setattr(auth, "_fetch_jwks_document", fake_fetch)
    good = jwt.encode(claims(), pem, algorithm="ES256", headers={"kid": "kid-1"})
    assert auth._decode_token(good)["sub"] == USER
    assert len(calls) == 1

    bogus = jwt.encode(claims(), pem, algorithm="ES256", headers={"kid": "attacker-random-kid"})
    expect_401(bogus)
    expect_401(bogus)
    # One refresh for the unknown kid at most; repeated unknown kids must not trigger a fetch per request.
    assert len(calls) <= 2


def test_stale_users_household_id_does_not_grant_access(fake_supabase):
    """Membership comes from household_memberships; a stale users.household_id must not authorize."""
    fake_supabase.seed("users", [{"id": USER, "household_id": HH, "role": "admin"}])
    request = MagicMock()
    request.headers = {"Authorization": f"Bearer {jwt.encode(claims(), SECRET, algorithm='HS256')}"}
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth.verify_household_access(request, HH))
    assert exc.value.status_code == 403

    fake_supabase.seed("household_memberships", [{"user_id": USER, "household_id": HH, "role": "member"}])
    assert asyncio.run(auth.verify_household_access(request, HH)) == HH
