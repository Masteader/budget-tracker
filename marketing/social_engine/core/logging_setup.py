"""Logging with secrets removed (spec Sections 9.4 and 11.2).

`httpx` logs request URLs at info level, and Telegram's URLs contain the bot token, so the
HTTP client loggers are held at WARNING. Every record is redacted when it is created, so a
handler on any logger, however late it was added, only sees clean text. Uncaught exceptions
and warnings are routed through logging for the same reason.

Every pattern here has to run in linear time: `redact` sees whatever a log call receives,
including text from web pages, and a slow pattern would stall the engine.
"""

from __future__ import annotations

import logging
import re
import sys
import threading
from collections.abc import Iterable
from pathlib import Path
from types import TracebackType

_MARK = "[REDACTED]"
_NOISY_HTTP_LOGGERS = ("httpx", "httpx2", "httpcore", "httpcore2")
_ENGINE_HANDLER = "_social_engine_handler"
_MIN_KNOWN_SECRET_LENGTH = 4

_SECRET_SHAPES = (
    # Not \b: in a Telegram URL the token follows the letters "bot" directly.
    re.compile(r"(?<!\d)\d{6,12}(?::|%3[Aa])[A-Za-z0-9_-]{30,}"),
    re.compile(r"sk-ant-[A-Za-z0-9_-]{8,}"),
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    # Azure Speech keys. A SHA-256 is 64 hex characters, so it does not match the first.
    re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])"),
    re.compile(r"(?<![A-Za-z0-9])[A-Za-z0-9]{84}(?![A-Za-z0-9])"),
)
_AFTER_BEARER = re.compile(r"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]+")
_AFTER_SECRET_NAME = re.compile(
    r"""(?ix)
    (
      (?<![a-z])                                 # so "monkey" is not a key
      (?:api[_-]?key|key|token|secret|password|passwd|pwd
         |credentials?|authorization|cookie|signature)
      (?:s|[_-][a-z0-9_-]{0,32})?                # tokens, TOKEN_OLD
    )
    (
      ["'\\]{0,4}\s{0,4}(?:=>|[:=]|%3D)\s{0,4}   # token=  "token": \"token\":
      | ["']\s{0,4},\s{0,4}(?=["'])              # ('AZURE_SPEECH_KEY', 'value')
    )
    (?:
      [\[({][^\n]{0,4096}                        # a structure: to the end of the line
      | (?:basic|bearer|digest|negotiate)\s+\S+  # Authorization: Basic value
      | b?["'\\]{0,4}[^\s"',;&\\\])}]+           # a plain value, perhaps b'...'
    )
    """
)

_known_secrets: set[str] = set()


def redact(text: str, known_secrets: Iterable[str] = ()) -> str:
    # Longest first, so a secret that starts with a shorter one does not leave a tail behind.
    for secret in sorted({*_known_secrets, *known_secrets}, key=len, reverse=True):
        if len(secret) >= _MIN_KNOWN_SECRET_LENGTH:
            text = text.replace(secret, _MARK)
    text = _AFTER_SECRET_NAME.sub(rf"\1\2{_MARK}", text)
    text = _AFTER_BEARER.sub(rf"\1{_MARK}", text)
    for shape in _SECRET_SHAPES:
        text = shape.sub(_MARK, text)
    return text


def forget_known_secrets() -> None:
    """Known secrets outlive `configure_logging` on purpose. This is for tests."""
    _known_secrets.clear()


def _clean_record(record: logging.LogRecord, known: Iterable[str] = ()) -> None:
    try:
        message = record.getMessage()
    except (TypeError, ValueError):
        message = str(record.msg)
    record.msg = redact(message, known)
    record.args = None
    # The text is made here, or a formatter would build it later from the raw exception.
    if record.exc_info and not record.exc_text:
        record.exc_text = logging.Formatter().formatException(record.exc_info)
    if record.exc_text:
        record.exc_text = redact(record.exc_text, known)
    if record.stack_info:
        record.stack_info = redact(record.stack_info, known)


class RedactingFilter(logging.Filter):
    """A second layer for records that did not come through the record factory."""

    def __init__(self, known_secrets: Iterable[str] = ()) -> None:
        super().__init__()
        self._known = tuple(known_secrets)

    def filter(self, record: logging.LogRecord) -> bool:
        _clean_record(record, self._known)
        return True


_plain_record_factory = logging.getLogRecordFactory()


def _redacting_record_factory(*args, **kwargs) -> logging.LogRecord:
    record = _plain_record_factory(*args, **kwargs)
    _clean_record(record)
    return record


def _log_uncaught(
    kind: type[BaseException], value: BaseException, traceback: TracebackType | None
) -> None:
    if issubclass(kind, KeyboardInterrupt):
        sys.__excepthook__(kind, value, traceback)
        return
    logging.getLogger("engine.uncaught").critical(
        "Uncaught exception", exc_info=(kind, value, traceback)
    )


def _log_uncaught_in_thread(args: threading.ExceptHookArgs) -> None:
    _log_uncaught(args.exc_type, args.exc_value or args.exc_type(), args.exc_traceback)


def configure_logging(
    log_dir: Path | None = None,
    level: int = logging.INFO,
    known_secrets: Iterable[str] = (),
) -> None:
    """Safe to call again: the engine's own handlers are replaced, not added to."""
    _known_secrets.update(known_secrets)
    logging.setLogRecordFactory(_redacting_record_factory)
    logging.captureWarnings(True)
    sys.excepthook = _log_uncaught
    threading.excepthook = _log_uncaught_in_thread

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

    redacting = RedactingFilter()
    for handler in root.handlers:
        handler.filters = [f for f in handler.filters if not isinstance(f, RedactingFilter)]
        handler.addFilter(redacting)

    for name in _NOISY_HTTP_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)
