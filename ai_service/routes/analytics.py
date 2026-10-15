"""Analytics routes: price history and shopping basket optimization."""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from auth import verify_household_access
from utils import safe_error_response, validate_uuid
from models import ShoppingBasketOptimizeRequest
from price_tracker import get_grocery_price_history, optimize_shopping_basket

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get(
    "/analytics/price-history",
    tags=["analytics"],
    summary="Query grocery price history, inflation percentage, and store comparisons.",
)
async def grocery_price_history(
    household_id: str,
    item_filter: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    """
    Groups line items across receipts, voice, and chat logs by normalized product name and store.
    Computes price trends, cheapest store (Panda vs Danube vs Tamimi), and inflation rate.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        items = await asyncio.to_thread(get_grocery_price_history, household_id, item_filter=item_filter)
        return {"items": items, "count": len(items)}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to fetch grocery price history.")


@router.post(
    "/analytics/shopping-basket-optimize",
    tags=["analytics"],
    summary="Optimize shopping list across major Saudi grocery retailers.",
)
async def shopping_basket_optimize(
    request: Request,
    req: ShoppingBasketOptimizeRequest,
):
    """
    Computes total basket pricing at Panda, Danube, Tamimi, Othaim, and Lulu,
    identifying the cheapest single store and optimal multi-store savings split.
    """
    if not req.household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(req.household_id)
    await verify_household_access(request, req.household_id)
    try:
        return await asyncio.to_thread(optimize_shopping_basket, req.household_id, req.items)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to optimize shopping basket.")
