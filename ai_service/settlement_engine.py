"""
Smart Partner Settlement & Fair-Share Splitting Engine.
Calculates balance between partners for shared household expenses and generates STC Pay / Urpay settle-up recommendations.
"""

from __future__ import annotations
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

from supabase_client import get_client
from salary_cycle import get_salary_cycle_dates

logger = logging.getLogger(__name__)

def calculate_partner_settlement(
    household_id: str,
    cycle_start: Optional[str] = None,
    split_ratio: float = 0.50,  # default 50/50
) -> Dict[str, Any]:
    """
    Computes household partner balance for the current active salary cycle.
    Supports 2D model:
      - paid_by: 'me' | 'partner' (who actually paid/tapped card)
      - beneficiary: 'me' | 'partner' | 'both' (who benefits from purchase)
    Backward compatible with legacy 'spent_by' field.
    """
    client = get_client()
    dates = get_salary_cycle_dates()
    start_iso = cycle_start or dates["cycle_start"]

    try:
        response = (
            client.table("transactions")
            .select("id, amount, merchant, category_code, spent_by, paid_by, beneficiary, timestamp, raw_sms")
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

    if abs(net_balance) < 0.5:
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

        # Normal expenses
        if paid_by in (wife_id.lower(), "wife", "spouse"):
            # Wife paid for household, kids, or husband -> Husband owes 100% reimbursement
            if ben_type in ("household", "all_peers", "") or ben_id in ("household", "kids", "children", husband_id.lower(), "husband", "") or "child" in ben_id:
                wife_reimbursement_owed += amt
                if "child" in ben_id or ben_id in ("kids", "children"):
                    spent_on_children += amt
                else:
                    family_general_total += amt
            elif ben_id in (wife_id.lower(), "wife", "spouse"):
                # Wife personal expenditure from own pocket
                spent_on_wife += amt
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
    """
    peers_norm = [p.strip().lower() for p in peers if p]
    if not peers_norm or len(peers_norm) < 2:
        return []

    # balance[i][j]: how much money person i paid on behalf of person j
    balance: Dict[str, Dict[str, float]] = {p: {q: 0.0 for q in peers_norm} for p in peers_norm}

    for tx in txs:
        amt = float(tx.get("amount") or 0.0)
        paid_by = str(tx.get("paid_by") or "").strip().lower()
        if paid_by not in balance:
            continue

        is_settlement = bool(tx.get("is_settlement", False))
        if is_settlement:
            target_id = str(tx.get("settlement_target_id") or tx.get("beneficiary_id") or "").strip().lower()
            if target_id in balance and target_id != paid_by:
                # Direct settlement payment from paid_by to target_id reduces target_id's debt
                balance[paid_by][target_id] += amt
            continue

        line_items = tx.get("line_items") or []
        if isinstance(line_items, list) and len(line_items) > 0:
            for item in line_items:
                item_amt = float(item.get("amount") or 0.0)
                ben = str(item.get("beneficiary") or item.get("beneficiary_id") or "all_peers").strip().lower()
                if ben in ("all_peers", "all", "shared", "household", ""):
                    share = item_amt / len(peers_norm)
                    for p in peers_norm:
                        if p != paid_by:
                            balance[paid_by][p] += share
                elif ben in balance and ben != paid_by:
                    balance[paid_by][ben] += item_amt
        else:
            ben_type = str(tx.get("beneficiary_type") or "all_peers").strip().lower()
            ben_id = str(tx.get("beneficiary_id") or "").strip().lower()

            if ben_type in ("all_peers", "household", "both") or not ben_id:
                share = amt / len(peers_norm)
                for p in peers_norm:
                    if p != paid_by:
                        balance[paid_by][p] += share
            elif ben_id in balance and ben_id != paid_by:
                balance[paid_by][ben_id] += amt

    # Compute net pairwise debts
    debts: List[Dict[str, Any]] = []
    peers_list = sorted(list(peers_norm))
    for i in range(len(peers_list)):
        for j in range(i + 1, len(peers_list)):
            p1 = peers_list[i]
            p2 = peers_list[j]
            net = balance[p1][p2] - balance[p2][p1]
            if net > 0.01:
                debts.append({"from_id": p2, "to_id": p1, "amount": round(net, 2)})
            elif net < -0.01:
                debts.append({"from_id": p1, "to_id": p2, "amount": round(abs(net), 2)})

    return debts


def simplify_debts(debts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Minimizes transaction count among multi-party debts using net balance matching.
    """
    net_balances: Dict[str, float] = {}
    for d in debts:
        from_id = d["from_id"]
        to_id = d["to_id"]
        amt = float(d["amount"])
        net_balances[from_id] = net_balances.get(from_id, 0.0) - amt
        net_balances[to_id] = net_balances.get(to_id, 0.0) + amt

    # Separate into creditors (> 0) and debtors (< 0)
    debtors = []
    creditors = []
    for person, bal in net_balances.items():
        round_bal = round(bal, 2)
        if round_bal < -0.01:
            debtors.append([person, abs(round_bal)])
        elif round_bal > 0.01:
            creditors.append([person, round_bal])

    simplified: List[Dict[str, Any]] = []
    d_idx = 0
    c_idx = 0

    while d_idx < len(debtors) and c_idx < len(creditors):
        debtor_person, debtor_amt = debtors[d_idx]
        creditor_person, creditor_amt = creditors[c_idx]

        settle_amt = min(debtor_amt, creditor_amt)
        if settle_amt > 0.01:
            simplified.append({
                "from_id": debtor_person,
                "to_id": creditor_person,
                "amount": round(settle_amt, 2),
            })

        debtors[d_idx][1] -= settle_amt
        creditors[c_idx][1] -= settle_amt

        if debtors[d_idx][1] < 0.01:
            d_idx += 1
        if creditors[c_idx][1] < 0.01:
            c_idx += 1

    return simplified

