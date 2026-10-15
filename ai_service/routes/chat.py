"""Chat routes: conversational expense extraction."""

from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, HTTPException, Request, status

from auth import verify_household_access
from utils import safe_error_response, validate_uuid, verify_signature
from chat_parser import process_chat_transaction

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post(
    "/agent/chat-transaction",
    tags=["chat"],
    summary="Process natural language conversational expense message.",
)
async def chat_transaction(request: Request):
    """
    Parse a user chat message into an itemized transaction.
    Extracts merchant, total, line items, and checks for duplicates.
    """
    raw_body = await request.body()
    sig_header = request.headers.get("X-Signature")
    if not verify_signature(raw_body, sig_header):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature.")

    try:
        body = json.loads(raw_body.decode("utf-8"))
    except Exception as exc:
        raise safe_error_response(exc, status_code=422, public_message="Invalid request JSON payload.")

    message = body.get("message")
    household_id = body.get("household_id")
    if not message or not household_id:
        raise HTTPException(status_code=400, detail="message and household_id are required.")

    validate_uuid(household_id)
    await verify_household_access(request, household_id)

    try:
        result = await asyncio.to_thread(
            process_chat_transaction,
            household_id=household_id,
            message=message,
            user_id=body.get("user_id"),
            allow_duplicate=bool(body.get("allow_duplicate", False)),
            enrich_tx_id=body.get("enrich_tx_id"),
            preview_only=bool(body.get("preview_only", False)),
            override_merchant=body.get("merchant"),
            override_spent_by=body.get("spent_by"),
            override_category_code=body.get("category_code"),
            override_sub_category=body.get("sub_category"),
            override_paid_by=body.get("paid_by"),
            override_beneficiary=body.get("beneficiary"),
        )
        return result
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to process chat transaction.")
