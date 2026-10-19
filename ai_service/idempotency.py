"""
Idempotent replay support for transaction-committing endpoints.

The mobile app replays queued chat/receipt commits after connectivity loss and tags each with
an ``Idempotency-Key`` header. A key is scoped to (user_id, endpoint): the first request
reserves it, its successful result is stored, and every replay of the same key returns that
stored result instead of inserting a second transaction.

Storage: Redis (``REDIS_URL``) when available so all instances share keys, otherwise an
in-process TTL map. Durable cross-instance dedupe without Redis needs a DB table (documented
as an owner action in docs/review/audit/ai_service.md).
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import re
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional, Tuple

from fastapi import HTTPException, status

from utils import utc_now

logger = logging.getLogger(__name__)

IDEMPOTENCY_TTL_SECONDS = 24 * 3600
_PENDING_TTL_SECONDS = 120
_KEY_RE = re.compile(r"^[A-Za-z0-9._:-]{8,128}$")
_PENDING = "__pending__"

# client_occurred_at bounds: small forward clock skew; offline queues are drained within days,
# anything older than this is treated as a corrupt/forged timestamp.
MAX_FUTURE_SKEW = timedelta(minutes=5)
MAX_CLIENT_AGE = timedelta(days=90)


def validate_idempotency_key(raw: Optional[str]) -> Optional[str]:
    if raw is None or raw == "":
        return None
    key = raw.strip()
    if not _KEY_RE.match(key):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Idempotency-Key must be 8-128 characters of [A-Za-z0-9._:-].",
        )
    return key


def parse_client_occurred_at(raw: Optional[str]) -> Optional[datetime]:
    """Validate the client-side event time used as the transaction timestamp on replays."""
    if raw is None or raw == "":
        return None
    try:
        dt = datetime.fromisoformat(str(raw).strip().replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=400, detail="client_occurred_at must be an ISO-8601 timestamp.")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    dt = dt.astimezone(timezone.utc)
    now = utc_now()
    if dt > now + MAX_FUTURE_SKEW:
        raise HTTPException(status_code=400, detail="client_occurred_at is in the future.")
    if dt < now - MAX_CLIENT_AGE:
        raise HTTPException(status_code=400, detail="client_occurred_at is too old.")
    return dt


class IdempotencyStore:
    def __init__(self) -> None:
        self._memory: Dict[str, Tuple[float, str]] = {}
        self._lock = asyncio.Lock()

    @staticmethod
    def _scoped(user_id: str, endpoint: str, key: str) -> str:
        digest = hashlib.sha256(f"{user_id}|{endpoint}|{key}".encode("utf-8")).hexdigest()
        return f"idem:{digest}"

    async def _redis(self):
        from rate_limiter import default_rate_limiter

        return await default_rate_limiter._get_redis()

    async def reserve(self, user_id: str, endpoint: str, key: str) -> Optional[Any]:
        """
        Reserve the key. Returns the stored result for a completed earlier request, None when the
        caller should proceed. Raises 409 while an identical request is still in flight.
        """
        scoped = self._scoped(user_id, endpoint, key)
        redis = await self._redis()
        if redis is not None:
            try:
                if await redis.set(scoped, _PENDING, nx=True, ex=_PENDING_TTL_SECONDS):
                    return None
                existing = await redis.get(scoped)
                return self._interpret(existing)
            except HTTPException:
                raise
            except Exception as exc:
                logger.warning("Redis idempotency store failed (%s); using in-memory store.", exc)
        async with self._lock:
            now = time.monotonic()
            self._memory = {k: v for k, v in self._memory.items() if v[0] > now}
            entry = self._memory.get(scoped)
            if entry is None:
                self._memory[scoped] = (now + _PENDING_TTL_SECONDS, _PENDING)
                return None
            return self._interpret(entry[1])

    @staticmethod
    def _interpret(stored: Optional[str]) -> Optional[Any]:
        if stored is None:
            return None
        if stored == _PENDING:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="A request with this Idempotency-Key is still being processed.",
                headers={"Retry-After": "2"},
            )
        return json.loads(stored)

    async def complete(self, user_id: str, endpoint: str, key: str, result: Any) -> None:
        scoped = self._scoped(user_id, endpoint, key)
        payload = json.dumps(result, default=str)
        redis = await self._redis()
        if redis is not None:
            try:
                await redis.set(scoped, payload, ex=IDEMPOTENCY_TTL_SECONDS)
                return
            except Exception as exc:
                logger.warning("Redis idempotency store failed (%s); using in-memory store.", exc)
        async with self._lock:
            self._memory[scoped] = (time.monotonic() + IDEMPOTENCY_TTL_SECONDS, payload)

    async def release(self, user_id: str, endpoint: str, key: str) -> None:
        """Drop a reservation after a failed request so the client can retry with the same key."""
        scoped = self._scoped(user_id, endpoint, key)
        redis = await self._redis()
        if redis is not None:
            try:
                await redis.delete(scoped)
            except Exception as exc:
                logger.warning("Redis idempotency release failed: %s", exc)
        async with self._lock:
            self._memory.pop(scoped, None)

    def clear(self) -> None:
        self._memory.clear()


idempotency_store = IdempotencyStore()
