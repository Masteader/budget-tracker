"""Budget management routes: cycles, breakdown, categories, sub-allocations, installments."""

from __future__ import annotations

import asyncio
from datetime import date
import logging
import math
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status

from auth import verify_household_access, verify_household_admin_access, get_current_user_id
from utils import safe_error_response, validate_uuid
from models import (
    MAX_SAR_AMOUNT,
    CategoryCreateRequest,
    SubAllocationsRequest,
    SubCategoryCreateRequest,
    SubCategoryRenameRequest,
    RecurringBillToggleRequest,
)
from salary_cycle import (
    get_salary_cycle_forecast,
    get_available_cycles_for_household,
    get_cycle_breakdown,
    add_category_and_budget,
    save_sub_allocations,
    add_sub_category_for_household,
    get_sub_categories_for_parent,
    rename_sub_category,
    remove_sub_category_for_household,
    archive_category_for_household,
    simulate_affordability,
    get_category_owner_households,
)
from recurring_detector import (
    fetch_household_recurring_bills,
    toggle_household_recurring_bill,
    get_recurring_bill_candidates,
)
from installment_service import InstallmentService, InstallmentPlanCreate

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get(
    "/budgets/salary-cycle-forecast",
    tags=["budgets"],
    summary="Get active Saudi salary cycle stats, burn rate velocity, and projected run-out date.",
)
async def salary_cycle_forecast(
    household_id: str,
    payday_day: Optional[int] = None,
    _auth: str = Depends(verify_household_access),
):
    """Returns salary cycle progress, days to payday, burn rate, and pace indicator."""
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(get_salary_cycle_forecast, household_id, None, payday_day)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to generate salary cycle forecast.")


@router.get(
    "/budgets/cycles",
    tags=["budgets"],
    summary="List active and available salary cycles for a household.",
)
async def list_salary_cycles(
    household_id: str,
    payday_day: Optional[int] = None,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(get_available_cycles_for_household, household_id, payday_day)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to list salary cycles.")


@router.get(
    "/budgets/recurring-bills",
    tags=["budgets"],
    summary="Get detected recurring household bills, cycle payment status, and reserved allowance.",
)
async def get_recurring_bills(
    household_id: str,
    as_of_date: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    """
    Analyzes historical transactions for recurring cadence (telecom, utilities, subscriptions)
    and reports upcoming vs paid bills for the active Saudi salary cycle.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)

    target_date = None
    if as_of_date:
        try:
            target_date = date.fromisoformat(as_of_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="as_of_date must be in YYYY-MM-DD format.")

    try:
        return await asyncio.to_thread(fetch_household_recurring_bills, household_id, target_date)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to fetch recurring bills.")


@router.post(
    "/budgets/recurring-bills/toggle",
    tags=["budgets"],
    summary="Toggle or customize whether a sub-budget appears in recurring bills.",
)
async def toggle_recurring_bill(
    request: Request,
    req: RecurringBillToggleRequest,
):
    await verify_household_access(request, req.household_id)
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
        raise safe_error_response(exc, public_message="Failed to toggle recurring bill.")


@router.get(
    "/budgets/recurring-bills/candidates",
    tags=["budgets"],
    summary="List all sub-budget items eligible to be recurring bills.",
)
async def list_recurring_bill_candidates(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(get_recurring_bill_candidates, household_id)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to list recurring bill candidates.")


@router.get(
    "/budgets/installments",
    tags=["installments"],
    summary="List active and completed BNPL installment plans for a household.",
)
async def list_installments(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        plans = await asyncio.to_thread(InstallmentService.list_plans, household_id)
        return {"plans": [p.model_dump() for p in plans], "count": len(plans)}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to list installment plans.")


@router.post(
    "/budgets/installments",
    tags=["installments"],
    summary="Create a new BNPL installment plan (e.g. Tamara/Tabby) and amortize purchase.",
)
async def create_installment_plan(request: Request):
    try:
        body = await request.json()
    except Exception as exc:
        raise safe_error_response(exc, status_code=422, public_message="Invalid request body.")

    get_current_user_id(request)
    household_id = body.get("household_id") if isinstance(body, dict) else None
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    await verify_household_access(request, household_id)

    try:
        req = InstallmentPlanCreate(**body)
        plan = await asyncio.to_thread(InstallmentService.create_plan, req)
        return plan.model_dump()
    except PermissionError:
        raise HTTPException(status_code=404, detail="Original transaction not found in this household.")
    except Exception as exc:
        raise safe_error_response(exc, status_code=400, public_message="Failed to create installment plan.")


@router.post(
    "/budgets/installments/{plan_id}/pay",
    tags=["installments"],
    summary="Record an installment payment towards a plan.",
)
async def pay_installment_endpoint(plan_id: str, request: Request):
    get_current_user_id(request)
    household_id = await asyncio.to_thread(InstallmentService.get_plan_household_id, plan_id)
    if not household_id:
        raise HTTPException(status_code=404, detail="Installment plan not found.")
    await verify_household_access(request, household_id)
    try:
        plan = await asyncio.to_thread(InstallmentService.pay_installment, plan_id, household_id)
        if not plan:
            raise HTTPException(status_code=404, detail="Installment plan not found.")
        return plan.model_dump()
    except HTTPException:
        raise
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to pay installment.")


@router.post(
    "/budgets/recalculate",
    tags=["budgets"],
    summary="Recalculate spent_amount for all categories in a household from transactions.",
)
async def recalculate_budgets_endpoint(
    household_id: str,
    cycle_key: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    try:
        await asyncio.to_thread(InstallmentService.recalculate_budgets, household_id, cycle_key)
        return {"status": "ok", "household_id": household_id, "cycle_key": cycle_key}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to recalculate budgets.")


@router.get(
    "/budgets/breakdown",
    tags=["budgets"],
    summary="Get budget categories and sub-budget spending breakdown for a salary cycle.",
)
async def get_budget_breakdown(
    household_id: str,
    cycle_key: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(get_cycle_breakdown, household_id, cycle_key)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to get budget breakdown.")


@router.post(
    "/budgets/categories",
    tags=["budgets"],
    summary="Add a new category and initial budget allocation.",
)
async def add_budget_category(
    request: Request,
    req: CategoryCreateRequest,
):
    await verify_household_access(request, req.household_id)
    try:
        return await asyncio.to_thread(add_category_and_budget, req)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to add category.")


@router.post(
    "/budgets/sub-allocations",
    tags=["budgets"],
    summary="Set sub-category budget allocations and automatically recompute parent budget amount.",
)
async def set_sub_allocations(
    request: Request,
    req: SubAllocationsRequest,
):
    await verify_household_access(request, req.household_id)
    try:
        return await asyncio.to_thread(
            save_sub_allocations,
            household_id=req.household_id,
            category_code=req.category_code,
            sub_allocations=req.sub_allocations,
            cycle_key=req.cycle_key,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to save sub-allocations.")


@router.post(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Add a new sub-category to a parent budget category with an allocation.",
)
async def add_sub_category(
    request: Request,
    req: SubCategoryCreateRequest,
):
    await verify_household_access(request, req.household_id)
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
        raise safe_error_response(exc, public_message="Failed to add sub-category.")


@router.get(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Get all sub-categories for a parent category code.",
)
async def get_sub_categories_route(parent_code: str, request: Request):
    get_current_user_id(request)
    try:
        sub_cats = await asyncio.to_thread(get_sub_categories_for_parent, parent_code)
        return {
            "status": "success",
            "sub_categories": sub_cats,
        }
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to get sub-categories.")


@router.patch(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Rename an existing sub-category.",
)
async def rename_sub_category_endpoint(req: SubCategoryRenameRequest, request: Request):
    """
    Sub-category definitions are not household-scoped in the schema. Renaming is therefore
    only allowed under a parent category that is a household's own custom category, and only
    by an admin of that household. Shared/system definitions are read-only for households.
    """
    get_current_user_id(request)
    ownership = await asyncio.to_thread(get_category_owner_households, req.parent_code)
    if ownership["shared"] or not ownership["owners"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Shared system sub-categories cannot be renamed by a household.",
        )
    authorized = False
    for owner_household_id in ownership["owners"]:
        try:
            await verify_household_admin_access(request, owner_household_id)
            authorized = True
            break
        except HTTPException as exc:
            if exc.status_code == status.HTTP_401_UNAUTHORIZED:
                raise
    if not authorized:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: Admin access to the owning household is required.",
        )
    try:
        return await asyncio.to_thread(
            rename_sub_category,
            parent_code=req.parent_code,
            sub_code=req.sub_code,
            name_en=req.name_en,
            name_ar=req.name_ar,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to rename sub-category.")


@router.delete(
    "/budgets/sub-categories",
    tags=["budgets"],
    summary="Remove a sub-category from budget and purge if unused.",
)
async def remove_sub_category_endpoint(
    household_id: str,
    parent_code: str,
    sub_code: str,
    cycle_key: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    if not household_id or not parent_code or not sub_code:
        raise HTTPException(status_code=400, detail="household_id, parent_code, and sub_code are required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(
            remove_sub_category_for_household,
            household_id=household_id,
            parent_code=parent_code,
            sub_code=sub_code,
            cycle_key=cycle_key,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to remove sub-category.")


@router.delete(
    "/budgets/categories/{category_code}",
    tags=["budgets"],
    summary="Deactivate or remove a category allocation for a household.",
)
async def delete_budget_category(
    category_code: str,
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(archive_category_for_household, household_id, category_code)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to archive category.")


@router.post(
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
        raise safe_error_response(exc, status_code=422, public_message="Invalid request body.")

    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Request body must be a JSON object.")
    household_id = body.get("household_id")
    try:
        target_amount = float(body.get("target_amount") or 0.0)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="target_amount must be a number.")
    if not math.isfinite(target_amount) or target_amount < 0 or target_amount > MAX_SAR_AMOUNT:
        raise HTTPException(status_code=400, detail="target_amount must be between 0 and 10,000,000 SAR.")
    item_name = str(body.get("item_name") or "Item")[:120]
    category_code = body.get("category_code")

    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    await verify_household_access(request, household_id)

    try:
        return await asyncio.to_thread(
            simulate_affordability,
            household_id=household_id,
            target_amount=target_amount,
            item_name=item_name,
            category_code=category_code,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to simulate affordability.")
