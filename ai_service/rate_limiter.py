"""Distributed sliding-window rate limiter supporting Redis and local memory fallback."""

from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from typing import Optional

from fastapi import HTTPException, status

from utils import is_production

logger = logging.getLogger(__name__)

# After a failed Redis connection/command, wait this long before trying Redis again
# (previously every request re-attempted a 2 s connect while Redis was down).
REDIS_RETRY_SECONDS = 30.0


class SlidingWindowRateLimiter:
    """
    Sliding window rate limiter.
    Uses a Redis ZSET if REDIS_URL is available; falls back to an in-memory dict.

    Semantics (identical for both back ends): a request is admitted when fewer than
    ``max_requests`` admitted requests exist in the trailing window; rejected requests
    do not consume window capacity.
    """

    def __init__(self, redis_url: Optional[str] = None):
        self.redis_url = redis_url or os.environ.get("REDIS_URL", "").strip()
        self._redis = None
        self._redis_retry_at = 0.0
        self._memory_history: dict[str, list[float]] = {}
        self._lock = asyncio.Lock()

    def _mark_redis_down(self, exc: Exception) -> None:
        self._redis = None
        self._redis_retry_at = time.monotonic() + REDIS_RETRY_SECONDS
        logger.warning(
            "Redis unavailable (%s); using in-memory rate limiting for %ds.", exc, int(REDIS_RETRY_SECONDS)
        )

    async def _get_redis(self):
        if self._redis is not None or not self.redis_url:
            return self._redis
        if time.monotonic() < self._redis_retry_at:
            return None
        try:
            import redis.asyncio as aioredis
            client = aioredis.from_url(
                self.redis_url,
                encoding="utf-8",
                decode_responses=True,
                socket_connect_timeout=2.0,
                socket_timeout=2.0,
            )
            await client.ping()
            self._redis = client
            logger.info("Connected to Redis for distributed rate limiting.")
        except Exception as exc:
            self._mark_redis_down(exc)
        return self._redis

    @staticmethod
    def _too_many(max_requests: int, window_seconds: int, retry_after: int) -> HTTPException:
        return HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Rate limit exceeded: Maximum {max_requests} requests per {max(1, window_seconds // 60)} "
                f"minutes allowed. Please try again in {retry_after} seconds."
            ),
            headers={"Retry-After": str(retry_after)},
        )

    async def check_rate_limit(
        self,
        key: str,
        max_requests: int = 10,
        window_seconds: int = 600,
    ) -> None:
        """
        Enforce sliding window rate limit.
        Raises HTTPException(429) if request count exceeds max_requests within window_seconds.
        """
        now = time.time()
        cutoff = now - window_seconds
        redis_client = await self._get_redis()

        if redis_client:
            try:
                redis_key = f"rl:{key}"
                # Unique member: the old `str(now)` member collided for concurrent requests with
                # the same timestamp, so a burst was counted as a single request.
                member = f"{now:.6f}:{uuid.uuid4().hex}"
                pipe = redis_client.pipeline(transaction=True)
                pipe.zremrangebyscore(redis_key, 0, cutoff)
                pipe.zadd(redis_key, {member: now})
                pipe.zcard(redis_key)
                pipe.expire(redis_key, window_seconds + 60)
                results = await pipe.execute()

                current_count = results[2]
                if current_count > max_requests:
                    # Rejected requests must not consume capacity (otherwise a client hammering
                    # the endpoint would stay locked out indefinitely).
                    await redis_client.zrem(redis_key, member)
                    oldest_entries = await redis_client.zrange(redis_key, 0, 0, withscores=True)
                    retry_after = max(1, int(oldest_entries[0][1] + window_seconds - now)) if oldest_entries else window_seconds
                    logger.warning(
                        "Rate limit exceeded (Redis) for %s: %d/%d in %ds. Retry-After: %ds",
                        key, current_count, max_requests, window_seconds, retry_after,
                    )
                    raise self._too_many(max_requests, window_seconds, retry_after)
                return
            except HTTPException:
                raise
            except Exception as exc:
                self._mark_redis_down(exc)

        # In-memory fallback (per process)
        async with self._lock:
            timestamps = self._memory_history.get(key, [])
            valid_timestamps = [t for t in timestamps if t > cutoff]

            if len(valid_timestamps) >= max_requests:
                oldest = valid_timestamps[0]
                retry_after = max(1, int(oldest + window_seconds - now))
                logger.warning(
                    "Rate limit exceeded (Memory) for %s: %d/%d in %ds. Retry-After: %ds",
                    key, len(valid_timestamps), max_requests, window_seconds, retry_after,
                )
                self._memory_history[key] = valid_timestamps
                raise self._too_many(max_requests, window_seconds, retry_after)

            valid_timestamps.append(now)
            self._memory_history[key] = valid_timestamps

            # Housekeeping
            if len(self._memory_history) > 500:
                stale_keys = [k for k, ts in self._memory_history.items() if not ts or ts[-1] <= cutoff]
                for sk in stale_keys:
                    self._memory_history.pop(sk, None)


# Default global instance
default_rate_limiter = SlidingWindowRateLimiter()


async def check_receipt_scan_rate_limit(key: str) -> None:
    """Convenience dependency for receipt scan rate limiting."""
    await default_rate_limiter.check_rate_limit(key, max_requests=10, window_seconds=600)


def _consume_db_quota(user_id: str, bucket: str, max_requests: int, window_seconds: int):
    from supabase_client import get_client

    client = get_client()
    return client.rpc(
        "consume_quota",
        {
            "p_user_id": user_id,
            "p_bucket": bucket,
            "p_limit": max_requests,
            "p_window_seconds": window_seconds,
        },
    ).execute()


async def check_api_quota(
    user_id: Optional[str] = None,
    household_id: Optional[str] = None,
    bucket: str = "general",
    max_requests: int = 30,
    window_seconds: int = 600,
) -> None:
    """
    Unified rate-limiter and cost-control quota enforcer.
    1. If user_id is provided, calls PostgreSQL consume_quota RPC to persist quotas across instances.
       In production a failing/ambiguous quota check fails CLOSED (503): the old behaviour of
       logging and continuing meant a misconfigured key (anon role cannot execute the
       service_role-only RPC) silently disabled all LLM cost controls.
    2. Enforces a sliding window keyed by the verified user (falls back to household, then anon).
       Keying by a client-supplied household_id let one user exhaust another household's quota.
    """
    if user_id:
        try:
            res = await asyncio.to_thread(_consume_db_quota, user_id, bucket, max_requests, window_seconds)
            allowed = res.data if res is not None else None
        except Exception as exc:
            allowed = None
            logger.error("Database quota check failed for bucket=%s: %s", bucket, exc)
        if allowed is False:
            logger.warning(
                "Persistent database quota exceeded: user=%s bucket=%s limit=%d in %ds",
                user_id, bucket, max_requests, window_seconds,
            )
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Rate limit exceeded: Maximum {max_requests} requests per {window_seconds // 60} minutes allowed for {bucket}. Please try again later.",
                headers={"Retry-After": str(window_seconds)},
            )
        if allowed is not True:
            if is_production():
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Usage quota service is temporarily unavailable. Please try again shortly.",
                    headers={"Retry-After": "30"},
                )
            logger.warning("Quota check inconclusive for bucket=%s (dev mode): continuing.", bucket)

    # Secondary sliding window check (Redis or local memory)
    if user_id:
        rate_key = f"{bucket}:user:{user_id}"
    elif household_id:
        rate_key = f"{bucket}:household:{household_id}"
    else:
        rate_key = f"{bucket}:anon"
    await default_rate_limiter.check_rate_limit(rate_key, max_requests=max_requests, window_seconds=window_seconds)


def reset_rate_limiters() -> None:
    """Reset in-memory rate limiter histories for testing."""
    default_rate_limiter._memory_history.clear()
