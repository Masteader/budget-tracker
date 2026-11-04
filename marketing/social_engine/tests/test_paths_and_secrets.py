"""Paths, startup guard, environment scrub and log redaction (spec Section 11, task A3)."""

import io
import json
import logging
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest
from conftest import make_junction

from core.logging_setup import (
    RedactingFilter,
    configure_logging,
    forget_known_secrets,
    redact,
)
from core.paths import RAW_RECORDING_FOLDERS, EnginePaths, PathConfigError, expand_path
from core.paths import resolve_data_root as resolve
from core.secrets import (
    FORBIDDEN_ENV_PREFIX,
    ForbiddenEnvironment,
    check_startup_environment,
    load_env_file,
    scrubbed_env,
)

ENGINE_ROOT = Path(__file__).resolve().parents[1]

# Shaped like real secrets, and fake.
TELEGRAM_TOKEN = "123456789:AAEhBOweik6ad9r_QXMENQjcrGbqCr4K-Ms"
ANTHROPIC_KEY = "sk-ant-api03-abcDEF123_456-ghiJKL789"
AZURE_KEY_32 = "0123456789abcdef0123456789abcdef"
AZURE_KEY_84 = "A1b2C3d4E5" * 8 + "F6g7"
MP4_SHA256 = "ab" * 32


# --- Paths -----------------------------------------------------------------------------


def test_local_app_data_expands(monkeypatch, tmp_path):
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    assert expand_path("%LOCALAPPDATA%/SocialEngine") == tmp_path / "SocialEngine"


def test_expansion_can_use_a_given_environment(tmp_path):
    env = {"LOCALAPPDATA": str(tmp_path)}
    assert expand_path("%LOCALAPPDATA%/x", env=env) == tmp_path / "x"


def test_an_undefined_variable_stops_rather_than_making_a_literal_folder(monkeypatch):
    monkeypatch.delenv("LOCALAPPDATA")
    with pytest.raises(PathConfigError, match="LOCALAPPDATA"):
        expand_path("%LOCALAPPDATA%/SocialEngine")


def test_data_root_from_the_shipped_form_resolves(monkeypatch, tmp_path):
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    assert resolve("%LOCALAPPDATA%/SocialEngine") == tmp_path / "SocialEngine"


def test_a_relative_data_root_is_refused():
    with pytest.raises(PathConfigError, match="absolute"):
        resolve("SocialEngine")


def test_a_data_root_inside_the_repo_folder_is_refused():
    with pytest.raises(PathConfigError, match="social_engine"):
        resolve(str(ENGINE_ROOT / "data"))


@pytest.mark.parametrize("folder", ["OneDrive", "OneDrive - Contoso", "onedrive"])
def test_a_data_root_in_onedrive_is_refused(tmp_path, folder):
    with pytest.raises(PathConfigError, match="OneDrive"):
        resolve(str(tmp_path / folder / "SocialEngine"))


def test_a_data_root_under_the_onedrive_variable_is_refused(tmp_path):
    synced = tmp_path / "Synced"
    with pytest.raises(PathConfigError, match="OneDrive"):
        resolve(str(synced / "SocialEngine"), env={"OneDrive": str(synced)})


def _engine_as_text() -> str:
    return str(ENGINE_ROOT)


@pytest.mark.parametrize(
    "raw",
    [
        lambda: _engine_as_text() + r".\zz_probe",
        lambda: _engine_as_text() + r"..\zz_probe",
        lambda: _engine_as_text() + r" \zz_probe",
        lambda: "\\\\?\\" + _engine_as_text() + r"\data",
        lambda: "\\\\.\\" + _engine_as_text() + r"\data",
        lambda: "//?/" + _engine_as_text() + "/data",
        lambda: str(ENGINE_ROOT.parent),
        lambda: str(ENGINE_ROOT.parents[1]),
        lambda: str(ENGINE_ROOT.parents[1] / "data"),
        lambda: str(ENGINE_ROOT.parents[1] / "ai_service" / "data"),
        lambda: _engine_as_text().upper() + r"\data",
    ],
    ids=[
        "trailing dot",
        "two trailing dots",
        "trailing space",
        "extended prefix",
        "device prefix",
        "forward extended prefix",
        "parent of the engine",
        "repo root",
        "inside the repo",
        "another part of the repo",
        "upper case",
    ],
)
def test_tricks_that_land_in_the_repo_are_refused(raw):
    with pytest.raises(PathConfigError):
        resolve(raw(), env={})


def test_a_folder_holding_the_repo_is_refused():
    with pytest.raises(PathConfigError):
        resolve(ENGINE_ROOT.anchor, env={})


@pytest.mark.parametrize(
    "raw",
    [
        r"\\?\D:\Cloud\x",
        r"D:\Cloud.\x",
        r"D:\Cloud \x",
        r"D:\Cloud\..\Cloud\x",
        r"\\server\share\x",
        r"D:\plain\NUL\x",
        r"D:\plain\file.txt:stream",
    ],
)
def test_tricks_around_the_onedrive_variable_are_refused(raw):
    with pytest.raises(PathConfigError):
        resolve(raw, env={"ONEDRIVE": r"D:\Cloud"})


@pytest.mark.parametrize("variable", ["OneDrive", "OneDriveConsumer", "OneDriveCommercial"])
def test_each_onedrive_variable_counts(tmp_path, variable):
    synced = tmp_path / "Synced"
    with pytest.raises(PathConfigError, match="OneDrive"):
        resolve(str(synced / "x"), env={variable: str(synced)})


def test_a_sibling_whose_name_starts_like_a_synced_folder_is_fine(tmp_path):
    # D:\Cloud must not catch D:\CloudBackup.
    root = tmp_path / "SyncedBackup" / "x"
    assert resolve(str(root), env={"OneDrive": str(tmp_path / "Synced")}) == root


def test_parent_steps_are_resolved_before_checking(tmp_path):
    with pytest.raises(PathConfigError, match="OneDrive"):
        resolve(str(tmp_path / "plain" / ".." / "OneDrive" / "x"), env={})
    assert resolve(str(tmp_path / "a" / ".." / "b"), env={}) == tmp_path / "b"


@pytest.mark.skipif(sys.platform != "win32", reason="junctions are a Windows feature")
def test_a_junction_into_onedrive_is_refused(tmp_path):
    target = tmp_path / "OneDrive" / "x"
    target.mkdir(parents=True)
    link = tmp_path / "plain"
    make_junction(link, target)
    with pytest.raises(PathConfigError, match="OneDrive"):
        resolve(str(link / "data"), env={})


@pytest.mark.skipif(sys.platform != "win32", reason="junctions are a Windows feature")
def test_a_junction_into_the_repo_is_refused(tmp_path):
    link = tmp_path / "plain"
    make_junction(link, ENGINE_ROOT)
    try:
        with pytest.raises(PathConfigError):
            resolve(str(link / "data"), env={})
    finally:
        link.rmdir()


def test_engine_paths_follow_spec_section_4(tmp_path):
    paths = EnginePaths.from_root(tmp_path)
    assert paths.env_file == tmp_path / ".env"
    assert paths.remotion_work == tmp_path / "remotion_work"
    assert paths.raw_recordings == tmp_path / "assets" / "raw_recordings"
    assert paths.screenshots == tmp_path / "assets" / "screenshots"
    assert paths.manifest == tmp_path / "assets" / "manifest.json"
    assert paths.bg_music == tmp_path / "assets" / "audio" / "bg_music"
    assert paths.voiceovers == tmp_path / "assets" / "audio" / "voiceovers"
    assert paths.renders == tmp_path / "renders"
    assert paths.state_db == tmp_path / "state" / "engine.db"
    assert paths.claude_cwd == tmp_path / "claude_cwd"
    assert paths.logs == tmp_path / "logs"


def test_ensure_dirs_creates_the_tree_and_leaves_claude_cwd_empty(tmp_path):
    paths = EnginePaths.from_root(tmp_path / "root")
    paths.ensure_dirs()
    for folder in RAW_RECORDING_FOLDERS:
        assert (paths.raw_recordings / folder).is_dir()
    for folder in [
        paths.screenshots,
        paths.bg_music,
        paths.voiceovers,
        paths.renders,
        paths.state_db.parent,
        paths.logs,
        paths.remotion_work,
    ]:
        assert folder.is_dir()
    assert list(paths.claude_cwd.iterdir()) == []
    assert not paths.env_file.exists()


def test_the_feature_folders_are_the_shot_list():
    assert set(RAW_RECORDING_FOLDERS) == {
        "payday_cycle",
        "zatca_receipt_scan",
        "receipt_photo_scan",
        "chat_and_voice_entry",
        "multi_account_ledger",
        "budget_capacity",
        "nafaqah_wife_expenses",
        "roommate_debt_split",
        "recurring_and_installments",
        "price_tracker",
        "smart_basket",
        "app_experience",
    }


# --- Startup guard ---------------------------------------------------------------------


@pytest.mark.parametrize("suffix", ["URL", "SERVICE_ROLE_KEY", "ANON_KEY"])
def test_a_forbidden_variable_stops_startup(monkeypatch, suffix):
    name = FORBIDDEN_ENV_PREFIX + suffix
    monkeypatch.setenv(name, "x")
    with pytest.raises(ForbiddenEnvironment) as caught:
        check_startup_environment()
    assert name in str(caught.value)


def test_a_forbidden_variable_in_a_given_mapping_stops_startup_in_any_case():
    with pytest.raises(ForbiddenEnvironment):
        check_startup_environment({FORBIDDEN_ENV_PREFIX.lower() + "url": "x"})


def test_the_refusal_names_the_variable_but_never_its_value():
    secret = "very-secret-value"
    with pytest.raises(ForbiddenEnvironment) as caught:
        check_startup_environment({FORBIDDEN_ENV_PREFIX + "KEY": secret})
    assert secret not in str(caught.value)


def test_a_clean_environment_starts():
    check_startup_environment({"PATH": "x", "DATABASE_URL_NOTE": "x"})


@pytest.mark.parametrize(
    "name",
    [
        "VITE_" + FORBIDDEN_ENV_PREFIX + "ANON_KEY",
        "NEXT_PUBLIC_" + FORBIDDEN_ENV_PREFIX + "URL",
        "MY_" + FORBIDDEN_ENV_PREFIX + "SERVICE_ROLE_KEY",
        FORBIDDEN_ENV_PREFIX.lower() + "x",
        FORBIDDEN_ENV_PREFIX.rstrip("_"),
    ],
)
def test_the_guard_catches_the_name_anywhere_in_a_variable(name):
    with pytest.raises(ForbiddenEnvironment):
        check_startup_environment({name: "x"})
    assert name not in scrubbed_env(None, {name: "x"})


# --- Scrubbed environment --------------------------------------------------------------

DIRTY = {
    "PATH": "keep",
    "USERPROFILE": "keep",
    "TELEGRAM_BOT_TOKEN": "x",
    "TELEGRAM_OWNER_USER_ID": "x",
    "AZURE_SPEECH_KEY": "x",
    "AZURE_SPEECH_REGION": "x",
    "PUBLISHER_API_KEY": "x",
    "ANTHROPIC_AUTH_TOKEN": "x",
    FORBIDDEN_ENV_PREFIX + "URL": "x",
    FORBIDDEN_ENV_PREFIX + "SERVICE_ROLE_KEY": "x",
    "ANTHROPIC_API_KEY": "x",
}


def test_scrub_removes_every_listed_secret_and_keeps_the_rest():
    assert scrubbed_env("subscription", DIRTY) == {"PATH": "keep", "USERPROFILE": "keep"}


def test_scrub_keeps_the_anthropic_key_only_for_api_key_auth():
    assert scrubbed_env("api_key", DIRTY) == {
        "PATH": "keep",
        "USERPROFILE": "keep",
        "ANTHROPIC_API_KEY": "x",
    }


@pytest.mark.parametrize("auth", ["subscription", "API_KEY", "", None])
def test_scrub_removes_the_anthropic_key_for_anything_else(auth):
    assert "ANTHROPIC_API_KEY" not in scrubbed_env(auth, DIRTY)


def test_scrub_ignores_case_in_variable_names():
    env = {"anthropic_api_key": "x", "Azure_Speech_Key": "x", "path": "keep"}
    assert scrubbed_env("subscription", env) == {"path": "keep"}


def test_scrub_does_not_change_its_input():
    env = dict(DIRTY)
    scrubbed_env("subscription", env)
    assert env == DIRTY


def test_scrub_reads_the_process_environment_by_default(monkeypatch):
    monkeypatch.setenv("AZURE_SPEECH_KEY", "x")
    monkeypatch.setenv("TEMP", "keep")
    result = scrubbed_env("subscription")
    assert "AZURE_SPEECH_KEY" not in result
    assert result["TEMP"] == "keep"


@pytest.mark.parametrize(
    "name",
    [
        "CLAUDE_CODE_OAUTH_TOKEN",
        "NPM_TOKEN",
        "npm_config__authToken",
        "NODE_AUTH_TOKEN",
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "AWS_SECRET_ACCESS_KEY",
        "GEM" + "INI_API_KEY",
        "WEBHOOK_SECRET",
        "DATABASE_URL",
        "HTTPS_PROXY",
        "NODE_OPTIONS",
        "ANY_NAME_NOBODY_THOUGHT_OF",
    ],
)
@pytest.mark.parametrize("auth", [None, "subscription", "api_key"])
def test_scrub_is_an_allowlist_so_unknown_variables_never_pass(auth, name):
    assert scrubbed_env(auth, {name: "x", "PATH": "keep"}) == {"PATH": "keep"}


def test_scrub_keeps_what_a_windows_child_process_needs():
    needed = ["PATH", "PATHEXT", "SYSTEMROOT", "COMSPEC", "TEMP", "TMP", "USERPROFILE"]
    needed += ["APPDATA", "LOCALAPPDATA", "PROGRAMDATA", "HOMEDRIVE", "HOMEPATH"]
    env = {name: "keep" for name in needed}
    assert scrubbed_env(None, env) == env
    assert scrubbed_env(None, {"Path": "keep"}) == {"Path": "keep"}


# --- The .env file, always a temporary one here ----------------------------------------


def test_env_file_values_are_returned_and_not_put_in_the_process_environment(
    tmp_path, monkeypatch
):
    monkeypatch.delenv("AZURE_SPEECH_REGION", raising=False)
    (tmp_path / ".env").write_text("AZURE_SPEECH_REGION=uaenorth\nEMPTY=\n", encoding="utf-8")
    assert load_env_file(tmp_path) == {"AZURE_SPEECH_REGION": "uaenorth", "EMPTY": ""}
    assert "AZURE_SPEECH_REGION" not in os.environ


def test_a_missing_env_file_is_an_empty_mapping(tmp_path):
    assert load_env_file(tmp_path) == {}


def test_env_file_values_are_not_interpolated(tmp_path, monkeypatch):
    # A value holding ${...} must stay as typed, and must not pull in another variable.
    monkeypatch.setenv("SOME_OTHER_VALUE", "leaked")
    (tmp_path / ".env").write_text("A_KEY=abc${SOME_OTHER_VALUE}def\n", encoding="utf-8")
    assert load_env_file(tmp_path) == {"A_KEY": "abc${SOME_OTHER_VALUE}def"}


def test_a_forbidden_variable_in_the_env_file_stops_startup(tmp_path):
    (tmp_path / ".env").write_text(f"{FORBIDDEN_ENV_PREFIX}URL=x\n", encoding="utf-8")
    with pytest.raises(ForbiddenEnvironment):
        load_env_file(tmp_path)


# --- Log redaction ---------------------------------------------------------------------


@pytest.mark.parametrize(
    "secret",
    [TELEGRAM_TOKEN, ANTHROPIC_KEY, AZURE_KEY_32, AZURE_KEY_84, "abc.def-ghi_jkl123"],
)
@pytest.mark.parametrize(
    "template",
    [
        "Bearer {}",
        "token={}",
        "AZURE_SPEECH_KEY={}",
        "Ocp-Apim-Subscription-Key: {}",
        'x-api-key": "{}',
    ],
)
def test_secrets_after_a_secret_looking_name_are_redacted(template, secret):
    assert secret not in redact(template.format(secret))


@pytest.mark.parametrize(
    "text",
    [
        f"POST https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendVideo failed",
        f"bare {TELEGRAM_TOKEN} here",
        f"key is {ANTHROPIC_KEY}.",
        f"azure {AZURE_KEY_32} here",
        f"azure {AZURE_KEY_84} here",
    ],
)
def test_token_shaped_strings_are_redacted_anywhere(text):
    result = redact(text)
    for secret in (TELEGRAM_TOKEN, ANTHROPIC_KEY, AZURE_KEY_32, AZURE_KEY_84):
        assert secret not in result
    assert "REDACTED" in result


def test_ordinary_log_text_is_left_alone():
    text = f"reel R-2026-11-03-01 rev 2 at 12:30:45, sha256 {MP4_SHA256}, user 123456789 ok"
    assert redact(text) == text


@pytest.mark.parametrize(
    "text",
    [
        "monkey: banana",
        "keyboard: arabic",
        "the token expired, please log in",
        "for key, value in items",
    ],
)
def test_ordinary_words_near_secret_names_keep_their_meaning(text):
    assert redact(text) == text


def test_a_known_secret_is_redacted_even_when_it_has_no_recognised_shape():
    assert "plain-looking" not in redact("value plain-looking here", ["plain-looking"])


def test_a_very_short_known_secret_does_not_shred_the_log():
    assert redact("abcdef", ["abc"]) == "abcdef"


def test_the_longest_known_secret_is_redacted_first():
    assert "ef" not in redact("abcdef", ["abcd", "abcdef"])


LEAK = "s3cretv4lue"


@pytest.mark.parametrize(
    "text",
    [
        repr({"token": [LEAK]}),
        repr({"token": (LEAK,)}),
        repr({"token": {"value": LEAK}}),
        repr({"token": [{"a": "b"}, {"c": LEAK}]}),
        repr({"api_key": LEAK}),
        json.dumps({"api_key": [LEAK]}),
        json.dumps(json.dumps({"api_key": LEAK})),
        f"token=b'{LEAK}'",
        f'token=b"{LEAK}"',
        f"Authorization: Basic {LEAK}",
        f"authorization: Bearer {LEAK}",
        f"authorization: {LEAK}",
        f"Cookie: session={LEAK}",
        f"pwd={LEAK}",
        f"passwd: {LEAK}",
        f"credential: {LEAK}",
        f"tokens={LEAK}",
        f"TELEGRAM_BOT_TOKEN_OLD={LEAK}",
        f"apikey={LEAK}",
        f"token%3D{LEAK}",
        repr(("AZURE_SPEECH_KEY", LEAK)),
    ],
)
def test_structured_and_encoded_secret_values_are_redacted(text):
    assert LEAK not in redact(text), redact(text)


@pytest.mark.parametrize(
    "text",
    [
        f"Authorization: Token {LEAK}",
        f"Authorization: Apikey {LEAK}",
        f"authorization: Custom-Scheme_2 {LEAK}",
        f"AUTHORIZATION:\tToken\t{LEAK}",
        f"Authorization: Token {' ' * 40}{LEAK}",
        f"Proxy-Authorization: Token {LEAK}",
        f"Authorization=Token {LEAK}",
        f"GET /reels Authorization: Token {LEAK} status=200",
        f"Authorization: Token {'a' * 5000} {LEAK}",
        repr({"Authorization": f"Token {LEAK}"}),
        repr({"Authorization": f"Bearer {LEAK}"}),
        repr({"authorization": f"Apikey {LEAK}", "Accept": "json"}),
        repr([("Authorization", f"Token {LEAK}")]),
        repr({b"Authorization": f"Token {LEAK}".encode()}),
        json.dumps({"Authorization": f"Token {LEAK}"}),
        json.dumps(json.dumps({"Authorization": f"Token {LEAK}"})),
        f'Authorization: Digest username="bob", realm="r", response="{LEAK}"',
        f"Authorization: AWS4-HMAC-SHA256 Credential=a/b, SignedHeaders=host, Sig={LEAK}",
    ],
    ids=lambda text: text[:40],
)
def test_any_scheme_on_an_authorization_header_is_redacted(text):
    assert LEAK not in redact(text), redact(text)


@pytest.mark.parametrize(
    "text",
    [
        "token x",
        "Token x",
        "token abc def",
        "Apikey x",
        "authorization failed for user 5",
        "Authorization header is missing",
    ],
)
def test_prose_about_tokens_and_authorization_is_left_alone(text):
    assert redact(text) == text


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("token: first second", "token: [REDACTED] second"),
        ("key: value here", "key: [REDACTED] here"),
        ("Authorization: abc", "Authorization: [REDACTED]"),
        ("authorization: required\nreel ready", "authorization: [REDACTED]\nreel ready"),
    ],
)
def test_only_the_authorization_line_loses_more_than_one_word(text, expected):
    assert redact(text) == expected


def test_a_url_encoded_telegram_token_is_redacted():
    number, secret = TELEGRAM_TOKEN.split(":")
    url = f"https://api.telegram.org/bot{number}%3A{secret}/getMe"
    assert secret not in redact(url)
    assert secret not in redact(url.replace("%3A", "%3a"))


@pytest.mark.parametrize(
    "text",
    [
        "a" * 200_000,
        "1" * 200_000,
        "f" * 200_000,
        "key" * 70_000,
        "key_" * 50_000,
        "key=" * 50_000,
        "token:[" * 30_000,
        "token: '" * 25_000,
        "bearer " * 30_000,
        "sk-" * 70_000,
        "123456:" * 30_000,
        "authorization: " * 15_000,
        "authorization: a " * 15_000,
        "authorization: a\n" * 15_000,
        "authorization: " + "a" * 200_000,
        "authorization: a" + " " * 200_000,
        "authorization: a\t" * 15_000,
    ],
    ids=lambda text: text[:8],
)
def test_redaction_takes_linear_time(text):
    started = time.perf_counter()
    redact(text)
    assert time.perf_counter() - started < 2.0


@pytest.fixture
def clean_logging():
    root = logging.getLogger()
    handlers, level = list(root.handlers), root.level
    watched = {name: logging.getLogger(name).level for name in ("httpx", "httpx2", "httpcore")}
    factory = logging.getLogRecordFactory()
    excepthook, threading_hook = sys.excepthook, threading.excepthook
    root.handlers = []
    yield root
    for handler in root.handlers:
        handler.close()
    root.handlers, root.level = handlers, level
    for name, previous in watched.items():
        logging.getLogger(name).setLevel(previous)
    logging.setLogRecordFactory(factory)
    sys.excepthook, threading.excepthook = excepthook, threading_hook
    logging.captureWarnings(False)
    forget_known_secrets()


def _captured(root) -> io.StringIO:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(logging.Formatter("%(name)s %(levelname)s %(message)s"))
    handler.addFilter(RedactingFilter())
    root.addHandler(handler)
    return stream


def test_a_token_is_redacted_from_message_args_and_tracebacks(clean_logging):
    configure_logging()
    stream = _captured(clean_logging)
    logger = logging.getLogger("engine.test")
    logger.warning(f"plain {TELEGRAM_TOKEN}")
    logger.warning("args %s", f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getMe")
    try:
        raise RuntimeError(f"boom {TELEGRAM_TOKEN}")
    except RuntimeError:
        logger.exception("failed")
    logger.warning("stack", stack_info=True)
    output = stream.getvalue()
    assert TELEGRAM_TOKEN not in output
    assert "failed" in output
    assert "Traceback" in output


def test_configure_logging_filters_console_and_file_output(clean_logging, tmp_path, capsys):
    log_dir = tmp_path / "logs"
    configure_logging(log_dir=log_dir)
    logging.getLogger("engine.test").warning("token %s", TELEGRAM_TOKEN)
    for handler in clean_logging.handlers:
        handler.flush()
    written = (log_dir / "engine.log").read_text(encoding="utf-8")
    console = capsys.readouterr().err
    assert "REDACTED" in written
    assert TELEGRAM_TOKEN not in written
    assert TELEGRAM_TOKEN not in console


def test_configure_logging_covers_handlers_already_on_the_root_logger(clean_logging):
    stream = io.StringIO()
    clean_logging.addHandler(logging.StreamHandler(stream))
    configure_logging()
    logging.getLogger("engine.test").warning(TELEGRAM_TOKEN)
    assert TELEGRAM_TOKEN not in stream.getvalue()


def test_configure_logging_redacts_known_secrets(clean_logging, tmp_path):
    configure_logging(log_dir=tmp_path, known_secrets=["plain-looking"])
    logging.getLogger("engine.test").warning("value plain-looking")
    for handler in clean_logging.handlers:
        handler.flush()
    assert "plain-looking" not in (tmp_path / "engine.log").read_text(encoding="utf-8")


def test_calling_configure_logging_twice_does_not_double_the_output(clean_logging, tmp_path):
    configure_logging(log_dir=tmp_path)
    configure_logging(log_dir=tmp_path)
    logging.getLogger("engine.test").warning("once")
    for handler in clean_logging.handlers:
        handler.flush()
    assert (tmp_path / "engine.log").read_text(encoding="utf-8").count("once") == 1


@pytest.mark.parametrize("name", ["httpx", "httpx2", "httpcore"])
def test_http_client_loggers_are_at_warning(clean_logging, name):
    logging.getLogger(name).setLevel(logging.DEBUG)
    configure_logging()
    assert logging.getLogger(name).level == logging.WARNING


def test_a_broken_log_call_does_not_raise_through_the_filter(clean_logging):
    configure_logging()
    stream = _captured(clean_logging)
    logging.getLogger("engine.test").warning("%d is not a number", "x")
    assert "%d is not a number" in stream.getvalue()


def _record_with(**fields) -> logging.LogRecord:
    return logging.LogRecord(
        "engine.test", logging.ERROR, __file__, 1, "msg", None, fields.pop("exc_info", None),
        **fields,
    )


def test_the_filter_formats_and_redacts_exc_info_itself():
    # On its own, with no earlier handler having cached the traceback text.
    try:
        raise RuntimeError(f"boom {TELEGRAM_TOKEN}")
    except RuntimeError:
        record = _record_with(exc_info=sys.exc_info())
    assert RedactingFilter().filter(record) is True
    assert record.exc_text and "boom" in record.exc_text
    assert TELEGRAM_TOKEN not in record.exc_text
    assert TELEGRAM_TOKEN not in logging.Formatter().format(record)


def test_the_filter_redacts_an_already_cached_traceback():
    record = _record_with()
    record.exc_text = f"cached {TELEGRAM_TOKEN}"
    RedactingFilter().filter(record)
    assert TELEGRAM_TOKEN not in record.exc_text


def test_the_filter_redacts_stack_info():
    record = _record_with(sinfo=f"frame with {TELEGRAM_TOKEN}")
    RedactingFilter().filter(record)
    assert record.stack_info == "frame with [REDACTED]"
    assert TELEGRAM_TOKEN not in logging.Formatter().format(record)


def test_a_real_stack_trace_is_redacted(clean_logging):
    configure_logging(known_secrets=["UNIQUE_FRAME_NAME"])
    stream = _captured(clean_logging)

    def UNIQUE_FRAME_NAME():  # noqa: N802 - the name is the secret here
        logging.getLogger("engine.test").warning("stack", stack_info=True)

    UNIQUE_FRAME_NAME()
    assert "UNIQUE_FRAME_NAME" not in stream.getvalue()
    assert "Stack (most recent call last)" in stream.getvalue()


def test_a_record_that_skipped_the_factory_is_still_redacted_by_the_handler(clean_logging):
    # Queue listeners rebuild records with makeLogRecord, which goes round the factory.
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    clean_logging.addHandler(handler)
    configure_logging()
    record = logging.makeLogRecord({"msg": TELEGRAM_TOKEN, "levelno": logging.WARNING})
    handler.handle(record)
    assert stream.getvalue() == "[REDACTED]\n"


def test_a_handler_on_a_child_logger_gets_a_redacted_record(clean_logging):
    configure_logging()
    stream = io.StringIO()
    child = logging.getLogger("engine.child")
    child.addHandler(logging.StreamHandler(stream))
    try:
        child.warning("token %s", TELEGRAM_TOKEN)
    finally:
        child.handlers.clear()
    assert TELEGRAM_TOKEN not in stream.getvalue()


def _run_engine_python(code: str) -> subprocess.CompletedProcess:
    setup = (
        "import logging, warnings\n"
        "from core.logging_setup import configure_logging\n"
        f"configure_logging(known_secrets=[{LEAK!r}])\n"
    )
    return subprocess.run(
        [sys.executable, "-c", setup + code],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=ENGINE_ROOT,
        timeout=60,
    )


def test_an_uncaught_exception_is_redacted():
    result = _run_engine_python(
        f"raise RuntimeError('https://api.telegram.org/bot{TELEGRAM_TOKEN}/x {LEAK}')"
    )
    assert result.returncode == 1
    assert "RuntimeError" in result.stderr
    assert TELEGRAM_TOKEN not in result.stderr
    assert LEAK not in result.stderr


def test_an_uncaught_exception_in_a_thread_is_redacted():
    result = _run_engine_python(
        "import threading\n"
        "def boom():\n"
        f"    raise RuntimeError({LEAK!r})\n"
        "thread = threading.Thread(target=boom)\n"
        "thread.start()\n"
        "thread.join()\n"
    )
    assert "RuntimeError" in result.stderr
    assert LEAK not in result.stderr


def test_a_warning_is_redacted():
    result = _run_engine_python(f"warnings.warn('careful {LEAK}')")
    assert "careful" in result.stderr
    assert LEAK not in result.stderr


def test_a_second_configure_keeps_known_secrets():
    result = _run_engine_python(f"configure_logging()\nlogging.getLogger('x').warning({LEAK!r})")
    assert LEAK not in result.stderr


def test_keyboard_interrupt_is_left_to_python():
    result = _run_engine_python("raise KeyboardInterrupt")
    assert "KeyboardInterrupt" in result.stderr
    assert "CRITICAL" not in result.stderr
