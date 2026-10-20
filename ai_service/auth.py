"""
Authentication and household authorization module.
Decodes Supabase JWT, extracts user ID, and verifies membership in requested household.
"""

from __future__ import annotations

import asyncio
import logging
import os
import threading
import time
from typing import Optional

from fastapi import HTTPException, Request, status
from jose import JWTError, jwt

from utils import validate_uuid
from supabase_client import get_client

logger = logging.getLogger(__name__)

# Supabase JWT Secret — if unset in dev, will warn and skip crypto verification
SUPABASE_JWT_SECRET = os.environ.get("SUPABASE_JWT_SECRET", "").strip()
IS_PRODUCTION = os.environ.get("ENV", "development").lower() == "production"


def _check_household_membership(user_household_id: Optional[str], requested_household_id: str) -> None:
    """Verify that user belongs to the requested household. Raises 403 if not."""
    if not user_household_id or user_household_id != requested_household_id:
        logger.warning(
            "IDOR attempt blocked: user belongs to household=%s, requested household=%s",
            user_household_id,
            requested_household_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this household's data.",
        )


_JWKS_CACHE: dict = {}
# last_success: monotonic time of the last successful JWKS download (0 = never);
# last_failure: monotonic time of the last failed attempt (0 = none since the last success).
_JWKS_STATE = {"last_success": 0.0, "last_failure": 0.0}
# Unknown `kid`s are attacker-controlled: after a successful download never refetch the JWKS
# more often than this.
_JWKS_MIN_REFRESH_SECONDS = 60.0
# After a failed download retry soon (a transient DNS/network error must not lock out ES256
# verification for a minute), but not on every request while the endpoint is down.
_JWKS_FAILURE_BACKOFF_SECONDS = 2.0
_JWKS_FETCH_TIMEOUT_SECONDS = 3.0
# Serialises downloads across worker threads so a burst of requests causes one fetch.
_JWKS_FETCH_LOCK = threading.Lock()
_MAX_TOKEN_LENGTH = 8192
_INVALID_TOKEN_DETAIL = "Invalid or expired authentication token."
_monotonic = time.monotonic  # test seam


def _reset_jwks_cache() -> None:
    """Clear cached JWKS keys (tests / key rotation)."""
    _JWKS_CACHE.clear()
    _JWKS_STATE["last_success"] = 0.0
    _JWKS_STATE["last_failure"] = 0.0


def _fetch_jwks_document(url: str) -> dict:
    import json
    import urllib.request

    with urllib.request.urlopen(url, timeout=_JWKS_FETCH_TIMEOUT_SECONDS) as resp:
        return json.loads(resp.read(256 * 1024).decode("utf-8"))


def _get_jwk_for_kid(kid: str):
    """Return the cached ES256 verification key for ``kid`` (never does network I/O)."""
    return _JWKS_CACHE.get(kid)


def _jwks_refresh_allowed(now: float) -> bool:
    last_success = _JWKS_STATE["last_success"]
    last_failure = _JWKS_STATE["last_failure"]
    if last_success and now - last_success < _JWKS_MIN_REFRESH_SECONDS:
        return False
    if last_failure and now - last_failure < _JWKS_FAILURE_BACKOFF_SECONDS:
        return False
    return True


def _refresh_jwks_for_kid(kid: str) -> None:
    """
    Blocking JWKS download; run it in a worker thread (``asyncio.to_thread``), never on the
    event loop. Only a successful download starts the 60 s throttle: a failure used to stamp
    the throttle before fetching, so one transient error rejected every ES256 token for a
    minute. A failure starts the short back-off instead. Known keys stay cached on failure.
    """
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    if not supabase_url:
        return
    with _JWKS_FETCH_LOCK:
        # Another thread may have fetched (or failed) while this one waited for the lock.
        if kid in _JWKS_CACHE or not _jwks_refresh_allowed(_monotonic()):
            return
        try:
            from jose import jwk

            data = _fetch_jwks_document(f"{supabase_url}/auth/v1/.well-known/jwks.json")
            keys = {}
            for k in data.get("keys", []):
                # Only asymmetric P-256 signing keys are acceptable for the ES256 path.
                if not k.get("kid") or k.get("kty") != "EC" or k.get("crv", "P-256") != "P-256":
                    continue
                if k.get("alg", "ES256") != "ES256":
                    continue
                keys[k["kid"]] = jwk.construct(k, algorithm="ES256")
        except Exception as exc:
            _JWKS_STATE["last_failure"] = _monotonic()
            logger.warning("Failed to fetch Supabase JWKS: %s", type(exc).__name__)
            return
        # Replace the key set: a key removed from the project's JWKS (revoked) stops verifying.
        _JWKS_CACHE.clear()
        _JWKS_CACHE.update(keys)
        _JWKS_STATE["last_success"] = _monotonic()
        _JWKS_STATE["last_failure"] = 0.0


async def ensure_jwks_for_token(token: str) -> None:
    """
    Make sure the verification key for an ES256 token's ``kid`` is cached, downloading the
    project's JWKS in a worker thread when needed (and allowed by the throttle/back-off).
    Never raises: verification itself happens in ``_decode_token``.
    """
    if not token or len(token) > _MAX_TOKEN_LENGTH:
        return
    try:
        header = jwt.get_unverified_header(token)
    except Exception:
        return
    kid = header.get("kid")
    if header.get("alg") != "ES256" or not kid or str(kid) in _JWKS_CACHE:
        return
    if not _jwks_refresh_allowed(_monotonic()):
        return
    await asyncio.to_thread(_refresh_jwks_for_kid, str(kid))


async def decode_token(token: str) -> dict:
    """Async variant of ``_decode_token`` that fetches a missing JWKS key off the event loop."""
    await ensure_jwks_for_token(token)
    return _decode_token(token)


def _reject(reason: str, *args) -> HTTPException:
    logger.info("JWT rejected: " + reason, *args)
    return HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_INVALID_TOKEN_DETAIL)


def _decode_token(token: str) -> dict:
    """
    Decode and validate a Supabase JWT.
    Enforces:
    1. Algorithm pinning: only ES256 (key from the project's JWKS, by kid) or HS256
       (SUPABASE_JWT_SECRET); 'none' and every other alg are rejected before verification.
    2. Audience 'authenticated', issuer '{SUPABASE_URL}/auth/v1', role 'authenticated'.
    3. exp, iat and sub are required (a token without exp would never expire).
    4. Fail-closed: any failure → 401 with a generic detail (reason logged server-side only).
    """
    secret = os.environ.get("SUPABASE_JWT_SECRET", "").strip() or SUPABASE_JWT_SECRET
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    if not supabase_url:
        raise _reject("SUPABASE_URL not configured; cannot pin issuer")
    expected_issuer = f"{supabase_url}/auth/v1"

    if not token or len(token) > _MAX_TOKEN_LENGTH:
        raise _reject("empty or oversized token")
    try:
        header = jwt.get_unverified_header(token)
    except Exception as exc:
        raise _reject("malformed header (%s)", type(exc).__name__)

    alg = header.get("alg")
    kid = header.get("kid")
    if alg == "ES256":
        if not kid:
            raise _reject("ES256 token without kid")
        # Cache only: the JWKS download happens off the event loop in ensure_jwks_for_token
        # (firewall middleware / decode_token), never in this synchronous path.
        key = _get_jwk_for_kid(str(kid))
        if not key:
            raise _reject("no JWKS key for kid")
        algorithms = ["ES256"]
    elif alg == "HS256":
        if not secret:
            raise _reject("HS256 token but SUPABASE_JWT_SECRET is not configured")
        key = secret
        algorithms = ["HS256"]
    else:
        raise _reject("algorithm %r is not allowed", alg)

    try:
        payload = jwt.decode(
            token,
            key,
            algorithms=algorithms,
            audience="authenticated",
            issuer=expected_issuer,
            options={"require_exp": True, "require_iat": True, "require_sub": True, "leeway": 30},
        )
    except JWTError as exc:
        raise _reject("verification failed (%s)", type(exc).__name__)

    if payload.get("role") != "authenticated":
        raise _reject("role %r is not 'authenticated'", payload.get("role"))
    return payload



def get_verified_claims(request: Request) -> dict:
    """Return the verified Supabase JWT claims (sub, email, ...) of the caller, or raise 401."""
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header. Expected: Bearer <token>",
        )

    token = auth_header[7:].strip()
    return _decode_token(token)


def get_current_user_id(request: Request) -> str:
    """Extract and verify the current authenticated user's ID from Supabase JWT."""
    payload = get_verified_claims(request)

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not contain a valid user ID.",
        )
    return str(user_id)


def _get_user_membership(user_id: str, household_id: str) -> Optional[dict]:
    """
    Retrieve the user's role and membership in the given household.

    household_memberships is authoritative. The legacy users.household_id column is consulted
    only when the memberships query itself fails (pre-migration databases); a missing membership
    row is a definitive "no access" (a stale users.household_id after removal must not grant it).
    """
    client = get_client()
    try:
        res = (
            client.table("household_memberships")
            .select("role, household_id")
            .eq("user_id", user_id)
            .eq("household_id", household_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return res.data
        return None
    except Exception as exc:
        logger.warning("Error querying household_memberships: %s", exc)

    # Fallback to users table cache (memberships table unavailable)
    try:
        user_res = (
            client.table("users")
            .select("household_id, role")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        if user_res and user_res.data and user_res.data.get("household_id") == household_id:
            return {
                "household_id": household_id,
                "role": user_res.data.get("role", "member"),
            }
    except Exception as exc:
        logger.warning("Error querying users fallback: %s", exc)

    return None


async def verify_household_access(request: Request, household_id: str) -> str:
    """
    FastAPI dependency that confirms caller belongs to the requested household.
    """
    if household_id:
        validate_uuid(household_id)

    user_id = get_current_user_id(request)
    membership = await asyncio.to_thread(_get_user_membership, user_id, household_id)
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this household's data.",
        )

    return household_id


async def verify_household_admin_access(request: Request, household_id: str) -> str:
    """
    FastAPI dependency that confirms caller is an admin of the requested household.
    """
    if household_id:
        validate_uuid(household_id)

    user_id = get_current_user_id(request)
    membership = await asyncio.to_thread(_get_user_membership, user_id, household_id)
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: You do not have access to this household's data.",
        )

    if membership.get("role") != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: Admin access required for this household.",
        )

    return household_id

