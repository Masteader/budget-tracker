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
            elif beneficiary == "both":
                # I paid shared expense -> partner owes me (1 - split_ratio)
                shared_paid_by_me += amt
                shared_txs.append(tx)
            else:  # beneficiary == "me"
                # Personal solo
                me_personal_total += amt
        elif paid_by == "partner":
            if beneficiary == "me":
                # Partner paid 100% for me -> I owe partner 100%
                partner_paid_for_me_100 += amt
                shared_txs.append(tx)
            elif beneficiary == "both":
                # Partner paid shared expense -> I owe partner split_ratio
                shared_paid_by_partner += amt
                shared_txs.append(tx)
            else:  # beneficiary == "partner"
                # Partner personal solo
                partner_personal_total += amt
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

