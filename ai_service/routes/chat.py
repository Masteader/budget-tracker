"""Chat routes: conversational expense extraction."""

from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import JSONResponse

from auth import verify_household_access, get_current_user_id
from household_permissions import PermissionDeniedError
from nafaqah_service import NafaqahError
from routes.nafaqah import nafaqah_http_error
from supabase_client import InvalidAttributionError, UnknownCategoryError
from utils import bounded_text, safe_error_response, validate_uuid
from rate_limiter import check_api_quota
from chat_parser import process_chat_transaction
from idempotency import idempotency_store, parse_client_occurred_at, validate_idempotency_key

logger = logging.getLogger(__name__)

router = APIRouter()

# Results that represent a finished request and are safe to return again on replay.
REPLAYABLE_STATUSES = {"success", "enriched", "duplicate_candidate", "simulation", "non_transactional"}


@router.post(
    "/agent/chat-transaction",
    tags=["chat"],
    summary="Process natural language conversational expense message.",
)
async def chat_transaction(request: Request):
    """
    Parse a user chat message into an itemized transaction.
    Extracts merchant, total, line items, and checks for duplicates.

    Authentication is the caller's Supabase JWT. X-Signature is optional defense in depth: its
    secret ships inside the app and authenticates nobody, so a stale signature next to a valid JWT
    is only logged (auth.verify_signature_if_present, applied to every router in main.py).

    Replays: an ``Idempotency-Key`` header makes a commit idempotent per user, and
    ``client_occurred_at`` (ISO-8601) is used as the transaction time.
    """
    user_id = get_current_user_id(request)
    raw_body = await request.body()
    try:
        body = json.loads(raw_body.decode("utf-8"))
    except Exception as exc:
        raise safe_error_response(exc, status_code=422, public_message="Invalid request JSON payload.")
    if not isinstance(body, dict):
        raise HTTPException(status_code=422, detail="Request body must be a JSON object.")

    message = body.get("message")
    household_id = body.get("household_id")
    if not message or not household_id:
        raise HTTPException(status_code=400, detail="message and household_id are required.")
    if not isinstance(message, str) or len(message) > 4000:
        raise HTTPException(status_code=400, detail="message must be text of at most 4000 characters.")

    validate_uuid(household_id)
    await verify_household_access(request, household_id)
    # Free-text overrides are bounded (FABLE-API-06): 422 instead of storing megabytes per row.
    overrides = {
        field: bounded_text(body, field, limit)
        for field, limit in (
            ("merchant", 120), ("spent_by", 20), ("sub_category", 60),
            ("paid_by", 60), ("beneficiary", 60), ("nafaqah_spouse_id", 64), ("enrich_tx_id", 64),
        )
    }

    nafaqah_class = body.get("nafaqah_class")
    if nafaqah_class is not None and nafaqah_class not in ("wife_reimbursable", "wife_personal", "none"):
        # Family households never split between spouses: there is no "50/50" or ratio class.
        raise HTTPException(
            status_code=422,
            detail="nafaqah_class must be 'wife_reimbursable', 'wife_personal' or 'none'.",
        )

    preview_only = bool(body.get("preview_only", False))
    idem_key = validate_idempotency_key(request.headers.get("Idempotency-Key"))
    occurred_at = parse_client_occurred_at(
        body.get("client_occurred_at") or request.headers.get("X-Client-Occurred-At")
    )
    use_idempotency = bool(idem_key) and not preview_only

    if use_idempotency:
        cached = await idempotency_store.reserve(user_id, "chat-transaction", idem_key)
        if cached is not None:
            return JSONResponse(content=cached, headers={"Idempotent-Replayed": "true"})

    try:
        # Persistent DB quota & sliding window rate limit (strictly verified user_id)
        await check_api_quota(
            user_id=user_id,
            household_id=household_id,
            bucket="chat_transaction",
            max_requests=30,
            window_seconds=600,
        )
        result = await asyncio.to_thread(
            process_chat_transaction,
            household_id=household_id,
            message=message,
            user_id=user_id,
            allow_duplicate=bool(body.get("allow_duplicate", False)),
            enrich_tx_id=overrides["enrich_tx_id"],
            preview_only=preview_only,
            override_merchant=overrides["merchant"],
            override_spent_by=overrides["spent_by"],
            override_category_code=body.get("category_code"),  # unknown/oversized: 422 in the parser
            override_sub_category=overrides["sub_category"],
            override_paid_by=overrides["paid_by"],
            override_beneficiary=overrides["beneficiary"],
            occurred_at=occurred_at,
            override_nafaqah_class=nafaqah_class,
            override_nafaqah_spouse_id=overrides["nafaqah_spouse_id"],
        )
    except NafaqahError as exc:
        # A class contradicting paid_by/beneficiary, or a wife that is not allowed (422).
        if use_idempotency:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
        raise nafaqah_http_error(exc)
    except HTTPException:
        if use_idempotency:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
        raise
    except PermissionDeniedError as exc:
        # Enriching another member's transaction needs a household admin (DB-18).
        if use_idempotency:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except UnknownCategoryError:
        # The category code is not in the global or household taxonomy (E2E-03): the client's
        # error, answered with a fixed message (no database text).
        if use_idempotency:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
        raise HTTPException(status_code=422, detail=UnknownCategoryError.PUBLIC_MESSAGE)
    except InvalidAttributionError as exc:
        # paid_by / beneficiary name nobody in this household (a fixed, database-free message).
        if use_idempotency:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
        raise HTTPException(status_code=422, detail=str(exc))
    except Exception as exc:
        if use_idempotency:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
        raise safe_error_response(exc, public_message="Failed to process chat transaction.")

    if use_idempotency:
        if isinstance(result, dict) and result.get("status") in REPLAYABLE_STATUSES:
            await idempotency_store.complete(user_id, "chat-transaction", idem_key, result)
        else:
            await idempotency_store.release(user_id, "chat-transaction", idem_key)
    return result
