"""Receipt scanning routes: multimodal OCR and itemization."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Request, status

from auth import verify_household_access, get_current_user_id
from utils import safe_error_response, validate_uuid, verify_signature
from rate_limiter import check_api_quota, check_receipt_scan_rate_limit
from receipt_scanner import process_receipt_scan

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post(
    "/agent/scan-receipt",
    tags=["receipt"],
    summary="Process camera or gallery receipt invoice image.",
)
async def scan_receipt(request: Request):
    """
    Analyze receipt image using multimodal Gemini vision.
    Extracts line items, store name, totals, and prevents duplicate charges.
    """
    raw_body = await request.body()
    sig_header = request.headers.get("X-Signature")
    if not verify_signature(raw_body, sig_header):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature.")

    try:
        body = json.loads(raw_body.decode("utf-8"))
    except Exception as exc:
        raise safe_error_response(exc, status_code=422, public_message="Invalid JSON payload.")

    images_base64 = body.get("images_base64")
    if not images_base64 and body.get("image_base64"):
        images_base64 = [body.get("image_base64")]
    if not images_base64:
        images_base64 = []

    qr_code_raw = body.get("qr_code_raw")
    household_id = body.get("household_id")
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    await verify_household_access(request, household_id)
    user_id = get_current_user_id(request)

    if not images_base64 and not qr_code_raw:
        raise HTTPException(status_code=400, detail="Either images_base64 or qr_code_raw is required.")

    # Strict rate limit & quota: 10 invoices per 10 minutes maximum per user/household
    await check_api_quota(
        user_id=user_id,
        household_id=household_id,
        bucket="scan_receipt",
        max_requests=10,
        window_seconds=600,
    )

    try:
        result = await asyncio.to_thread(
            process_receipt_scan,
            household_id=household_id,
            images_base64=images_base64,
            qr_code_raw=qr_code_raw,
            user_id=user_id,
            allow_duplicate=bool(body.get("allow_duplicate", False)),
            enrich_tx_id=body.get("enrich_tx_id"),
            preview_only=bool(body.get("preview_only", False)),
            override_merchant=body.get("merchant"),
            override_spent_by=body.get("spent_by"),
            receipt_url=body.get("receipt_url"),
        )
        return result
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to process receipt scan.")
