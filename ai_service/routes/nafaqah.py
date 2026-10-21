"""
Family Nafaqah routes: the wife's reimbursement ledger and her personal allowance.

Every route authenticates the Supabase JWT and checks household membership
(``verify_household_access``); the acting user is always the JWT subject, never a body field,
and every wife id is checked to be a spouse member of the URL's household (no IDOR).

The husband is the household's explicit Nafaqah provider (``PUT .../nafaqah/provider``, admins);
roles are read per household (migration 20261020800000).
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from auth import get_current_user_id, verify_household_access, verify_household_admin_access
from models import NafaqahAllowanceSetRequest, NafaqahProviderSetRequest, NafaqahReimbursementCreateRequest
from nafaqah_service import (
    InvalidNafaqahRequest,
    LedgerWouldBeOverpaid,
    NafaqahClassificationForbidden,
    NafaqahError,
    NafaqahForbidden,
    NoProviderError,
    NotFamilyHousehold,
    OverpaymentError,
    build_summary,
    get_allowance,
    get_reimbursement_ledger,
    load_family_context,
    record_reimbursement,
    resolve_wife_id,
    set_allowance,
    set_provider,
)
from utils import safe_error_response, validate_uuid

logger = logging.getLogger(__name__)

router = APIRouter()

_CYCLE_KEY_PATTERN = r"^[0-9]{4}-(0[1-9]|1[0-2])$"


def nafaqah_http_error(exc: NafaqahError) -> HTTPException:
    """Rule violations → 403 (who), 409 (state: not a family / overpayment / ledger / no provider), 422 (input)."""
    if isinstance(exc, NafaqahClassificationForbidden):
        # D2: the recorder may not classify (chat / receipt / DB refusal); the client shows why.
        return HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail={"message": str(exc), "code": exc.code}
        )
    if isinstance(exc, NafaqahForbidden):
        return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    if isinstance(exc, OverpaymentError):
        detail = {"message": str(exc), "code": "overpayment"}
        if exc.outstanding is not None:
            detail["outstanding"] = exc.outstanding
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)
    if isinstance(exc, LedgerWouldBeOverpaid):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": "ledger_would_be_overpaid"}
        )
    if isinstance(exc, NoProviderError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": "no_provider"})
    if isinstance(exc, NotFamilyHousehold):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": "not_family"})
    if isinstance(exc, InvalidNafaqahRequest):
        return HTTPException(status_code=422, detail=str(exc))
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))


async def _run(fn, *args, public_message: str):
    try:
        return await asyncio.to_thread(fn, *args)
    except NafaqahError as exc:
        raise nafaqah_http_error(exc)
    except HTTPException:
        raise
    except Exception as exc:
        raise safe_error_response(exc, public_message=public_message)


@router.get(
    "/households/{household_id}/nafaqah",
    tags=["nafaqah"],
    summary="Family Nafaqah summary: husband-owes-wife balance and the wife's allowance for a cycle.",
)
async def nafaqah_summary(
    household_id: str,
    request: Request,
    cycle_key: Optional[str] = Query(None, pattern=_CYCLE_KEY_PATTERN),
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)

    def work():
        return build_summary(load_family_context(household_id), caller, cycle_key)

    return await _run(work, public_message="Failed to load the Nafaqah summary.")


@router.get(
    "/households/{household_id}/nafaqah/reimbursements",
    tags=["nafaqah"],
    summary="Wife reimbursement ledger: outstanding balance and history of advances and repayments.",
)
async def nafaqah_reimbursement_ledger(
    household_id: str,
    wife_user_id: Optional[str] = Query(None),
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        return get_reimbursement_ledger(ctx, resolve_wife_id(ctx, wife_user_id))

    return await _run(work, public_message="Failed to load the reimbursement ledger.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursements",
    tags=["nafaqah"],
    summary="Record a partial or full repayment of the wife's advances (overpayment rejected).",
)
async def nafaqah_record_reimbursement(
    household_id: str,
    payload: NafaqahReimbursementCreateRequest,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        if not ctx.is_member(caller):
            raise NafaqahForbidden("Not a member of this household.")
        wife_id = resolve_wife_id(ctx, payload.wife_user_id)
        return record_reimbursement(
            ctx, caller, wife_id, str(payload.amount), payload.payment_method, payload.notes
        )

    return await _run(work, public_message="Failed to record the reimbursement.")


@router.get(
    "/households/{household_id}/nafaqah/allowance",
    tags=["nafaqah"],
    summary="Wife personal allowance for a salary cycle: allocated, spent and remaining.",
)
async def nafaqah_get_allowance(
    household_id: str,
    wife_user_id: Optional[str] = Query(None),
    cycle_key: Optional[str] = Query(None, pattern=_CYCLE_KEY_PATTERN),
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        return get_allowance(ctx, resolve_wife_id(ctx, wife_user_id), cycle_key)

    return await _run(work, public_message="Failed to load the allowance.")


@router.put(
    "/households/{household_id}/nafaqah/allowance",
    tags=["nafaqah"],
    summary="Set the wife's personal allowance for a salary cycle (husband or household admin).",
)
async def nafaqah_set_allowance(
    household_id: str,
    payload: NafaqahAllowanceSetRequest,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        wife_id = resolve_wife_id(ctx, payload.wife_user_id)
        return set_allowance(ctx, caller, wife_id, str(payload.amount), payload.cycle_key)

    return await _run(work, public_message="Failed to set the allowance.")


@router.put(
    "/households/{household_id}/nafaqah/provider",
    tags=["nafaqah"],
    summary="Choose the household's Nafaqah provider (husband): a non-spouse member (household admins).",
)
async def nafaqah_set_provider(
    household_id: str,
    payload: NafaqahProviderSetRequest,
    request: Request,
    _auth: str = Depends(verify_household_admin_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)

    def work():
        result = set_provider(load_family_context(household_id), caller, payload.user_id)
        return {**result, "summary": build_summary(load_family_context(household_id), caller)}

    return await _run(work, public_message="Failed to set the Nafaqah provider.")
