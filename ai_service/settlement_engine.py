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
    split_ratio: float = 0.50, # 50/50 fair share
) -> Dict[str, Any]:
    """
    Computes household partner balance for the current active salary cycle.
    - Personal expenses ('me' vs 'partner') are excluded from split.
    - Shared expenses ('both') or household expenses are split according to split_ratio.
    """
    client = get_client()
    dates = get_salary_cycle_dates()
    start_iso = cycle_start or dates["cycle_start"]

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
    except Exception as exc:
        logger.error("Failed to query transactions for settlement: %s", exc)
        txs = []

    me_personal_total = 0.0
    partner_personal_total = 0.0
    shared_paid_by_me = 0.0
    shared_paid_by_partner = 0.0
    shared_paid_unspecified = 0.0

    shared_txs: List[Dict[str, Any]] = []

    for tx in txs:
        amt = float(tx.get("amount", 0.0))
        spent_by = (tx.get("spent_by") or "both").lower()
        cat = tx.get("category_code") or ""
        raw_sms = (tx.get("raw_sms") or "").lower()

        # Check attribution
        if spent_by == "me":
            # Is it explicitly personal or did I pay for a shared household expense?
            if any(k in cat for k in ("GROCERY", "UTILITIES", "MISC")) or "shared" in raw_sms:
                shared_paid_by_me += amt
                shared_txs.append(tx)
            else:
                me_personal_total += amt
        elif spent_by == "partner":
            if any(k in cat for k in ("GROCERY", "UTILITIES", "MISC")) or "shared" in raw_sms:
                shared_paid_by_partner += amt
                shared_txs.append(tx)
            else:
                partner_personal_total += amt
        else: # "both"
            # Default to paid by whoever registered the transaction, or split 50/50
            shared_paid_by_me += amt
            shared_txs.append(tx)

    total_shared = shared_paid_by_me + shared_paid_by_partner
    fair_share_me = total_shared * split_ratio
    fair_share_partner = total_shared * (1.0 - split_ratio)

    # Net balance: positive means partner owes me, negative means I owe partner
    net_balance = shared_paid_by_me - fair_share_me

    if abs(net_balance) < 0.5:
        who_owes = "settled"
        settle_amt = 0.0
        recommendation_en = "All shared expenses are evenly balanced! No transfer needed."
        recommendation_ar = "جميع المصاريف المشتركة متوازنة تماماً! لا يوجد مستحقات معلقة."
    elif net_balance > 0:
        who_owes = "partner_owes_me"
        settle_amt = net_balance
        recommendation_en = f"Partner owes you SAR {settle_amt:.2f} for their share of household expenses."
        recommendation_ar = f"الشريك مدين لك بمبلغ {settle_amt:.2f} ريال لتسوية المصاريف المشتركة."
    else:
        who_owes = "me_owes_partner"
        settle_amt = abs(net_balance)
        recommendation_en = f"You owe your partner SAR {settle_amt:.2f} to balance shared expenses."
        recommendation_ar = f"أنت مدين للشريك بمبلغ {settle_amt:.2f} ريال لتسوية المصاريف المشتركة."

    return {
        "cycle_start": start_iso,
        "total_shared_expenses": round(total_shared, 2),
        "shared_paid_by_me": round(shared_paid_by_me, 2),
        "shared_paid_by_partner": round(shared_paid_by_partner, 2),
        "me_personal_total": round(me_personal_total, 2),
        "partner_personal_total": round(partner_personal_total, 2),
        "fair_share_me": round(fair_share_me, 2),
        "fair_share_partner": round(fair_share_partner, 2),
        "net_balance": round(net_balance, 2),
        "who_owes": who_owes,
        "settlement_amount": round(settle_amt, 2),
        "recommendation_en": recommendation_en,
        "recommendation_ar": recommendation_ar,
        "stc_pay_note": f"Household Budget Settlement - {settle_amt:.2f} SAR",
        "shared_transactions_count": len(shared_txs),
    }
