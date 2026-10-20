"""Receipt scanning routes: multimodal OCR and itemization."""

from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import JSONResponse

from auth import verify_household_access, get_current_user_id
from household_permissions import PermissionDeniedError
from utils import safe_error_response, validate_uuid
from rate_limiter import check_api_quota
from receipt_scanner import process_receipt_scan
from idempotency import idempotency_store, parse_client_occurred_at, validate_idempotency_key

logger = logging.getLogger(__name__)

router = APIRouter()

REPLAYABLE_STATUSES = {"success", "enriched", "duplicate_candidate"}


@router.post(
    "/agent/scan-receipt",
    tags=["receipt"],
    summary="Process camera or gallery receipt invoice image.",
)
async def scan_receipt(request: Request):
    """
    Analyze receipt image using multimodal Gemini vision.
    Extracts line items, store name, totals, and prevents duplicate charges.

    Authentication is the caller's Supabase JWT. X-Signature is optional, but a present one must
    be valid (auth.verify_signature_if_present, applied to every router in main.py → 401).
    Replays: ``Idempotency-Key`` makes a commit idempotent per user; ``client_occurred_at``
    (ISO-8601) is used as the transaction time.
    """
    user_id = get_current_user_id(request)
    raw_body = await request.body()
    try:
        body = json.loads(raw_body.decode("utf-8"))
    except Exception as exc:
        raise safe_error_response(exc, status_code=422, public_message="Invalid JSON payload.")
    if not isinstance(body, dict):
        raise HTTPException(status_code=422, detail="Request body must be a JSON object.")

    images_base64 = body.get("images_base64")
    if not images_base64 and body.get("image_base64"):
        images_base64 = [body.get("image_base64")]
    if not images_base64:
        images_base64 = []
    if not isinstance(images_base64, list):
        raise HTTPException(status_code=400, detail="images_base64 must be a list.")

    qr_code_raw = body.get("qr_code_raw")
    household_id = body.get("household_id")
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    await verify_household_access(request, household_id)

    if not images_base64 and not qr_code_raw:
        raise HTTPException(status_code=400, detail="Either images_base64 or qr_code_raw is required.")

    preview_only = bool(body.get("preview_only", False))
    idem_key = validate_idempotency_key(request.headers.get("Idempotency-Key"))
    occurred_at = parse_client_occurred_at(
        body.get("client_occurred_at") or request.headers.get("X-Client-Occurred-At")
    )
    use_idempotency = bool(idem_key) and not preview_only

    if use_idempotency:
        cached = await idempotency_store.reserve(user_id, "scan-receipt", idem_key)
        if cached is not None:
            return JSONResponse(content=cached, headers={"Idempotent-Replayed": "true"})

    try:
        # Strict rate limit & quota: 10 invoices per 10 minutes maximum per user
        await check_api_quota(
            user_id=user_id,
            household_id=household_id,
            bucket="scan_receipt",
            max_requests=10,
            window_seconds=600,
        )
        result = await asyncio.to_thread(
            process_receipt_scan,
            household_id=household_id,
            images_base64=images_base64,
            qr_code_raw=qr_code_raw,
            user_id=user_id,
            allow_duplicate=bool(body.get("allow_duplicate", False)),
            enrich_tx_id=body.get("enrich_tx_id"),
            preview_only=preview_only,
            override_merchant=body.get("merchant"),
            override_spent_by=body.get("spent_by"),
            receipt_url=body.get("receipt_url"),
            occurred_at=occurred_at,
        )
    except HTTPException:
        if use_idempotency:
            await idempotency_store.release(user_id, "scan-receipt", idem_key)
        raise
    except PermissionDeniedError as exc:
        # Enriching another member's transaction needs a household admin (DB-18).
        if use_idempotency:
            await idempotency_store.release(user_id, "scan-receipt", idem_key)
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except Exception as exc:
        if use_idempotency:
            await idempotency_store.release(user_id, "scan-receipt", idem_key)
        raise safe_error_response(exc, public_message="Failed to process receipt scan.")

    if use_idempotency:
        if isinstance(result, dict) and result.get("status") in REPLAYABLE_STATUSES:
            await idempotency_store.complete(user_id, "scan-receipt", idem_key, result)
        else:
            await idempotency_store.release(user_id, "scan-receipt", idem_key)
    return result
