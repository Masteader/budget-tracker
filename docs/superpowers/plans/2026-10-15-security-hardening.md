# Security & Architecture Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 5 critical security vulnerabilities and 6 medium architecture issues identified in the AI service review, and remove dead SMS code.

**Architecture:** Replace hardcoded secrets with environment-only configuration, add Supabase JWT authorization middleware to bind requests to households, sanitize error responses, add input validation and request size limits, remove dead SMS webhook code, and split the 1200-line god file into focused route modules.

**Tech Stack:** Python 3.11+, FastAPI, Pydantic, Supabase (python client + JWT), Dart/Flutter, pytest, `python-jose[cryptography]` for JWT decoding.

**Spec:** [`ai_service_review.md`](file:///C:/Users/A/.gemini/antigravity-ide/brain/d430ed31-ed07-4d71-a773-b62bf29ce5aa/ai_service_review.md)

## Global Constraints

- All secrets must come from environment variables only — **no hardcoded fallbacks**, not even for dev
- Existing tests in `ai_service/tests/` must continue to pass (update as needed for new auth flow)
- Python code follows existing patterns: `asyncio.to_thread()` for sync Supabase calls, `HTTPException` for errors
- Flutter code uses `--dart-define` for all configuration — no `defaultValue` for secrets
- All new code must have tests
- Commits follow conventional commits (`fix:`, `feat:`, `refactor:`)
- Run all tests with: `cd ai_service && python -m pytest tests/ -v`

---

### Task 1: Remove All Hardcoded Secrets (Python + Dart)

**Files:**
- Modify: `ai_service/main.py:100-108` (APP_AUTH_TOKEN fallback)
- Modify: `ai_service/main.py:143-149` (WEBHOOK_SECRET fallback)
- Modify: `flutter_app/lib/supabase_config.dart:1-39` (all defaultValues)
- Modify: `flutter_app/lib/services/api/base_api_client.dart:7` (hardcoded appAuthToken)
- Modify: `ai_service/tests/test_api_endpoints.py:18` (fallback SECRET)
- Test: `ai_service/tests/test_secret_config.py` (new)

**Interfaces:**
- Consumes: nothing
- Produces: `APP_AUTH_TOKEN` and `WEBHOOK_SECRET` are now purely env-var driven; tests use `os.environ` to set them

- [ ] **Step 1: Write tests for secret configuration behavior**

Create `ai_service/tests/test_secret_config.py`:

```python
"""Tests that secrets are never hardcoded and require env var configuration."""
import os
import importlib
from unittest.mock import patch


def test_app_auth_token_requires_env_var():
    """APP_AUTH_TOKEN must come from environment, no fallback."""
    with patch.dict(os.environ, {"APP_AUTH_TOKEN": "", "ENV": "development"}, clear=False):
        import main
        # In dev without token, requests from proxies should still be rejected
        # The token should be empty string, not a hardcoded fallback
        assert main.APP_AUTH_TOKEN == "" or os.environ.get("APP_AUTH_TOKEN", "") != ""


def test_webhook_secret_requires_env_var():
    """WEBHOOK_SECRET must come from environment, no fallback."""
    with patch.dict(os.environ, {"WEBHOOK_SECRET": "", "ENV": "development"}, clear=False):
        import main
        # Should not contain the old hardcoded value
        assert main.WEBHOOK_SECRET != "<redacted: rotated>"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_secret_config.py -v`
Expected: FAIL — the hardcoded fallbacks still exist

- [ ] **Step 3: Remove APP_AUTH_TOKEN hardcoded fallback in main.py**

In `ai_service/main.py`, replace lines 99–108 with:

```python
# ─── Auth Token & Firewall (OWASP A01 / A02) ───────────────────────────────────
APP_AUTH_TOKEN = os.environ.get("APP_AUTH_TOKEN", "").strip()
IS_PRODUCTION = os.environ.get("ENV", "development").lower() == "production"

if not APP_AUTH_TOKEN:
    logger.warning(
        "APP_AUTH_TOKEN is not configured. "
        "Firewall middleware will reject all proxied/tunnel requests. "
        "Set APP_AUTH_TOKEN in environment variables."
    )
```

No `else` branch. No fallback token.

- [ ] **Step 4: Remove WEBHOOK_SECRET hardcoded fallback in main.py**

In `ai_service/main.py`, replace lines 143–149 with:

```python
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "").strip()
if not WEBHOOK_SECRET:
    logger.warning(
        "WEBHOOK_SECRET is not configured. "
        "HMAC signature verification will reject all signed requests. "
        "Set WEBHOOK_SECRET in environment variables."
    )
```

No dev fallback. No hardcoded hex string.

- [ ] **Step 5: Remove hardcoded secrets from Flutter Dart files**

In `flutter_app/lib/supabase_config.dart`, remove all `defaultValue` parameters:

```dart
/// Supabase + FastAPI configuration.
/// All values MUST be provided via --dart-define at build time.
/// Example: flutter build apk --dart-define=SUPABASE_URL=https://...
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Deprecated: use [supabasePublishableKey] instead.
const supabaseAnonKey = supabasePublishableKey;

const fastapiBaseUrl = String.fromEnvironment('FASTAPI_BASE_URL');

const fastapiWebhookUrl = String.fromEnvironment('FASTAPI_WEBHOOK_URL');

const authRedirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL');

const webhookSecret = String.fromEnvironment('WEBHOOK_SECRET');
```

In `flutter_app/lib/services/api/base_api_client.dart`, remove the hardcoded `appAuthToken`:

```dart
class BaseApiClient {
  static const String appAuthToken = String.fromEnvironment('APP_AUTH_TOKEN');
  final http.Client _client;
```

- [ ] **Step 6: Update test helper to use env var for SECRET**

In `ai_service/tests/test_api_endpoints.py`, change line 18:

```python
SECRET = os.environ.get("WEBHOOK_SECRET", "")
```

Remove the hardcoded fallback. Tests that need signing must have `WEBHOOK_SECRET` set in the environment. Create `ai_service/tests/conftest.py`:

```python
"""Shared test fixtures and environment setup."""
import os

# Set test secrets before any imports of main
os.environ.setdefault("WEBHOOK_SECRET", "test_secret_for_ci_only_do_not_use_in_prod")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token_for_ci_only")
os.environ.setdefault("ENV", "development")
```

Also update `test_api_endpoints.py` line 18 to read from the env:

```python
SECRET = os.environ["WEBHOOK_SECRET"]
```

- [ ] **Step 7: Run all tests to verify nothing broke**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
git add ai_service/main.py flutter_app/lib/supabase_config.dart flutter_app/lib/services/api/base_api_client.dart ai_service/tests/
git commit -m "fix(security): remove all hardcoded secrets, require env vars only"
```

---

### Task 2: Add JWT-Based Per-User Authorization (IDOR Fix)

**Files:**
- Create: `ai_service/auth.py`
- Modify: `ai_service/main.py` (add `verify_household_access` dependency to all household endpoints)
- Modify: `ai_service/requirements.txt` (add `python-jose[cryptography]`)
- Test: `ai_service/tests/test_auth.py` (new)

**Interfaces:**
- Consumes: `APP_AUTH_TOKEN`, `WEBHOOK_SECRET` from Task 1 (env vars)
- Produces: `verify_household_access(request: Request, household_id: str) -> str` — FastAPI dependency that extracts the Supabase JWT from the `Authorization: Bearer <token>` header, validates it, looks up the user's `household_id` from the `users` table, and raises `HTTPException(403)` if the requested `household_id` doesn't match. Returns the validated `household_id`.

- [ ] **Step 1: Add python-jose to requirements**

Append to `ai_service/requirements.txt`:

```
python-jose[cryptography]>=3.3.0
```

Then run: `cd ai_service && pip install python-jose[cryptography]`

- [ ] **Step 2: Write the failing auth tests**

Create `ai_service/tests/test_auth.py`:

```python
"""Tests for JWT-based household authorization."""
import os
import pytest
from unittest.mock import patch, MagicMock
from fastapi import HTTPException

# Ensure test env is configured before import
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")


def test_missing_authorization_header_raises_401():
    """Requests without Authorization header must be rejected."""
    from auth import verify_household_access
    from fastapi import Request

    mock_request = MagicMock(spec=Request)
    mock_request.headers = {}

    import asyncio
    with pytest.raises(HTTPException) as exc_info:
        asyncio.get_event_loop().run_until_complete(
            verify_household_access(mock_request, "some-household-id")
        )
    assert exc_info.value.status_code == 401


def test_mismatched_household_raises_403():
    """User requesting data for a household they don't belong to must get 403."""
    from auth import _check_household_membership

    # User belongs to household-A but requests household-B
    with pytest.raises(HTTPException) as exc_info:
        _check_household_membership(
            user_household_id="household-A",
            requested_household_id="household-B",
        )
    assert exc_info.value.status_code == 403


def test_matching_household_passes():
    """User requesting their own household data should pass."""
    from auth import _check_household_membership

    # Should not raise
    _check_household_membership(
        user_household_id="household-A",
        requested_household_id="household-A",
    )
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ai_service && python -m pytest tests/test_auth.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'auth'`

- [ ] **Step 4: Implement auth.py**

Create `ai_service/auth.py`:

```python
"""
JWT-based per-user authorization for the Budget Tracker API.

Decodes the Supabase JWT from the Authorization header, extracts the user ID,
looks up which household the user belongs to, and validates that the requested
household_id matches.

This prevents IDOR attacks where an authenticated user could access another
household's data by guessing/brute-forcing household UUIDs.
"""

from __future__ import annotations

import logging
import os
from typing import Optional

from fastapi import HTTPException, Request, status

logger = logging.getLogger(__name__)

# Supabase JWT secret — this is the JWT_SECRET from Supabase project settings
SUPABASE_JWT_SECRET = os.environ.get("SUPABASE_JWT_SECRET", "").strip()


def _decode_supabase_jwt(token: str) -> dict:
    """
    Decode and validate a Supabase-issued JWT.
    Returns the decoded payload dict.
    Raises HTTPException(401) on invalid/expired tokens.
    """
    if not SUPABASE_JWT_SECRET:
        logger.error("SUPABASE_JWT_SECRET is not configured — cannot verify JWTs.")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server authentication not configured.",
        )

    try:
        from jose import jwt, JWTError

        payload = jwt.decode(
            token,
            SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
        return payload
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
        )


def _extract_bearer_token(request: Request) -> str:
    """Extract Bearer token from Authorization header. Raises 401 if missing."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header. Expected: Bearer <token>",
        )
    return auth_header[7:]  # Strip "Bearer " prefix


def _check_household_membership(
    user_household_id: Optional[str],
    requested_household_id: str,
) -> None:
    """
    Verify that the user belongs to the requested household.
    Raises HTTPException(403) if there's a mismatch.
    """
    if not user_household_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User is not a member of any household.",
        )
    if user_household_id != requested_household_id:
        logger.warning(
            "IDOR attempt blocked: user belongs to household %s but requested %s",
            user_household_id,
            requested_household_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this household.",
        )


async def verify_household_access(request: Request, household_id: str) -> str:
    """
    FastAPI dependency that validates the caller has access to the given household.

    Usage in endpoint:
        @app.get("/budgets/breakdown")
        async def get_budget_breakdown(
            household_id: str,
            _auth: str = Depends(verify_household_access),
        ):

    Returns the validated household_id on success.
    Raises HTTPException(401) for missing/invalid token.
    Raises HTTPException(403) for household mismatch.
    """
    import asyncio
    from supabase_client import get_client

    token = _extract_bearer_token(request)
    payload = _decode_supabase_jwt(token)

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not contain a valid user ID.",
        )

    # Look up the user's household from the database
    client = get_client()
    response = await asyncio.to_thread(
        lambda: client.table("users")
        .select("household_id")
        .eq("id", user_id)
        .single()
        .execute()
    )

    user_data = response.data
    if not user_data:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User profile not found.",
        )

    _check_household_membership(user_data.get("household_id"), household_id)
    return household_id
```

- [ ] **Step 5: Run auth tests to verify they pass**

Run: `cd ai_service && python -m pytest tests/test_auth.py -v`
Expected: PASS (at least the unit tests for `_check_household_membership`)

- [ ] **Step 6: Wire auth dependency into main.py endpoints**

Add the import at the top of `ai_service/main.py` (near line 23):

```python
from fastapi import FastAPI, HTTPException, Request, status, Response, Depends
from auth import verify_household_access
```

Then add `Depends(verify_household_access)` to **every endpoint that takes `household_id`**. Example pattern — apply this to ALL household-bearing endpoints:

For **query param** endpoints like `get_budget_breakdown`:
```python
@app.get("/budgets/breakdown", tags=["budgets"])
async def get_budget_breakdown(
    request: Request,
    household_id: str,
    cycle_key: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
```

For **path param** endpoints like `get_household_payday_endpoint`:
```python
@app.get("/households/{household_id}/payday", tags=["households"])
async def get_household_payday_endpoint(
    request: Request,
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
```

For **body param** endpoints like `add_budget_category`, extract `household_id` from the body in the dependency. In these cases, verify inside the handler body directly:
```python
@app.post("/budgets/categories", tags=["budgets"])
async def add_budget_category(request: Request, req: CategoryCreateRequest):
    await verify_household_access(request, req.household_id)
```

Apply this to every endpoint that accepts `household_id` — the full list:
- `salary_cycle_forecast`
- `list_salary_cycles`
- `get_household_payday_endpoint`
- `update_household_payday_endpoint`
- `get_household_income_endpoint`
- `update_household_income_endpoint`
- `get_household_rollover_rule_endpoint`
- `update_household_rollover_rule_endpoint`
- `get_household_savings_summary_endpoint`
- `create_household_role_invite_endpoint`
- `claim_household_role_invite_endpoint`
- `record_household_reimbursement_endpoint`
- `get_recurring_bills`
- `toggle_recurring_bill`
- `list_recurring_bill_candidates`
- `list_installments`
- `create_installment_plan`
- `pay_installment_endpoint`
- `recalculate_budgets_endpoint`
- `get_budget_breakdown`
- `add_budget_category`
- `set_sub_allocations`
- `add_sub_category`
- `get_sub_categories_route`
- `rename_sub_category_endpoint`
- `remove_sub_category_endpoint`
- `delete_budget_category`
- `list_household_dependents`
- `add_household_dependent`
- `remove_household_dependent`
- `simulate_purchase_affordability`
- `household_settlement`
- `get_household_categories_endpoint`
- `toggle_category_endpoint`
- `create_custom_category_endpoint`
- `grocery_price_history`
- `shopping_basket_optimize`
- `export_statement_pdf`
- `chat_transaction`
- `scan_receipt`
- `support_chat`

- [ ] **Step 7: Update existing tests to mock auth**

Update `ai_service/tests/conftest.py` to add an auto-mock fixture:

```python
import pytest

TEST_HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"

@pytest.fixture(autouse=True)
def mock_auth(monkeypatch):
    """
    Auto-mock JWT verification in all tests so existing tests keep passing.
    Tests that specifically test auth behavior should override this.
    """
    async def fake_verify(request, household_id):
        return household_id

    monkeypatch.setattr("auth.verify_household_access", fake_verify)
```

- [ ] **Step 8: Add SUPABASE_JWT_SECRET to .env.example**

Append to `ai_service/.env.example`:

```
# Supabase JWT secret — found in Supabase Dashboard → Project Settings → API → JWT Secret
SUPABASE_JWT_SECRET=<your-supabase-jwt-secret>

# App-level auth token for firewall middleware (Flutter ↔ FastAPI)
# Generate with: python -c "import secrets; print('bt_sec_' + secrets.token_hex(16))"
APP_AUTH_TOKEN=<generate-a-random-token>
```

- [ ] **Step 9: Run all tests**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS

- [ ] **Step 10: Commit**

```bash
git add ai_service/auth.py ai_service/main.py ai_service/requirements.txt ai_service/tests/ ai_service/.env.example
git commit -m "feat(security): add JWT-based per-user authorization to prevent IDOR attacks"
```

---

### Task 3: Sanitize Error Responses (Stop Leaking Internals)

**Files:**
- Modify: `ai_service/main.py` (all ~30 instances of `detail=str(exc)`)
- Test: `ai_service/tests/test_error_sanitization.py` (new)

**Interfaces:**
- Consumes: nothing
- Produces: All 500 error responses now return `{"detail": "Internal server error. Reference: <correlation_id>"}` instead of raw exception strings. Helper function: `_safe_error_response(exc: Exception, status_code: int = 500, public_message: str = "An internal error occurred.") -> HTTPException`

- [ ] **Step 1: Write the failing test**

Create `ai_service/tests/test_error_sanitization.py`:

```python
"""Tests that internal errors don't leak exception details to API callers."""
import json
import os
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from main import app

client = TestClient(app)


@patch("salary_cycle.get_cycle_breakdown")
def test_500_error_does_not_leak_exception_message(mock_breakdown):
    """Internal errors should return a generic message, not str(exc)."""
    mock_breakdown.side_effect = RuntimeError("Connection to database failed at 10.0.0.5:5432")

    response = client.get("/budgets/breakdown", params={"household_id": "f860188e-23b5-4749-b180-868c956151a6"})
    assert response.status_code == 500
    data = response.json()
    # Must NOT contain the internal error details
    assert "10.0.0.5" not in data.get("detail", "")
    assert "database" not in data.get("detail", "").lower()
    # Should contain a reference ID for debugging
    assert "reference" in data.get("detail", "").lower() or "ref" in data.get("detail", "").lower()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_error_sanitization.py -v`
Expected: FAIL — the current code returns `detail=str(exc)` which contains the database IP

- [ ] **Step 3: Create error helper and replace all instances**

Add a helper function near the top of `ai_service/main.py` (after the logger definition, around line 63):

```python
import uuid as _uuid


def _safe_error_response(
    exc: Exception,
    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR,
    public_message: str = "An internal error occurred.",
) -> HTTPException:
    """
    Create an HTTPException that logs the full error server-side
    but returns only a generic message + correlation ID to the client.
    """
    ref_id = _uuid.uuid4().hex[:12]
    logger.error("Error ref=%s: %s", ref_id, exc, exc_info=True)
    return HTTPException(
        status_code=status_code,
        detail=f"{public_message} Reference: {ref_id}",
    )
```

Then replace **every** occurrence of this pattern in `main.py`:

```python
# BEFORE (appears ~30 times):
raise HTTPException(status_code=500, detail=str(exc))

# AFTER:
raise _safe_error_response(exc)
```

And for 422/400 validation errors, keep a user-friendly message but strip internal details:

```python
# BEFORE:
raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))

# AFTER:
raise _safe_error_response(exc, status_code=422, public_message="Invalid request format.")
```

And for the LangGraph agent error at line 334:

```python
# BEFORE:
raise HTTPException(status_code=500, detail=f"Agent error: {exc}")

# AFTER:
raise _safe_error_response(exc, public_message="Failed to process transaction.")
```

Apply this change to every `except` block in the file. There are approximately 30 instances. Do not miss any.

- [ ] **Step 4: Run all tests**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/main.py ai_service/tests/test_error_sanitization.py
git commit -m "fix(security): sanitize error responses, stop leaking internal exception details"
```

---

### Task 4: Add Request Body Size Limits

**Files:**
- Modify: `ai_service/main.py` (add size-checking middleware)
- Test: `ai_service/tests/test_request_limits.py` (new)

**Interfaces:**
- Consumes: nothing
- Produces: Middleware that rejects request bodies exceeding `MAX_REQUEST_BODY_BYTES` (default 10MB) with HTTP 413

- [ ] **Step 1: Write the failing test**

Create `ai_service/tests/test_request_limits.py`:

```python
"""Tests for request body size limits."""
import os
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_oversized_request_rejected():
    """Requests exceeding MAX_REQUEST_BODY_BYTES should return 413."""
    # Create a payload larger than the default 10MB limit
    oversized_body = "x" * (11 * 1024 * 1024)  # 11MB
    response = client.post(
        "/agent/chat-transaction",
        content=oversized_body,
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413


def test_normal_sized_request_accepted():
    """Normal-sized requests should not be blocked by size limits."""
    response = client.get("/health")
    assert response.status_code == 200
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_request_limits.py::test_oversized_request_rejected -v`
Expected: FAIL — no size limit middleware exists

- [ ] **Step 3: Add size limit middleware to main.py**

Add after the CORS middleware block (around line 97) in `ai_service/main.py`:

```python
# ─── Request Body Size Limit (OWASP A04: DoS Protection) ──────────────────────
MAX_REQUEST_BODY_BYTES = int(os.environ.get("MAX_REQUEST_BODY_BYTES", str(10 * 1024 * 1024)))  # 10MB default


@app.middleware("http")
async def request_size_limit_middleware(request: Request, call_next):
    """Reject request bodies exceeding MAX_REQUEST_BODY_BYTES to prevent DoS."""
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_REQUEST_BODY_BYTES:
        from starlette.responses import JSONResponse
        return JSONResponse(
            status_code=413,
            content={"detail": f"Request body too large. Maximum allowed: {MAX_REQUEST_BODY_BYTES // (1024 * 1024)}MB."},
        )
    return await call_next(request)
```

> **Important:** Place this middleware BEFORE the firewall middleware so oversized requests are rejected early.

- [ ] **Step 4: Run all tests**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/main.py ai_service/tests/test_request_limits.py
git commit -m "fix(security): add request body size limit middleware to prevent DoS"
```

---

### Task 5: Validate household_id as UUID Everywhere

**Files:**
- Modify: `ai_service/models.py` (add UUID validator to all models with `household_id`)
- Modify: `ai_service/main.py` (add UUID validation to query/path param endpoints)
- Test: `ai_service/tests/test_uuid_validation.py` (new)

**Interfaces:**
- Consumes: Pydantic models from `models.py`
- Produces: All `household_id` fields validated as UUID format before hitting the database. Helper: `_validate_uuid(value: str, field_name: str = "household_id") -> str`

- [ ] **Step 1: Write the failing test**

Create `ai_service/tests/test_uuid_validation.py`:

```python
"""Tests for UUID validation on household_id parameters."""
import os
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_invalid_household_id_rejected():
    """Non-UUID household_id should return 422 or 400."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "not-a-uuid; DROP TABLE transactions;--"},
    )
    assert response.status_code in (400, 422)


def test_valid_uuid_household_id_accepted():
    """Valid UUID should pass validation (may fail for other reasons)."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "f860188e-23b5-4749-b180-868c956151a6"},
    )
    # Should not be a validation error (may be 500 due to missing DB, but not 400/422)
    assert response.status_code != 422
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_uuid_validation.py::test_invalid_household_id_rejected -v`
Expected: FAIL — garbage `household_id` values are currently accepted

- [ ] **Step 3: Add UUID validation helper to main.py**

Add near the top of `ai_service/main.py` (after the imports):

```python
from uuid import UUID as _UUID


def _validate_uuid(value: str, field_name: str = "household_id") -> str:
    """Validate a string is a valid UUID. Raises HTTPException(400) if not."""
    try:
        _UUID(value)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid {field_name}: must be a valid UUID.",
        )
    return value
```

Then add `_validate_uuid(household_id)` at the start of every endpoint handler that takes `household_id` as a query or path parameter, right after the existing `if not household_id` check. Replace the pattern:

```python
# BEFORE:
if not household_id:
    raise HTTPException(status_code=400, detail="household_id is required.")

# AFTER:
if not household_id:
    raise HTTPException(status_code=400, detail="household_id is required.")
_validate_uuid(household_id)
```

Apply to all endpoints that accept `household_id` as query/path param.

- [ ] **Step 4: Add UUID validator to Pydantic models in models.py**

In `ai_service/models.py`, add a reusable validator and apply it to all models that have a `household_id` field:

```python
from uuid import UUID as _UUID

def _uuid_validator(v: str) -> str:
    """Validate household_id is a proper UUID string."""
    try:
        _UUID(v)
    except (ValueError, AttributeError):
        raise ValueError(f"Invalid UUID: {v}")
    return v
```

Then add the validator to these models: `CategoryCreateRequest`, `SubAllocationsRequest`, `SubCategoryCreateRequest`, `HouseholdReimbursementRequest`, `ShoppingBasketOptimizeRequest`, `RecurringBillToggleRequest`:

```python
class CategoryCreateRequest(BaseModel):
    household_id: str
    code: str
    category: str
    allocated_amount: float = 0.0
    is_flexible: bool = True
    keywords: list[str] = Field(default_factory=list)

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)
```

Add the same `@field_validator("household_id")` block to every model listed above that has a `household_id` field.

- [ ] **Step 5: Run all tests**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add ai_service/main.py ai_service/models.py ai_service/tests/test_uuid_validation.py
git commit -m "fix(security): validate household_id as UUID to prevent injection"
```

---

### Task 6: Remove Dead SMS Webhook Code

**Files:**
- Modify: `ai_service/main.py` (remove `/webhook/sms` endpoint, remove `sms_graph` import, remove SMS-only models from import)
- Modify: `ai_service/docker-compose.yml` (remove `ALLOWED_SENDERS`)
- Do NOT delete: `ai_service/graph.py` — verify nothing else uses it first
- Test: `ai_service/tests/test_sms_removal.py` (new)

**Interfaces:**
- Consumes: nothing
- Produces: Cleaner codebase with no dead SMS code

- [ ] **Step 1: Verify what still references SMS code**

Search for all references before deleting. Run these commands:

```bash
cd ai_service
grep -rn "sms_graph\|SMSWebhookRequest\|SMSWebhookResponse\|AgentState\|webhook_sms\|/webhook/sms" --include="*.py" . | grep -v __pycache__ | grep -v .pyc
```

Review the output. Only delete code that is not used by anything other than the SMS webhook endpoint.

Also check the Flutter side:

```bash
cd ../flutter_app
grep -rn "webhook/sms\|webhookSms\|sms_graph" --include="*.dart" lib/ | head -20
```

- [ ] **Step 2: Write a test confirming SMS endpoint no longer exists**

Create `ai_service/tests/test_sms_removal.py`:

```python
"""Tests confirming the SMS webhook endpoint has been removed."""
import os
os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_sms_webhook_endpoint_removed():
    """POST /webhook/sms should return 404 (or 405) since SMS feature is removed."""
    response = client.post("/webhook/sms", json={"raw_sms": "test", "sender": "SNB", "received_at": "2026-01-01", "household_id": "test"})
    assert response.status_code in (404, 405)


def test_health_still_works():
    """Health endpoint must still work after SMS removal."""
    response = client.get("/health")
    assert response.status_code == 200
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_sms_removal.py::test_sms_webhook_endpoint_removed -v`
Expected: FAIL — the endpoint still exists and returns 200 or 401

- [ ] **Step 4: Remove SMS code from main.py**

1. Remove the import at line 30:
```python
# DELETE this line:
from graph import sms_graph
```

2. Remove `AgentState` and `SMSWebhookRequest`, `SMSWebhookResponse` from the models import at lines 31–53 (only if no other endpoint uses them — check with grep first). `AgentState` is used only by the SMS webhook.

3. Remove the entire `/webhook/sms` endpoint handler (lines 277–358).

4. Remove the `ALLOWED_SENDERS` env var reference if it exists anywhere in `main.py`.

- [ ] **Step 5: Remove ALLOWED_SENDERS from docker-compose.yml**

In `ai_service/docker-compose.yml`, remove line 21:
```yaml
# DELETE:
ALLOWED_SENDERS: ${ALLOWED_SENDERS:-SNB,ALRAJHI,9200}
```

- [ ] **Step 6: Run all tests**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS. Fix any test that was testing the SMS endpoint (update or remove those tests).

- [ ] **Step 7: Commit**

```bash
git add ai_service/main.py ai_service/models.py ai_service/docker-compose.yml ai_service/tests/
git commit -m "refactor: remove dead SMS webhook code, feature no longer used"
```

---

### Task 7: Split main.py Into Route Modules

**Files:**
- Create: `ai_service/routes/__init__.py`
- Create: `ai_service/routes/budgets.py`
- Create: `ai_service/routes/households.py`
- Create: `ai_service/routes/analytics.py`
- Create: `ai_service/routes/receipts.py`
- Create: `ai_service/routes/chat.py`
- Create: `ai_service/routes/reports.py`
- Create: `ai_service/routes/support.py`
- Modify: `ai_service/main.py` (reduce to ~100 lines: app creation, middleware, router includes)

**Interfaces:**
- Consumes: `auth.verify_household_access` from Task 2, `_safe_error_response` from Task 3, `_validate_uuid` from Task 5
- Produces: Same API surface (all routes, paths, and response shapes identical), just organized into modules

- [ ] **Step 1: Create the routes package**

Create `ai_service/routes/__init__.py`:

```python
"""Route modules for the Budget Tracker API."""
```

- [ ] **Step 2: Move shared helpers to a utility module**

Before splitting, move `_safe_error_response` and `_validate_uuid` from `main.py` into a new file so route modules can import them without circular imports.

Create `ai_service/utils.py`:

```python
"""Shared utility functions for route handlers."""

import logging
import uuid as _uuid
from uuid import UUID

from fastapi import HTTPException, status

logger = logging.getLogger(__name__)


def safe_error_response(
    exc: Exception,
    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR,
    public_message: str = "An internal error occurred.",
) -> HTTPException:
    """
    Create an HTTPException that logs the full error server-side
    but returns only a generic message + correlation ID to the client.
    """
    ref_id = _uuid.uuid4().hex[:12]
    logger.error("Error ref=%s: %s", ref_id, exc, exc_info=True)
    return HTTPException(
        status_code=status_code,
        detail=f"{public_message} Reference: {ref_id}",
    )


def validate_uuid(value: str, field_name: str = "household_id") -> str:
    """Validate a string is a valid UUID. Raises HTTPException(400) if not."""
    try:
        UUID(value)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid {field_name}: must be a valid UUID.",
        )
    return value
```

Update `main.py` to import from `utils.py` instead:
```python
from utils import safe_error_response as _safe_error_response, validate_uuid as _validate_uuid
```

- [ ] **Step 3: Extract budget routes**

Create `ai_service/routes/budgets.py`. Move all endpoints with `tags=["budgets"]` or `tags=["installments"]` into this file:

```python
"""Budget management routes: cycles, breakdown, categories, sub-allocations, installments."""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status

from auth import verify_household_access
from utils import safe_error_response, validate_uuid
from models import (
    CategoryCreateRequest,
    SubAllocationsRequest,
    SubCategoryCreateRequest,
    SubCategoryRenameRequest,
    RecurringBillToggleRequest,
    CategoryToggleRequest,
    CustomCategoryCreateRequest,
)

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get(
    "/budgets/salary-cycle-forecast",
    tags=["budgets"],
    summary="Get active Saudi salary cycle stats, burn rate velocity, and projected run-out date.",
)
async def salary_cycle_forecast(
    request: Request,
    household_id: str,
    payday_day: Optional[int] = None,
    _auth: str = Depends(verify_household_access),
):
    """Returns salary cycle progress, days to payday, burn rate, and pace indicator."""
    validate_uuid(household_id)
    from salary_cycle import get_salary_cycle_forecast
    try:
        return await asyncio.to_thread(get_salary_cycle_forecast, household_id, None, payday_day)
    except Exception as exc:
        raise safe_error_response(exc)


# ... Move ALL other budget/installment endpoints here following the same pattern ...
# Use @router instead of @app, import from utils and auth
```

Move these endpoints to `routes/budgets.py`:
- `salary_cycle_forecast`, `list_salary_cycles`, `get_budget_breakdown`
- `add_budget_category`, `set_sub_allocations`, `add_sub_category`
- `get_sub_categories_route`, `rename_sub_category_endpoint`
- `remove_sub_category_endpoint`, `delete_budget_category`
- `get_recurring_bills`, `toggle_recurring_bill`, `list_recurring_bill_candidates`
- `list_installments`, `create_installment_plan`, `pay_installment_endpoint`
- `recalculate_budgets_endpoint`, `simulate_purchase_affordability`

- [ ] **Step 4: Extract household routes**

Create `ai_service/routes/households.py`. Move all endpoints with `tags=["households"]`, `tags=["dependents"]`, `tags=["settlement"]`, `tags=["categories"]`. Follow the same pattern: `APIRouter`, imports from `auth` and `utils`.

Move these endpoints:
- `get_household_payday_endpoint`, `update_household_payday_endpoint`
- `get_household_income_endpoint`, `update_household_income_endpoint`
- `get_household_rollover_rule_endpoint`, `update_household_rollover_rule_endpoint`
- `get_household_savings_summary_endpoint`
- `create_household_role_invite_endpoint`, `inspect_household_role_invite_endpoint`
- `claim_household_role_invite_endpoint`, `record_household_reimbursement_endpoint`
- `household_settlement`
- `list_household_dependents`, `add_household_dependent`, `remove_household_dependent`
- `get_household_categories_endpoint`, `toggle_category_endpoint`, `create_custom_category_endpoint`

- [ ] **Step 5: Extract remaining route modules**

Create these files, each with `router = APIRouter()`:

`ai_service/routes/analytics.py` — move: `grocery_price_history`, `shopping_basket_optimize`

`ai_service/routes/receipts.py` — move: `scan_receipt` (include the rate limiting import)

`ai_service/routes/chat.py` — move: `chat_transaction`

`ai_service/routes/reports.py` — move: `export_statement_pdf`

`ai_service/routes/support.py` — move: `support_chat`

Each file follows the same pattern as `routes/budgets.py`: import `APIRouter`, create `router = APIRouter()`, use `@router.get`/`@router.post` instead of `@app.get`/`@app.post`.

- [ ] **Step 6: Slim down main.py to just app setup + router includes**

After extraction, `ai_service/main.py` should be approximately 100-150 lines containing only:
- App creation and config
- CORS middleware
- Request size limit middleware
- Firewall token middleware
- HMAC verification function (still needed by route modules)
- Landing page / static file / health endpoints
- Router includes:

```python
from routes.budgets import router as budgets_router
from routes.households import router as households_router
from routes.analytics import router as analytics_router
from routes.receipts import router as receipts_router
from routes.chat import router as chat_router
from routes.reports import router as reports_router
from routes.support import router as support_router

app.include_router(budgets_router)
app.include_router(households_router)
app.include_router(analytics_router)
app.include_router(receipts_router)
app.include_router(chat_router)
app.include_router(reports_router)
app.include_router(support_router)
```

- Entry point (`if __name__ == "__main__"`)

- [ ] **Step 7: Run all tests**

Run: `cd ai_service && python -m pytest tests/ -v`
Expected: ALL PASS — every endpoint should still be reachable at the same paths.

- [ ] **Step 8: Commit**

```bash
git add ai_service/main.py ai_service/utils.py ai_service/routes/
git commit -m "refactor: split main.py god file into focused route modules"
```

---

### Task 8: Eliminate Lazy Imports Across Route Handlers

**Files:**
- Modify: `ai_service/routes/budgets.py`
- Modify: `ai_service/routes/households.py`
- Modify: `ai_service/routes/analytics.py`
- Modify: `ai_service/routes/receipts.py`
- Modify: `ai_service/routes/chat.py`
- Modify: `ai_service/routes/reports.py`
- Modify: `ai_service/routes/support.py`
- Test: `ai_service/tests/test_imports.py` (new)

**Interfaces:**
- Consumes: Route modules created in Task 7
- Produces: All domain module imports (`salary_cycle`, `supabase_client`, `recurring_detector`, `chat_parser`, `receipt_scanner`, `pdf_generator`) are declared at module top-level. No inline `from xyz import ...` inside route handlers. Cold-call latency is eliminated and import dependencies are verified at startup.

- [ ] **Step 1: Write test detecting inline/lazy imports**

Create `ai_service/tests/test_imports.py`:

```python
"""Tests ensuring no lazy/inline imports exist inside route handler functions."""
import ast
from pathlib import Path


def test_no_inline_imports_in_routes():
    """Verify all imports in route files are at module top-level."""
    routes_dir = Path(__file__).resolve().parent.parent / "routes"
    if not routes_dir.exists():
        return

    route_files = list(routes_dir.glob("*.py"))
    assert len(route_files) > 0, "No route files found to inspect"

    violations = []
    for route_file in route_files:
        if route_file.name == "__init__.py":
            continue
        tree = ast.parse(route_file.read_text(encoding="utf-8"), filename=str(route_file))
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                for sub_node in ast.walk(node):
                    if isinstance(sub_node, (ast.Import, ast.ImportFrom)):
                        violations.append(
                            f"{route_file.name}:{sub_node.lineno} inside {node.name}()"
                        )

    assert not violations, f"Found inline imports inside handlers: {violations}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_imports.py -v`
Expected: FAIL — existing routes still have inline `from salary_cycle import ...`, etc.

- [ ] **Step 3: Move all imports to top-level in `routes/budgets.py`**

In `ai_service/routes/budgets.py`, hoist all dependencies to the top:

```python
from salary_cycle import (
    get_salary_cycle_forecast,
    get_available_cycles_for_household,
    get_cycle_breakdown,
    recalculate_household_budgets,
    simulate_purchase,
)
from recurring_detector import (
    fetch_household_recurring_bills,
    toggle_household_recurring_bill,
    get_recurring_bill_candidates,
)
from supabase_client import (
    add_custom_budget_category,
    set_budget_sub_allocations,
    create_sub_category,
    get_sub_categories,
    rename_sub_category,
    delete_sub_category,
    remove_budget_category,
    fetch_installments,
    create_installment,
    pay_installment,
)
```

Remove all inner `from salary_cycle import ...` and `from supabase_client import ...` calls inside handlers. Handlers directly call the imported functions.

- [ ] **Step 4: Move all imports to top-level in `routes/households.py`**

In `ai_service/routes/households.py`, hoist:

```python
from supabase_client import (
    get_household_payday,
    set_household_payday,
    get_household_income,
    set_household_income,
    get_household_rollover_rule,
    set_household_rollover_rule,
    get_household_savings_summary,
    create_household_role_invite,
    inspect_household_role_invite,
    claim_household_role_invite,
    record_household_reimbursement,
    get_household_settlement_summary,
    get_dependents,
    add_dependent,
    remove_dependent,
    get_household_categories,
    toggle_category_visibility,
    create_custom_category,
)
```

Remove all inline `from supabase_client import ...` statements inside the endpoint functions.

- [ ] **Step 5: Move all imports to top-level in remaining route files**

- In `ai_service/routes/analytics.py`:
  ```python
  from analytics import get_grocery_price_history, optimize_shopping_basket
  ```
- In `ai_service/routes/receipts.py`:
  ```python
  from receipt_scanner import process_receipt_scan
  ```
- In `ai_service/routes/chat.py`:
  ```python
  from chat_parser import process_chat_transaction
  ```
- In `ai_service/routes/reports.py`:
  ```python
  from pdf_generator import generate_statement_pdf
  ```
- In `ai_service/routes/support.py`:
  ```python
  from support_agent import process_support_message
  ```

- [ ] **Step 6: Run import and regression tests**

Run: `cd ai_service && python -m pytest tests/test_imports.py tests/ -v`
Expected: ALL PASS. No circular imports, no inline import latency.

- [ ] **Step 7: Commit**

```bash
git add ai_service/routes/ ai_service/tests/test_imports.py
git commit -m "refactor: move all domain imports to module top-level across routes"
```

---

### Task 9: Distributed Persistent Rate Limiting (Redis with In-Memory Fallback)

**Files:**
- Create: `ai_service/rate_limiter.py`
- Modify: `ai_service/routes/receipts.py` (use distributed rate limiter)
- Modify: `ai_service/requirements.txt` (add `redis>=5.0.0`)
- Modify: `ai_service/docker-compose.yml` (add redis service)
- Modify: `ai_service/.env.example` (add `REDIS_URL`)
- Test: `ai_service/tests/test_rate_limiter.py` (new)

**Interfaces:**
- Consumes: `REDIS_URL` from env var (`redis://localhost:6379/0`), `RECEIPT_SCAN_WINDOW_SECONDS` (600), `RECEIPT_SCAN_MAX_REQUESTS` (10)
- Produces: `async def check_rate_limit(key: str, max_requests: int = 10, window_seconds: int = 600) -> None`
  - Uses Redis Sorted Sets (`ZADD`, `ZREMRANGEBYSCORE`, `ZCARD`, `EXPIRE`) for atomic sliding-window rate limiting that persists across deploys and scales across multiple FastAPI worker processes.
  - Automatically falls back to thread-safe local in-memory sliding window if Redis is not configured or temporarily unreachable (with warning logged), ensuring zero downtime.
  - Raises `HTTPException(429)` with accurate `Retry-After` header when limit is breached.

- [ ] **Step 1: Add redis to requirements**

In `ai_service/requirements.txt`, append:
```
redis>=5.0.0
```
Run: `cd ai_service && pip install redis>=5.0.0`

- [ ] **Step 2: Write failing rate limiter tests**

Create `ai_service/tests/test_rate_limiter.py`:

```python
"""Tests for distributed rate limiting with sliding window and Redis/memory fallback."""
import asyncio
import os
import pytest
from unittest.mock import AsyncMock, patch
from fastapi import HTTPException

os.environ.setdefault("WEBHOOK_SECRET", "test_secret")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token")


@pytest.mark.asyncio
async def test_in_memory_fallback_enforces_limit():
    """When REDIS_URL is absent, fallback in-memory rate limiter enforces limit."""
    from rate_limiter import SlidingWindowRateLimiter

    limiter = SlidingWindowRateLimiter(redis_url=None)
    key = "household_test_123"

    # Allow up to 3 requests in a 10s window
    for _ in range(3):
        await limiter.check_rate_limit(key, max_requests=3, window_seconds=10)

    # 4th request must raise 429
    with pytest.raises(HTTPException) as exc_info:
        await limiter.check_rate_limit(key, max_requests=3, window_seconds=10)
    assert exc_info.value.status_code == 429
    assert "Retry-After" in exc_info.value.headers


@pytest.mark.asyncio
async def test_redis_sliding_window_logic():
    """Verify Redis ZREMRANGEBYSCORE + ZADD pipeline is invoked when Redis is enabled."""
    from rate_limiter import SlidingWindowRateLimiter

    mock_redis = AsyncMock()
    mock_pipeline = AsyncMock()
    mock_redis.pipeline.return_value.__aenter__.return_value = mock_pipeline
    mock_pipeline.execute.return_value = [0, 1, 4, True]  # zrem, zadd, zcard=4 (exceeded limit 3), expire

    limiter = SlidingWindowRateLimiter(redis_url="redis://localhost:6379/0")
    limiter._redis = mock_redis

    with pytest.raises(HTTPException) as exc_info:
        await limiter.check_rate_limit("household_test_redis", max_requests=3, window_seconds=600)
    assert exc_info.value.status_code == 429
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_rate_limiter.py -v`
Expected: FAIL — `rate_limiter.py` does not exist yet.

- [ ] **Step 4: Implement rate_limiter.py**

Create `ai_service/rate_limiter.py`:

```python
"""Distributed sliding-window rate limiter supporting Redis and local memory fallback."""

from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import Optional

from fastapi import HTTPException, status

logger = logging.getLogger(__name__)


class SlidingWindowRateLimiter:
    """
    Sliding window rate limiter.
    Uses Redis ZSET if REDIS_URL is available; falls back to an in-memory dict.
    """

    def __init__(self, redis_url: Optional[str] = None):
        self.redis_url = redis_url or os.environ.get("REDIS_URL", "").strip()
        self._redis = None
        self._memory_history: dict[str, list[float]] = {}
        self._lock = asyncio.Lock()

    async def _get_redis(self):
        if self._redis is None and self.redis_url:
            try:
                import redis.asyncio as aioredis
                client = aioredis.from_url(
                    self.redis_url,
                    encoding="utf-8",
                    decode_responses=True,
                    socket_connect_timeout=2.0,
                )
                await client.ping()
                self._redis = client
                logger.info("Connected to Redis for distributed rate limiting.")
            except Exception as exc:
                logger.warning("Failed to connect to Redis (%s); falling back to in-memory rate limiting.", exc)
                self._redis = None
        return self._redis

    async def check_rate_limit(
        self,
        key: str,
        max_requests: int = 10,
        window_seconds: int = 600,
    ) -> None:
        """
        Enforce sliding window rate limit.
        Raises HTTPException(429) if request count exceeds max_requests within window_seconds.
        """
        now = time.time()
        cutoff = now - window_seconds
        redis_client = await self._get_redis()

        if redis_client:
            try:
                redis_key = f"rl:{key}"
                pipe = redis_client.pipeline(transaction=True)
                pipe.zremrangebyscore(redis_key, 0, cutoff)
                pipe.zadd(redis_key, {str(now): now})
                pipe.zcard(redis_key)
                pipe.expire(redis_key, window_seconds + 60)
                results = await pipe.execute()

                current_count = results[2]
                if current_count > max_requests:
                    # Get oldest timestamp in window to compute Retry-After
                    oldest_entries = await redis_client.zrange(redis_key, 0, 0, withscores=True)
                    retry_after = max(1, int(oldest_entries[0][1] + window_seconds - now)) if oldest_entries else window_seconds
                    logger.warning(
                        "Rate limit exceeded (Redis) for %s: %d/%d in %ds. Retry-After: %ds",
                        key, current_count, max_requests, window_seconds, retry_after,
                    )
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail=f"Rate limit exceeded: Maximum {max_requests} requests per {window_seconds // 60} minutes allowed. Please try again in {retry_after} seconds.",
                        headers={"Retry-After": str(retry_after)},
                    )
                return
            except HTTPException:
                raise
            except Exception as exc:
                logger.warning("Redis rate limit check failed (%s); falling back to in-memory for this check.", exc)

        # In-memory fallback
        async with self._lock:
            timestamps = self._memory_history.get(key, [])
            valid_timestamps = [t for t in timestamps if t > cutoff]

            if len(valid_timestamps) >= max_requests:
                oldest = valid_timestamps[0]
                retry_after = max(1, int(oldest + window_seconds - now))
                logger.warning(
                    "Rate limit exceeded (Memory) for %s: %d/%d in %ds. Retry-After: %ds",
                    key, len(valid_timestamps), max_requests, window_seconds, retry_after,
                )
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Rate limit exceeded: Maximum {max_requests} requests per {window_seconds // 60} minutes allowed. Please try again in {retry_after} seconds.",
                    headers={"Retry-After": str(retry_after)},
                )

            valid_timestamps.append(now)
            self._memory_history[key] = valid_timestamps

            # Housekeeping
            if len(self._memory_history) > 500:
                stale_keys = [k for k, ts in self._memory_history.items() if not ts or ts[-1] <= cutoff]
                for sk in stale_keys:
                    self._memory_history.pop(sk, None)


# Default global instance
default_rate_limiter = SlidingWindowRateLimiter()


async def check_receipt_scan_rate_limit(key: str) -> None:
    """Convenience dependency for receipt scan rate limiting."""
    await default_rate_limiter.check_rate_limit(key, max_requests=10, window_seconds=600)
```

- [ ] **Step 5: Wire rate_limiter into receipts route and docker-compose**

In `ai_service/routes/receipts.py`:
```python
from rate_limiter import check_receipt_scan_rate_limit
```

In `ai_service/docker-compose.yml`, add Redis service:
```yaml
  redis:
    image: redis:7-alpine
    container_name: budget_tracker_redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

volumes:
  redis_data:
```
Add `REDIS_URL: ${REDIS_URL:-redis://redis:6379/0}` under `ai_service` environment.
Update `ai_service/.env.example` with `REDIS_URL=redis://localhost:6379/0`.

- [ ] **Step 6: Run rate limiter tests**

Run: `cd ai_service && python -m pytest tests/test_rate_limiter.py -v`
Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add ai_service/rate_limiter.py ai_service/routes/receipts.py ai_service/docker-compose.yml ai_service/requirements.txt ai_service/.env.example ai_service/tests/test_rate_limiter.py
git commit -m "feat(security): implement distributed Redis sliding-window rate limiting with memory fallback"
```

---

### Task 10: Flutter Client Authentication & Secret Hardening Integration

**Files:**
- Modify: `flutter_app/lib/services/api/base_api_client.dart`
- Modify: `flutter_app/lib/supabase_config.dart`
- Test: `flutter_app/test/services/api/base_api_client_test.dart` (new/updated)

**Interfaces:**
- Consumes: `Supabase.instance.client.auth.currentSession?.accessToken` from `supabase_flutter`
- Produces: `BaseApiClient` automatically attaches `Authorization: Bearer <access_token>` to every request header, eliminates dead SMS `/webhook/sms` path manipulation, and consumes `APP_AUTH_TOKEN` from `--dart-define`.

- [ ] **Step 1: Write Flutter test for BaseApiClient headers**

Create or update `flutter_app/test/services/api/base_api_client_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';

void main() {
  test('BaseApiClient attaches Authorization bearer token when provided', () async {
    String? capturedAuthHeader;
    String? capturedAppToken;

    final mockClient = MockClient((request) async {
      capturedAuthHeader = request.headers['Authorization'];
      capturedAppToken = request.headers['X-App-Token'];
      return http.Response('{"status": "ok"}', 200);
    });

    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'fake_supabase_jwt_token',
    );

    await client.post('/budgets/breakdown', {'household_id': '11111111-1111-1111-1111-111111111111'}, shouldSign: false);

    expect(capturedAuthHeader, equals('Bearer fake_supabase_jwt_token'));
    expect(capturedAppToken, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/services/api/base_api_client_test.dart`
Expected: FAIL — `authTokenProvider` does not exist and `Authorization` header is not set.

- [ ] **Step 3: Update BaseApiClient in Flutter**

In `flutter_app/lib/services/api/base_api_client.dart`, update class definition:

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_config.dart';

typedef AuthTokenProvider = String? Function();

class BaseApiClient {
  static const String appAuthToken = String.fromEnvironment('APP_AUTH_TOKEN');
  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;

  BaseApiClient({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider;

  String? get _currentAccessToken {
    if (_authTokenProvider != null) {
      return _authTokenProvider!();
    }
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  String get baseUrl {
    if (fastapiBaseUrl.isNotEmpty) {
      return fastapiBaseUrl;
    }
    return fastapiWebhookUrl;
  }

  Map<String, String> buildHeaders({String? signature}) {
    final token = _currentAccessToken;
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'X-App-Token': appAuthToken,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (signature != null) 'X-Signature': signature,
    };
  }

  String sign(String body) {
    if (webhookSecret.isEmpty) {
      return '';
    }
    final key = utf8.encode(webhookSecret);
    final bytes = utf8.encode(body);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return 'sha256=${digest.toString()}';
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool shouldSign = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final payload = jsonEncode(body);
    final signature = shouldSign ? sign(payload) : null;
    final url = path.startsWith('http') ? Uri.parse(path) : Uri.parse('$baseUrl$path');

    try {
      final response = await _client
          .post(url, headers: buildHeaders(signature: signature), body: payload)
          .timeout(timeout);
      if (response.statusCode >= 400) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
        return {
          'status': 'error',
          'status_code': response.statusCode,
          'message': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = path.startsWith('http')
        ? Uri.parse(path).replace(queryParameters: queryParams)
        : Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);

    try {
      final response = await _client.get(uri, headers: buildHeaders()).timeout(timeout);
      if (response.statusCode >= 400) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
        return {
          'status': 'error',
          'status_code': response.statusCode,
          'message': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }
}
```

- [ ] **Step 4: Run Flutter test**

Run: `cd flutter_app && flutter test test/services/api/base_api_client_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/api/base_api_client.dart flutter_app/test/services/api/base_api_client_test.dart
git commit -m "feat(auth): inject Supabase JWT in Flutter BaseApiClient and clean up dead SMS URL handling"
```

---

### Task 11: Leaked Secret Rotation Runbook & Security Verification Suite

**Files:**
- Create: `docs/runbooks/security-secret-rotation.md`
- Test: `ai_service/tests/test_security_posture.py` (new)

**Interfaces:**
- Consumes: All hardened modules from Tasks 1–10
- Produces: Comprehensive automated regression test verifying that all 11 security/architecture issues are sealed, plus an operator runbook to rotate leaked Git secrets in production environments.

- [ ] **Step 1: Write comprehensive security posture test**

Create `ai_service/tests/test_security_posture.py`:

```python
"""Comprehensive verification of security hardening across the AI service."""
import os
import pytest
from fastapi.testclient import TestClient

OLD_LEAKED_SECRET = "<redacted: rotated>"
OLD_LEAKED_TOKEN = "<redacted: rotated>"

os.environ["WEBHOOK_SECRET"] = "new_secure_test_secret_32bytes_value"
os.environ["APP_AUTH_TOKEN"] = "new_secure_app_token_value"
os.environ["ENV"] = "production"

from main import app

client = TestClient(app)


def test_old_leaked_token_rejected_when_rotated():
    """Requests with the old leaked token must be rejected in production."""
    response = client.get(
        "/health",
        headers={"X-Forwarded-For": "1.2.3.4", "X-App-Token": OLD_LEAKED_TOKEN},
    )
    assert response.status_code == 403


def test_oversized_payload_rejected_with_413():
    """Payloads exceeding 10MB limit must receive 413."""
    oversized = "a" * (11 * 1024 * 1024)
    response = client.post(
        "/agent/chat-transaction",
        content=oversized,
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413


def test_unauthenticated_household_endpoint_rejected_with_401():
    """Household endpoints require Authorization header."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "f860188e-23b5-4749-b180-868c956151a6"},
        headers={"X-App-Token": "new_secure_app_token_value"},
    )
    assert response.status_code in (401, 403)


def test_non_uuid_household_rejected():
    """Non-UUID values must return 400 or 422."""
    response = client.get(
        "/budgets/breakdown",
        params={"household_id": "malicious-injection-string"},
        headers={"X-App-Token": "new_secure_app_token_value"},
    )
    assert response.status_code in (400, 422)


def test_sms_webhook_returns_404():
    """Dead SMS webhook must return 404."""
    response = client.post("/webhook/sms", json={})
    assert response.status_code in (404, 405)
```

- [ ] **Step 2: Run security posture test**

Run: `cd ai_service && python -m pytest tests/test_security_posture.py -v`
Expected: ALL PASS

- [ ] **Step 3: Create secret rotation runbook**

Create `docs/runbooks/security-secret-rotation.md`:

````markdown
# Runbook: Rotating Compromised Secrets

## 1. Secrets Compromised in Git History
The following values were committed to Git and must be treated as permanently compromised:
- `WEBHOOK_SECRET`: `<redacted: rotated>`
- `APP_AUTH_TOKEN`: `<redacted: rotated>`
- Default Supabase Anon Key in `supabase_config.dart`

## 2. Generating New Secrets
Run the following in a secure terminal:
```bash
python -c "import secrets; print('WEBHOOK_SECRET=' + secrets.token_hex(32))"
python -c "import secrets; print('APP_AUTH_TOKEN=bt_sec_' + secrets.token_hex(16))"
```

## 3. Server Deployment Update
1. Update `.env` on your deployment host (e.g. VPS / Cloud Run / Coolify):
   ```bash
   WEBHOOK_SECRET=<new-generated-hex-64>
   APP_AUTH_TOKEN=<new-generated-bt-sec-token>
   SUPABASE_JWT_SECRET=<supabase-project-jwt-secret>
   REDIS_URL=redis://redis:6379/0
   ENV=production
   ```
2. Restart the AI service container:
   ```bash
   docker compose down && docker compose up -d --build
   ```

## 4. Mobile Client Build Update
When building the Flutter APK/iOS bundle, supply the new values strictly via `--dart-define`:
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-anon-key> \
  --dart-define=FASTAPI_BASE_URL=https://<your-api-domain> \
  --dart-define=APP_AUTH_TOKEN=<new-generated-bt-sec-token> \
  --dart-define=WEBHOOK_SECRET=<new-generated-hex-64>
```

## 5. Git History Cleansing (Optional/Recommended for Public Repos)
If this repository is or will become public, run `git filter-repo` or BFG Repo-Cleaner to scrub the historical commit blobs containing the compromised strings.
````

- [ ] **Step 4: Commit**

```bash
git add docs/runbooks/security-secret-rotation.md ai_service/tests/test_security_posture.py
git commit -m "docs(security): add secret rotation runbook and security posture verification suite"
```

---

## Complete Self-Review Checklist

| Issue # | Area | Check | Planned In | Verification |
|---|---|---|---|---|
| **#1** | 🔴 Critical | `WEBHOOK_SECRET` hardcoded in Git removed | Task 1 & Task 11 | `test_secret_config.py`, runbook |
| **#2** | 🔴 Critical | Supabase publishable key hardcoded default removed | Task 1 | `flutter_app/lib/supabase_config.dart` |
| **#3** | 🔴 Critical | `APP_AUTH_TOKEN` dev fallback removed | Task 1 & Task 11 | `test_secret_config.py` |
| **#4** | 🔴 Critical | IDOR fixed: JWT auth required and binds to `household_id` | Task 2 & Task 10 | `test_auth.py`, `base_api_client_test.dart` |
| **#5** | 🔴 Critical | Error messages sanitized (`str(exc)` removed, correlation ref returned) | Task 3 | `test_error_sanitization.py` |
| **#6** | 🟡 Medium | In-memory rate limiting replaced with distributed Redis + memory fallback | Task 9 | `test_rate_limiter.py` |
| **#7** | 🟡 Medium | Service role key bypass constrained by mandatory per-user authorization checks | Task 2 & Task 11 | `test_auth.py`, `test_security_posture.py` |
| **#8** | 🟡 Medium | `main.py` 1208-line god file decomposed into 7 focused route modules | Task 7 | `ai_service/routes/`, `main.py` ~120 lines |
| **#9** | 🟡 Medium | Lazy imports inside handlers eliminated and hoisted to top-level | Task 8 | `test_imports.py` |
| **#10** | 🟡 Medium | Request body size limits (10MB) added via early middleware | Task 4 & Task 11 | `test_request_limits.py` |
| **#11** | 🟡 Medium | `household_id` UUID validation enforced on query/path params and Pydantic models | Task 5 & Task 11 | `test_uuid_validation.py` |
| **SMS** | 🧹 Cleanup | Dead SMS webhook (`/webhook/sms`), models, and imports completely removed | Task 6 & Task 10 | `test_sms_removal.py`, `base_api_client.dart` |

