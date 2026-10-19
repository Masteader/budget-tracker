"""API-07: the service must only ever run with a privileged (service_role / sb_secret_) key."""

import pytest
from jose import jwt

import supabase_client


def _legacy_key(role: str) -> str:
    return jwt.encode({"iss": "supabase", "ref": "mockproject", "role": role}, "k" * 32, algorithm="HS256")


@pytest.fixture()
def captured(monkeypatch):
    calls = {}

    def fake_create_client(url, key):
        calls["url"], calls["key"] = url, key
        return object()

    monkeypatch.setattr(supabase_client, "_client", None)
    monkeypatch.setattr(supabase_client, "create_client", fake_create_client)
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)
    return calls


def test_anon_jwt_in_secret_key_is_rejected_and_never_echoed(captured, monkeypatch):
    anon = _legacy_key("anon")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", anon)
    with pytest.raises(RuntimeError) as exc:
        supabase_client.get_client()
    assert "anon" in str(exc.value)
    assert anon not in str(exc.value)
    assert "key" not in captured
    assert supabase_client.is_supabase_configured() is False


def test_valid_service_role_key_wins_over_anon_secret_key(captured, monkeypatch):
    service = _legacy_key("service_role")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", _legacy_key("anon"))
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", service)
    supabase_client.get_client()
    assert captured["key"] == service


def test_publishable_key_is_rejected(captured, monkeypatch):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_publishable_abcdefghijklmnop")
    with pytest.raises(RuntimeError):
        supabase_client.get_client()


def test_opaque_secret_key_is_accepted(captured, monkeypatch):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_mock_value_for_tests_only")
    supabase_client.get_client()
    assert captured["key"] == "sb_secret_mock_value_for_tests_only"
    assert supabase_client.describe_supabase_key()["role"] == "secret"
