"""Paths, startup guard, environment scrub and log redaction (spec Section 11, task A3)."""

import io
import logging
import os
from pathlib import Path

import pytest

from core.logging_setup import RedactingFilter, configure_logging, redact
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
    check_startup_environment({"PATH": "x", "NOT_" + FORBIDDEN_ENV_PREFIX + "URL": "x"})


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
    monkeypatch.setenv("SOME_PLAIN_SETTING", "keep")
    result = scrubbed_env("subscription")
    assert "AZURE_SPEECH_KEY" not in result
    assert result["SOME_PLAIN_SETTING"] == "keep"


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


def test_a_known_secret_is_redacted_even_when_it_has_no_recognised_shape():
    assert "plain-looking" not in redact("value plain-looking here", ["plain-looking"])


@pytest.fixture
def clean_logging():
    root = logging.getLogger()
    handlers, level = list(root.handlers), root.level
    watched = {name: logging.getLogger(name).level for name in ("httpx", "httpx2", "httpcore")}
    root.handlers = []
    yield root
    for handler in root.handlers:
        handler.close()
    root.handlers, root.level = handlers, level
    for name, previous in watched.items():
        logging.getLogger(name).setLevel(previous)


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
