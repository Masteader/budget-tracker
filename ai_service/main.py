"""
FastAPI entry point for the Budget Tracker AI microservice.

Endpoints:
  POST /webhook/sms   — receive SMS from Flutter, run LangGraph agent
  GET  /health        — liveness probe
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import logging
import os
import re
import time
from typing import Optional

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, status, Response
from fastapi.responses import HTMLResponse

from fastapi.middleware.cors import CORSMiddleware

load_dotenv()  # Load .env before any other imports that read env vars

from graph import sms_graph
from models import (
    AgentState,
    SMSWebhookRequest,
    SMSWebhookResponse,
    CategoryCreateRequest,
    SubAllocationsRequest,
    SubCategoryCreateRequest,
    SubCategoryRenameRequest,
    PaydayUpdateRequest,
    ShoppingBasketOptimizeRequest,
    RecurringBillToggleRequest,
    SupportChatRequest,
    SupportChatResponse,
)
from support_agent import handle_support_query, SUPPORT_EMAIL


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

cors_origins_env = os.environ.get("CORS_ORIGINS", "*").strip()
allow_origins = [o.strip() for o in cors_origins_env.split(",") if o.strip()] or ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

APP_AUTH_TOKEN = os.environ.get("APP_AUTH_TOKEN", "").strip()
if not APP_AUTH_TOKEN and os.environ.get("ENV", "development").lower() != "production":
    APP_AUTH_TOKEN = "bt_sec_99a81f3d4c72e01b88e2"  # Local/testing fallback only
elif not APP_AUTH_TOKEN:
    logger.warning("APP_AUTH_TOKEN is not configured; unauthenticated proxied requests will be rejected.")


@app.middleware("http")
async def firewall_token_middleware(request: Request, call_next):
    # Allow local inspection, health check and docs
    path = request.url.path
    if path in ["/", "/auth/confirm", "/auth/callback", "/health", "/docs", "/openapi.json", "/redoc"] or path.startswith("/auth/") or request.method == "OPTIONS":
        return await call_next(request)

    # Check if request arrived via reverse proxy or public tunnel
    forwarded_for = request.headers.get("X-Forwarded-For")
    client_host = request.client.host if request.client else ""
    is_tunnel_or_proxy = bool(forwarded_for) or (client_host not in ["127.0.0.1", "localhost", "::1", "testclient"])

    # Constant-time comparison to prevent side-channel timing attacks (OWASP A02)
    provided_token = request.headers.get("X-App-Token", "")
    token_valid = bool(APP_AUTH_TOKEN and hmac.compare_digest(provided_token, APP_AUTH_TOKEN))
    if is_tunnel_or_proxy and not token_valid:
        logger.warning("Firewall blocked unauthorized public probe from IP=%s (forwarded=%s) to path=%s", client_host, forwarded_for, path)
        from starlette.responses import JSONResponse
        return JSONResponse(
            status_code=403,
            content={"detail": "Forbidden: Untrusted endpoint access."}
        )

    return await call_next(request)


# =============================================================================
# HMAC SIGNATURE VERIFICATION
# Shared secret between Flutter and this service.
# Flutter sends: X-Signature: sha256=<hmac_hex>
# =============================================================================

WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "").strip()
if not WEBHOOK_SECRET and os.environ.get("ENV", "development").lower() != "production":
    WEBHOOK_SECRET = "dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400"  # Dev fallback only


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
        if scheme != "sha256":
            return False
    except (ValueError, AttributeError):
        return False

    expected = hmac.new(WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, provided_sig)



# =============================================================================
# ROUTES
# =============================================================================

@app.get("/", response_class=HTMLResponse, tags=["ops"])
@app.get("/auth/confirm", response_class=HTMLResponse, tags=["ops"])
@app.get("/auth/callback", response_class=HTMLResponse, tags=["ops"])
async def auth_confirm_landing():
    """Welcome and email confirmation landing page."""
    html_content = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker - Email Confirmed</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Outfit', -apple-system, BlinkMacSystemFont, sans-serif;
      background: #0D1117;
      color: #C9D1D9;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: #161B22;
      border: 1px solid #30363D;
      border-radius: 20px;
      padding: 44px 32px;
      max-width: 440px;
      width: 100%;
      text-align: center;
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.4);
    }
    .icon-circle {
      width: 72px;
      height: 72px;
      border-radius: 50%;
      background: rgba(0, 200, 150, 0.15);
      border: 2px solid #00C896;
      color: #00C896;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 36px;
      margin-bottom: 24px;
    }
    h1 {
      color: #FFFFFF;
      font-size: 24px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .subtitle-ar {
      color: #00C896;
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 16px;
      direction: rtl;
    }
    p {
      color: #8B949E;
      font-size: 15px;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .badge {
      display: inline-block;
      background: rgba(88, 166, 255, 0.12);
      border: 1px solid rgba(88, 166, 255, 0.3);
      color: #58A6FF;
      font-size: 13px;
      padding: 6px 14px;
      border-radius: 12px;
      margin-bottom: 20px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon-circle">✓</div>
    <h1>Account Verified</h1>
    <div class="subtitle-ar">تم تأكيد البريد الإلكتروني بنجاح</div>
    <div class="badge">Budget Tracker</div>
    <p>Your email has been confirmed. You can now return to the Budget Tracker app on your mobile device to sign in.</p>
  </div>
</body>
</html>"""
    return HTMLResponse(content=html_content)


@app.get("/health", tags=["ops"])
async def health_check():
    """Liveness probe — returns 200 OK with uptime."""
    return {"status": "ok", "version": "1.0.2", "timestamp": time.time()}



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
        )
        return result
    except Exception as exc:
        logger.error("Failed to process chat transaction: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))



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

    images_base64 = body.get("images_base64")
    if not images_base64 and body.get("image_base64"):
        images_base64 = [body.get("image_base64")]
    if not images_base64:
        images_base64 = []

    qr_code_raw = body.get("qr_code_raw")
    household_id = body.get("household_id")
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")

    if not images_base64 and not qr_code_raw:
        raise HTTPException(status_code=400, detail="Either images_base64 or qr_code_raw is required.")

    from receipt_scanner import process_receipt_scan
    result = await asyncio.to_thread(
        process_receipt_scan,
        household_id=household_id,
        images_base64=images_base64,
        qr_code_raw=qr_code_raw,
        user_id=body.get("user_id"),
        allow_duplicate=bool(body.get("allow_duplicate", False)),
        enrich_tx_id=body.get("enrich_tx_id"),
        preview_only=bool(body.get("preview_only", False)),
        override_merchant=body.get("merchant"),
        override_spent_by=body.get("spent_by"),
        receipt_url=body.get("receipt_url"),
    )
    return result


@app.get(
    "/budgets/salary-cycle-forecast",
    tags=["budgets"],
    summary="Get active Saudi salary cycle stats, burn rate velocity, and projected run-out date.",
)
async def salary_cycle_forecast(household_id: str, payday_day: Optional[int] = None):
    """Returns salary cycle progress, days to payday, burn rate, and pace indicator."""
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from salary_cycle import get_salary_cycle_forecast
    try:
        return await asyncio.to_thread(get_salary_cycle_forecast, household_id, None, payday_day)
    except Exception as exc:
        logger.error("Failed to generate salary cycle forecast: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get(
    "/budgets/cycles",
    tags=["budgets"],
    summary="List active and available salary cycles for a household.",
)
async def list_salary_cycles(household_id: str, payday_day: Optional[int] = None):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from salary_cycle import get_available_cycles_for_household
    try:
        return await asyncio.to_thread(get_available_cycles_for_household, household_id, payday_day)
    except Exception as exc:
        logger.error("Failed to list cycles: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get(
    "/households/{household_id}/payday",
    tags=["households"],
    summary="Get configured monthly payday day for a household.",
)
async def get_household_payday_endpoint(household_id: str):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from supabase_client import get_household_payday
    day = await asyncio.to_thread(get_household_payday, household_id)
    return {"household_id": household_id, "payday_day": day}


@app.put(
    "/households/{household_id}/payday",
    tags=["households"],
    summary="Update configured monthly payday day for a household.",
)
async def update_household_payday_endpoint(household_id: str, payload: PaydayUpdateRequest):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from supabase_client import set_household_payday
    saved_day = await asyncio.to_thread(set_household_payday, household_id, payload.payday_day)
    return {"household_id": household_id, "payday_day": saved_day, "status": "success"}


@app.get(
    "/budgets/recurring-bills",
    tags=["budgets"],
    summary="Get detected recurring household bills, cycle payment status, and reserved allowance.",
)
async def get_recurring_bills(household_id: str, as_of_date: Optional[str] = None):
    """
    Analyzes historical transactions for recurring cadence (telecom, utilities, subscriptions)
    and reports upcoming vs paid bills for the active Saudi salary cycle.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from recurring_detector import fetch_household_recurring_bills
    from datetime import date

    target_date = None
    if as_of_date:
        try:
            target_date = date.fromisoformat(as_of_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="as_of_date must be in YYYY-MM-DD format.")

    try:
        return await asyncio.to_thread(fetch_household_recurring_bills, household_id, target_date)
    except Exception as exc:
        logger.error("Failed to fetch recurring bills: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/budgets/recurring-bills/toggle",
    tags=["budgets"],
    summary="Toggle or customize whether a sub-budget appears in recurring bills.",
)
async def toggle_recurring_bill(req: RecurringBillToggleRequest):
    from recurring_detector import toggle_household_recurring_bill
    try:
        return await asyncio.to_thread(
            toggle_household_recurring_bill,
            household_id=req.household_id,
            category_code=req.category_code,
            sub_code=req.sub_code,
            is_recurring=req.is_recurring,
            due_day=req.due_day,
            custom_name=req.custom_name,
        )
    except Exception as exc:
        logger.error("Failed to toggle recurring bill: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get(
    "/budgets/recurring-bills/candidates",
    tags=["budgets"],
    summary="List all sub-budget items eligible to be recurring bills.",
)
async def list_recurring_bill_candidates(household_id: str):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from recurring_detector import get_recurring_bill_candidates
    try:
        return await asyncio.to_thread(get_recurring_bill_candidates, household_id)
    except Exception as exc:
        logger.error("Failed to list recurring bill candidates: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get(
    "/budgets/installments",
    tags=["installments"],
    summary="List active and completed BNPL installment plans for a household.",
)
async def list_installments(household_id: str):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from installment_service import InstallmentService
    try:
        plans = await asyncio.to_thread(InstallmentService.list_plans, household_id)
        return {"plans": [p.model_dump() for p in plans], "count": len(plans)}
    except Exception as exc:
        logger.error("Failed to list installment plans: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/budgets/installments",
    tags=["installments"],
    summary="Create a new BNPL installment plan (e.g. Tamara/Tabby) and amortize purchase.",
)
async def create_installment_plan(request: Request):
    try:
        body = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    from installment_service import InstallmentService, InstallmentPlanCreate
    try:
        req = InstallmentPlanCreate(**body)
        plan = await asyncio.to_thread(InstallmentService.create_plan, req)
        return plan.model_dump()
    except Exception as exc:
        logger.error("Failed to create installment plan: %s", exc)
        raise HTTPException(status_code=400, detail=str(exc))


@app.post(
    "/budgets/installments/{plan_id}/pay",
    tags=["installments"],
    summary="Record an installment payment towards a plan.",
)
async def pay_installment_endpoint(plan_id: str):
    from installment_service import InstallmentService
    try:
        plan = await asyncio.to_thread(InstallmentService.pay_installment, plan_id)
        if not plan:
            raise HTTPException(status_code=404, detail="Installment plan not found.")
        return plan.model_dump()
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Failed to pay installment: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/budgets/recalculate",
    tags=["budgets"],
    summary="Recalculate spent_amount for all categories in a household from transactions.",
)
async def recalculate_budgets_endpoint(household_id: str):
    from installment_service import InstallmentService
    try:
        await asyncio.to_thread(InstallmentService.recalculate_budgets, household_id)
        return {"status": "ok", "household_id": household_id}
    except Exception as exc:
        logger.error("Failed to recalculate budgets: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))



@app.get(
    "/budgets/breakdown",
    tags=["budgets"],
    summary="Get budget categories and sub-budget spending breakdown for a salary cycle.",
)
async def get_budget_breakdown(household_id: str, cycle_key: Optional[str] = None):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from salary_cycle import get_cycle_breakdown
    try:
        return await asyncio.to_thread(get_cycle_breakdown, household_id, cycle_key)
    except Exception as exc:
        logger.error("Failed to get budget breakdown: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/budgets/categories",
    tags=["budgets"],
    summary="Add a new category and initial budget allocation.",
)
async def add_budget_category(req: CategoryCreateRequest):
    from salary_cycle import add_category_and_budget
    try:
        return await asyncio.to_thread(add_category_and_budget, req)
    except Exception as exc:
        logger.error("Failed to add category: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/budgets/sub-allocations",
    tags=["budgets"],
    summary="Set sub-category budget allocations and automatically recompute parent budget amount.",
)
async def set_sub_allocations(req: SubAllocationsRequest):
    from salary_cycle import save_sub_allocations
    try:
        return await asyncio.to_thread(
            save_sub_allocations,
            household_id=req.household_id,
            category_code=req.category_code,
            sub_allocations=req.sub_allocations,
            cycle_key=req.cycle_key,
        )
    except Exception as exc:
        logger.error("Failed to save sub-allocations: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Add a new sub-category to a parent budget category with an allocation.",
)
async def add_sub_category(req: SubCategoryCreateRequest):
    from salary_cycle import add_sub_category_for_household
    try:
        return await asyncio.to_thread(
            add_sub_category_for_household,
            household_id=req.household_id,
            parent_code=req.parent_code,
            name_en=req.name_en,
            allocated_amount=req.allocated_amount,
            sub_code=req.sub_code,
            cycle_key=req.cycle_key,
        )
    except Exception as exc:
        logger.error("Failed to add sub-category: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Get all sub-categories for a parent category code.",
)
async def get_sub_categories_route(parent_code: str):
    from salary_cycle import get_sub_categories_for_parent
    try:
        sub_cats = await asyncio.to_thread(get_sub_categories_for_parent, parent_code)
        return {
            "status": "success",
            "sub_categories": sub_cats,
        }
    except Exception as exc:
        logger.error("Failed to get sub-categories: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.patch(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Rename an existing sub-category.",
)
async def rename_sub_category_endpoint(req: SubCategoryRenameRequest):
    from salary_cycle import rename_sub_category
    try:
        return await asyncio.to_thread(
            rename_sub_category,
            parent_code=req.parent_code,
            sub_code=req.sub_code,
            name_en=req.name_en,
            name_ar=req.name_ar,
        )
    except Exception as exc:
        logger.error("Failed to rename sub-category: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.delete(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Remove a sub-category from budget and purge if unused.",
)
async def remove_sub_category_endpoint(
    household_id: str,
    parent_code: str,
    sub_code: str,
    cycle_key: Optional[str] = None,
):
    if not household_id or not parent_code or not sub_code:
        raise HTTPException(status_code=400, detail="household_id, parent_code, and sub_code are required.")
    from salary_cycle import remove_sub_category_for_household
    try:
        return await asyncio.to_thread(
            remove_sub_category_for_household,
            household_id=household_id,
            parent_code=parent_code,
            sub_code=sub_code,
            cycle_key=cycle_key,
        )
    except Exception as exc:
        logger.error("Failed to remove sub-category: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.delete(
    "/budgets/categories/{category_code}",
    tags=["budgets"],
    summary="Deactivate or remove a category allocation for a household.",
)
async def delete_budget_category(category_code: str, household_id: str):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from salary_cycle import archive_category_for_household
    try:
        return await asyncio.to_thread(archive_category_for_household, household_id, category_code)
    except Exception as exc:
        logger.error("Failed to delete category: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))



@app.post(
    "/budgets/simulate-affordability",
    tags=["budgets"],
    summary="Pre-purchase affordability simulator ('Can I Afford This?').",
)
async def simulate_purchase_affordability(request: Request):
    """
    Evaluates purchase against active salary cycle cushion, flexible budget pools, and days to 27th.
    """
    try:
        body = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    household_id = body.get("household_id")
    target_amount = float(body.get("target_amount") or 0.0)
    item_name = body.get("item_name") or "Item"
    category_code = body.get("category_code")

    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")

    from salary_cycle import simulate_affordability
    return await asyncio.to_thread(
        simulate_affordability,
        household_id=household_id,
        target_amount=target_amount,
        item_name=item_name,
        category_code=category_code,
    )


@app.get(
    "/households/{household_id}/settlement",
    tags=["settlement"],
    summary="Calculate shared partner expense balance and settle-up payment note.",
)
async def household_settlement(household_id: str, split_ratio: float = 0.50):
    """
    Aggregates transactions in the active salary cycle by spent_by ('me', 'partner', 'both').
    Returns net balance, who owes whom, and copyable STC Pay / Urpay / IBAN transfer note.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from settlement_engine import calculate_partner_settlement
    try:
        return await asyncio.to_thread(calculate_partner_settlement, household_id, split_ratio=split_ratio)
    except Exception as exc:
        logger.error("Failed to compute partner settlement: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.get(
    "/analytics/price-history",
    tags=["analytics"],
    summary="Query grocery price history, inflation percentage, and store comparisons.",
)
async def grocery_price_history(household_id: str, item_filter: str | None = None):
    """
    Groups line items across receipts, voice, and chat logs by normalized product name and store.
    Computes price trends, cheapest store (Panda vs Danube vs Tamimi), and inflation rate.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from price_tracker import get_grocery_price_history
    try:
        items = await asyncio.to_thread(get_grocery_price_history, household_id, item_filter=item_filter)
        return {"items": items, "count": len(items)}
    except Exception as exc:
        logger.error("Failed to fetch grocery price history: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/analytics/shopping-basket-optimize",
    tags=["analytics"],
    summary="Optimize shopping list across major Saudi grocery retailers.",
)
async def shopping_basket_optimize(req: ShoppingBasketOptimizeRequest):
    """
    Computes total basket pricing at Panda, Danube, Tamimi, Othaim, and Lulu,
    identifying the cheapest single store and optimal multi-store savings split.
    """
    if not req.household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from price_tracker import optimize_shopping_basket
    try:
        return await asyncio.to_thread(optimize_shopping_basket, req.household_id, req.items)
    except Exception as exc:
        logger.error("Failed to optimize shopping basket: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))



@app.get(
    "/reports/statement-pdf",
    tags=["reports"],
    summary="Download branded monthly financial statement PDF.",
)
async def export_statement_pdf(household_id: str, cycle_key: str | None = None):
    """
    Generates a branded monthly PDF statement covering salary cycle spending,
    partner splits, category utilization, and 15% VAT breakdown.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    from pdf_statement_generator import generate_monthly_pdf_statement
    try:
        pdf_bytes = await asyncio.to_thread(generate_monthly_pdf_statement, household_id, cycle_key=cycle_key)
        safe_cycle = re.sub(r"[^a-zA-Z0-9_\-]", "", cycle_key or "current")
        safe_hid = re.sub(r"[^a-zA-Z0-9_\-]", "", household_id)[:8] or "unknown"
        filename = f"statement_{safe_cycle}_{safe_hid}.pdf"
        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )
    except Exception as exc:
        logger.error("Failed to generate PDF statement: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post(
    "/support/chat",
    response_model=SupportChatResponse,
    tags=["support"],
    summary="AI Support Chatbot and Developer Escalation",
)
async def support_chat(payload: SupportChatRequest) -> SupportChatResponse:
    reply, escalate, summary = await handle_support_query(
        message=payload.message,
        household_id=payload.household_id,
        user_id=payload.user_id,
        history=payload.history,
    )
    return SupportChatResponse(
        reply=reply,
        escalate_to_developer=escalate,
        summary=summary,
        support_email=SUPPORT_EMAIL,
    )


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
