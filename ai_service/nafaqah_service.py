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
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Any, Dict, Iterable, List, Optional

from postgrest_compat import db_error_fields, first_row
from supabase_client import get_client, get_household_payday

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


class NotFamilyHousehold(NafaqahError):
    """The household has no spouse member: Nafaqah ledgers do not apply."""


class InvalidNafaqahRequest(NafaqahError):
    """Malformed amount, cycle key, payment method or a wife outside this household."""


class OverpaymentError(NafaqahError):
    """A reimbursement larger than the outstanding balance."""

    def __init__(self, message: str, outstanding: Optional[float] = None):
        super().__init__(message)
        self.outstanding = outstanding


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

@dataclass
class FamilyContext:
    household_id: str
    members: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    husband_id: Optional[str] = None
    wives: List[Dict[str, Any]] = field(default_factory=list)

    @property
    def is_family(self) -> bool:
        return bool(self.wives)

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


def load_family_context(household_id: str) -> FamilyContext:
    """
    Members of the household (household_memberships is authoritative) with their financial role.
    The husband mirrors public.nafaqah_husband_id(): a provider member (financial_role 'provider'
    or unset), preferring the household's primary admin, then any admin (co-admins included),
    then the longest-standing membership. Admin rights alone never make a wife the husband.
    """
    client = get_client()
    memberships = (
        client.table("household_memberships")
        .select("user_id, role, created_at")
        .eq("household_id", household_id)
        .execute()
    ).data or []
    user_ids = [str(m["user_id"]) for m in memberships if m.get("user_id")]
    users: Dict[str, Dict[str, Any]] = {}
    if user_ids:
        rows = (
            client.table("users")
            .select("id, display_name, financial_role")
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
            "financial_role": _norm(user.get("financial_role")) or "provider",
        }

    ordered = sorted(ctx.members.values(), key=lambda m: (m["created_at"], m["id"]))
    ctx.wives = [
        {"id": m["id"], "display_name": m["display_name"]}
        for m in ordered
        if m["financial_role"] == "spouse"
    ]
    if ctx.wives:
        from household_permissions import household_owner_id

        primary = household_owner_id(client, household_id)
        providers = [m for m in ordered if m["financial_role"] == "provider"]
        providers.sort(key=lambda m: (m["id"] != primary, m["role"] != "admin", m["created_at"], m["id"]))
        ctx.husband_id = providers[0]["id"] if providers else None
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
    only for herself. Households without a spouse member are never classified.
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
    else:
        # Other members (e.g. an adult child) have no spouse-relative vocabulary to classify with.
        if chosen not in (None, OVERRIDE_NONE):
            raise InvalidNafaqahRequest("Only the husband or a wife can classify a family expense.")
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
    return result


def resolve_wife_id(ctx: FamilyContext, requested: Optional[str]) -> str:
    """The wife a request refers to: an explicit member id, an alias, or the only wife."""
    req = _norm(requested)
    if req and req not in _WIFE_ALIASES:
        if not ctx.is_wife(req):
            raise InvalidNafaqahRequest("wife_user_id is not a spouse member of this household.")
        return req
    if len(ctx.wives) == 1:
        return ctx.wives[0]["id"]
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


def can_set_allowance(ctx: FamilyContext, actor_id: str, wife_id: Optional[str] = None) -> bool:
    """The husband or a household admin; never the wife herself."""
    if not ctx.is_member(actor_id) or (wife_id and str(actor_id) == str(wife_id)):
        return False
    if wife_id is None and ctx.is_wife(actor_id):
        return False
    return str(actor_id) == ctx.husband_id or ctx.is_admin(actor_id)


def can_record_reimbursement(ctx: FamilyContext, actor_id: str, wife_id: Optional[str] = None) -> bool:
    """The husband, the wife concerned (confirming receipt) or a household admin."""
    if not ctx.is_member(actor_id):
        return False
    if str(actor_id) == ctx.husband_id or ctx.is_admin(actor_id):
        return True
    return ctx.is_wife(actor_id) if wife_id is None else str(actor_id) == str(wife_id)


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
    if hint == "overpayment" or "exceeds the outstanding balance" in message:
        return OverpaymentError("Reimbursement exceeds the outstanding balance.")
    if code == "42501" or message.startswith("Forbidden"):
        return NafaqahForbidden("Not allowed for this household member.")
    if code in ("22023", "23514", "23503"):
        return InvalidNafaqahRequest("The database rejected the request.")
    return exc


# ─── Reimbursement ledger (rule 2) ────────────────────────────────────────────

def get_reimbursement_ledger(ctx: FamilyContext, wife_id: str) -> Dict[str, Any]:
    """Outstanding balance plus the history of advances and repayments (newest first)."""
    _require_family(ctx)
    _require_wife(ctx, wife_id)
    client = get_client()
    advances = (
        client.table("transactions")
        .select("id, amount, merchant, category_code, timestamp, cycle_key")
        .eq("household_id", ctx.household_id)
        .eq("nafaqah_spouse_id", wife_id)
        .eq("nafaqah_class", WIFE_REIMBURSABLE)
        .execute()
    ).data or []
    repayments = (
        client.table("spouse_reimbursements")
        .select("id, amount, payment_method, notes, recorded_by, paid_by_user_id, created_at")
        .eq("household_id", ctx.household_id)
        .eq("wife_user_id", wife_id)
        .execute()
    ).data or []

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
    ] + [
        {
            "type": "reimbursement",
            "id": r.get("id"),
            "amount": halalas_to_sar(to_halalas(r.get("amount"))),
            "payment_method": r.get("payment_method"),
            "notes": r.get("notes"),
            "recorded_by": r.get("recorded_by"),
            "timestamp": r.get("created_at"),
        }
        for r in repayments
    ]
    history.sort(key=lambda h: str(h.get("timestamp") or ""), reverse=True)

    return {
        "household_id": ctx.household_id,
        "wife_user_id": wife_id,
        "husband_user_id": ctx.husband_id,
        "balance": compute_reimbursement_balance(
            [a.get("amount") for a in advances], [r.get("amount") for r in repayments]
        ),
        "history": history,
    }


def record_reimbursement(
    ctx: FamilyContext,
    actor_id: str,
    wife_id: str,
    amount: Any,
    payment_method: str = "cash",
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    """Record a (partial or full) repayment by the husband; overpayment is rejected."""
    _require_family(ctx)
    _require_member(ctx, actor_id)
    if not can_record_reimbursement(ctx, actor_id):
        raise NafaqahForbidden("Only the husband, the wife or a household admin can record a reimbursement.")
    _require_wife(ctx, wife_id)
    if not can_record_reimbursement(ctx, actor_id, wife_id):  # a wife records only her own
        raise NafaqahForbidden("Only the husband, the wife or a household admin can record a reimbursement.")

    value = parse_sar_amount(amount, allow_zero=False)
    method = _norm(payment_method) or "cash"
    if method not in PAYMENT_METHODS:
        raise InvalidNafaqahRequest(f"Unsupported payment method {payment_method!r}.")
    clean_notes = (notes or "").strip()[:500] or None

    # Early, friendly rejection; the RPC re-checks under an advisory lock.
    outstanding_h = to_halalas(get_reimbursement_ledger(ctx, wife_id)["balance"]["outstanding"])
    amount_h = to_halalas(value)
    if amount_h > outstanding_h:
        raise OverpaymentError(
            "Reimbursement exceeds the outstanding balance.", outstanding=halalas_to_sar(outstanding_h)
        )

    try:
        res = get_client().rpc(
            "record_spouse_reimbursement",
            {
                "p_household_id": ctx.household_id,
                "p_wife_user_id": wife_id,
                # Exact decimal text ("123.40"): PostgREST casts it to the numeric parameter.
                "p_amount": format(value, "f"),
                "p_payment_method": method,
                "p_notes": clean_notes,
                "p_actor_user_id": actor_id,
            },
        ).execute()
    except Exception as exc:
        mapped = _map_db_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc

    data = res.data if isinstance(getattr(res, "data", None), dict) else {}
    if "outstanding_after" in data and "outstanding_before" in data:
        before_h, after_h = to_halalas(data["outstanding_before"]), to_halalas(data["outstanding_after"])
    else:
        before_h, after_h = outstanding_h, outstanding_h - amount_h
    return {
        "status": "success",
        "reimbursement_id": data.get("reimbursement_id"),
        "household_id": ctx.household_id,
        "wife_user_id": wife_id,
        "paid_by_user_id": ctx.husband_id,
        "amount": halalas_to_sar(amount_h),
        "payment_method": method,
        "outstanding_before": halalas_to_sar(before_h),
        "outstanding_after": halalas_to_sar(after_h),
    }


# ─── Personal allowance (rule 3) ──────────────────────────────────────────────

def get_allowance(ctx: FamilyContext, wife_id: str, cycle_key: Optional[str]) -> Dict[str, Any]:
    """Allocated / spent / remaining of the wife's personal allowance for a cycle."""
    _require_family(ctx)
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
    spent = (
        client.table("transactions")
        .select("amount")
        .eq("household_id", ctx.household_id)
        .eq("nafaqah_spouse_id", wife_id)
        .eq("nafaqah_class", WIFE_PERSONAL)
        .eq("cycle_key", cycle)
        .execute()
    ).data or []
    return {
        "household_id": ctx.household_id,
        "member_user_id": wife_id,
        "cycle_key": cycle,
        **compute_allowance_status(allocated, [t.get("amount") for t in spent]),
    }


def set_allowance(
    ctx: FamilyContext, actor_id: str, wife_id: str, amount: Any, cycle_key: Optional[str]
) -> Dict[str, Any]:
    """The husband (or a household admin other than the wife) sets the cycle allowance."""
    _require_family(ctx)
    _require_member(ctx, actor_id)
    if not can_set_allowance(ctx, actor_id, wife_id):
        raise NafaqahForbidden("The allowance is set by the husband or a household admin.")
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
    if not ctx.is_family:
        return {
            "household_id": ctx.household_id,
            "mode": "not_family",
            "caller_role": role,
            "caller_user_id": caller_id,
            "cycle_key": None,
            "husband": None,
            "wives": [],
            "can_set_allowance": False,
            "can_record_reimbursement": False,
        }
    cycle = _resolve_cycle(ctx, cycle_key)
    wives = []
    for wife in ctx.wives:
        wives.append({
            "id": wife["id"],
            "display_name": wife["display_name"],
            "reimbursement": get_reimbursement_ledger(ctx, wife["id"])["balance"],
            "allowance": get_allowance(ctx, wife["id"], cycle),
        })
    return {
        "household_id": ctx.household_id,
        "mode": "family_nafaqah",
        "caller_role": role,
        "caller_user_id": caller_id,
        "cycle_key": cycle,
        "husband": (
            {"id": ctx.husband_id, "display_name": ctx.display_name(ctx.husband_id)} if ctx.husband_id else None
        ),
        "wives": wives,
        "can_set_allowance": can_set_allowance(ctx, caller_id),
        "can_record_reimbursement": can_record_reimbursement(ctx, caller_id),
    }
