"""Household management routes: payday, income, rollover rules, savings, invites, dependents, settlement, categories."""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status

from auth import verify_household_access
from utils import safe_error_response, validate_uuid
from models import (
    PaydayUpdateRequest,
    HouseholdIncomeRequest,
    RolloverRuleUpdateRequest,
    HouseholdInviteCreateRequest,
    HouseholdProfileClaimRequest,
    HouseholdReimbursementRequest,
    DependentCreateRequest,
    CategoryToggleRequest,
    CustomCategoryCreateRequest,
)
from supabase_client import (
    get_household_payday,
    set_household_payday,
    get_household_income,
    set_household_income,
    get_household_rollover_rule,
    set_household_rollover_rule,
    get_household_savings_summary,
    create_household_role_invite,
    inspect_household_role_invite,
    claim_household_role_invite,
    record_household_reimbursement,
)
from dependents_service import (
    get_household_dependents,
    create_household_dependent,
    delete_household_dependent,
)
from settlement_engine import calculate_partner_settlement, calculate_settlement_v2
from salary_cycle import (
    get_household_categories,
    toggle_category_status,
    create_household_custom_category,
)

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get(
    "/households/{household_id}/payday",
    tags=["households"],
    summary="Get configured monthly payday day for a household.",
)
async def get_household_payday_endpoint(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        day = await asyncio.to_thread(get_household_payday, household_id)
        return {"household_id": household_id, "payday_day": day}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to get household payday.")


@router.put(
    "/households/{household_id}/payday",
    tags=["households"],
    summary="Update configured monthly payday day for a household.",
)
async def update_household_payday_endpoint(
    household_id: str,
    payload: PaydayUpdateRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        saved_day = await asyncio.to_thread(set_household_payday, household_id, payload.payday_day)
        return {"household_id": household_id, "payday_day": saved_day, "status": "success"}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to update household payday.")


@router.get(
    "/households/{household_id}/income",
    tags=["households"],
    summary="Get configured monthly income/salary for a household.",
)
async def get_household_income_endpoint(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        income = await asyncio.to_thread(get_household_income, household_id)
        return {"household_id": household_id, "monthly_income": income}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to get household income.")


@router.put(
    "/households/{household_id}/income",
    tags=["households"],
    summary="Update configured monthly income/salary for a household.",
)
async def update_household_income_endpoint(
    household_id: str,
    payload: HouseholdIncomeRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        saved_income = await asyncio.to_thread(set_household_income, household_id, payload.monthly_income)
        return {"household_id": household_id, "monthly_income": saved_income, "status": "success"}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to update household income.")


@router.get(
    "/households/{household_id}/rollover-rule",
    tags=["households"],
    summary="Get configured budget rollover rule for a household.",
)
async def get_household_rollover_rule_endpoint(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        rule = await asyncio.to_thread(get_household_rollover_rule, household_id)
        return {"household_id": household_id, "rollover_rule": rule}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to get rollover rule.")


@router.put(
    "/households/{household_id}/rollover-rule",
    tags=["households"],
    summary="Update configured budget rollover rule for a household.",
)
async def update_household_rollover_rule_endpoint(
    household_id: str,
    payload: RolloverRuleUpdateRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        saved_rule = await asyncio.to_thread(set_household_rollover_rule, household_id, payload.rollover_rule)
        return {"household_id": household_id, "rollover_rule": saved_rule, "status": "success"}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to update rollover rule.")


@router.get(
    "/households/{household_id}/savings-summary",
    tags=["households"],
    summary="Get accumulated savings summary and last surplus swept for a household.",
)
async def get_household_savings_summary_endpoint(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(get_household_savings_summary, household_id)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to get savings summary.")


@router.post(
    "/households/{household_id}/invites",
    tags=["households"],
    summary="Create a role-tagged 8-character invite code for a household.",
)
async def create_household_role_invite_endpoint(
    household_id: str,
    payload: HouseholdInviteCreateRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(
            create_household_role_invite,
            household_id,
            payload.role,
            payload.target_member_id,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to create invite.")


@router.get(
    "/households/invites/{invite_code}",
    tags=["households"],
    summary="Inspect invite code metadata and assigned role.",
)
async def inspect_household_role_invite_endpoint(invite_code: str):
    if not invite_code:
        raise HTTPException(status_code=400, detail="invite_code is required.")
    try:
        return await asyncio.to_thread(inspect_household_role_invite, invite_code)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to inspect invite.")


@router.post(
    "/households/invites/{invite_code}/claim",
    tags=["households"],
    summary="Claim a household invite code and link user account to member profile.",
)
async def claim_household_role_invite_endpoint(
    invite_code: str,
    payload: HouseholdProfileClaimRequest,
):
    if not invite_code:
        raise HTTPException(status_code=400, detail="invite_code is required.")
    try:
        return await asyncio.to_thread(claim_household_role_invite, invite_code, payload.user_id)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to claim invite.")


@router.post(
    "/households/{household_id}/reimbursements",
    tags=["settlement"],
    summary="Record a settlement reimbursement transaction between household members.",
)
async def record_household_reimbursement_endpoint(
    household_id: str,
    payload: HouseholdReimbursementRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(
            record_household_reimbursement,
            household_id=household_id,
            payer_id=payload.payer_id,
            recipient_id=payload.recipient_id,
            amount=payload.amount,
            payment_method=payload.payment_method,
            notes=payload.notes,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to record reimbursement.")


@router.get(
    "/households/{household_id}/dependents",
    tags=["dependents"],
    summary="Get all children and dependents for a household.",
)
async def list_household_dependents(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    try:
        deps = await asyncio.to_thread(get_household_dependents, household_id)
        return {"status": "success", "dependents": deps}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to list dependents.")


@router.post(
    "/households/{household_id}/dependents",
    tags=["dependents"],
    summary="Add a new child or dependent to a household.",
)
async def add_household_dependent(
    household_id: str,
    req: DependentCreateRequest,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    try:
        dep = await asyncio.to_thread(
            create_household_dependent,
            household_id,
            req.name,
            req.avatar_icon,
            req.relationship,
            req.monthly_allowance,
        )
        return {"status": "success", "dependent": dep}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to add dependent.")


@router.delete(
    "/households/{household_id}/dependents/{dependent_id}",
    tags=["dependents"],
    summary="Remove a child or dependent from a household.",
)
async def remove_household_dependent(
    household_id: str,
    dependent_id: str,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    try:
        await asyncio.to_thread(delete_household_dependent, household_id, dependent_id)
        return {"status": "success", "message": "Dependent removed successfully."}
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to remove dependent.")


@router.get(
    "/households/{household_id}/settlement",
    tags=["settlement"],
    summary="Calculate shared partner expense balance and settle-up payment note.",
)
async def household_settlement(
    household_id: str,
    split_ratio: float = 0.50,
    _auth: str = Depends(verify_household_access),
):
    """
    Aggregates transactions in the active salary cycle by spent_by ('me', 'partner', 'both').
    Returns net balance, who owes whom, and copyable STC Pay / Urpay / IBAN transfer note.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(calculate_partner_settlement, household_id, split_ratio=split_ratio)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to compute partner settlement.")


@router.get(
    "/households/{household_id}/settlement-v2",
    tags=["settlement"],
    summary="Role-aware multi-party and Islamic Family Nafaqah settlement summary.",
)
async def household_settlement_v2(
    household_id: str,
    cycle_start: Optional[str] = None,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(calculate_settlement_v2, household_id, cycle_start=cycle_start)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to compute settlement v2.")


@router.get(
    "/households/{household_id}/categories",
    tags=["categories"],
    summary="Get active and inactive categories for household.",
)
async def get_household_categories_endpoint(
    household_id: str,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(get_household_categories, household_id)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to fetch household categories.")


@router.post(
    "/households/{household_id}/categories/toggle",
    tags=["categories"],
    summary="Toggle category active/inactive status for a household.",
)
async def toggle_category_endpoint(
    household_id: str,
    req: CategoryToggleRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(
            toggle_category_status,
            household_id=household_id,
            category_code=req.category_code,
            is_active=req.is_active,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to toggle category status.")


@router.post(
    "/households/{household_id}/categories/custom",
    tags=["categories"],
    summary="Create custom root category for a household.",
)
async def create_custom_category_endpoint(
    household_id: str,
    req: CustomCategoryCreateRequest,
    _auth: str = Depends(verify_household_access),
):
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    try:
        return await asyncio.to_thread(
            create_household_custom_category,
            household_id=household_id,
            code=req.code,
            category=req.category,
            keywords=req.keywords,
            is_flexible=req.is_flexible,
            allocated_amount=req.allocated_amount,
        )
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to create custom category.")
