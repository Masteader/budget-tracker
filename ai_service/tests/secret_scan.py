"""
Working-tree secret scanner used by the security tests.

Known-leaked credentials are stored ONLY as SHA-256 digests: the scanner extracts
candidate tokens with generic patterns, hashes each one and compares the digest.
Never paste a raw secret value into this file (the repository is public).

Digest inventory (values were committed to git history and must stay rotated):
- WEBHOOK_SECRET (64-hex)          f516a232df76...
- legacy shared token (64-hex)      c3d7f5e65951...
- APP_AUTH_TOKEN (bt_sec_ prefix)   34164266f633...
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
from pathlib import Path
from typing import Iterable, List

LEAKED_SECRET_SHA256 = frozenset({
    "f516a232df76f55242de350e7fb3c7206faebd3f61837940c8fd3f3e2010c501",
    "c3d7f5e65951829de17a3059e324e8d7af141db025c14c38dc21b26939343571",
    "34164266f6331cd78f94c36156999fc85bf5bd2dc96cb772d8833d88040314e5",
})

HEX64_RE = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])")
BT_SEC_RE = re.compile(r"bt_sec_[A-Za-z0-9_-]{8,}")
SB_SECRET_RE = re.compile(r"sb_secret_[A-Za-z0-9_-]{8,}")
JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")

SCAN_EXTENSIONS = {
    ".py", ".dart", ".ts", ".tsx", ".js", ".jsx", ".md", ".json", ".yaml", ".yml",
    ".toml", ".sh", ".env", ".example", ".html", ".txt",
}
SKIP_DIRS = {"node_modules", "build", ".dart_tool", "__pycache__", ".pytest_cache", "dist", ".venv", "venv"}
# Obvious test/placeholder values that are allowed to carry a real-looking prefix.
PLACEHOLDER_MARKERS = ("mock", "test", "example", "dummy", "placeholder", "your")


def sha256_hex(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _jwt_role(token: str) -> str | None:
    try:
        payload_b64 = token.split(".")[1]
        payload_b64 += "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64.encode("ascii")))
        role = payload.get("role")
        return str(role) if role is not None else None
    except Exception:
        return None


def scan_text(text: str) -> List[str]:
    """Return human-readable reasons (never the secret value) for every hit in text."""
    reasons: List[str] = []
    for pat, kind in ((HEX64_RE, "hex64"), (BT_SEC_RE, "bt_sec"), (SB_SECRET_RE, "sb_secret"), (JWT_RE, "jwt")):
        for m in pat.finditer(text):
            token = m.group(0)
            digest = sha256_hex(token)
            line = text.count("\n", 0, m.start()) + 1
            if digest in LEAKED_SECRET_SHA256:
                reasons.append(f"line {line}: known-leaked {kind} (sha256 {digest[:12]})")
                continue
            lowered = token.lower()
            if kind == "bt_sec" and not any(mk in lowered for mk in PLACEHOLDER_MARKERS):
                reasons.append(f"line {line}: hardcoded app token with bt_sec_ prefix (sha256 {digest[:12]})")
            elif kind == "sb_secret" and not any(mk in lowered for mk in PLACEHOLDER_MARKERS):
                reasons.append(f"line {line}: hardcoded Supabase secret key (sha256 {digest[:12]})")
            elif kind == "jwt" and _jwt_role(token) == "service_role":
                reasons.append(f"line {line}: hardcoded service_role JWT (sha256 {digest[:12]})")
    return reasons


def iter_files(roots: Iterable[Path]) -> Iterable[Path]:
    for root in roots:
        if root.is_file():
            yield root
            continue
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            if path.suffix in SCAN_EXTENSIONS or path.name.startswith(".env"):
                yield path


def scan_paths(roots: Iterable[Path], repo_root: Path) -> List[str]:
    findings: List[str] = []
    for path in iter_files(roots):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for reason in scan_text(text):
            findings.append(f"{path.relative_to(repo_root)} {reason}")
    return findings
