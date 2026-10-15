"""Tests for distributed rate limiting with sliding window and Redis/memory fallback."""
import asyncio
import os
import pytest
from unittest.mock import AsyncMock, MagicMock
from fastapi import HTTPException

os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")


@pytest.mark.asyncio
async def test_in_memory_fallback_enforces_limit():
    """When REDIS_URL is absent, fallback in-memory rate limiter enforces limit."""
    from rate_limiter import SlidingWindowRateLimiter

    limiter = SlidingWindowRateLimiter(redis_url=None)
    key = "household_test_123"

    # Allow up to 3 requests in a 10s window
    for _ in range(3):
        await limiter.check_rate_limit(key, max_requests=3, window_seconds=10)

    # 4th request must raise 429
    with pytest.raises(HTTPException) as exc_info:
        await limiter.check_rate_limit(key, max_requests=3, window_seconds=10)
    assert exc_info.value.status_code == 429
    assert "Retry-After" in exc_info.value.headers


@pytest.mark.asyncio
async def test_redis_sliding_window_logic():
    """Verify Redis ZREMRANGEBYSCORE + ZADD pipeline is invoked when Redis is enabled."""
    from rate_limiter import SlidingWindowRateLimiter

    mock_redis = MagicMock()
    mock_pipeline = MagicMock()
    mock_redis.pipeline.return_value = mock_pipeline
    mock_pipeline.zremrangebyscore = MagicMock()
    mock_pipeline.zadd = MagicMock()
    mock_pipeline.zcard = MagicMock()
    mock_pipeline.expire = MagicMock()
    mock_pipeline.execute = AsyncMock(return_value=[0, 1, 4, True])  # count=4 > limit 3
    mock_redis.zrange = AsyncMock(return_value=[("entry", 100.0)])

    limiter = SlidingWindowRateLimiter(redis_url="redis://localhost:6379/0")
    limiter._redis = mock_redis

    with pytest.raises(HTTPException) as exc_info:
        await limiter.check_rate_limit("household_test_redis", max_requests=3, window_seconds=600)
    assert exc_info.value.status_code == 429
    assert "Retry-After" in exc_info.value.headers
