"""API-08 / 09 / 10 / 11 / 29: quota fail-mode, Redis limiter correctness, XFF trust, fail-closed ENV."""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import rate_limiter
from rate_limiter import SlidingWindowRateLimiter, check_api_quota
from utils import get_client_ip, is_production, verify_signature


@pytest.fixture()
def fake_redis_limiter():
    fakeredis = pytest.importorskip("fakeredis")
    import fakeredis.aioredis

    limiter = SlidingWindowRateLimiter(redis_url="redis://fake:6379/0")
    limiter._redis = fakeredis.aioredis.FakeRedis(decode_responses=True)
    return limiter


@pytest.mark.asyncio
async def test_redis_counts_concurrent_requests_with_identical_timestamps(fake_redis_limiter, monkeypatch):
    """Members keyed by str(now) collided, so a burst within one clock tick counted as one request."""
    monkeypatch.setattr(rate_limiter.time, "time", lambda: 1_700_000_000.0)
    admitted = 0
    for _ in range(5):
        try:
            await fake_redis_limiter.check_rate_limit("burst", max_requests=3, window_seconds=60)
            admitted += 1
        except HTTPException as exc:
            assert exc.status_code == 429
    assert admitted == 3


@pytest.mark.asyncio
async def test_redis_rejected_requests_do_not_consume_window(fake_redis_limiter):
    for _ in range(2):
        await fake_redis_limiter.check_rate_limit("hammer", max_requests=2, window_seconds=60)
    for _ in range(5):
        with pytest.raises(HTTPException):
            await fake_redis_limiter.check_rate_limit("hammer", max_requests=2, window_seconds=60)
    assert await fake_redis_limiter._redis.zcard("rl:hammer") == 2


@pytest.mark.asyncio
async def test_redis_outage_backs_off_instead_of_reconnecting_every_request(monkeypatch):
    redis = pytest.importorskip("redis")
    import redis.asyncio as aioredis

    attempts = []

    class Broken:
        async def ping(self):
            raise ConnectionError("down")

    def fake_from_url(*_a, **_k):
        attempts.append(1)
        return Broken()

    monkeypatch.setattr(aioredis, "from_url", fake_from_url)
    limiter = SlidingWindowRateLimiter(redis_url="redis://unreachable:6379/0")
    for _ in range(5):
        await limiter.check_rate_limit("k", max_requests=100, window_seconds=60)
    assert len(attempts) == 1


@pytest.mark.asyncio
async def test_quota_fails_closed_in_production_when_rpc_errors(monkeypatch, fake_supabase):
    monkeypatch.setenv("ENV", "production")

    def boom(_params):
        raise RuntimeError("permission denied for function consume_quota")

    fake_supabase.rpc_handlers["consume_quota"] = boom
    with pytest.raises(HTTPException) as exc:
        await check_api_quota(user_id="u1", household_id="h1", bucket="chat_transaction", max_requests=5)
    assert exc.value.status_code == 503

    monkeypatch.setenv("ENV", "development")
    await check_api_quota(user_id="u1", household_id="h1", bucket="chat_transaction", max_requests=5)


@pytest.mark.asyncio
async def test_quota_denied_by_db_returns_429(fake_supabase):
    fake_supabase.rpc_handlers["consume_quota"] = lambda _p: False
    with pytest.raises(HTTPException) as exc:
        await check_api_quota(user_id="u1", household_id="h1", bucket="scan_receipt", max_requests=5)
    assert exc.value.status_code == 429


# External review (Gemini) BLOCKER 3: PostgREST can hand back the boolean RPC result in several
# shapes (scalar, single-element array, object keyed by the function name, text). Every shape that
# clearly says "allowed" must pass and every clear "denied" must be 429 — never a 503 in production.
_ALLOWED_SHAPES = [True, [True], {"consume_quota": True}, [{"consume_quota": True}], "true", "TRUE", " t ", ["true"]]
_DENIED_SHAPES = [False, [False], {"consume_quota": False}, [{"consume_quota": False}], "false", "f", ["false"]]
_UNKNOWN_SHAPES = [None, [], {}, [True, False], {"other": True}, "maybe", 1, 0, [None], {"consume_quota": None}]


@pytest.mark.parametrize("shape", _ALLOWED_SHAPES, ids=repr)
def test_consume_quota_result_shapes_that_mean_allowed(shape):
    assert rate_limiter._normalize_quota_result(shape) is True


@pytest.mark.parametrize("shape", _DENIED_SHAPES, ids=repr)
def test_consume_quota_result_shapes_that_mean_denied(shape):
    assert rate_limiter._normalize_quota_result(shape) is False


@pytest.mark.parametrize("shape", _UNKNOWN_SHAPES, ids=repr)
def test_consume_quota_result_shapes_that_are_unknown(shape):
    assert rate_limiter._normalize_quota_result(shape) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("shape", _ALLOWED_SHAPES, ids=repr)
async def test_allowed_quota_shapes_pass_in_production(monkeypatch, fake_supabase, shape):
    monkeypatch.setenv("ENV", "production")
    fake_supabase.rpc_handlers["consume_quota"] = lambda _p, _s=shape: _s
    await check_api_quota(user_id="u-allowed", household_id="h1", bucket="chat_transaction", max_requests=50)


@pytest.mark.asyncio
@pytest.mark.parametrize("shape", _DENIED_SHAPES, ids=repr)
async def test_denied_quota_shapes_are_429_in_production(monkeypatch, fake_supabase, shape):
    monkeypatch.setenv("ENV", "production")
    fake_supabase.rpc_handlers["consume_quota"] = lambda _p, _s=shape: _s
    with pytest.raises(HTTPException) as exc:
        await check_api_quota(user_id="u-denied", household_id="h1", bucket="chat_transaction", max_requests=50)
    assert exc.value.status_code == 429


@pytest.mark.asyncio
@pytest.mark.parametrize("shape", _UNKNOWN_SHAPES, ids=repr)
async def test_unknown_quota_shapes_fail_closed_only_in_production(monkeypatch, fake_supabase, shape):
    fake_supabase.rpc_handlers["consume_quota"] = lambda _p, _s=shape: _s
    monkeypatch.setenv("ENV", "production")
    with pytest.raises(HTTPException) as exc:
        await check_api_quota(user_id="u-unknown", household_id="h1", bucket="chat_transaction", max_requests=50)
    assert exc.value.status_code == 503
    monkeypatch.setenv("ENV", "development")
    await check_api_quota(user_id="u-unknown", household_id="h1", bucket="chat_transaction", max_requests=50)


def test_quota_rpc_call_matches_the_consume_quota_sql_signature(fake_supabase):
    """The RPC parameters must be exactly the SQL function's named arguments (PostgREST matches by name)."""
    import pathlib
    import re

    migrations = pathlib.Path(__file__).resolve().parents[2] / "supabase" / "migrations"
    definitions = []
    for path in sorted(migrations.glob("*.sql")):
        for match in re.finditer(
            r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.consume_quota\s*\((.*?)\)\s*RETURNS\s+(\w+)",
            path.read_text(encoding="utf-8"), re.IGNORECASE | re.DOTALL,
        ):
            definitions.append((path.name, match.group(1), match.group(2)))
    assert definitions, "consume_quota must be defined in a migration"
    _, args, returns = definitions[-1]  # the last definition in migration order is the live one
    params = [tuple(a.split()[:2]) for a in (x.strip() for x in args.split(",")) if a]
    assert [(n, t.upper()) for n, t in params] == [
        ("p_user_id", "UUID"), ("p_bucket", "TEXT"), ("p_limit", "INT"), ("p_window_seconds", "INT"),
    ]
    assert returns.upper() == "BOOLEAN"

    rate_limiter._consume_db_quota("00000000-0000-4000-8000-000000000001", "chat_transaction", 30, 600)
    name, sent = fake_supabase.rpc_calls[-1]
    assert name == "consume_quota"
    assert list(sent) == [n for n, _ in params]
    assert isinstance(sent["p_limit"], int) and isinstance(sent["p_window_seconds"], int)


@pytest.mark.asyncio
async def test_sliding_window_is_per_user_not_per_client_supplied_household():
    for user in ("user-a", "user-b"):
        await check_api_quota(user_id=user, household_id="shared-hh", bucket="support_chat", max_requests=1)
    with pytest.raises(HTTPException):
        await check_api_quota(user_id="user-a", household_id="other-hh", bucket="support_chat", max_requests=1)


def _req(peer: str, xff: str | None):
    headers = {"X-Forwarded-For": xff} if xff else {}
    return SimpleNamespace(client=SimpleNamespace(host=peer), headers=headers)


def test_xff_ignored_from_untrusted_peer(monkeypatch):
    monkeypatch.delenv("TRUSTED_PROXY_IPS", raising=False)
    assert get_client_ip(_req("203.0.113.9", "1.2.3.4")) == "203.0.113.9"
    assert get_client_ip(_req("127.0.0.1", "1.2.3.4, 198.51.100.7")) == "198.51.100.7"
    monkeypatch.setenv("TRUSTED_PROXY_IPS", "10.0.0.5")
    assert get_client_ip(_req("10.0.0.5", "9.9.9.9")) == "9.9.9.9"
    assert get_client_ip(_req("127.0.0.1", "9.9.9.9")) == "127.0.0.1"


def test_missing_env_is_treated_as_production(monkeypatch):
    monkeypatch.delenv("ENV", raising=False)
    assert is_production() is True
    monkeypatch.setenv("WEBHOOK_SECRET", "")
    assert verify_signature(b"{}", None) is False
    monkeypatch.setenv("ENV", "development")
    assert is_production() is False
    assert verify_signature(b"{}", None) is True


@pytest.mark.asyncio
async def test_idempotency_store_is_shared_across_instances_via_redis(monkeypatch):
    fakeredis = pytest.importorskip("fakeredis")
    import fakeredis.aioredis
    from idempotency import IdempotencyStore

    monkeypatch.setattr(rate_limiter.default_rate_limiter, "_redis", fakeredis.aioredis.FakeRedis(decode_responses=True))
    instance_a, instance_b = IdempotencyStore(), IdempotencyStore()
    assert await instance_a.reserve("u1", "chat-transaction", "key-12345678") is None
    with pytest.raises(HTTPException) as in_flight:
        await instance_b.reserve("u1", "chat-transaction", "key-12345678")
    assert in_flight.value.status_code == 409
    await instance_a.complete("u1", "chat-transaction", "key-12345678", {"transaction_id": "t1"})
    assert await instance_b.reserve("u1", "chat-transaction", "key-12345678") == {"transaction_id": "t1"}


def test_api_docs_hidden_in_production(monkeypatch):
    from main import app

    client = TestClient(app)
    monkeypatch.setenv("ENV", "production")
    assert client.get("/docs").status_code == 404
    assert client.get("/openapi.json").status_code == 404
    monkeypatch.setenv("ENV", "development")
    assert client.get("/openapi.json").status_code == 200
