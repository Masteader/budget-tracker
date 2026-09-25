"""
FastAPI entry point for the Budget Tracker AI microservice.

Endpoints:
  POST /webhook/sms   — receive SMS from Flutter, run LangGraph agent
  GET  /health        — liveness probe
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import time

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()  # Load .env before any other imports that read env vars

from graph import sms_graph
from models import AgentState, SMSWebhookRequest, SMSWebhookResponse

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ─── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Budget Tracker AI Service",
    description="LangGraph-powered SMS parser and budget manager for Saudi bank notifications.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten in production to your Flutter app's origin
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


# =============================================================================
# HMAC SIGNATURE VERIFICATION
# Shared secret between Flutter and this service.
# Flutter sends: X-Signature: sha256=<hmac_hex>
# =============================================================================

WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")


def _verify_signature(body: bytes, signature_header: str | None) -> bool:
    """Return True if the HMAC-SHA256 signature matches, or if no secret is configured in dev."""
    env = os.environ.get("ENV", "development").lower()
    if not WEBHOOK_SECRET:
        if env == "production":
            logger.error("WEBHOOK_SECRET is not set in production — rejecting request.")
            return False
        logger.warning("WEBHOOK_SECRET not set — skipping signature verification (dev mode).")
        return True
    if not signature_header:
        return False
    try:
        scheme, provided_sig = signature_header.split("=", 1)
        assert scheme == "sha256"
    except (ValueError, AssertionError):
        return False

    expected = hmac.new(WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, provided_sig)



# =============================================================================
# ROUTES
# =============================================================================

@app.get("/health", tags=["ops"])
async def health_check():
    """Liveness probe — returns 200 OK with uptime."""
    return {"status": "ok", "timestamp": time.time()}


@app.post(
    "/webhook/sms",
    response_model=SMSWebhookResponse,
    status_code=status.HTTP_200_OK,
    tags=["sms"],
    summary="Receive a bank SMS from the Flutter Android app and process it.",
)
async def webhook_sms(request: Request) -> SMSWebhookResponse:
    """
    Main webhook endpoint.
    1. Verifies HMAC signature.
    2. Parses request body into SMSWebhookRequest.
    3. Runs the LangGraph sms_graph.
    4. Returns a structured SMSWebhookResponse.
    """
    # ── Signature verification ────────────────────────────────────────────
    raw_body = await request.body()
    sig_header = request.headers.get("X-Signature")
    if not _verify_signature(raw_body, sig_header):
        logger.warning("Webhook signature mismatch — request rejected.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing HMAC signature.",
        )

    # ── Parse body ────────────────────────────────────────────────────────
    try:
        payload = SMSWebhookRequest.model_validate_json(raw_body)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))

    logger.info(
        "Webhook received: sender=%s household=%s sms_len=%d",
        payload.sender, payload.household_id, len(payload.raw_sms),
    )

    # ── Build initial LangGraph state ─────────────────────────────────────
    initial_state = AgentState(
        raw_sms=payload.raw_sms,
        sender=payload.sender,
        received_at=payload.received_at,
        household_id=payload.household_id,
        device_id=payload.device_id,
    )

    # ── Run graph ─────────────────────────────────────────────────────────
    try:
        raw_result = await sms_graph.ainvoke(initial_state)
        final_state: AgentState = (
            AgentState.model_validate(raw_result)
            if isinstance(raw_result, dict)
            else raw_result
        )
    except Exception as exc:
        logger.exception("LangGraph execution failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Agent error: {exc}",
        )

    # ── Map state → response ──────────────────────────────────────────────
    if final_state.rejection_reason:
        return SMSWebhookResponse(
            status="rejected",
            message=final_state.rejection_reason,
        )
    if final_state.error:
        return SMSWebhookResponse(
            status="error",
            message=final_state.error,
        )

    return SMSWebhookResponse(
        status="success",
        transaction_id=final_state.transaction_id,
        category_code=final_state.category_code,
        amount=final_state.amount,
        merchant=final_state.merchant,
        is_reallocated=final_state.is_reallocated,
        reallocated_from_category=final_state.reallocated_from_category,
        message="Transaction recorded successfully.",
    )


@app.post(
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
    if not _verify_signature(raw_body, sig_header):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature.")

    try:
        body = json.loads(raw_body.decode("utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))

    message = body.get("message")
    household_id = body.get("household_id")
    if not message or not household_id:
        raise HTTPException(status_code=400, detail="message and household_id are required.")

    from chat_parser import process_chat_transaction
    result = process_chat_transaction(
        household_id=household_id,
        message=message,
        user_id=body.get("user_id"),
        allow_duplicate=bool(body.get("allow_duplicate", False)),
        enrich_tx_id=body.get("enrich_tx_id"),
    )
    return result


@app.post(
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
    if not _verify_signature(raw_body, sig_header):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature.")

    try:
        body = json.loads(raw_body.decode("utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))

    image_base64 = body.get("image_base64")
    household_id = body.get("household_id")
    if not image_base64 or not household_id:
        raise HTTPException(status_code=400, detail="image_base64 and household_id are required.")

    from receipt_scanner import process_receipt_scan
    result = process_receipt_scan(
        household_id=household_id,
        image_base64=image_base64,
        user_id=body.get("user_id"),
        allow_duplicate=bool(body.get("allow_duplicate", False)),
        enrich_tx_id=body.get("enrich_tx_id"),
    )
    return result


# =============================================================================
# ENTRY POINT
# =============================================================================

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8000)),
        reload=os.environ.get("RELOAD", "false").lower() == "true",
        log_level="info",
    )
