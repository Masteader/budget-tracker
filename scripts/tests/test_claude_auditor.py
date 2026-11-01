"""
scripts/tests/test_claude_auditor.py
Hermetic unit tests for scripts/claude_auditor.py.
No Anthropic API calls are made.
"""

import re
import pytest
from pathlib import Path
import sys

# Add scripts directory to sys.path so we can import claude_auditor
SCRIPTS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS_DIR))

from claude_auditor import _should_exclude, _SECRET_CONTENT_REGEX


def test_should_exclude_secret_files():
    assert _should_exclude(".env.audit") is True
    assert _should_exclude("ai_service/.env") is True
    assert _should_exclude("flutter_app/dart_defines.json") is True
    assert _should_exclude(".env") is True
    assert _should_exclude("ai_service/service_account.json") is True
    assert _should_exclude("docs/review/audit_spend.json") is True


def test_env_files_never_collected():
    env_paths = [
        ".env",
        ".env.local",
        ".env.production",
        ".env.audit",
        "ai_service/.env",
        "flutter_app/.env",
        "certs/server.pem",
        "certs/server.key",
        "flutter_app/dart_defines.json",
        "sub/dir/dart_defines.json",
    ]
    for path in env_paths:
        assert _should_exclude(path) is True, f"{path} should be excluded"


def test_should_exclude_normal_code_files():
    assert _should_exclude("flutter_app/lib/models/operating_cash.dart") is False
    assert _should_exclude("ai_service/routers/budgets.py") is False


def test_secret_content_regex_detects_service_role_and_keys():
    assert _SECRET_CONTENT_REGEX.search('SUPABASE_SERVICE_ROLE_KEY = "xyz"') is not None
    assert _SECRET_CONTENT_REGEX.search('SUPABASE_SECRET_KEY="abc"') is not None
    assert _SECRET_CONTENT_REGEX.search('"role": "service_role"') is not None
    assert _SECRET_CONTENT_REGEX.search('"role" : "service_role"') is not None
    assert _SECRET_CONTENT_REGEX.search('sb_secret_12345') is not None

    # Safe public code should not match
    assert _SECRET_CONTENT_REGEX.search('SUPABASE_ANON_KEY = "public-anon-key"') is None
    assert _SECRET_CONTENT_REGEX.search('"role": "authenticated"') is None


def test_verdict_parsing_logic():
    def parse_approved(result: str) -> bool:
        return "AUDIT VERDICT: REVISE" not in result and bool(
            re.search(r"^#?\s*AUDIT VERDICT:\s*APPROVED", result, re.M)
        )

    approved_text = "# AUDIT VERDICT: APPROVED\nPush to main. All rules satisfied."
    assert parse_approved(approved_text) is True

    clean_approved = "AUDIT VERDICT: APPROVED\nEverything looks good."
    assert parse_approved(clean_approved) is True

    # Quoting APPROVED inside a REVISE report must NOT be approved
    revise_quoting_approved = """# AUDIT VERDICT: REVISE

PROMPT FOR ANTIGRAVITY:
Do not output AUDIT VERDICT: APPROVED until all tests pass.
Fix issue 1.
"""
    assert parse_approved(revise_quoting_approved) is False

    pure_revise = "# AUDIT VERDICT: REVISE\nFix line 22."
    assert parse_approved(pure_revise) is False

