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
from models import (
    FormerMemberDebtPaymentRequest,
    FormerMemberDebtWaiverRequest,
    NafaqahAllowanceSetRequest,
    NafaqahProviderSetRequest,
    NafaqahReimbursementCreateRequest,
    NafaqahRepaymentRequestApprove,
    NafaqahRepaymentRequestCreate,
    NafaqahRepaymentRequestDecline,
    NafaqahReversalRequest,
)
from nafaqah_service import (
    AccountForbidden,
    AppUpdateRequired,
    InvalidCodedRequest,
    PendingExceedsOutstanding,
    RecordNotFound,
    RequestExceedsOutstanding,
    RequestNotFound,
    RequestNotPending,
    ReversalRefused,
    WifeMustRequest,
    approve_reimbursement_request,
    cancel_reimbursement_request,
    create_reimbursement_request,
    decline_reimbursement_request,
    reverse_former_member_debt_payment,
    reverse_reimbursement,
    AccountUnavailable,
    InsufficientFunds,
    DebtClosed,
    DebtNotFound,
    InvalidNafaqahRequest,
    RequestKeyReused,
    NoWifeInHousehold,
    LedgerWouldBeOverpaid,
    NafaqahClassificationForbidden,
    NafaqahError,
    NafaqahForbidden,
    NoProviderError,
    NotFamilyHousehold,
    AccountPendingDeletion,
    OverpaymentError,
    build_summary,
    get_allowance,
    get_reimbursement_ledger,
    load_family_context,
    record_former_member_debt_payment,
    record_reimbursement,
    resolve_wife_id,
    waive_former_member_debt,
    set_allowance,
    set_provider,
)
from utils import safe_error_response, validate_uuid

logger = logging.getLogger(__name__)

router = APIRouter()

_CYCLE_KEY_PATTERN = r"^[0-9]{4}-(0[1-9]|1[0-2])$"


def nafaqah_http_error(exc: NafaqahError) -> HTTPException:
    """Rule violations → 403 (who), 404 (no such record here), 409 (state: not a family / overpayment /
    ledger / no provider / record closed / insufficient funds / request no longer pending /
    reversal refused), 422 (input), 426 (an app that predates tracked repayments)."""
    if isinstance(exc, AppUpdateRequired):
        # Owner decision 2026-11-06: a repayment without an account is never recorded.
        return HTTPException(status_code=426, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, WifeMustRequest):
        return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, (RequestNotFound, RecordNotFound)):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, (RequestNotPending, ReversalRefused)):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, RequestExceedsOutstanding):
        detail = {"message": str(exc), "code": exc.code}
        if exc.outstanding is not None:
            detail["outstanding"] = exc.outstanding
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)
    if isinstance(exc, PendingExceedsOutstanding):
        detail = {"message": str(exc), "code": exc.code}
        if exc.available is not None:
            detail["available"] = exc.available
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)
    if isinstance(exc, InvalidCodedRequest):
        return HTTPException(status_code=422, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, (AccountForbidden, AccountUnavailable)):
        # Migration 20261105001300: an account he may not pay from, or one this household cannot use.
        return HTTPException(
            status_code=status.HTTP_403_FORBIDDEN if isinstance(exc, AccountForbidden) else 422,
            detail={"message": str(exc), "code": exc.code},
        )
    if isinstance(exc, InsufficientFunds):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": exc.code})
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
    if isinstance(exc, DebtNotFound):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, (DebtClosed, RequestKeyReused)):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, NotFamilyHousehold):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": "not_family"})
    if isinstance(exc, AccountPendingDeletion):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, NoWifeInHousehold):
        return HTTPException(status_code=422, detail={"message": str(exc), "code": exc.code})
    if isinstance(exc, InvalidNafaqahRequest):
        return HTTPException(status_code=422, detail=str(exc))
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))


def _family_context(household_id: str):
    """The household's context, refused outside a family (the Nafaqah ledgers are a family's)."""
    ctx = load_family_context(household_id)
    if not ctx.is_family:
        raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
    return ctx


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
    summary="Wife reimbursement ledger: balance, advances, repayments and reversals (with who may reverse), and her requests.",
)
async def nafaqah_reimbursement_ledger(
    household_id: str,
    request: Request,
    wife_user_id: Optional[str] = Query(None),
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        return get_reimbursement_ledger(ctx, resolve_wife_id(ctx, wife_user_id), caller)

    return await _run(work, public_message="Failed to load the reimbursement ledger.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursements",
    tags=["nafaqah"],
    summary="The husband or an admin records a repayment, paid from an account (required; 426 without one).",
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
            ctx, caller, wife_id, str(payload.amount), payload.payment_method, payload.notes,
            account_id=payload.account_id, request_key=payload.request_key,
        )

    return await _run(work, public_message="Failed to record the reimbursement.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursements/{reimbursement_id}/reversal",
    tags=["nafaqah"],
    summary="Reverse a tracked repayment in full: the money goes back to its account, the amount is owed again.",
)
async def nafaqah_reverse_reimbursement(
    household_id: str,
    reimbursement_id: str,
    payload: NafaqahReversalRequest,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(reimbursement_id)
    caller = get_current_user_id(request)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        return reverse_reimbursement(ctx, caller, reimbursement_id, payload.request_key)

    return await _run(work, public_message="Failed to reverse the repayment.")


# ─── The wife's requests (migration 20261105001300) ─────────────────────────────
# She marks "I received X"; the husband or an admin approves it from an account (the normal
# repayment of exactly that amount) or declines it; she can cancel it while it is pending.


@router.get(
    "/households/{household_id}/nafaqah/reimbursement-requests",
    tags=["nafaqah"],
    summary="Her requests with their outcomes (pending, approved, declined, cancelled, closed), newest first.",
)
async def nafaqah_list_repayment_requests(
    household_id: str,
    wife_user_id: Optional[str] = Query(None),
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)

    def work():
        ctx = load_family_context(household_id)
        if not ctx.is_family:
            raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")
        ledger = get_reimbursement_ledger(ctx, resolve_wife_id(ctx, wife_user_id))
        return {"requests": ledger["requests"], "balance": ledger["balance"]}

    return await _run(work, public_message="Failed to load the requests.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursement-requests",
    tags=["nafaqah"],
    summary="The wife marks what she received: a pending request; nothing moves until it is approved.",
)
async def nafaqah_create_repayment_request(
    household_id: str,
    payload: NafaqahRepaymentRequestCreate,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    caller = get_current_user_id(request)

    def work():
        return create_reimbursement_request(
            load_family_context(household_id), caller, str(payload.amount), payload.payment_method, payload.request_key,
        )

    return await _run(work, public_message="Failed to send the request.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursement-requests/{request_id}/cancel",
    tags=["nafaqah"],
    summary="The wife cancels her own pending request.",
)
async def nafaqah_cancel_repayment_request(
    household_id: str,
    request_id: str,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(request_id)
    caller = get_current_user_id(request)

    def work():
        return cancel_reimbursement_request(load_family_context(household_id), caller, request_id)

    return await _run(work, public_message="Failed to cancel the request.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursement-requests/{request_id}/approve",
    tags=["nafaqah"],
    summary="The husband or an admin approves her request, paying exactly that amount from an account.",
)
async def nafaqah_approve_repayment_request(
    household_id: str,
    request_id: str,
    payload: NafaqahRepaymentRequestApprove,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(request_id)
    caller = get_current_user_id(request)

    def work():
        return approve_reimbursement_request(
            load_family_context(household_id), caller, request_id, payload.account_id, payload.request_key,
        )

    return await _run(work, public_message="Failed to approve the request.")


@router.post(
    "/households/{household_id}/nafaqah/reimbursement-requests/{request_id}/decline",
    tags=["nafaqah"],
    summary="The husband or an admin declines her request, with an optional short reason; nothing moves.",
)
async def nafaqah_decline_repayment_request(
    household_id: str,
    request_id: str,
    payload: NafaqahRepaymentRequestDecline,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(request_id)
    caller = get_current_user_id(request)

    def work():
        return decline_reimbursement_request(load_family_context(household_id), caller, request_id, payload.reason)

    return await _run(work, public_message="Failed to decline the request.")


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


# ─── A former member's record (migration 20261105001200) ────────────────────────
# What the husband still owed a wife who deleted her account. The husband or any admin who is not a
# wife closes it (review R1-01), in a family household only, as the ledger routes (review R1-10):
# a payment (amount, payment method and the account it is paid from, required, as an ordinary
# reimbursement: his account goes down, no budget moves) or her waiver (إبراء). A tracked payment
# is corrected by a reversal. request_key makes a retried tap record once.


@router.post(
    "/households/{household_id}/nafaqah/former-member-debts/{debt_id}/payments",
    tags=["nafaqah"],
    summary="Record a payment of what was owed to a former member (husband or household admin).",
)
async def nafaqah_former_member_debt_payment(
    household_id: str,
    debt_id: str,
    payload: FormerMemberDebtPaymentRequest,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(debt_id)
    caller = get_current_user_id(request)

    def work():
        return record_former_member_debt_payment(
            _family_context(household_id), caller, debt_id, str(payload.amount),
            payload.payment_method, payload.request_key, account_id=payload.account_id,
        )

    return await _run(work, public_message="Failed to record the payment.")


@router.post(
    "/households/{household_id}/nafaqah/former-member-debts/{debt_id}/payments/{event_id}/reversal",
    tags=["nafaqah"],
    summary="Reverse a tracked payment of a former member's record (reopens a settled record).",
)
async def nafaqah_former_member_debt_payment_reversal(
    household_id: str,
    debt_id: str,
    event_id: str,
    payload: NafaqahReversalRequest,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(debt_id)
    validate_uuid(event_id)
    caller = get_current_user_id(request)

    def work():
        return reverse_former_member_debt_payment(
            _family_context(household_id), caller, debt_id, event_id, payload.request_key,
        )

    return await _run(work, public_message="Failed to reverse the payment.")


@router.post(
    "/households/{household_id}/nafaqah/former-member-debts/{debt_id}/waiver",
    tags=["nafaqah"],
    summary="Record that the former member waived what remained (husband or household admin).",
)
async def nafaqah_former_member_debt_waiver(
    household_id: str,
    debt_id: str,
    payload: FormerMemberDebtWaiverRequest,
    request: Request,
    _auth: str = Depends(verify_household_access),
):
    validate_uuid(household_id)
    validate_uuid(debt_id)
    caller = get_current_user_id(request)

    def work():
        return waive_former_member_debt(_family_context(household_id), caller, debt_id, payload.request_key)

    return await _run(work, public_message="Failed to record the waiver.")
