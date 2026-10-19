"""Distributed sliding-window rate limiter supporting Redis and local memory fallback."""

from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import Optional

from fastapi import HTTPException, status

logger = logging.getLogger(__name__)


class SlidingWindowRateLimiter:
    """
    Sliding window rate limiter.
    Uses Redis ZSET if REDIS_URL is available; falls back to an in-memory dict.
    """

    def __init__(self, redis_url: Optional[str] = None):
        self.redis_url = redis_url or os.environ.get("REDIS_URL", "").strip()
        self._redis = None
        self._memory_history: dict[str, list[float]] = {}
        self._lock = asyncio.Lock()

    async def _get_redis(self):
        if self._redis is None and self.redis_url:
            try:
                import redis.asyncio as aioredis
                client = aioredis.from_url(
                    self.redis_url,
                    encoding="utf-8",
                    decode_responses=True,
                    socket_connect_timeout=2.0,
                )
                await client.ping()
                self._redis = client
                logger.info("Connected to Redis for distributed rate limiting.")
            except Exception as exc:
                logger.warning("Failed to connect to Redis (%s); falling back to in-memory rate limiting.", exc)
                self._redis = None
        return self._redis

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
                pipe = redis_client.pipeline(transaction=True)
                pipe.zremrangebyscore(redis_key, 0, cutoff)
                pipe.zadd(redis_key, {str(now): now})
                pipe.zcard(redis_key)
                pipe.expire(redis_key, window_seconds + 60)
                results = await pipe.execute()

                current_count = results[2]
                if current_count > max_requests:
                    oldest_entries = await redis_client.zrange(redis_key, 0, 0, withscores=True)
                    retry_after = max(1, int(oldest_entries[0][1] + window_seconds - now)) if oldest_entries else window_seconds
                    logger.warning(
                        "Rate limit exceeded (Redis) for %s: %d/%d in %ds. Retry-After: %ds",
                        key, current_count, max_requests, window_seconds, retry_after,
                    )
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail=f"Rate limit exceeded: Maximum {max_requests} requests per {window_seconds // 60} minutes allowed. Please try again in {retry_after} seconds.",
                        headers={"Retry-After": str(retry_after)},
                    )
                return
            except HTTPException:
                raise
            except Exception as exc:
                logger.warning("Redis rate limit check failed (%s); falling back to in-memory for this check.", exc)

        # In-memory fallback
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
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Rate limit exceeded: Maximum {max_requests} requests per {window_seconds // 60} minutes allowed. Please try again in {retry_after} seconds.",
                    headers={"Retry-After": str(retry_after)},
                )

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
    2. Enforces sliding window rate limit (Redis or local memory fallback).
    """
    if user_id:
        try:
            from supabase_client import get_client
            client = get_client()
            res = await asyncio.to_thread(
                lambda: client.rpc(
                    "consume_quota",
                    {
                        "p_user_id": user_id,
                        "p_bucket": bucket,
                        "p_limit": max_requests,
                        "p_window_seconds": window_seconds,
                    },
                ).execute()
            )
            allowed = res.data if res else True
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
        except HTTPException:
            raise
        except Exception as exc:
            logger.warning("Database quota check skipped/fallback: %s", exc)

    # Secondary / in-memory sliding window check by household or user key
    rate_key = f"{bucket}:{household_id or user_id or 'anon'}"
    await default_rate_limiter.check_rate_limit(rate_key, max_requests=max_requests, window_seconds=window_seconds)


def reset_rate_limiters() -> None:
    """Reset in-memory rate limiter histories for testing."""
    default_rate_limiter._memory_history.clear()
