"""
Smart Partner Settlement & Fair-Share Splitting Engine.
Calculates balance between partners for shared household expenses and generates STC Pay / Urpay settle-up recommendations.
"""

from __future__ import annotations
import logging
import re
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Dict, Any, List, Optional, Tuple

from supabase_client import get_client, get_household_payday
from salary_cycle import get_salary_cycle_dates
from nafaqah_service import FamilyContext, get_reimbursement_ledger, load_family_context

logger = logging.getLogger(__name__)

_HALALA = Decimal("0.01")


def _to_halalas(amount: Any) -> int:
    """SAR amount → integer halalas (1/100 SAR), rounding half-up on the decimal value."""
    return int((Decimal(str(amount or 0)) / _HALALA).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _to_sar(halalas: int) -> float:
    return float((Decimal(halalas) * _HALALA).quantize(_HALALA))


def _cycle_dates(household_id: str) -> Dict[str, Any]:
    """Active salary cycle of the household (its configured payday, Riyadh dates)."""
    return get_salary_cycle_dates(payday_day=get_household_payday(household_id))


# Who paid and for whom (FABLE-API-01 / FABLE-LOGIC-03). public.transactions has no paid_by
# column (live and the repo schema agree; selecting a missing column fails the whole query,
# FR-B-02/03). Rows written by the API store the attribution structurally:
#   * ``spent_by``  payer relative to the creator ``user_id``: 'me' | 'partner';
#   * ``beneficiary_type`` / ``beneficiary_id``: 'household'/'household' (everyone),
#     'individual'/<member id> or 'dependent'/<name> (a household cost).
# The ``raw_sms`` note is for humans. Rows from the app's manual sheet (direct inserts) carry the
# payer in the fixed tail of their note ("… | PaidBy: <x> | Beneficiary: <y> | SpentBy: <z>"),
# read right-anchored so a merchant containing a forged tag cannot shadow it. Rows written before
# this change (``beneficiary_id`` NULL) are read from their tags, but only from the
# server-authored segment (the last occurrence, before the trailing item summary), and a chat or
# receipt row's payer can only be 'me' or 'partner' there (the API never wrote a member id).
# Settlement rows carry the payer in their server-authored head "Settlement | PaidBy: <id> |".
_PARTNER_TX_COLUMNS = (
    "id, user_id, amount, merchant, category_code, spent_by, timestamp, raw_sms, source, "
    "beneficiary_type, beneficiary_id, is_settlement, settlement_target_id, nafaqah_class"
)
_PARTNER_TX_COLUMNS_PRE_NAFAQAH = (
    "id, user_id, amount, merchant, category_code, spent_by, timestamp, raw_sms, source, "
    "beneficiary_type, beneficiary_id, is_settlement, settlement_target_id"
)
_V2_TX_COLUMNS = (
    "id, user_id, amount, raw_sms, source, beneficiary_type, beneficiary_id, is_settlement, settlement_target_id, "
    "line_items, timestamp, category_code, spent_by, nafaqah_class, nafaqah_spouse_id"
)

SHARED = "shared"
_SHARED_IDS = {"", "household", "all_peers", "all", "both", "shared", "family", "everyone"}
_WIFE_TOKENS = ("wife", "spouse")
_HUSBAND_TOKENS = ("husband", "provider")
_RELATIVE_TOKENS = ("me", "partner") + _WIFE_TOKENS + _HUSBAND_TOKENS
_MANUAL_TAIL_RE = re.compile(
    r"\|\s*PaidBy:\s*([^|]*?)\s*\|\s*Beneficiary:\s*([^|]*?)\s*\|\s*SpentBy:\s*([^|]*?)\s*$", re.IGNORECASE
)
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_SETTLEMENT_HEAD_RE = re.compile(r"^\s*Settlement\s*\|\s*PaidBy:\s*([^|]+?)\s*\|", re.IGNORECASE)


def audit_tag(raw_sms: Any, tag: str) -> str:
    """
    Lower-cased value of the first ``<tag>: value`` part of a ``|``-separated audit note. For
    display and tests only: notes written by the API start with the server's tags, but money is
    never attributed from a note's free text (see transaction_attribution).
    """
    prefix = f"{tag.lower()}:"
    for part in str(raw_sms or "").split("|"):
        text = part.strip().lower()
        if text.startswith(prefix):
            return text[len(prefix):].strip()
    return ""


def _swap_relative(value: str) -> str:
    return {"me": "partner", "partner": "me"}.get(value, value)


def counterpart_id(ctx: FamilyContext, creator: Optional[str]) -> Optional[str]:
    """
    The member 'partner' refers to for ``creator``: the other member of a two-member household,
    or in a family the spouse (husband <-> his only wife). None when it names nobody.
    """
    members = [str(m).lower() for m in ctx.members]
    me = str(creator or "").lower()
    if me not in members:
        return None
    if len(members) == 2:
        return next(m for m in members if m != me)
    if ctx.is_family:
        husband = str(ctx.husband_id or "").lower()
        wives = [str(w["id"]).lower() for w in ctx.wives]
        if me == husband and len(wives) == 1:
            return wives[0]
        if me in wives and husband in members:
            return husband
    return None


def resolve_member_ref(ref: Any, creator: Optional[str], ctx: FamilyContext) -> Optional[str]:
    """Member id named by ``ref`` (a member id or a token relative to ``creator``), else None."""
    value = str(ref or "").strip().lower()
    members = {str(m).lower() for m in ctx.members}
    me = str(creator or "").lower()
    if value in members:
        return value
    if value in ("", "me"):
        return me if me in members else None
    if value == "partner":
        return counterpart_id(ctx, me)
    if value in _WIFE_TOKENS:
        wives = [str(w["id"]).lower() for w in ctx.wives]
        if me in wives:
            return me
        return wives[0] if len(wives) == 1 else None
    if value in _HUSBAND_TOKENS:
        husband = str(ctx.husband_id or "").lower()
        return husband if husband in members else None
    return None


def _beneficiary_ref(beneficiary_type: Any, beneficiary_id: Any) -> str:
    """Normalised beneficiary: SHARED for everyone or a dependent, else the stored id or token."""
    btype = str(beneficiary_type or "").strip().lower()
    bid = str(beneficiary_id or "").strip().lower()
    if bid in _SHARED_IDS or btype == "dependent":
        return SHARED
    return bid


def _legacy_tags(raw_sms: Any) -> Dict[str, str]:
    """Tags of a pre-structured note: the server's segment (last occurrence, before the items)."""
    text = str(raw_sms or "")
    cut = text.rfind(" | Items: [")
    if cut != -1:
        text = text[:cut]
    tags: Dict[str, str] = {}
    for part in text.split("|"):
        low = part.strip().lower()
        for tag in ("paidby", "beneficiary", "spentby"):
            if low.startswith(tag + ":"):
                tags[tag] = low[len(tag) + 1:].strip()
    return tags


def transaction_attribution(tx: Dict[str, Any]) -> Tuple[str, str]:
    """
    ``(payer_ref, beneficiary_ref)`` of a non-settlement row. Refs are member ids or tokens
    relative to the creator ('me', 'partner', 'wife', 'husband'); ``beneficiary_ref`` SHARED
    means the whole household. Resolve them with resolve_member_ref.
    """
    source = str(tx.get("source") or "").strip().lower()
    raw = str(tx.get("raw_sms") or "")
    if str(tx.get("beneficiary_id") or "").strip():
        beneficiary = _beneficiary_ref(tx.get("beneficiary_type"), tx.get("beneficiary_id"))
        if source == "manual":
            tail = _MANUAL_TAIL_RE.search(raw)
            payer = tail.group(1).strip().lower() if tail else "me"
        else:
            payer = str(tx.get("spent_by") or "me").strip().lower()
            if payer not in ("me", "partner"):
                payer = "me"
        return payer or "me", beneficiary

    tags = _legacy_tags(raw)
    payer, beneficiary = tags.get("paidby", ""), tags.get("beneficiary", "")
    api_row = source in ("chat", "receipt_scan") or raw.lstrip().startswith(("Chat:", "Receipt Scan:"))
    if api_row and payer not in ("", "me", "partner"):
        payer = "me"
    if not payer or not beneficiary:
        # Oldest rows: no tags at all, only the legacy spent_by and the category.
        spent_by = str(tx.get("spent_by") or "").strip().lower()
        category = str(tx.get("category_code") or "")
        shared_hint = (
            any(k in category for k in ("GROCERY", "UTILITIES", "MISC"))
            or "shared" in raw.lower() or "both" in raw.lower()
        )
        if spent_by in ("me", "partner"):
            payer = payer or spent_by
            beneficiary = beneficiary or (SHARED if shared_hint else spent_by)
        else:
            payer = payer or "me"
            beneficiary = beneficiary or SHARED
    return payer, _beneficiary_ref(None, beneficiary)


def _item_beneficiary(item: Dict[str, Any], creator: Optional[str], ctx: FamilyContext) -> str:
    """A line item's beneficiary as a member id, or 'all_peers' for everyone / non-members."""
    ref = str(item.get("beneficiary") or item.get("beneficiary_id") or "").strip().lower()
    if ref in _SHARED_IDS:
        return "all_peers"
    return resolve_member_ref(ref, creator, ctx) or "all_peers"


def settlement_payer_ref(tx: Dict[str, Any]) -> str:
    """Payer of a settlement row: the member id in its server-authored head, else the creator."""
    head = _SETTLEMENT_HEAD_RE.match(str(tx.get("raw_sms") or ""))
    return head.group(1).strip().lower() if head else "me"


def structured_attribution(
    ctx: Optional[FamilyContext],
    creator: Optional[str],
    paid_by: Optional[str],
    beneficiary: Optional[str],
    spouse_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Columns recording who paid (``spent_by``) and for whom (``beneficiary_type`` /
    ``beneficiary_id``) for an API insert. ``paid_by`` is 'me' or 'partner' (relative to the
    creator); ``beneficiary`` is 'me', 'partner', 'both'/'household', 'children', a member id or a
    dependent's name. 'partner' must name someone (two-member household, the spouse in a family,
    or ``spouse_id``: the wife a Nafaqah entry names in a household with several wives),
    otherwise InvalidAttributionError. Without a roster (``ctx`` None or empty) the relative
    token is stored and resolved by the settlement engines when they read the row.
    """
    from supabase_client import InvalidAttributionError
    from utils import sanitize_audit_text

    if ctx is not None and not ctx.members:
        ctx = None
    me = str(creator or "").lower()
    spouse = str(spouse_id or "").lower()
    if ctx is not None and spouse not in {str(m).lower() for m in ctx.members}:
        spouse = ""

    def partner_of_creator() -> Optional[str]:
        return (counterpart_id(ctx, me) or spouse or None) if ctx is not None else None

    payer = str(paid_by or "me").strip().lower()
    if payer not in ("me", "partner"):
        raise InvalidAttributionError("paid_by must be 'me' or 'partner'.")
    if payer == "partner" and ctx is not None and partner_of_creator() is None:
        raise InvalidAttributionError(
            "paid_by 'partner' does not name a member of this household: the member who paid records the expense."
        )

    raw_ben = str(beneficiary or "").strip()
    ben = raw_ben.lower()
    if ben in _SHARED_IDS or ben in ("us", "we", "home", "house"):
        btype, bid = "household", "household"
    elif ben == "me":
        btype, bid = "individual", me or "me"
    elif ben in ("children", "kids", "child", "dependents"):
        btype, bid = "dependent", "children"
    elif ben in _RELATIVE_TOKENS:
        resolved = None
        if ctx is not None:
            resolved = partner_of_creator() if ben == "partner" else resolve_member_ref(ben, me, ctx)
            if resolved is None and ben in _WIFE_TOKENS:
                resolved = spouse or None
        if resolved is None and ctx is not None:
            raise InvalidAttributionError(
                f"beneficiary '{ben}' does not name a member of this household: choose the member."
            )
        btype, bid = "individual", resolved or ben
    elif ben in ({str(m).lower() for m in ctx.members} if ctx is not None else set()) or (
        ctx is None and _UUID_RE.match(ben)
    ):
        btype, bid = "individual", ben
    else:
        btype, bid = "dependent", sanitize_audit_text(raw_ben, 60) or "children"
    return {"spent_by": payer, "beneficiary_type": btype, "beneficiary_id": bid}


def _caller_relative(ref: str, creator: str, anchor: str, ctx: FamilyContext) -> Optional[str]:
    """
    'me' / 'partner' relative to ``anchor`` (the caller, or the creator when nobody is asking).
    Without a known roster the creator-relative token is turned around for another caller.
    None when the household roster is known but the ref names nobody in it.
    """
    member = resolve_member_ref(ref, creator, ctx)
    if member is not None and anchor:
        return "me" if member == anchor else "partner"
    if ctx.members:
        return None
    if ref in ("me", "partner"):
        return _swap_relative(ref) if anchor and creator and creator != anchor else ref
    return None


def _cycle_transactions(client, household_id: str, start_iso: str, columns: str) -> List[Dict[str, Any]]:
    response = (
        client.table("transactions")
        .select(columns)
        .eq("household_id", household_id)
        .gte("timestamp", start_iso)
        .order("timestamp", desc=True)
        .execute()
    )
    return response.data or []


def _nafaqah_balance(ctx: FamilyContext, wife_ids: List[str]) -> Dict[str, Any]:
    """
    Outstanding Nafaqah debt from the ledger (``wife_reimbursable`` advances minus
    ``spouse_reimbursements``), all time and exact to the halala: the same figures as
    GET /households/{id}/nafaqah and the database's get_spouse_reimbursement_balance().
    """
    gross = paid = outstanding = 0
    for wife_id in wife_ids:
        balance = get_reimbursement_ledger(ctx, wife_id)["balance"]
        gross += _to_halalas(balance["gross_advanced"])
        paid += _to_halalas(balance["reimbursed"])
        outstanding += _to_halalas(balance["outstanding"])
    return {"gross_advanced": _to_sar(gross), "reimbursed": _to_sar(paid), "outstanding": _to_sar(outstanding)}


def calculate_partner_settlement(
    household_id: str,
    cycle_start: Optional[str] = None,
    split_ratio: float = 0.50,  # roommate/partner households only
    caller_user_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Computes household partner balance for the current active salary cycle.
    Supports 2D model:
      - paid_by: 'me' | 'partner' (who actually paid/tapped card)
      - beneficiary: 'me' | 'partner' | 'both' (who benefits from purchase)
    Backward compatible with legacy 'spent_by' field.

    In a married-family household (a spouse member in ``household_memberships``, which is
    authoritative: ``users.household_id`` is only the member's *active* household) the Islamic
    Nafaqah rule applies instead of ``split_ratio``: the husband bears household, children and
    wife expenses in full, so nothing he pays creates a debt for the wife. What he owes is the
    Nafaqah ledger: ``wife_reimbursable`` advances minus the repayments recorded in
    ``spouse_reimbursements`` (all time, to the halala), the same balance as the Nafaqah card.
    ``caller_user_id`` identifies which spouse "me" refers to; a wife sees her own balance,
    anyone else the husband's total across wives.
    """
    if not (0.0 <= float(split_ratio) <= 1.0):
        raise ValueError("split_ratio must be between 0 and 1")
    client = get_client()
    # No fallback on failure: guessing "not a family" would split the spouses 50/50.
    ctx = load_family_context(household_id)
    is_family = ctx.is_family
    caller_is_wife = ctx.is_wife(caller_user_id)
    dates = _cycle_dates(household_id)
    start_iso = cycle_start or dates["cycle_start"]

    try:
        txs = _cycle_transactions(client, household_id, start_iso, _PARTNER_TX_COLUMNS)
    except Exception as exc:
        # Databases without the Nafaqah migration lack nafaqah_class; any other failure propagates
        # (an empty list would report every balance as settled).
        logger.warning("Settlement query with nafaqah_class failed (%s), retrying without it.", exc)
        txs = _cycle_transactions(client, household_id, start_iso, _PARTNER_TX_COLUMNS_PRE_NAFAQAH)

    me_personal_total = 0.0
    partner_personal_total = 0.0
    shared_paid_by_me = 0.0
    shared_paid_by_partner = 0.0
    i_paid_for_partner_100 = 0.0
    partner_paid_for_me_100 = 0.0

    settled_by_me = 0.0
    settled_to_me = 0.0
    caller = str(caller_user_id or "").lower()

    shared_txs: List[Dict[str, Any]] = []

    for tx in txs:
        amt = float(tx.get("amount") or 0.0)
        creator = str(tx.get("user_id") or "").lower()
        anchor = caller or creator

        if tx.get("is_settlement"):
            # A recorded settlement payment, not a shared expense. Family debts live in the
            # Nafaqah ledger (spouse_reimbursements), so settlement rows only move roommate
            # balances: paying the partner back raises what they owe me (lowers what I owe).
            if not is_family and caller:
                payer = resolve_member_ref(settlement_payer_ref(tx), creator, ctx) or creator
                recipient = str(tx.get("settlement_target_id") or "").lower()
                if payer == caller:
                    settled_by_me += amt
                elif recipient == caller:
                    settled_to_me += amt
            continue

        # Family: the explicit Nafaqah class decides, relative to the caller ('me').
        nafaqah_class = str(tx.get("nafaqah_class") or "").strip().lower()
        if is_family and nafaqah_class in ("wife_reimbursable", "wife_personal"):
            paid_by = "me" if caller_is_wife else "partner"
            beneficiary = paid_by if nafaqah_class == "wife_personal" else "both"
        else:
            # Structured attribution (the same as /settlement-v2), relative to the caller.
            payer_ref, beneficiary_ref = transaction_attribution(tx)
            paid_by = _caller_relative(payer_ref, creator, anchor, ctx)
            if paid_by is None:
                logger.info("Settlement: payer of transaction %s unknown; not attributed.", tx.get("id"))
                continue
            beneficiary = (
                "both" if beneficiary_ref == SHARED
                else (_caller_relative(beneficiary_ref, creator, anchor, ctx) or "both")
            )

        # Apply 2D financial attribution
        if paid_by == "me":
            if beneficiary == "partner":
                # I paid 100% for partner -> partner owes me 100%
                i_paid_for_partner_100 += amt
                shared_txs.append(tx)
            elif beneficiary == "me":
                # Personal solo
                me_personal_total += amt
            else:
                # Shared / Family / Child dependent expense -> partner owes (1 - split_ratio)
                shared_paid_by_me += amt
                shared_txs.append(tx)
        elif paid_by == "partner":
            if beneficiary == "me":
                # Partner paid 100% for me -> I owe partner 100%
                partner_paid_for_me_100 += amt
                shared_txs.append(tx)
            elif beneficiary == "partner":
                # Partner personal solo
                partner_personal_total += amt
            else:
                # Shared / Family / Child dependent expense -> I owe split_ratio
                shared_paid_by_partner += amt
                shared_txs.append(tx)
        else:
            # Default to shared paid by me
            shared_paid_by_me += amt
            shared_txs.append(tx)

    total_shared = shared_paid_by_me + shared_paid_by_partner
    nafaqah_balance: Optional[Dict[str, Any]] = None
    if is_family:
        # Nafaqah: husband carries 100% of shared family expenses; no spousal 50/50 split.
        # The debt is the ledger balance, so recorded repayments reduce it.
        wife_ids = [str(caller_user_id)] if caller_is_wife else [w["id"] for w in ctx.wives]
        nafaqah_balance = _nafaqah_balance(ctx, wife_ids)
        if caller_is_wife:
            fair_share_me, fair_share_partner = 0.0, round(total_shared, 2)
            total_owed_to_me = nafaqah_balance["outstanding"]
            total_owed_to_partner = 0.0
        else:
            fair_share_me, fair_share_partner = round(total_shared, 2), 0.0
            total_owed_to_me = 0.0
            total_owed_to_partner = nafaqah_balance["outstanding"]
    else:
        fair_share_me = round(total_shared * split_ratio, 2)
        fair_share_partner = round(total_shared * (1.0 - split_ratio), 2)

        # Calculate net debt:
        # What partner owes me:
        partner_owes_for_shared = shared_paid_by_me * (1.0 - split_ratio)
        total_owed_to_me = i_paid_for_partner_100 + partner_owes_for_shared

        # What I owe partner:
        i_owe_for_shared = shared_paid_by_partner * split_ratio
        total_owed_to_partner = partner_paid_for_me_100 + i_owe_for_shared

        # Recorded settlement payments between the two of us.
        total_owed_to_me += settled_by_me
        total_owed_to_partner += settled_to_me

    # Net balance: positive = partner owes me, negative = I owe partner
    net_balance = round(total_owed_to_me - total_owed_to_partner, 2)

    # Roommate splits round to whole riyals; the Nafaqah ledger is exact to the halala, so any
    # outstanding halala is still shown (the repayment RPC would accept it).
    settled_below = 0.01 if is_family else 0.5
    if abs(net_balance) < settled_below:
        who_owes = "settled"
        settle_amt = 0.0
        recommendation_en = "All expenses are evenly balanced! No transfer needed."
        recommendation_ar = "جميع المصاريف المشتركة متوازنة تماماً! لا يوجد مستحقات معلقة."
    elif net_balance > 0:
        who_owes = "partner_owes_me"
        settle_amt = net_balance
        recommendation_en = f"Partner owes you SAR {settle_amt:.2f} for shared and on-behalf expenses."
        recommendation_ar = f"الشريك مدين لك بمبلغ {settle_amt:.2f} ريال لتسوية المصاريف المشتركة والخاصة."
    else:
        who_owes = "me_owes_partner"
        settle_amt = abs(net_balance)
        recommendation_en = f"You owe your partner SAR {settle_amt:.2f} to balance shared and on-behalf expenses."
        recommendation_ar = f"أنت مدين للشريك بمبلغ {settle_amt:.2f} ريال لتسوية المصاريف المشتركة والخاصة."

    return {
        "mode": "family_nafaqah" if is_family else "shared_split",
        "cycle_start": start_iso,
        "total_shared_expenses": round(total_shared, 2),
        "shared_paid_by_me": round(shared_paid_by_me, 2),
        "shared_paid_by_partner": round(shared_paid_by_partner, 2),
        "i_paid_for_partner_100": round(i_paid_for_partner_100, 2),
        "partner_paid_for_me_100": round(partner_paid_for_me_100, 2),
        "me_personal_total": round(me_personal_total, 2),
        "partner_personal_total": round(partner_personal_total, 2),
        "fair_share_me": fair_share_me,
        "fair_share_partner": fair_share_partner,
        "owed_to_me": round(total_owed_to_me, 2),
        "owed_to_partner": round(total_owed_to_partner, 2),
        "net_balance": net_balance,
        "who_owes": who_owes,
        "settlement_amount": round(settle_amt, 2),
        "recommendation_en": recommendation_en,
        "recommendation_ar": recommendation_ar,
        "stc_pay_note": f"Household Budget Settlement - {settle_amt:.2f} SAR",
        "shared_transactions_count": len(shared_txs),
        "nafaqah": nafaqah_balance,
    }


# =============================================================================
# ISLAMIC FAMILY NAFAQAH & WIFE REIMBURSEMENT
# =============================================================================

def calculate_family_nafaqah(
    txs: List[Dict[str, Any]],
    husband_id: str,
    wife_id: str,
) -> Dict[str, Any]:
    """
    Computes Islamic Family Nafaqah (maintenance) & Wife Reimbursement.
    - Husband paying for household/kids: 0 debt for wife.
    - Wife paying for household/kids: Husband owes Wife 100% reimbursement.
    - Husband settlement payments to wife deduct from pending reimbursement.
    """
    wife_reimbursement_owed = 0.0
    reimbursed_total = 0.0
    spent_on_wife = 0.0
    spent_on_children = 0.0
    family_general_total = 0.0

    for tx in txs:
        amt = float(tx.get("amount") or 0.0)
        paid_by = str(tx.get("paid_by") or "").strip().lower()
        ben_type = str(tx.get("beneficiary_type") or "").strip().lower()
        ben_id = str(tx.get("beneficiary_id") or "").strip().lower()
        is_settlement = bool(tx.get("is_settlement", False))
        target_id = str(tx.get("settlement_target_id") or ben_id).strip().lower()

        # Handle settlement reimbursement payments
        if is_settlement:
            if (paid_by == husband_id.lower() or paid_by in ("me", "husband", "owner")) and (target_id == wife_id.lower() or target_id in ("wife", "spouse")):
                reimbursed_total += amt
            continue

        # Explicit Nafaqah classification (set at entry by the wife's choice) wins over the
        # paid_by/beneficiary heuristics: reimbursable = husband owes her, personal = her allowance.
        nafaqah_class = str(tx.get("nafaqah_class") or "").strip().lower()
        if nafaqah_class == "wife_reimbursable":
            wife_reimbursement_owed += amt
            family_general_total += amt
            continue
        if nafaqah_class == "wife_personal":
            spent_on_wife += amt
            continue

        # Normal expenses
        is_tabarru = bool(tx.get("is_tabarru") or tx.get("is_gift"))
        if paid_by in (wife_id.lower(), "wife", "spouse"):
            if ben_id in (wife_id.lower(), "wife", "spouse"):
                # Wife personal expenditure from own pocket
                spent_on_wife += amt
            else:
                # Wife paid for the household, the husband, children or any dependent (incl. a
                # dependent referenced only by id, which previously fell through uncounted):
                # the husband owes it back in full unless she gave it as Tabarru' (voluntary gift).
                is_child = "child" in ben_id or ben_id in ("kids", "children") or ben_type in ("individual", "dependent")
                if not is_tabarru:
                    wife_reimbursement_owed += amt
                if is_child and ben_id not in (husband_id.lower(), "husband"):
                    spent_on_children += amt
                else:
                    family_general_total += amt
        else:
            # Husband or general household payer
            if ben_id in (wife_id.lower(), "wife", "spouse"):
                spent_on_wife += amt
            elif ben_id in (husband_id.lower(), "husband", "provider"):
                # The husband's own purchase ('individual'/<his id> since structured attribution).
                family_general_total += amt
            elif "child" in ben_id or ben_id in ("kids", "children") or ben_type in ("individual", "dependent"):
                spent_on_children += amt
            else:
                family_general_total += amt

    pending_reimbursement = max(0.0, round(wife_reimbursement_owed - reimbursed_total, 2))

    return {
        "wife_reimbursement_owed": pending_reimbursement,
        "gross_wife_advances": round(wife_reimbursement_owed, 2),
        "reimbursed_total": round(reimbursed_total, 2),
        "spent_on_wife": round(spent_on_wife, 2),
        "spent_on_children": round(spent_on_children, 2),
        "family_general_total": round(family_general_total, 2),
        "status": "settled" if pending_reimbursement < 0.01 else "reimbursement_pending",
    }


# =============================================================================
# MULTI-PARTY ROOMMATE PAIRWISE LEDGER & DEBT SIMPLIFICATION
# =============================================================================

def _pro_rata(weights: List[int], total: int) -> List[int]:
    """
    Split ``total`` halalas (may be negative) over ``weights`` proportionally, exact to the
    halala: floor shares, then the leftover halalas to the largest remainders (ties: first item).
    Equal shares when every weight is zero.
    """
    if not weights or total == 0:
        return [0] * len(weights)
    sign, magnitude = (1, total) if total > 0 else (-1, -total)
    if sum(weights) <= 0:
        weights = [1] * len(weights)
    weight_sum = sum(weights)
    shares = [magnitude * w // weight_sum for w in weights]
    remainders = sorted(range(len(weights)), key=lambda i: (-(magnitude * weights[i] % weight_sum), i))
    for i in remainders[: magnitude - sum(shares)]:
        shares[i] += 1
    return [sign * s for s in shares]


def calculate_roommate_pairwise_debts(
    txs: List[Dict[str, Any]],
    peers: List[str],
) -> List[Dict[str, Any]]:
    """
    Computes pairwise debt balance across multiple roommates, honoring line-item tags.
    Returns: [{'from_id': 'omar', 'to_id': 'ahmed', 'amount': 100.0}, ...]

    All arithmetic is in integer halalas. Equal splits distribute the indivisible remainder
    one halala at a time in sorted peer order, so every halala paid is attributed exactly once
    (float shares such as 100/3 previously leaked or invented fractions of a halala per split).
    """
    peers_norm = sorted({p.strip().lower() for p in peers if p})
    if len(peers_norm) < 2:
        return []

    # balance[i][j]: halalas person i paid on behalf of person j
    balance: Dict[str, Dict[str, int]] = {p: {q: 0 for q in peers_norm} for p in peers_norm}

    def split_equally(payer: str, amount_halalas: int) -> None:
        n = len(peers_norm)
        base, remainder = divmod(amount_halalas, n)
        for idx, p in enumerate(peers_norm):
            share = base + (1 if idx < remainder else 0)
            if p != payer:
                balance[payer][p] += share

    for tx in txs:
        amt = _to_halalas(tx.get("amount"))
        paid_by = str(tx.get("paid_by") or "").strip().lower()
        if paid_by not in balance:
            continue

        if bool(tx.get("is_settlement", False)):
            target_id = str(tx.get("settlement_target_id") or tx.get("beneficiary_id") or "").strip().lower()
            if target_id in balance and target_id != paid_by:
                # Direct settlement payment from paid_by to target_id reduces paid_by's debt
                balance[paid_by][target_id] += amt
            continue

        def attribute(beneficiary: str, amount_halalas: int) -> None:
            # A member (incl. the payer: a personal purchase) or, for anyone/anything else
            # (everyone, a child, a dependent), an equal split among all roommates.
            if beneficiary in balance:
                if beneficiary != paid_by:
                    balance[paid_by][beneficiary] += amount_halalas
            else:
                split_equally(paid_by, amount_halalas)

        line_items = [i for i in (tx.get("line_items") or []) if isinstance(i, dict)]
        if line_items:
            items = [
                (
                    str(item.get("beneficiary") or item.get("beneficiary_id") or "all_peers").strip().lower(),
                    _to_halalas(item.get("amount", item.get("price"))),
                )
                for item in line_items
            ]
            # VAT, service or a discount that is not itemised (FABLE-LOGIC-08): the receipt total
            # minus the item sum follows the items pro-rata, to the halala (largest remainder).
            for (ben, item_amt), extra in zip(items, _pro_rata([a for _, a in items], amt - sum(a for _, a in items))):
                attribute(ben, item_amt + extra)
        else:
            ben_type = str(tx.get("beneficiary_type") or "all_peers").strip().lower()
            ben_id = str(tx.get("beneficiary_id") or "").strip().lower()
            if ben_type in ("all_peers", "household", "both") or not ben_id:
                split_equally(paid_by, amt)
            else:
                attribute(ben_id, amt)

    # Compute net pairwise debts
    debts: List[Dict[str, Any]] = []
    for i in range(len(peers_norm)):
        for j in range(i + 1, len(peers_norm)):
            p1, p2 = peers_norm[i], peers_norm[j]
            net = balance[p1][p2] - balance[p2][p1]
            if net > 0:
                debts.append({"from_id": p2, "to_id": p1, "amount": _to_sar(net)})
            elif net < 0:
                debts.append({"from_id": p1, "to_id": p2, "amount": _to_sar(-net)})

    return debts


def simplify_debts(debts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Minimises transfers among multi-party debts by settling net balances.

    Net positions are computed exactly in halalas; the largest debtor is repeatedly matched with
    the largest creditor. The result preserves every participant's net position to the halala
    and needs at most (participants with a non-zero balance - 1) transfers. Finding the absolute
    minimum number of transfers is NP-hard (subset-sum); this greedy bound is the standard one.
    """
    net: Dict[str, int] = {}
    for d in debts:
        amt = _to_halalas(d["amount"])
        net[d["from_id"]] = net.get(d["from_id"], 0) - amt
        net[d["to_id"]] = net.get(d["to_id"], 0) + amt

    debtors = sorted(([p, -b] for p, b in net.items() if b < 0), key=lambda x: (-x[1], x[0]))
    creditors = sorted(([p, b] for p, b in net.items() if b > 0), key=lambda x: (-x[1], x[0]))

    simplified: List[Dict[str, Any]] = []
    while debtors and creditors:
        debtor, creditor = debtors[0], creditors[0]
        settle = min(debtor[1], creditor[1])
        simplified.append({"from_id": debtor[0], "to_id": creditor[0], "amount": _to_sar(settle)})
        debtor[1] -= settle
        creditor[1] -= settle
        if debtor[1] == 0:
            debtors.pop(0)
        if creditor[1] == 0:
            creditors.pop(0)
        debtors.sort(key=lambda x: (-x[1], x[0]))
        creditors.sort(key=lambda x: (-x[1], x[0]))

    return simplified


def calculate_settlement_v2(
    household_id: str,
    cycle_start: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Computes unified role-aware settlement:
    - If household contains peer members (roommates) and no spouse: computes multi-party pairwise debts & simplification.
    - Otherwise (default family household): computes Islamic Family Nafaqah (husband provides, wife owes 0).

    Members come from ``household_memberships`` (authoritative); ``users.household_id`` is only
    each member's active household. In a family household the reimbursement figures
    (``wife_reimbursement_owed``, ``gross_wife_advances``, ``reimbursed_total``, ``status``) are
    the Nafaqah ledger balance, so repayments recorded in ``spouse_reimbursements`` reduce them;
    the spending breakdown (``spent_on_*``, ``family_general_total``) covers the cycle.
    """
    client = get_client()
    dates = _cycle_dates(household_id)
    start_iso = cycle_start or dates["cycle_start"]

    # No fallback on failure: an empty roster would silently change the household's mode.
    ctx = load_family_context(household_id)
    members = list(ctx.members.values())
    has_peers = any(m.get("financial_role") == "peer" for m in members)
    has_spouse = ctx.is_family

    # No fallback on failure: an empty list would report every balance as settled.
    txs = []
    for tx in _cycle_transactions(client, household_id, start_iso, _V2_TX_COLUMNS):
        creator = str(tx.get("user_id") or "").lower()
        if tx.get("is_settlement"):
            payer = resolve_member_ref(settlement_payer_ref(tx), creator, ctx)
            normalized = {"beneficiary_type": tx.get("beneficiary_type"), "beneficiary_id": tx.get("beneficiary_id")}
        else:
            # Structured attribution (the same as /settlement), resolved to member ids.
            payer_ref, beneficiary_ref = transaction_attribution(tx)
            payer = resolve_member_ref(payer_ref, creator, ctx)
            if str(tx.get("nafaqah_class") or "").lower() in ("wife_reimbursable", "wife_personal"):
                # A classified Nafaqah row was paid by the wife it names (several wives: 'partner'
                # alone does not say which).
                payer = resolve_member_ref(tx.get("nafaqah_spouse_id"), creator, ctx) or payer
            beneficiary = None if beneficiary_ref == SHARED else resolve_member_ref(beneficiary_ref, creator, ctx)
            normalized = {
                "line_items": [
                    {**item, "beneficiary": _item_beneficiary(item, creator, ctx)}
                    for item in (tx.get("line_items") or []) if isinstance(item, dict)
                ],
            }
            if not has_spouse:
                # The family summary keeps the stored columns (member id, 'household', dependent).
                normalized["beneficiary_type"] = "individual" if beneficiary else "all_peers"
                normalized["beneficiary_id"] = beneficiary
        if payer is None:
            logger.info("Settlement v2: payer of transaction %s unknown; not attributed.", tx.get("id"))
            continue
        txs.append({**tx, **normalized, "paid_by": payer})

    if has_peers and not has_spouse:
        peers = [m["id"] for m in members]
        pairwise = calculate_roommate_pairwise_debts(txs, peers)
        simplified = simplify_debts(pairwise)
        return {
            "mode": "multi_roommate",
            "cycle_start": start_iso,
            "family_summary": None,
            "pairwise_debts": pairwise,
            "simplified_debts": simplified,
            "roommate_balances": {},
        }

    # financial_role decides (load_family_context); household admin rights say nothing about
    # who the husband is (a wife who administers the household is never the provider).
    husband_id = ctx.husband_id or "provider"
    wife_id = ctx.wives[0]["id"] if ctx.wives else "spouse"
    family_summary = calculate_family_nafaqah(txs, husband_id=husband_id, wife_id=wife_id)
    if has_spouse:
        balance = _nafaqah_balance(ctx, [w["id"] for w in ctx.wives])
        family_summary.update({
            "wife_reimbursement_owed": balance["outstanding"],
            "gross_wife_advances": balance["gross_advanced"],
            "reimbursed_total": balance["reimbursed"],
            "status": "settled" if _to_halalas(balance["outstanding"]) == 0 else "reimbursement_pending",
        })
    return {
        "mode": "family_nafaqah",
        "cycle_start": start_iso,
        "family_summary": family_summary,
        "pairwise_debts": [],
        "simplified_debts": [],
        "roommate_balances": {},
    }
