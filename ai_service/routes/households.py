"""Household management routes: payday, income, rollover rules, savings, invites, dependents, settlement, categories."""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from auth import verify_household_access, verify_household_admin_access, get_current_user_id
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
    PrimaryAdminTransferRequest,
)
from household_permissions import (
    HouseholdPermissionError,
    InvalidRoleChangeError,
    MemberNotFoundError,
    PermissionDeniedError,
    can_record_settlement,
    list_members,
    member_role,
    promote_member,
    revoke_admin,
    transfer_primary_admin,
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
from nafaqah_service import (
    PAYMENT_METHODS as NAFAQAH_PAYMENT_METHODS,
    NafaqahError,
    load_family_context,
    record_reimbursement,
    resolve_wife_id,
)
from routes.nafaqah import nafaqah_http_error
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
    _auth: str = Depends(verify_household_admin_access),
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
    _auth: str = Depends(verify_household_admin_access),
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
    _auth: str = Depends(verify_household_admin_access),
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
    _auth: str = Depends(verify_household_admin_access),
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


from rate_limiter import default_rate_limiter
from utils import get_client_ip


@router.get(
    "/households/invites/{invite_code}",
    tags=["households"],
    summary="Inspect invite code metadata and assigned role.",
)
async def inspect_household_role_invite_endpoint(invite_code: str, request: Request):
    if not invite_code:
        raise HTTPException(status_code=400, detail="invite_code is required.")

    # Rate-limit invite inspection by client IP (rightmost X-Forwarded-For hop)
    client_ip = get_client_ip(request)
    await default_rate_limiter.check_rate_limit(f"inspect_invite:{client_ip}", max_requests=20, window_seconds=60)

    try:
        raw = await asyncio.to_thread(inspect_household_role_invite, invite_code)
        # Return minimal safe public metadata: omit household_id, created_by
        is_valid = raw.get("is_valid", False)
        return {
            "invite_code": raw.get("invite_code", invite_code.strip().upper()),
            "role": raw.get("role", "peer"),
            "is_valid": is_valid,
            "expires_at": raw.get("expires_at"),
            "target_member_name": raw.get("target_member_name"),
            "target_member_id": raw.get("target_member_id") if is_valid else None,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to inspect invite.")


@router.post(
    "/households/invites/{invite_code}/claim",
    tags=["households"],
    summary="Claim a household invite code and link user account to member profile.",
)
async def claim_household_role_invite_endpoint(
    invite_code: str,
    request: Request,
    payload: Optional[HouseholdProfileClaimRequest] = None,
):
    if not invite_code:
        raise HTTPException(status_code=400, detail="invite_code is required.")
    
    # Must be authenticated with Supabase JWT; user_id is extracted from token, never request body
    user_id = get_current_user_id(request)
    try:
        res = await asyncio.to_thread(claim_household_role_invite, invite_code, user_id)
        if res.get("code") == "rate_limited":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=res.get("error", "Too many failed join attempts. Please try again later."),
                headers={"Retry-After": "900"},
            )
        if res.get("status") != "success":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=res.get("error", "Failed to claim invite code."),
            )
        return res
    except HTTPException:
        raise
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
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    """
    Roommate/partner households: a settlement transaction between members (unchanged).
    Family households (Nafaqah): the only debt is the husband's to his wife for her advances, so
    a repayment to the wife goes to the append-only Nafaqah ledger (overpayment rejected) and any
    other direction is refused; nothing in a family is split between the spouses.
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    if payload.household_id != household_id:
        raise HTTPException(status_code=400, detail="Body household_id does not match the URL.")
    if payload.payer_id.strip().lower() == payload.recipient_id.strip().lower():
        raise HTTPException(status_code=400, detail="payer_id and recipient_id must differ.")
    caller = get_current_user_id(request)
    try:
        ctx = await asyncio.to_thread(load_family_context, household_id)
    except Exception as exc:
        # No fallback: guessing "not a family" would record a split between the spouses.
        raise safe_error_response(exc, public_message="Failed to record reimbursement.")
    if ctx.is_family:
        try:
            wife_id = resolve_wife_id(ctx, payload.recipient_id)
        except NafaqahError:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="In a family household only the husband's repayments to his wife are recorded.",
            )
        method = payload.payment_method.strip().lower()
        if method not in NAFAQAH_PAYMENT_METHODS:
            method = "other"
        try:
            result = await asyncio.to_thread(
                record_reimbursement, ctx, caller, wife_id, str(payload.amount), method, payload.notes
            )
        except NafaqahError as exc:
            raise nafaqah_http_error(exc)
        except Exception as exc:
            raise safe_error_response(exc, public_message="Failed to record reimbursement.")
        return {**result, "mode": "family_nafaqah", "is_settlement": False}
    # Both parties must be members of this household (the ids are stored on the transaction and
    # read back by the settlement engines).
    payer_id = payload.payer_id.strip().lower()
    recipient_id = payload.recipient_id.strip().lower()
    if not (ctx.is_member(payer_id) and ctx.is_member(recipient_id)):
        raise HTTPException(status_code=400, detail="payer_id and recipient_id must be members of this household.")
    # A settlement attributes a payment to members: either party records it, or an admin (DB-18).
    try:
        caller_role = await asyncio.to_thread(member_role, household_id, caller)
    except Exception as exc:
        raise safe_error_response(exc, public_message="Failed to record reimbursement.")
    if not can_record_settlement(caller, caller_role, payer_id, recipient_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer, the recipient or a household admin can record this settlement.",
        )
    try:
        return await asyncio.to_thread(
            record_household_reimbursement,
            household_id=household_id,
            payer_id=payer_id,
            recipient_id=recipient_id,
            amount=payload.amount,
            payment_method=payload.payment_method,
            notes=payload.notes,
            recorded_by=caller,
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
    request: Request,
    split_ratio: float = Query(0.50, ge=0.0, le=1.0, allow_inf_nan=False),
    _auth: str = Depends(verify_household_access),
):
    """
    Aggregates transactions in the active salary cycle by spent_by ('me', 'partner', 'both').
    Returns net balance, who owes whom, and copyable STC Pay / Urpay / IBAN transfer note.
    split_ratio applies to roommate/partner households only; married-family households are
    settled by Nafaqah rules (no 50/50 spousal split).
    """
    if not household_id:
        raise HTTPException(status_code=400, detail="household_id is required.")
    validate_uuid(household_id)
    caller_user_id = get_current_user_id(request)
    try:
        return await asyncio.to_thread(
            calculate_partner_settlement, household_id, split_ratio=split_ratio, caller_user_id=caller_user_id
        )
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
    _auth: str = Depends(verify_household_admin_access),
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
    _auth: str = Depends(verify_household_admin_access),
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



# ─── Members, co-admins and the primary admin (owner decision on DB-16 / DB-18) ──

def _permission_http_error(exc: HouseholdPermissionError) -> HTTPException:
    if isinstance(exc, PermissionDeniedError):
        return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    if isinstance(exc, MemberNotFoundError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if isinstance(exc, InvalidRoleChangeError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))


async def _run_roles(fn, *args, public_message: str):
    try:
        return await asyncio.to_thread(fn, *args)
    except HouseholdPermissionError as exc:
        raise _permission_http_error(exc)
    except HTTPException:
        raise
    except Exception as exc:
        raise safe_error_response(exc, public_message=public_message)


@router.get(
    "/households/{household_id}/members",
    tags=["households"],
    summary="Members of the household with their roles; the primary admin is listed first.",
)
async def list_household_members(
    household_id: str,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)
    return await _run_roles(list_members, household_id, caller, public_message="Failed to list members.")


@router.post(
    "/households/{household_id}/members/{member_user_id}/admin",
    tags=["households"],
    summary="Make a member an admin (co-admin). Any admin of the household may do this.",
)
async def promote_household_member(
    household_id: str,
    member_user_id: str,
    request: Request,
    _auth: str = Depends(verify_household_admin_access),
):
    validate_uuid(household_id)
    validate_uuid(member_user_id)
    caller = get_current_user_id(request)
    return await _run_roles(
        promote_member, household_id, caller, member_user_id, public_message="Failed to promote member."
    )


@router.delete(
    "/households/{household_id}/members/{member_user_id}/admin",
    tags=["households"],
    summary="Revoke a co-admin. The primary admin and the last admin cannot be demoted.",
)
async def revoke_household_admin(
    household_id: str,
    member_user_id: str,
    request: Request,
    _auth: str = Depends(verify_household_admin_access),
):
    validate_uuid(household_id)
    validate_uuid(member_user_id)
    caller = get_current_user_id(request)
    return await _run_roles(
        revoke_admin, household_id, caller, member_user_id, public_message="Failed to revoke admin."
    )


@router.post(
    "/households/{household_id}/primary-admin",
    tags=["households"],
    summary="Transfer primary admin to another member (primary admin only).",
)
async def transfer_household_primary_admin(
    household_id: str,
    payload: PrimaryAdminTransferRequest,
    request: Request,
    _auth: str = Depends(verify_household_admin_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)
    return await _run_roles(
        transfer_primary_admin,
        household_id,
        caller,
        payload.new_primary_user_id,
        public_message="Failed to transfer primary admin.",
    )
