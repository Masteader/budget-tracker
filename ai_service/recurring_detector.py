"""
Recurring Bill & Subscription Predictor Engine.
Analyzes transaction clusters for monthly cadence and known Saudi utility/telecom/subscription
patterns, merged with user-allocated sub-budgets (utilities, iqama fees, recurring subscriptions)
to reserve funds in the active 27th salary cycle.
"""

from __future__ import annotations
import logging
import re
from collections import defaultdict
from dataclasses import dataclass, asdict
from datetime import date, datetime, timedelta, timezone
from typing import Dict, Any, List, Optional, Set

from salary_cycle import get_cycle_for_date

logger = logging.getLogger(__name__)

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

# Recurring keywords for cross-category detection (Iqama, Government fees, Rent, Utilities, Subscriptions)
KNOWN_RECURRING_KEYWORDS = [
    "iqama", "visa", "visas", "rent", "housing", "kahraba", "electricity",
    "sec", "water", "nwc", "internet", "fiber", "sim", "telecom", "mobile",
    "stc", "mobily", "zain", "salam", "cooling", "district", "subscription",
    "tuition", "school", "fee", "fees", "bill", "bills",
    "إيجار", "سكن", "كهرباء", "مياه", "نت", "انترنت", "ألياف", "باقة", "جوال",
    "اتصالات", "تبريد", "إقامة", "اقامة", "جوازات", "تأشيرة", "رسوم", "اشتراك",
]

DEFAULT_DUE_DAYS: Dict[str, int] = {
    "housing_rent": 1,
    "electricity_sec": 28,
    "fiber_internet": 28,
    "mobile_sims": 28,
    "water_municipal": 15,
    "sub-district-cooling": 5,
    "district_cooling": 5,
    "sub-zain-internet-sim": 28,
    "sub-iqama-fees": 25,
    "iqama_visas": 25,
    "gaming_subscriptions": 10,
    "tuition_fees": 1,
}

DEFAULT_ICONS: Dict[str, int] = {
    "housing_rent": "home",
    "electricity_sec": "bolt",
    "fiber_internet": "wifi",
    "mobile_sims": "phone_android",
    "water_municipal": "water_drop",
    "sub-district-cooling": "ac_unit",
    "district_cooling": "ac_unit",
    "sub-zain-internet-sim": "wifi",
    "sub-iqama-fees": "badge",
    "iqama_visas": "badge",
    "gaming_subscriptions": "sports_esports",
    "tuition_fees": "school",
}


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
    sub_code: Optional[str] = None
    name_ar: Optional[str] = None
    icon_key: Optional[str] = None
    is_budgeted: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def detect_recurring_bills(
    transactions: List[Dict[str, Any]],
    as_of_date: Optional[date] = None,
    budgets: Optional[List[Dict[str, Any]]] = None,
    sub_categories: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """
    Combines budget-allocated recurring obligations (utilities, iqama, subscriptions)
    with historical transaction pattern clustering to calculate reserved funds for
    the active salary cycle.
    """
    now_date = as_of_date or datetime.now(timezone.utc).date()
    cycle_info = get_cycle_for_date(now_date)
    cycle_start = date.fromisoformat(cycle_info["cycle_start"])
    cycle_end = date.fromisoformat(cycle_info["cycle_end"])
    cycle_key = cycle_info["cycle_key"]

    # Parse and index transactions
    parsed_txs = []
    for tx in transactions or []:
        amt = float(tx.get("amount") or 0.0)
        if amt <= 0:
            continue
        ts_str = tx.get("timestamp") or tx.get("created_at")
        if not ts_str:
            continue
        try:
            tx_date = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).date()
            raw_m = tx.get("merchant") or "Unknown"
            norm_m = normalize_bill_merchant(raw_m)
            parsed_txs.append({
                "id": str(tx.get("id") or ""),
                "date": tx_date,
                "amount": amt,
                "category_code": tx.get("category_code") or "OPEX-MISC",
                "sub_category": tx.get("sub_category"),
                "merchant": raw_m,
                "norm_m": norm_m,
            })
        except Exception:
            continue

    # Transactions in the current active salary cycle
    cycle_txs = [t for t in parsed_txs if cycle_start <= t["date"] <= cycle_end]
    matched_tx_ids: Set[str] = set()
    detected_bills: List[RecurringBill] = []

    # Map sub-category definitions for friendly names, Arabic labels, and keywords
    sub_def_map: Dict[str, Dict[str, Any]] = {}
    for s in (sub_categories or []):
        sub_code = s.get("sub_code")
        if sub_code:
            sub_def_map[sub_code] = s

    # 1. PROCESS BUDGET-ALLOCATED RECURRING OBLIGATIONS
    if budgets:
        # Filter for active budgets in current cycle
        active_budgets = [
            b for b in budgets
            if b.get("is_active") is not False and (
                b.get("cycle_key") == cycle_key or
                (not b.get("cycle_key") and (b.get("month") or "")[:7] == cycle_key)
            )
        ]

        for b in active_budgets:
            cat_code = b.get("category_code") or ""
            sub_allocs = b.get("sub_allocations") or {}
            rec_config = sub_allocs.get("_recurring_config") or {}

            for sub_code, alloc_amt in sub_allocs.items():
                if str(sub_code).startswith("_"):
                    continue
                try:
                    amount = float(alloc_amt or 0.0)
                except (ValueError, TypeError):
                    continue

                if amount <= 0:
                    continue

                # Determine if this sub-allocation is a recurring bill
                sub_def = sub_def_map.get(sub_code, {})
                name_en = sub_def.get("name_en") or sub_code.replace("sub-", "").replace("_", " ").title()
                name_ar = sub_def.get("name_ar") or ""
                keywords = [k.lower() for k in (sub_def.get("keywords") or [])]

                cfg = rec_config.get(sub_code) or {}
                is_explicit = cfg.get("enabled")

                is_utility = (cat_code == "OPEX-UTILITIES")
                kw_match = any(
                    kw in sub_code.lower() or kw in name_en.lower() or kw in name_ar.lower()
                    for kw in KNOWN_RECURRING_KEYWORDS
                )

                should_include = False
                if is_explicit is True:
                    should_include = True
                elif is_explicit is None and (is_utility or kw_match):
                    should_include = True

                if not should_include:
                    continue

                # Expected due day
                expected_day = cfg.get("due_day") or DEFAULT_DUE_DAYS.get(sub_code) or 28
                icon_key = DEFAULT_ICONS.get(sub_code, "receipt_long")

                # Reconcile against payments in the current active salary cycle
                matching_tx = None
                clean_sub = sub_code.replace("sub-", "").replace("_", " ").lower()

                for tx in cycle_txs:
                    if tx["id"] and tx["id"] in matched_tx_ids:
                        continue

                    # Exact sub-category match
                    if tx.get("sub_category") and tx["sub_category"] == sub_code:
                        matching_tx = tx
                        break

                    # Match by category + keywords / provider normalization
                    if tx["category_code"] == cat_code:
                        t_m_lower = tx["merchant"].lower()
                        if clean_sub in t_m_lower or any(kw in t_m_lower for kw in keywords if len(kw) >= 3):
                            matching_tx = tx
                            break
                        if tx["norm_m"].lower() in clean_sub or tx["norm_m"].lower() in name_en.lower():
                            matching_tx = tx
                            break

                    # Cross-category match for specific recognized items (e.g. Iqama)
                    if "iqama" in sub_code.lower() and ("iqama" in tx["merchant"].lower() or "إقامة" in tx["merchant"].lower()):
                        matching_tx = tx
                        break

                if matching_tx:
                    if matching_tx["id"]:
                        matched_tx_ids.add(matching_tx["id"])
                    status = "PAID_THIS_CYCLE"
                    last_paid = matching_tx["date"].isoformat()
                    paid_amount = matching_tx["amount"]
                else:
                    # Determine due vs overdue based on cycle boundaries
                    if expected_day >= 27:
                        due_date = date(cycle_start.year, cycle_start.month, min(expected_day, 28))
                    else:
                        due_date = date(cycle_end.year, cycle_end.month, min(expected_day, 28))

                    status = "OVERDUE" if now_date > due_date else "UPCOMING"
                    last_paid = None
                    paid_amount = None

                detected_bills.append(
                    RecurringBill(
                        merchant=name_en,
                        normalized_merchant=name_en,
                        category_code=cat_code,
                        average_amount=amount,
                        expected_day_of_month=expected_day,
                        status=status,
                        last_paid_date=last_paid,
                        paid_amount=paid_amount,
                        cadence="monthly",
                        sub_code=sub_code,
                        name_ar=name_ar,
                        icon_key=icon_key,
                        is_budgeted=True,
                    )
                )

    # 2. PROCESS TRANSACTION-BASED RECURRING PREDICTIONS (CADENCE & KNOWN BILL PROVIDERS)
    # Group remaining transactions not claimed by a budgeted bill
    unmatched_txs = [t for t in parsed_txs if not t["id"] or t["id"] not in matched_tx_ids]
    covered_providers = {b.normalized_merchant.lower() for b in detected_bills}
    covered_categories = {b.category_code for b in detected_bills}

    groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for tx in unmatched_txs:
        groups[tx["norm_m"]].append(tx)

    for norm_m, tx_list in groups.items():
        if norm_m.lower() in covered_providers:
            continue

        # Sort ascending by date
        tx_list.sort(key=lambda x: x["date"])
        is_known = any(norm_m == canonical for _, canonical in KNOWN_BILL_PROVIDERS)
        is_cadence_match = False

        if len(tx_list) >= 2:
            intervals = [(tx_list[i]["date"] - tx_list[i - 1]["date"]).days for i in range(1, len(tx_list))]
            monthly_intervals = [inv for inv in intervals if 25 <= inv <= 35]
            if len(monthly_intervals) >= 1:
                amounts = [t["amount"] for t in tx_list]
                avg_a = sum(amounts) / len(amounts)
                variance = max(abs(a - avg_a) for a in amounts) / (avg_a if avg_a > 0 else 1)
                if is_known or variance <= 0.25:
                    is_cadence_match = True

        if not (is_known or is_cadence_match):
            continue

        amounts = [t["amount"] for t in tx_list]
        avg_amt = round(sum(amounts) / len(amounts), 2)
        days = [t["date"].day for t in tx_list]
        expected_day = round(sum(days) / len(days))
        category_code = tx_list[-1]["category_code"]
        display_m = tx_list[-1]["merchant"]

        # Check payment in current active cycle
        c_txs = [t for t in tx_list if cycle_start <= t["date"] <= cycle_end]
        if c_txs:
            latest = c_txs[-1]
            status = "PAID_THIS_CYCLE"
            last_paid = latest["date"].isoformat()
            paid_amount = latest["amount"]
        else:
            last_paid = tx_list[-1]["date"].isoformat()
            paid_amount = None
            if expected_day >= 27:
                due_date = date(cycle_start.year, cycle_start.month, min(expected_day, 28))
            else:
                due_date = date(cycle_end.year, cycle_end.month, min(expected_day, 28))
            status = "OVERDUE" if now_date > due_date else "UPCOMING"

        detected_bills.append(
            RecurringBill(
                merchant=display_m,
                normalized_merchant=norm_m,
                category_code=category_code,
                average_amount=avg_amt,
                expected_day_of_month=expected_day,
                status=status,
                last_paid_date=last_paid,
                paid_amount=paid_amount,
                cadence="monthly",
                is_budgeted=False,
            )
        )

    # Sort bills: OVERDUE first, then UPCOMING (by due day), then PAID_THIS_CYCLE
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
    """
    Fetches transactions, active budget sub-allocations, and category taxonomies
    for a household to compute complete recurring bills and cycle reserves.
    """
    from supabase_client import get_client
    client = get_client()
    cutoff = (datetime.now(timezone.utc) - timedelta(days=180)).isoformat()
    now_date = as_of_date or datetime.now(timezone.utc).date()

    # 1. Transactions
    try:
        resp = (
            client.table("transactions")
            .select("id, merchant, amount, category_code, sub_category, timestamp, created_at")
            .eq("household_id", household_id)
            .gte("timestamp", cutoff)
            .order("timestamp", desc=False)
            .execute()
        )
        txs = resp.data or []
    except Exception:
        resp = (
            client.table("transactions")
            .select("id, merchant, amount, category_code, sub_category, timestamp, created_at")
            .eq("household_id", household_id)
            .limit(300)
            .execute()
        )
        txs = resp.data or []

    # 2. Budgets
    try:
        b_resp = (
            client.table("budgets")
            .select("id, category_code, allocated_amount, spent_amount, sub_allocations, cycle_key, month, is_active")
            .eq("household_id", household_id)
            .execute()
        )
        budgets = b_resp.data or []
    except Exception as exc:
        logger.warning("Could not load budgets for recurring bills: %s", exc)
        budgets = []

    # 3. Sub-categories
    try:
        s_resp = (
            client.table("cost_control_sub_categories")
            .select("parent_code, sub_code, name_en, name_ar, keywords")
            .execute()
        )
        sub_categories = s_resp.data or []
    except Exception as exc:
        logger.warning("Could not load sub-categories: %s", exc)
        sub_categories = []

    return detect_recurring_bills(
        transactions=txs,
        as_of_date=now_date,
        budgets=budgets,
        sub_categories=sub_categories,
    )


def toggle_household_recurring_bill(
    household_id: str,
    category_code: str,
    sub_code: str,
    is_recurring: bool = True,
    due_day: Optional[int] = None,
    custom_name: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Toggles or customizes whether a sub-budget item appears in the Recurring Bills & Reserves card.
    Stores the configuration directly in the budget's sub_allocations JSONB.
    """
    from supabase_client import get_client
    client = get_client()
    cycle_info = get_cycle_for_date()
    cycle_key = cycle_info["cycle_key"]

    resp = (
        client.table("budgets")
        .select("id, sub_allocations")
        .eq("household_id", household_id)
        .eq("category_code", category_code)
        .execute()
    )
    matching = [
        r for r in (resp.data or [])
        if r.get("cycle_key") == cycle_key or (not r.get("cycle_key") and (r.get("month") or "")[:7] == cycle_key)
    ]

    if not matching:
        return {"status": "error", "message": f"Budget for {category_code} not found in active cycle."}

    b_id = matching[0]["id"]
    sub_allocs = matching[0].get("sub_allocations") or {}
    rec_config = sub_allocs.get("_recurring_config") or {}

    item_cfg = rec_config.get(sub_code) or {}
    item_cfg["enabled"] = is_recurring
    if due_day is not None:
        item_cfg["due_day"] = due_day
    if custom_name is not None:
        item_cfg["custom_name"] = custom_name

    rec_config[sub_code] = item_cfg
    sub_allocs["_recurring_config"] = rec_config

    client.table("budgets").update({"sub_allocations": sub_allocs}).eq("id", b_id).execute()

    return {
        "status": "success",
        "category_code": category_code,
        "sub_code": sub_code,
        "is_recurring": is_recurring,
        "due_day": item_cfg.get("due_day"),
    }


def get_recurring_bill_candidates(household_id: str) -> Dict[str, Any]:
    """
    Lists all available sub-budget items across all categories for the household,
    indicating which are currently configured or detected as recurring bills.
    """
    from supabase_client import get_client
    client = get_client()
    cycle_info = get_cycle_for_date()
    cycle_key = cycle_info["cycle_key"]

    # Load active budgets
    b_resp = (
        client.table("budgets")
        .select("id, category_code, allocated_amount, sub_allocations, cycle_key, month")
        .eq("household_id", household_id)
        .execute()
    )
    budgets = [
        b for b in (b_resp.data or [])
        if b.get("cycle_key") == cycle_key or (not b.get("cycle_key") and (b.get("month") or "")[:7] == cycle_key)
    ]

    # Load sub-category metadata
    s_resp = (
        client.table("cost_control_sub_categories")
        .select("parent_code, sub_code, name_en, name_ar")
        .execute()
    )
    sub_map = {s["sub_code"]: s for s in (s_resp.data or [])}

    candidates = []
    for b in budgets:
        cat_code = b.get("category_code") or ""
        sub_allocs = b.get("sub_allocations") or {}
        rec_config = sub_allocs.get("_recurring_config") or {}

        for sub_code, amount in sub_allocs.items():
            if str(sub_code).startswith("_"):
                continue
            amt = float(amount or 0.0)
            if amt <= 0:
                continue

            sub_def = sub_map.get(sub_code, {})
            name_en = sub_def.get("name_en") or sub_code.replace("sub-", "").replace("_", " ").title()
            name_ar = sub_def.get("name_ar") or ""

            cfg = rec_config.get(sub_code) or {}
            is_explicit = cfg.get("enabled")
            is_util = (cat_code == "OPEX-UTILITIES")
            kw_match = any(kw in sub_code.lower() or kw in name_en.lower() for kw in KNOWN_RECURRING_KEYWORDS)

            is_recurring = is_explicit if is_explicit is not None else (is_util or kw_match)
            due_day = cfg.get("due_day") or DEFAULT_DUE_DAYS.get(sub_code, 28)

            candidates.append({
                "category_code": cat_code,
                "sub_code": sub_code,
                "name_en": name_en,
                "name_ar": name_ar,
                "allocated_amount": amt,
                "is_recurring": is_recurring,
                "due_day": due_day,
                "icon_key": DEFAULT_ICONS.get(sub_code, "receipt_long"),
            })

    return {"status": "success", "candidates": candidates}
