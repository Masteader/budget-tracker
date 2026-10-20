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
    assert decode(good)["sub"] == USER
    assert len(calls) == 1

    bogus = jwt.encode(claims(), pem, algorithm="ES256", headers={"kid": "attacker-random-kid"})
    expect_401_async(bogus)
    expect_401_async(bogus)
    # One refresh for the unknown kid at most; repeated unknown kids must not trigger a fetch per request.
    assert len(calls) <= 2


# ─── External review (Gemini) HIGH 3: JWKS fetch failure lock-out and blocking fetch ───────────

def decode(token: str) -> dict:
    return asyncio.run(auth.decode_token(token))


def expect_401_async(token: str) -> None:
    with pytest.raises(HTTPException) as exc:
        decode(token)
    assert exc.value.status_code == 401


@pytest.fixture()
def es256(monkeypatch):
    """ES256 key pair published as kid-1, a controllable clock and a scripted JWKS endpoint."""
    pem, public_jwk = _ec_keypair()
    public_jwk.update({"kid": "kid-1", "alg": "ES256", "use": "sig"})
    state = {"now": 1000.0, "fail": False, "calls": 0, "on_loop": []}

    def fake_fetch(url):
        state["calls"] += 1
        try:
            asyncio.get_running_loop()
            state["on_loop"].append(True)
        except RuntimeError:
            state["on_loop"].append(False)
        if state["fail"]:
            raise OSError("temporary failure in name resolution")
        return {"keys": [public_jwk]}

    monkeypatch.setattr(auth, "_fetch_jwks_document", fake_fetch)
    monkeypatch.setattr(auth, "_monotonic", lambda: state["now"])
    state["token"] = lambda kid="kid-1", **kw: jwt.encode(claims(**kw), pem, algorithm="ES256", headers={"kid": kid})
    return state


def test_sync_decode_never_does_network_io(es256):
    """get_current_user_id runs synchronously inside async routes: it must only read the cache."""
    with pytest.raises(HTTPException):
        auth._decode_token(es256["token"]())
    assert es256["calls"] == 0


def test_jwks_fetch_runs_off_the_event_loop(es256):
    assert decode(es256["token"]())["sub"] == USER
    assert es256["on_loop"] == [False]
    # Once cached, the synchronous path verifies without any further fetch.
    assert auth._decode_token(es256["token"]())["sub"] == USER
    assert es256["calls"] == 1


def test_failed_jwks_fetch_backs_off_briefly_instead_of_locking_out_for_a_minute(es256):
    es256["fail"] = True
    expect_401_async(es256["token"]())
    assert es256["calls"] == 1

    es256["now"] += 1.0  # within the short failure back-off: no hammering of the JWKS endpoint
    expect_401_async(es256["token"]())
    assert es256["calls"] == 1

    es256["fail"] = False
    es256["now"] += auth._JWKS_FAILURE_BACKOFF_SECONDS  # well before the 60 s success throttle
    assert decode(es256["token"]())["sub"] == USER
    assert es256["calls"] == 2


def test_unknown_kid_refresh_stays_throttled_for_a_minute_once_keys_are_cached(es256):
    assert decode(es256["token"]())["sub"] == USER
    assert es256["calls"] == 1

    es256["now"] += 10
    expect_401_async(es256["token"](kid="attacker-random-kid"))
    es256["now"] += 45
    expect_401_async(es256["token"](kid="attacker-random-kid-2"))
    assert es256["calls"] == 1

    es256["now"] += 10  # 65 s after the last successful refresh
    expect_401_async(es256["token"](kid="attacker-random-kid-3"))
    assert es256["calls"] == 2
    # The known key keeps working throughout.
    assert decode(es256["token"]())["sub"] == USER


def test_failed_refresh_with_cached_keys_keeps_known_keys_and_backs_off(es256):
    assert decode(es256["token"]())["sub"] == USER
    es256["now"] += 61
    es256["fail"] = True
    expect_401_async(es256["token"](kid="rotated-kid"))
    assert es256["calls"] == 2
    expect_401_async(es256["token"](kid="rotated-kid"))
    assert es256["calls"] == 2  # failure back-off also applies with a populated cache
    assert decode(es256["token"]())["sub"] == USER


def test_concurrent_requests_share_one_jwks_fetch(es256, monkeypatch):
    import time as _time

    original = auth._fetch_jwks_document

    def slow_fetch(url):
        _time.sleep(0.05)
        return original(url)

    monkeypatch.setattr(auth, "_fetch_jwks_document", slow_fetch)

    async def burst():
        return await asyncio.gather(*(auth.decode_token(es256["token"]()) for _ in range(5)))

    results = asyncio.run(burst())
    assert all(r["sub"] == USER for r in results)
    assert es256["calls"] == 1


def test_firewall_prewarms_jwks_so_routes_accept_es256_tokens(es256, fake_supabase):
    from fastapi.testclient import TestClient

    from main import app

    fake_supabase.seed("household_memberships", [{"user_id": USER, "household_id": HH, "role": "admin"}])
    resp = TestClient(app).get(
        "/budgets/installments",
        params={"household_id": HH},
        headers={"X-Forwarded-For": "198.51.100.23", "Authorization": f"Bearer {es256['token']()}"},
    )
    assert resp.status_code == 200
    assert es256["calls"] == 1 and es256["on_loop"] == [False]


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
