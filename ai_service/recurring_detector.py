"""
Recurring Bill & Subscription Predictor Engine.
Analyzes transaction clusters for monthly cadence and known Saudi utility/telecom/subscription
patterns to reserve funds in the active 27th salary cycle.
"""

from __future__ import annotations
import re
from collections import defaultdict
from dataclasses import dataclass, asdict
from datetime import date, datetime, timedelta, timezone
from typing import Dict, Any, List, Optional

from salary_cycle import get_cycle_for_date

# Known recurring merchant patterns in Saudi Arabia and global digital subscriptions
KNOWN_BILL_PROVIDERS = [
    (r"\b(stc|mystc)\b", "STC"),
    (r"\b(mobily)\b", "Mobily"),
    (r"\b(zain)\b", "Zain"),
    (r"\b(salam|virgin\s*mobile|red\s*bull\s*mobile)\b", "Telecom"),
    (r"\b(saudi\s*electricity|sec\b|al\s*kahraba|power\s*bill)\b", "Saudi Electricity"),
    (r"\b(national\s*water|nwc\b|water\s*bill)\b", "National Water Company"),
    (r"\b(netflix)\b", "Netflix"),
    (r"\b(spotify)\b", "Spotify"),
    (r"\b(apple|itunes|icloud)\b", "Apple Services"),
    (r"\b(google|youtube\s*premium|google\s*storage)\b", "Google Services"),
    (r"\b(amazon\s*prime|prime\s*video)\b", "Amazon Prime"),
    (r"\b(shahid|mbc)\b", "Shahid VIP"),
    (r"\b(osn|osn\+)\b", "OSN"),
    (r"\b(chatgpt|openai)\b", "ChatGPT Plus"),
    (r"\b(rent|housing\s*rent|apartment\s*lease)\b", "Housing Rent"),
]


def normalize_bill_merchant(raw_merchant: str) -> str:
    """Normalizes raw merchant text to standard bill provider if recognized."""
    if not raw_merchant:
        return "Unknown"
    norm = raw_merchant.strip()
    lowered = norm.lower()

    for pattern, canonical in KNOWN_BILL_PROVIDERS:
        if re.search(pattern, lowered, re.IGNORECASE):
            return canonical

    return norm


@dataclass
class RecurringBill:
    merchant: str
    normalized_merchant: str
    category_code: str
    average_amount: float
    expected_day_of_month: int
    status: str  # 'PAID_THIS_CYCLE', 'UPCOMING', 'OVERDUE'
    last_paid_date: Optional[str] = None
    paid_amount: Optional[float] = None
    cadence: str = "monthly"

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def detect_recurring_bills(
    transactions: List[Dict[str, Any]],
    as_of_date: Optional[date] = None,
) -> Dict[str, Any]:
    """
    Groups historical transactions to detect recurring monthly bills and calculates
    reserved funds required for the active salary cycle.
    """
    now_date = as_of_date or datetime.now(timezone.utc).date()
    cycle_info = get_cycle_for_date(now_date)
    cycle_start = date.fromisoformat(cycle_info["cycle_start"])
    cycle_end = date.fromisoformat(cycle_info["cycle_end"])

    if not transactions:
        return {
            "cycle_key": cycle_info["cycle_key"],
            "cycle_label": cycle_info["label"],
            "total_recurring_monthly": 0.0,
            "paid_this_cycle": 0.0,
            "reserved_amount": 0.0,
            "bills": [],
        }

    # Group by normalized merchant
    groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for tx in transactions:
        raw_m = tx.get("merchant") or "Unknown"
        norm_m = normalize_bill_merchant(raw_m)
        groups[norm_m].append(tx)

    detected_bills: List[RecurringBill] = []

    for norm_m, tx_list in groups.items():
        # Parse dates and amounts
        parsed_entries = []
        for t in tx_list:
            amt = float(t.get("amount") or 0.0)
            if amt <= 0:
                continue
            ts_str = t.get("timestamp") or t.get("created_at")
            if not ts_str:
                continue
            try:
                tx_date = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).date()
                parsed_entries.append((tx_date, amt, t.get("category_code") or "OPEX-MISC", t.get("merchant") or norm_m))
            except Exception:
                continue

        if not parsed_entries:
            continue

        # Sort by date ascending
        parsed_entries.sort(key=lambda x: x[0])

        is_known = any(norm_m == canonical for _, canonical in KNOWN_BILL_PROVIDERS)
        is_cadence_match = False

        if len(parsed_entries) >= 2:
            # Check intervals between consecutive transactions
            intervals = [(parsed_entries[i][0] - parsed_entries[i - 1][0]).days for i in range(1, len(parsed_entries))]
            monthly_intervals = [inv for inv in intervals if 25 <= inv <= 35]
            if len(monthly_intervals) >= 1:
                # Check amount variance
                amounts = [e[1] for e in parsed_entries]
                avg_amt = sum(amounts) / len(amounts)
                variance = max(abs(a - avg_amt) for a in amounts) / (avg_amt if avg_amt > 0 else 1)
                # Known utilities (electricity/water) can vary more with seasons, others must be reasonably stable (< 25%)
                if is_known or variance <= 0.25:
                    is_cadence_match = True

        if not (is_known or is_cadence_match):
            continue

        # Calculate average amount and expected day of month
        amounts = [e[1] for e in parsed_entries]
        avg_amt = round(sum(amounts) / len(amounts), 2)
        days = [e[0].day for e in parsed_entries]
        expected_day = round(sum(days) / len(days))
        category_code = parsed_entries[-1][2]
        display_merchant = parsed_entries[-1][3]

        # Determine payment status in current active cycle
        cycle_txs = [e for e in parsed_entries if cycle_start <= e[0] <= cycle_end]

        if cycle_txs:
            latest_cycle_tx = cycle_txs[-1]
            status = "PAID_THIS_CYCLE"
            last_paid = latest_cycle_tx[0].isoformat()
            paid_amount = latest_cycle_tx[1]
        else:
            last_paid = parsed_entries[-1][0].isoformat()
            paid_amount = None
            # Check if expected day in current month is past or upcoming
            # For 27th cycle (e.g. Sep 27 - Oct 26):
            # If expected_day >= 27, it belongs to the earlier calendar month (Sep)
            # If expected_day < 27, it belongs to the later calendar month (Oct)
            if expected_day >= 27:
                expected_date = date(cycle_start.year, cycle_start.month, expected_day)
            else:
                expected_date = date(cycle_end.year, cycle_end.month, expected_day)

            if now_date > expected_date:
                status = "OVERDUE"
            else:
                status = "UPCOMING"

        detected_bills.append(
            RecurringBill(
                merchant=display_merchant,
                normalized_merchant=norm_m,
                category_code=category_code,
                average_amount=avg_amt,
                expected_day_of_month=expected_day,
                status=status,
                last_paid_date=last_paid,
                paid_amount=paid_amount,
            )
        )

    # Sort bills: OVERDUE first, then UPCOMING (by expected day), then PAID_THIS_CYCLE
    def sort_key(b: RecurringBill):
        if b.status == "OVERDUE":
            return (0, b.expected_day_of_month)
        if b.status == "UPCOMING":
            return (1, b.expected_day_of_month)
        return (2, b.expected_day_of_month)

    detected_bills.sort(key=sort_key)

    total_monthly = round(sum(b.average_amount for b in detected_bills), 2)
    paid_cycle = round(sum(b.paid_amount or b.average_amount for b in detected_bills if b.status == "PAID_THIS_CYCLE"), 2)
    reserved = round(sum(b.average_amount for b in detected_bills if b.status in ("UPCOMING", "OVERDUE")), 2)

    return {
        "cycle_key": cycle_info["cycle_key"],
        "cycle_label": cycle_info["label"],
        "total_recurring_monthly": total_monthly,
        "paid_this_cycle": paid_cycle,
        "reserved_amount": reserved,
        "bills": [b.to_dict() for b in detected_bills],
    }


def fetch_household_recurring_bills(
    household_id: str,
    as_of_date: Optional[date] = None,
) -> Dict[str, Any]:
    """Fetches historical transactions for a household and calculates recurring bills."""
    from supabase_client import get_client
    client = get_client()
    cutoff = (datetime.now(timezone.utc) - timedelta(days=180)).isoformat()
    try:
        resp = (
            client.table("transactions")
            .select("id, merchant, amount, category_code, timestamp, created_at")
            .eq("household_id", household_id)
            .gte("timestamp", cutoff)
            .order("timestamp", desc=False)
            .execute()
        )
        txs = resp.data or []
    except Exception as exc:
        # Fallback to non-filtered query if timestamp column index / comparison is unavailable
        resp = (
            client.table("transactions")
            .select("id, merchant, amount, category_code, timestamp, created_at")
            .eq("household_id", household_id)
            .limit(300)
            .execute()
        )
        txs = resp.data or []

    return detect_recurring_bills(txs, as_of_date=as_of_date)

