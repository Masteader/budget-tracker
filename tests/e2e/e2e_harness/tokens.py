"""Locally signed Supabase-shaped JWTs (HS256 with the e2e test secret)."""

from __future__ import annotations

import time
from typing import Optional

from jose import jwt

from .config import JWT_SECRET


def user_token(supabase_url: str, user_id: str, email: Optional[str] = None, ttl: int = 3600, **extra) -> str:
    """A GoTrue-style access token for an authenticated user."""
    now = int(time.time())
    claims = {
        "sub": user_id,
        "aud": "authenticated",
        "role": "authenticated",
        "iss": f"{supabase_url.rstrip('/')}/auth/v1",
        "iat": now,
        "exp": now + ttl,
        "email": email or f"{user_id[:8]}@e2e.test",
        "aal": "aal1",
        "session_id": user_id,
        "is_anonymous": False,
    }
    claims.update(extra)
    return jwt.encode(claims, JWT_SECRET, algorithm="HS256")


def service_role_key() -> str:
    """Legacy-style service_role API key (what SUPABASE_SECRET_KEY holds on Railway)."""
    now = int(time.time())
    return jwt.encode(
        {"iss": "supabase", "role": "service_role", "iat": now, "exp": now + 10 * 365 * 86400},
        JWT_SECRET,
        algorithm="HS256",
    )


def anon_key() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": "supabase", "role": "anon", "iat": now, "exp": now + 10 * 365 * 86400},
        JWT_SECRET,
        algorithm="HS256",
    )
