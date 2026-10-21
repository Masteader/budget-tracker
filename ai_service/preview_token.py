"""
Server-signed preview tokens (PRODUCT-R6: one LLM call per expense).

A chat or receipt preview runs the model once and returns the parsed result together with a
``preview_token``: an HMAC-SHA256 signed envelope of the canonical parsed payload, the verified
user id, the household id, an expiry (15 minutes) and a binding to the input (a digest of the chat
message, or of the receipt photos and QR text). The commit sends the token back with the user's
edits; the server verifies it and inserts from the signed payload without calling the model again.
The user's edits still go through the same validation as a commit without a token.

Format: ``pt1.<key id>.<base64url canonical JSON claims>.<base64url HMAC>``. The payload is signed,
not encrypted; it only holds what the preview response already showed the same user.

Verification outcomes:
* ``valid``: signature, kind, user and household match and the token has not expired;
* ``expired``: a genuine token past its expiry: the caller re-parses (today's behaviour);
* ``unverifiable``: signed with another key (another process without PREVIEW_TOKEN_SECRET, or a
  rotated secret): the caller re-parses as well, since nothing proves tampering;
* anything else (malformed, bad signature, another user / household / kind) raises
  ``InvalidPreviewToken`` (HTTP 422 ``{"detail": {"code": "invalid_preview_token"}}``).

The key is derived from ``PREVIEW_TOKEN_SECRET`` (at least 32 characters). Without it every
process uses a random key and logs a warning: tokens then only verify on the process that issued
them, and a commit reaching another instance falls back to re-parsing.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import logging
import os
import secrets
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

TOKEN_VERSION = "pt1"
PREVIEW_TOKEN_TTL_SECONDS = 15 * 60
# A receipt with many line items still fits; larger previews get no token (commit re-parses).
MAX_PREVIEW_TOKEN_LENGTH = 512 * 1024
MIN_SECRET_LENGTH = 32
PREVIEW_TOKEN_SECRET_ENV = "PREVIEW_TOKEN_SECRET"

KIND_CHAT = "chat"
KIND_RECEIPT = "receipt"

_key_lock = threading.Lock()
_key: Optional[bytes] = None
_key_id: Optional[str] = None


class InvalidPreviewToken(ValueError):
    """A preview token that is malformed, tampered with or issued to someone else (HTTP 422)."""

    CODE = "invalid_preview_token"

    def __init__(self, reason: str = "invalid preview token"):
        super().__init__(reason)


class PreviewTokenExpired(ValueError):
    """An expired / unverifiable token on a request with nothing to re-parse (HTTP 422)."""

    CODE = "preview_token_expired"


@dataclass
class PreviewTokenCheck:
    status: str  # 'valid' | 'expired' | 'unverifiable'
    payload: Dict[str, Any] = field(default_factory=dict)
    binding: Dict[str, Any] = field(default_factory=dict)

    @property
    def valid(self) -> bool:
        return self.status == "valid"


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64d(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def canonical_json(value: Any) -> bytes:
    """Deterministic JSON (sorted keys, no whitespace, UTF-8)."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


def text_digest(value: Optional[str]) -> str:
    """SHA-256 of a text input ('' for none), used to bind a token to its message / QR code."""
    if not value:
        return ""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def images_digest(images_base64: Optional[List[str]]) -> str:
    """SHA-256 over the base64 photos (data-URL prefixes ignored), '' for none."""
    if not images_base64:
        return ""
    h = hashlib.sha256()
    for img in images_base64:
        clean = img.split(",", 1)[1] if isinstance(img, str) and "," in img else str(img)
        h.update(hashlib.sha256(clean.strip().encode("ascii", "ignore")).digest())
    return h.hexdigest()


def _load_key() -> tuple[bytes, str]:
    global _key, _key_id
    with _key_lock:
        if _key is None:
            secret = (os.environ.get(PREVIEW_TOKEN_SECRET_ENV) or "").strip()
            if len(secret) >= MIN_SECRET_LENGTH:
                _key = hashlib.sha256(b"budget-tracker/preview-token/v1|" + secret.encode("utf-8")).digest()
            else:
                if secret:
                    logger.warning(
                        "%s is shorter than %d characters; using a random per-process key instead.",
                        PREVIEW_TOKEN_SECRET_ENV, MIN_SECRET_LENGTH,
                    )
                else:
                    logger.warning(
                        "%s is not set; preview tokens use a random per-process key (a commit reaching "
                        "another instance re-parses with the LLM).", PREVIEW_TOKEN_SECRET_ENV,
                    )
                _key = secrets.token_bytes(32)
            _key_id = hashlib.sha256(b"kid|" + _key).hexdigest()[:10]
        return _key, _key_id  # type: ignore[return-value]


def reset_preview_token_key() -> None:
    """Forget the derived key (tests, secret rotation)."""
    global _key, _key_id
    with _key_lock:
        _key = None
        _key_id = None


def _sign(key: bytes, kid: str, body: str) -> str:
    return _b64e(hmac.new(key, f"{TOKEN_VERSION}.{kid}.{body}".encode("ascii"), hashlib.sha256).digest())


def issue_preview_token(
    kind: str,
    user_id: Optional[str],
    household_id: str,
    payload: Dict[str, Any],
    binding: Optional[Dict[str, Any]] = None,
    now: Optional[float] = None,
) -> Optional[str]:
    """A signed token for ``payload``; None when it would exceed MAX_PREVIEW_TOKEN_LENGTH."""
    key, kid = _load_key()
    issued = time.time() if now is None else now
    claims = {
        "v": 1,
        "k": kind,
        "u": str(user_id or ""),
        "h": str(household_id),
        "exp": int(issued) + PREVIEW_TOKEN_TTL_SECONDS,
        "b": binding or {},
        "p": payload,
    }
    try:
        body = _b64e(canonical_json(claims))
    except (TypeError, ValueError) as exc:
        logger.warning("Preview payload is not serialisable; no preview token issued: %s", exc)
        return None
    token = f"{TOKEN_VERSION}.{kid}.{body}.{_sign(key, kid, body)}"
    if len(token) > MAX_PREVIEW_TOKEN_LENGTH:
        logger.info("Preview token of %d characters exceeds the limit; commit will re-parse.", len(token))
        return None
    return token


def verify_preview_token(
    token: Any,
    kind: str,
    user_id: Optional[str],
    household_id: str,
    now: Optional[float] = None,
) -> PreviewTokenCheck:
    """Check a token sent back on commit (see the module docstring for the outcomes)."""
    if not isinstance(token, str) or not token or len(token) > MAX_PREVIEW_TOKEN_LENGTH:
        raise InvalidPreviewToken("malformed")
    parts = token.split(".")
    if len(parts) != 4 or parts[0] != TOKEN_VERSION or not all(parts):
        raise InvalidPreviewToken("malformed")
    _, kid, body, signature = parts
    key, current_kid = _load_key()
    if not hmac.compare_digest(kid, current_kid):
        return PreviewTokenCheck(status="unverifiable")
    if not hmac.compare_digest(signature, _sign(key, kid, body)):
        raise InvalidPreviewToken("bad signature")
    try:
        claims = json.loads(_b64d(body).decode("utf-8"))
    except (ValueError, UnicodeDecodeError, binascii.Error) as exc:
        raise InvalidPreviewToken("undecodable") from exc
    if not isinstance(claims, dict) or claims.get("v") != 1:
        raise InvalidPreviewToken("unsupported claims")
    if (
        claims.get("k") != kind
        or claims.get("u") != str(user_id or "")
        or claims.get("h") != str(household_id)
        or not isinstance(claims.get("p"), dict)
        or not isinstance(claims.get("b"), dict)
        or not isinstance(claims.get("exp"), int)
    ):
        raise InvalidPreviewToken("issued for another request")
    current = time.time() if now is None else now
    if claims["exp"] < current:
        return PreviewTokenCheck(status="expired")
    return PreviewTokenCheck(status="valid", payload=claims["p"], binding=claims["b"])
