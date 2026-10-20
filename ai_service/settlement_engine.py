"""
Smart Partner Settlement & Fair-Share Splitting Engine.
Calculates balance between partners for shared household expenses and generates STC Pay / Urpay settle-up recommendations.
"""

from __future__ import annotations
import logging
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
        response = (
            client.table("transactions")
            .select("id, amount, merchant, category_code, spent_by, paid_by, beneficiary, timestamp, raw_sms, nafaqah_class")
            .eq("household_id", household_id)
            .gte("timestamp", start_iso)
            .order("timestamp", desc=True)
            .execute()
        )
        txs = response.data or []
    except Exception as exc:
        logger.warning("Querying with paid_by/beneficiary failed (%s), falling back to spent_by query.", exc)
        try:
            response = (
                client.table("transactions")
                .select("id, amount, merchant, category_code, spent_by, timestamp, raw_sms")
                .eq("household_id", household_id)
                .gte("timestamp", start_iso)
                .order("timestamp", desc=True)
                .execute()
            )
            txs = response.data or []
        except Exception as inner_exc:
            logger.error("Failed to query transactions for settlement: %s", inner_exc)
            txs = []

    me_personal_total = 0.0
    partner_personal_total = 0.0
    shared_paid_by_me = 0.0
    shared_paid_by_partner = 0.0
    i_paid_for_partner_100 = 0.0
    partner_paid_for_me_100 = 0.0

    shared_txs: List[Dict[str, Any]] = []

    for tx in txs:
        amt = float(tx.get("amount", 0.0))
        cat = tx.get("category_code") or ""
        raw_sms = (tx.get("raw_sms") or "").lower()

        # Check explicit paid_by and beneficiary
        paid_by = (tx.get("paid_by") or "").strip().lower()
        beneficiary = (tx.get("beneficiary") or "").strip().lower()
        spent_by = (tx.get("spent_by") or "").strip().lower()

        # Family: the explicit Nafaqah class decides, relative to the caller ('me').
        nafaqah_class = str(tx.get("nafaqah_class") or "").strip().lower()
        if is_family and nafaqah_class in ("wife_reimbursable", "wife_personal"):
            paid_by = "me" if caller_is_wife else "partner"
            if nafaqah_class == "wife_personal":
                beneficiary = paid_by
            else:
                beneficiary = "both"

        # Fallback to parsing raw_sms tags if present
        if not paid_by and "paidby:" in raw_sms:
            for part in raw_sms.split("|"):
                if "paidby:" in part:
                    paid_by = part.replace("paidby:", "").strip().lower()
        if not beneficiary and "beneficiary:" in raw_sms:
            for part in raw_sms.split("|"):
                if "beneficiary:" in part:
                    beneficiary = part.replace("beneficiary:", "").strip().lower()

        # Fallback to legacy spent_by if still undefined
        if not paid_by or not beneficiary:
            if spent_by == "me":
                paid_by = "me"
                # Check category or text for shared household vs personal
                if any(k in cat for k in ("GROCERY", "UTILITIES", "MISC")) or "shared" in raw_sms or "both" in raw_sms:
                    beneficiary = "both"
                else:
                    beneficiary = "me"
            elif spent_by == "partner":
                paid_by = "partner"
                if any(k in cat for k in ("GROCERY", "UTILITIES", "MISC")) or "shared" in raw_sms or "both" in raw_sms:
                    beneficiary = "both"
                else:
                    beneficiary = "partner"
            else:  # "both" or unspecified
                paid_by = paid_by or "me"
                beneficiary = "both"

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
            elif "child" in ben_id or ben_id in ("kids", "children") or ben_type == "individual":
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

        line_items = tx.get("line_items") or []
        if isinstance(line_items, list) and len(line_items) > 0:
            for item in line_items:
                item_amt = _to_halalas(item.get("amount"))
                ben = str(item.get("beneficiary") or item.get("beneficiary_id") or "all_peers").strip().lower()
                if ben in ("all_peers", "all", "shared", "household", ""):
                    split_equally(paid_by, item_amt)
                elif ben in balance and ben != paid_by:
                    balance[paid_by][ben] += item_amt
        else:
            ben_type = str(tx.get("beneficiary_type") or "all_peers").strip().lower()
            ben_id = str(tx.get("beneficiary_id") or "").strip().lower()
            if ben_type in ("all_peers", "household", "both") or not ben_id:
                split_equally(paid_by, amt)
            elif ben_id in balance and ben_id != paid_by:
                balance[paid_by][ben_id] += amt

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

    try:
        tx_resp = (
            client.table("transactions")
            .select("id, amount, paid_by, beneficiary_type, beneficiary_id, is_settlement, settlement_target_id, line_items, timestamp, category_code, spent_by, nafaqah_class, nafaqah_spouse_id")
            .eq("household_id", household_id)
            .gte("timestamp", start_iso)
            .order("timestamp", desc=True)
            .execute()
        )
        txs = tx_resp.data or []
    except Exception as exc:
        logger.warning("Failed to fetch transactions for settlement v2: %s", exc)
        txs = []

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
