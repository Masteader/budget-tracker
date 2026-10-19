"""
Proof tests for SEC-07: Rate Limiting, API Quotas, Payload Limits, and LLM Output Validation.
"""

import os
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

from main import app
from rate_limiter import SlidingWindowRateLimiter, check_api_quota, reset_rate_limiters
from chat_parser import ParsedChatExpense, ChatLineItem

client = TestClient(app)

TEST_USER_ID = "00000000-0000-0000-0000-000000000001"
TEST_HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"


@pytest.mark.asyncio
async def test_sliding_window_rate_limiter_blocks_excessive_requests():
    limiter = SlidingWindowRateLimiter()
    key = "test_user_key"
    
    # 3 requests allowed under max_requests=3
    for _ in range(3):
        await limiter.check_rate_limit(key, max_requests=3, window_seconds=60)
        
    # 4th request must raise 429
    with pytest.raises(Exception) as exc_info:
        await limiter.check_rate_limit(key, max_requests=3, window_seconds=60)
    assert "429" in str(exc_info.value) or "Rate limit exceeded" in str(exc_info.value)


@pytest.mark.asyncio
async def test_check_api_quota_calls_db_consume_quota():
    with patch("supabase_client.get_client") as mock_get_client:
        mock_rpc = MagicMock()
        mock_get_client.return_value.rpc = mock_rpc
        mock_rpc.return_value.execute.return_value.data = False  # Quota exceeded

        with pytest.raises(Exception) as exc_info:
            await check_api_quota(
                user_id=TEST_USER_ID,
                household_id=TEST_HOUSEHOLD_ID,
                bucket="chat_transaction",
                max_requests=5,
                window_seconds=600,
            )
        assert "429" in str(exc_info.value) or "Rate limit exceeded" in str(exc_info.value)


def test_payload_size_limit_rejects_oversized_request():
    """Requests with Content-Length exceeding the limit must be rejected with 413."""
    headers = {
        "Content-Length": str(2 * 1024 * 1024),  # 2MB for standard JSON endpoint (limit is 1MB)
        "Content-Type": "application/json",
    }
    resp = client.post("/households/test/income", headers=headers, content=b"{}")
    assert resp.status_code == 413
    assert "Payload too large" in resp.json()["detail"]


def test_llm_output_validator_clamps_or_rejects_invalid_amounts():
    """Negative or astronomical amounts from LLM must be rejected or sanitized."""
    # Negative amount in ParsedChatExpense raises ValidationError
    with pytest.raises(Exception):
        ParsedChatExpense(
            merchant="Tamimi",
            total_amount=-50.0,
            category_code="OPEX-GROCERY",
        )

    with pytest.raises(Exception):
        ChatLineItem(
            name="Milk",
            price=-10.0,
            quantity=1.0,
        )

    # Valid amounts pass
    expense = ParsedChatExpense(
        merchant="Tamimi",
        total_amount=150.50,
        category_code="OPEX-GROCERY",
    )
    assert expense.total_amount == 150.50
