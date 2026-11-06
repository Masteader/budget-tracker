"""
Islamic family Nafaqah ledger: the wife's reimbursement debt and her personal allowance.

Owner decision on audit item UI-24 (family mode = married couple):

1. Nafaqah is on the husband. Shared family/household expenses are his responsibility and are
   never split between the spouses (no 50/50 or any percentage).
2. The wife paying from her own money for something shared (household, children, dependents,
   the husband) is a debt the husband owes her: ``wife_reimbursable``. Reimbursements reduce it,
   partially or in full; paying back more than is outstanding is rejected.
3. A personal purchase the wife makes for herself is not a debt: ``wife_personal`` is charged to
   her personal allowance ("مصروفها") for the salary cycle (``cycle_key``). The husband or a
   household admin sets the allowance; overspend is reported as a negative remainder, not blocked.
4. The husband paying for shared things is an ordinary household expense (no class, no debt).

Roommate households (and any household without a spouse member) never get a Nafaqah class.

Money is handled as ``Decimal`` / integer halalas; floats only appear in API responses.
Writes go through the SECURITY DEFINER RPCs of migration
``20261020300000_nafaqah_wife_allowance_and_reimbursements.sql`` with the verified caller passed
as ``p_actor_user_id``, so the database re-checks every rule (and serialises repayments).

Roles are per household (migration ``20261020800000``, Fable review): who is the wife comes from
``household_memberships.financial_role`` of THAT household (a wife who also joins a roommate flat
stays the wife of her family), and the husband is the household's explicit Nafaqah provider
(``households.nafaqah_provider_user_id``: the primary admin by default, changed by an admin), never
inferred from user-level roles or admin rights.

Household type (owner decision D1, migration ``20261020900000``): ``households.household_type`` is
'family' or 'roommates', chosen at creation. Family features (Nafaqah classes, provider, ledger)
apply only to a 'family' household that has a spouse member; a roommates household never gets them.
Only the wife herself, the Nafaqah provider or a household admin may classify an expense (D2);
the database enforces the same rule for client writes.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Any, Callable, Dict, Iterable, List, Optional

from postgrest_compat import db_error_fields, first_row
from supabase_client import account_deletion_guard_error, get_client, get_household_payday

logger = logging.getLogger(__name__)

WIFE_REIMBURSABLE = "wife_reimbursable"
WIFE_PERSONAL = "wife_personal"
NAFAQAH_CLASSES = (WIFE_REIMBURSABLE, WIFE_PERSONAL)

PAYMENT_METHODS = ("stc_pay", "urpay", "bank_transfer", "iban", "cash", "other")
MAX_AMOUNT = Decimal("999999999999.99")
_HALALA = Decimal("0.01")
_CYCLE_KEY_RE = re.compile(r"^[0-9]{4}-(0[1-9]|1[0-2])$")

_WIFE_ALIASES = ("wife", "spouse")
_HUSBAND_ALIASES = ("husband", "provider")


class NafaqahError(Exception):
    """Base class for Nafaqah rule violations."""


class NafaqahForbidden(NafaqahError):
    """The caller may not perform this action in this household."""


class AccountPendingDeletion(NafaqahError):
    """The grace-period guard refused: the target account is scheduled for deletion."""

    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code


class NotFamilyHousehold(NafaqahError):
    """The household has no spouse member: Nafaqah ledgers do not apply."""


class InvalidNafaqahRequest(NafaqahError):
    """Malformed amount, cycle key, payment method or a wife outside this household."""


class NoWifeInHousehold(InvalidNafaqahRequest):
    """The family has no wife member, so there is no allowance or reimbursement to record (HTTP 422)."""

    code = "no_wife"


class LedgerWouldBeOverpaid(NafaqahError):
    """An edit/delete of a wife_reimbursable advance would leave the advances below the repayments."""


class NoProviderError(NafaqahError):
    """The family household has no Nafaqah provider; an admin must choose one (HTTP 409)."""


class NafaqahClassificationForbidden(NafaqahForbidden):
    """D2: the recorder is not the wife, the Nafaqah provider or a household admin (HTTP 403)."""

    code = "nafaqah_classification_forbidden"


class OverpaymentError(NafaqahError):
    """A reimbursement larger than the outstanding balance."""

    def __init__(self, message: str, outstanding: Optional[float] = None):
        super().__init__(message)
        self.outstanding = outstanding


class DebtNotFound(NafaqahError):
    """No such former member record in this household (HTTP 404)."""

    code = "debt_not_found"


class DebtClosed(NafaqahError):
    """The former member record is already settled or waived (HTTP 409)."""

    code = "debt_closed"


class RequestKeyReused(NafaqahError):
    """The request key already recorded a different action on this record (HTTP 409)."""

    code = "request_key_reused"


# ─── Repayments that move money (migration 20261105001300) ─────────────────────

class AccountUnavailable(InvalidNafaqahRequest):
    """The account is not in this household, is archived or is not in SAR (HTTP 422)."""

    code = "account_unavailable"


class AccountForbidden(NafaqahForbidden):
    """Not his own personal account, a shared pool for a non-admin, or the wife picking one (HTTP 403)."""

    code = "account_forbidden"


class InsufficientFunds(NafaqahError):
    """The account does not hold the amount (HTTP 409), as transfer_between_accounts refuses."""

    code = "insufficient_funds"


class AppUpdateRequired(NafaqahError):
    """A repayment without an account: every repayment moves money now, so the caller is an app
    that predates it (HTTP 426, owner decision 2026-11-06)."""

    code = "app_update_required"


class WifeMustRequest(NafaqahForbidden):
    """The wife does not record a repayment; she asks, and the husband or an admin approves (HTTP 403)."""

    code = "wife_must_request"


class RequestNotFound(NafaqahError):
    """No such request in this household (HTTP 404)."""

    code = "request_not_found"


class RequestNotPending(NafaqahError):
    """The request was already approved, declined, cancelled or closed (HTTP 409)."""

    code = "request_not_pending"


class RequestExceedsOutstanding(NafaqahError):
    """Approval: the requested amount is more than is owed now (HTTP 409); decline it and record
    the right amount."""

    code = "request_exceeds_outstanding"

    def __init__(self, message: str, outstanding: Optional[float] = None):
        super().__init__(message)
        self.outstanding = outstanding


class PendingExceedsOutstanding(NafaqahError):
    """A new request would take the pending total above what is owed (HTTP 409). ``available`` is
    what can still be asked for."""

    code = "pending_exceeds_outstanding"

    def __init__(self, message: str, available: Optional[float] = None):
        super().__init__(message)
        self.available = available


class RecordNotFound(NafaqahError):
    """No such repayment, or no such payment of a former member's record (HTTP 404)."""

    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code


class ReversalRefused(NafaqahError):
    """A reversal the ledger refuses (HTTP 409): ``not_reversible`` (a reversal or a waiver),
    ``already_reversed``, ``reversal_not_tracked`` (a legacy row with no transfer),
    ``reversal_account_unavailable`` (the account is archived or gone) or ``reversal_after_waiver``."""

    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code


class InvalidCodedRequest(InvalidNafaqahRequest):
    """Malformed input with a code the app translates (HTTP 422): ``account_required``,
    ``invalid_reason``, ``request_key_required``."""

    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code


REVERSAL_REFUSALS = (
    "not_reversible", "already_reversed", "reversal_not_tracked", "reversal_account_unavailable", "reversal_after_waiver",
)


# ─── Money ────────────────────────────────────────────────────────────────────

def _decimal(value: Any) -> Decimal:
    try:
        dec = value if isinstance(value, Decimal) else Decimal(str(value if value is not None else 0))
    except (InvalidOperation, ValueError) as exc:
        raise InvalidNafaqahRequest(f"Invalid amount: {value!r}") from exc
    if not dec.is_finite():
        raise InvalidNafaqahRequest("Amount must be a finite number.")
    return dec


def to_halalas(value: Any) -> int:
    """Stored SAR amount → integer halalas (half-up on the decimal value)."""
    return int((_decimal(value) / _HALALA).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def halalas_to_sar(halalas: int) -> float:
    return float((Decimal(halalas) * _HALALA).quantize(_HALALA))


def parse_sar_amount(value: Any, *, allow_zero: bool) -> Decimal:
    """Validate a user-supplied SAR amount: finite, at most 2 decimals, within numeric(14,2)."""
    dec = _decimal(value)
    if dec != dec.quantize(_HALALA):
        raise InvalidNafaqahRequest("Amount must have at most 2 decimal places.")
    if dec < 0 or (dec == 0 and not allow_zero):
        raise InvalidNafaqahRequest("Amount must be positive." if not allow_zero else "Amount cannot be negative.")
    if dec > MAX_AMOUNT:
        raise InvalidNafaqahRequest("Amount is too large.")
    return dec.quantize(_HALALA)


def compute_reimbursement_balance(advances: Iterable[Any], reimbursements: Iterable[Any]) -> Dict[str, float]:
    """Gross wife advances vs. husband repayments, exact to the halala."""
    gross = sum(to_halalas(a) for a in advances)
    paid = sum(to_halalas(r) for r in reimbursements)
    return {
        "gross_advanced": halalas_to_sar(gross),
        "reimbursed": halalas_to_sar(paid),
        "outstanding": halalas_to_sar(max(gross - paid, 0)),
        "overpaid": halalas_to_sar(max(paid - gross, 0)),
    }


def compute_allowance_status(allocated: Optional[Any], spent_amounts: Iterable[Any]) -> Dict[str, Any]:
    """Allocated / spent / remaining; remaining goes negative on overspend (never blocked)."""
    spent_list = [to_halalas(s) for s in spent_amounts]
    allocated_h = to_halalas(allocated) if allocated is not None else 0
    spent_h = sum(spent_list)
    return {
        "is_set": allocated is not None,
        "allocated": halalas_to_sar(allocated_h),
        "spent": halalas_to_sar(spent_h),
        "remaining": halalas_to_sar(allocated_h - spent_h),
        "transaction_count": len(spent_list),
    }


# ─── Classification ───────────────────────────────────────────────────────────

def _norm(value: Any) -> str:
    return str(value or "").strip().lower()


def classify_nafaqah(
    recorder_role: Optional[str],
    paid_by: Optional[str],
    beneficiary: Optional[str],
    is_tabarru: bool = False,
) -> Optional[str]:
    """
    Nafaqah class of an expense from the recorder's point of view.

    ``paid_by`` / ``beneficiary`` use the app's relative vocabulary: 'me' is the recorder,
    'partner' the other spouse, 'both'/'household'/'children' or a dependent's name are shared.
    Only an expense the wife paid from her own money gets a class (rules 2 and 3); whatever the
    husband pays, including things for his wife, is his Nafaqah and an ordinary expense (rule 4).
    ``is_tabarru`` is the explicit opt-in for a voluntary gift by the wife: it is never assumed.
    """
    role = _norm(recorder_role)
    pb, ben = _norm(paid_by), _norm(beneficiary)
    if role == "wife":
        wife_paid = pb in ("me",) + _WIFE_ALIASES
        for_wife = ben in ("me",) + _WIFE_ALIASES
    elif role == "husband":
        wife_paid = pb in ("partner",) + _WIFE_ALIASES
        for_wife = ben in ("partner",) + _WIFE_ALIASES
    else:
        return None
    if not wife_paid:
        return None
    if for_wife:
        return WIFE_PERSONAL
    if is_tabarru:
        return None
    return WIFE_REIMBURSABLE


# ─── Household context ────────────────────────────────────────────────────────

FAMILY = "family"
ROOMMATES = "roommates"
HOUSEHOLD_TYPES = (FAMILY, ROOMMATES)


def infer_household_type(financial_roles: Iterable[Any]) -> str:
    """The migration's backfill rule, for rows read before the column exists: any peer -> roommates."""
    return ROOMMATES if any(_norm(r) == "peer" for r in financial_roles) else FAMILY


def normalize_household_type(value: Any, financial_roles: Iterable[Any] = ()) -> str:
    """households.household_type as stored, or the backfill rule when it is missing/unknown."""
    norm = _norm(value)
    return norm if norm in HOUSEHOLD_TYPES else infer_household_type(financial_roles)


@dataclass
class FamilyContext:
    household_id: str
    members: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    # The husband: the explicit provider while the household is a family and he is still a
    # non-spouse member; None otherwise (mirrors public.nafaqah_husband_id()).
    husband_id: Optional[str] = None
    wives: List[Dict[str, Any]] = field(default_factory=list)
    # households.nafaqah_provider_user_id as stored (also set in households without a wife).
    provider_user_id: Optional[str] = None
    primary_admin_id: Optional[str] = None
    # households.household_type: 'family' | 'roommates' (decides the settlement mode).
    household_type: str = FAMILY

    @property
    def is_roommates(self) -> bool:
        return self.household_type == ROOMMATES

    @property
    def is_family(self) -> bool:
        """A 'family' household: the Nafaqah rules apply (never in roommates)."""
        if self.is_roommates:
            return False
        return self.household_type == FAMILY or any(
            m.get("financial_role") == "spouse" for m in self.members.values()
        )

    @property
    def settlement_mode(self) -> str:
        """'multi_roommate' for a roommates household, else 'family_nafaqah' (spouses never split)."""
        return "multi_roommate" if self.is_roommates else "family_nafaqah"

    def can_classify(self, user_id: Optional[str]) -> bool:
        """D2: the wife herself, the Nafaqah provider or a household admin may classify."""
        if not self.is_member(user_id):
            return False
        uid = str(user_id)
        return self.is_wife(uid) or uid == self.provider_user_id or self.is_admin(uid)

    @property
    def needs_provider(self) -> bool:
        """A family with a wife and no (valid) provider: new classified expenses are refused until set.

        husband_id needs a wife, and without one there is nothing to classify, so a family with no
        wife is never asked, or the notice would show with a provider set and no way to clear it.
        """
        return self.is_family and bool(self.wives) and not self.husband_id

    @property
    def ledger_husband_id(self) -> Optional[str]:
        """Her husband, for her repayment ledger and a former member's record (review R3-01; mirrors
        public.nafaqah_ledger_husband_id): the household's provider while he is a current member who
        is not a wife. Unlike ``husband_id`` it does not need a wife in the household: a former
        member's record outlives the last wife. None: the husband is gone."""
        provider = self.provider_user_id
        if not provider or not self.is_member(provider):
            return None
        if self.members[provider].get("financial_role") == "spouse":
            return None
        return provider

    @property
    def husband_gone(self) -> bool:
        """He left, his account was deleted (both clear the provider), or nobody was named."""
        return self.ledger_husband_id is None

    def is_member(self, user_id: Optional[str]) -> bool:
        return bool(user_id) and str(user_id) in self.members

    def is_admin(self, user_id: Optional[str]) -> bool:
        return self.is_member(user_id) and self.members[str(user_id)].get("role") == "admin"

    def is_wife(self, user_id: Optional[str]) -> bool:
        return bool(user_id) and any(w["id"] == str(user_id) for w in self.wives)

    def role_of(self, user_id: Optional[str]) -> Optional[str]:
        """'wife' | 'husband' | 'member' for members of the household, else None."""
        if not self.is_member(user_id):
            return None
        if self.is_wife(user_id):
            return "wife"
        if self.husband_id and str(user_id) == self.husband_id:
            return "husband"
        return "member"

    def display_name(self, user_id: Optional[str]) -> Optional[str]:
        member = self.members.get(str(user_id or ""))
        return member.get("display_name") if member else None


def _household_roles_row(client, household_id: str) -> Dict[str, Any]:
    """owner_user_id (primary admin), nafaqah_provider_user_id and household_type of the household."""
    row = first_row(
        client.table("households")
        .select("owner_user_id, nafaqah_provider_user_id, household_type")
        .eq("id", household_id)
    )
    return row or {}


def load_family_context(household_id: str) -> FamilyContext:
    """
    Members of the household (household_memberships is authoritative) with their financial role
    IN THIS HOUSEHOLD (``household_memberships.financial_role``). The husband is the household's
    explicit Nafaqah provider (``households.nafaqah_provider_user_id``), as long as the household
    has a wife and he is a non-spouse member; admin rights or a user-level role never make anyone
    the husband. ``household_type`` comes from ``households.household_type`` (the migration's
    backfill rule when the row has none): a roommates household is never a family, whatever the
    roles say. Errors propagate: callers must not guess "not a family".
    """
    client = get_client()
    memberships = (
        client.table("household_memberships")
        .select("user_id, role, created_at, financial_role")
        .eq("household_id", household_id)
        .execute()
    ).data or []
    user_ids = [str(m["user_id"]) for m in memberships if m.get("user_id")]
    users: Dict[str, Dict[str, Any]] = {}
    if user_ids:
        rows = (
            client.table("users")
            .select("id, display_name")
            .in_("id", user_ids)
            .execute()
        ).data or []
        users = {str(u["id"]): u for u in rows if u.get("id")}

    ctx = FamilyContext(household_id=household_id)
    for m in memberships:
        uid = str(m.get("user_id") or "")
        if not uid:
            continue
        user = users.get(uid, {})
        ctx.members[uid] = {
            "id": uid,
            "role": m.get("role") or "member",
            "created_at": str(m.get("created_at") or ""),
            "display_name": user.get("display_name"),
            # NOT NULL in the database; a missing value is never read as 'spouse' or 'provider'.
            "financial_role": _norm(m.get("financial_role")) or "family_member",
        }

    roles = _household_roles_row(client, household_id)
    ctx.household_type = normalize_household_type(
        roles.get("household_type"), (m["financial_role"] for m in ctx.members.values())
    )

    ordered = sorted(ctx.members.values(), key=lambda m: (m["created_at"], m["id"]))
    if ctx.household_type == FAMILY:
        ctx.wives = [
            {"id": m["id"], "display_name": m["display_name"]}
            for m in ordered
            if m["financial_role"] == "spouse"
        ]

    owner = str(roles.get("owner_user_id") or "") or None
    provider = str(roles.get("nafaqah_provider_user_id") or "") or None
    ctx.primary_admin_id = owner
    ctx.provider_user_id = provider
    if ctx.wives and provider and ctx.is_member(provider) and not ctx.is_wife(provider):
        ctx.husband_id = provider
    return ctx


OVERRIDE_NONE = "none"
NAFAQAH_OVERRIDE_CHOICES = NAFAQAH_CLASSES + (OVERRIDE_NONE,)


def attribution_for_class(role: str, nafaqah_class: Optional[str], beneficiary: Optional[str]) -> tuple:
    """
    Recorder-relative (paid_by, beneficiary) that express a class chosen without an explicit
    attribution, so the stored row never contradicts its class. ``nafaqah_class`` None means the
    husband paid (rule 4).
    """
    wife_side, husband_side = ("me", "partner") if role == "wife" else ("partner", "me")
    ben = beneficiary if _norm(beneficiary) else "both"
    ben_is_wife = _norm(ben) in (wife_side,) + _WIFE_ALIASES
    if nafaqah_class == WIFE_PERSONAL:
        return wife_side, wife_side
    if nafaqah_class == WIFE_REIMBURSABLE:
        return wife_side, ("both" if ben_is_wife else ben)
    return husband_side, ben


def resolve_expense_nafaqah(
    household_id: str,
    user_id: Optional[str],
    paid_by: str,
    beneficiary: Optional[str],
    *,
    override_class: Optional[str] = None,
    override_spouse_id: Any = None,
    attribution_explicit: bool = False,
    require_spouse: bool = False,
) -> Dict[str, Any]:
    """
    Nafaqah class (rules 2-4) of an expense entered by chat or a scanned receipt.

    The class follows from who paid for whom (``classify_nafaqah``). ``override_class`` is the
    user's confirmed choice ('wife_reimbursable' | 'wife_personal' | 'none' = the husband paid):
    with an explicit ``paid_by``/``beneficiary`` it must agree with them (a stale class from an
    earlier preview is rejected, never stored against the edited attribution); without one the
    attribution is recomputed from the class. ``override_spouse_id`` names the wife in a
    household with several wives (required on commit when the class needs her); a wife records
    only for herself. Households without a spouse member (and roommates households) are never
    classified. ``require_spouse`` marks a commit: then a failed household lookup raises instead
    of degrading to "not a family".
    D2: only the wife, the Nafaqah provider (husband) or a household admin may classify. An admin
    who is neither spouse classifies only by an explicit ``override_class`` (no spouse-relative
    vocabulary to derive it from); any other member choosing a class gets
    NafaqahClassificationForbidden (HTTP 403, code ``nafaqah_classification_forbidden``).
    Raises InvalidNafaqahRequest for an unknown or contradicting choice.
    """
    chosen = (_norm(override_class) or None) if override_class is not None else None
    if chosen is not None and chosen not in NAFAQAH_OVERRIDE_CHOICES:
        raise InvalidNafaqahRequest("nafaqah_class must be 'wife_reimbursable', 'wife_personal' or 'none'.")
    if override_spouse_id is not None and not isinstance(override_spouse_id, str):
        raise InvalidNafaqahRequest("nafaqah_spouse_id must be a member id.")
    requested_spouse = _norm(override_spouse_id) or None

    result: Dict[str, Any] = {
        "household_mode": "not_family",
        "recorder_role": None,
        "nafaqah_class": None,
        "nafaqah_spouse_id": None,
        "nafaqah_spouse_required": False,
        "wives": [],
        "paid_by": paid_by,
        "beneficiary": beneficiary,
    }
    try:
        ctx = load_family_context(household_id)
    except Exception as exc:
        if require_spouse:
            # A commit must not guess "not a family": the expense would be stored without its
            # class and the wife's reimbursement debt silently lost (FR-B-07). Fail so the
            # client keeps the entry queued and retries.
            raise
        logger.warning("Could not load family context for Nafaqah classification: %s", exc)
        return result
    if not ctx.is_family:
        return result

    role = ctx.role_of(user_id)
    result.update({
        "household_mode": "family_nafaqah",
        "recorder_role": role,
        "wives": [{"id": w["id"], "display_name": w["display_name"]} for w in ctx.wives],
    })

    if role in ("wife", "husband"):
        if chosen is not None and not attribution_explicit:
            paid_by, beneficiary = attribution_for_class(role, None if chosen == OVERRIDE_NONE else chosen, beneficiary)
            result["paid_by"], result["beneficiary"] = paid_by, beneficiary
        nafaqah_class = classify_nafaqah(role, paid_by, beneficiary)
        if chosen is not None and (None if chosen == OVERRIDE_NONE else chosen) != nafaqah_class:
            raise InvalidNafaqahRequest(
                "nafaqah_class contradicts paid_by/beneficiary: a debt needs the wife to have paid for "
                "something shared, the allowance a purchase she paid for herself, 'none' the husband paying."
            )
    elif chosen not in (None, OVERRIDE_NONE):
        # D2: an admin may classify explicitly; any other member (e.g. an adult son) may not.
        if not ctx.can_classify(user_id):
            raise NafaqahClassificationForbidden(
                "Only the wife, the Nafaqah provider or a household admin can classify a family expense."
            )
        nafaqah_class = chosen
    else:
        # Other members have no spouse-relative vocabulary to classify with.
        nafaqah_class = None

    spouse_id: Optional[str] = None
    if role == "wife":
        if requested_spouse and requested_spouse != str(user_id):
            raise InvalidNafaqahRequest("A wife records Nafaqah expenses for herself only.")
        spouse_id = str(user_id)
    elif requested_spouse:
        if not ctx.is_wife(requested_spouse):
            raise InvalidNafaqahRequest("nafaqah_spouse_id is not a spouse member of this household.")
        spouse_id = requested_spouse
    elif len(ctx.wives) == 1:
        spouse_id = ctx.wives[0]["id"]

    if nafaqah_class and not spouse_id:
        if require_spouse:
            raise InvalidNafaqahRequest("This household has several wives: choose the wife (nafaqah_spouse_id).")
        result["nafaqah_spouse_required"] = True
    result["nafaqah_class"] = nafaqah_class
    result["nafaqah_spouse_id"] = spouse_id if nafaqah_class else None
    result["default_spouse_id"] = spouse_id
    return result


def resolve_wife_id(ctx: FamilyContext, requested: Optional[str], caller_id: Optional[str] = None) -> str:
    """The wife a request refers to: an explicit member id, an alias, or the only wife.

    A wife calling resolves herself only (review R3-01): no id, or an alias, is her; naming a co-wife
    is refused (NafaqahForbidden), for her ledger and her allowance alike."""
    req = _norm(requested)
    if caller_id and ctx.is_wife(caller_id):
        if req and req not in _WIFE_ALIASES and req != _norm(caller_id):
            raise NafaqahForbidden("A wife reads and asks for herself only.")
        return str(caller_id)
    if req and req not in _WIFE_ALIASES:
        if not ctx.is_wife(req):
            raise InvalidNafaqahRequest("wife_user_id is not a spouse member of this household.")
        return req
    if len(ctx.wives) == 1:
        return ctx.wives[0]["id"]
    if not ctx.wives:
        raise NoWifeInHousehold("This household has no wife member, so there is no allowance or reimbursement to record.")
    raise InvalidNafaqahRequest("This household has several wives: pass wife_user_id.")


def _require_family(ctx: FamilyContext) -> None:
    if not ctx.is_family:
        raise NotFamilyHousehold("Nafaqah ledgers apply to family households with a spouse member.")


def _require_wife(ctx: FamilyContext, wife_id: str) -> None:
    if not ctx.is_wife(wife_id):
        raise InvalidNafaqahRequest("The member is not a spouse member of this household.")


def _require_member(ctx: FamilyContext, actor_id: str) -> None:
    if not ctx.is_member(actor_id):
        raise NafaqahForbidden("Not a member of this household.")


def _is_spouse_member(ctx: FamilyContext, user_id: Optional[str]) -> bool:
    return ctx.is_member(user_id) and (
        ctx.members[str(user_id)].get("financial_role") == "spouse" or ctx.is_wife(user_id)
    )


def can_set_allowance(ctx: FamilyContext, actor_id: str, wife_id: Optional[str] = None) -> bool:
    """The husband (an admin or not) or a household admin; never a wife: not herself, and not a
    co-wife, even an admin (owner decision 2026-11-06). Mirrors ``public.set_member_allowance``."""
    if not ctx.is_member(actor_id) or (wife_id and str(actor_id) == str(wife_id)):
        return False
    if _is_spouse_member(ctx, actor_id):
        return False
    return str(actor_id) == ctx.husband_id or ctx.is_admin(actor_id)


def can_see_allowances(ctx: FamilyContext, actor_id: Optional[str]) -> bool:
    """Who reads every wife's allowance (owner decision 2026-11-06; mirrors
    ``public.nafaqah_may_see_allowances``): her husband (the provider while he is a current member
    who is not a wife) and a household admin who is not a wife. Never a wife (a co-wife, even an
    admin) and never an ordinary member."""
    if not ctx.is_member(actor_id) or _is_spouse_member(ctx, actor_id):
        return False
    return ctx.is_admin(actor_id) or str(actor_id) == ctx.ledger_husband_id


def can_view_allowance(ctx: FamilyContext, actor_id: Optional[str], wife_id: Optional[str]) -> bool:
    """Her allowance (allocated, spent, remaining) is read by her and by those who see allowances."""
    if not actor_id or not wife_id or not ctx.is_member(actor_id):
        return False
    return str(actor_id) == str(wife_id) or can_see_allowances(ctx, actor_id)


def require_allowance_reader(ctx: FamilyContext, actor_id: Optional[str]) -> None:
    """A caller who may read some wife's allowance: a wife (her own) or those who see allowances;
    anyone else is refused before any wife is named or looked up."""
    _require_member(ctx, actor_id)
    if not ctx.is_wife(actor_id) and not can_see_allowances(ctx, actor_id):
        raise NafaqahForbidden("Only she, her husband, or an admin who is not a wife, reads her allowance.")


# ─── Her personal purchases: who reads them (owner decision 2026-11-06) ─────────

def can_view_personal_purchase(ctx: FamilyContext, actor_id: Optional[str], row: Dict[str, Any]) -> bool:
    """Whether ``actor_id`` reads transaction ``row`` (mirrors the read policy of
    ``public.transactions``, migration 20261105001300 section 10d). A wife's personal purchase
    (``nafaqah_class`` 'wife_personal') is read by the same people as her allowance: she herself,
    her husband and a household admin who is not a wife. Every other transaction is read by every
    member (the routes check membership first). Every read this filters selects ``nafaqah_class``
    and ``nafaqah_spouse_id`` (test_wife_personal_privacy reads them from a strict table)."""
    if str(row.get("nafaqah_class") or "").strip().lower() != WIFE_PERSONAL:
        return True
    return can_view_allowance(ctx, actor_id, row.get("nafaqah_spouse_id"))


def visible_transactions(
    ctx: FamilyContext, actor_id: Optional[str], rows: Iterable[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """The rows of ``rows`` (transactions of ``ctx``'s household, read with the service role) that
    ``actor_id`` reads, in their order: what an answer to that member may show, list or sum."""
    return [row for row in rows if can_view_personal_purchase(ctx, actor_id, row)]


def transactions_visible_to(
    household_id: str, actor_id: Optional[str], rows: Iterable[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """``visible_transactions`` for a caller of ``household_id``. ``actor_id`` None is the server's
    own read (no member asks): every row."""
    rows = list(rows)
    if actor_id is None:
        return rows
    return visible_transactions(load_family_context(household_id), actor_id, rows)


def can_manage_wife_ledgers(ctx: FamilyContext, actor_id: Optional[str]) -> bool:
    """Who sees and settles every wife's repayment ledger and the former member records (review
    R3-01, owner decision 2026-11-06; mirrors ``public.nafaqah_may_manage_ledgers``): her husband;
    when he is gone, an admin of the household who is not a wife. Never a wife (a co-wife, even an
    admin) and never an ordinary member; no admin while the husband is there."""
    if not ctx.is_member(actor_id):
        return False
    if ctx.members[str(actor_id)].get("financial_role") == "spouse" or ctx.is_wife(actor_id):
        return False
    husband = ctx.ledger_husband_id
    if husband is None:
        return ctx.is_admin(actor_id)
    return str(actor_id) == husband


def can_view_wife_ledger(ctx: FamilyContext, actor_id: Optional[str], wife_id: Optional[str]) -> bool:
    """Her ledger (what is owed, advances, repayments, reversals, her requests, their outcomes,
    decline reasons and notes) is read by her and by those who manage it (review R3-01)."""
    if not actor_id or not wife_id or not ctx.is_member(actor_id):
        return False
    return str(actor_id) == str(wife_id) or can_manage_wife_ledgers(ctx, actor_id)


def require_ledger_reader(ctx: FamilyContext, actor_id: Optional[str]) -> None:
    """A caller who may read some wife's ledger: a wife (her own) or its managers; anyone else is
    refused before any wife is named or looked up (review R3-01)."""
    _require_member(ctx, actor_id)
    if not ctx.is_wife(actor_id) and not can_manage_wife_ledgers(ctx, actor_id):
        raise NafaqahForbidden("Only she, her husband, or an admin when he is gone, reads her ledger.")


def can_record_reimbursement(ctx: FamilyContext, actor_id: str, wife_id: Optional[str] = None) -> bool:
    """Her husband; when he is gone, a household admin who is not a wife (owner decisions
    2026-11-06, reviews R1-01 and R3-01): never the wife the repayment is for, who asks instead
    (``can_request_reimbursement``), never a co-wife, even an admin, and no admin while the husband
    is there. The same people approve and decline. Who reverses follows the account
    (``can_reverse_repayment``). Mirrors ``public.nafaqah_may_repay``."""
    if wife_id is not None and str(actor_id) == str(wife_id):
        return False
    return can_manage_wife_ledgers(ctx, actor_id)


def can_reverse_repayment(ctx: FamilyContext, actor_id: Optional[str], account: Optional[Dict[str, Any]]) -> bool:
    """Who reverses a repayment (or a former member's payment) follows the account it left (review
    R1-07): its owner while he is a member and not a wife, whatever his role now; a shared pool's,
    the husband if he is an admin, or an admin who is not a wife when he is gone (review R3-01).
    The database checks the same under its locks."""
    if not ctx.is_member(actor_id) or ctx.is_wife(actor_id) or not _account_usable_by(ctx, account, actor_id):
        return False
    if (account or {}).get("is_shared_pool"):
        return can_manage_wife_ledgers(ctx, actor_id)
    return True


def can_request_reimbursement(ctx: FamilyContext, actor_id: str, wife_id: Optional[str] = None) -> bool:
    """The wife herself: she marks what she received, and the husband or an admin approves it."""
    return ctx.is_wife(actor_id) and (wife_id is None or str(actor_id) == str(wife_id))


# ─── Cycle ────────────────────────────────────────────────────────────────────

def current_cycle_key(household_id: str) -> str:
    """Current salary cycle (payday → day before next payday, Riyadh dates) of the household."""
    from salary_cycle import get_cycle_for_date
    from utils import riyadh_today

    return get_cycle_for_date(riyadh_today(), payday_day=get_household_payday(household_id))["cycle_key"]


def _resolve_cycle(ctx: FamilyContext, cycle_key: Optional[str]) -> str:
    key = (cycle_key or "").strip() or current_cycle_key(ctx.household_id)
    if not _CYCLE_KEY_RE.match(key):
        raise InvalidNafaqahRequest(f"Invalid cycle_key {key!r}; expected YYYY-MM.")
    return key


# ─── Database error mapping ───────────────────────────────────────────────────

LEDGER_WOULD_BE_OVERPAID = "ledger_would_be_overpaid"


def is_ledger_overpaid_error(exc: Exception) -> bool:
    """The guard trigger of migration 20261020800000 refused a transaction edit/delete."""
    fields = db_error_fields(exc)
    return fields["hint"] == LEDGER_WOULD_BE_OVERPAID or (
        fields["code"] == "22023" and "ledger overpaid" in fields["message"]
    )


def _detail_amount(details: str) -> Optional[float]:
    """The SAR amount a refusal puts in its DETAIL (what is owed, or what can still be asked)."""
    try:
        return halalas_to_sar(to_halalas(Decimal(str(details).strip())))
    except (InvalidOperation, InvalidNafaqahRequest, ValueError):
        return None


# The constraints that keep a request key to one operation (migrations 20261105001200 and
# 20261105001300, review R2-01).
REQUEST_KEY_CONSTRAINTS = (
    "nafaqah_request_keys_pkey",
    "uq_spouse_reimbursements_request",
    "uq_former_member_debt_events_request",
    "uq_spouse_reimbursement_requests_key",
)


def _map_db_error(exc: Exception) -> Exception:
    """
    Map a refusal of the Nafaqah RPCs to the service's errors. Every RAISE in migration
    20261020300000 sets an SQLSTATE (42501 forbidden, 22023 invalid, 23514/23503 constraint) and
    the overpayment refusal also sets HINT 'overpayment'; PostgREST returns them as the JSON
    ``code`` / ``hint`` / ``message`` that postgrest-py's APIError exposes (read by
    ``db_error_fields`` from whatever shape the exception arrives in).
    """
    fields = db_error_fields(exc)
    message, code, hint = fields["message"], fields["code"], fields["hint"]
    guard = account_deletion_guard_error(exc)
    if guard is not None:
        return AccountPendingDeletion(str(guard), guard.code)
    # Migration 20261105001300: every repayment moves money; the wife asks; reversals.
    details = fields.get("details", "")
    if hint == "app_update_required":
        return AppUpdateRequired("Repayments are now paid from an account: update the app.")
    if hint == "wife_must_request":
        return WifeMustRequest("The wife asks for a repayment; the husband or an admin records it.")
    if hint == "request_not_found":
        return RequestNotFound("No such request in this household.")
    if hint == "request_not_pending":
        return RequestNotPending("This request was already answered.")
    if hint == "request_exceeds_outstanding":
        return RequestExceedsOutstanding("The request is more than is owed now.", outstanding=_detail_amount(details))
    if hint == "pending_exceeds_outstanding":
        return PendingExceedsOutstanding("Pending requests would be more than is owed.", available=_detail_amount(details))
    if hint in ("reimbursement_not_found", "payment_not_found"):
        return RecordNotFound("No such repayment in this household.", hint)
    if hint in REVERSAL_REFUSALS:
        return ReversalRefused("This repayment cannot be reversed.", hint)
    if hint in ("account_required", "invalid_reason", "request_key_required"):
        return InvalidCodedRequest("The database rejected the request.", hint)
    if hint == "account_unavailable":
        return AccountUnavailable("This account cannot be used in this household.")
    if hint == "account_forbidden":
        return AccountForbidden("You cannot pay from this account.")
    if hint == "insufficient_funds":
        return InsufficientFunds("This account does not hold the amount.")
    # Migration 20261105001200 (the former member record): every refusal carries a HINT.
    if hint == "debt_not_found":
        return DebtNotFound("No such record in this household.")
    if hint == "debt_closed":
        return DebtClosed("This record is already settled or waived.")
    if hint == "request_key_reused":
        return RequestKeyReused("This request was already used for a different action.")
    # Two calls with one key at once: the database answers request_key_reused, but a raw unique
    # violation of a key constraint is the same answer, never a 500 (review R2-07).
    if code == "23505" and any(c in message or c in details for c in REQUEST_KEY_CONSTRAINTS):
        return RequestKeyReused("This request was already used for a different action.")
    if hint in ("invalid_amount", "invalid_payment_method", "request_key_required"):
        return InvalidNafaqahRequest("The database rejected the request.")
    if hint == "forbidden":
        return NafaqahForbidden("Not allowed for this household member.")
    if hint == "overpayment" or "exceeds the outstanding balance" in message:
        return OverpaymentError("Reimbursement exceeds the outstanding balance.", outstanding=_detail_amount(details))
    if hint == LEDGER_WOULD_BE_OVERPAID or "ledger overpaid" in message:
        return LedgerWouldBeOverpaid(
            "This change would leave the wife's reimbursement ledger overpaid: the husband already repaid more."
        )
    if hint == "no_nafaqah_provider":
        return NoProviderError("This family has no Nafaqah provider: a household admin must choose one.")
    if hint == "provider_is_spouse":
        return InvalidNafaqahRequest("A wife cannot be the Nafaqah provider.")
    if hint == "nafaqah_class_not_allowed":
        return NafaqahClassificationForbidden(
            "Only the wife, the Nafaqah provider or a household admin can classify a family expense."
        )
    if hint == "not_family_household":
        return NotFamilyHousehold("Nafaqah applies to family households only.")
    if code == "P0002":
        return InvalidNafaqahRequest("That user is not a member of this household.")
    if code == "42501" or message.startswith("Forbidden"):
        return NafaqahForbidden("Not allowed for this household member.")
    if code in ("22023", "23514", "23503"):
        return InvalidNafaqahRequest("The database rejected the request.")
    return exc


# ─── Reimbursement ledger (rule 2) ────────────────────────────────────────────
#
# Owner decisions 2026-11-06 (migration 20261105001300):
#   * Every repayment leaves an account the payer picks (his own, or a shared pool when he is an
#     admin) as one transfer to no account: her account is never credited, no budget moves. A call
#     without an account comes from an app that predates this and is refused (AppUpdateRequired).
#   * The wife asks ("I received X"): a pending request that moves nothing and lowers nothing owed.
#     The husband or an admin approves it with an account (the normal repayment of exactly that
#     amount) or declines it; she can cancel it while it is pending.
#   * Nothing is deleted or edited: a correction is a reversal, which returns the money to the
#     original account and adds the amount back to what is owed.
# What is owed = advances - payments + reversals. Pending requests never count.

KIND_PAYMENT = "payment"
KIND_REVERSAL = "reversal"


# PostgREST answers at most its max-rows setting per request (1000 on Supabase by default) and says
# nothing when it cut an answer short. Every ledger read whose rows are summed or listed in full
# goes through these two: the rows page by page in a stable order, and a long list of ids in
# chunks (each one short enough for a URL, each one paged too).
PAGE_ROWS = 1000
IN_CHUNK = 100


def all_rows(make_query: Callable[[], Any], order_by: str = "id") -> List[Dict[str, Any]]:
    """Every row of a select. ``make_query`` builds it afresh for each page (filters, no order or
    range); pages run in ``order_by`` (a unique column), each starting where the rows so far end,
    until one comes back empty, so a server capping pages below PAGE_ROWS still gives them all."""
    rows: List[Dict[str, Any]] = []
    seen = set()
    while True:
        page = (make_query().order(order_by).range(len(rows), len(rows) + PAGE_ROWS - 1).execute()).data or []
        fresh = [r for r in page if r.get(order_by) not in seen]
        if not fresh:
            return rows
        seen.update(r.get(order_by) for r in fresh)
        rows.extend(fresh)


def rows_in(client, table: str, columns: str, column: str, values: Iterable[Any],
            order_by: str = "id") -> List[Dict[str, Any]]:
    """Every row of ``table`` whose ``column`` is one of ``values``, IN_CHUNK values per request."""
    ids = sorted({str(v) for v in values if v})
    out: List[Dict[str, Any]] = []
    for i in range(0, len(ids), IN_CHUNK):
        chunk = ids[i:i + IN_CHUNK]
        out += all_rows(lambda: client.table(table).select(columns).in_(column, chunk), order_by)
    return out


def _signed_repayment(row: Dict[str, Any]) -> Decimal:
    """A ledger row's effect on what was repaid: a payment adds, a reversal takes it back."""
    amount = _decimal(row.get("amount"))
    return -amount if str(row.get("kind") or KIND_PAYMENT) == KIND_REVERSAL else amount


def _transfers(client, transfer_ids: Iterable[Any]) -> Dict[str, Dict[str, Optional[str]]]:
    """{transfer id: {"from": account, "to": account}} for the rows that moved money."""
    rows = rows_in(client, "account_transfers", "id, from_account_id, to_account_id", "id", transfer_ids)
    return {
        str(r.get("id")): {
            "from": str(r["from_account_id"]) if r.get("from_account_id") else None,
            "to": str(r["to_account_id"]) if r.get("to_account_id") else None,
        }
        for r in rows
    }


def _accounts(client, account_ids: Iterable[Any]) -> Dict[str, Dict[str, Any]]:
    rows = rows_in(client, "accounts", "id, household_id, owner_user_id, is_shared_pool, is_archived, currency",
                   "id", account_ids)
    return {str(r.get("id")): r for r in rows}


def _account_usable_by(ctx: FamilyContext, account: Optional[Dict[str, Any]], actor_id: Optional[str]) -> bool:
    """The account rules of the RPCs: in this household, not archived, in SAR; a shared pool only by
    an admin, a personal account only by its owner; never by a wife, who pays nothing (review R1-01)."""
    if not account or not actor_id or ctx.is_wife(actor_id):
        return False
    if str(account.get("household_id")) != ctx.household_id or account.get("is_archived"):
        return False
    if str(account.get("currency") or "SAR") != "SAR":
        return False
    if account.get("is_shared_pool"):
        return ctx.is_admin(actor_id)
    return str(account.get("owner_user_id") or "") == str(actor_id)


def _requests_of(client, ctx: FamilyContext, wife_id: str) -> List[Dict[str, Any]]:
    """Her requests, newest first, each with its outcome ('pending' while it has none)."""
    rows = all_rows(lambda: (
        client.table("spouse_reimbursement_requests")
        .select("id, amount, payment_method, created_at")
        .eq("household_id", ctx.household_id)
        .eq("wife_user_id", wife_id)
    ))
    outcomes = {
        str(o.get("request_id")): o
        for o in rows_in(client, "spouse_reimbursement_request_outcomes",
                         "request_id, outcome, reason, reimbursement_id, created_at", "request_id",
                         [r.get("id") for r in rows], order_by="request_id")
    }
    out = []
    for r in rows:
        o = outcomes.get(str(r.get("id")))
        out.append({
            "id": r.get("id"),
            "amount": halalas_to_sar(to_halalas(r.get("amount"))),
            "payment_method": r.get("payment_method"),
            "created_at": r.get("created_at"),
            "status": (o or {}).get("outcome") or "pending",
            # Only a decline carries a reason; who decided is not shown.
            "reason": (o or {}).get("reason"),
            "decided_at": (o or {}).get("created_at"),
            "reimbursement_id": (o or {}).get("reimbursement_id"),
        })
    out.sort(key=lambda q: str(q.get("created_at") or ""), reverse=True)
    return out


def _pending_totals(requests: List[Dict[str, Any]]) -> Dict[str, Any]:
    pending = [to_halalas(q["amount"]) for q in requests if q.get("status") == "pending"]
    return {"pending_requested": halalas_to_sar(sum(pending)), "pending_count": len(pending)}


def get_reimbursement_ledger(ctx: FamilyContext, wife_id: str, caller_id: Optional[str] = None) -> Dict[str, Any]:
    """Outstanding balance, the history of advances, repayments and reversals (newest first), and
    her requests. ``caller_id`` is who asks: only she or a manager of the ledgers reads it (review
    R3-01: NafaqahForbidden otherwise), and it decides ``can_reverse`` on each repayment. Without a
    caller it is the server's own read (the settlement totals, an answer's stand-in figures)."""
    _require_family(ctx)
    _require_wife(ctx, wife_id)
    if caller_id is not None and not can_view_wife_ledger(ctx, caller_id, wife_id):
        raise NafaqahForbidden("Only she, her husband, or an admin when he is gone, reads her ledger.")
    client = get_client()
    # Every row, page by page: what is owed is their sum (PostgREST caps each answer).
    advances = all_rows(lambda: (
        client.table("transactions")
        .select("id, amount, merchant, category_code, timestamp, cycle_key")
        .eq("household_id", ctx.household_id)
        .eq("nafaqah_spouse_id", wife_id)
        .eq("nafaqah_class", WIFE_REIMBURSABLE)
    ))
    # Every column: transfer_id, kind and reverses_id exist once 20261105001300 has run.
    repayments = all_rows(lambda: (
        client.table("spouse_reimbursements")
        .select("*")
        .eq("household_id", ctx.household_id)
        .eq("wife_user_id", wife_id)
    ))
    transfers = _transfers(client, [r.get("transfer_id") for r in repayments])
    reversed_by = {
        str(r.get("reverses_id")): r.get("id") for r in repayments if str(r.get("kind") or KIND_PAYMENT) == KIND_REVERSAL
    }
    paid_from = {
        str(r.get("id")): (transfers.get(str(r.get("transfer_id"))) or {}).get("from")
        for r in repayments if r.get("transfer_id") and str(r.get("kind") or KIND_PAYMENT) == KIND_PAYMENT
    }
    # Who may reverse follows the account it left (review R1-07), never a wife.
    may_reverse = bool(caller_id) and ctx.is_member(caller_id) and not ctx.is_wife(caller_id)
    accounts = _accounts(client, paid_from.values()) if may_reverse else {}

    def repayment_entry(r: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(r.get("kind") or KIND_PAYMENT)
        moved = transfers.get(str(r.get("transfer_id"))) if r.get("transfer_id") else None
        account = (moved or {}).get("to" if kind == KIND_REVERSAL else "from")
        reversal = reversed_by.get(str(r.get("id")))
        return {
            "type": "reimbursement",
            "kind": kind,
            "id": r.get("id"),
            "amount": halalas_to_sar(to_halalas(r.get("amount"))),
            "payment_method": r.get("payment_method"),
            "notes": r.get("notes"),
            "recorded_by": r.get("recorded_by"),
            # Who actually paid (review R1-08): the owner of the account it left, or the admin who
            # paid from a pool; for a reversal, the payer of the repayment it reverses.
            "paid_by_user_id": r.get("paid_by_user_id"),
            "timestamp": r.get("created_at"),
            # Whether it moved money in the app, and through which account (the app names it only
            # when the viewer can see that account).
            "moved_balance": bool(r.get("transfer_id")),
            "account_id": account,
            "reverses_id": r.get("reverses_id"),
            "reversed": reversal is not None,
            "reversed_by_id": reversal,
            "can_reverse": (
                may_reverse and kind == KIND_PAYMENT and reversal is None and bool(account)
                and can_reverse_repayment(ctx, caller_id, accounts.get(str(account)))
            ),
        }

    history: List[Dict[str, Any]] = [
        {
            "type": "advance",
            "id": a.get("id"),
            "amount": halalas_to_sar(to_halalas(a.get("amount"))),
            "merchant": a.get("merchant"),
            "category_code": a.get("category_code"),
            "cycle_key": a.get("cycle_key"),
            "timestamp": a.get("timestamp"),
        }
        for a in advances
    ] + [repayment_entry(r) for r in repayments]
    history.sort(key=lambda h: str(h.get("timestamp") or ""), reverse=True)

    requests = _requests_of(client, ctx, wife_id)
    return {
        "household_id": ctx.household_id,
        "wife_user_id": wife_id,
        "husband_user_id": ctx.husband_id,
        "balance": {
            **compute_reimbursement_balance(
                [a.get("amount") for a in advances], [_signed_repayment(r) for r in repayments]
            ),
            **_pending_totals(requests),
        },
        "history": history,
        "requests": requests,
    }


def _require_payer(ctx: FamilyContext, actor_id: str, wife_id: str) -> None:
    """Her husband, or an admin who is not a wife when he is gone; the wife herself is told to ask
    instead, and a co-wife is refused (reviews R1-01, R3-01)."""
    _require_member(ctx, actor_id)
    if str(actor_id) == str(wife_id):
        raise WifeMustRequest("The wife asks for a repayment; her husband records it.")
    if not can_record_reimbursement(ctx, actor_id, wife_id):
        raise NafaqahForbidden("Only her husband, or an admin who is not a wife when he is gone, can do this.")


def _require_key(request_key: Optional[str]) -> None:
    if not request_key:
        raise InvalidCodedRequest("A request key is required to move money.", "request_key_required")


def _repayment_answer(ctx: FamilyContext, wife_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    """What the app needs after a repayment, an approval or a reversal (a replay answers with what
    the first call stored)."""
    return {
        "status": "success",
        "reimbursement_id": data.get("reimbursement_id"),
        "request_id": data.get("request_id"),
        "kind": data.get("kind") or KIND_PAYMENT,
        "reverses_id": data.get("reverses_id"),
        "household_id": ctx.household_id,
        "wife_user_id": wife_id,
        # Who actually paid, as the database recorded it (review R1-08); never assumed.
        "paid_by_user_id": data.get("paid_by_user_id"),
        "amount": halalas_to_sar(to_halalas(data.get("amount"))),
        "payment_method": data.get("payment_method"),
        "outstanding_before": halalas_to_sar(to_halalas(data.get("outstanding_before"))),
        "outstanding_after": halalas_to_sar(to_halalas(data.get("outstanding_after"))),
        "replayed": bool(data.get("replayed")),
        "account_id": str(data["account_id"]) if data.get("account_id") else None,
        "balance_moved": bool(data.get("account_id")),
    }


def record_reimbursement(
    ctx: FamilyContext,
    actor_id: str,
    wife_id: str,
    amount: Any,
    payment_method: str = "cash",
    notes: Optional[str] = None,
    account_id: Optional[str] = None,
    request_key: Optional[str] = None,
) -> Dict[str, Any]:
    """
    The husband (or an admin) records a partial or full repayment, paid from ``account_id``: the
    database debits it by the amount as one transfer to no account (her account is never credited)
    and refuses an overpayment, an account he may not use and one that does not hold the amount.
    ``request_key`` is the client's idempotency key: the same key again is answered as the first
    time. Without an account the call comes from an app that predates this: AppUpdateRequired.
    """
    _require_family(ctx)
    _require_member(ctx, actor_id)
    _require_wife(ctx, wife_id)
    if not account_id:
        raise AppUpdateRequired("Repayments are now paid from an account: update the app.")
    _require_payer(ctx, actor_id, wife_id)

    value = parse_sar_amount(amount, allow_zero=False)
    method = _norm(payment_method) or "cash"
    if method not in PAYMENT_METHODS:
        raise InvalidNafaqahRequest(f"Unsupported payment method {payment_method!r}.")
    _require_key(request_key)

    data = _rpc_mapped("record_spouse_reimbursement", {
        "p_household_id": ctx.household_id,
        "p_wife_user_id": wife_id,
        # Exact decimal text ("123.40"): PostgREST casts it to the numeric parameter.
        "p_amount": format(value, "f"),
        "p_payment_method": method,
        "p_notes": (notes or "").strip()[:500] or None,
        "p_actor_user_id": actor_id,
        "p_account_id": account_id,
        "p_request_key": request_key,
    })
    data = data if isinstance(data, dict) else {}
    if "amount" not in data:
        data = {**data, "amount": format(value, "f"), "payment_method": method}
    if "outstanding_after" not in data:
        # A stand-in that does not say: what is owed now, read back.
        after = get_reimbursement_ledger(ctx, wife_id)["balance"]["outstanding"]
        data = {**data, "outstanding_after": after,
                "outstanding_before": halalas_to_sar(to_halalas(after) + to_halalas(value))}
    if "account_id" not in data:
        data = {**data, "account_id": account_id}
    return _repayment_answer(ctx, wife_id, data)


# ─── The wife's requests (migration 20261105001300) ────────────────────────────

def _request_row(ctx: FamilyContext, request_id: str) -> Dict[str, Any]:
    row = first_row(
        get_client()
        .table("spouse_reimbursement_requests")
        .select("id, household_id, wife_user_id, amount, payment_method")
        .eq("id", request_id)
        .eq("household_id", ctx.household_id)
    )
    if not row:
        raise RequestNotFound("No such request in this household.")
    return row


def create_reimbursement_request(
    ctx: FamilyContext, actor_id: str, amount: Any, payment_method: str, request_key: str
) -> Dict[str, Any]:
    """She marks "I received X": a pending request. Nothing moves and nothing owed changes until
    the husband or an admin approves it. Pending requests together never exceed what is owed."""
    _require_family(ctx)
    _require_member(ctx, actor_id)
    if not can_request_reimbursement(ctx, actor_id):
        raise NafaqahForbidden("Only the wife asks for a repayment to be recorded.")
    value = parse_sar_amount(amount, allow_zero=False)
    method = _norm(payment_method) or "cash"
    if method not in PAYMENT_METHODS:
        raise InvalidNafaqahRequest(f"Unsupported payment method {payment_method!r}.")
    _require_key(request_key)
    data = _rpc_mapped("request_spouse_reimbursement", {
        "p_household_id": ctx.household_id,
        "p_amount": format(value, "f"),
        "p_payment_method": method,
        "p_request_key": request_key,
        "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    return {
        "status": "success",
        "request_id": data.get("request_id"),
        "request_status": data.get("status") or "pending",
        "replayed": bool(data.get("replayed")),
        "amount": halalas_to_sar(to_halalas(data.get("amount", value))),
        "payment_method": data.get("payment_method") or method,
        "outstanding": halalas_to_sar(to_halalas(data.get("outstanding"))),
    }


def cancel_reimbursement_request(ctx: FamilyContext, actor_id: str, request_id: str) -> Dict[str, Any]:
    """She cancels her own pending request; nothing moves."""
    _require_family(ctx)
    _require_member(ctx, actor_id)
    row = _request_row(ctx, request_id)
    if str(row.get("wife_user_id")) != str(actor_id):
        raise NafaqahForbidden("Only she cancels her request.")
    data = _rpc_mapped("cancel_spouse_reimbursement_request", {
        "p_household_id": ctx.household_id, "p_request_id": request_id, "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    return {"status": "success", "request_id": request_id, "outcome": data.get("outcome") or "cancelled",
            "replayed": bool(data.get("replayed"))}


def decline_reimbursement_request(
    ctx: FamilyContext, actor_id: str, request_id: str, reason: Optional[str] = None
) -> Dict[str, Any]:
    """The husband or an admin declines a pending request, with an optional short reason; nothing moves."""
    _require_family(ctx)
    row = _request_row(ctx, request_id)
    _require_payer(ctx, actor_id, str(row.get("wife_user_id")))
    clean = (reason or "").strip() or None
    # Unicode code points (len), as the database's char_length and the app's runes count them.
    if clean and len(clean) > 200:
        raise InvalidCodedRequest("A reason is at most 200 characters.", "invalid_reason")
    data = _rpc_mapped("decline_spouse_reimbursement_request", {
        "p_household_id": ctx.household_id, "p_request_id": request_id, "p_reason": clean, "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    return {"status": "success", "request_id": request_id, "outcome": data.get("outcome") or "declined",
            "reason": data.get("reason", clean), "replayed": bool(data.get("replayed"))}


def approve_reimbursement_request(
    ctx: FamilyContext, actor_id: str, request_id: str, account_id: Optional[str], request_key: Optional[str]
) -> Dict[str, Any]:
    """The husband or an admin approves her request from ``account_id``: the normal repayment of
    exactly the requested amount (debit, idempotent, overpayment refused), linked to the request.
    The database re-checks what is owed at that moment (RequestExceedsOutstanding)."""
    _require_family(ctx)
    row = _request_row(ctx, request_id)
    wife_id = str(row.get("wife_user_id"))
    if str(actor_id) == wife_id:
        raise NafaqahForbidden("She does not approve her own request.")
    _require_payer(ctx, actor_id, wife_id)
    if not account_id:
        raise InvalidCodedRequest("An approval is paid from an account.", "account_required")
    _require_key(request_key)
    data = _rpc_mapped("approve_spouse_reimbursement_request", {
        "p_household_id": ctx.household_id,
        "p_request_id": request_id,
        "p_account_id": account_id,
        "p_request_key": request_key,
        "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    data.setdefault("request_id", request_id)
    return _repayment_answer(ctx, wife_id, data)


def _require_reverser(ctx: FamilyContext, actor_id: str, transfer_id: Any, *, reversal: bool = False) -> None:
    """Never a wife (review R1-01). Otherwise who reverses follows the account the payment left
    (review R1-07): an early, clear refusal for one the caller may not use. A row with no transfer,
    or a reversal, is left to the database, which names why it cannot be reversed."""
    _require_member(ctx, actor_id)
    if ctx.is_wife(actor_id):
        raise NafaqahForbidden("A wife does not reverse a repayment.")
    if not transfer_id or reversal:
        return
    client = get_client()
    source = (_transfers(client, [transfer_id]).get(str(transfer_id)) or {}).get("from")
    if not source:
        return
    account = _accounts(client, [source]).get(str(source))
    if account and str(account.get("household_id")) == ctx.household_id and not account.get("is_archived") \
            and not can_reverse_repayment(ctx, actor_id, account):
        raise AccountForbidden("You cannot take money back into this account.")


def reverse_reimbursement(ctx: FamilyContext, actor_id: str, reimbursement_id: str, request_key: Optional[str]) -> Dict[str, Any]:
    """Reverses a tracked repayment in full: the money goes back to the account it left and the
    amount back to what is owed. The original stays, marked reversed. Who reverses follows the
    account (review R1-07): its owner while he is a member and not a wife, whatever his role now; a
    pool's repayment, any admin who is not a wife. Once per repayment."""
    _require_family(ctx)
    row = first_row(
        get_client()
        .table("spouse_reimbursements")
        .select("id, household_id, wife_user_id, transfer_id, kind")
        .eq("id", reimbursement_id)
        .eq("household_id", ctx.household_id)
    )
    if not row:
        raise RecordNotFound("No such repayment in this household.", "reimbursement_not_found")
    wife_id = str(row.get("wife_user_id"))
    _require_reverser(ctx, actor_id, row.get("transfer_id"), reversal=str(row.get("kind") or KIND_PAYMENT) == KIND_REVERSAL)
    _require_key(request_key)
    data = _rpc_mapped("reverse_spouse_reimbursement", {
        "p_household_id": ctx.household_id,
        "p_reimbursement_id": reimbursement_id,
        "p_request_key": request_key,
        "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    data.setdefault("kind", KIND_REVERSAL)
    data.setdefault("reverses_id", reimbursement_id)
    return _repayment_answer(ctx, wife_id, data)


# ─── A former member's record (migration 20261105001200) ───────────────────────
#
# When a wife deletes her account, the purge keeps one anonymised record per household of what
# the husband still owed her. It is closed by payments (an amount, a payment method and the
# account it is paid from, as record_reimbursement takes them: his account goes down, no budget or
# transaction moves; since 20261105001300 there is no payment without an account) or by her
# waiver, which moves nothing (إبراء). A tracked payment is corrected by a reversal: the money
# goes back to its account and the amount back to what remains, reopening a settled record (not
# after her waiver). She is gone, so there are no requests. Everything goes through SECURITY
# DEFINER RPCs with the verified caller; the checks here only answer early and clearly.


def can_manage_former_member_debts(ctx: FamilyContext, actor_id: Optional[str]) -> bool:
    """Who sees and closes a former member's record (review R3-01): the husband it is owed by; when
    he is gone, an admin who is not a wife. Never a wife (review R1-01), even an admin, nor an
    ordinary member, nor an admin while he is there."""
    return can_manage_wife_ledgers(ctx, actor_id)


def _debt_view(row: Dict[str, Any], events: List[Dict[str, Any]]) -> Dict[str, Any]:
    original_h = to_halalas(row.get("original_amount"))
    paid_h = to_halalas(row.get("paid_amount"))
    ordered = sorted(events, key=lambda e: (str(e.get("created_at") or ""), -to_halalas(e.get("remaining_after"))))
    reversed_by = {str(e.get("reverses_event_id")) for e in events if e.get("kind") == KIND_REVERSAL}
    return {
        "id": row.get("id"),
        "original_amount": halalas_to_sar(original_h),
        "paid_amount": halalas_to_sar(paid_h),
        "remaining": halalas_to_sar(original_h - paid_h),
        "status": row.get("status"),
        "created_at": row.get("created_at"),
        "closed_at": row.get("closed_at"),
        # Who recorded each step is not shown: the record names no one.
        "events": [
            {
                "id": e.get("id"),
                "kind": e.get("kind"),
                "amount": halalas_to_sar(to_halalas(e.get("amount"))),
                "payment_method": e.get("payment_method"),
                "remaining_after": halalas_to_sar(to_halalas(e.get("remaining_after"))),
                "created_at": e.get("created_at"),
                "moved_balance": bool(e.get("transfer_id")),
                "account_id": e.get("account_id"),
                "reverses_event_id": e.get("reverses_event_id"),
                "reversed": str(e.get("id")) in reversed_by,
                # Who may reverse it now: a tracked payment not yet reversed, of a record she has
                # not waived, from an account the caller may use.
                "can_reverse": bool(e.get("can_reverse")) and str(e.get("id")) not in reversed_by
                and row.get("status") != "waived",
            }
            for e in ordered
        ],
    }


def list_former_member_debts(ctx: FamilyContext, caller_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """The household's records, newest first, each with its payments, reversals and waiver, oldest
    first. ``caller_id`` is who asks: only the managers read them (review R3-01; anyone else gets
    none), and it decides ``can_reverse`` on each payment."""
    if caller_id is not None and not can_manage_former_member_debts(ctx, caller_id):
        return []
    client = get_client()
    rows = all_rows(lambda: (
        client.table("former_member_debts")
        .select("id, original_amount, paid_amount, status, created_at, closed_at")
        .eq("household_id", ctx.household_id)
    ))
    if not rows:
        return []
    # Every column: transfer_id and reverses_event_id exist once 20261105001300 has run.
    events = rows_in(client, "former_member_debt_events", "*", "debt_id", [r.get("id") for r in rows])
    transfers = _transfers(client, [e.get("transfer_id") for e in events])
    # Who may reverse follows the account the payment left (review R1-07), never a wife.
    may_reverse = bool(caller_id) and ctx.is_member(caller_id) and not ctx.is_wife(caller_id)
    sources = [(transfers.get(str(e.get("transfer_id"))) or {}).get("from") for e in events if e.get("kind") == "payment"]
    accounts = _accounts(client, sources) if may_reverse else {}
    by_debt: Dict[str, List[Dict[str, Any]]] = {}
    for e in events:
        moved = transfers.get(str(e.get("transfer_id"))) if e.get("transfer_id") else None
        account = (moved or {}).get("to" if e.get("kind") == KIND_REVERSAL else "from")
        e = {
            **e,
            "account_id": account,
            "can_reverse": may_reverse and e.get("kind") == "payment" and bool(account)
            and can_reverse_repayment(ctx, caller_id, accounts.get(str(account))),
        }
        by_debt.setdefault(str(e.get("debt_id")), []).append(e)
    rows.sort(key=lambda r: str(r.get("created_at") or ""), reverse=True)
    return [_debt_view(r, by_debt.get(str(r.get("id")), [])) for r in rows]


def _rpc_mapped(name: str, params: Dict[str, Any]) -> Any:
    try:
        return get_client().rpc(name, params).execute().data
    except Exception as exc:
        mapped = _map_db_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc


def get_deletion_notices(ctx: FamilyContext, caller_id: str) -> Dict[str, Dict[str, Any]]:
    """{wife id: {scheduled_for, outstanding}} for the creditor of the household (the husband, or
    the admins when it has none); empty for anyone else. The database decides who that is."""
    data = _rpc_mapped(
        "get_former_member_debt_deletion_notices",
        {"p_household_id": ctx.household_id, "p_actor_user_id": caller_id},
    )
    out: Dict[str, Dict[str, Any]] = {}
    for row in data if isinstance(data, list) else []:
        wife = str(row.get("wife_user_id") or "")
        if wife:
            out[wife] = {
                "scheduled_for": row.get("scheduled_for"),
                "outstanding": halalas_to_sar(to_halalas(row.get("outstanding"))),
            }
    return out


def _former_member_debt(ctx: FamilyContext, debt_id: str) -> Dict[str, Any]:
    row = first_row(
        get_client()
        .table("former_member_debts")
        .select("id, household_id, original_amount, paid_amount, status")
        .eq("id", debt_id)
        .eq("household_id", ctx.household_id)
    )
    if not row:
        raise DebtNotFound("No such record in this household.")
    return row


def _require_debt_manager(ctx: FamilyContext, actor_id: str) -> None:
    _require_member(ctx, actor_id)
    if not can_manage_former_member_debts(ctx, actor_id):
        raise NafaqahForbidden("Only the husband, or an admin who is not a wife when he is gone, can close this record.")


def record_former_member_debt_payment(
    ctx: FamilyContext,
    actor_id: str,
    debt_id: str,
    amount: Any,
    payment_method: str,
    request_key: str,
    account_id: Optional[str] = None,
) -> Dict[str, Any]:
    """A partial or full payment of a former member's record; never more than remains.

    ``account_id`` (migration 20261105001300): the account it is paid from, debited by the amount;
    she is gone, so nothing is credited. Without one the caller is an app that predates this:
    AppUpdateRequired, and nothing is recorded."""
    _require_family(ctx)
    _require_debt_manager(ctx, actor_id)
    if not account_id:
        raise AppUpdateRequired("Payments are now paid from an account: update the app.")
    value = parse_sar_amount(amount, allow_zero=False)
    method = _norm(payment_method) or "cash"
    if method not in PAYMENT_METHODS:
        raise InvalidNafaqahRequest(f"Unsupported payment method {payment_method!r}.")

    # No look at the record first (review R1-02): a retry of a payment that went through finds it
    # settled, or with less remaining than this payment, and must still get the first answer. The
    # database answers a replay before it checks the record is open, held and big enough
    # (debt_closed, overpayment with what remains, debt_not_found).
    data = _rpc_mapped("record_former_member_debt_payment", {
        "p_household_id": ctx.household_id,
        "p_debt_id": debt_id,
        # Exact decimal text ("123.40"): PostgREST casts it to the numeric parameter.
        "p_amount": format(value, "f"),
        "p_payment_method": method,
        "p_request_key": request_key,
        "p_actor_user_id": actor_id,
        "p_account_id": account_id,
    })
    data = data if isinstance(data, dict) else {}
    paid_from = data.get("account_id", account_id)
    return {
        "status": data.get("status"),
        "replayed": bool(data.get("replayed")),
        "debt_id": data.get("debt_id") or debt_id,
        "event_id": data.get("event_id"),
        "amount": halalas_to_sar(to_halalas(data.get("amount", value))),
        "payment_method": data.get("payment_method") or method,
        "remaining": halalas_to_sar(to_halalas(data.get("remaining"))),
        "account_id": str(paid_from) if paid_from else None,
        "balance_moved": bool(paid_from),
    }


def reverse_former_member_debt_payment(
    ctx: FamilyContext, actor_id: str, debt_id: str, event_id: str, request_key: str
) -> Dict[str, Any]:
    """Reverses a tracked payment of a former member's record in full: the money goes back to the
    account it left and the amount back to what remains, reopening a settled record. Refused after
    her waiver, for a payment with no transfer, from an archived or deleted account, and twice. Who
    reverses follows the account (review R1-07), never a wife."""
    _require_family(ctx)
    row = _former_member_debt(ctx, debt_id)
    event = first_row(
        get_client()
        .table("former_member_debt_events")
        .select("id, debt_id, kind, transfer_id")
        .eq("id", event_id)
        .eq("debt_id", row.get("id"))
    )
    _require_reverser(ctx, actor_id, (event or {}).get("transfer_id"), reversal=(event or {}).get("kind") != "payment")
    data = _rpc_mapped("reverse_former_member_debt_payment", {
        "p_household_id": ctx.household_id,
        "p_debt_id": debt_id,
        "p_event_id": event_id,
        "p_request_key": request_key,
        "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    return {
        "status": data.get("status"),
        "replayed": bool(data.get("replayed")),
        "debt_id": data.get("debt_id") or debt_id,
        "event_id": data.get("event_id"),
        "reverses_event_id": data.get("reverses_event_id") or event_id,
        "amount": halalas_to_sar(to_halalas(data.get("amount"))),
        "remaining": halalas_to_sar(to_halalas(data.get("remaining"))),
        "account_id": str(data["account_id"]) if data.get("account_id") else None,
        "balance_moved": bool(data.get("account_id")),
    }


def waive_former_member_debt(ctx: FamilyContext, actor_id: str, debt_id: str, request_key: str) -> Dict[str, Any]:
    """Her release (إبراء): closes the record as waived; no money moves. A retry of a waiver that
    went through finds the record closed: the database answers the replay (review R1-02)."""
    _require_family(ctx)
    _require_debt_manager(ctx, actor_id)
    data = _rpc_mapped("waive_former_member_debt", {
        "p_household_id": ctx.household_id,
        "p_debt_id": debt_id,
        "p_request_key": request_key,
        "p_actor_user_id": actor_id,
    })
    data = data if isinstance(data, dict) else {}
    return {
        "status": data.get("status"),
        "replayed": bool(data.get("replayed")),
        "debt_id": data.get("debt_id") or debt_id,
        "event_id": data.get("event_id"),
        "waived_amount": halalas_to_sar(to_halalas(data.get("waived_amount"))),
        "remaining": halalas_to_sar(to_halalas(data.get("remaining"))),
    }


# ─── Personal allowance (rule 3) ──────────────────────────────────────────────

def get_allowance(
    ctx: FamilyContext, wife_id: str, cycle_key: Optional[str], caller_id: Optional[str] = None
) -> Dict[str, Any]:
    """Allocated / spent / remaining of the wife's personal allowance for a cycle. ``caller_id`` is
    who asks: only she, her husband, or an admin who is not a wife reads it (NafaqahForbidden
    otherwise). Without a caller it is the server's own read (after a set)."""
    _require_family(ctx)
    if caller_id is not None and not can_view_allowance(ctx, caller_id, wife_id):
        raise NafaqahForbidden("Only she, her husband, or an admin who is not a wife, reads her allowance.")
    _require_wife(ctx, wife_id)
    cycle = _resolve_cycle(ctx, cycle_key)
    client = get_client()
    # (household, member, cycle) is unique; limit(1) instead of maybe_single(), whose zero-row
    # behaviour differs across postgrest-py versions (see postgrest_compat).
    row = first_row(
        client.table("member_allowances")
        .select("amount")
        .eq("household_id", ctx.household_id)
        .eq("member_user_id", wife_id)
        .eq("cycle_key", cycle)
    )
    allocated = row.get("amount") if row else None
    # Every purchase of the cycle, page by page (PostgREST caps each answer).
    spent = all_rows(lambda: (
        client.table("transactions")
        .select("id, amount")
        .eq("household_id", ctx.household_id)
        .eq("nafaqah_spouse_id", wife_id)
        .eq("nafaqah_class", WIFE_PERSONAL)
        .eq("cycle_key", cycle)
    ))
    return {
        "household_id": ctx.household_id,
        "member_user_id": wife_id,
        "cycle_key": cycle,
        **compute_allowance_status(allocated, [t.get("amount") for t in spent]),
    }


def set_allowance(
    ctx: FamilyContext, actor_id: str, wife_id: str, amount: Any, cycle_key: Optional[str]
) -> Dict[str, Any]:
    """The husband or a household admin, never a wife, sets the cycle allowance."""
    _require_family(ctx)
    _require_member(ctx, actor_id)
    if not can_set_allowance(ctx, actor_id, wife_id):
        raise NafaqahForbidden("The allowance is set by the husband or a household admin who is not a wife.")
    _require_wife(ctx, wife_id)
    value = parse_sar_amount(amount, allow_zero=True)
    cycle = _resolve_cycle(ctx, cycle_key)

    try:
        res = get_client().rpc(
            "set_member_allowance",
            {
                "p_household_id": ctx.household_id,
                "p_member_user_id": wife_id,
                # Exact decimal text ("123.40"): PostgREST casts it to the numeric parameter.
                "p_amount": format(value, "f"),
                "p_cycle_key": cycle,
                "p_actor_user_id": actor_id,
            },
        ).execute()
    except Exception as exc:
        mapped = _map_db_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc

    data = res.data if isinstance(getattr(res, "data", None), dict) else None
    if data and "allocated" in data:
        allocated_h, spent_h = to_halalas(data.get("allocated")), to_halalas(data.get("spent"))
        return {
            "household_id": ctx.household_id,
            "member_user_id": wife_id,
            "cycle_key": data.get("cycle_key") or cycle,
            "is_set": bool(data.get("is_set", True)),
            "allocated": halalas_to_sar(allocated_h),
            "spent": halalas_to_sar(spent_h),
            "remaining": halalas_to_sar(allocated_h - spent_h),
            "transaction_count": int(data.get("transaction_count") or 0),
        }
    return get_allowance(ctx, wife_id, cycle)


# ─── Summary for the app ──────────────────────────────────────────────────────

def build_summary(ctx: FamilyContext, caller_id: str, cycle_key: Optional[str] = None) -> Dict[str, Any]:
    """Everything the family Nafaqah card needs, from the caller's point of view."""
    role = ctx.role_of(caller_id)
    provider_fields = {
        "provider_user_id": ctx.provider_user_id,
        "needs_provider": ctx.needs_provider,
        "can_set_provider": ctx.is_admin(caller_id) and not ctx.is_roommates,
    }
    if not ctx.is_family:
        return {
            "household_id": ctx.household_id,
            "household_type": ctx.household_type,
            "mode": "not_family",
            "caller_role": role,
            "caller_user_id": caller_id,
            "cycle_key": None,
            "husband": None,
            "wives": [],
            "can_set_allowance": False,
            "can_record_reimbursement": False,
            "can_request_reimbursement": False,
            "allowance_wives": [],
            "former_member_debts": [],
            "can_manage_former_member_debts": False,
            **provider_fields,
        }
    cycle = _resolve_cycle(ctx, cycle_key)
    pending = get_deletion_notices(ctx, caller_id) if ctx.wives else {}
    wives = []
    # Her allowance is not her repayment ledger: she, her husband and an admin who is not a wife
    # read it (owner decision 2026-11-06). An admin who reads no wife's ledger (the husband is
    # there) still gets each wife's allowance, with nothing of her ledger (review R3-01); a
    # co-wife and an ordinary member get none.
    allowance_wives = []
    for wife in ctx.wives:
        # Only the wives whose ledger the caller reads (review R3-01): a wife her own entry, the
        # husband (an admin who is not a wife when he is gone) every wife's, anyone else none.
        if not can_view_wife_ledger(ctx, caller_id, wife["id"]):
            if can_view_allowance(ctx, caller_id, wife["id"]):
                allowance_wives.append({
                    "id": wife["id"],
                    "display_name": wife["display_name"],
                    "allowance": get_allowance(ctx, wife["id"], cycle, caller_id),
                })
            continue
        ledger = get_reimbursement_ledger(ctx, wife["id"], caller_id)
        wives.append({
            "id": wife["id"],
            "display_name": wife["display_name"],
            "reimbursement": ledger["balance"],
            # Her requests (pending first in the app) and their outcomes, newest first.
            "requests": ledger["requests"],
            # Who may act on this wife's ledger: she asks; her husband (an admin who is not a wife
            # when he is gone) records, approves, declines and reverses.
            "can_request": can_request_reimbursement(ctx, caller_id, wife["id"]),
            "can_decide": can_record_reimbursement(ctx, caller_id, wife["id"]),
            # Whoever reads her ledger reads her allowance (she, her husband, an admin who is not
            # a wife once he is gone); checked again with the caller all the same.
            "allowance": get_allowance(ctx, wife["id"], cycle, caller_id),
            # Only for the husband (or the admins without one): she scheduled her deletion.
            "pending_deletion": pending.get(wife["id"]),
        })
    return {
        "household_id": ctx.household_id,
        "household_type": ctx.household_type,
        "mode": "family_nafaqah",
        "caller_role": role,
        "caller_user_id": caller_id,
        "cycle_key": cycle,
        "husband": (
            {"id": ctx.husband_id, "display_name": ctx.display_name(ctx.husband_id)} if ctx.husband_id else None
        ),
        "wives": wives,
        "allowance_wives": allowance_wives,
        "can_set_allowance": can_set_allowance(ctx, caller_id),
        "can_record_reimbursement": can_record_reimbursement(ctx, caller_id),
        "can_request_reimbursement": can_request_reimbursement(ctx, caller_id),
        # Only for those who manage them (review R3-01); empty for anyone else.
        "former_member_debts": list_former_member_debts(ctx, caller_id),
        "can_manage_former_member_debts": can_manage_former_member_debts(ctx, caller_id),
        **provider_fields,
    }


# ─── Nafaqah provider (owner decision 2026-10-21) ─────────────────────────────

def set_provider(ctx: FamilyContext, actor_id: str, provider_user_id: str) -> Dict[str, Any]:
    """
    A household admin names the Nafaqah provider (husband): a non-spouse member of the household.
    Goes through public.set_nafaqah_provider with the verified caller, so the database re-checks.
    """
    _require_member(ctx, actor_id)
    if not ctx.is_admin(actor_id):
        raise NafaqahForbidden("Only a household admin can choose the Nafaqah provider.")
    if ctx.is_roommates:
        raise NotFamilyHousehold("A roommates household has no Nafaqah provider.")
    target = _norm(provider_user_id)
    if not ctx.is_member(target):
        raise InvalidNafaqahRequest("The provider must be a member of this household.")
    if ctx.members[target].get("financial_role") == "spouse":
        raise InvalidNafaqahRequest("A wife cannot be the Nafaqah provider.")

    try:
        res = get_client().rpc(
            "set_nafaqah_provider",
            {"p_household_id": ctx.household_id, "p_user_id": target, "p_actor_user_id": actor_id},
        ).execute()
    except Exception as exc:
        mapped = _map_db_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc

    data = res.data if isinstance(getattr(res, "data", None), dict) else {}
    previous = data.get("previous_provider_user_id", ctx.provider_user_id)
    return {
        "status": "success",
        "household_id": ctx.household_id,
        "provider_user_id": target,
        "previous_provider_user_id": str(previous) if previous else None,
    }
