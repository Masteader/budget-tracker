"""Support chat routes: AI support assistant and escalation."""

from __future__ import annotations

import logging

from fastapi import APIRouter

from utils import safe_error_response
from models import SupportChatRequest, SupportChatResponse
from support_agent import handle_support_query, SUPPORT_EMAIL

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post(
    "/support/chat",
    response_model=SupportChatResponse,
    tags=["support"],
    summary="AI Support Chatbot and Developer Escalation",
)
async def support_chat(payload: SupportChatRequest) -> SupportChatResponse:
    try:
        reply, escalate, summary = await handle_support_query(
            message=payload.message,
            household_id=payload.household_id,
            user_id=payload.user_id,
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
