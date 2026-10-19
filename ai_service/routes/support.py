"""Support chat routes: AI support assistant and escalation."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Request

from utils import safe_error_response, validate_uuid
from auth import get_current_user_id, verify_household_access
from models import SupportChatRequest, SupportChatResponse
from rate_limiter import check_api_quota
from support_agent import handle_support_query, SUPPORT_EMAIL

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post(
    "/agent/support-chat",
    response_model=SupportChatResponse,
    tags=["support"],
    summary="AI Support Chatbot and Developer Escalation",
)
@router.post(
    "/support/chat",
    response_model=SupportChatResponse,
    tags=["support"],
    summary="AI Support Chatbot and Developer Escalation",
)
async def support_chat(payload: SupportChatRequest, request: Request) -> SupportChatResponse:
    user_id = get_current_user_id(request)
    # household_id is optional context; when supplied it must be the caller's household.
    if payload.household_id:
        validate_uuid(payload.household_id)
        await verify_household_access(request, payload.household_id)

    # Cost control & rate limiting: 20 support messages per 10 minutes
    await check_api_quota(
        user_id=user_id,
        household_id=payload.household_id,
        bucket="support_chat",
        max_requests=20,
        window_seconds=600,
    )

    try:
        reply, escalate, summary = await handle_support_query(
            message=payload.message,
            household_id=payload.household_id,
            user_id=user_id,
            history=payload.history,
            language=payload.language or "ar",
        )
        return SupportChatResponse(
            reply=reply,
            escalate_to_developer=escalate,
            summary=summary,
            support_email=SUPPORT_EMAIL,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to process support request.")
