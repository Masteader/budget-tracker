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


# ─── External review (Gemini) BLOCKER 1: sb_secret_ keys in either variable, clear precedence ──

SB_SECRET = "sb_secret_mock_value_for_tests_only"
SB_SECRET_OTHER = "sb_secret_other_mock_value_for_tests"


@pytest.mark.parametrize("env_var", ["SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY"])
def test_opaque_secret_key_is_accepted_in_either_variable(captured, monkeypatch, env_var):
    monkeypatch.setenv(env_var, SB_SECRET)
    supabase_client.get_client()
    assert captured["key"] == SB_SECRET
    info = supabase_client.describe_supabase_key()
    assert (info["env_var"], info["role"]) == (env_var, "secret")
    assert info["warnings"] == []


@pytest.mark.parametrize("env_var", ["SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY"])
def test_legacy_service_role_jwt_is_accepted_in_either_variable(captured, monkeypatch, env_var):
    service = _legacy_key("service_role")
    monkeypatch.setenv(env_var, service)
    supabase_client.get_client()
    assert captured["key"] == service
    assert supabase_client.describe_supabase_key()["role"] == "service_role"


@pytest.mark.parametrize("env_var", ["SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY"])
@pytest.mark.parametrize(
    "value, role",
    [
        (_legacy_key("anon"), "anon"),
        (_legacy_key("authenticated"), "authenticated"),
        ("sb_publishable_abcdefghijklmnop", "publishable"),
        ("sb_secret_", "unknown"),
        ("not-a-supabase-key", "unknown"),
        (_legacy_key("supabase_admin"), "unknown-jwt"),
    ],
    ids=["anon-jwt", "authenticated-jwt", "publishable", "bare-prefix", "garbage", "other-role-jwt"],
)
def test_non_privileged_key_alone_is_rejected_in_either_variable(captured, monkeypatch, env_var, value, role):
    monkeypatch.setenv(env_var, value)
    with pytest.raises(RuntimeError) as exc:
        supabase_client.get_client()
    if value != "sb_secret_":  # the bare prefix legitimately appears in the help text
        assert value not in str(exc.value)
    assert "key" not in captured
    assert supabase_client.describe_supabase_key()["rejected"] == [(env_var, role)]
    assert supabase_client.is_supabase_configured() is False


@pytest.mark.parametrize(
    "service_role_value, secret_value, expected_var",
    [
        (_legacy_key("service_role"), _legacy_key("anon"), "SUPABASE_SERVICE_ROLE_KEY"),
        (_legacy_key("anon"), SB_SECRET, "SUPABASE_SECRET_KEY"),
        ("sb_publishable_abcdefghijklmnop", SB_SECRET, "SUPABASE_SECRET_KEY"),
        (SB_SECRET, "sb_publishable_abcdefghijklmnop", "SUPABASE_SERVICE_ROLE_KEY"),
        (SB_SECRET, _legacy_key("anon"), "SUPABASE_SERVICE_ROLE_KEY"),
    ],
    ids=["service_jwt+anon", "anon+sb_secret", "publishable+sb_secret", "sb_secret+publishable", "sb_secret+anon"],
)
def test_privileged_key_wins_over_non_privileged_one_with_a_warning(
    captured, monkeypatch, service_role_value, secret_value, expected_var
):
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", service_role_value)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", secret_value)
    supabase_client.get_client()
    expected = service_role_value if expected_var == "SUPABASE_SERVICE_ROLE_KEY" else secret_value
    assert captured["key"] == expected
    info = supabase_client.describe_supabase_key()
    assert info["env_var"] == expected_var
    other = "SUPABASE_SECRET_KEY" if expected_var == "SUPABASE_SERVICE_ROLE_KEY" else "SUPABASE_SERVICE_ROLE_KEY"
    assert [var for var, _ in info["rejected"]] == [other]
    assert len(info["warnings"]) == 1 and other in info["warnings"][0]
    assert service_role_value not in info["warnings"][0] and secret_value not in info["warnings"][0]


@pytest.mark.parametrize(
    "service_role_value, secret_value",
    [
        (_legacy_key("service_role"), SB_SECRET),  # sb_secret_ beats a legacy JWT whichever variable holds it
        (SB_SECRET, _legacy_key("service_role")),
    ],
    ids=["service_jwt+sb_secret", "sb_secret+service_jwt"],
)
def test_opaque_secret_key_is_preferred_over_legacy_service_role_jwt(captured, monkeypatch, service_role_value, secret_value):
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", service_role_value)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", secret_value)
    supabase_client.get_client()
    assert captured["key"] == SB_SECRET
    info = supabase_client.describe_supabase_key()
    assert info["role"] == "secret"
    assert len(info["warnings"]) == 1 and "ignored" in info["warnings"][0]


def test_two_different_opaque_secret_keys_use_supabase_secret_key_and_warn(captured, monkeypatch):
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", SB_SECRET_OTHER)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", SB_SECRET)
    supabase_client.get_client()
    assert captured["key"] == SB_SECRET
    assert len(supabase_client.describe_supabase_key()["warnings"]) == 1


def test_same_opaque_secret_key_in_both_variables_is_silent(captured, monkeypatch):
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", SB_SECRET)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", f"  {SB_SECRET}\n")
    supabase_client.get_client()
    assert captured["key"] == SB_SECRET
    assert supabase_client.describe_supabase_key()["warnings"] == []


def test_startup_check_warns_about_ignored_anon_key_without_echoing_it(captured, monkeypatch, caplog):
    import logging

    import main

    anon = _legacy_key("anon")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", anon)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", SB_SECRET)
    with caplog.at_level(logging.WARNING, logger="main"):
        main._log_security_configuration()
    records = [r for r in caplog.records if r.name == "main"]
    assert any(r.levelno == logging.WARNING and "SUPABASE_SERVICE_ROLE_KEY" in r.getMessage() for r in records)
    assert not any(r.levelno >= logging.CRITICAL for r in records)
    assert all(anon not in r.getMessage() and SB_SECRET not in r.getMessage() for r in records)


def test_startup_check_is_critical_when_no_privileged_key(captured, monkeypatch, caplog):
    import logging

    import main

    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_publishable_abcdefghijklmnop")
    with caplog.at_level(logging.WARNING, logger="main"):
        main._log_security_configuration()
    critical = [r.getMessage() for r in caplog.records if r.name == "main" and r.levelno >= logging.CRITICAL]
    assert any("SUPABASE_SECRET_KEY" in m for m in critical)
    assert any("No privileged Supabase key" in m for m in critical)


def test_requirements_pin_a_supabase_py_that_accepts_sb_secret_keys():
    """supabase-py <= 2.15.3 rejects non-JWT keys in create_client ("Invalid API key"); 2.16.0 removed that check."""
    import pathlib
    import re

    text = (pathlib.Path(__file__).resolve().parents[1] / "requirements.txt").read_text()
    match = re.search(r"^supabase>=([0-9]+)\.([0-9]+)\.([0-9]+)", text, re.MULTILINE)
    assert match, "supabase must have an exact x.y.z lower bound"
    assert tuple(int(p) for p in match.groups()) >= (2, 16, 0)


def test_installed_supabase_py_accepts_opaque_secret_key_offline():
    """create_client must accept the opaque key and send it as `apikey` (plus the identical Bearer supabase-js sends)."""
    from supabase import create_client

    client = create_client("https://mockproject.supabase.co", SB_SECRET)
    headers = client.postgrest.session.headers
    assert headers["apikey"] == SB_SECRET
    assert headers["Authorization"] == f"Bearer {SB_SECRET}"
