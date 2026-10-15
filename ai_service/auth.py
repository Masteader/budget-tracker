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
    """Decode and validate a Supabase JWT (supports modern ES256 asymmetric keys and legacy HS256 secret)."""
    secret = os.environ.get("SUPABASE_JWT_SECRET", "").strip() or SUPABASE_JWT_SECRET
    is_prod = os.environ.get("ENV", "development").lower() == "production"

    try:
        header = jwt.get_unverified_header(token)
    except Exception:
        header = {}

    alg = header.get("alg", "HS256")
    kid = header.get("kid")

    if alg == "ES256" and kid:
        key = _get_jwk_for_kid(kid)
        if key:
            try:
                return jwt.decode(
                    token,
                    key,
                    algorithms=["ES256"],
                    options={"verify_aud": False},
                )
            except JWTError as exc:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Invalid or expired authentication token: {exc}",
                )

    if secret:
        try:
            return jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                options={"verify_aud": False},
            )
        except JWTError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid or expired authentication token: {exc}",
            )
    else:
        # Development fallback: decode without signature verification if no secret set
        if is_prod and alg != "ES256":
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Server configuration error: SUPABASE_JWT_SECRET not set.",
            )
        logger.warning("SUPABASE_JWT_SECRET not configured. Decoding JWT without signature verification (dev only).")
        try:
            return jwt.get_unverified_claims(token)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid authentication token: {exc}",
            )


async def verify_household_access(request: Request, household_id: str) -> str:
    """
    FastAPI dependency that:
    1. Validates household_id format
    2. Extracts Bearer token from Authorization header
    3. Decodes the Supabase JWT to get user_id (sub claim)
    4. Queries users table to find user's household_id
    5. Confirms user belongs to the requested household
    6. Returns the validated household_id
    """
    if household_id:
        validate_uuid(household_id)

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

    # Look up the user's household from the database
    client = get_client()
    response = await asyncio.to_thread(
        lambda: client.table("users")
        .select("household_id")
        .eq("id", user_id)
        .single()
        .execute()
    )

    user_data = response.data
    if not user_data:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User profile not found.",
        )

    _check_household_membership(user_data.get("household_id"), household_id)
    return household_id
