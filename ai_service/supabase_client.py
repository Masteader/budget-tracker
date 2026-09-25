"""
Supabase database helper functions for the Budget Tracker AI microservice.
All DB operations use the SERVICE ROLE KEY — bypasses RLS intentionally.
"""

from __future__ import annotations

import logging
import os
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from supabase import create_client, Client

from models import BudgetRow, CostControlCode

logger = logging.getLogger(__name__)

# ─── Singleton client ─────────────────────────────────────────────────────────
_client: Optional[Client] = None


def get_client() -> Client:
    """Return (or lazily create) the Supabase service-role client."""
    global _client
    if _client is None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        _client = create_client(url, key)
        logger.info("Supabase client initialised (service role).")
    return _client


# =============================================================================
# COST CONTROL CODES
# =============================================================================

def fetch_all_cost_control_codes() -> list[CostControlCode]:
    """
    Load the full cost_control_codes table into memory.
    Called once at startup and cached — table rarely changes.
    """
    client = get_client()
    response = client.table("cost_control_codes").select("*").execute()
    rows = response.data or []
    logger.debug("Fetched %d cost control codes.", len(rows))
    return [CostControlCode(**row) for row in rows]


def match_category(merchant: str, codes: list[CostControlCode]) -> Optional[CostControlCode]:
    """
    Find the best-matching CostControlCode for a merchant name.
    Requires word-boundary matching for short keywords (< 4 chars) to prevent false positives (e.g. 'du' matching 'Dunkin').
    """
    import re
    merchant_lower = merchant.lower().strip()
    
    # Sort codes with longer keywords first for specificity
    for code in codes:
        for kw in sorted(code.keywords, key=len, reverse=True):
            kw_clean = kw.lower().strip()
            if not kw_clean:
                continue
            if len(kw_clean) < 4:
                # Require word boundary
                if re.search(rf"\b{re.escape(kw_clean)}\b", merchant_lower):
                    logger.debug("Merchant '%s' matched short keyword '%s' → %s", merchant, kw, code.code)
                    return code
            else:
                if kw_clean in merchant_lower or merchant_lower in kw_clean:
                    logger.debug("Merchant '%s' matched keyword '%s' → %s", merchant, kw, code.code)
                    return code
    return None


# =============================================================================
# BUDGETS
# =============================================================================

def fetch_budget(
    household_id: str,
    category_code: str,
    month: date,
) -> Optional[BudgetRow]:
    """
    Fetch the budget row for a given household + category + month.
    Returns None if no budget has been allocated yet.
    """
    client = get_client()
    month_str = month.replace(day=1).isoformat()  # always first of month

    response = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("category_code", category_code)
        .eq("month", month_str)
        .limit(1)
        .execute()
    )
    data = response.data
    if not data:
        logger.warning(
            "No budget found for household=%s category=%s month=%s",
            household_id, category_code, month_str,
        )
        return None
    return BudgetRow(**data[0])


def fetch_flexible_budgets(
    household_id: str,
    month: date,
    exclude_code: str,
) -> list[BudgetRow]:
    """
    Fetch all flexible budgets for the household in the given month,
    sorted by remaining_amount descending (most headroom first).
    Excludes the category that already overflowed.
    """
    client = get_client()
    month_str = month.replace(day=1).isoformat()

    # Get flexible category codes first
    codes_resp = (
        client.table("cost_control_codes")
        .select("code")
        .eq("is_flexible", True)
        .neq("code", exclude_code)
        .execute()
    )
    flexible_codes = [row["code"] for row in (codes_resp.data or [])]
    if not flexible_codes:
        return []

    response = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("month", month_str)
        .in_("category_code", flexible_codes)
        .gt("remaining_amount", 0)
        .order("remaining_amount", desc=True)
        .execute()
    )
    rows = response.data or []
    logger.debug("Found %d flexible budgets available for reallocation.", len(rows))
    return [BudgetRow(**r) for r in rows]


def reallocate_budget(from_budget_id: str, to_budget_id: str, amount: float) -> None:
    """
    Reallocate `amount` from a flexible budget to cover a deficit in `to_budget_id`.
    Atomically shifts `allocated_amount` between the two budgets so total household
    spend remains strictly pegged to actual transactions without phantom expenses.
    """
    client = get_client()
    try:
        client.rpc("reallocate_budget", {
            "p_from_id": from_budget_id,
            "p_to_id": to_budget_id,
            "p_amount": amount,
        }).execute()
    except Exception as exc:
        logger.warning("RPC reallocate_budget unavailable (%s), falling back to two-step update.", exc)
        from_row = client.table("budgets").select("allocated_amount").eq("id", from_budget_id).single().execute()
        to_row = client.table("budgets").select("allocated_amount").eq("id", to_budget_id).single().execute()
        client.table("budgets").update({
            "allocated_amount": from_row.data["allocated_amount"] - amount
        }).eq("id", from_budget_id).execute()
        client.table("budgets").update({
            "allocated_amount": to_row.data["allocated_amount"] + amount
        }).eq("id", to_budget_id).execute()

    logger.info("Reallocated %.2f from budget %s to %s.", amount, from_budget_id, to_budget_id)


def deduct_from_budget(budget_id: str, amount: float) -> None:
    """
    Legacy helper: Add `amount` to a budget's spent_amount.
    """
    client = get_client()
    current = client.table("budgets").select("spent_amount").eq("id", budget_id).single().execute()
    current_spent = current.data["spent_amount"]
    new_spent = current_spent + amount

    client.table("budgets").update({"spent_amount": new_spent}).eq("id", budget_id).execute()
    logger.info("Deducted %.2f from budget %s (new spent=%.2f).", amount, budget_id, new_spent)


# =============================================================================
# TRANSACTIONS
# =============================================================================

def insert_transaction(
    household_id: str,
    amount: float,
    currency: str,
    merchant: str,
    category_code: str,
    timestamp: str,
    raw_sms: str,
    is_reallocated: bool = False,
    reallocated_from_budget_id: Optional[str] = None,
    source: str = "sms",
    items: Optional[list] = None,
    receipt_url: Optional[str] = None,
) -> str:
    """
    Insert a new transaction row and return its UUID.
    The on_transaction_insert trigger automatically updates budgets.spent_amount.
    """
    client = get_client()
    payload = {
        "household_id": household_id,
        "amount": amount,
        "currency": currency,
        "merchant": merchant,
        "category_code": category_code,
        "timestamp": timestamp,
        "raw_sms": raw_sms,
        "is_reallocated": is_reallocated,
        "reallocated_from_budget_id": reallocated_from_budget_id,
        "source": source,
    }
    if items:
        payload["items"] = items
    if receipt_url:
        payload["receipt_url"] = receipt_url

    try:
        response = client.table("transactions").insert(payload).execute()
    except Exception as exc:
        logger.warning("Insert with new schema columns failed (%s), falling back to base columns.", exc)
        base_payload = {
            "household_id": household_id,
            "amount": amount,
            "currency": currency,
            "merchant": merchant,
            "category_code": category_code,
            "timestamp": timestamp,
            "raw_sms": raw_sms,
            "is_reallocated": is_reallocated,
            "reallocated_from_budget_id": reallocated_from_budget_id,
        }
        response = client.table("transactions").insert(base_payload).execute()

    transaction_id = response.data[0]["id"]
    logger.info(
        "Transaction inserted: id=%s amount=%.2f %s merchant=%s category=%s reallocated=%s source=%s",
        transaction_id, amount, currency, merchant, category_code, is_reallocated, source,
    )
    return transaction_id


def is_duplicate_sms(raw_sms: str, household_id: str, window_seconds: int = 60) -> bool:
    """
    Check if an identical SMS was already processed in the last `window_seconds`.
    Prevents double-logging if the device retransmits the same SMS.
    """
    client = get_client()
    cutoff = (datetime.now(timezone.utc) - timedelta(seconds=window_seconds)).isoformat()
    response = (
        client.table("transactions")
        .select("id")
        .eq("household_id", household_id)
        .eq("raw_sms", raw_sms)
        .gte("created_at", cutoff)
        .limit(1)
        .execute()
    )
    return bool(response.data)
