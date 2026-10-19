"""
Authentication and household authorization module.
Decodes Supabase JWT, extracts user ID, and verifies membership in requested household.
"""

from __future__ import annotations

import asyncio
import logging
import os
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


def _get_jwk_for_kid(kid: str):
    """Retrieve and construct a JWK from Supabase JWKS endpoint with in-memory caching."""
    global _JWKS_CACHE
    if kid in _JWKS_CACHE:
        return _JWKS_CACHE[kid]
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    if not supabase_url:
        return None
    try:
        import json
        import urllib.request
        from jose import jwk
        req = urllib.request.urlopen(f"{supabase_url}/auth/v1/.well-known/jwks.json", timeout=5)
        data = json.loads(req.read().decode("utf-8"))
        for k in data.get("keys", []):
            if k.get("kid"):
                _JWKS_CACHE[k["kid"]] = jwk.construct(k)
        return _JWKS_CACHE.get(kid)
    except Exception as exc:
        logger.warning("Failed to fetch Supabase JWKS: %s", exc)
        return None


def _decode_token(token: str) -> dict:
    """
    Decode and validate a Supabase JWT.
    Enforces:
    1. Signature verification via ES256 (cached JWKS) or HS256 (SUPABASE_JWT_SECRET).
    2. Audience check: aud must be 'authenticated'.
    3. Issuer check: iss must be '{SUPABASE_URL}/auth/v1'.
    4. Fail-closed: rejection on any failure, zero unverified fallback claims.
    """
    secret = os.environ.get("SUPABASE_JWT_SECRET", "").strip() or SUPABASE_JWT_SECRET
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    expected_issuer = f"{supabase_url}/auth/v1" if supabase_url else None

    try:
        header = jwt.get_unverified_header(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Malformed JWT header: {exc}",
        )

    alg = header.get("alg", "HS256")
    kid = header.get("kid")

    # 1. Asymmetric ES256 verification via Supabase JWKS
    if alg == "ES256" and kid:
        key = _get_jwk_for_kid(kid)
        if not key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Unable to fetch or construct verification key for token.",
            )
        try:
            decode_kwargs = {
                "algorithms": ["ES256"],
                "audience": "authenticated",
            }
            if expected_issuer:
                decode_kwargs["issuer"] = expected_issuer
            return jwt.decode(token, key, **decode_kwargs)
        except JWTError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid or expired authentication token: {exc}",
            )

    # 2. Symmetric HS256 verification via SUPABASE_JWT_SECRET
    if secret and alg == "HS256":
        try:
            decode_kwargs = {
                "algorithms": ["HS256"],
                "audience": "authenticated",
            }
            if expected_issuer:
                decode_kwargs["issuer"] = expected_issuer
            return jwt.decode(token, secret, **decode_kwargs)
        except JWTError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid or expired authentication token: {exc}",
            )

    # 3. Fail closed if no key or secret matches
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Unauthorized: No valid cryptographic key or secret configured to verify token signature.",
    )



def get_current_user_id(request: Request) -> str:
    """Extract and verify the current authenticated user's ID from Supabase JWT."""
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header. Expected: Bearer <token>",
        )

    token = auth_header[7:].strip()
    payload = _decode_token(token)

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not contain a valid user ID.",
        )
    return str(user_id)


def _get_user_membership(user_id: str, household_id: str) -> Optional[dict]:
    """Retrieve the user's role and membership in the given household."""
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
    except Exception as exc:
        logger.warning("Error querying household_memberships: %s", exc)

    # Fallback to users table cache
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

