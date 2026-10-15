"""Reports routes: PDF statement generation."""

from __future__ import annotations

import asyncio
import logging
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response

from auth import verify_household_access
from utils import safe_error_response, validate_uuid
from pdf_statement_generator import generate_monthly_pdf_statement

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get(
    "/reports/statement-pdf",
    tags=["reports"],
    summary="Download branded monthly financial statement PDF.",
)
async def export_statement_pdf(
    household_id: str,
    cycle_key: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    """
    Generates a branded monthly PDF statement covering salary cycle spending,
    partner splits, category utilization, and 15% VAT breakdown.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)

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
        raise safe_error_response(exc, public_message="Failed to generate PDF statement.")
