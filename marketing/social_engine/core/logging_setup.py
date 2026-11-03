"""Logging with secrets removed (spec Sections 9.4 and 11.2).

`httpx` logs request URLs at info level, and Telegram's URLs contain the bot token, so the
HTTP client loggers are held at WARNING and a filter redacts anything shaped like a secret.
"""

from __future__ import annotations

import logging
import re
import sys
from collections.abc import Iterable
from pathlib import Path

_MARK = "[REDACTED]"
_NOISY_HTTP_LOGGERS = ("httpx", "httpx2", "httpcore", "httpcore2")
_ENGINE_HANDLER = "_social_engine_handler"
_MIN_KNOWN_SECRET_LENGTH = 4

_SECRET_SHAPES = (
    # Not \b: in a Telegram URL the token follows the letters "bot" directly.
    re.compile(r"(?<!\d)\d{6,12}:[A-Za-z0-9_-]{30,}"),
    re.compile(r"sk-ant-[A-Za-z0-9_-]{8,}"),
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    # Azure Speech keys. A SHA-256 is 64 hex characters, so it does not match the first.
    re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])"),
    re.compile(r"(?<![A-Za-z0-9])[A-Za-z0-9]{84}(?![A-Za-z0-9])"),
)
_AFTER_BEARER = re.compile(r"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]+")
_AFTER_SECRET_NAME = re.compile(
    r"""(?ix)
    ([a-z0-9_-]*(?:key|token|secret|password))   # a name like AZURE_SPEECH_KEY
    (["']?\s*[:=]\s*["']?)                       # then : or =, perhaps quoted
    [^\s"',;&]+                                  # then the value
    """
)


def redact(text: str, known_secrets: Iterable[str] = ()) -> str:
    for secret in sorted(known_secrets, key=len, reverse=True):
        if len(secret) >= _MIN_KNOWN_SECRET_LENGTH:
            text = text.replace(secret, _MARK)
    text = _AFTER_BEARER.sub(rf"\1{_MARK}", text)
    text = _AFTER_SECRET_NAME.sub(rf"\1\2{_MARK}", text)
    for shape in _SECRET_SHAPES:
        text = shape.sub(_MARK, text)
    return text


class RedactingFilter(logging.Filter):
    """Attach to handlers: a filter on a logger misses records from its child loggers."""

    def __init__(self, known_secrets: Iterable[str] = ()) -> None:
        super().__init__()
        self._known = tuple(known_secrets)

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            message = record.getMessage()
        except (TypeError, ValueError):
            message = str(record.msg)
        record.msg = redact(message, self._known)
        record.args = None
        if record.exc_info and not record.exc_text:
            record.exc_text = logging.Formatter().formatException(record.exc_info)
        if record.exc_text:
            record.exc_text = redact(record.exc_text, self._known)
        if record.stack_info:
            record.stack_info = redact(record.stack_info, self._known)
        return True


def configure_logging(
    log_dir: Path | None = None,
    level: int = logging.INFO,
    known_secrets: Iterable[str] = (),
) -> None:
    """Safe to call again: the engine's own handlers are replaced, not added to."""
    root = logging.getLogger()
    root.setLevel(level)
    for handler in [h for h in root.handlers if getattr(h, _ENGINE_HANDLER, False)]:
        root.removeHandler(handler)
        handler.close()

    new_handlers: list[logging.Handler] = [logging.StreamHandler(sys.stderr)]
    if log_dir is not None:
        Path(log_dir).mkdir(parents=True, exist_ok=True)
        new_handlers.append(logging.FileHandler(Path(log_dir) / "engine.log", encoding="utf-8"))

    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
    for handler in new_handlers:
        handler.setFormatter(formatter)
        setattr(handler, _ENGINE_HANDLER, True)
        root.addHandler(handler)

    redacting = RedactingFilter(known_secrets)
    for handler in root.handlers:
        handler.filters = [f for f in handler.filters if not isinstance(f, RedactingFilter)]
        handler.addFilter(redacting)

    for name in _NOISY_HTTP_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)
